<!--
Raw capture of the decision chain for this change.
No interactive brainstorming session ran. The operator opened the den-ready-fleet project on 2026-11-26 from a read-only den-readiness audit of the repository and settled five decisions in advance (no person/account key rename, the poisoned-flake guard replacement, disko as an independent literal, a typed `flake.fleet.hosts` registry, and the stibnite `controller` tag left open). This change is the first of that project; every other change in it depends on the oracle it commits.
The audit is a session artifact outside the repository. Its findings used here are restated so this file stands alone, and every file:line below was re-read against the working tree on 2026-11-26.
-->

# Brainstorm: a cross-revision identity oracle and a cost baseline before the den-ready refactors

## Background

The den-readiness audit found that the fleet already has den's aspect shape and one seam per host, and falls short in four places: the host entity is split over several hand-kept tables, host↔user and worker↔host relations are restated, hosts read other hosts' evaluated config, and composition order and identity are implicit.
The refactors that close those gaps are meant to change no built output, or only a small set named in advance.
Nothing in the repository can show that across two revisions.

What exists:
- `just eval-identity` (`justfile:435-452`) runs `apps/nix-eval-jobs-identity` and `apps/nix-classic-identity`. Both compare two **evaluators** (stock Nix and iets) at **one** commit. `modules/README.md:88` calls the first "the drvPath-identity oracle", which a reader takes to mean the cross-revision one.
- The skill `preferences-nix-checks-architecture`, `references/evaluation-cost.md:90-121` ("drvPath-identity oracle") describes the cross-revision procedure: dump drvPath maps of every check set and every configuration toplevel at a base and a candidate revision and `diff` them. It is prose with `/tmp` paths, not a committed tool. Its source is `modules/home/ai/plugins/preferences-nix-and-secrets/.apm/skills/preferences-nix-checks-architecture/references/evaluation-cost.md`; the copy under `~/.claude/skills/` is the delivered one, identical on 2026-11-26.
- `checks.x86_64-linux.structure-fleet` and `structure-home-configurations` (`modules/checks/structure/flake-shape.nix`) pin the machine and home-configuration **names**. They catch a dropped machine, not a changed one.
- Runtime tests live under the flake output `vmTests.<system>` (`modules/vm-tests/default.nix:1`, transposed from `perSystem.vmTests`), not under `checks`, so the skill's procedure, which dumps `checks` only, does not see them.

Measured eval cost, 2026-11-26 (`logs/cross-host-eval-cost-*-20261126-*`, gitignored; restated here):

| label | what (from the audit) | cpuTime s | nrThunks | gc.totalBytes |
|---|---|---|---|---|
| b | `darwinConfigurations.stibnite` toplevel drvPath | 10.97 | 24,376,302 | 3,148,532,208 |
| b2 | the same, second run | 10.70 | 24,376,302 | 3,148,547,760 |
| base-flake | flake load (`builtins.attrNames` of outputs, 26) | 1.61 | 121,461 | 8,219,888 |
| base-host | stibnite's host name only | 0.39 | 681,965 | 138,745,408 |
| a | one NixOS host key read through cinnabar's config | 0.70 | 1,505,491 | 286,808,336 |
| c | the whole known-hosts attrset of `system/ssh-known-hosts.nix` | 1.37 | 4,402,939 | 562,100,704 |
| d | magnetite's `stibnite-agent-session` public key through its config | 0.57 | 1,182,490 | 176,070,096 |

c − base-host is the audit's cross-host cost: 0.98 s CPU, 3.72M thunks, 423 MB, 9–12 % of the stibnite toplevel.
The two stibnite runs agree on thunks exactly and on allocation within 16 kB, while CPU differs by 2.5 %.
The logs do not record the evaluator, the Nix version or the exact command; the tree was dirty; base-flake's wall time (113 s, 23 s system) is dominated by copying the flake to the store, not by evaluation.
So these figures are a reference, not a baseline that a later A/B can be compared against.

## Decision chain

**Q1. Is `just eval-identity` enough?**
No. It holds the revision fixed and varies the evaluator. A refactor holds the evaluator fixed and varies the revision. Reusing it would compare stock and iets at the candidate commit and say nothing about the base.
Decision: a separate tool, and a one-sentence note in `modules/README.md` beside the existing "drvPath-identity oracle" line.

**Q2. Which output sets?**
Everything a person deploys or a gate builds:
- `nixosConfigurations.<h>.config.system.build.toplevel` (6 hosts) and `darwinConfigurations.<h>.config.system.build.toplevel` (4);
- `homeConfigurations.<name>.activationPackage` (20 names, `flake-shape.nix:50-71`);
- `checks.x86_64-linux` and `checks.aarch64-darwin`, the systems nixbot evaluates;
- `vmTests.x86_64-linux` and `vmTests.aarch64-linux` (added on 2026-11-26: runtime tests live there, and register-fleet-obligations declares an intended difference in them that the oracle must see).
Rejected: asking the flake for every system, as the skill suggests. `checks.aarch64-linux` (about 100 attributes) is built by nothing, and dumping it would double the run for no gate. The system lists are parameters with these defaults.
Rejected: `packages`, `apps`, `devShells`. A refactor of composition reaches them only through what the sets above already cover; adding them is a parameter change if a later change needs it.

**Q3. One evaluation per set, or one per attribute?**
A single `nix eval --apply 'mapAttrs …'` over all six NixOS toplevels would hold every host in one heap; stibnite alone keeps 2.2 GB live. Per-attribute is safer.
Decision: configurations and homes are evaluated one attribute per `nix eval --raw` process with stock Nix; `checks.<sys>` and `vmTests.<sys>` go through `nix-eval-jobs` with a worker count and a per-worker memory limit, as `apps/nix-eval-jobs-identity` already does, which isolates an attribute that fails to evaluate instead of aborting the dump. Nothing is built: `nix-eval-jobs` and `nix eval …drvPath` instantiate only.

**Q4. Which evaluator?**
Stock, by name. On stibnite `nix` may be iets' classic mode (`home/development/nix-classic.nix`), which refuses `--apply` and falls back. The oracle uses `flake.lib.fleetNix` (as `apps/nix-classic-identity` does via `NIX_STOCK`) and `nix-eval-jobs-stock` where the host has it, else `nix-eval-jobs`. The dump records the resolved binaries so a reader can tell.

**Q5. How are the two revisions read?**
By commit, through `git+file://<repo>?rev=<commit>`, as `nix-eval-jobs-identity.sh:53` does. This sees exactly the committed tree, so an untracked file or a dirty working copy cannot leak into either side. In this jj-colocated repository a change is passed by its commit id (`jj log -r <rev> --no-graph -T commit_id`); the tool resolves names with `git rev-parse --verify <rev>^{commit}`.

**Q6. How are intended differences declared?**
An allow-list file, one attribute per line with an expectation and a reason:
`<set>.<attr>  changed|added|removed|may-change  # reason`.
A refactor declared neutral passes no file. A difference not on the list fails. A `changed`, `added` or `removed` entry that did not happen also fails: the change claimed an effect it does not have. `may-change` is for differences the author cannot predict (for example whether an option manual is built). Each change keeps its file in its own change directory, so the declaration is reviewed with the change.

**Q7. What does a failed evaluation count as?**
An attribute that fails at both revisions is reported and does not fail the diff, as in `nix-eval-jobs-identity`. One that fails at one revision only is a difference.

**Q8. How is a cost claim accepted?**
By the skill's A/B/A/B discipline (`evaluation-cost.md:77-88`): base, candidate, base, candidate, a fresh process each, same host and evaluator, `NIX_SHOW_STATS=1`, evaluation cache off, with one untimed warm-up per revision so the store copy of the flake is not timed. Report every run. Thunk count and allocation are near-deterministic (b and b2), so they separate on one pair; CPU and wall need the interleaving.
Decision: a second recipe, `just eval-cost`, that runs this for one attribute (or one key set) and writes every run and its conditions to `logs/`.

**Q9. Where do baselines live?**
`logs/` is gitignored (`.gitignore:59`), so a figure there is lost to anyone else. Decision: a committed note, `docs/notes/development/eval-cost-baselines.md`, with one row per measurement and its conditions, referenced from the architectural-principles document. Baselines to record now: stibnite toplevel, cinnabar toplevel, `checks.x86_64-linux` key set, plus the reference figures above marked as not comparable.

**Q10. What happens to `docs/notes/development/architectural-principles.md`?**
It is the planning entry point for this work and is stale:
- it plans "beads epics" (`:7`, `:348`, `:417`, `:453`, `:475`); the repository has no beads tracker and plans through OpenSpec changes and Linear;
- O07 and O08 are resolved (`system/ssh-known-hosts.nix:26-101` reads `hosts.<h>.zerotier.address`), O13 says RESOLVED, O14 is resolved (`checks/machines.nix:15-30` derives the host sets from the inventory with `deferred`), and O16 has consumers (`home/development/git.nix:61-62`, `clan/inventory/services/omnigent.nix:30`);
- the `mkMachine{Darwin,NixOS}` cluster (`:111`, `:357`) is superseded by deriving from a typed host record plus aspects;
- O06's severity note (`:181`) claims eval cost without a consumer, which is false for an unimported module.
The audit also found three findings (cross-host config reads, unkeyed dual exports, deploy-record order resting on import order) that P1–P4 cannot derive. `:466-469` asks for that to be surfaced, and a principle revision is the operator's decision.
Decision: fold the audit in, remove the resolved entries per `:460-462`, rewrite the E-section as the OpenSpec changes in the Linear project "Den-ready fleet architecture", and add the candidate fifth principle as a **proposal** in its own section, not into "The four principles", for the operator to accept or reject.

**Q11. ADRs?**
ADR-0018, -0019 and -0020 describe 8 machines and 5 users, put `nixpkgs.hostPlatform` in `clan.machines`, use `flakeModulesHome."users/crs58"`, and ADR-0020 cites a non-existent `inventory/services/ssh-known-hosts.nix` and `modules.common`. No ADR in the directory has an amendment yet. Decision: a dated amendment section in each, leaving the original decision text intact, since an ADR records what was decided then.

**Q12. home/README.md?**
`modules/home/README.md:32` calls Den "drupol's aspect framework". Den is `github:denful/den`; drupol's infra uses it. Fix the attribution; the "not adopted here" statement stays true until a migration lands.

## Trade-offs

- Per-attribute processes pay the flake load (1.6 s CPU measured) 30 times per revision. Accepted: it bounds memory, and the oracle is run once per refactor, not per commit.
- The oracle proves the build recipe is unchanged, not that the running system behaves the same. For input-addressed derivations that is the strongest statement available without building; it is weaker on darwin, where builds are not sandboxed by default.
- Non-derivation outputs (`flake.lib` values, `clan.inventory` data read by `clan machines update`, terranix JSON) are outside the dump. A refactor that touches them needs its own check; the structure pins cover the inventory's names and classes.
