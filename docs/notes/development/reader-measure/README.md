---
title: Reader measure
---

# Reader measure

How fresh agents are timed and graded on questions a later reader of this repository asks, so a change of the repository's shape can be judged by what readers can do rather than by its look.

## Files

- `lookup.json`: twenty lookup questions (where something is, or what decides it), each with its readers, the answer key, the shortest path known when it was written and the trap on the way. Question 1's key names the omnigent clan service as a route by which PostgreSQL reaches magnetite.
- `hard.json`: ten harder tasks with keys: placement (PL1-PL5, where a new addition goes), enumeration (E1-E3, everything of a kind a host or the fleet has) and impact (I1-I2, what changes when one file changes).
- `baseline.json`: the baseline, measured at commit `1e8fb9ff6d66`, with each lookup run's own account of what misled it, untruncated.

The answer keys cite files and lines as they were at commit `1e8fb9ff6d66`; a later run grades against what those citations meant, re-reading them at that commit when a file has moved.
- `grade.py`: tallies graded runs against the baseline.

## Protocol

1. Record the commit the run measures.
2. One fresh agent per task and run, with no memory or session history, the same model and effort each time, started at the repository root with the agent context loaded as in a real session.
3. Two arms. **Tree**: read and search tools only, as at the baseline. **Commands**: also the read-only commands `modules/README.md` names (`just composition <name>`, `nix eval`).
4. Prompt: "Answer from this repository only: <task>. Cite file:line. Stop when confident."
5. From each transcript record the distinct files opened, the searches, whether the decisive file was reached, and, for a placement task, whether the run cites the placement rule's file.
6. Grade each answer by hand against the key: right, partly right, or wrong; note a trap opened and whether it changed the answer, and whether a repository text misled the run.
7. Three runs per hard task, one per lookup question. Write the graded runs as JSON and run `./grade.py <runs.json>`.

## What the baseline can carry

The lookup set was run once per question; its file and search counts are the agents' own reports, and two runs answered from search output alone (zero files). The hard set had three runs per task, two for E1, graded by one agent. Evaluation was not allowed, though one `nix eval` answers I1. Three runs show whether independent readers converge or split, and why; they do not give rates, so every target is a count of runs meeting it, reported with the sample size.

Baseline, in brief:

| Set | Result |
|---|---|
| Lookup | 20 of 20 right; files median 2, maximum 4; searches median 2, maximum 8; five answers misled once (questions 1, 6, 17, 18, 19) |
| PL1 | file sets identical; macOS mechanism and cask name split |
| PL2 | 27 files read (median); every run missed the `fleet-deployers` group link |
| PL3 | two prompt shapes and an older `exit 1` shape in the tree |
| PL4 | file sets identical |
| PL5 | split between a standalone check and a fleet obligation |
| E1 | 79 and 80 of 80 names; 26-33 files |
| E2 | three of three complete; 19-29 files |
| E3 | unanimous; 7 files |
| I1 | hosts right; standalone homes wrong in every run (26 named, 20 exist) |
| I2 | 91 files under `modules/` |
