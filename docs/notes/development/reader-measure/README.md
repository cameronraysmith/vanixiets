---
title: Reader measure
---

# Reader measure

How fresh agents are timed and graded on questions a later reader of this repository asks, so a change of the repository's shape can be judged by what readers can do rather than by its look.

## Files

- `lookup.json`: twenty lookup questions (where something is, or what decides it), each with its readers, the answer key, the shortest path known when it was written and the trap on the way. Question 1's key names the omnigent clan service as a route by which PostgreSQL reaches magnetite.
- `hard.json`: ten harder tasks with keys: placement (PL1-PL5, where a new addition goes), enumeration (E1-E3, everything of a kind a host or the fleet has) and impact (I1-I2, what changes when one file changes).
- `baseline.json`: the baseline, measured at commit `1e8fb9ff6d66`, with each lookup run's own account of what misled it, untruncated.
- `after.json`: the re-measure, at commit `d705c39bd6c6`, tree arm only, in the baseline's form, with every run's answer untruncated (`answer` for a lookup, `answers` for a hard task) and the grading's notes beside its counts.

The answer keys cite files and lines as they were at commit `1e8fb9ff6d66`; a later run grades against what those citations meant, re-reading them at that commit when a file has moved.
- `grade.py`: tallies graded runs against the baseline. It takes a flat list of per-run records; neither `baseline.json` nor `after.json` is in that form, so it graded neither, and both sets were graded by hand.

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

## Re-measure at `d705c39bd6c6`

Tree arm only, against the baseline at `1e8fb9ff6d66`; the runs are in `after.json`.
Files are the distinct paths on each run's FILES line (a directory listing or a URL counts as one), searches as each run reported them, both as at the baseline.

| Class | Measure | Before | After |
|---|---|---|---|
| Lookup (20) | right | 20 of 20 | 20 of 20 |
| Lookup | files: median, maximum, total | 2, 4, 35 | 2, 6, 38 |
| Lookup | searches: median, maximum, total | 2, 8, 44 | 1.5, 8, 41 |
| Lookup | runs reporting a mislead | 5 (1, 6, 17, 18, 19) | 5 (1, 10, 16, 17, 19) |
| Lookup | misleads that changed an answer | 0 | 0 |
| Placement PL1 | median files / searches; result | 15 / 7; file sets identical, macOS mechanism and cask name split | 10 / 6; Jaccard 1.0, all three use the nix-darwin service |
| Placement PL2 | median files / searches; result | 27 / 17; Jaccard 0.70-0.77; fleet-deployers link 0 of 3, topology 1 of 3, bridge files 1 of 3 | 15 / 7; hand edits Jaccard 1.0, with generated files 0.91-1.0; fleet-deployers link, topology and bridge files 3 of 3; size class wrong in 3 of 3 |
| Placement PL3 | median files / searches; result | 13 / 17; two prompt shapes | 12 / 13; one prompt shape; generator name differs |
| Placement PL4 | median files / searches; result | 8 / 5; Jaccard 1.0; `mkDefault` split | 8 / 4; Jaccard 1.0; `mkDefault` in all three |
| Placement PL5 | median files / searches; result | 7 / 6; Jaccard 0-0.5; 2 of 3 wrongly add the setting | 4 / 4; 3 of 3 add nothing; the rung for a check, if one is wanted, split 2:1 |
| Enumeration E1 | median files / searches; result | 29.5 / 27 (2 runs); 80 versus 79 names | 30 / 24; 83, 81 and 83 names listed; graded at the time against `just composition`'s 81, but at this commit it prints 83, and two of three runs name all 83 (the third lacks `omnigent-worker-options`, `shared-reference-tree-options` and the host module); one run misses the `flakeConfig` alias again; one route vocabulary |
| Enumeration E2 | median files / searches; result | 22 / 13; complete | 27 / 17; complete |
| Enumeration E3 | median files / searches; result | 7 / 4; unanimous | 7 / 3; unanimous |
| Impact I1 | median files / searches; result | 16 / 12; 26 standalone homes in every run (wrong) | 16 / 15; 26 again in every run (wrong; the pin has 20) |
| Impact I2 | median files / searches; result | 0 / 21; 91 files under `modules/`; skill-file gaps, path slips | 1 / 19; 90 files under `modules/`; skill files and paths complete; the same margins |

PL5 is recorded under two gradings, because its key (create a standalone check, written at `1e8fb9ff6d66`) conflicts with the rule `modules/checks/README.md` states at `d705c39bd6c6` ("a setting nixpkgs or nix-darwin already turns on needs neither"). Against that rule, every run's first answer, create nothing, is right: 3 of 3. Against the key, the check each run would add if one is still wanted: two runs put it on rung 2 because scheelite's `checked = false` removes its machine check, and one put it on rung 1 as a fleet obligation: 2 of 3.

### Against the design's targets

Numbered as the rows of the targets table in `shape-the-repository-for-its-readers` design D1:
- Met: 1 (lookups right, 20 of 20); 4 for PL1 and PL3 (3 of 3 each), and for PL5 against the rule `modules/checks/README.md` states (3 of 3) but not against the key (2 of 3); 5 as the guide counted at the measured commit (8 / 6 / 1), though by the design's definition of a host list the counts are 9 written by hand, 6 checked and 2 by convention only, `ztRecords` and the evaluator table in `modules/README.md`; 6 (every generated step, 3 of 3).
- Not met: 2 (lookup files maximum 6 against 4); 3 (lookup 17's mislead recurs, and `modules/README.md:70` caused a new one); 9 (E2's median files 22 to 27).
- Not measured: 7 and 8, which need the commands arm.
- Reported: 10 (I2, 90 files under `modules/`).

### Improved, and the cause in the tree

- PL2 halved in cost and converged, with every generated step found: the host-onboarding guide's "Adding a host to the fleet description" (host lists by treatment, a hand-written count, then given as 8, that left out the evaluator table and is 9 with it, the generated steps in order naming the `fleet-deployers` link and `fleet-topology-fresh`, the server's boot mode tied to its type); the clan inventory machines and the sops `machineAnchors` derived from the registry; `host-list-keys` checking the cloud, observability and ssh-login lists.
- PL1 converged on the nix-darwin service, citing the `modules/README.md` row "Mac application several hosts take".
- PL3 converged on one prompt shape, citing the row "Hand-entered secret" with `greptimedb-r2` as the example.
- PL5: no run adds the setting, and two give the stated reason for rung 2: `modules/checks/README.md` (the ladder, the `checked = false` exception, the "needs neither" sentence).
- PL4: the `mkDefault` split closed and the darwin list is used: the row "Setting every machine of a class takes" and the new `darwinBaseParts`.
- E1: the runs share one route vocabulary: "How a named module reaches a configuration" in `modules/README.md` and `lib/composition.nix`.
- Lookups 6, 8 and 18: `fleet-observability.md:607` corrected; the `compose.nix` comment rewritten and "Where order is written" added; the evaluator table answering question 8 from one file.

### Not improved, and why

- I1 still names 26 standalone homes, not 20: no text stated the systems the homes are built for; only the locked `nix-systems` revision and the flake-shape pin held it, and no run read either.
- E1: the runs were graded against composition's 81 names, the count at `c63a450f800e`; at the measured commit `just composition magnetite` prints 83 (`base-package-order` and `nix-build-lock` joined, `base-initrd-networking` became `initrd-networking`). Against 83, two of three runs are complete (baseline 1 of 2); one run again misses imports written `flakeConfig.flake.modules.nixos`; cost unchanged.
- I2: still 16-21 searches, with no retirement list in the tree, only markers in place; the margins (ADRs, rendered SVGs, lockfiles) still differ.
- PL5: the fallback rung is still split 2:1; one run applied "cheapest rung" without the `checked = false` exception the task triggers.
- PL1: how the login URL reaches the macOS service is unresolved in every run.
- Lookup 17: the search ranking of `openspec/` is unchanged.

### Worse

- PL2's size class: all three declare `small` instead of `medium` with `measured = false` (before, one of three erred); the guide's `testSizes` row said only "a size class", and every existing `nixos-*` entry in `modules/checks/machines.nix` is `small`.
- A stale clause at `modules/README.md:69` ("until that list exists"), noticed by all three PL4 runs; no answer changed.
- A new mislead from `modules/README.md:70`: the "Feature for some hosts" example list, through `postgresql-backup`, suggested a PostgreSQL host module to lookup 1; no answer changed.
- E2's cost rose from 22 / 13 to 27 / 17, and I1's searches from 12 to 15.

### Limits

- Three runs per hard task and one per lookup question (and two baseline runs for E1): counts of runs, not rates; one run's variance can move a median.
- One model under one prompt, so the comparison cannot separate the tree's effect from that model's habits.
- Read-only tools only. The commands arm, which allows `just composition` and `nix eval`, was not run, because the measuring agents have no shell. E1's 81 was taken as given at grading, though the measured commit prints 83 (above), and I1's 20 homes were read from the flake-shape pin; the claim that `just composition magnetite` answers the enumeration question rests on comparing its names with the import graph read by hand, not on a reader trial.
- The tree also changed between the two commits for reasons unrelated to readability (magnetite's host imports 34 to 36, `base` 33 to 32 parts, `darwinBaseParts` added, two host lists derived, the ZeroTier footprint 91 to 90 files), so some differences, in cost especially, measure a different repository rather than a better-described one.
- The keys cite the earlier commit; where code had moved, runs were graded against the current code. One agent graded both sets, counting files from the runs' own FILES lines.
