# Retrospective: <change-name>

> Written: <YYYY-MM-DD> (after verify passed)
> Commit range: `<base-sha>..<head-sha>`
> Worktree: <path or "merged to main">

---

## 0. Evidence

> Up-front quantified data — later Wins / Misses bullets reference it directly, avoiding a repeated [evidence: ...] on every line.
> In a cold-write scenario (the retro is written some time after the cycle ends), this section should be reconstructable using only `git log` + `tasks.md` +
> commit messages.

- **Commit range**: `<base-sha>..<head-sha>` (<n> commits)
- **Diff size**: <+X / -Y lines across N files>
- **Tasks done**: <x>/<y> (`grep -cE '^\s*- \[x\]' tasks.md` → x; the regex tolerates sub-task indentation)
- **Active hours**: <estimate>
- **Subagent dispatches**: <count or "n/a">
- **New external dependencies**: <list, with license + version, or "none">
- **Bugs encountered post-merge**: <count, one-line each, or "none">
- **OpenSpec validate state at archive**: <pass / fail / not-run>
- **Test coverage signal**: <e.g. jacoco %, pytest count, vitest count, or "n/a">

Commit chain (chronological):

```
<base-sha> <one-line summary>
...
<head-sha> <archive commit one-line>
```

---

## 1. Wins

- [evidence: <commit/file/test>] <description>

## 2. Misses

- [high] [blocking | evidence: ...] <description>
- [med]  [painful  | evidence: ...] <description>
- [low]  [nit      | evidence: ...] <description>

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 1.2       | ...          | ... |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        |      |
| superpowers:writing-plans                        |      |
| superpowers:using-git-worktrees                  |      |
| superpowers:subagent-driven-development          |      |
| (transitive) superpowers:test-driven-development |      |
| (transitive) superpowers:requesting-code-review  |      |
| superpowers:finishing-a-development-branch       |      |

> **Default expectation**: all yes. Every skill is part of the schema design,
> so skipping is an exceptional situation. Any no must give its reason and a prevention plan in the
> `### Deliberately Skipped Skills` subsection below.

### Deliberately Skipped Skills

> Skipping a skill is a designed escape hatch, not the normal path. Each no must answer the three questions below;
> an entirely empty section (all yes) is the expected state.

- **`<skill name>`**
  - **What was skipped**: <was the whole skill skipped, or a particular sub-step>
  - **Why this cycle**: <the specific cycle condition — do not write vague reasons such as "not needed" / "too small" / "no time" / "blocked by an external dep" / "the skill's output looked wrong"; write the actual trigger (a specific commit / log line / observed behavior)>
  - **How to prevent recurrence**: how will the next cycle avoid skipping under the same kind of condition? Choose one:
    - `schema graph fix` — write specifically which part of schema.yaml to change
    - `skill description tightening` — write specifically which skill's frontmatter / instruction to change
    - `CLAUDE.md trigger` — write specifically which interpretation rule to add to the adopter CLAUDE.md.fragment
    - `scope-judgment rule` — write specifically how the cycle's scope should be interpreted
    - `one-off — schema boundary case, no prevention possible` — but you must state explicitly why it is a boundary case (no vague hedging accepted)

> **Relationship to §6 Promote candidates**: when multiple cycles share the same skill and the same `How to prevent`
> answer → that pattern should be promoted to §6, directly triggering a schema / skill PR, and must not accumulate into a "norm".

## 5. Surprises

- <assumption that turned out wrong>

## 6. Promote candidates → long-term learning

Write each candidate as a `- [ ]` checklist item:

- Title: severity marker ([high]/[med]/[low]) + a one-sentence learning
- `→ **Promote to** <destination>` (memory / CLAUDE.md / schema / skill / one-off)
- A two-line body (matching the superpowers feedback memory body schema):
  - `> **Why**: <reason; often a past incident or strong preference>`
  - `> **How to apply**: <when/where this guidance kicks in>`

An unchecked `- [ ]` means the candidate has not yet been promoted — it can be carried to the next cycle's retro for re-evaluation,
or kept as a cross-cycle observation point.

> **Carry-forward mechanism**: when writing the retro for the next cycle, resolve the archive
> directory from the CLI rather than hardcoding the repo-local change path:
> `changes_dir=$(openspec status --change "<change-name>" --json | jq -r '.planningHome.changesDir')`,
> then run `grep -A 5 '^- \[ \]' "$changes_dir"/archive/*/retrospective.md` to pull out
> previous unchecked candidates, then decide case by case whether to carry each forward into this cycle's §6, promote it
> in place, or mark it stale and stop tracking.

Examples:

- [ ] [high] **<short rule>** → **Promote to memory** (type: feedback)
  > **Why**: <past incident or strong preference that motivated this rule>
  > **How to apply**: <which file / cycle phase / decision moment this kicks in>

- [ ] [med] **<another candidate>** → **Promote to project CLAUDE.md** (`<path/to/CLAUDE.md>` section)
  > **Why**: ...
  > **How to apply**: ...

- [ ] [low] **<third candidate>** → **One-off** (just record it, do not promote)
  > **Why**: <why it doesn't generalize>
