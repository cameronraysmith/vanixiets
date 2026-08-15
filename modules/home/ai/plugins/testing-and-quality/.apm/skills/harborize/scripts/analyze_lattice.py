#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Aggregate rewards into E(C) per cell with paired first and second differences.

Input: results.json = [{"condition": "a+b", "cell": "...", "task": "...",
                       "trial": 0, "reward": 1.0}, ...]
Produce it with scripts/collect_rewards.py; extra keys are carried through the
collector and ignored here.

Interval branch (invariant 5 reads E as a map into [0,1], so the estimator has
to match the reward's own type): the reward type is read off the data, per
task, because it is a property of that task's verifier. A task whose observed
rewards all lie in {0, 1} is binary and gets a Wilson interval; any other value
in [0, 1] makes the task graded and it gets a bootstrap percentile interval on
the mean, resampling tasks. A cell mixing binary and graded tasks is refused:
pooling a pass rate with a partial-credit mean is a category error, not a
wider interval. Values outside [0, 1] are refused for the same reason.

The bootstrap resamples tasks as clusters, so it needs at least two distinct
tasks to have anything to resample. Below that every replicate is the same
sample and the percentile interval collapses to a point. A design carrying one
task per cell is refused an interval and reports its point estimate alone,
rather than printing a zero-width interval that reads as certainty. Phase 1
proposes 1-3 tasks per unit, so a single-task cell is an ordinary case and this
is a degradation rather than an error.

Coupling (invariant 4) is enforced here rather than assumed. Every contrast
intersects the (task, trial) keys of its arms and reports how many keys each
arm contributed and how many were dropped, so the review gate can be evidenced
from this output. Neither Harbor nor BenchFlow exposes a per-trial seed at the
revisions this skill pins, so the coupling is exact at the task level and
positional within a task: trial ordinals are assigned by the collector and
align replicate k with replicate k across conditions.

Exit codes:
    0   analysis ran
    1   --strict-pairing was requested and a contrast dropped keys
    2   input refused: malformed rows, mixed reward types, out-of-range rewards
"""

import argparse
import collections
import itertools
import json
import math
import pathlib
import random
import statistics as st
import sys

ROW_KEYS = ("condition", "cell", "task", "trial", "reward")
EMPTY_CONDITION = "none"
MIN_BOOTSTRAP_TASKS = 2
ADDITIVE_TOLERANCE = 1e-9
NO_INTERVAL = f"[no interval: needs >= {MIN_BOOTSTRAP_TASKS} tasks]"


class InputError(Exception):
    """The results file cannot be analyzed as given."""


def load_rows(path):
    try:
        rows = json.loads(pathlib.Path(path).read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise InputError(f"cannot read {path}: {exc}") from exc
    if not isinstance(rows, list) or not rows:
        raise InputError(f"{path} is not a non-empty JSON list of result rows")
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise InputError(f"row {index} is not an object")
        missing = [key for key in ROW_KEYS if key not in row]
        if missing:
            raise InputError(f"row {index} is missing {', '.join(missing)}")
        if not isinstance(row["reward"], (int, float)) or isinstance(
            row["reward"], bool
        ):
            raise InputError(f"row {index} has a non-numeric reward")
    return rows


def classify_rewards(values):
    for value in values:
        if not 0.0 <= value <= 1.0:
            raise InputError(
                f"reward {value} lies outside [0, 1]; E is a map into [0, 1] "
                "and neither estimator is defined off it"
            )
    return "binary" if all(value in (0.0, 1.0) for value in values) else "graded"


def cell_reward_type(cell_rows):
    """Reward type for a cell, refusing a cell whose tasks disagree."""
    by_task = collections.defaultdict(list)
    for row in cell_rows:
        by_task[row["task"]].append(float(row["reward"]))
    per_task = {task: classify_rewards(values) for task, values in by_task.items()}
    types = set(per_task.values())
    if len(types) > 1:
        binary = sorted(t for t, kind in per_task.items() if kind == "binary")
        graded = sorted(t for t, kind in per_task.items() if kind == "graded")
        raise InputError(
            "cell mixes reward types across tasks; analyze them separately. "
            f"binary: {', '.join(binary)}. graded: {', '.join(graded)}"
        )
    return types.pop()


def wilson(k, n, z=1.96):
    if n == 0:
        return 0.0, 0.0, 1.0
    p = k / n
    d = 1 + z * z / n
    center = (p + z * z / (2 * n)) / d
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return p, max(0.0, center - half), min(1.0, center + half)


def bootstrap_percentile_ci(values, task_keys, iters, seed):
    """Percentile interval on the mean, resampling tasks with replacement.

    Tasks are the exchangeable unit; trials within a task are correlated, so
    the cluster is the task and every one of its values travels together.

    Returns (nan, nan) below MIN_BOOTSTRAP_TASKS distinct tasks, where every
    replicate would be the same sample and the interval would be a point.
    """
    by_task = collections.defaultdict(list)
    for value, task in zip(values, task_keys):
        by_task[task].append(value)
    tasks = sorted(by_task)
    if len(tasks) < MIN_BOOTSTRAP_TASKS:
        return float("nan"), float("nan")
    rng = random.Random(seed)
    means = []
    for _ in range(iters):
        sample = [
            value
            for task in rng.choices(tasks, k=len(tasks))
            for value in by_task[task]
        ]
        means.append(st.mean(sample))
    means.sort()
    lo = means[min(int(0.025 * iters), iters - 1)]
    hi = means[min(int(0.975 * iters), iters - 1)]
    return lo, hi


def format_interval(lo, hi, sign=""):
    if math.isnan(lo) or math.isnan(hi):
        return NO_INTERVAL
    return f"[{lo:{sign}.3f},{hi:{sign}.3f}]"


def condition_estimate(rows, reward_type, iters, seed):
    values = [float(row["reward"]) for row in rows]
    tasks = [row["task"] for row in rows]
    if reward_type == "binary":
        successes = sum(1 for value in values if value == 1.0)
        point, lo, hi = wilson(successes, len(values))
        return point, lo, hi, "wilson"
    point = st.mean(values)
    lo, hi = bootstrap_percentile_ci(values, tasks, iters, seed)
    return point, lo, hi, "bootstrap"


def keyed(rows, condition):
    return {
        (row["task"], row["trial"]): float(row["reward"])
        for row in rows
        if row["condition"] == condition
    }


def couple(rows, conditions):
    """Intersect the (task, trial) keys of several conditions.

    This is the operational form of invariant 4: a contrast is only ever taken
    over keys every arm carries. The returned record is the evidence the review
    gate cites, so it is emitted whether or not anything was dropped.
    """
    arms = {condition: keyed(rows, condition) for condition in conditions}
    shared = set.intersection(*(set(arm) for arm in arms.values())) if arms else set()
    keys = sorted(shared)
    record = {
        "conditions": list(conditions),
        "n_shared": len(keys),
        "n_by_arm": {condition: len(arm) for condition, arm in arms.items()},
        "n_dropped_by_arm": {
            condition: len(arm) - len(keys) for condition, arm in arms.items()
        },
    }
    return arms, keys, record


def format_coupling(record):
    parts = [
        f"{condition or EMPTY_CONDITION}:{record['n_by_arm'][condition]}"
        f"-{record['n_dropped_by_arm'][condition]}"
        for condition in record["conditions"]
    ]
    return f"paired n={record['n_shared']} (arm:n-dropped {' '.join(parts)})"


def analyze_cell(cell, cell_rows, units, args, dropped_flag):
    reward_type = cell_reward_type(cell_rows)
    n_tasks = len({row["task"] for row in cell_rows})
    print(f"\n== {cell} == reward-type={reward_type} tasks={n_tasks}")
    if n_tasks < MIN_BOOTSTRAP_TASKS:
        print(
            f"  note: {n_tasks} task in this cell, so every bootstrap "
            "interval is suppressed; point estimates only"
        )

    for condition in sorted({row["condition"] for row in cell_rows}):
        rows = [row for row in cell_rows if row["condition"] == condition]
        point, lo, hi, estimator = condition_estimate(
            rows, reward_type, args.bootstrap_iters, args.bootstrap_seed
        )
        label = condition or EMPTY_CONDITION
        print(
            f"  E({label:<20}) = {point:.3f} {format_interval(lo, hi)} "
            f"n={len(rows)} ({estimator})"
        )

    for unit in units:
        arms, keys, record = couple(cell_rows, [unit, EMPTY_CONDITION])
        if not keys:
            print(f"  D({unit}) unavailable: {format_coupling(record)}")
            continue
        if any(record["n_dropped_by_arm"].values()):
            dropped_flag.append((cell, record))
        diffs = [arms[unit][key] - arms[EMPTY_CONDITION][key] for key in keys]
        tasks = [key[0] for key in keys]
        lo, hi = bootstrap_percentile_ci(
            diffs, tasks, args.bootstrap_iters, args.bootstrap_seed
        )
        base = st.mean([arms[EMPTY_CONDITION][key] for key in keys])
        gain = (
            f" norm-gain={st.mean(diffs) / (1 - base):.2f}" if base < 1.0 else ""
        )
        print(
            f"  D({unit}) = {st.mean(diffs):+.3f} "
            f"{format_interval(lo, hi, '+')}{gain}  "
            f"{format_coupling(record)}"
        )

    present = {row["condition"] for row in cell_rows}
    for left, right in itertools.combinations(units, 2):
        pair = "+".join(sorted([left, right]))
        quad = [pair, left, right, EMPTY_CONDITION]
        if not set(quad) <= present:
            continue
        arms, keys, record = couple(cell_rows, quad)
        if not keys:
            continue
        if any(record["n_dropped_by_arm"].values()):
            dropped_flag.append((cell, record))
        seconds = [
            arms[pair][key]
            - arms[left][key]
            - arms[right][key]
            + arms[EMPTY_CONDITION][key]
            for key in keys
        ]
        tasks = [key[0] for key in keys]
        lo, hi = bootstrap_percentile_ci(
            seconds, tasks, args.bootstrap_iters, args.bootstrap_seed
        )
        point = st.mean(seconds)
        if abs(point) <= ADDITIVE_TOLERANCE:
            tag = "additive"
        else:
            tag = "synergy" if point > 0 else "interference"
        print(
            f"  D2({left},{right}) = {point:+.3f} "
            f"{format_interval(lo, hi, '+')} ({tag})  "
            f"{format_coupling(record)}"
        )


def build_parser():
    parser = argparse.ArgumentParser(
        description="Aggregate condition-lattice rewards into E(C) and contrasts.",
        epilog="Exit codes: 0 analysis ran, 1 strict pairing violated, "
        "2 input refused.",
    )
    parser.add_argument("results", help="results.json from collect_rewards.py")
    parser.add_argument(
        "--units", nargs="+", required=True, help="ablation unit names"
    )
    parser.add_argument("--bootstrap-iters", type=int, default=2000)
    parser.add_argument("--bootstrap-seed", type=int, default=0)
    parser.add_argument(
        "--strict-pairing",
        action="store_true",
        help="exit 1 if any contrast dropped an unpaired (task, trial) key",
    )
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        rows = load_rows(args.results)
    except InputError as exc:
        print(f"analyze_lattice: {exc}", file=sys.stderr)
        return 2

    conditions = {row["condition"] for row in rows}
    for unit in args.units:
        if unit not in conditions:
            print(
                f"analyze_lattice: unit {unit!r} appears in no condition; "
                f"observed conditions: {', '.join(sorted(conditions))}",
                file=sys.stderr,
            )

    dropped_flag = []
    for cell in sorted({row["cell"] for row in rows}):
        cell_rows = [row for row in rows if row["cell"] == cell]
        try:
            analyze_cell(cell, cell_rows, args.units, args, dropped_flag)
        except InputError as exc:
            print(f"analyze_lattice: cell {cell}: {exc}", file=sys.stderr)
            return 2

    if dropped_flag:
        print("\nunpaired keys dropped (invariant 4 evidence):")
        for cell, record in dropped_flag:
            print(f"  {cell}: {format_coupling(record)}")
        if args.strict_pairing:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
