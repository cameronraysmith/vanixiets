#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Collect Harbor and BenchFlow run output into the results.json analyze_lattice reads.

Bridges the gap between running design/manifest.sh and feeding
scripts/analyze_lattice.py. Emits a JSON list of
{condition, cell, task, trial, reward} rows plus provenance fields the analyzer
ignores.

Files and fields parsed, at the pinned revisions recorded below:

Harbor (ac398bbda7c4c1073461797d3b95c2455cc671b5)
    <harbor-jobs>/<cell>__<condition>/<trial-name>/result.json
    is a serialized TrialResult (src/harbor/models/trial/result.py). Read
    task_name, trial_name, started_at, verifier_result.rewards
    (dict[str, float | int] | None, src/harbor/models/verifier/result.py) and
    exception_info. Trial directories are the job directory's immediate
    subdirectories (src/harbor/job.py:252 iterates them the same way); the
    job's own result.json is a JobResult and is not read.

    The injection check reads the sibling lock.json
    (src/harbor/models/trial/paths.py:182-183), whose top-level `skills` list
    records the name, source and content digest of every skill the HOST
    resolved (src/harbor/models/job/lock.py:141-146, :462-475).

    That is resolution, not delivery. The lock is written in Trial.__init__
    (src/harbor/trial/trial.py:104), before _resolve_injected_skills at :107
    and long before _upload_injected_skills at :411, and
    _build_agent_skill_locks calls only host-side functions. So a populated
    lock proves the paths resolved and pins their digests, and proves nothing
    about what reached the container: it stays fully populated through an
    upload failure, a permissions failure, or an adapter that reads the
    injected directory not at all. That last class is refused before the run
    by design_matrix.check_harbor_agents, because no artifact written after
    the run distinguishes it. config.agent.skills in result.json is the
    request as written and is used only when a trial wrote no lock.

BenchFlow (d30527b82027a416e72014920cdf43a534967ad3)
    <bench-jobs>/<cell>__<condition>/.../<job-name>/<rollout-name>/result.json
    is the dict written at src/benchflow/rollout/_results.py:387-431. The
    elided levels are whatever the manifest puts under the per-condition
    directory, such as design_matrix.py's trial-NN outer loop. Read
    task_name, rollout_name, rewards, error, verifier_error,
    partial_trajectory and started_at. The injection check requires both
    skill_mode == "with-skill" and a non-null effective_skills_dir, which
    skill_policy.config_metadata fills with the resolved host directory
    (src/benchflow/skill_policy.py:60-68); skill_mode alone records the
    request. Rollout directories are located the way
    src/benchflow/eval_lift.py:277-291 does it: the given directory if it
    holds a result.json, otherwise every directory that holds one anywhere
    beneath it.

BenchFlow has no run-id flag, so condition identity has to travel through
--jobs-dir and each (cell, condition) needs its own jobs directory named for
it. `bench eval run`'s options are declared at src/benchflow/cli/main.py:193-592,
except those sharing an Annotated alias in src/benchflow/cli/_options.py:16-32
(--model at main.py:270 and --skill-mode at main.py:438 among them), which do
not appear literally inside the command body.

Condition identity is recovered by splitting a job directory name on its last
"__" and requiring the suffix to be a key of conditions.json. An unrecognized
suffix is an error rather than a guess. --job-index bypasses the encoding
entirely for names the split cannot resolve.

Trial ordinals are assigned here, by sorting each (cell, condition, task)
group on (started_at, name). Neither runner exposes or accepts a per-trial seed
at these revisions, so ordinals align replicate k with replicate k; they do not
recover a shared randomness object. analyze_lattice.py states what that means
for invariant 4.

Reward reduction: a single-key reward dict is used as-is. A multi-key dict
requires --reward-key, because Harbor computes pass@k only when every trial
carries exactly one reward key valued 0 or 1
(src/harbor/utils/pass_at_k.py:32-53), so which key was chosen changes what the
run supports.

Usage:
    collect_rewards.py --conditions design/conditions.json \\
        [--harbor-jobs DIR] [--benchflow-jobs DIR] [--job-index FILE] \\
        [--reward-key KEY] [--errors-as drop|zero] --out results.json

Exit codes:
    0   results written
    1   no rollouts were found under any of the given roots
    2   input refused: unresolvable condition, ambiguous reward dict,
        unscored rollouts with no --errors-as choice, or a failed
        injection check
"""

import argparse
import collections
import json
import pathlib
import sys

EMPTY_CONDITION = "none"


class CollectError(Exception):
    """Collection cannot proceed as specified."""


def read_json(path):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise CollectError(f"cannot read {path}: {exc}") from exc


def load_conditions(path):
    data = read_json(pathlib.Path(path))
    if not isinstance(data, dict):
        raise CollectError(f"{path} is not a condition-id to unit-list object")
    return data


def split_job_name(name, condition_ids):
    head, sep, tail = name.rpartition("__")
    if not sep or tail not in condition_ids:
        raise CollectError(
            f"job directory {name!r} does not end in a known condition id. "
            f"Known ids: {', '.join(sorted(condition_ids))}. "
            "Rename the job, or map it explicitly with --job-index."
        )
    return head, tail


def discover_jobs(root, runner, condition_ids):
    root = pathlib.Path(root)
    if not root.is_dir():
        raise CollectError(f"{runner} jobs root {root} is not a directory")
    jobs = []
    for path in sorted(root.iterdir()):
        if not path.is_dir() or path.name.startswith("."):
            continue
        cell, condition = split_job_name(path.name, condition_ids)
        jobs.append(
            {"runner": runner, "cell": cell, "condition": condition, "path": path}
        )
    return jobs


def load_job_index(path, condition_ids):
    data = read_json(pathlib.Path(path))
    entries = data.get("jobs") if isinstance(data, dict) else data
    if not isinstance(entries, list):
        raise CollectError(f"{path} has no 'jobs' list")
    jobs = []
    for entry in entries:
        missing = [
            key
            for key in ("runner", "cell", "condition", "path")
            if key not in entry
        ]
        if missing:
            raise CollectError(f"job-index entry {entry} is missing {missing}")
        if entry["runner"] not in ("harbor", "benchflow"):
            raise CollectError(f"unknown runner {entry['runner']!r} in {path}")
        if entry["condition"] not in condition_ids:
            raise CollectError(
                f"job-index condition {entry['condition']!r} is not in conditions.json"
            )
        jobs.append({**entry, "path": pathlib.Path(entry["path"])})
    return jobs


def harbor_rollout_dirs(job_dir):
    return [
        path
        for path in sorted(job_dir.iterdir())
        if path.is_dir()
        and not path.name.startswith(".")
        and (path / "result.json").is_file()
    ]


def benchflow_rollout_dirs(job_dir):
    if (job_dir / "result.json").is_file():
        return [job_dir]
    return sorted({path.parent for path in job_dir.rglob("result.json")})


def harbor_lock_skills(trial_dir):
    """Host-resolved skill records from a trial's lock, or None if unlocked."""
    lock_path = trial_dir / "lock.json"
    if not lock_path.is_file():
        return None
    skills = read_json(lock_path).get("skills")
    return skills if isinstance(skills, list) else []


def harbor_injection(result, trial_dir):
    locked = harbor_lock_skills(trial_dir)
    if locked is None:
        requested = (result.get("config") or {}).get("agent", {}).get("skills") or []
        return bool(requested), f"no lock.json; config.agent.skills={requested}"
    pinned = [
        f"{skill.get('name')}@{str(skill.get('digest'))[:12]}"
        for skill in locked
        if isinstance(skill, dict)
    ]
    return bool(pinned), f"lock.skills={pinned}"


def parse_harbor_result(result, path):
    if "trial_name" not in result:
        raise CollectError(
            f"{path} has no trial_name; it does not look like a Harbor TrialResult"
        )
    if result.get("verifier_result") is None and result.get("step_results"):
        raise CollectError(
            f"{path} is a multi-step trial; per-step rewards are out of scope"
        )
    verifier = result.get("verifier_result") or {}
    injected, evidence = harbor_injection(result, path.parent)
    return {
        "name": result["trial_name"],
        "task": result.get("task_name"),
        "rewards": verifier.get("rewards"),
        "started_at": result.get("started_at") or "",
        "error": (result.get("exception_info") or {}).get("exception_type"),
        "injected": injected,
        "injection_evidence": evidence,
    }


def parse_benchflow_result(result, path):
    if "rollout_name" not in result:
        raise CollectError(
            f"{path} has no rollout_name; it does not look like a BenchFlow rollout"
        )
    error = (
        result.get("error")
        or result.get("verifier_error")
        or result.get("export_error")
    )
    if result.get("partial_trajectory") is True and not error:
        error = "partial_trajectory"
    mode = result.get("skill_mode")
    effective = result.get("effective_skills_dir")
    return {
        "name": result["rollout_name"],
        "task": result.get("task_name"),
        "rewards": result.get("rewards"),
        "started_at": result.get("started_at") or "",
        "error": error,
        "injected": mode == "with-skill" and effective is not None,
        "injection_evidence": (
            f"skill_mode={mode!r} effective_skills_dir={effective!r}"
        ),
    }


PARSERS = {"harbor": parse_harbor_result, "benchflow": parse_benchflow_result}
ROLLOUT_DIRS = {"harbor": harbor_rollout_dirs, "benchflow": benchflow_rollout_dirs}


def reduce_reward(rewards, reward_key, path):
    if not rewards:
        return None
    if reward_key is not None:
        if reward_key not in rewards:
            raise CollectError(
                f"{path} has no reward key {reward_key!r}; "
                f"present: {', '.join(sorted(rewards))}"
            )
        return float(rewards[reward_key])
    if len(rewards) == 1:
        return float(next(iter(rewards.values())))
    raise CollectError(
        f"{path} carries {len(rewards)} reward keys "
        f"({', '.join(sorted(rewards))}); pass --reward-key to choose one. "
        "Harbor computes pass@k only for a single 0/1 reward key, so the "
        "choice changes what the run supports."
    )


def check_injection(job, rollout, path):
    """Flag a rollout whose recorded skill request disagrees with its condition.

    One-sided. A disagreement proves the lattice did not vary as designed;
    agreement proves only that the request and the host-side resolution
    matched, which is all either runner records post hoc on the Harbor arm.
    """
    expected = job["condition"] != EMPTY_CONDITION
    if rollout["injected"] == expected:
        return None
    verb = "resolved no skills" if expected else "resolved skills"
    return (
        f"{path}: condition {job['condition']!r} {verb} "
        f"({rollout['injection_evidence']})"
    )


def collect(jobs, reward_key, verify_injection):
    scored, unscored, injection_failures = [], [], []
    for job in jobs:
        if not job["path"].is_dir():
            raise CollectError(f"job path {job['path']} is not a directory")
        for rollout_dir in ROLLOUT_DIRS[job["runner"]](job["path"]):
            path = rollout_dir / "result.json"
            rollout = PARSERS[job["runner"]](read_json(path), path)
            if rollout["task"] is None:
                raise CollectError(f"{path} has no task name")
            if verify_injection:
                failure = check_injection(job, rollout, path)
                if failure:
                    injection_failures.append(failure)
            record = {
                "condition": job["condition"],
                "cell": job["cell"],
                "task": rollout["task"],
                "runner": job["runner"],
                "job": job["path"].name,
                "rollout": rollout["name"],
                "started_at": rollout["started_at"],
                "source": str(path),
            }
            reward = reduce_reward(rollout["rewards"], reward_key, path)
            if reward is None or rollout["error"]:
                unscored.append({**record, "reason": rollout["error"] or "no rewards"})
            else:
                scored.append({**record, "reward": reward})
    return scored, unscored, injection_failures


def assign_trial_ordinals(rows):
    groups = collections.defaultdict(list)
    for row in rows:
        groups[(row["cell"], row["condition"], row["task"])].append(row)
    for group in groups.values():
        group.sort(key=lambda row: (row["started_at"], row["rollout"], row["source"]))
        for ordinal, row in enumerate(group):
            row["trial"] = ordinal
    return sorted(
        rows, key=lambda row: (row["cell"], row["condition"], row["task"], row["trial"])
    )


def build_parser():
    parser = argparse.ArgumentParser(
        description="Collect Harbor and BenchFlow run output into results.json.",
        epilog="Exit codes: 0 results written, 1 nothing found, 2 input refused.",
    )
    parser.add_argument(
        "--conditions",
        required=True,
        help="design/conditions.json emitted by design_matrix.py",
    )
    parser.add_argument("--harbor-jobs", help="Harbor --jobs-dir root to scan")
    parser.add_argument(
        "--benchflow-jobs", help="root holding one BenchFlow --jobs-dir per condition"
    )
    parser.add_argument(
        "--job-index",
        help="JSON with a 'jobs' list of {runner, cell, condition, path}, "
        "bypassing the job-name encoding",
    )
    parser.add_argument(
        "--reward-key", help="reward dict key to use when a rollout carries several"
    )
    parser.add_argument(
        "--errors-as",
        choices=["drop", "zero"],
        help="how to treat unscored rollouts; required when any are present",
    )
    parser.add_argument(
        "--no-verify-injection",
        action="store_true",
        help="skip the check that each rollout's recorded skill injection "
        "matches its condition",
    )
    parser.add_argument("--out", required=True, help="results.json to write")
    parser.add_argument(
        "--errors-out",
        help="unscored-rollout record (default: <out stem>.errors.json)",
    )
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    if not (args.harbor_jobs or args.benchflow_jobs or args.job_index):
        print(
            "collect_rewards: give at least one of --harbor-jobs, "
            "--benchflow-jobs, --job-index",
            file=sys.stderr,
        )
        return 2

    try:
        conditions = load_conditions(args.conditions)
        jobs = []
        if args.harbor_jobs:
            jobs += discover_jobs(args.harbor_jobs, "harbor", set(conditions))
        if args.benchflow_jobs:
            jobs += discover_jobs(args.benchflow_jobs, "benchflow", set(conditions))
        if args.job_index:
            jobs += load_job_index(args.job_index, set(conditions))
        scored, unscored, injection_failures = collect(
            jobs, args.reward_key, not args.no_verify_injection
        )
    except CollectError as exc:
        print(f"collect_rewards: {exc}", file=sys.stderr)
        return 2

    if injection_failures:
        print(
            "collect_rewards: skill injection does not match the condition "
            "for these rollouts, so the lattice did not vary as designed:",
            file=sys.stderr,
        )
        for failure in injection_failures:
            print(f"  {failure}", file=sys.stderr)
        return 2

    if unscored and args.errors_as is None:
        counts = collections.Counter(
            (row["cell"], row["condition"], row["reason"]) for row in unscored
        )
        print(
            f"collect_rewards: {len(unscored)} rollouts carry no usable reward. "
            "Choose --errors-as drop (exclude them, as BenchFlow's own lift "
            "report does) or --errors-as zero (score them 0, as Harbor's "
            "pass@k does). Counts by (cell, condition, reason):",
            file=sys.stderr,
        )
        for (cell, condition, reason), count in sorted(counts.items()):
            print(f"  {cell} {condition} {reason}: {count}", file=sys.stderr)
        return 2

    rows = list(scored)
    if args.errors_as == "zero":
        rows += [
            {key: value for key, value in row.items() if key != "reason"}
            | {"reward": 0.0}
            for row in unscored
        ]
    if not rows:
        print("collect_rewards: no scored rollouts found", file=sys.stderr)
        return 1

    rows = assign_trial_ordinals(rows)
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(rows, indent=2) + "\n")

    errors_out = pathlib.Path(
        args.errors_out or out.parent / f"{out.stem}.errors.json"
    )
    errors_out.write_text(
        json.dumps(
            {"errors_as": args.errors_as, "unscored": unscored}, indent=2
        )
        + "\n"
    )

    cells = sorted({row["cell"] for row in rows})
    print(
        f"rows={len(rows)} jobs={len(jobs)} cells={len(cells)} "
        f"unscored={len(unscored)} -> {out} (unscored record: {errors_out})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
