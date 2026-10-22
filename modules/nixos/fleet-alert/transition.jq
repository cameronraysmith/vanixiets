# Alert-instance transition for fleet-alert (ADR-009 items 3-7, 17, R9.1;
# design D11, D15; tasks.md 4.2).
#
# Pure: the input is the state (null or {} on a first run), and
# transition($observations; $now; $rules) returns {state, posts}; nothing
# here reads a clock, a file or the environment, except in_window, which the
# evaluator runs under TZ=<window zone>. An instance is one rule plus its
# result label set. It fires once its condition has held on every run for
# the rule's `for` (seconds) and resolves once the condition has been absent
# 300 s; a critical instance is re-posted every 24 h, a warning never, and an
# info instance posts no RESOLVED and is not counted. A database in
# $observations.storeErrors freezes every instance whose rule is on it (a
# rule or an instance without `database` is on fleet) and raises one
# StoreQueryFailing per failing database, labelled `database` and never
# frozen; `reporting` (system_memory_usage_bytes) and state.hosts come from
# RuleSignalMissing's database, and a host missing from `reporting` freezes
# the instances labelled with it (stand-up-devloop-collection review F7).
# Frozen time is not absence: absence counts from `absenceFrom`, the run the
# instance was last seen on or, after a freeze, the first unfrozen run (a
# state written before the field existed counts from `lastSeen`).
# StoreQueryFailing and RuleSignalMissing are raised only if $rules lists
# them, with their `for`. RuleSignalMissing also reports each host in its
# `alwaysOn` list that the store answered without for 10 min, counted from
# state.hosts (the last run it reported on, or the first run the state saw
# it missing), with no `for` and no host freeze (ADR-009 item 16, charter
# v20); it resolves once the host reports again. Posts carry no topic; the
# caller adds it. The caller posts in order and applies mark_posted($post)
# to the saved state
# after each successful post, so a failed post or a killed run leaves the
# difference for the next run (D15). modules/checks/fleet-alert/model.py is
# the reference model the property test compares this file with.

def resolve_after: 300;
def repost_every: 86400;
def absent_after: 600;
def budget_window: 86400;
def budget_fleet: 10;
def budget_hosts: { stibnite: 3, pyrite: 3 };

def priority_of($severity):
  { critical: "high", warning: "default", info: "low" }[$severity] // "default";

def instance_id($alert; $labels):
  [$alert, ($labels | to_entries | sort_by(.key))] | tojson;

def normalize_state:
  { instances: {}, hosts: {}, firings: [], budgetPostedAt: null, lastRun: null } + (. // {});

def title($kind; $alert; $host):
  "[\(if $kind == "resolved" then "RESOLVED" else "FIRING" end)] \($alert)"
  + (if $host == "" then "" else " \($host)" end);

def minutes_of($hhmm): ($hhmm | split(":") | map(tonumber)) as $p | $p[0] * 60 + $p[1];

# jq's localtime gives [year, month, mday, hours, minutes, seconds,
# wday (Sunday 0), yday]; $window.weekday is ISO (Monday 1); end exclusive.
def in_window($window; $now):
  ($now | localtime) as $t
  | ($t[3] * 60 + $t[4]) as $minute
  | ((if $t[6] == 0 then 7 else $t[6] end) == $window.weekday)
    and $minute >= minutes_of($window.start)
    and $minute < minutes_of($window.end);

def rule_named($rules; $name): [ $rules[] | select(.alert == $name) ] | .[0];

# A rule is evaluated from $observations.results when it has an `expr` (the
# evaluator's PromQL rules) or when results has an entry for its alert name
# (a caller's own query, such as fleet-deadman's AlertEvaluatorSilent);
# StoreQueryFailing and RuleSignalMissing come only from the logic below.
def internal_rule($alert): $alert | IN("StoreQueryFailing", "RuleSignalMissing");

def store_errors($observations): $observations.storeErrors // [];
def database_of($x): $x.database // "fleet";
def store_failed($observations; $database): any(store_errors($observations) | .[]; . == $database);
def reporting_database($rules): database_of(rule_named($rules; "RuleSignalMissing") // {});

def conditions($observations; $rules; $hosts; $now):
  ( rule_named($rules; "StoreQueryFailing") as $failing
    | if $failing == null then []
      else [ store_errors($observations) | .[] | {rule: $failing, labels: {database: .}, value: "1"} ] end )
  + [ $rules[] | . as $r
      | select(store_failed($observations; database_of($r)) | not)
      | select(has("expr")
               or ((internal_rule($r.alert) | not) and (($observations.results // {}) | has($r.alert))))
      | select(($r.window == null) or ($observations.windows[$r.alert] == true))
      | ($observations.results[$r.alert] // [])[]
      | {rule: $r, labels: (.labels | del(.__name__)), value: (.value | tostring)} ]
  + ( rule_named($rules; "RuleSignalMissing") as $missing
      | if $missing == null then [] else
          [ $rules[] | . as $r
            | select(store_failed($observations; database_of($r)) | not)
            | ($r.presence // [])[]
            | select((($observations.presence[.selector] // []) | length) == 0)
            | select(. as $p | any(($observations.reporting // [])[]; . as $h | any($p.expectedHosts[]; . == $h)))
            | {rule: $missing, labels: {rule: $r.alert, selector: .selector}, value: "0"} ]
          + ( if store_failed($observations; reporting_database($rules)) then [] else
                [ ($missing.alwaysOn // [])[] as $h
                  | select(any(($observations.reporting // [])[]; . == $h) | not)
                  | select($now - ($hosts[$h] // $now) >= absent_after)
                  | {rule: ($missing + {for: 0}), labels: {selector: "system_memory_usage_bytes", host_name: $h}, value: "0"} ]
              end )
        end );

def frozen($inst; $observations):
  if $inst.alert == "StoreQueryFailing" then false
  elif store_failed($observations; database_of($inst)) then true
  elif $inst.alert == "RuleSignalMissing" then false
  elif ($inst.labels.host_name // null) == null then false
  else (($inst.labels.host_name) as $h | any(($observations.reporting // [])[]; . == $h) | not)
  end;

def advance($inst; $cond; $now):
  if $cond != null then
    ($inst // { alert: $cond.rule.alert, labels: $cond.labels, phase: "pending",
                activeSince: $now, firingPostedAt: null, lastPostedAt: null })
    | . + { severity: $cond.rule.severity, for: $cond.rule.for,
            summary: ($cond.rule.annotations.summary // ""),
            attributed: ((($cond.rule.attribution // []) | length) > 0),
            value: $cond.value, database: $cond.rule.database, lastSeen: $now, absenceFrom: $now }
    | if .phase == "resolved" then .phase = "firing" else . end
    | if .phase == "pending" and ($now - .activeSince) >= .for then .phase = "firing" else . end
  elif $inst == null then null
  elif $inst.phase == "pending" then null
  elif $inst.phase == "firing" then
    ((if $inst | has("absenceFrom") then $inst.absenceFrom else $inst.lastSeen end) // $now) as $from
    | if ($now - $from) >= resolve_after then
        if $inst.severity == "info" or $inst.firingPostedAt == null then null
        else $inst | .phase = "resolved" end
      else $inst | .absenceFrom = $from end
  else $inst
  end;

def post_for($id; $inst; $now; $observations):
  ($inst.labels.host_name // "") as $host
  | ( if $inst.phase == "firing" and $inst.firingPostedAt == null then "firing"
      elif $inst.phase == "firing" and $inst.severity == "critical" and ($now - $inst.lastPostedAt) >= repost_every then "repost"
      elif $inst.phase == "resolved" then "resolved"
      else empty end ) as $kind
  | { title: title($kind; $inst.alert;
            if $inst.alert == "StoreQueryFailing" then ($inst.labels.database // $host) else $host end),
      priority: priority_of($inst.severity),
      message: ( [ $inst.summary,
                   (if $inst.alert == "StoreQueryFailing" then "the store did not answer queries on \($inst.labels.database // "?")" else empty end),
                   ($inst.labels | to_entries | map("\(.key)=\(.value)") | join(", ")),
                   (if $kind != "resolved" then "value \($inst.value)" else empty end),
                   (if $kind != "resolved" and $inst.attributed and $host != ""
                    then ($observations.attribution[$host] // "attribution unavailable") else empty end) ]
                 | map(select(. != "")) | join("\n") ),
      key: { kind: $kind, id: $id } };

def budget_post($state; $observations; $now):
  ( [ $state.firings[] | {key: "\(.alert) \(.host)", host} ]
    + [ ($observations.failedLog // [])[] | select(.at > $now - budget_window)
        | {key: "FAILED \(.unit) \(.host)", host} ] ) as $all
  | ($all | length) as $total
  | [ budget_hosts | to_entries[] | . as $limit
      | select(([ $all[] | select(.host == $limit.key) ] | length) > $limit.value) ] as $laptops
  | if ($total > budget_fleet or ($laptops | length) > 0)
       and ($state.budgetPostedAt == null or ($now - $state.budgetPostedAt) >= budget_window)
    then ( $all | group_by(.key) | map({key: .[0].key, count: length}) | sort_by(-.count, .key) | .[0] ) as $top
      | [ { title: "[FIRING] AlertBudgetExceeded",
            priority: "default",
            message: "\($total) FIRING posts and failure notices in 24 h exceed the alert budget (10 fleet-wide, 3 per laptop); most firings: \($top.key) (\($top.count)). Nothing is suppressed; review the threshold.",
            key: { kind: "budget", id: "AlertBudgetExceeded" } } ]
    else [] end;

def transition($observations; $now; $rules):
  normalize_state
  | .firings |= map(select(.at > $now - budget_window))
  | . as $state
  | ( conditions($observations; $rules; $state.hosts; $now)
      | map({key: instance_id(.rule.alert; .labels), value: .}) | from_entries ) as $conds
  | ( [ ($state.instances | keys[]), ($conds | keys[]) ] | unique ) as $ids
  | ( reduce $ids[] as $id ({};
        $state.instances[$id] as $inst
        | $conds[$id] as $cond
        | if frozen(($inst // {alert: $cond.rule.alert, labels: $cond.labels, database: $cond.rule.database}); $observations) then
            (if $inst == null then . else .[$id] = ($inst | .absenceFrom = null) end)
          else
            advance($inst; $cond; $now) as $next
            | if $next == null then . else .[$id] = $next end
          end) ) as $instances
  | ( $state
      | .instances = $instances
      | .lastRun = $now
      | if store_failed($observations; reporting_database($rules)) then .
        else .hosts += (reduce ($observations.reporting // [])[] as $h ({}; .[$h] = $now)) end
      | reduce ((rule_named($rules; "RuleSignalMissing") // {}).alwaysOn // [])[] as $h (.; .hosts[$h] //= $now) ) as $next
  | { state: $next,
      posts: ( [ $ids[] as $id
                 | $instances[$id] as $inst
                 | select($inst != null)
                 | select(frozen($inst; $observations) | not)
                 | post_for($id; $inst; $now; $observations) ]
               + budget_post($next; $observations; $now) ) };

def mark_posted($post):
  normalize_state
  | .lastRun as $t
  | if $post.key.kind == "firing" or $post.key.kind == "repost" then
      .instances[$post.key.id] as $inst
      | if $inst == null then .
        else .instances[$post.key.id] = ($inst | .firingPostedAt = (.firingPostedAt // $t) | .lastPostedAt = $t)
          | if $inst.severity == "info" then .
            else .firings += [ {at: $t, alert: $inst.alert, host: ($inst.labels.host_name // "")} ] end
        end
    elif $post.key.kind == "resolved" then del(.instances[$post.key.id])
    elif $post.key.kind == "budget" then .budgetPostedAt = $t
    else . end;
