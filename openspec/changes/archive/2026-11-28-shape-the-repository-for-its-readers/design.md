## Context

### What exists

The fleet is described by flake-parts modules that import-tree loads from every `.nix` file under `modules/` (A356 for the `_` rule). Each module assigns `deferredModule` values into `flake.modules.<class>.<name>`, so the unit a host, home or test imports is a **named module**: one attribute of `flake.modules.nixos`, `flake.modules.darwin` or `flake.modules.homeManager`.

Identifiers used below: **P1-P5** are the five principles of `docs/notes/development/architectural-principles.md` (derive, don't enumerate; type at the natural boundary; resolve relations at one site; types are evidence; composition is order-free); **O03-O46** are that document's numbered opportunity entries, and **L1-L7** the low items of the den-readiness coverage audit (L5: the order of nixpkgs overlays). den (github.com/denful/den) is an aspect framework over flake-parts; gen (github.com/sini/gen) is a toolkit of typed registries and graphs that den uses for entity schemas.

Already done toward den's and gen's principles:
- Typed registries: hosts (`flake.fleet.hosts`, `modules/lib/hosts.nix`), the accounts people hold on hosts (`flake.fleet.hosts.<host>.users.<account>`, `modules/lib/host-users.nix`), omnigent workers (`flake.fleet.workers.<owner>`, `modules/lib/fleet-workers.nix`), cloud machines (`modules/lib/cloud-machines.nix`), observability rows (`modules/lib/observability-hosts.nix`).
- An obligations register (`fleetObligations`, `modules/lib/fleet-obligations.nix`): host judges folded into the machine checks (`modules/checks/machines.nix`).
- Provider and workstation aspects: `nixos.hetzner-cloud`, `nixos.gcp-cloud`, `darwin.darwin-workstation`.
- A secrets seam (`vanixiets.secrets`, `modules/system/secrets.nix`).
- NixOS `base` as a list of 33 named parts with a structure check (`modules/nixos/base.nix`, `modules/checks/structure/aspect-parts.nix`), committed as the first step of `name-the-parts-of-base-and-ai`.

Not done:
- Five directory principles under `modules/` (by class: `nixos/`, `darwin/`; cross-class: `system/`; by aggregate: `home/`; by host: `machines/`; by external system: `clan/`), each with breaks: `nixos/` holds darwin halves (`ntfy-alerter`, `hm-sops-bridge`), `system/` holds NixOS-only parts, cinnabar's directory defines eight reusable modules.
- Implicit unions: `darwin.base` (37 definitions), `homeManager.ai` (19), `tools` (about 62), `development` (about 26), `terminal` (21), `shell`, `languages`, `core`.
- Several routes by which a host is composed, written in several alias forms (`modules.nixos`, `flakeModules`, `flakeConfig.flake.modules.nixos`, let-bound names).
- List order decided by import depth (A344, A375).

### What readers were measured to ask, and what it cost

Terms: a **lookup question** asks where something is or what decides it; a **placement task** asks where something new goes; an **enumeration task** asks for everything of a kind that a host or the fleet has; an **impact task** asks what changes when one file changes. A **route** is how a named module reaches a configuration: the host module's own imports, a shared list such as `base`, another named module's imports, a clan service's machine or role modules, or a module generated per host. A configuration's **composition** is the set of named modules it takes, each with its route. A **host list** is a file outside the host's own directory in which a host's name or one of its facts is written by hand.

Task identifiers: Q1-Q20 are the lookup questions; PL1-PL5 the placement tasks, E1-E3 the enumeration tasks and I1-I2 the impact tasks of `/tmp/den-design/hard-tasks.json` (committed in step 1).

Five reader profiles (`future-reader-questions.md`): R1 the operator back after months; R2 an agent with one task; R3 a new contributor or household user; R4 someone debugging a failed deploy; R5 someone refactoring the structure.

**What the numbers can carry.** Both sets were measured once each, on main `1e8fb9ff6d66`, with one model and effort, by agents limited to reading and searching: evaluation was forbidden, though one `nix eval` answers I1 (`checks/structure/flake-shape.nix:11` names the pin's source). Lookups were one run per question, with files and searches self-reported (two runs report zero files: they answered from search output). The hard set had three runs per task, two for E1; one agent graded it. Three runs show whether independent readers converge or split and why; they do not give rates, and a difference of one run is not a result. Where a placement agreed, the rule was sometimes inferred rather than stated: PL4's one-file-for-both-classes rule is inferred from `system/nix-download-timeout.nix`, and PL1's scoping to four hosts from blackphos's absence. Part of PL5's split came from nixpkgs' default (`services.fstrim.enable` is on), not from the tree.

Lookup set (`/tmp/den-design/baseline-lookup.json`; one fresh read-only agent per question):

| Measure | Baseline |
|---|---|
| Right answers, graded against the keys | 20 of 20 (Q1's key is wrong, see below) |
| Files opened | median 2, maximum 4 (self-reported) |
| Searches | median 2, maximum 8 (self-reported) |
| Answers misled once | 5: Q1 (cinnabar's `matrix-server` looked like a PostgreSQL host; it is tuwunel), Q6 (stale `fleet-observability.md:607`), Q17 (a search returned archived plans under `openspec/changes/archive/`), Q18 (`nixpkgs/compose.nix:39` names an order no code enforces), Q19 (stibnite's host file names the user, not the uid) |

Q1's key says `nixos/omnigent.nix` is a trap because magnetite does not import it. It does, through the clan service: `modules/clan/services/omnigent/flake-module.nix:20-23` imports `nixos.omnigent` into every machine of the instance (A385), the server role on magnetite (`modules/clan/inventory/services/omnigent.nix:62`) sets `services.omnigent.enable` (`flake-module.nix:44-47`), and `modules/nixos/omnigent.nix:61-70` turns PostgreSQL on under that flag. The agent's answer is right; the key is corrected in the measure kit (D1).

Hard set (`/tmp/den-design/hard-tasks.json`; raw `/tmp/den-design/baseline-hard-raw.json`, graded summary `/tmp/den-design/baseline-hard.md`). Agreement is the Jaccard index of the file sets the runs would create or edit.

| Task | Kind | Median files / searches | Agreement | Right? |
|---|---|---|---|---|
| PL1 Tailscale on three Macs and pyrite | placement | 15 / 7 | file set 1.0; macOS mechanism (cask or nix-darwin service) and cask name diverge | file set yes; mechanism not settled by the tree |
| PL2 new Hetzner server `basalt` | placement | 27 / 17 | 0.70-0.77 (hand edits 0.82-1.0) | no: all three miss the `fleet-deployers` group link a new enabled host needs; two miss topology regeneration; one wrong bridge scope, one wrong size class |
| PL3 hand-entered token for service `foo` | placement | 13 / 17 | 0.75-1.0 | placement yes; two prompt shapes in the tree plus an older `exit 1` shape |
| PL4 fleet-wide Nix daemon setting | placement | 8 / 5 | 1.0 | yes |
| PL5 a check that every NixOS host has `fstrim` | placement | 7 / 6 | 0-0.5 | partly: the checks skill's ladder (obligation) and the precedent (`sshd-no-keyboard-interactive.nix`, standalone) disagree; two runs wrongly add a setting nixpkgs defaults on |
| E1 every named module in magnetite | enumeration | 29.5 / 27 | 79 versus 80 names | one run misses a module imported through a `flakeConfig` alias |
| E2 argentum but not blackphos | enumeration | 22 / 13 | same 10 mechanisms | yes; almost all registry-derived, across about ten host-keyed tables |
| E3 hosts with dnscrypt-proxy, and why | enumeration | 7 / 4 | unanimous | yes |
| I1 machines changed by editing `home/development/git.nix` | impact | 16 / 12 | unanimous | hosts yes; standalone homes no: all three say 26, the pin (`checks/structure/flake-shape.nix:47-70`) has 20 |
| I2 every file touched by removing ZeroTier | impact | grep only / 21 | 0.97-0.99 | yes: 91 files under `modules/`, 13 vars directories, about 60 documentation and skill files |

PL2 in detail: outside the host's own directory (`machines/nixos/<host>/default.nix` and `disko.nix`), a new host is written in 12 host lists. Eight are enforced by an evaluation or check: `lib/hosts.nix`, `lib/cloud-machines.nix`, `clan/inventory/machines.nix`, `lib/host-users.nix`, the `structure-fleet` pin, the machine `testSizes` entry, `machineAnchors` in `checks/sops-correspondence.nix`, `.sops.yaml`. Four are kept by convention only: the observability row, `ztRecords` (`machines/nixos/cinnabar/zt-dns.nix`), the ssh `logins` (`home/core/ssh.nix`) and the justfile's `nixos_hosts`. Generated, committed steps follow (machine key and vars, bridge re-encryption, the `fleet-deployers` link, topology files). No rule in the tree settles a new server's type and boot mode (cinnabar is BIOS cx43, electrum UEFI ccx23), its `stateVersion`, or its facter file.

What the measurements support: lookups are cheap whatever the tree's shape, because the registries and a text search answer named questions; where the tree states one rule in a header or the README, three readers found it; where it holds two answers, they split (PL5, PL3, PL1's mechanism); listing a host's composition by reading costs 26-33 files and can miss an alias form; a new host's lists are many, partly unenforced, and no guide gathers them; a home's systems are not readable from the tree without evaluation; the overlay network is read in 91 files. None of these is a cost of the directory layout. Had the hard set come out good, the case for restructuring would have rested only on the principles; it did not, and the recommendation is bounded by these costs (D3).

### Constraints

Allowed: moving and renaming files and named modules; changing the order of list options on hosts and homes with one deploy of each host at the end; making cosmetically ordered lists order-insensitive once, fleet-wide. Not allowed: adopting den or gen as a dependency; renaming people's account keys or the `machines/<class>/<host>` names; changing what any machine does beyond order; a mechanism plain flake-parts, import-tree and the NixOS module system cannot express. Code comments carry no design, task or assumption identifiers, dates, measurements, log paths or change history; `just comment-gate <rev>` runs before each publish.

### Requirements and the world they rest on

- `repository-shape` (behavioral) and `repository-shape-interface` (interface), new.
- `world-assumptions` (world): A383 (provenance of a definition made through `flake.modules`), A384 (an upstream list option re-declared with `apply` alone), A385 (a clan service's per-machine module reaches every machine of its instances), A386 (an evaluated configuration records its import tree); A344, A351, A356, A375, A376 and A377 are relied on as stated.

## Goals / Non-Goals

**Goals:**
- Every host list is derived from the registry, or written by hand with a check that names a host it lacks or has extra; none is kept by convention only except the two the overlay migration removes; the onboarding guide lists every generated step with the check that fails until it is done.
- Any configuration's composition, with each named module's route, is rendered by one command from the evaluated import tree, and a check fails when a named module arrives by a route kind the rendering does not know.
- One placement rule for each kind of addition, including checks, hand-entered secrets and Mac applications, in the entry-point document.
- System package order is settled by explicit priority where it decides a file, and then sorted, so moves and renames change no machine.
- The lookup set does not regress; the hard set's divergences and misses named above do not recur.

**Non-Goals:**
- A feature-first or entity-and-role-first re-layout of `modules/` (D3 says what each would add and at what cost).
- Dissolving `base` into fleet-wide settings and host roles (D2(d) gives the mapping for later).
- The overlay-network seam: `migrate-mesh-to-tincr` plans it, and its retirement task removes `ztRecords` and the `zerotier` registry field; this change leaves both as they are.
- Changing what any part does, including the parts that fit `base` least (Resolved Questions 3-5 move two of them in second-pass steps).
- A check that a declared hand-entered secret has a committed value (a separate later change, Resolved Question 10).
- O46's remaining reads of magnetite in runtime tests.

## Decisions

### D1: The readers and the measure

- **Choice**: two sets run by one protocol (`future-reader-questions.md`, "Measurement protocol"): a fresh agent per task, same model and effort, repository root, agent context loaded as in a real session, prompt "Answer from this repository only: <task>. Cite file:line. Stop when confident."; record files opened, searches, whether the decisive file was reached; grade against a key. Two arms: **tree** (read and search only, as at the baseline) and **commands** (also the read-only commands the entry-point document names, `just composition <name>` and `nix eval`). The kit (questions, keys with Q1 corrected, the hard-task keys, the grading script) is committed under `docs/notes/development/reader-measure/` in step 1.

  Targets. The lookup set bounds regressions; for the hard set each target is a pass or miss per run, reported as counts, never as rates:

  | Set | Measure | Baseline | Target |
  |---|---|---|---|
  | Lookup, tree arm | right answers | 20 of 20 | 20 of 20 |
  | Lookup, tree arm | files opened / searches, median and maximum | 2, 4 / 2, 8 | no higher |
  | Lookup, tree arm | misleads caused by a repository text | 4 (Q1, Q6, Q17, Q18) and Q19's comment | none of these five recur |
  | PL1, PL3, PL5, tree arm | runs that choose the mechanism a stated rule names and cite it | no rule stated | every run |
  | PL2, tree arm | host lists outside `modules/lib/hosts.nix` and the host directory in which a host's name is written by hand / of those, checked / kept by convention only | 12 / 8 / 4 | 8 / 6 / 1 (`ztRecords`, named in the guide until `migrate-mesh-to-tincr` removes it) |
  | PL2, tree arm | runs listing every generated step, including the `fleet-deployers` link | 0 of 3 | every run |
  | E1, E2, commands arm | runs complete against the key | E1 1 of 2, E2 3 of 3 (tree arm) | every run |
  | I1, commands arm | runs naming the 20 standalone homes | 0 of 3 (tree arm) | every run |
  | E1, E2, I1, tree arm | completeness and files read | as baseline | no worse |
  | I2 | files under `modules/` a removal touches | 91 | reported; the target belongs to `migrate-mesh-to-tincr` |

- **Rationale**: lookups already cost two files, so they are a bound. The hard set shows where readers split or miss; with three runs, "every run" is the only target the sample can test. E1 and I1 are answered by evaluation, which the baseline forbade; the commands arm measures the shape as an agent with a shell meets it, and the tree arm guards against a regression for a reader without one.
- **Alternatives considered**: the lookup set alone (it cannot tell shapes apart); rate targets such as agreement on 5 of 5 tasks (three runs cannot carry them); judging by the principles alone (they favour the larger shapes and say nothing about readers' cost).
- **Re-measure (correction, 2026-11-28)**: the tree arm ran at `d705c39bd6c6` (`docs/notes/development/reader-measure/after.json`); the commands arm has not run. Both sets were graded by hand: `grade.py` takes a flat list of per-run records, neither `baseline.json` nor `after.json` is in that form, and it graded nothing. E1 was graded against composition's 81 names, but at the measured commit `just composition magnetite` prints 83 (since `c63a450f800e`, `base-package-order` and `nix-build-lock` joined and `base-initrd-networking` became `initrd-networking`); against 83, runs E1-1 and E1-3 name all 83 and E1-2 lacks three, so E1's tree-arm completeness is 2 of 3 (baseline 1 of 2), files median 30 (29.5). The targets, numbered as the table's rows:
  - met: 1 (20 of 20 right); 4 for PL1 and PL3 (3 of 3 each), and for PL5 against the rule `modules/checks/README.md` states (3 of 3) but not against the key (2 of 3); 5 as the guide counted (8 / 6 / 1), though by this design's definition the counts are 9 / 6 / 2 (D2(d)); 6 (3 of 3, baseline 0 of 3);
  - not met: 2 (files maximum 6 against 4); 3 (Q17's mislead recurs, and `modules/README.md:70` caused a new one); 9 (E2 median files 22 to 27);
  - not measured: 7 and 8, the commands arm;
  - reported: 10 (90 files under `modules/`, baseline 91).

### D2: The target shape, as rules

**(a) The unit.** A named module is the unit, as today. A **concern** is one named thing the fleet does; its named modules for each class share one name (`flake.modules.nixos.<n>`, `flake.modules.darwin.<n>`, `flake.modules.homeManager.<n>`) and are written in one file or one directory whose path ends in `<n>`, under the class directory of its classes (`nixos/`, `darwin/`, `home/<area>/`) or `system/` when it spans several. Example, as `system/zt-dns.nix` already does:

```nix
{ config, ... }:
let shared = { /* values both halves read */ }; in
{
  flake.modules.nixos.zt-dns = { ... };
  flake.modules.darwin.zt-dns = { ... };
}
```

Nested names, which den writes `den.aspects.a.b`, are written `<n>-<part>` and live in the concern's file or directory (`omnigent-host`, `otel-collector-agent`). Module identity for de-duplication is the `key` `lib/export-as.nix` gives (`vanixiets/<key>`, A351); den, the aspect framework at github.com/denful/den, nests aspects instead, which this repository does not adopt. The rule is stated in the entry-point document; no new check enforces path-equals-name, because lookups already find names in one search.

**(b) Kinds of thing and where each lives (unchanged tree, stated):**

| Kind | Where | Rule |
|---|---|---|
| Entity registries: hosts, cloud machines, observability rows | `modules/lib/hosts.nix`, `cloud-machines.nix`, `observability-hosts.nix` | one typed record per host; other host literals derived (D2(d)) |
| Relations: account on host, worker on host | `modules/lib/host-users.nix` (`hosts.<h>.users.<a>`), `modules/lib/fleet-workers.nix` (`workers.<owner>.hosts.<h>`) | one record per pair, keyed by both relata; views from either end (`hostsOfAccount`, `workerAccountsOn`) |
| People | `modules/home/users/<account>/` | one meta record per account; content derived (D5 step 7) |
| Settings every machine of a class takes | the `base` lists: `nixos/base.nix`, `darwin/base.nix` | one part per concern, listed (`name-the-parts-of-base-and-ai`) |
| Kinds of machine | `nixos/hetzner-cloud.nix`, `nixos/gcp-cloud.nix`, `darwin/darwin-workstation.nix` | an import list plus the settings of that kind |
| Features | `nixos/`, `darwin/`, `system/`, `home/<area>/` | one concern per file or directory |
| Judges and obligations | beside the concern they judge; registered in `fleetObligations` | one convention (D2(b) checks row) |
| Glue for clan, home-manager, sops, secrets | `modules/clan/`, `system/home-manager-integration.nix`, `system/secrets.nix` | the only readers of the external system they wrap |
| Checks | ladder below | — |

Checks, one convention, taking the checks skill's ladder as the rule and stating its one exception: (1) a fact about one configuration's values is a module `assertions` entry or a fleet obligation judged in the existing machine checks; (2) a fact that must also hold on hosts the machine checks skip, or a fact across configurations or about flake structure, is a check under `modules/checks/`, with a `testSizes` entry beside it and a negative control in the same comparison; (3) runtime behaviour is a runtime test under `modules/vm-tests/`. The exception exists because fleet obligations run in the machine checks, which skip hosts the registry marks `checked = false` (scheelite, `lib/hosts.nix:288`); `sshd-no-keyboard-interactive.nix`, which compares one value on every NixOS machine of the inventory with a mutant, is the stated example of rung 2. PL5's `fstrim` task ("every NixOS host") then has one answer, a standalone check, and the rule tells the author to read the option's default first: two runs added a setting nixpkgs already defaults on (`services.fstrim.enable`).

Hand-entered secrets, one shape: a hidden prompt, `files.<f>.deploy = false`, and a script rendering the file the service reads, as the six existing hand-entered credentials do (`r2-usage.nix:383-390`, `greptimedb-server.nix:91-110`, `omnigraph-server.nix:88-107`, `omnigraph-backup.nix:253-270`, `postgresql-backup.nix:355-372`, `cinnabar/fleet-alert.nix:45-52`). The older shape (a script that exits 1, set with `clan vars set`: nixbot, renovate, gitea-mq, gitea, niks3) stays where it is, since changing a generator changes its vars and can re-prompt; the rule names it as superseded (Resolved Question 8).

Mac applications: a Mac application several hosts take is a named module in `darwin/` (or `system/` with a NixOS half) imported by each host or by `darwin-workstation`, using the nix-darwin service when one exists and a cask otherwise; a host file lists only values that differ by host. `darwin-workstation.nix:11-13`, which calls casks a per-host delta, is reworded to match.

The relation records are already keyed by both relata (gen's binding-node case, `gen/docs/.../understand/identity.mdx`, "Relations that carry data"): the host-user relation is nested under the host and the worker relation under the owner, and both are queried from the other end by derived views. gen's identity minted from the relata's identities, and its selectors over identities, have no plain equivalent; in the module system the pair of names is the identity (D4).

**(c) The directory tree.** The top level stays as it is; its principle, stated once in `modules/README.md`, is: a module lives under the class directory of the classes it defines (`nixos/`, `darwin/`, `home/`; `system/` for more than one), except registries and pure functions (`lib/`), clan glue (`clan/`), host composition (`machines/<class>/<host>/`), the package set (`nixpkgs/`) and flake outputs (`apps/`, `checks/`, `containers/`, `devshells/`, `effects/`, `terranix/`, `vm-tests/`). The darwin halves defined in `nixos/` (`ntfy-alerter`, `hm-sops-bridge`) move to `system/` after the parts step: `nixos/hm-sops-bridge.nix:185-186` assigns into `darwin.base`, so moving the file before `darwin.base` is an explicit list would change import-tree order and reorder darwin `base`'s definitions. NixOS-only parts in `system/` stay (the parts list names them); cinnabar's eight reusable modules stay in its directory (Q15 was answered in one read). The full mapping for the larger shape is in D3.

**(d) How a host says what it is.**

The registry record (`flake.fleet.hosts.<host>`) is the host's one declaration of facts. Each other host list gets one of three treatments, chosen by whether a judge independent of the registry still has work to do:
- **Derived** from the registry, where no independent judge is needed because the list says nothing the registry does not.
- **Hand-written and checked** against the registry, where the list carries data the registry should not hold or is read outside evaluation, so a check that names a missing or extra host is the judge.
- **Left**, where another change removes the list or its intent is not stated.

| Host list | Treatment | Why |
|---|---|---|
| `lib/hosts.nix` | the source | — |
| `clan/inventory/machines.nix` tags and description | derived: `tags` and `description` move into the record; the inventory maps over the registry | the inventory's machine set then equals the registry's by construction, so the assert at `checks/machines.nix:78-79` that `machineSystems` names equal the inventory's compares a value with itself and is deleted |
| `lib/cloud-machines.nix` | hand-written and checked: its keys are compared with the registry's cloud hosts | it carries provider data (server type, location, zone, image, GPU type and count, comment) that terranix reads; moving it would add those fields to every record |
| `lib/observability-hosts.nix` | hand-written and checked: its keys are compared with the registry's hosts | `observabilityHostsFor` takes the omnigraph root stores as a parameter, and `checks/omnigraph-retired-roots.nix:45` calls it with a substituted store; the table stays a function |
| `lib/host-users.nix` | left as written | a relation between a host and an account, not a host fact |
| the `structure-fleet` pin (`checks/structure/flake-shape.nix`) | hand-written and checked | its purpose is to falsify the registry's derived kinds (P4) |
| machine `testSizes` entries (`checks/machines.nix`) | hand-written and checked | `test-size-classes` already fails on a check with no entry, and a size class is a measured judgement, not a host fact |
| `machineAnchors` (`checks/sops-correspondence.nix`) | derived from the registry's enrolled hosts | `.sops.yaml` stays hand-written, so `sops-correspondence` still judges it against the recipients on disk |
| `.sops.yaml` | hand-written and checked | read by the sops tool outside evaluation; `sops-correspondence` is its judge |
| ssh `logins` (`home/core/ssh.nix`) | derived from the host-users relation (the account attached as admin on each host; the phones stay literal) if the evaluated set equals today's for every host; otherwise hand-written and checked against the registry's hosts | an attribute set, so deriving it renders the same configuration when the values are equal; whether the admin attachment gives today's logins (crs58 on blackphos and stibnite, cameron elsewhere) is verified at apply, not assumed |
| `ztRecords` (`machines/nixos/cinnabar/zt-dns.nix`) | left | its order feeds every peer's hosts file (`system/mesh-hosts.nix:46`) and cinnabar's dnsmasq, so deriving it would reorder them; `migrate-mesh-to-tincr` deletes it |
| the justfile's `darwin_hosts` and `nixos_hosts` (`justfile:54-56`) | deleted | they exist only so `just check-uncached-machine <hostname>` can choose `darwinConfigurations` or `nixosConfigurations`, and the NixOS list lacks magnetite and pyrite; the recipe reads the class with `nix eval --raw .#lib.hosts.<hostname>.class` (`flake.lib.hosts`, `modules/lib/hosts.nix:397`) |
| `modules/README.md` host tables | left | no generator exists and none is added; the registry is where lookups land |

Counted as files outside `modules/lib/hosts.nix` and the host's own directory in which a host's name is written by hand, the 12 host lists of PL2 become 9: 6 checked against the registry or by evaluation (`lib/cloud-machines.nix`, `lib/observability-hosts.nix` and the ssh logins by `host-list-keys`; the `structure-fleet` pin; the machine `testSizes`; `.sops.yaml` by `sops-correspondence`), `lib/host-users.nix` (a relation, needed only when the host carries accounts), and 2 kept by convention only, both named in the onboarding guide: `ztRecords` and the evaluator table in `modules/README.md`. D1's target of 8 / 6 / 1 was set without the evaluator table, which the table above classes as left: its rows state each host's memory, evaluator and bound, a per-host reading of `flake.lib.nixEvalJobsBoundRules` that no registry field names, so it stays written by hand. The checks are fleet obligations or existing structural checks, each with a negative control written the way `checks/validation.nix:105-120` writes one: a phantom entry whose `expected` value is the value a correct comparison gives it, so `mkStructuralCheck`'s equality passes only if the comparison really distinguishes it.

The steps no declaration can derive are generated, and one section of the host-onboarding guide lists them in order with the check that fails until each is done: the machine key and vars (`clan vars generate`; the host-key obligation), the bridge files re-encrypted for the new recipient (`sops-correspondence`), the `sops/secrets/<host>-age.key/groups/fleet-deployers` link for every enabled deploy target (`sops-correspondence`; `lib/fleet-deployer.nix:5-9` makes every enabled machine a target with no edit there), and the topology files (`fleet-topology-fresh`).

A new server's facts follow one rule, stated in the guide's new-host section:
- `serverType` (the Hetzner `serverType` or GCP `machineType` of its `lib/cloud-machines.nix` row) and `stateVersion` (`lib/hosts.nix:109`, already without a default) are required, with no default, so a new host fails evaluation until both are written; the registry's `cloud.type` (`lib/hosts.nix:34`, today `m.serverType or m.machineType`, which fails with a missing-attribute error) fails instead with a message naming the host and the field. A server type costs money and is chosen per host.
- `stateVersion` is the NixOS release of the locked nixpkgs when the host is first installed, and is never changed afterwards.
- Boot mode is not chosen per host; it follows the server type, once, in `nixos.hetzner-cloud`: shared-vCPU `cx*` types boot BIOS with GRUB, as the aspect's srvos module already sets up; dedicated `ccx*` and ARM `cax*` types boot UEFI with systemd-boot (`boot.loader.grub.enable = false`, `systemd-boot.enable = true`, `efi.canTouchEfiVariables = true`), which electrum writes by hand today (`machines/nixos/electrum/default.nix:35-38`). Those three lines leave electrum's host file only if electrum's derivation stays identical. A fleet obligation judges that a Hetzner host's boot loader is the one its type gives; since the aspect sets it, the judge's work is to catch a host file overriding it, and its mutant is electrum forcing GRUB on. GCP hosts are not mapped: both are disabled and boot as the gcp-cloud aspect sets.

The host's machine module stays `modules/machines/<class>/<host>/default.nix`. The registry record stays in `modules/lib/hosts.nix` (Resolved Question 1).

`base` and inventory tags: `base` stays one list per class. Clan services that select by tag (`sshd`, `tor`: `nixos`; `zerotier`: `peer`; `emergency-access`: `all`) keep working, reading the tags the inventory now derives. Dissolving `base`, should it be taken later, assigns its parts by the classification report:
- NixOS fleet-wide (15): `base-nixpkgs`, `base-admins`, `base-caches`, `base-harmonia-gc`, `base-mesh-dns`, `mesh-hosts`, the six `base-nix-*`, `base-command-not-found`, `base-sshd-max-auth-tries`, `base-zram-swap`; glue every host needs (4): `hm-sops-bridge`, `node-exporter-textfile`, `postgresql-collation`, `secrets`; judges (3): `base-host-keys`, `base-shared-vars-recipients`, `base-source-context-obligations`; parts that guard themselves on registry data or configuration and so stay fleet-wide: `nix-eval-lock`, `zpool-probe`, `base-commit-signing-key`, `fleet-deploy-target`, `base-zfs-hm-ordering`, `cli-host-inspection`, `base-mosh`.
- NixOS host roles, unguarded and true of some hosts: `base-initrd-networking` (remote unlock of cloud VMs), `base-zfs-force-import` (local-disk cloud VMs); features used by one host: `r2-usage`, `postgresql-backup`.
- darwin fleet-wide (12 settings, 5 glue, 3 judges, plus self-guarded `nix-eval-jobs`, `commit-signing-key`, `fleet-deploy-target`, `cli-host-inspection`, `mosh`); darwin roles: `homebrew`, the nine `system-defaults`, `secure-input-watch` (workstation desktop), `pmset` (laptop).
- Applied without a guard to hosts that do not need them: `base-initrd-networking` on pyrite, which turns it off with `mkForce false` (`machines/nixos/pyrite/default.nix:214-227`) and still receives its virtio initrd modules and its initrd host-key secret; `base-zfs-force-import` on hosts that are not cloud VMs; `r2-usage` and `postgresql-backup` imported, inert, everywhere. Removing any of them from a host changes that host's derivation beyond order, so each is an owner question (Resolved Questions 3-5 move two of them in second-pass steps), and a dissolution keeps every host's set of parts as it is.

**(e) The aggregates.** `darwin.base` and `ai` get named parts as `name-the-parts-of-base-and-ai` designed. The home aggregates (`tools`, `development`, `terminal`, `shell`, `languages`, `core`) get a smaller treatment: each file that assigns into two aggregates (`development/gh-dash.nix` into `development` and `ai`, `tools/omnigraph.nix` into `tools` and `ai`, `shell/session-path.nix` into `development`, `system/cli-tools/host-inspection.nix` into `engineering-tools`) is split into named parts of one concern, and the per-user aggregate lists get one default (O22). Full parts lists for `tools` (about 62 files) are not written: the composition command lists each home's named modules with the file each came from, and no measured task failed because `tools` is implicit.

**(f) Order.**
- **The system path, settled by priority, then sorted.** NixOS (`nixos/modules/config/system-path.nix:211`) and nix-darwin build the system path with `ignoreCollisions = true`, so where two equal-priority packages provide one path, the first listed wins and order is behavioural (A376). Before any sort: for every enabled host's system path, list each path provided by two or more equal-priority packages whose files differ in content; for each, mark today's winner with `lib.hiPrio` (or the loser with `lib.lowPrio`) in the module that adds it, so the winner no longer depends on order. That step changes no derivation except the marked packages' priority metadata, and is its own pull request. Only then is `environment.systemPackages` re-declared once per class with `apply = lib.sort` by name alone (A384): `lib.getName` of a derivation, else the entry's string, since `types.package` also admits a store path string. There is no tie-break by `outPath`: two different packages of one name (`python3` and a `python3.withPackages` environment) would then be ordered by store hash, and a nixpkgs bump could change which one wins an equal-priority collision. The sort is stable, so same-named entries keep their definition order. The built-profile comparison compares, for each path, the content hash of the file it resolves to, so identical files from different packages are not flagged.
- **Home packages, sorted for derivation stability only.** home-manager builds `home-manager-path` without `ignoreCollisions`, so differing files at one path abort the build and identical ones are equivalent; order there is already immaterial to behaviour. It still decides the derivation (`chosenOutputs` order), so every later move would otherwise change every reached home's derivation. `home.packages` is sorted the same way, through `home-manager.sharedModules` and `flake.lib.mkHome`; this retires the `lib.mkAfter` at `lib/host-users.nix:166`.
- **Homebrew lists, sorted for the same reason.** nix-darwin writes the `Brewfile` one section per kind (taps, brews, casks, ...) and each section in its list's order, and nothing reads an entry's position (`name-the-parts-of-base-and-ai` design D4 cites the lines). `homebrew.taps`, `homebrew.brews` and `homebrew.casks` are sorted by `name` in the darwin `base-package-order`, so moving `base-homebrew` or a module adding a cask leaves the `Brewfile` as it is. Attribute-set options (`masApps`) need no sort.
- `programs.gh-dash.settings.keybindings.prs` is written as an attribute set keyed by key and rendered in one fixed list, `C`, `m`, `M`, the order the bindings already rendered in (`home/development/gh-dash.nix`, `prsOrder`); a binding whose key the list lacks fails evaluation. The rendered `gh-dash-config.yml` is unchanged, and moving either module that defines bindings no longer reorders it.
- `users.knownUsers` and `knownGroups` are not touched: nix-darwin builds its delete list in their order, sorting them gains nothing, and their order reaches no derivation.
- Written once as an explicit order: the nixpkgs overlays. Each file under `nixpkgs/overlays/` adds its overlays as `nixpkgsOverlaysByName.<name>`, and `overlayOrder` in `nixpkgs/compose.nix` is the one list of their names (Q18, L5). The order it writes is the order nixpkgs applied before, reverse-alphabetical by file name (`zed-delta` first, `aeneas` last), not import order as `compose.nix` used to say; every package set is unchanged. A name missing from the list, or listed and defined by no file, fails evaluation.
- Ordered on purpose, order written in one place: darwin `postActivation` and launchd activation take their `lib.mkOrder` priority from `activationOrder` (`system/deploy-record.nix`), which holds `resolverReload`, `localDevelopmentCa` (stibnite's local development CA snippet), `casks`, `dnscryptProxy`, `fleetServicesTrust`, `deployRecord` and `launchd.{omnigentHost,otelAgentSession,otelCollector,sharedReferenceTree}`, values that reproduce the activation scripts as they were; tmux plugins and shell init were already pinned. `modules/README.md` names `activationOrder` as the one table.
- Pinned with `lib.mkAfter`: the `ExecStartPost` commands of `r2-usage.service` (`r2-usage-publish`) and `restic-backups-postgresql.service` (`postgresql-backup-stamp`) follow observability-notify's resolve hook wherever their modules are imported. Open: whether the resolve notice should instead follow those commands, so that their failure suppresses it.
- After the order step and these three items, import order no longer decides the order of the package lists (`environment.systemPackages`, `home.packages`), the Brewfile's taps, brews and casks, the gh-dash bindings, the overlays or the named activation snippets. It still decides any other list option that two modules define, and the uid preflight's `preActivation` snippet in `system/home-manager-integration.nix` takes the literal order `600`, outside `activationOrder`.
- Left as they are: `systemd.tmpfiles.rules`, firewall port lists.

**(g) The map, and each configuration's composition.**
- **Entry point**: `modules/README.md`, rewritten as the map: the kinds table of D2(b), the directory principle of D2(c), the placement rule for each kind of addition (host, with the onboarding guide's ordered generated steps; person; fleet-wide setting; feature for some hosts; Mac application; server service; hand-entered secret; home tool; check), where each order is written, the route kinds, and the read-only commands a reader may run.
- **Source of truth for routes**: every configuration the module system evaluates records its import tree as `graph`, one node per module with `key`, `file`, `imports` and `disabled` (A386, nixpkgs `lib/modules.nix:410,616-645`). `nixosSystem` and nix-darwin's `darwinSystem` return the evaluation with extra attributes merged in, and home-manager's standalone configuration returns its raw evaluation merged likewise, so `nixosConfigurations.<h>.graph`, `darwinConfigurations.<h>.graph` and `homeConfigurations.<n>.graph` exist. Integrated homes are submodules inside a host's evaluation and expose no graph; their composition is the standalone home's of the same account plus the attachment's extra imports from `lib/host-users.nix`, stated as such. A named module's node is recognised by its file ending `, via option flake.modules.<class>.<name>` (A375, A383); its route is the kind of its nearest named or host ancestor: the host module, a `base` list, another named module, a clan service module (A385), or a per-host generated module (`mesh-dns/<host>`).
- **The command**: `just composition <host-or-home>` evaluates the graph and prints each named module with its route, and for a standalone home the systems it is built for. Nothing is committed. A committed rendering was considered: it would let a reader without a shell list magnetite's composition in one file (E1 took 26-33), but every change that adds, removes or re-imports a named module would then regenerate up to 10 host files and 20 home files, its check failing with "composition of <host> is stale; run `just composition-render`" on changes about something else. The baseline's E1 and I1 misses were evaluation questions answered by reading; with the command named in the entry point, the commands arm of the measure tests it.
- **The check**: one fleet obligation, `compositionRoutes` (its fixture check is `composition-routes`), run inside the machine checks (rung 1 of the check rule; precedent `system/mesh-hosts.nix:33-36`, where a standalone every-host check cost 454 MB of evaluation and was replaced by an obligation). The machine check passes the configuration's `graph` to judges that ask for it; the judge fails, naming the host, the module and its parent's file, when a named module's route kind is none of the known kinds. A new route kind is then a deliberate edit to the judge and to the entry point's route list. Its negative control is a fixture graph with a named module under an unknown parent, in the judge's fixture check.
- **What the check judges**: route kinds for the named modules of checked NixOS and darwin hosts. It does not judge unnamed modules (inline modules, srvos, nixos-hardware), scheelite or any other host with `checked = false`, or homes, integrated or standalone (the `home` kind is the command's, for a standalone home's own list); a named module below another named module is `include` whatever alias form imports it, so an import written `flakeConfig.flake.modules.nixos` is not told apart. `just composition` prints a name reached by several routes once, with all of them (on magnetite `secrets` by `clan`, `include` and `base`).
- **No name-list rewrite.** Writing every composing list through a `modulesNamed` helper was planned to make routes readable as data; reading routes from `graph` makes that unnecessary, and the helper would be a second way to write a name list beside `nixosBaseParts`. The alias forms that made E1 miss a module stay, and the command, not a search, answers E1.
- No column of "registry facts that switch guarded modules" is rendered: no source gives it without reading each module's guards. E2's registry-derived differences are answered by the registry and the host lists' table in D2(d).
- **Boundary** (source-versus-delivered): the command states what the fleet description composes at a commit; what a host runs is that only once deployed.

### D3: Candidate shapes, scored

| | (i) Narrow (recommended) | (ii) Feature-first re-layout | (iii) Entity-and-role-first |
|---|---|---|---|
| Shape | today's tree; host lists derived or checked; composition command and route obligation; placement rules; order step; parts lists | `modules/<area>/<concern>/` with every class half inside; registries in `modules/fleet/` | `fleet/` entities and relations; one file per host with facts and one import list; `roles/` pure lists; `policy/` for every machine (no `base`); `features/<area>/<concern>`; `glue/`; checks beside concerns |
| Lookup set, walked | same files as today; Q19 fixed by its comment; no regression expected | Q3, Q15 change path; 1,370 path references in 121 doc, spec and agent-context files go stale until rewritten (Q6-type misleads) | Q8, Q13, Q19, Q20 move to host files, still 1-2 reads; same stale-path risk as (ii) |
| PL1, PL3, PL5 (split) | each settled by a stated rule | not moved: the split was over mechanisms the tree holds two of, not directories | not moved without the same rules; checks beside concerns adds a third check convention |
| PL2 (12 host lists, 4 by convention, 0 of 3 complete) | 9 by hand (6 checked against the registry or by evaluation, `host-users` a relation needed only for hosts with accounts, `ztRecords` and the evaluator table in `modules/README.md` by convention only); generated steps listed with their checks | not moved: the lists are about host facts | the same treatments are needed; the record in the host file saves one more list |
| E1, E2 | one command per host; E2 by the registry and D2(d)'s table | not moved: the routes and host-keyed tables remain | fewer routes (tags from roles, `base` gone), but the clan route and the registry-decided differences remain |
| I1 (0 of 3 right) | the command lists a home's systems | not moved | not moved |
| I2 (91 files) | not moved; `migrate-mesh-to-tincr` | about 10 ZeroTier files gather in one directory; the `.zt` readers stay | not moved |
| Files moved | 2 | about 400 (`nixos/` 54, `darwin/` 31, `system/` 37, `home/` 208, parts of `lib/`, `clan/`, `machines/`) | about 250 (parts of `base`, registry records into 10 host files, about 80 checks) |
| Named modules renamed | 0 beyond `name-the-parts` | 0-40 (class halves merged under one concern name) | about 60 (`base-*` to fleet-wide names, aggregates to home roles) |
| Configurations whose derivations change | every host and home, once, in the order step (package order and the marked priorities only) | the same, once, if the order step lands first | the same, once, if the order step lands first and no part is removed from a host |
| Deploys | the six enabled hosts, once; standalone homes in use activated once | the same | the same |

- **Choice**: (i). A feature-first re-layout would move none of the measured costs; the narrower changes (host lists derived or checked, a composition command with a route judge, rules where the tree holds two answers, and the overlay seam `migrate-mesh-to-tincr` already plans) address all of them that this change takes on.
- **What it gives up**: one principle for the whole tree (it states today's and removes the breaks that mislead); a directory per concern holding all class halves (omnigent stays spread over about eight files, joined by its name and the command); den's single file per host holding facts and composition; `base` as fleet-wide settings plus roles; a composition a reader without a shell can read.
- **What (iii) would add, and at what cost**: a host file that is the host's whole statement, roles a reader can name, a tree with one principle. About 250 moves, about 60 renames, and a rewrite of the docs and agent context citing today's paths; it moves no measured cost (i) does not, except the `base` mismatches, which need owner decisions anyway.
- **What (ii) would add**: every class half of a concern in one place, as dendritic (github.com/mightyiam/dendritic) has it: "a file path represents a feature". About 400 moves; it moves none of the measured costs.
- **Evidence that would change the recommendation**: after (i), a placement task where readers still split because of directory principles (towards (ii)); E1 or E2 still missed in the commands arm (towards (iii)'s role lists); the owner answering Resolved Questions 3-5 with removals (towards dissolving `base`, the first step of (iii)); a decision to weigh the principles alone (P1 and P3 favour (iii)) at the costs above.

The larger shape's tree, recorded for that decision:

```
modules/
  README.md      the map
  fleet/         registries and relations (from lib/hosts.nix, host-users.nix, fleet-workers.nix, cloud-machines.nix, observability-hosts.nix, home/users/*/meta.nix)
  machines/      <class>/<host>/ one directory per host (kept)
  policy/        what every machine of a class takes (from nixos/base.nix, darwin/base.nix and their parts in system/, darwin/, lib/, nixpkgs/)
  roles/         pure import lists (hetzner-cloud, gcp-cloud, darwin-workstation, remote-unlock, mac-desktop, laptop, home roles from the aggregates)
  features/      <area>/<concern> (from nixos/, darwin/, system/, home/<area>/, the reusable modules under machines/nixos/cinnabar/)
  glue/          clan/, home-manager, secrets, nixpkgs/ (from clan/, system/home-manager-integration.nix, system/secrets.nix, nixpkgs/)
  lib/           pure functions only
  checks/        fleet-wide checks and the harness; per-concern checks beside the concern
  outputs/       apps/, containers/, devshells/, effects/, terranix/, vm-tests/
  flake/         flake-parts.nix, systems.nix, formatting.nix, debug.nix, kubernetes.nix, nixidy.nix, k3d-cluster-config.nix
```
`brand/` joins `outputs/`; `_disabled/` is deleted or kept under its `_` prefix.

### D4: What stays out, and what only den or gen gives

Out of this change: the overlay-network seam (planned by `migrate-mesh-to-tincr`); the larger shapes of D3; removing unguarded parts from hosts that do not need them; a rule for a new server's type, boot mode, `stateVersion` and facter file; whether a missing hand-entered secret value fails any check (no check does today; the graded runs found none); O46's residue (runtime tests reading magnetite's evaluated configuration: a read across entities, P5, not a question of shape).

Only by adopting den or gen:
- Composition as data before evaluation, with de-duplication by identity over a graph of includes and membership as a query (den's `hasAspect`). Here composition is read after evaluation from the module system's `graph` (A386); it costs an evaluation per configuration.
- Context-shaped dispatch (den runs an aspect written as a function of `{ host, user }` only where that context exists) and policy-driven fan-out across entities (den's `provides.to-users`, which sends an aspect from a host to each of its users). Here relations are fanned out by derived views written by hand (`hostsOfAccount`, `workerAccountsOn`, `inventoryMembers`).
- Cross-host data without reading evaluated configuration (den's quirks, named data that aspects emit, and pipes, which collect them across hosts). Here pure `flake.lib` values do this by convention (P5), with no collector.
- Rendered diagrams of the fleet (den-diagram). Here the composition is text.
- gen's identities minted from content for entities and for relations that carry data, references typed against a registry with errors naming the available instances, and queries over identities rather than names. Here identity is the attribute name; a wrong name fails as a missing attribute.
- gen's provenance channel in the merge itself. Here `definitionsWithLocations`, the `via option` file string (A383) and `graph` (A386) carry part of it.

### D5: The migration

Each step is one pull request accepted by `just drv-diff <parent> <commit> <allow-list>` (about 16 minutes, run by the operator) and by its own checks; `just comment-gate <rev>` runs before each publish, and code comments carry no design, task or assumption identifiers, dates, measurements, log paths or change history. Mutants run in a throwaway tree.

| Step | Changes | Derivations | Open changes touching the same files | Can run beside |
|---|---|---|---|---|
| 1 Measure kit and misleading texts | `docs/notes/development/reader-measure/`; fix the texts behind Q1 (a header in `machines/nixos/cinnabar/matrix.nix` naming tuwunel and no PostgreSQL), Q6 (`fleet-observability.md:607`), Q17 (an `.ignore` entry `openspec/changes/archive/`, Resolved Question 12), Q19 (stibnite's host comment pointing to `lib/host-users.nix` for the uid) | none (comments only) | — | 2, 4, 7 |
| 2 Host lists | the three treatments of D2(d): tags and description into the record; inventory, `machineAnchors` and ssh `logins` derived; the self-comparing assert deleted; key checks for `cloud-machines.nix` and `observability-hosts.nix`; phantom in `structure-fleet` (O12); the guide's generated-steps section | none | `observability-hosts.nix`: agent-session-telemetry, back-up-postgresql-off-host, bind-mesh-writes-to-their-host, bound-fleet-garbage-collection, darwin-agent-session-telemetry, track-r2-usage, verify-ntfy-before-sending-tokens; `checks/machines.nix`: back-up-postgresql-off-host, bound-fleet-garbage-collection, delegate-fleet-deploys, deploy-omnigent-magnetite, filter-check-sources-for-substitution, migrate-mesh-to-tincr, separate-commit-signing-from-login; `cloud-machines.nix`, `sops-correspondence.nix`: delegate-fleet-deploys; `inventory/machines.nix`: diagram-fleet-topology; `home/core/ssh.nix`: migrate-mesh-to-tincr, workstation-parity; `lib/hosts.nix`: migrate-mesh-to-tincr | 1, 4, 7 |
| 2b New-server facts and the justfile recipe | `cloud.type` required with a message (`lib/hosts.nix`); the type-to-boot mapping and its judge in `nixos/hetzner-cloud.nix` and a new judge file; electrum's three boot lines removed only if its derivation is identical; `check-uncached-machine` reads the class from `lib.hosts` and both hand lists are deleted (`justfile`); the guide's new-host facts | none | `lib/hosts.nix`: migrate-mesh-to-tincr; `hetzner-cloud.nix`: compose-hosts-from-cohesive-aspects | 1, 3, 4, 7 (after 2 for `lib/hosts.nix`) |
| 3 Composition command and route judge | `just composition`; the judge and its fixtures; the machine check passing `graph` to judges | none; the judge's fixture check added | `checks/machines.nix`: as step 2 | 1, 4, 7 (after 2, which also edits `checks/machines.nix`) |
| 4 Placement rules | `modules/README.md` map; a new `modules/checks/README.md` with the ladder and its exception; the checks skill's source (edited in step 5b, since the skill is delivered into homes); the hand-entered secret shape in `system/secrets.nix`'s header; `darwin-workstation.nix:11-13` reworded | none (comments and docs) | `modules/README.md`: bind-mesh-writes-to-their-host, compose-hosts-from-cohesive-aspects, declare-test-size-classes, migrate-mesh-to-tincr, seam-secrets-away-from-clan-vars, verify-ntfy-before-sending-tokens; `darwin-workstation.nix`: compose-hosts-from-cohesive-aspects | 1, 2, 3, 7 |
| 5a Priorities | the measured equal-priority collisions with differing contents, each resolved by `hiPrio`/`lowPrio` to today's winner | only the marked packages' priority and the profiles containing them; behaviour unchanged, shown by the content comparison | — | after 2-4 |
| 5b Order | the sort modules, keyed `gh-dash` bindings, the overlay list, launchd and stibnite slots; the texts delivered into homes aligned with the first pass: the checks skill and `modules/home/ai/plugins/agent-context-vanixiets/.apm/instructions/40-fleet-and-user-conventions.instructions.md:19` (inventory tags and descriptions are registry fields in `modules/lib/hosts.nix`) | every toplevel and home: package order and the three bindings only, judged by `name-the-parts-of-base-and-ai`'s `drv-order-trace.py`; built profiles compared by content | `nixpkgs/compose.nix`, `home/development/gh-dash.nix`: none found | after 5a |
| 6 Parts lists resumed, then moves | `name-the-parts-of-base-and-ai` steps 2 (darwin `base`) and 3 (`ai`), names unchanged; the split home files of D2(e); then the darwin halves out of `nixos/` | none, after 5b; the structure check's entries declared | `hm-sops-bridge.nix`: filter-check-sources-for-substitution, name-the-parts-of-base-and-ai, seam-secrets-away-from-clan-vars | after 5b |
| 6b pyrite's initrd part | `base-initrd-networking` leaves `nixos/base.nix`'s list and enters `nixos.hetzner-cloud` and `nixos.gcp-cloud` | pyrite (loses virtio initrd modules and its initrd host-key secret); cinnabar, electrum, galena, magnetite, scheelite (order only, if any) | `hm-sops-bridge.nix`: none; `hetzner-cloud.nix`: compose-hosts-from-cohesive-aspects | after 5b |
| 6c r2-usage and postgresql-backup where used | both leave `nixos/base.nix`'s list and enter magnetite's import list | magnetite (order only, if any); cinnabar, electrum, galena, pyrite, scheelite where option documentation is built | `observability-hosts.nix` readers: none edited | after 5b |
| 7 People's literals | O11 (`meta.username` defaults to the key), O22 (aggregate default), O03 (a per-user content constructor), O17 (resolved by O03), O04 (a clan user-instance constructor), O09 (the ssh-key sites `clan/inventory/services/users/cameron.nix:45`, `tara.nix:38`, `darwin-workstation.nix:80`, `system/admins.nix:20` read the people registry) | none | `darwin-workstation.nix`: compose-hosts-from-cohesive-aspects | 1-4 |
| 8 Deploy | the enabled hosts, then the standalone homes in use | — | — | after 5b-7 |
| 9 Re-measure | both sets, both arms, three runs each | none | — | after 8 |

Each named open change is rebased past or onto the step that shares its file, whichever lands second; the step's pull request description names them.

`name-the-parts-of-base-and-ai`: its NixOS step is committed; its darwin and `ai` steps are held until step 5b lands, then resume with their names; their per-step deploys fold into step 8.

Audit items not planned elsewhere: O03, O04's constructor, O09's remaining sites, O11, O17, O22 fall into step 7; O12 into step 2 and every check this change adds; L5 into step 5b; O46's residue stays out.

**Boundary** (source-versus-delivered): steps 1-4, 2b, 6 and 7 change the fleet description only; steps 5a, 5b, 6b and 6c change what is built, and take effect at step 8.

**Comparisons as run (correction, 2026-11-28).** The steps landed as three commits with one comparison each, and `repository-shape`'s requirement "Restructuring delivers nothing but its declared differences" states what each was allowed. Each pass's evidence is its report's summary lines:
- First pass (steps 1-4, 2b and 7), `963e6ac6b` (pull request 4497), compared as `c63a450f800e`, the same patch, against `drv-delta-first-pass.txt`: no host or home changed.
- Second pass (steps 5b and 6, with `name-the-parts-of-base-and-ai`'s darwin and `ai` steps), `c69bbcac5` (pull request 4509), against `drv-delta-order.txt`: every toplevel and home changed, in package, review-binding and Brewfile order and in the two texts delivered into homes that row 5b plans (the checks skill's ladder and `40-fleet-and-user-conventions.instructions.md`); the moved path cited in `packages/docs/src/content/docs/tutorials/nixos-deployment.md` changed only the docs checks. The comparison ran on parent `fb7b981f1e74` and candidate `de1600cb6e74`; the commit landed on `1c2b60fc1`, six commits later, with an identical patch (`git range-diff`), so no comparison ran on the landed parent, and the order trace and profile replay also ran against `fb7b981f1e74`.
- Third pass (steps 6b and 6c), `d705c39bd6c6` (pull request 4510), on its landed parent `c69bbcac5565`, against `drv-delta-host-content.txt`: pyrite changed, `virtio_net` and `virtio_pci` leaving its initrd with the `initrd-networking` part; magnetite and every other host and home are identical.

```text
drv-diff 96a3c1ef8a8d -> c63a450f800e
nixos: 6 attributes; 6 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
darwin: 4 attributes; 4 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
home: 20 attributes; 20 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
result: PASS

drv-diff fb7b981f1e74 -> de1600cb6e74
nixos: 6 attributes; 0 identical, 6 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
darwin: 4 attributes; 0 identical, 4 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
home: 20 attributes; 0 identical, 20 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
result: PASS

drv-diff c69bbcac5565 -> d705c39bd6c6
nixos: 6 attributes; 5 identical, 1 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
darwin: 4 attributes; 4 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
home: 20 attributes; 20 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
result: PASS
```

The reports are `logs/drv-diff-96a3c1ef8a8d-c63a450f800e-20261128T031645Z`, `logs/drv-diff-fb7b981f1e74-de1600cb6e74-20261128T044712Z` and `logs/drv-diff-c69bbcac5565-d705c39bd6c6-20261128T051525Z`.

The three order items left open after the order step (the gh-dash bindings, the overlay list, the activation slots) and `structure-fleet`'s negative control follow on main `d705c39bd6c6` with the allow-list `drv-delta-order-items.txt`, which declares only `checks.x86_64-linux.structure-fleet`. Its comparison, `drv-diff d705c39bd6c6 -> 709ada4e324b` (`logs/drv-diff-d705c39bd6c6-709ada4e324b-20261128T062913Z`), passes: every NixOS, darwin and home attribute and every runtime test is identical, and `structure-fleet` changes as declared, with the base-allowed checks.

## Risks / Trade-offs

- [Risk] Sorting the system path changes which package provides a file. → Mitigation: step 5a measures every equal-priority collision with differing contents on every enabled host and fixes today's winner by priority before 5b sorts; 5b is accepted only when every path resolves to a file of the same content as at its parent.
- [Risk] The route judge forces each host's import tree in the machine checks. → Mitigation: the tree is already built by the same evaluation; the judge's cost is measured with `just eval-cost` on one host before it is registered, and reported before any run expected to exceed five minutes.
- [Risk] Integrated homes have no graph of their own. → Mitigation: their composition is stated as the standalone home's plus the attachment's extra imports; a module reaching an integrated home by another route is not judged, and the entry point says so.
- [Trade-off] No committed composition file: a reader without a shell still reads to list a host's composition. → Accepted: committing it would make every module-adding change regenerate up to 30 files; the tree arm of the measure records the cost.
- [Trade-off] The tree keeps several principles and the class halves of a concern stay apart. → Accepted: the measured costs are elsewhere; D3's evidence rule says when to revisit.
- [Risk] Three runs per task can agree by chance. → Mitigation: a target is met only when every run cites the stated rule's file.

## Migration Plan

1. Land steps 1-4, 2b and 7 in any order (2 before 2b and 3), each on an empty comparison apart from declared checks.
2. Land step 5a with its allow-list (the profiles containing a re-prioritised package), then 5b with its allow-list (every toplevel, every standalone home, their machine and home checks), the order trace and the content comparison.
3. Land step 6 on an empty comparison, then 6b and 6c, each with an allow-list measured at its parent (6b: pyrite, and the cloud hosts if their order moves; 6c: magnetite and whichever hosts' option documentation changes).
4. **[operator]** Deploy the enabled hosts: cinnabar and magnetite (cloud, `enabled = true` in `lib/cloud-machines.nix`), pyrite, then stibnite, argentum and rosegold; activate each standalone `crs58@*` or `cameron@*` home in use. Each deploy checks that the host runs the system its branch evaluates to, that a Mac's deploy deletes no account (A377), and reads every alert posted since it began. electrum, galena and scheelite are `enabled = false` (provisioned on demand): their derivations change and nothing is deployed; they take the new order when next provisioned. blackphos is a reserved name with no machine (`lib/observability-hosts.nix:164-167`): its derivation changes and nothing is deployed.
5. Re-measure (step 9).
6. Rollback: revert a step and redeploy, or roll a host back a generation; steps 5a, 5b, 6b and 6c change delivered systems: 5a and 5b in priority metadata and order only, 6b pyrite's initrd, 6c option documentation.

## Resolved Questions

1. The registry record stays in `modules/lib/hosts.nix`; host directories hold the configuration module and disk layout only.
2. A configuration's composition is printed on demand by `just composition <name>`; no rendering is committed.
3. pyrite stops receiving `base-initrd-networking`. The part moves from the NixOS `base` list into the two provider aspects, so the five cloud hosts keep it; this is its own second-pass step, and it changes pyrite (its virtio initrd modules and initrd host-key secret go) and may reorder lists on the five cloud hosts.
4. `r2-usage` and `postgresql-backup` are imported only by the hosts that use them: magnetite alone sets `vanixiets.r2Usage.enable` and `vanixiets.postgresqlBackup.enable` (`machines/nixos/magnetite/default.nix:195,200`). Both leave the NixOS `base` list and enter magnetite's import list, in their own second-pass step. The judges read those options with `or false` (`nixos/postgresql-backup.nix`, `nixos/r2-usage.nix`), so other hosts still evaluate. Hosts that change: magnetite (the modules sit at another import depth, so list order may move), and the other five NixOS hosts wherever their option documentation is built, since two option sets leave them; which of them change is measured in the step, not assumed.
5. Darwin `homebrew` and the macOS defaults stay in darwin `base` until a Mac that is not a workstation exists.
6. scheelite stays outside the machine checks; the check rule's exception stands.
7. The held parts steps wait for the order step.
8. The five generators using the older `exit 1` shape move when their service next changes.
9. A new server's facts follow the rule in D2(d): `serverType` and `stateVersion` are required facts with no default; `stateVersion` is the NixOS release of the locked nixpkgs at first install and never changes; boot mode follows the server type in the provider aspect, with a judge.
10. A check that a required secret value exists is a separate later change.
11. The justfile's two host lists are deleted; `just check-uncached-machine` reads the host's class from the registry.
12. Archived plans are hidden from default searches by an `.ignore` entry `openspec/changes/archive/`; `rg --no-ignore` still reaches them.
13. (2026-11-28) The fleet deploy switched cinnabar, magnetite, pyrite and stibnite to main `d705c39bd6c6`. electrum, galena and scheelite are disabled and blackphos has no machine: none was deployed, and each takes the new derivations when next provisioned. argentum and rosegold, enabled Macs, were offline and wait for their deploy.
14. (2026-11-28) No standalone home is known to be activated on a real host. On stibnite the integrated home is the one in use, and `~/.local/state/nix/profiles` there holds no standalone home-manager profile. The evidence for the standalone homes is therefore a test. On 2026-11-28 the five aarch64-linux standalone homes `crs58`, `cameron`, `tara`, `raquel` and `christophersmith` were built from main `709ada4e324b` and activated in a throwaway Ubuntu arm64 virtual machine (`logs/dht-*-20261128T06*.log`):
    - each built with no package failing;
    - each activation ran every step through linking the generation, installing packages and reloading systemd, and made generation 1 equal to the evaluated `activationPackage`;
    - each home's package list is the name-sorted one, entry for entry;
    - `gh-dash` renders `C`, `m`, `M` in the two homes with the `ai` aspect, crs58's and cameron's;
    - a repeat activation creates no new generation;
    - each activation exits 1 at the sops-nix step, because the machine has no age key (`sops-install-secrets: cannot read keyfile`), so the one step after it does not run.

    It does not show secret decryption, an activation that exits 0, the x86_64-linux or aarch64-darwin standalone homes, or any real host. Tasks 8.1 and 8.4 are ticked on verify lines reworded to this.
