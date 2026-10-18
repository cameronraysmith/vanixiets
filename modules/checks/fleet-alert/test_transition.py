"""Property test: transition.jq equals model.py (design D11; tasks.md 4.6).

Hypothesis generates timelines of runs: the time step, a store error, the
hosts reporting system_memory_usage_bytes, each rule's firing hosts, and the
index of the first post that fails in that run (the posts before it
succeed, as the evaluator posts in order and stops at a failure). One jq
process folds each whole timeline through transition and mark_posted; the
model does the same; posts and state must be equal at every run. The test
is derandomized, with no example database and no deadline, so it is a pure
function of its source and cannot flake the merge queue.
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


def rule(alert, seconds, severity):
    return {
        "alert": alert,
        "expr": alert.lower(),
        "for": seconds,
        "severity": severity,
        "annotations": {"summary": alert},
        "presence": [],
        "attribution": [],
    }


RULES = [
    rule("Crit", 0, "critical"),
    rule("Warn", 120, "warning"),
    rule("Info", 0, "info"),
    {
        "alert": "StoreQueryFailing",
        "for": 180,
        "severity": "critical",
        "annotations": {"summary": "store"},
        "presence": [],
        "attribution": [],
    },
]
RULE_NAMES = ["Crit", "Warn", "Info"]

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
                    "storeError": step["storeError"],
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
        "storeError": st.sampled_from([False, False, False, False, True]),
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


if __name__ == "__main__":
    test_transition_matches_model()
    print("ok: transition.jq equals the reference model on every generated timeline")
