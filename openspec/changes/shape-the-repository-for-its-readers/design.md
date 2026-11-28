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
- Changing what any part does, including the parts that fit `base` least (Open Questions 3-5).
- A rule for a new server's type, boot mode, `stateVersion` or facter file (Open Question 9); whether a missing hand-entered secret value fails any check (Open Question 10).
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
  | PL2, tree arm | host lists outside the host directory written by hand / kept by convention only | 12 / 4 | 9 / 2, and those 2 (`ztRecords`, the justfile's list) named in the guide |
  | PL2, tree arm | runs listing every generated step, including the `fleet-deployers` link | 0 of 3 | every run |
  | E1, E2, commands arm | runs complete against the key | E1 1 of 2, E2 3 of 3 (tree arm) | every run |
  | I1, commands arm | runs naming the 20 standalone homes | 0 of 3 (tree arm) | every run |
  | E1, E2, I1, tree arm | completeness and files read | as baseline | no worse |
  | I2 | files under `modules/` a removal touches | 91 | reported; the target belongs to `migrate-mesh-to-tincr` |

- **Rationale**: lookups already cost two files, so they are a bound. The hard set shows where readers split or miss; with three runs, "every run" is the only target the sample can test. E1 and I1 are answered by evaluation, which the baseline forbade; the commands arm measures the shape as an agent with a shell meets it, and the tree arm guards against a regression for a reader without one.
- **Alternatives considered**: the lookup set alone (it cannot tell shapes apart); rate targets such as agreement on 5 of 5 tasks (three runs cannot carry them); judging by the principles alone (they favour the larger shapes and say nothing about readers' cost).

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

Hand-entered secrets, one shape: a hidden prompt, `files.<f>.deploy = false`, and a script rendering the file the service reads, as the six existing hand-entered credentials do (`r2-usage.nix:383-390`, `greptimedb-server.nix:91-110`, `omnigraph-server.nix:88-107`, `omnigraph-backup.nix:253-270`, `postgresql-backup.nix:355-372`, `cinnabar/fleet-alert.nix:45-52`). The older shape (a script that exits 1, set with `clan vars set`: nixbot, renovate, gitea-mq, gitea, niks3) stays where it is, since changing a generator changes its vars and can re-prompt; the rule names it as superseded (Open Question 8).

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
| the justfile's `nixos_hosts` | left | it lists four of the six NixOS hosts and its intent is not stated (Open Question 11) |
| `modules/README.md` host tables | left | no generator exists and none is added; the registry is where lookups land |

So the 12 host lists of PL2 become 9 written by hand, 7 of them checked; the 2 kept by convention only are named in the onboarding guide. The checks are fleet obligations or existing structural checks, each with a negative control written the way `checks/validation.nix:105-120` writes one: a phantom entry whose `expected` value is the value a correct comparison gives it, so `mkStructuralCheck`'s equality passes only if the comparison really distinguishes it.

The steps no declaration can derive are generated, and one section of the host-onboarding guide lists them in order with the check that fails until each is done: the machine key and vars (`clan vars generate`; the host-key obligation), the bridge files re-encrypted for the new recipient (`sops-correspondence`), the `sops/secrets/<host>-age.key/groups/fleet-deployers` link for every enabled deploy target (`sops-correspondence`; `lib/fleet-deployer.nix:5-9` makes every enabled machine a target with no edit there), and the topology files (`fleet-topology-fresh`).

The host's machine module stays `modules/machines/<class>/<host>/default.nix`. Whether the registry record moves into that file is Open Question 1 (recommended: no).

`base` and inventory tags: `base` stays one list per class. Clan services that select by tag (`sshd`, `tor`: `nixos`; `zerotier`: `peer`; `emergency-access`: `all`) keep working, reading the tags the inventory now derives. Dissolving `base`, should it be taken later, assigns its parts by the classification report:
- NixOS fleet-wide (15): `base-nixpkgs`, `base-admins`, `base-caches`, `base-harmonia-gc`, `base-mesh-dns`, `mesh-hosts`, the six `base-nix-*`, `base-command-not-found`, `base-sshd-max-auth-tries`, `base-zram-swap`; glue every host needs (4): `hm-sops-bridge`, `node-exporter-textfile`, `postgresql-collation`, `secrets`; judges (3): `base-host-keys`, `base-shared-vars-recipients`, `base-source-context-obligations`; parts that guard themselves on registry data or configuration and so stay fleet-wide: `nix-eval-lock`, `zpool-probe`, `base-commit-signing-key`, `fleet-deploy-target`, `base-zfs-hm-ordering`, `cli-host-inspection`, `base-mosh`.
- NixOS host roles, unguarded and true of some hosts: `base-initrd-networking` (remote unlock of cloud VMs), `base-zfs-force-import` (local-disk cloud VMs); features used by one host: `r2-usage`, `postgresql-backup`.
- darwin fleet-wide (12 settings, 5 glue, 3 judges, plus self-guarded `nix-eval-jobs`, `commit-signing-key`, `fleet-deploy-target`, `cli-host-inspection`, `mosh`); darwin roles: `homebrew`, the nine `system-defaults`, `secure-input-watch` (workstation desktop), `pmset` (laptop).
- Applied without a guard to hosts that do not need them: `base-initrd-networking` on pyrite, which turns it off with `mkForce false` (`machines/nixos/pyrite/default.nix:214-227`) and still receives its virtio initrd modules and its initrd host-key secret; `base-zfs-force-import` on hosts that are not cloud VMs; `r2-usage` and `postgresql-backup` imported, inert, everywhere. Removing any of them from a host changes that host's derivation beyond order, so each is an owner question (Open Questions 3-5), and a dissolution keeps every host's set of parts as it is.

**(e) The aggregates.** `darwin.base` and `ai` get named parts as `name-the-parts-of-base-and-ai` designed. The home aggregates (`tools`, `development`, `terminal`, `shell`, `languages`, `core`) get a smaller treatment: each file that assigns into two aggregates (`development/gh-dash.nix` into `development` and `ai`, `tools/omnigraph.nix` into `tools` and `ai`, `shell/session-path.nix` into `development`, `system/cli-tools/host-inspection.nix` into `engineering-tools`) is split into named parts of one concern, and the per-user aggregate lists get one default (O22). Full parts lists for `tools` (about 62 files) are not written: the composition command lists each home's named modules with the file each came from, and no measured task failed because `tools` is implicit.

**(f) Order.**
- **The system path, settled by priority, then sorted.** NixOS (`nixos/modules/config/system-path.nix:211`) and nix-darwin build the system path with `ignoreCollisions = true`, so where two equal-priority packages provide one path, the first listed wins and order is behavioural (A376). Before any sort: for every enabled host's system path, list each path provided by two or more equal-priority packages whose files differ in content; for each, mark today's winner with `lib.hiPrio` (or the loser with `lib.lowPrio`) in the module that adds it, so the winner no longer depends on order. That step changes no derivation except the marked packages' priority metadata, and is its own pull request. Only then is `environment.systemPackages` re-declared once per class with `apply = lib.sort` by `lib.getName`, then `outPath` (A384). The built-profile comparison compares, for each path, the content hash of the file it resolves to, so identical files from different packages are not flagged.
- **Home packages, sorted for derivation stability only.** home-manager builds `home-manager-path` without `ignoreCollisions`, so differing files at one path abort the build and identical ones are equivalent; order there is already immaterial to behaviour. It still decides the derivation (`chosenOutputs` order), so every later move would otherwise change every reached home's derivation. `home.packages` is sorted the same way, through `home-manager.sharedModules` and `flake.lib.mkHome`; this retires the `lib.mkAfter` at `lib/host-users.nix:166`.
- `programs.gh-dash.settings.keybindings.prs` is written as an attribute set keyed by key, rendered in today's order `m`, `M`, `C`.
- `users.knownUsers` and `knownGroups` are not touched: nix-darwin builds its delete list in their order, sorting them gains nothing, and their order reaches no derivation.
- Written once as an explicit order: the nixpkgs overlays (`nixpkgs/compose.nix` lists them; today merge order, Q18, L5).
- Ordered on purpose, order written in one place: darwin `postActivation` (`activationOrder`, `system/deploy-record.nix:206-213`), darwin launchd activation (four `mkBefore` snippets, each given a slot in the same table), stibnite's k8s certificate snippet (`machines/darwin/stibnite/default.nix:163`, given a slot), tmux plugins and shell init (already pinned). `modules/README.md` names `activationOrder` as the one table.
- Left as they are: `systemd.tmpfiles.rules`, firewall port lists.

**(g) The map, and each configuration's composition.**
- **Entry point**: `modules/README.md`, rewritten as the map: the kinds table of D2(b), the directory principle of D2(c), the placement rule for each kind of addition (host, with the onboarding guide's ordered generated steps; person; fleet-wide setting; feature for some hosts; Mac application; server service; hand-entered secret; home tool; check), where each order is written, the route kinds, and the read-only commands a reader may run.
- **Source of truth for routes**: every configuration the module system evaluates records its import tree as `graph`, one node per module with `key`, `file`, `imports` and `disabled` (A386, nixpkgs `lib/modules.nix:410,616-645`). `nixosSystem` and nix-darwin's `darwinSystem` return the evaluation with extra attributes merged in, and home-manager's standalone configuration returns its raw evaluation merged likewise, so `nixosConfigurations.<h>.graph`, `darwinConfigurations.<h>.graph` and `homeConfigurations.<n>.graph` exist. Integrated homes are submodules inside a host's evaluation and expose no graph; their composition is the standalone home's of the same account plus the attachment's extra imports from `lib/host-users.nix`, stated as such. A named module's node is recognised by its file ending `, via option flake.modules.<class>.<name>` (A375, A383); its route is the kind of its nearest named or host ancestor: the host module, a `base` list, another named module, a clan service module (A385), or a per-host generated module (`mesh-dns/<host>`).
- **The command**: `just composition <host-or-home>` evaluates the graph and prints each named module with its route, and for a standalone home the systems it is built for. Nothing is committed. A committed rendering was considered: it would let a reader without a shell list magnetite's composition in one file (E1 took 26-33), but every change that adds, removes or re-imports a named module would then regenerate up to 10 host files and 20 home files, its check failing with "composition of <host> is stale; run `just composition-render`" on changes about something else. The baseline's E1 and I1 misses were evaluation questions answered by reading; with the command named in the entry point, the commands arm of the measure tests it.
- **The check**: one fleet obligation, `composition-routes`, run inside the machine checks (rung 1 of the check rule; precedent `system/mesh-hosts.nix:33-36`, where a standalone every-host check cost 454 MB of evaluation and was replaced by an obligation). The machine check passes the configuration's `graph` to judges that ask for it; the judge fails, naming the host, the module and its parent's file, when a named module's route kind is none of the known kinds. A new route kind is then a deliberate edit to the judge and to the entry point's route list. Its negative control is a fixture graph with a named module under an unknown parent, in the judge's fixture check. Hosts with `checked = false` (scheelite) are not judged, as for every obligation.
- **No name-list rewrite.** Writing every composing list through a `modulesNamed` helper was planned to make routes readable as data; reading routes from `graph` makes that unnecessary, and the helper would be a second way to write a name list beside `nixosBaseParts`. The alias forms that made E1 miss a module stay, and the command, not a search, answers E1.
- No column of "registry facts that switch guarded modules" is rendered: no source gives it without reading each module's guards. E2's registry-derived differences are answered by the registry and the host lists' table in D2(d).
- **Boundary** (source-versus-delivered): the command states what the fleet description composes at a commit; what a host runs is that only once deployed.

### D3: Candidate shapes, scored

| | (i) Narrow (recommended) | (ii) Feature-first re-layout | (iii) Entity-and-role-first |
|---|---|---|---|
| Shape | today's tree; host lists derived or checked; composition command and route obligation; placement rules; order step; parts lists | `modules/<area>/<concern>/` with every class half inside; registries in `modules/fleet/` | `fleet/` entities and relations; one file per host with facts and one import list; `roles/` pure lists; `policy/` for every machine (no `base`); `features/<area>/<concern>`; `glue/`; checks beside concerns |
| Lookup set, walked | same files as today; Q19 fixed by its comment; no regression expected | Q3, Q15 change path; 1,370 path references in 121 doc, spec and agent-context files go stale until rewritten (Q6-type misleads) | Q8, Q13, Q19, Q20 move to host files, still 1-2 reads; same stale-path risk as (ii) |
| PL1, PL3, PL5 (split) | each settled by a stated rule | not moved: the split was over mechanisms the tree holds two of, not directories | not moved without the same rules; checks beside concerns adds a third check convention |
| PL2 (12 host lists, 4 by convention, 0 of 3 complete) | 9 by hand, 7 checked, 2 named; generated steps listed with their checks | not moved: the lists are about host facts | the same treatments are needed; the record in the host file saves one more list |
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
- **Evidence that would change the recommendation**: after (i), a placement task where readers still split because of directory principles (towards (ii)); E1 or E2 still missed in the commands arm (towards (iii)'s role lists); the owner answering Open Questions 3-5 with removals (towards dissolving `base`, the first step of (iii)); a decision to weigh the principles alone (P1 and P3 favour (iii)) at the costs above.

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
| 1 Measure kit and misleading texts | `docs/notes/development/reader-measure/`; fix the texts behind Q1 (a header in `machines/nixos/cinnabar/matrix.nix` naming tuwunel and no PostgreSQL), Q6 (`fleet-observability.md:607`), Q17 (an `.ignore` entry for `openspec/changes/archive/`, Open Question 12), Q19 (stibnite's host comment pointing to `lib/host-users.nix` for the uid) | none (comments only) | — | 2, 4, 7 |
| 2 Host lists | the three treatments of D2(d): tags and description into the record; inventory, `machineAnchors` and ssh `logins` derived; the self-comparing assert deleted; key checks for `cloud-machines.nix` and `observability-hosts.nix`; phantom in `structure-fleet` (O12); the guide's generated-steps section | none | `observability-hosts.nix`: agent-session-telemetry, back-up-postgresql-off-host, bind-mesh-writes-to-their-host, bound-fleet-garbage-collection, darwin-agent-session-telemetry, track-r2-usage, verify-ntfy-before-sending-tokens; `checks/machines.nix`: back-up-postgresql-off-host, bound-fleet-garbage-collection, delegate-fleet-deploys, deploy-omnigent-magnetite, filter-check-sources-for-substitution, migrate-mesh-to-tincr, separate-commit-signing-from-login; `cloud-machines.nix`, `sops-correspondence.nix`: delegate-fleet-deploys; `inventory/machines.nix`: diagram-fleet-topology; `home/core/ssh.nix`: migrate-mesh-to-tincr, workstation-parity; `lib/hosts.nix`: migrate-mesh-to-tincr | 1, 4, 7 |
| 3 Composition command and route judge | `just composition`; the judge and its fixtures; the machine check passing `graph` to judges | none; the judge's fixture check added | `checks/machines.nix`: as step 2 | 1, 4, 7 (after 2, which also edits `checks/machines.nix`) |
| 4 Placement rules | `modules/README.md` map; a new `modules/checks/README.md` with the ladder and its exception; the checks skill's source; the hand-entered secret shape in `system/secrets.nix`'s header; `darwin-workstation.nix:11-13` reworded | none (comments and docs) | `modules/README.md`: bind-mesh-writes-to-their-host, compose-hosts-from-cohesive-aspects, declare-test-size-classes, migrate-mesh-to-tincr, seam-secrets-away-from-clan-vars, verify-ntfy-before-sending-tokens; `darwin-workstation.nix`: compose-hosts-from-cohesive-aspects | 1, 2, 3, 7 |
| 5a Priorities | the measured equal-priority collisions with differing contents, each resolved by `hiPrio`/`lowPrio` to today's winner | only the marked packages' priority and the profiles containing them; behaviour unchanged, shown by the content comparison | — | after 2-4 |
| 5b Order | the sort modules, keyed `gh-dash` bindings, the overlay list, launchd and stibnite slots | every toplevel and home: package order and the three bindings only, judged by `name-the-parts-of-base-and-ai`'s `drv-order-trace.py`; built profiles compared by content | `nixpkgs/compose.nix`, `home/development/gh-dash.nix`: none found | after 5a |
| 6 Parts lists resumed, then moves | `name-the-parts-of-base-and-ai` steps 2 (darwin `base`) and 3 (`ai`), names unchanged; the split home files of D2(e); then the darwin halves out of `nixos/` | none, after 5b; the structure check's entries declared | `hm-sops-bridge.nix`: filter-check-sources-for-substitution, name-the-parts-of-base-and-ai, seam-secrets-away-from-clan-vars | after 5b |
| 7 People's literals | O11 (`meta.username` defaults to the key), O22 (aggregate default), O03 (a per-user content constructor), O17 (resolved by O03), O04 (a clan user-instance constructor), O09 (the ssh-key sites `clan/inventory/services/users/cameron.nix:45`, `tara.nix:38`, `darwin-workstation.nix:80`, `system/admins.nix:20` read the people registry) | none | `darwin-workstation.nix`: compose-hosts-from-cohesive-aspects | 1-4 |
| 8 Deploy | the enabled hosts, then the standalone homes in use | — | — | after 5b-7 |
| 9 Re-measure | both sets, both arms, three runs each | none | — | after 8 |

Each named open change is rebased past or onto the step that shares its file, whichever lands second; the step's pull request description names them.

`name-the-parts-of-base-and-ai`: its NixOS step is committed; its darwin and `ai` steps are held until step 5b lands, then resume with their names; their per-step deploys fold into step 8.

Audit items not planned elsewhere: O03, O04's constructor, O09's remaining sites, O11, O17, O22 fall into step 7; O12 into step 2 and every check this change adds; L5 into step 5b; O46's residue stays out.

**Boundary** (source-versus-delivered): steps 1-4, 6 and 7 change the fleet description only; steps 5a and 5b change what is built (5a priorities, 5b order), and take effect at step 8.

## Risks / Trade-offs

- [Risk] Sorting the system path changes which package provides a file. → Mitigation: step 5a measures every equal-priority collision with differing contents on every enabled host and fixes today's winner by priority before 5b sorts; 5b is accepted only when every path resolves to a file of the same content as at its parent.
- [Risk] The route judge forces each host's import tree in the machine checks. → Mitigation: the tree is already built by the same evaluation; the judge's cost is measured with `just eval-cost` on one host before it is registered, and reported before any run expected to exceed five minutes.
- [Risk] Integrated homes have no graph of their own. → Mitigation: their composition is stated as the standalone home's plus the attachment's extra imports; a module reaching an integrated home by another route is not judged, and the entry point says so.
- [Trade-off] No committed composition file: a reader without a shell still reads to list a host's composition. → Accepted: committing it would make every module-adding change regenerate up to 30 files; the tree arm of the measure records the cost.
- [Trade-off] The tree keeps several principles and the class halves of a concern stay apart. → Accepted: the measured costs are elsewhere; D3's evidence rule says when to revisit.
- [Risk] Three runs per task can agree by chance. → Mitigation: a target is met only when every run cites the stated rule's file.

## Migration Plan

1. Land steps 1-4 and 7 in any order (2 before 3 for `checks/machines.nix`), each on an empty comparison apart from declared checks.
2. Land step 5a with its allow-list (the profiles containing a re-prioritised package), then 5b with its allow-list (every toplevel, every standalone home, their machine and home checks), the order trace and the content comparison.
3. Land step 6 on an empty comparison.
4. **[operator]** Deploy the enabled hosts: cinnabar and magnetite (cloud, `enabled = true` in `lib/cloud-machines.nix`), pyrite, then stibnite, argentum and rosegold; activate each standalone `crs58@*` or `cameron@*` home in use. Each deploy checks that the host runs the system its branch evaluates to, that a Mac's deploy deletes no account (A377), and reads every alert posted since it began. electrum, galena and scheelite are `enabled = false` (provisioned on demand): their derivations change and nothing is deployed; they take the new order when next provisioned. blackphos is a reserved name with no machine (`lib/observability-hosts.nix:164-167`): its derivation changes and nothing is deployed.
5. Re-measure (step 9).
6. Rollback: revert a step and redeploy, or roll a host back a generation; only steps 5a and 5b change a delivered system, in priority metadata and order only.

## Open Questions

1. Should each host's registry record move into its machine directory, so one file per host holds its facts? Recommended: no. The central registry is where lookups land in one read; the treatments of D2(d), not the move, remove the unenforced lists.
2. Should the composition be committed per host as well as rendered by command, for readers without a shell? Recommended: no, for the regeneration cost argued in D2(g); revisit if the tree arm of the re-measure shows E1 worse than the baseline.
3. pyrite receives `base-initrd-networking` and disables it with `mkForce false`, still receiving its virtio initrd modules and initrd host-key secret; should pyrite stop receiving it? Recommended: yes, as its own change, deployed to pyrite.
4. Should `r2-usage` and `postgresql-backup` be imported only by the hosts that use them? Recommended: yes, as its own derivation-checked change.
5. Should darwin `homebrew` and `system-defaults` be a workstation role rather than `base`? Recommended: yes when a Mac that is not a workstation joins; today every Mac is one.
6. Should scheelite, which the registry marks `checked = false`, stay outside the machine checks, so that a fact required of every NixOS host needs a standalone check? Recommended: yes for now; the rule names the exception.
7. Should `name-the-parts-of-base-and-ai`'s darwin and `ai` steps wait for the order step? Recommended: wait; they then change no derivation and share the one deploy.
8. Should the five generators using the older hand-entry shape (a script that exits 1, set with `clan vars set`: nixbot, renovate, gitea-mq, gitea, niks3) move to the prompt shape? Recommended: no, not in this change; each moves when its service next changes, with its re-prompt planned.
9. Should a new server's type and boot mode, `stateVersion` and facter file follow a stated rule (for example, copy electrum's UEFI template; the current release's `stateVersion`)? Recommended: yes, the owner states it and step 4 writes it into the onboarding guide; until then the guide names both templates.
10. Should a host fail a check when a declared hand-entered secret has no committed value? Recommended: yes, as a separate change, since none does today.
11. What is the justfile's `nixos_hosts` list for (it names cinnabar, electrum, galena and scheelite, not magnetite or pyrite)? Recommended: derive it from the registry's cloud hosts if it means "cloud NixOS hosts other than magnetite", or delete it if unused.
12. Should archived OpenSpec plans be hidden from default searches with an `.ignore` entry (Q17's mislead), leaving them reachable with `rg --no-ignore`? Recommended: yes.
