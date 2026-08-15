#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Non-triviality audit (algebraic invariant 3, square_S does not derive phi).

Checks that the skills under audit cannot satisfy the task's verifier by
copying:

  1. literals   quoted expectation strings in the verifier's own sources that
                appear verbatim somewhere in skill content;
  2. oracle     token-Jaccard similarity above 0.6 between the oracle's
                solve.sh and any script the skill bundles;
  3. identity   a skill file byte-identical to a verifier file.

Each check reports its own status, so a package whose oracle does not exist yet
records check 2 as skipped rather than passing it silently.

Usage:
    audit_leakage.py --task <task-package-dir> --skills <dir> [<dir> ...]

Exit codes:
    0   every check that could run raised no flag
    1   at least one flag was raised; the review gate fails
    2   the audit could not run: bad invocation, missing task package, a
        missing or SKILL.md-free skill directory, or no verifier sources

Exit 2 is distinct from exit 0 deliberately. Every check searches for evidence
of leakage, so a mistyped path finds nothing and would otherwise be reported as
a clean package that was never examined.
"""

import argparse
import hashlib
import json
import pathlib
import re
import sys

TEXT_SUFFIXES = (".py", ".sh", ".md", ".toml", ".txt", ".json")
VERIFIER_DIRS = ("verifier", "tests")
ORACLE_DIRS = ("oracle", "solution")
MIN_LITERAL_LENGTH = 8
JACCARD_THRESHOLD = 0.6
CONTAINER_PATH_PREFIXES = ("/logs", "/tests", "/app", "/solution", "/harbor")


def tokens(text):
    return set(re.findall(r"[A-Za-z0-9_./-]{4,}", text))


def read_text_files(root, suffixes=TEXT_SUFFIXES):
    for path in sorted(pathlib.Path(root).rglob("*")):
        if path.is_file() and path.suffix in suffixes:
            try:
                yield path, path.read_text(errors="ignore")
            except OSError:
                continue


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verifier_dirs(task):
    return [task / name for name in VERIFIER_DIRS if (task / name).is_dir()]


def oracle_scripts(task):
    return [
        task / name / "solve.sh"
        for name in ORACLE_DIRS
        if (task / name / "solve.sh").is_file()
    ]


def validate_inputs(task, skills):
    """Return a list of fatal input problems (empty when the audit can run)."""
    problems = []
    if not task.is_dir():
        problems.append(f"task package {task} is not a directory")
    elif not verifier_dirs(task):
        problems.append(
            f"task package {task} has no verifier/ or tests/ directory; "
            "there are no expectations to audit against"
        )
    for skill in skills:
        if not skill.is_dir():
            problems.append(f"skill path {skill} is not a directory")
        elif not any(skill.rglob("SKILL.md")):
            problems.append(f"skill path {skill} contains no SKILL.md at any depth")
    return problems


def check_literals(task, skill_texts):
    """Verifier expectation strings recoverable from skill content."""
    literals = set()
    for directory in verifier_dirs(task):
        for _, text in read_text_files(directory):
            literals |= {
                match
                for match in re.findall(
                    rf"[\"']([^\"']{{{MIN_LITERAL_LENGTH},}})[\"']", text
                )
                if not match.startswith(CONTAINER_PATH_PREFIXES)
            }
    flags = [
        f"verifier literal {literal!r} appears in {path}"
        for literal in sorted(literals)
        for path, text in skill_texts
        if literal in text
    ]
    return {
        "id": "literals",
        "status": "ran",
        "n_literals": len(literals),
        "flags": flags,
    }


def check_oracle_similarity(task, skill_texts):
    """Oracle solve.sh token-similar to a script the skill ships."""
    scripts = oracle_scripts(task)
    if not scripts:
        return {
            "id": "oracle",
            "status": "skipped",
            "reason": "no oracle/solve.sh or solution/solve.sh in the task package",
            "flags": [],
        }
    flags = []
    for script in scripts:
        oracle_tokens = tokens(script.read_text(errors="ignore"))
        for path, text in skill_texts:
            if path.suffix not in (".sh", ".py"):
                continue
            skill_tokens = tokens(text)
            union = oracle_tokens | skill_tokens
            jaccard = len(oracle_tokens & skill_tokens) / max(1, len(union))
            if jaccard > JACCARD_THRESHOLD:
                flags.append(
                    f"{script} ~ {path} (Jaccard {jaccard:.2f}) - parameterize "
                    "task inputs or the skill IS the answer key"
                )
    return {
        "id": "oracle",
        "status": "ran",
        "n_oracles": len(scripts),
        "flags": flags,
    }


def check_byte_identity(task, skills):
    """Skill files byte-identical to verifier files."""
    verifier_digests = {}
    for directory in verifier_dirs(task):
        for path in sorted(directory.rglob("*")):
            if path.is_file():
                verifier_digests.setdefault(sha256(path), path)
    flags = []
    for skill in skills:
        for path in sorted(skill.rglob("*")):
            if not path.is_file():
                continue
            match = verifier_digests.get(sha256(path))
            if match is not None:
                flags.append(f"{path} byte-identical to verifier file {match}")
    return {
        "id": "identity",
        "status": "ran",
        "n_verifier_files": len(verifier_digests),
        "flags": flags,
    }


def audit(task, skills):
    skill_texts = [
        (path, text) for skill in skills for path, text in read_text_files(skill)
    ]
    return [
        check_literals(task, skill_texts),
        check_oracle_similarity(task, skill_texts),
        check_byte_identity(task, skills),
    ]


def gate_line(checks):
    flagged = sum(len(check["flags"]) for check in checks)
    skipped = [check["id"] for check in checks if check["status"] == "skipped"]
    verdict = "FAIL" if flagged else "pass"
    detail = f"{flagged} flag(s)" if flagged else "no flags"
    if skipped:
        detail += f"; skipped: {','.join(skipped)}"
    return f"invariant 3 non-triviality: {verdict} ({detail})"


def build_parser():
    parser = argparse.ArgumentParser(
        description="Non-triviality audit for a harborize evaluation package.",
        epilog="Exit codes: 0 clean, 1 flags raised, 2 audit could not run.",
    )
    parser.add_argument(
        "--task",
        required=True,
        type=pathlib.Path,
        help="task package directory (holds verifier/ or tests/)",
    )
    parser.add_argument(
        "--skills",
        required=True,
        nargs="+",
        type=pathlib.Path,
        help="one directory per ablation unit; each must contain a SKILL.md",
    )
    parser.add_argument(
        "--json",
        type=pathlib.Path,
        help="write the machine-readable audit record here",
    )
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)

    problems = validate_inputs(args.task, args.skills)
    if problems:
        for problem in problems:
            print(f"audit could not run: {problem}", file=sys.stderr)
        return 2

    checks = audit(args.task, args.skills)
    flags = [flag for check in checks for flag in check["flags"]]
    exit_code = 1 if flags else 0

    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps(
                {
                    "task": str(args.task),
                    "skills": [str(skill) for skill in args.skills],
                    "min_literal_length": MIN_LITERAL_LENGTH,
                    "jaccard_threshold": JACCARD_THRESHOLD,
                    "checks": checks,
                    "exit_code": exit_code,
                    "gate_line": gate_line(checks),
                },
                indent=2,
            )
            + "\n"
        )

    for check in checks:
        if check["status"] == "skipped":
            print(f"check {check['id']}: skipped - {check['reason']}")
    if flags:
        print("LEAKAGE FLAGS:")
        for flag in flags:
            print(" -", flag)
    print(gate_line(checks))
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
