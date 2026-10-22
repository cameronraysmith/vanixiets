"""Property test: transition.jq equals model.py (design D11; tasks.md 4.6).

Hypothesis generates timelines of runs: the time step, the databases whose
queries failed (storeErrors, over fleet and devloop), the hosts reporting
system_memory_usage_bytes, each rule's firing hosts, and the index of the
first post that fails in that run (the posts before it succeed, as the
evaluator posts in order and stops at a failure). One jq process folds each
whole timeline through transition and mark_posted; the model does the same;
posts and state must be equal at every run. Further properties, written
from the timeline alone, hold both to posting a RESOLVED only after 5 min
of absence observed while not frozen, to leaving fleet's posts unchanged by
a devloop failure, and to one StoreQueryFailing per failing database
(stand-up-devloop-collection review F7). The test is derandomized, with no
example database and no deadline, so it is a pure function of its source
and cannot flake the merge queue.
FLEET_ALERT_JQ_LIB names a directory holding transition.jq.
"""

import json
import os
import subprocess

from hypothesis import HealthCheck, given, settings
from hypothesis import strategies as st

import model

JQ_LIB = os.environ["FLEET_ALERT_JQ_LIB"]
HOSTS = ["magnetite", "stibnite"]
T0 = 1793102400


DATABASES = ["fleet", "devloop"]


def rule(alert, seconds, severity, database="fleet"):
    return {
        "alert": alert,
        "database": database,
        "expr": alert.lower(),
        "for": seconds,
        "severity": severity,
        "annotations": {"summary": alert},
        "presence": [],
        "attribution": [],
    }


# Crit, Warn and Info on fleet, Dev on devloop; StoreQueryFailing has no
# database of its own, as in rules.nix.
RULES = [
    rule("Crit", 0, "critical"),
    rule("Warn", 120, "warning"),
    rule("Info", 0, "info"),
    rule("Dev", 60, "critical", "devloop"),
    {
        "alert": "StoreQueryFailing",
        "for": 180,
        "severity": "critical",
        "annotations": {"summary": "store"},
        "presence": [],
        "attribution": [],
    },
]
RULE_NAMES = ["Crit", "Warn", "Info", "Dev"]
FLEET_RULE_NAMES = ["Crit", "Warn", "Info"]
RULE_DATABASE = {r["alert"]: r["database"] for r in RULES if "database" in r}

DRIVER = r"""
include "transition";
. as $timeline
| reduce $timeline.steps[] as $s ({state: null, posts: []};
    (.state | transition($s.observations; $s.now; $timeline.rules)) as $r
    | .posts += [$r.posts | map({title, priority, kind: .key.kind, id: .key.id})]
    | .state = (reduce ($r.posts | if $s.failAt == null then . else .[:$s.failAt] end)[] as $p
                ($r.state; mark_posted($p))))
"""

INSTANCE_FIELDS = (
    "alert",
    "labels",
    "phase",
    "severity",
    "for",
    "activeSince",
    "lastSeen",
    "absenceFrom",
    "firingPostedAt",
    "lastPostedAt",
)


def project(state):
    state = model.normalize(state)
    return {
        "instances": {
            iid: {field: instance.get(field) for field in INSTANCE_FIELDS}
            for iid, instance in state["instances"].items()
        },
        "hosts": state["hosts"],
        "firings": state["firings"],
        "budgetPostedAt": state["budgetPostedAt"],
        "lastRun": state["lastRun"],
    }


def build(steps):
    now = T0
    built = []
    for step in steps:
        now += step["dt"]
        built.append(
            {
                "now": now,
                "failAt": step["failAt"],
                "observations": {
                    "storeErrors": step["storeErrors"],
                    "reporting": step["reporting"],
                    "presence": {},
                    "results": {
                        alert: [{"labels": {"host_name": host}, "value": "1"} for host in hosts]
                        for alert, hosts in step["results"].items()
                    },
                    "failedLog": [],
                },
            }
        )
    return {"rules": RULES, "steps": built}


def run_jq(timeline):
    done = subprocess.run(
        ["jq", "-c", "-L", JQ_LIB, DRIVER],
        input=json.dumps(timeline),
        capture_output=True,
        text=True,
        check=True,
    )
    result = json.loads(done.stdout)
    return {"posts": result["posts"], "state": project(result["state"])}


def run_model(timeline):
    state = None
    posts = []
    for step in timeline["steps"]:
        state, planned = model.transition(state, step["observations"], step["now"], timeline["rules"])
        posts.append(
            [
                {"title": p["title"], "priority": p["priority"], "kind": p["key"]["kind"], "id": p["key"]["id"]}
                for p in planned
            ]
        )
        succeeded = planned if step["failAt"] is None else planned[: step["failAt"]]
        for post in succeeded:
            state = model.mark_posted(state, post)
    return {"posts": posts, "state": project(state)}


step_strategy = st.fixed_dictionaries(
    {
        "dt": st.sampled_from([60, 60, 60, 120, 300, 900, 3600, 86400]),
        "storeErrors": st.sampled_from([[], [], [], [], ["devloop"], ["fleet"], ["devloop", "fleet"]]),
        "reporting": st.sampled_from([HOSTS, HOSTS, HOSTS, ["magnetite"], ["stibnite"], []]),
        "results": st.fixed_dictionaries(
            {name: st.lists(st.sampled_from(HOSTS), unique=True) for name in RULE_NAMES}
        ),
        "failAt": st.one_of(st.none(), st.integers(min_value=0, max_value=3)),
    }
)


@settings(
    derandomize=True,
    database=None,
    deadline=None,
    max_examples=200,
    print_blob=False,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)
@given(st.lists(step_strategy, min_size=1, max_size=40))
def test_transition_matches_model(steps):
    timeline = build(steps)
    expected = run_model(timeline)
    actual = run_jq(timeline)
    for index, (want, got) in enumerate(zip(expected["posts"], actual["posts"])):
        assert want == got, f"run {index}: model posts {want}, transition.jq posts {got}"
    assert expected["state"] == actual["state"], (
        f"final state differs:\nmodel {json.dumps(expected['state'], sort_keys=True)}\n"
        f"jq    {json.dumps(actual['state'], sort_keys=True)}"
    )


def without_expr(timeline):
    """The same timeline with every non-internal rule's `expr` removed."""
    rules = [{k: v for k, v in r.items() if k != "expr"} for r in timeline["rules"]]
    return {"rules": rules, "steps": timeline["steps"]}


# A rule with no `expr` whose alert has a results entry (the dead-man's
# AlertEvaluatorSilent) is evaluated exactly as the same rule with an `expr`:
# the generated results always hold an entry for each of RULE_NAMES.
@settings(
    derandomize=True,
    database=None,
    deadline=None,
    max_examples=100,
    print_blob=False,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)
@given(st.lists(step_strategy, min_size=1, max_size=40))
def test_rule_without_expr_matches_rule_with_expr(steps):
    timeline = build(steps)
    stripped = without_expr(timeline)
    assert run_jq(stripped) == run_jq(timeline), "transition.jq: a rule without expr differs from its expr twin"
    assert run_model(stripped) == run_model(timeline), "model: a rule without expr differs from its expr twin"


# A rule with no `expr` and no results entry produces nothing, and results
# entries named StoreQueryFailing or RuleSignalMissing are never read.
def test_rule_without_expr_or_results_is_silent():
    silent = {k: v for k, v in rule("Silent", 0, "critical").items() if k != "expr"}
    missing = {
        "alert": "RuleSignalMissing",
        "for": 0,
        "severity": "warning",
        "annotations": {"summary": "missing"},
        "presence": [],
        "attribution": [],
    }
    series = [{"labels": {"host_name": "magnetite"}, "value": "1"}]
    steps = []
    for n, results in enumerate(
        [{}, {"Other": series}, {"StoreQueryFailing": series, "RuleSignalMissing": series}, {}] * 2
    ):
        steps.append(
            {
                "now": T0 + 300 * (n + 1),
                "failAt": None,
                "observations": {
                    "storeErrors": [],
                    "reporting": HOSTS,
                    "presence": {},
                    "results": results,
                    "failedLog": [],
                },
            }
        )
    timeline = {"rules": [silent, model.rule_named(RULES, "StoreQueryFailing"), missing], "steps": steps}
    for name, got in (("transition.jq", run_jq(timeline)), ("model", run_model(timeline))):
        assert all(posts == [] for posts in got["posts"]), f"{name}: posts {got['posts']}"
        assert got["state"]["instances"] == {}, f"{name}: instances {got['state']['instances']}"


def unobserved_resolves(timeline, posts):
    """The RESOLVED posts not preceded by RESOLVE_AFTER seconds of observed absence.

    Written from the timeline alone (design D11, D15; review F7): an instance
    is frozen on a run when its rule's database is in storeErrors or its host
    does not report (StoreQueryFailing never), seen when unfrozen and in the
    results, and absent otherwise; StoreQueryFailing for a database is seen
    exactly when that database failed.
    Absence counts from the run it was last seen on or, after a freeze, from
    the first unfrozen run; a RESOLVED is due once that count reaches
    RESOLVE_AFTER, and stays due, across later freezes, until it is seen.
    """
    candidates = {
        model.instance_id("StoreQueryFailing", {"database": database}): ("StoreQueryFailing", None, database)
        for database in DATABASES
    }
    for alert in RULE_NAMES:
        for host in HOSTS:
            candidates[model.instance_id(alert, {"host_name": host})] = (alert, host, RULE_DATABASE[alert])
    since = dict.fromkeys(candidates)
    due = dict.fromkeys(candidates, False)
    found = []
    for index, (step, planned) in enumerate(zip(timeline["steps"], posts)):
        observations, now = step["observations"], step["now"]
        errors = observations["storeErrors"]
        for iid, (alert, host, database) in candidates.items():
            if alert == "StoreQueryFailing":
                frozen, seen = False, database in errors
            else:
                frozen = database in errors or host not in observations["reporting"]
                seen = not frozen and host in [
                    s["labels"]["host_name"] for s in observations["results"][alert]
                ]
            if frozen:
                since[iid] = None
            elif seen:
                since[iid], due[iid] = now, False
            else:
                if since[iid] is None:
                    since[iid] = now
                if now - since[iid] >= model.RESOLVE_AFTER:
                    due[iid] = True
        found += [
            f"run {index}: {post['title']}" for post in planned if post["kind"] == "resolved" and not due[post["id"]]
        ]
    return found


# Frozen time is not absence: a RESOLVED is posted only after RESOLVE_AFTER
# seconds of absence observed while neither the store nor the instance's
# host is frozen, in transition.jq and in the model alike.
@settings(
    derandomize=True,
    database=None,
    deadline=None,
    max_examples=200,
    print_blob=False,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)
@given(st.lists(step_strategy, min_size=1, max_size=40))
def test_resolve_follows_unfrozen_absence(steps):
    timeline = build(steps)
    found = {
        name: unobserved_resolves(timeline, run(timeline)["posts"])
        for name, run in (("transition.jq", run_jq), ("model", run_model))
    }
    assert not any(found.values()), "RESOLVED before 5 min of unfrozen absence: " + "; ".join(
        f"{name}: {', '.join(runs)}" for name, runs in found.items() if runs
    )


def every_post_succeeds(timeline):
    """The timeline with no failed post, so removing one database's posts cannot shift another's."""
    return {"rules": timeline["rules"], "steps": [dict(step, failAt=None) for step in timeline["steps"]]}


def without_devloop_failures(timeline):
    """The same timeline with devloop removed from every run's storeErrors."""
    steps = []
    for step in timeline["steps"]:
        errors = [database for database in step["observations"]["storeErrors"] if database != "devloop"]
        steps.append(dict(step, observations=dict(step["observations"], storeErrors=errors)))
    return {"rules": timeline["rules"], "steps": steps}


def on_fleet(post):
    alert, entries = json.loads(post["id"])
    return alert in FLEET_RULE_NAMES or (
        alert == "StoreQueryFailing" and entries == [{"key": "database", "value": "fleet"}]
    )


def fleet_posts(result):
    return [[post for post in run if post["kind"] != "budget" and on_fleet(post)] for run in result["posts"]]


# A devloop failure leaves every fleet instance as it is without it (review
# F7): fleet's posts, StoreQueryFailing for fleet among them, are those of
# the same timeline with devloop removed from every run's storeErrors.
@settings(
    derandomize=True,
    database=None,
    deadline=None,
    max_examples=200,
    print_blob=False,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)
@given(st.lists(step_strategy, min_size=1, max_size=40))
def test_failure_freezes_only_its_database(steps):
    timeline = every_post_succeeds(build(steps))
    twin = without_devloop_failures(timeline)
    for name, run in (("transition.jq", run_jq), ("model", run_model)):
        assert fleet_posts(run(timeline)) == fleet_posts(run(twin)), f"{name}: a devloop failure changed fleet's posts"


# StoreQueryFailing is one instance per failing database, labelled with it,
# and its title names that database.
@settings(
    derandomize=True,
    database=None,
    deadline=None,
    max_examples=200,
    print_blob=False,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)
@given(st.lists(step_strategy, min_size=1, max_size=40))
def test_store_query_failing_is_keyed_by_database(steps):
    timeline = build(steps)
    allowed = {model.instance_id("StoreQueryFailing", {"database": database}) for database in DATABASES}
    for name, run in (("transition.jq", run_jq), ("model", run_model)):
        got = run(timeline)
        failing = [
            post
            for posts in got["posts"]
            for post in posts
            if post["kind"] != "budget" and json.loads(post["id"])[0] == "StoreQueryFailing"
        ]
        ids = {post["id"] for post in failing}
        ids |= {iid for iid, inst in got["state"]["instances"].items() if inst["alert"] == "StoreQueryFailing"}
        assert ids <= allowed, f"{name}: StoreQueryFailing instances {sorted(ids - allowed)}"
        titles = [
            post["title"]
            for post in failing
            if not post["title"].endswith(" StoreQueryFailing " + json.loads(post["id"])[1][0]["value"])
        ]
        assert not titles, f"{name}: StoreQueryFailing titles without their database {titles}"


if __name__ == "__main__":
    test_transition_matches_model()
    print("ok: transition.jq equals the reference model on every generated timeline")
    test_rule_without_expr_matches_rule_with_expr()
    print("ok: a rule without expr but with a results entry fires and resolves as its expr twin")
    test_rule_without_expr_or_results_is_silent()
    print("ok: a rule without expr or results entry, and results named for internal rules, produce nothing")
    test_resolve_follows_unfrozen_absence()
    print("ok: a RESOLVED follows 5 min of absence observed while neither the store nor the host is frozen")
    test_failure_freezes_only_its_database()
    print("ok: a devloop failure leaves fleet's posts as they are without it")
    test_store_query_failing_is_keyed_by_database()
    print("ok: StoreQueryFailing is one instance per failing database, labelled and titled with it")
