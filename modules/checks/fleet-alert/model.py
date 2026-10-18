"""Reference model of fleet-alert's instance transition (design D11).

checks.x86_64-linux.fleet-alert's property test compares this model with
modules/nixos/fleet-alert/transition.jq over generated timelines: posts
(title, priority, kind, instance id) and state. It is written from the
specification, not translated from the jq: Prometheus `for` over instances
of a rule plus its result label set; resolve after 5 min absent, where
frozen time is not absence (after a freeze the count restarts at the first
unfrozen run); a `critical` instance re-posted every 24 h, a `warning`
never, an `info` with no RESOLVED and not counted; a store error freezes
every instance but StoreQueryFailing; a host without
system_memory_usage_bytes freezes its instances; RuleSignalMissing per
presence selector while an expected host reports; R9.1's 24 h count over
posted FIRINGs and failed.log with one AlertBudgetExceeded per 24 h.
Messages are not modelled.
"""

import copy
import json

RESOLVE_AFTER = 300
REPOST_EVERY = 86400
BUDGET_WINDOW = 86400
BUDGET_FLEET = 10
BUDGET_HOSTS = {"stibnite": 3, "pyrite": 3}
PRIORITY = {"critical": "high", "warning": "default", "info": "low"}


def instance_id(alert, labels):
    entries = [{"key": key, "value": labels[key]} for key in sorted(labels)]
    return json.dumps([alert, entries], separators=(",", ":"), ensure_ascii=False)


def normalize(state):
    base = {"instances": {}, "hosts": {}, "firings": [], "budgetPostedAt": None, "lastRun": None}
    base.update(copy.deepcopy(state or {}))
    return base


def rule_named(rules, name):
    return next((rule for rule in rules if rule["alert"] == name), None)


# Raised only by the logic below, never from results.
INTERNAL = ("StoreQueryFailing", "RuleSignalMissing")


def conditions(observations, rules):
    if observations["storeError"]:
        rule = rule_named(rules, "StoreQueryFailing")
        return [] if rule is None else [(rule, {}, "1")]
    found = []
    windows = observations.get("windows") or {}
    results = observations.get("results") or {}
    for rule in rules:
        # A rule with an `expr`, or one whose alert has a results entry (a
        # caller's own query, such as the dead-man's AlertEvaluatorSilent).
        if "expr" not in rule and (rule["alert"] in INTERNAL or rule["alert"] not in results):
            continue
        if rule.get("window") is not None and windows.get(rule["alert"]) is not True:
            continue
        for series in results.get(rule["alert"]) or []:
            labels = {k: v for k, v in series["labels"].items() if k != "__name__"}
            found.append((rule, labels, str(series["value"])))
    missing = rule_named(rules, "RuleSignalMissing")
    if missing is not None:
        reporting = observations.get("reporting") or []
        presence = observations.get("presence") or {}
        for rule in rules:
            for selector in rule.get("presence") or []:
                if presence.get(selector["selector"]):
                    continue
                if any(host in reporting for host in selector["expectedHosts"]):
                    found.append((missing, {"rule": rule["alert"], "selector": selector["selector"]}, "0"))
    return found


def frozen(alert, labels, observations):
    if alert == "StoreQueryFailing":
        return False
    if observations["storeError"]:
        return True
    host = labels.get("host_name")
    if host is None:
        return False
    return host not in (observations.get("reporting") or [])


def advance(instance, condition, now):
    if condition is not None:
        rule, labels, _value = condition
        if instance is None:
            nxt = {
                "alert": rule["alert"],
                "labels": labels,
                "phase": "pending",
                "activeSince": now,
                "firingPostedAt": None,
                "lastPostedAt": None,
            }
        else:
            nxt = copy.deepcopy(instance)
        nxt.update({"severity": rule["severity"], "for": rule["for"], "lastSeen": now, "absenceFrom": now})
        if nxt["phase"] == "resolved":
            nxt["phase"] = "firing"
        if nxt["phase"] == "pending" and now - nxt["activeSince"] >= nxt["for"]:
            nxt["phase"] = "firing"
        return nxt
    if instance is None or instance["phase"] == "pending":
        return None
    if instance["phase"] == "firing":
        since = instance.get("absenceFrom", instance["lastSeen"])
        if since is None:
            since = now
        if now - since >= RESOLVE_AFTER:
            if instance["severity"] == "info" or instance["firingPostedAt"] is None:
                return None
            nxt = copy.deepcopy(instance)
            nxt["phase"] = "resolved"
            return nxt
        return dict(instance, absenceFrom=since)
    return instance


def post_kind(instance, now):
    if instance["phase"] == "firing" and instance["firingPostedAt"] is None:
        return "firing"
    if (
        instance["phase"] == "firing"
        and instance["severity"] == "critical"
        and now - instance["lastPostedAt"] >= REPOST_EVERY
    ):
        return "repost"
    if instance["phase"] == "resolved":
        return "resolved"
    return None


def title(kind, alert, host):
    word = "RESOLVED" if kind == "resolved" else "FIRING"
    return f"[{word}] {alert}" + (f" {host}" if host else "")


def budget_post(state, observations, now):
    entries = [(f'{f["alert"]} {f["host"]}', f["host"]) for f in state["firings"]]
    entries += [
        (f'FAILED {f["unit"]} {f["host"]}', f["host"])
        for f in observations.get("failedLog") or []
        if f["at"] > now - BUDGET_WINDOW
    ]
    laptops = [
        host for host, limit in BUDGET_HOSTS.items() if sum(1 for _, h in entries if h == host) > limit
    ]
    due = state["budgetPostedAt"] is None or now - state["budgetPostedAt"] >= BUDGET_WINDOW
    if (len(entries) > BUDGET_FLEET or laptops) and due:
        return [
            {
                "title": "[FIRING] AlertBudgetExceeded",
                "priority": "default",
                "key": {"kind": "budget", "id": "AlertBudgetExceeded"},
            }
        ]
    return []


def transition(state, observations, now, rules):
    state = normalize(state)
    state["firings"] = [f for f in state["firings"] if f["at"] > now - BUDGET_WINDOW]
    conds = {}
    for rule, labels, value in conditions(observations, rules):
        conds[instance_id(rule["alert"], labels)] = (rule, labels, value)
    ids = sorted(set(state["instances"]) | set(conds))
    instances = {}
    for iid in ids:
        instance = state["instances"].get(iid)
        condition = conds.get(iid)
        if instance is not None:
            alert, labels = instance["alert"], instance["labels"]
        else:
            alert, labels = condition[0]["alert"], condition[1]
        if frozen(alert, labels, observations):
            if instance is not None:
                instances[iid] = dict(instance, absenceFrom=None)
            continue
        nxt = advance(instance, condition, now)
        if nxt is not None:
            instances[iid] = nxt
    state["instances"] = instances
    state["lastRun"] = now
    if not observations["storeError"]:
        for host in observations.get("reporting") or []:
            state["hosts"][host] = now
    posts = []
    for iid in ids:
        instance = instances.get(iid)
        if instance is None or frozen(instance["alert"], instance["labels"], observations):
            continue
        kind = post_kind(instance, now)
        if kind is not None:
            posts.append(
                {
                    "title": title(kind, instance["alert"], instance["labels"].get("host_name") or ""),
                    "priority": PRIORITY.get(instance["severity"], "default"),
                    "key": {"kind": kind, "id": iid},
                }
            )
    return state, posts + budget_post(state, observations, now)


def mark_posted(state, post):
    state = normalize(state)
    at = state["lastRun"]
    kind, iid = post["key"]["kind"], post["key"]["id"]
    if kind in ("firing", "repost"):
        instance = state["instances"].get(iid)
        if instance is not None:
            if instance["firingPostedAt"] is None:
                instance["firingPostedAt"] = at
            instance["lastPostedAt"] = at
            if instance["severity"] != "info":
                state["firings"].append(
                    {"at": at, "alert": instance["alert"], "host": instance["labels"].get("host_name") or ""}
                )
    elif kind == "resolved":
        state["instances"].pop(iid, None)
    elif kind == "budget":
        state["budgetPostedAt"] = at
    return state
