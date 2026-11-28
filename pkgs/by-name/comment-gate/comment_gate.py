"""Fail a change whose added comments carry content that belongs elsewhere.

Every comment, docstring, documentation comment and `#` comment inside a Nix
indented string that the change adds is tested against content rules. A
blocking rule decides the exit status; a reporting rule prints to standard
error and leaves the status alone. Prose added to a Nix `description`
attribute is tested too and only reported.

Modes:
  comment-gate --staged                     the index against HEAD
  comment-gate --base REV [--head REV]      REV against the working tree, or against --head
  comment-gate --file PATH --base REV       one file of the working tree against REV
  comment-gate self-test [FIXTURES]         run the fixtures and the edge-case scenarios
A jj revision must be resolved to a git commit id before it is passed.
Paths after `--` limit the change to those paths.

Blocking findings print to standard output as `path:line: RULE: message`;
reporting findings and one summary line print to standard error.
Exit status: 0 no blocking finding, 1 blocking findings, 2 could not complete.
"""

import argparse
import ast
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field

HASH_FALLBACK_NAMES = {"justfile", "Justfile", ".justfile"}
HASH_FALLBACK_EXTS = {".just", ".jq", ".nu"}
# Fixtures and their expectations are data that contain every forbidden pattern on purpose.
SKIP_EXTS = {
    ".md", ".markdown", ".json", ".jsonl", ".lock", ".patch", ".diff", ".txt", ".prom", ".svg",
    ".fixture", ".expect",
}

# With uncomment's default preservation list, a comment that contains a word
# such as "license" or "todo" and sits next to a keep marker reports that
# pattern as its reason, and the count of kept comments misses it.
UNCOMMENT_CONFIG = """
[global]
remove_todos = true
remove_fixme = true
remove_docs = false
use_default_ignores = false
respect_gitignore = false
traverse_git_repos = false
"""
KEEP_REASONS = {"keep_marker", "extended_by_neighbour_marker"}
DIRECTIVE_CODES = re.compile(
    r"(?:noqa|type: ?ignore|pyright: ?ignore|ruff: ?noqa|shellcheck disable)\s*[:=\[]?\s*[A-Z]+\d+(?:\s*,\s*[A-Z]+\d+)*\]?"
)

HOSTS = r"(?:argentum|blackphos|rosegold|stibnite|cinnabar|electrum|galena|magnetite|pyrite|scheelite|pixel7|nixbot)"
MONTHS = r"(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\.?"
UNIT = r"\d+(?:\.\d+)?\s?(?:ms|µs|us|ns|s|sec|seconds?|min(?:utes?)?|h|hours?|[KMGT]i?B|[KMGT]B/s|%|x|cores?|CPUs?|req/s|ops/s)\b"

COMMIT_MESSAGE = "it belongs in the commit message"


@dataclass(frozen=True)
class Rule:
    rid: str
    blocking: bool
    pattern: re.Pattern
    what: str
    belongs: str


def rule(rid, blocking, pattern, flags, what, belongs):
    return Rule(rid, blocking, re.compile(pattern, flags), what, belongs)


RULES = [
    rule("B-ID", True,
         r"\b(?:design|decision|question|finding|task|stage|wave|round|phase|clause|gap|assumption|requirement|criterion|story|epic)\s+[A-Z]{0,3}\d+[a-z]?\b"
         r"|\b(?:design|decision|question|finding|task|stage|wave|round|phase|clause|gap|assumption)s?\s+[A-Z]{1,3}\d*(?:[,/ ]+(?:and\s+)?[A-Z]{1,3}\d+)*\b(?=[\s,.;:)])"
         r"|(?<![\w/.-])(?:D|Q|F|A|T|W|G|AC|OQ|CAM|DEC)\d{1,4}[a-z]?(?![\w-])",
         0, "an id that resolves only inside one change's files",
         "state the reason itself; the id belongs in the design file, the ADR or the commit message"),
    rule("B-DATE", True,
         r"\b20\d\d-[01]\d-[0-3]\d\b|\b" + MONTHS + r" \d{1,2},? 20\d\d\b|\b\d{1,2} " + MONTHS + r" 20\d\d\b|\bas of 20\d\d\b",
         0, "a literal date", COMMIT_MESSAGE),
    rule("B-MEASURE", True,
         r"(?:\b(?:measured|observed|benchmarked|timed|profiled)\b.{0,80}?" + UNIT + r")|(?:" + UNIT + r".{0,80}?\b(?:measured|observed)\b)"
         r"|(?:" + UNIT + r".{0,80}?\b(?:on|from|at)\s+" + HOSTS + r"\b)|(?:\bon\s+" + HOSTS + r"\b.{0,80}?" + UNIT + r")"
         r"|(?:\b(?:median|slowest|fastest|mean|average|p50|p90|p95|p99)\b.{0,40}?" + UNIT + r")|(?:\b\d+ runs? (?:in|over) (?:the last )?\d+ days\b)",
         re.I, "a measurement tied to a host, a date or a run", COMMIT_MESSAGE),
    rule("B-LOGPATH", True,
         r"(?<![\w/.-])logs/[\w*-][\w.*-]*",
         0, "a path under the git-ignored logs/, which a later reader cannot open", COMMIT_MESSAGE),
    rule("B-HISTORY", True,
         r"\b(?:used to|formerly|originally|until recently|now uses?|instead of the old|the old (?:code|version|way|behaviou?r|implementation)|"
         r"(?:is|are|was|were) no longer|no longer (?:needed|used|required|necessary|works?)|(?:was|were) previously|previously(?=,)|"
         r"(?:was|were|has been|have been) (?:moved|renamed|replaced|removed|dropped|changed|rewritten|split|merged)|"
         r"before this (?:change|commit)|this (?:change|commit|patch|PR) (?:adds|makes|fixes|removes|replaces|moves))\b",
         re.I, "change history", COMMIT_MESSAGE),
    rule("B-BANNER", True,
         r"^\s*(?:#|//|--|;)+\s*(?:[-=*#~_]{3,}.*|.*[-=*#~_]{6,})\s*$",
         re.M, "a section banner", "delete it; the code's own structure carries sections"),
    rule("B-TRACKER", False,
         r"(?<![\w/.-])(?!(?:SHA|UTF|ISO|RFC|CVE|AES|TLS|SSL|HTTP|IPV|CRC|PKCS|ED|X|MD|BLAKE|UCS|GPL|LGPL|AGPL|MPL|BSD|CC|ARM|PEP|SC|DS|TC|SM|GCC|LLVM|POSIX|IEEE|ECMA|ANSI|UTC|GMT|BIOS|PCI|USB|NVME|ZFS|EXT|FAT|DDR|LTS|AMD|ADR|M|R|C|K|S|P|V)-)[A-Z][A-Z0-9]{1,6}-\d+\b"
         r"|(?<![\w/.:-])(?<!upstream )(?<!upstream PR )#\d{3,6}\b|(?<!upstream )\bPR\s*#?\d+\b|(?<!upstream )\bpull request\s+#?\d+\b",
         0, "a tracker key or pull-request number", "it belongs in the commit message unless it follows the reason it points to"),
    rule("B-WHO", False,
         r"\b(?:the operator|we (?:decided|chose|agreed|settled)|I (?:decided|chose)|(?:was |is )?approved(?: by)?|as (?:requested|agreed|discussed|instructed)|per (?:the )?(?:operator|reviewer|review|discussion|user)|signed off|the user (?:asked|wants|decided|approved|chose))\b",
         re.I, "who decided", "delete it; the comment keeps the reason and the ADR records the decision"),
]
DESCRIPTION_RULES = {"B-ID", "B-DATE", "B-MEASURE", "B-LOGPATH", "B-HISTORY"}
RUN_LIMIT = 11
HEADER_LIMIT = 8
BLOCKING = {r.rid for r in RULES if r.blocking}
REPORTING = {r.rid for r in RULES if not r.blocking} | {"B-RUN", "B-HEADER", "B-DESCRIPTION"}


@dataclass
class Comment:
    path: str
    line: int
    end_line: int
    text: str
    kind: str
    reason: object = None
    added_lines: list = field(default_factory=list)


@dataclass
class Unit:
    """A judged block: a docstring, a block comment, or a run of adjacent line comments."""

    path: str
    comments: list

    @property
    def line(self):
        return self.comments[0].line

    @property
    def text(self):
        return "\n".join(c.text for c in self.comments)

    @property
    def added(self):
        return [n for c in self.comments for n in c.added_lines]


@dataclass
class Change:
    comments: list
    descriptions: list
    sources: dict
    not_judged: list


class GateError(Exception):
    pass


def git(args, cwd, binary=False):
    r = subprocess.run(["git", "-c", "core.quotePath=false", *args], cwd=cwd, capture_output=True)
    if r.returncode != 0:
        raise GateError(f"git {' '.join(args)}: {r.stderr.decode(errors='replace').strip()}")
    return r.stdout if binary else r.stdout.decode(errors="replace")


def unquote(path):
    if path.startswith('"') and path.endswith('"'):
        raw = path[1:-1].encode("latin-1", "backslashreplace").decode("unicode_escape")
        return raw.encode("latin-1").decode("utf-8", "replace")
    return path


def parse_diff(text):
    """Map path -> {new line number: text} for every added line of a -U0 diff."""
    added, cur, ln, header = {}, None, 0, False
    for line in text.split("\n"):
        if line.startswith("diff --git "):
            header, cur = True, None
        elif header and line.startswith("+++ "):
            target = unquote(line[4:])
            cur = target[2:] if target.startswith("b/") else None
            if cur is not None:
                added.setdefault(cur, {})
        elif line.startswith("@@"):
            header = False
            ln = int(re.match(r"@@ -\S+ \+(\d+)", line).group(1))
        elif not header and line.startswith("+") and cur is not None:
            added[cur][ln] = line[1:]
            ln += 1
    return added


def verify_commit(root, rev):
    r = subprocess.run(["git", "rev-parse", "--verify", "-q", f"{rev}^{{commit}}"], cwd=root, capture_output=True)
    if r.returncode != 0:
        raise GateError(f"{rev} is not a commit in this repository (resolve a jj revision to its commit id first)")


def collect_change(root, staged, base, head, pathspec):
    """Return the added lines by path and a function reading a path's post-image."""
    diff = ["diff", "--no-color", "--no-ext-diff", "-U0", "-w", "-M", "--diff-filter=d", "--src-prefix=a/", "--dst-prefix=b/"]
    for rev in filter(None, (base, head)):
        verify_commit(root, rev)
    if staged:
        has_head = subprocess.run(["git", "rev-parse", "-q", "--verify", "HEAD"], cwd=root, capture_output=True).returncode == 0
        ref = "HEAD" if has_head else git(["hash-object", "-t", "tree", "/dev/null"], root).strip()
        added = parse_diff(git(diff + ["--cached", ref, "--", *pathspec], root))

        def read(path):
            return git(["show", f":{path}"], root, binary=True)
    elif head:
        added = parse_diff(git(diff + [base, head, "--", *pathspec], root))

        def read(path):
            return git(["show", f"{head}:{path}"], root, binary=True)
    else:
        added = parse_diff(git(diff + [base, "--", *pathspec], root))
        for path in git(["ls-files", "--others", "--exclude-standard", "-z", "--", *pathspec], root).split("\0"):
            if path and os.path.isfile(os.path.join(root, path)):
                with open(os.path.join(root, path), "rb") as fh:
                    lines = fh.read().decode("utf-8", "replace").split("\n")
                added[path] = {i: t for i, t in enumerate(lines, 1) if i < len(lines) or t}

        def read(path):
            with open(os.path.join(root, path), "rb") as fh:
                return fh.read()
    return {p: v for p, v in added.items() if v}, read


def run_scan(tree, config, paths):
    """uncomment's comment records for paths, and how many of the paths it recognised."""
    r = subprocess.run(
        ["uncomment", "scan", "--format", "jsonl", "-j", "0", "-c", config, "--", *paths],
        cwd=tree, capture_output=True, text=True,
    )
    if r.returncode != 0:
        raise GateError(f"uncomment scan failed ({r.returncode}): {r.stderr.strip()[:400]}")
    m = re.search(r"Scanned (\d+) files?", r.stderr)
    if m is None:
        raise GateError(f"uncomment scan printed no file count: {r.stderr.strip()[:400]}")
    return [json.loads(line) for line in r.stdout.splitlines() if line.startswith("{")], int(m.group(1))


def scan(tree, paths):
    config = os.path.join(os.path.dirname(tree), "uncomment.toml")
    with open(config, "w") as fh:
        fh.write(UNCOMMENT_CONFIG)
    records, unknown, recognised = [], [], 0
    for i in range(0, len(paths), 300):
        batch = paths[i:i + 300]
        found, count = run_scan(tree, config, batch)
        records += found
        recognised += count
    if recognised < len(paths):
        with_records = {r["path"] for r in records}
        for path in paths:
            if path not in with_records and run_scan(tree, config, [path])[1] == 0:
                unknown.append(path)
    return records, unknown


def nix_strings(src):
    """Lines that begin inside a Nix indented string, and the spans of `description` string values."""
    inside, descriptions = set(), []
    stack, i, n, line = [["code", 0, 0, False]], 0, len(src), 1

    def open_string(kind, start):
        is_description = re.search(r"(?<![\w'-])description\s*=\s*$", src[max(0, i - 200):i]) is not None
        stack.append([kind, 0, start, is_description])

    def close_string(end):
        frame = stack.pop()
        if frame[3]:
            descriptions.append((frame[2], end))

    while i < n:
        ch, fr = src[i], stack[-1]
        if ch == "\n":
            line += 1
            if fr[0] == "ind":
                inside.add(line)
            i += 1
            continue
        if fr[0] == "code":
            if ch == "#":
                j = src.find("\n", i)
                i = n if j < 0 else j
            elif src.startswith("/*", i):
                j = src.find("*/", i + 2)
                j = n if j < 0 else j + 2
                line += src.count("\n", i, j)
                i = j
            elif src.startswith("''", i):
                open_string("ind", i + 2)
                i += 2
            elif ch == '"':
                open_string("dq", i + 1)
                i += 1
            elif ch == "{":
                fr[1] += 1
                i += 1
            elif ch == "}":
                if fr[1] == 0 and len(stack) > 1:
                    stack.pop()
                else:
                    fr[1] -= 1
                i += 1
            else:
                i += 1
        elif fr[0] == "ind":
            if src.startswith("'''", i) or src.startswith("''$", i):
                i += 3
            elif src.startswith("''\\", i):
                i += 4
            elif src.startswith("''", i):
                close_string(i)
                i += 2
            elif src.startswith("${", i):
                stack.append(["code", 0, 0, False])
                i += 2
            else:
                i += 1
        else:
            if ch == "\\":
                i += 2
            elif ch == '"':
                close_string(i)
                i += 1
            elif src.startswith("${", i):
                stack.append(["code", 0, 0, False])
                i += 2
            else:
                i += 1
    return inside, descriptions


HASH_LINE = re.compile(r"^\s*#(?:\s|$)")


def hash_line_comments(path, src, accept):
    """Full-line `#` comments on the lines accept admits, with uncomment's keep-marker run semantics."""
    found = [
        Comment(path, i, i, text.strip(), "line")
        for i, text in enumerate(src.split("\n"), 1)
        if accept(i) and HASH_LINE.match(text)
    ]
    run = []
    for c in found + [None]:
        if c is not None and run and c.line == run[-1].line + 1:
            run.append(c)
            continue
        if any("~keep" in r.text for r in run):
            for r in run:
                r.reason = "keep_marker"
        run = [] if c is None else [c]
    return found


def python_string_statements(path, src):
    """Bare string statements outside docstring position, which uncomment does not report."""
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return []
    docstrings = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)) and node.body:
            first = node.body[0]
            if isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant) and isinstance(first.value.value, str):
                docstrings.add(id(first))
    return [
        Comment(path, node.lineno, node.end_lineno, ast.get_source_segment(src, node) or node.value.value, "string-statement")
        for node in ast.walk(tree)
        if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str) and id(node) not in docstrings
    ]


def in_scope(path):
    return os.path.splitext(path)[1] not in SKIP_EXTS


def gather(root, staged, base, head, pathspec):
    added, read = collect_change(root, staged, base, head, pathspec)
    comments, descriptions, sources, not_judged, scan_paths = [], [], {}, [], []
    tmp = tempfile.mkdtemp(prefix="comment-gate.")
    try:
        tree = os.path.join(tmp, "tree")
        for path in sorted(p for p in added if in_scope(p)):
            try:
                data = read(path)
            except (GateError, OSError) as exc:
                raise GateError(f"{path}: cannot read the post-image: {exc}")
            try:
                src = data.decode("utf-8")
            except UnicodeDecodeError:
                not_judged.append(f"{path} (not UTF-8)")
                continue
            sources[path] = src
            name = os.path.basename(path)
            if name in HASH_FALLBACK_NAMES or os.path.splitext(name)[1] in HASH_FALLBACK_EXTS:
                comments += hash_line_comments(path, src, lambda i: True)
                continue
            dest = os.path.join(tree, path)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with open(dest, "wb") as fh:
                fh.write(data)
            scan_paths.append(path)
            if path.endswith(".nix"):
                inside, spans = nix_strings(src)
                comments += hash_line_comments(path, src, inside.__contains__)
                for start, end in spans:
                    first = src.count("\n", 0, start) + 1
                    descriptions.append(Comment(path, first, first + src.count("\n", start, end), src[start:end], "description"))
            elif path.endswith(".py"):
                comments += python_string_statements(path, src)
        if scan_paths:
            records, unknown = scan(tree, scan_paths)
            not_judged += [f"{p} (unknown file type)" for p in unknown]
            for r in records:
                c = Comment(r["path"], r["line"], r["end_line"], r["text"], r["kind"], r.get("reason"))
                if c.kind in ("line", "doc") and c.reason == "documentation" and c.text.startswith("##"):
                    c.kind, c.reason = "line", None
                comments.append(c)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    for c in comments + descriptions:
        lines = added.get(c.path, {})
        c.added_lines = [n for n in range(c.line, c.end_line + 1) if n in lines]
    judged = [c for c in comments if c.added_lines]
    return Change(judged, [d for d in descriptions if d.added_lines], sources, sorted(not_judged))


def build_units(comments, sources):
    """Group adjacent standalone line comments into runs; other comments stand alone."""
    units, by_path = [], {}
    for c in comments:
        by_path.setdefault(c.path, []).append(c)
    for path, cs in by_path.items():
        src_lines = sources.get(path, "").split("\n")

        def standalone(c):
            if c.kind != "line" or c.line > len(src_lines):
                return False
            return src_lines[c.line - 1].strip().startswith(c.text.strip()[:2])

        cs.sort(key=lambda c: c.line)
        run = []
        for c in cs:
            if run and standalone(c) and standalone(run[-1]) and c.line == run[-1].end_line + 1:
                run.append(c)
                continue
            if run:
                units.append(Unit(path, run))
            run = [c]
        if run:
            units.append(Unit(path, run))
    return units


def excerpt(match):
    return repr(match.group(0).strip()[:40])


def judge(units, descriptions):
    """Findings as (path, line, rule id, message)."""
    findings = []
    for u in units:
        if len(u.comments) == 1 and u.comments[0].reason == "shebang":
            continue
        text = DIRECTIVE_CODES.sub("", u.text)
        for r in RULES:
            m = r.pattern.search(text)
            if m:
                line = u.line + text.count("\n", 0, m.start())
                findings.append((u.path, line if line in u.added else u.added[0], r.rid, f"{r.what} ({excerpt(m)}); {r.belongs}"))
        is_doc = all(c.kind in ("docstring", "doc") for c in u.comments)
        n = len(u.added)
        if not is_doc and n > RUN_LIMIT:
            findings.append((u.path, u.added[0], "B-RUN", f"a comment of {n} added lines (limit {RUN_LIMIT}); the comment keeps one reason, the rationale belongs in the design file or the ADR"))
        if not is_doc and u.line <= 3 and n > HEADER_LIMIT:
            findings.append((u.path, u.added[0], "B-HEADER", f"a file-header comment of {n} added lines (limit {HEADER_LIMIT}); what the file does belongs in its option descriptions or doc comments, why in the design file or the ADR"))
    for d in descriptions:
        lines = d.text.split("\n")
        hit = set()
        for n in d.added_lines:
            for r in RULES:
                m = r.rid in DESCRIPTION_RULES and r.rid not in hit and r.pattern.search(lines[n - d.line])
                if m:
                    hit.add(r.rid)
                    findings.append((d.path, n, "B-DESCRIPTION", f"a description carries {r.what} ({excerpt(m)}); keep it to what the option does: {r.belongs}"))
    return sorted(set(findings))


def run_gate(root, staged, base, head, pathspec):
    change = gather(root, staged, base, head, pathspec)
    return judge(build_units(change.comments, change.sources), change.descriptions), change


def summary(change):
    kept = sum(1 for c in change.comments if c.reason in KEEP_REASONS)
    docs = sum(len(c.added_lines) for c in change.comments if c.kind in ("docstring", "doc"))
    line = f"comment-gate: {len(change.comments)} added comment(s), {kept} kept by ~keep, {docs} added docstring or doc-comment line(s)"
    if change.not_judged:
        line += "; not judged: " + ", ".join(change.not_judged)
    return line


FINDING = re.compile(r"^(.+?):(\d+): (B-[A-Z]+): ", re.M)


def self_test(fixtures):
    """Stage each fixture in a scratch repository, run the gate on it, and compare with its expectations.

    A fixture `<name>.fixture` is staged as `<name>`; `<name>.expect` lists the
    findings as `line: RULE`, the exit status as `exit: N` and, for a file the
    gate cannot judge, `not judged: <reason>`. Then each scenario checks one
    way a change reaches the gate.
    """
    failures = []
    me = [sys.executable, os.path.realpath(__file__)]
    env = dict(
        os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1",
        GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t",
    )
    tmp = tempfile.mkdtemp(prefix="comment-gate-self-test.")

    def sh(*args):
        return subprocess.run(["git", *args], cwd=tmp, env=env, capture_output=True, check=True)

    def gate(*args):
        return subprocess.run([*me, *args], cwd=tmp, env=env, capture_output=True, text=True)

    def write(name, text):
        with open(os.path.join(tmp, name), "w") as fh:
            fh.write(text)

    def expect(label, cond, detail):
        print(f"{'ok' if cond else 'FAIL'} {label}" + ("" if cond else f": {detail}"))
        if not cond:
            failures.append(label)

    try:
        sh("init", "-q")
        sh("commit", "-q", "--allow-empty", "-m", "base")
        r = gate("--staged")
        expect("nothing staged", r.returncode == 0, f"exit {r.returncode}: {r.stdout}{r.stderr}")

        names = sorted(f[: -len(".fixture")] for f in os.listdir(fixtures) if f.endswith(".fixture"))
        for name in names:
            shutil.copy(os.path.join(fixtures, name + ".fixture"), os.path.join(tmp, name))
        sh("add", "-A")
        fired = set()
        for name in names:
            want, want_exit, want_skip = set(), 0, None
            with open(os.path.join(fixtures, name + ".expect")) as fh:
                for raw in fh:
                    key, _, value = raw.strip().partition(":")
                    if key == "exit":
                        want_exit = int(value)
                    elif key == "not judged":
                        want_skip = f"{name} ({value.strip()})"
                    elif key:
                        want.add((int(key), value.strip()))
            r = gate("--staged", "--", name)
            out = {(int(m[1]), m[2]) for m in FINDING.findall(r.stdout)}
            err = {(int(m[1]), m[2]) for m in FINDING.findall(r.stderr)}
            fired |= {rid for _, rid in out | err}
            problems = []
            if out | err != want:
                problems.append(f"missing {sorted(want - (out | err))}, unexpected {sorted((out | err) - want)}")
            if any(rid not in BLOCKING for _, rid in out) or any(rid not in REPORTING for _, rid in err):
                problems.append(f"a finding on the wrong stream: stdout {sorted(out)}, stderr {sorted(err)}")
            if r.returncode != want_exit:
                problems.append(f"exit {r.returncode}, expected {want_exit}: {r.stderr.strip()}")
            if want_skip and want_skip not in r.stderr:
                problems.append(f"summary does not name {want_skip}: {r.stderr.strip()}")
            expect(name, not problems, "; ".join(problems))
        silent = (BLOCKING | REPORTING) - fired
        expect("every rule fires in some fixture", not silent, ", ".join(sorted(silent)))

        sh("commit", "-q", "-m", "fixtures")
        bad = "x = 1  # Restart it (stage 2).\n"
        write("partial.py", "x = 1  # The socket opens late.\n")
        sh("add", "partial.py")
        write("partial.py", bad)
        r = gate("--staged")
        expect("partially staged file: the index is judged", r.returncode == 0, r.stdout + r.stderr)
        sh("add", "partial.py")
        r = gate("--staged")
        expect("partially staged file: a blocking finding fails", r.returncode == 1, r.stdout + r.stderr)
        sh("commit", "-q", "-m", "partial")
        base = sh("rev-parse", "HEAD").stdout.decode().strip()

        sh("mv", "partial.py", "renamed.py")
        r = gate("--staged")
        expect("rename: the moved comments are not judged again", r.returncode == 0, r.stdout + r.stderr)
        sh("reset", "-q", "--hard")
        sh("rm", "-q", "partial.py")
        r = gate("--staged")
        expect("deletion", r.returncode == 0, r.stdout + r.stderr)
        sh("reset", "-q", "--hard")

        sh("checkout", "-q", "-b", "side")
        write("side.sh", "#!/bin/sh\n# Read 2026-01-02 from the history.\necho\n")
        sh("add", "side.sh")
        sh("commit", "-q", "-m", "side")
        head = sh("rev-parse", "HEAD").stdout.decode().strip()
        sh("checkout", "-q", "-")
        r = gate("--base", base, "--head", head)
        expect("--base/--head on a commit that is not checked out", r.returncode == 1 and "side.sh:2: B-DATE" in r.stdout, r.stdout + r.stderr)
        r = gate("--base", "no-such-revision")
        expect("an unknown revision cannot complete", r.returncode == 2, r.stdout + r.stderr)
    except subprocess.CalledProcessError as exc:
        raise GateError(f"{' '.join(exc.cmd)}: {exc.stderr.decode(errors='replace').strip()}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("self-test:", "passed" if not failures else f"{len(failures)} failure(s)")
    return 1 if failures else 0


def main(argv):
    if shutil.which("uncomment") is None or shutil.which("git") is None:
        print("comment-gate: git and uncomment must be on PATH", file=sys.stderr)
        return 2
    if argv[:1] == ["self-test"]:
        default = os.environ.get("COMMENT_GATE_FIXTURES") or os.path.join(os.path.dirname(os.path.realpath(__file__)), "fixtures")
        try:
            return self_test(argv[1] if len(argv) > 1 else default)
        except (GateError, OSError) as exc:
            print(f"comment-gate: self-test could not complete: {exc}", file=sys.stderr)
            return 2
    ap = argparse.ArgumentParser(prog="comment-gate", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--staged", action="store_true")
    mode.add_argument("--base")
    ap.add_argument("--head")
    ap.add_argument("--file")
    ap.add_argument("pathspec", nargs="*")
    try:
        args = ap.parse_args(argv)
    except SystemExit as exc:
        return 2 if exc.code else 0
    if args.head and not args.base or args.file and not args.base:
        print("comment-gate: --head and --file need --base", file=sys.stderr)
        return 2
    try:
        root = git(["rev-parse", "--show-toplevel"], os.getcwd()).strip()
        pathspec = list(args.pathspec)
        if args.file:
            rel = os.path.relpath(os.path.realpath(args.file), os.path.realpath(root))
            if rel.startswith(".."):
                raise GateError(f"{args.file} is outside the repository")
            pathspec = [rel]
        findings, change = run_gate(root, args.staged, args.base, args.head, pathspec)
    except GateError as exc:
        print(f"comment-gate: could not complete: {exc}", file=sys.stderr)
        return 2
    for path, line, rid, message in findings:
        stream = sys.stdout if rid in BLOCKING else sys.stderr
        print(f"{path}:{line}: {rid}: {message}", file=stream)
    print(summary(change), file=sys.stderr)
    return 1 if any(rid in BLOCKING for _, _, rid, _ in findings) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
