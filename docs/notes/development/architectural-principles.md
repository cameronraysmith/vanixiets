# Architectural principles for vanixiets

This document carries five generative principles for vanixiets' flake / module architecture, eight tactical corollaries derived from them, and a register of current opportunities to apply them more fully.
The principles are durable; the opportunities close as work lands and new ones may surface as the codebase evolves.

It is intended to be read at /session-plan time when the actor-critic / worker-orchestrator pair schedules architectural improvement work.
The principles, corollaries, opportunities, and their planned decomposition into OpenSpec changes are all included inline so the document is self-contained.

## Provenance

The principles were distilled during the typed-`flake.users` refactor (PR #1938, merged 2026-05-02 at commit 8e334238).
Reviews R5-A through R5-D evaluated that PR along type-safety, dendritic-fidelity, adversarial whole-branch, and regression-probe axes; R6 swept the post-merge codebase against the resulting rubric.
The eight tactical corollaries were the original session-end synthesis; the four principles are the limit-point compression of those eight, with each corollary instantiating one principle.
The 22 opportunities first catalogued instantiate one or more principles and have current-shape, aligned-shape, and approach captured inline.
The den-readiness audit of the repository (2026-11-26) re-verified them, resolved or corrected several, and added the findings listed under "Den-readiness findings"; P5 is the principle that derives the findings P1–P4 could not.

## The five principles

These are the generative axioms.
Applied iteratively, they produce the architectural pattern; each tactical corollary and each opportunity entry is an instantiation.

### P1. Derive, don't enumerate

Construction recipes, default values, and cross-cutting bindings are derivations from typed slots, not literals restated at each callsite.
The recipe is a derivation from typed inputs; lift it once and let callers read the derived value.
Default values that depend on a submodule's own attribute key derive parametrically via the function form `({ name, config, ... }: ...)` rather than being hardcoded per-instance.

### P2. Type at the natural boundary; nothing more, nothing less

Type discipline lives at the field where consumers will fail-loudly on malformed inputs — typically the consumer side of an upstream-native registry — with exactly the slots that have real consumers.
Don't wrap upstream-native registries in parallel typed layers when typing the consumer field via `listOf deferredModule` against the existing source achieves the same eval-time error semantics without duplication.
Don't add typed fields without a current consumer; speculative slots are debt the type system cannot tell you to remove.

### P3. Resolve relations and ownership at one site, then propagate uni-directionally

Every cross-cutting relationship (alias→target, host→user, controller→peers) and every authoritative datum (SSH keys, sops age IDs, network addresses) has exactly one resolution / write site; consumers read from there.
When authority and data ownership both apply (clan inventory creates the user account; the typed registry holds identity data), the authoritative consumer reads from the data registry rather than duplicating or writing back.
Bidirectional flow is the smell that indicates a missing abstraction layer.

### P4. Types are evidence — both falsifying and falsifiable

A type, assertion, or structural check has epistemic content only when paired with a captured demonstration that it rejects what it claims to forbid.
Type-system rejections are evidence about design, not obstacles to bypass: when the type system rejects a shape, the design is usually in the wrong namespace and the corrective move is to migrate, not to layer workarounds.
Pattern: a sibling check derivation that uses `builtins.tryEval` against a phantom and asserts `success = false`, returning an empty derivation on test pass.

### P5. Composition is order-free and demand-driven; a module never reads another entity's evaluated config

Importing a set of modules gives the same result whatever order they are imported in: where order matters it is declared at one site (a named `mkOrder` position), and where a module may be imported twice its identity is declared (a `key`), never left to import order.
Evaluating one entity — a host, a home, a check — costs only that entity: a module reads committed data or a pure `flake.lib` value, never another host's, user's or feature's evaluated configuration.
Evidence: hosts read other hosts' evaluated configuration to obtain committed public keys (O18; measured at about 0.98 s CPU, 3.7 million thunks and 423 MB of the 10.97 s stibnite toplevel, see [eval-cost-baselines.md](eval-cost-baselines.md)), dual-exported home modules carry no `key` (O37), and the darwin deploy record is last only by import order (O38).

## Eight tactical corollaries

These are the concrete tactics each principle generates.
Listed by parent principle.

### C1 (P1). Smart constructors instead of recipes at each callsite

When N call-sites carry copies of the same construction, the construction belongs as a derived / `readOnly` attribute on the type itself, not as a function each caller invokes.

### C2 (P1). Parametric defaults via the submodule's `name` arg

When a submodule's default behavior depends on the key it lives under, use `attrsOf (submodule ({ name, config, ... }: ...))` and derive defaults parametrically.
Defaults belong at the slot, not at the consumer.

### C3 (P2). Type the consumer field, not the registry

When a typed-registry need surfaces, audit upstream-native typed registries before building a parallel one.
flake-parts' `flake.modules.<class>.<name>` is already typed as `lazyAttrsOf (lazyAttrsOf deferredModule)` and supports multi-writer dendritic composition; type discipline at the consumer field via `listOf deferredModule` against the existing native registry achieves the same eval-time error semantics as a parallel typed-wrapper layer, without the duplication cost.

### C4 (P2). No speculative slots without a real consumer

The cheap test: name the consumer file:line.
If you can't, don't add the slot.
A field that exists for hypothetical future use is debt; the type system can't tell you to remove it because nothing uses it.

### C5 (P3). Eager symmetry beats leaky dispatch

In registry-and-consumer designs, prefer symmetric keys — every consumer reads the same way regardless of canonical-vs-alias status.
If aliases must inherit, propagate eagerly at one site and let consumers read alias-keyed slots blindly.
The alias→target relationship resolves at exactly one place.

### C6 (P3). Authority and data ownership distinction

When authority and data ownership both apply, distinguish them.
A consumer with authority should read FROM the data registry, not write into it or duplicate it.

### C7 (P4). Falsifiability requires a captured negative control

Every structural check earns its keep only when paired with a captured demonstration that it fails under a plausible incorrect implementation.
If you cannot construct a falsifying input, the check might be a tautology and you cannot tell.

### C8 (P4). Type-system errors are messengers; don't work around them

Workarounds layered atop type-system constraints are signals that the design is in the wrong namespace.
Migrate to a namespace where the natural shape is a typed attrset of submodules.

### Procedural meta-corollary

When a typed-registry need surfaces, run the upstream-native audit *before* implementation, not after.
Across the nix-0pd cluster, three architectural revisions superseded each other before consumer-field-typing landed; nine commits of work were retired by the architectural pivot at .16.
Five minutes of `rg 'options\.flake\.modules' ~/projects/nix-workspace/flake-parts/extras/` would have foreclosed the entire `flake.profiles` thread.

## Opportunities to apply these principles

43 opportunities are catalogued: the 22 of the post-PR-#1938 pass less the three removed (O07, O08, O13), and 24 from the den-readiness audit (O23–O46); O14 and O16 are resolved and await removal.
By principle: P1 = 21 entries, P2 = 9, P3 = 14, P4 = 3, P5 = 4, no principle = 1 (some entries cite several).
By severity: HIGH = 7, MEDIUM = 23, LOW = 10, WATCH = 1, RESOLVED = 2.

Severity rubric describes leverage:
- HIGH — replicates a pattern the cluster already proved was wrong, or actively misleads readers
- MEDIUM — focused tranche; not blocking new work but degrading every change in the area
- LOW — visible deviation, address opportunistically when touching the area
- WATCH — borderline; flagged for awareness, may be intentional

The cross-cutting clusters where one fix lands many entries:

- **Smart host constructor** (O01, O02, O09, O19, O20) — superseded. A `flake.lib.mkMachine{Darwin,NixOS}` constructor is no longer planned; the host recipe is instead derived from a typed host record (O10, O23) plus shared aspects (O01's home-manager integration, O19's darwin workstation template, O28's cloud-server aspects).
- **Smart user content constructor** (O03, O11, O22, plus tail of O09) — replaces 5 per-user `default.nix` files with thin `mkUserContent` calls and removes redundant `username` / `aggregates` literals from `meta.nix`. ~5 files × ~40 lines.
- **Smart inventory user-instance constructor** (O04, O20) — collapses three near-clone clan inventory user services into one. 3 files × ~50 lines.
- **Typed host registry** (O10, O18, O23, O32, O33, possibly O21) — `flake.lib.hosts` already carries the mesh addresses (O07 and O08 were resolved by the OpenSpec change `migrate-mesh-to-tincr`, CAM-109) and the darwin SSH host keys; the remaining work types it as one record per host and derives the system, inventory class, role membership and lifecycle facts from it.

### Den-readiness findings

The den-readiness audit (2026-11-26) verified these findings; each is folded into the entry it extends or is an entry of its own.
Its finding on stale documents (ADR-0018/0019/0020, the READMEs and this document) is closed by the change that commits this list, establish-refactor-oracle, and has no entry.

| Audit | Finding | Location | Principle | Entry |
|---|---|---|---|---|
| A1 | Host registry untyped (`lazyAttrsOf raw`) with sentinel fields | `modules/lib/option.nix:3-6`, `modules/lib/hosts.nix` | P2, P4 | O10 |
| A2 | System and class encoded four ways; name-only asserts | `modules/checks/machines.nix`, `-darwin` suffix tests, `nixpkgs.hostPlatform` in each host | P1, P3 | O23 |
| A3 | Three host↔user relations restated in four to seven places | `modules/lib/hosts.nix`, `modules/clan/inventory/services/users/`, host bodies, `modules/checks/home.nix` | P1, P3 | O04 |
| A4 | Cross-host evaluated-config reads | `modules/system/ssh-known-hosts.nix`, `modules/machines/darwin/stibnite/default.nix` | P3, P5 | O18 |
| A5 | Vars layout read ad hoc | `modules/clan/inventory/services/tincr.nix`, `modules/darwin/fleet-services-trust.nix`, about fifteen readers | P3 | O24 |
| A6 | No seam for secret consumption; features reach into each other's generators | `modules/nixos/nixbot.nix`, `modules/nixos/matrix.nix`, `modules/home/development/vcs-signing.nix` | P3 | O25 |
| A7 | Ambient `flake` specialArg with an order-dependent merge | `_module.args.flake` in nine hosts; `extraSpecialArgs.flake` in seven files | P1, P3 | O20 |
| A8 | Home-manager integration block repeated six times | the three user services, `modules/darwin/laptop.nix` (now `modules/darwin/darwin-workstation.nix`), stibnite, blackphos | P1 | O01 |
| A9 | Magnetite body holds service wiring | `modules/machines/nixos/magnetite/default.nix` | P1 | O26 |
| A10 | Cinnabar features keyed to the host | `modules/machines/nixos/cinnabar/` (each feature now under its own key, O27) | P1 | O27 |
| A11 | Cloud-server boilerplate repeated five times | the five cloud servers' `default.nix` | P1 | O28 |
| A12 | Host data written as priority fights | `modules/darwin/base.nix`, `modules/darwin/laptop.nix` (now `modules/darwin/darwin-workstation.nix`), host bodies | P1 | O02 |
| A13 | Darwin host template drift | `modules/machines/darwin/{blackphos,stibnite}/default.nix` copy `modules/darwin/laptop.nix` (now `modules/darwin/darwin-workstation.nix`) | P1 | O19 |
| A14 | Double opt-in and dead flags | host bodies, `modules/darwin/profile.nix` (deleted) | P2 | O05 |
| A15 | Host literal in a user module | `modules/home/users/crs58/default.nix` | P3 | O29 |
| A16 | Omnigent worker relation hand-copied | `modules/clan/inventory/services/omnigent.nix`, `modules/lib/fleet-deployer.nix` | P3 | O30 |
| A17 | Person and account vocabulary; file and key mismatch | `modules/lib/commit-signing.nix`, `modules/home/ai/agent-telemetry.nix`, `modules/system/stibnite-access.nix` | P3 | O31 |
| A18 | Role membership hand-resolved; decorative and homonym tags | `modules/lib/fleet-topology.nix`, `modules/clan/inventory/` | P3 | O32 |
| A19 | Lifecycle and cloud facts scattered | `modules/lib/hosts.nix`, tincr peers, `modules/lib/observability-hosts.nix` | P1, P2 | O33 |
| A20 | Obligation judges wired by hand | `modules/checks/machines.nix` | P1 | O34 |
| A21 | Two pure-judge check conventions | the `misjudges` fixture checks, `modules/lib/mk-eval-check.nix` | P1 | O35 |
| A22 | Redundant system double gates | `modules/checks/{pyrite-audio,mesh-hosts-obligations,sops-correspondence}.nix` | P1 | O36 |
| A23 | Dual-exported modules have no `key` | `modules/home/terminal/`, `modules/home/**/direnv.nix`, `agents-md.nix` | P5 | O37 |
| A24 | Deploy-record order rests on import order | `modules/system/deploy-record.nix` | P5 | O38 |
| A25 | Extra nixpkgs instantiations in tests | `modules/vm-tests/`, `modules/checks/{omnigent-workers,devin-worker}.nix` | P1 | O39 |
| A26 | Unused import-from-derivation `patched` channel | `modules/nixpkgs/overlays/channels.nix` | P2 | O40 |
| A27 | otel-collector file holds three units | `modules/clan/services/otel-collector/flake-module.nix` (now `agent.nix`, `ingress.nix`, `service.nix` and `_shared.nix` in that directory) | no principle | O41 |
| A28 | Untyped envelope and host-facts schemas | `modules/clan/services/otel-collector/flake-module.nix` (the envelope budget now in `_shared.nix`), `modules/lib/observability-hosts.nix` | P2, P4 | O42 |
| A29 | ZFS boot invariants written fourteen times | `modules/machines/nixos/magnetite/default.nix` | P1 | O43 |
| A30 | `base` and `homeManager.ai` have no named includes | the `darwin.base`, `nixos.base` and `ai` contributors | P2 | O44 |
| A31 | `darwin/caches.nix` duplicates `system/caches.nix` | `modules/darwin/caches.nix` (deleted) | P1 | O45 |
| A32 | Magnetite-shared facts read from the host in tests | `modules/vm-tests/{greptimedb-pipeline,fleet-ingress}.nix` | P5 | O46 |

### O01 [P1, P3] [HIGH] Cross-host duplication of `_module.args.flake`, `flakeForHomeManager`, and home-manager wiring block in every host module

- Locations:
  - `modules/machines/darwin/argentum/default.nix:8-15, 25, 140-156`
  - `modules/machines/darwin/blackphos/default.nix:8-15, 25, 148-162`
  - `modules/machines/darwin/rosegold/default.nix:8-15, 25, 140-156`
  - `modules/machines/darwin/stibnite/default.nix:8-15, 25, 243-265`
  - `modules/machines/nixos/cinnabar/default.nix:6-10, 34, 97-100`
  - `modules/machines/nixos/electrum/default.nix:6-10, 33, 99-102`
  - `modules/machines/nixos/galena/default.nix:6-10, 32, 96-103`
  - `modules/machines/nixos/magnetite/default.nix:7-9, 41, 115-118`
  - `modules/machines/nixos/scheelite/default.nix:9-13, 36, 101-108`
- Current shape: every host module restates four pieces of identical glue — `let flakeModules = config.flake.modules.<class>;`, `let flakeUsers = config.flake.users;` (and on darwin `flakeForHomeManager = config.flake // { inherit inputs; }`), `_module.args.flake = inputs.self;`, and the home-manager block (`useGlobalPkgs`, `useUserPackages`, `backupFileExtension`, `extraSpecialArgs.flake = flakeForHomeManager;`).
- Why this matters: P1 — the construction recipe is restated 9 times rather than derived once. P3 — `inputs.self` and `config.flake` are the same value via different evaluation contexts; recomputing the splice at every host site distributes responsibility for the same identity across 9 sites.
- Approach: introduce a base `flake.modules.<class>.machine-base` (or `flake.lib.mkMachineHomeManagerInfra { class }`) that sets `_module.args.flake`, the home-manager infrastructure block, and exposes `flakeUsers` / `flakeModules` as a smart constructor. Hosts then read `users.<u>.imports = flakeUsers.<u>.modules` only.
- Dependencies: O02 (host docs block). Landing both at once gives clean per-host files of ~50 lines instead of ~150.
- Den-readiness finding: **Home-manager integration block repeated six times** (A8). The integration block (`useGlobalPkgs`, `useUserPackages`, `backupFileExtension`, the home-manager module import) is written in the three clan user services, `modules/darwin/laptop.nix` (now `modules/darwin/darwin-workstation.nix`), stibnite and blackphos; one `{nixos,darwin}.home-manager-integration` aspect replaces them, keeping the machine-level imports that deduplicate catppuccin. Closed by declare-host-user-relations-once.

### O02 [P1] [MEDIUM] Cross-darwin-host duplication of documentation override block

- Locations:
  - `modules/machines/darwin/argentum/default.nix:42-48`
  - `modules/machines/darwin/blackphos/default.nix:44-50`
  - `modules/machines/darwin/rosegold/default.nix:42-48`
  - `modules/machines/darwin/stibnite/default.nix:49-55`
- Current shape: every darwin host repeats the same 7-line `srvos.server.docs.enable + documentation.* + programs.{info,man}.enable = lib.mkForce true` block.
- Why this matters: P1 — recipe at every callsite when the four laptop hosts share an "isDesktop" property already.
- Approach: move into a darwin module conditioned on `config.custom.profile.isDesktop` (or a new `flake.modules.darwin.docs-for-laptops` aggregate), then drop the 7-line block from each host.
- Den-readiness finding: **Host data written as priority fights** (A12). Darwin `stateVersion` 5 in `modules/darwin/base.nix` is forced to 4 in `modules/darwin/laptop.nix`, blackphos and stibnite; the documentation block above is three `mkForce` sites (`laptop.nix`, blackphos, stibnite); zram and GRUB are forced over base. Bases use `mkDefault` and hosts write plain values, with `stateVersion` in the host record; the `isDesktop` approach above is superseded, since `custom.profile` has no reader (O05).
- Status: partly resolved by compose-hosts-from-cohesive-aspects (pull request 4453). `system.stateVersion` is read from `flake.fleet.hosts.<host>.stateVersion` in `modules/darwin/base.nix` and `modules/system/nix-settings.nix`, and no host writes it; `modules/system/zram-swap.nix` sets `zramSwap.memoryPercent = lib.mkDefault 100` and magnetite writes 150 plainly; electrum, galena and scheelite write `boot.loader.grub.enable = false` plainly. `modules/darwin/darwin-workstation.nix` writes the seven documentation options plainly for argentum, rosegold and blackphos. stibnite does not import that aspect and keeps its seven `lib.mkForce true` lines (`modules/machines/darwin/stibnite/default.nix:50-56`), because importing it reorders stibnite's `users.knownUsers` and colima's system packages (that change's design, Open Question 11).

### O03 [P1] [HIGH] Per-user content `default.nix` recipe is 90% identical across 5 users; sopsFile path hardcodes attribute key

- Locations:
  - `modules/home/users/christophersmith/default.nix:1-56`
  - `modules/home/users/janettesmith/default.nix:1-54`
  - `modules/home/users/raquel/default.nix:1-59`
  - `modules/home/users/tara/default.nix:1-47`
  - `modules/home/users/crs58/default.nix:1-95` (extended with extra slots, but shares the pattern)
- Current shape: each per-user `default.nix` is structurally `let content = { ... }: { home.stateVersion = "23.11"; home.packages = [...]; sops = { defaultSopsFile = flake.inputs.self + "/secrets/home-manager/users/<literal>/secrets.yaml"; secrets = {...}; templates."allowed_signers" = { content = "${flake.users.<literal>.meta.email} namespaces=\"git\" ${...}"; }; }; programs.git.settings = { user.name = flake.users.<literal>.meta.fullname; user.email = flake.users.<literal>.meta.email; }; }; in { flake.users.<literal>.contentPrivate = content; }`. The four secondary users differ only in the secret list and home.packages list.
- Why this matters: P1 — recipe instantiated 5 times with literal restating of the attribute key, when the typed registry already passes `name` to the submodule.
- Approach: provide a `flake.lib.mkUserContent { name, packages, secrets, secretsRepoSubpath ? name }` smart constructor that computes the sopsFile path, allowed_signers template, and git/jujutsu user from the `name` argument and the resolved `flake.users.${name}.meta`. Each per-user file becomes a 5-line invocation listing only its differences (secrets list, packages list).
- Dependencies: lands more cleanly after O11 (meta.username redundancy removed).

### O04 [P1, P3] [HIGH] `clan/inventory/services/users/{cameron,crs58,tara}.nix` are three near-clones of the same `extraModules` recipe

- Locations:
  - `modules/clan/inventory/services/users/cameron.nix:36-71`
  - `modules/clan/inventory/services/users/crs58.nix:31-58`
  - `modules/clan/inventory/services/users/tara.nix:27-54`
- Current shape: all three define `clan.inventory.instances.user-<u>` with identical boilerplate (`module = { name = "users"; input = "clan-core"; }`, `roles.default.settings = { user = "<u>"; share = true; prompt = false; ... }`, and an `extraModules` block wiring `users.users.<u>.shell = pkgs.zsh`, `users.users.<u>.openssh.authorizedKeys.keys = inputs.self.users.<u>.meta.sshKeys`, `programs.zsh.enable = true`, and the home-manager infra block). Differences: user shortname, machine list, group set.
- Why this matters: P1 — three files restate the same `extraModules` recipe; the user shortname is a literal in every reference instead of being derived from a key.
- Approach: introduce `flake.lib.mkClanUserInstance { name, machines, groups, shell ? "zsh" }` (or a typed `attrsOf submodule` field) that emits the inventory instance from a small record. Each user file becomes a `{ machines = [...]; groups = [...]; }` literal.
- Dependencies: independent.
- Den-readiness finding: **Three host↔user relations restated in four to seven places** (A3). Membership (the user services' `roles.default.machines`), primary user (`modules/lib/hosts.nix` and again in darwin host bodies) and the home-manager and sops-bridge attachments (host bodies, `modules/checks/home.nix`) are each written by hand. One per-(host, user) record with the role, bridge, extra imports and uid generates the user instances, `custom.laptop.primaryUser`, `hm-sops-bridge.users`, the home-manager imports and the checked users; this also closes O09, O15, the user half of O19, and O21. Closed by declare-host-user-relations-once.

### O05 [P2] [MEDIUM] `custom.profile.{isServer,isWorkstation,isHeadless}` declared with no consumer

- Location: `modules/darwin/profile.nix:21-39` (deleted by pull request 4462)
- Current shape: `options.custom.profile` declares `isDesktop`, `isServer`, `isWorkstation`, `isHeadless`. `rg` for `isServer|isWorkstation|isHeadless` returns hits only in the declaration site itself; only `isDesktop` is actually written by hosts.
- Why this matters: P2 — three of four slots are speculative; no consumer references them.
- Approach: drop the unused slots; keep only `isDesktop`. Or, if a future feature is genuinely planned, capture the intended consumer in the same commit that adds the slot.
- Den-readiness finding: **Double opt-in and dead flags** (A14). Features imported and then enabled again (memory-pressure guards, colima, shared reference tree, greptimedb, the stibnite session pair), always-true `custom.homebrew.enable` and `services.moshi-hook.enable`, and the whole of `custom.profile` (`modules/darwin/profile.nix`), which nothing reads. Delete the flags and the option; mergify, dnscrypt and k3s-server stay.
- Status: partly resolved by compose-hosts-from-cohesive-aspects (pull request 4462). `modules/darwin/profile.nix` and every `custom.profile` line are deleted, and so are the memory-pressure-guards, colima, greptimedb, `stibnite-session`, `stibnite-session-host`, `custom.homebrew` and `services.moshi-hook` flags; importing the module is the decision. `services.shared-reference-tree.enable` remains (`modules/system/shared-reference-tree.nix:31`), read by `modules/darwin/omnigent-host.nix:157` and set by `modules/vm-tests/shared-reference-tree.nix`.

### O06 [P2] [MEDIUM] `flake.modules.nixos.k3s-server` declares a typed option set with no host enabling it

- Location: `modules/nixos/k3s-server/default.nix:34-74` and `modules/nixos/k3s-server/{kernel,networking,packages}.nix`
- Current shape: the k3s-server option set is exhaustively typed (`enable`, `role`, `clusterInit`, `serverAddr`, `clusterCidr`, `serviceCidr`, `tokenFile`). `rg` for `k3s-server\.enable` outside `modules/nixos/k3s-server/` returns zero hits.
- Why this matters: P2 — the module is speculative scaffolding with no host writing `k3s-server.enable = true;`. The CLAUDE.md indicates active prototyping work for k3s, so this may be in-flight rather than abandoned.
- Approach: either (a) wire it into a host (presumably stibnite or an electrum-substitute) so the consumer/declaration ratio reaches 1+, or (b) move it under `docs/notes/` as a draft until a host imports it.
- Severity note: MEDIUM because the option set is large. An unimported module is never evaluated, so it adds no evaluation cost; the cost is only the reader's. Its consumers are planned (`docs/notes/development/kubernetes/decisions/ADR-007-nixos-vm-tests-for-k3s.md`), so it is kept as is for now.

### O09 [P3] [MEDIUM] Per-host SSH `users.users.<u>.openssh.authorizedKeys.keys` re-resolves `inputs.self.users.<u>.meta.sshKeys` instead of being centralized

- Locations:
  - `modules/machines/darwin/argentum/default.nix:116`
  - `modules/machines/darwin/blackphos/default.nix:123, 131`
  - `modules/machines/darwin/rosegold/default.nix:116`
  - `modules/machines/darwin/stibnite/default.nix:134`
  - `modules/machines/nixos/magnetite/default.nix:104` (uses `crs58` keys for the `builder` user)
  - `modules/system/admins.nix:20` (NixOS base)
  - `modules/clan/inventory/services/users/cameron.nix:46`, `tara.nix:36`
- Current shape: 9 distinct call sites duplicate the lookup `inputs.self.users.<u>.meta.sshKeys`. The post-PR-#1938 design reads from the typed registry (good), but every consumer site repeats the resolution rather than receiving a derived value.
- Why this matters: P3 — borderline. The data flow is correct (registry → consumer), but the *recipe* for resolving it is restated. Combined with O01, the host module already has `flakeUsers = config.flake.users;` in scope; users.users.<u> reads should occur once from a host helper, not 9 times.
- Approach: a `flake.lib.mkUserSystemEntry { name, uid, ... }` smart constructor would produce both the `users.users.<u>` and the `users.knownUsers` entry; the SSH keys would resolve internally. (See also O19/O21.)
- Closed with O04's per-(host, user) record, which resolves the keys once per attachment (declare-host-user-relations-once).

### O10 [P2, P4] [HIGH] `flake.lib` typed as `lazyAttrsOf raw` carries structurally typed values

- Locations:
  - `modules/lib/option.nix:3-7` (declaration)
  - `modules/lib/md-format.nix:6` (`flake.lib.mdFormat = lib.types.submodule (...)`)
  - `modules/home/users/lib.nix:28` (`config.flake.lib.mkUserIdentity = ...`)
- Current shape: the `flake.lib` namespace is typed as `lazyAttrsOf raw`. Per `reference_flake-lib-lazyattrsof-raw.md`, this rejects nested option declarations and forbids multi-file writes at the same nested path. The current contents (`mdFormat`, `mkUserIdentity`, `mkHome`, `mkStructuralCheck`, `mkEvalCheck`, `bitwardenSocketPath`) are flat top-level keys, so no collision occurs *today*.
- Why this matters: P2 / P4 — using `raw` as a permissive escape hatch for things that *could* be properly typed (a literal collection of typed helper functions and types). When the next nested registry need surfaces (e.g., a `flake.lib.policies.<x>`), the workaround pressure will repeat.
- Approach: watch only — no immediate breakage. If the next typed-registry need under `flake.lib` arises, prefer extracting to a top-level `options.flake.<x>` field with a proper submodule type rather than nesting under `flake.lib`. Per `feedback_no-parallel-typed-registries.md`, also consider whether the consumer field can be typed against the existing native registry instead.
- Dependencies: independent.
- Den-readiness finding: **Host registry untyped (`lazyAttrsOf raw`) with sentinel fields** (A1). `flake.lib.hosts` (`modules/lib/hosts.nix`) is the case this entry anticipated: a registry of host records under the untyped namespace, held together by name-only asserts. Add `options.flake.fleet.hosts = attrsOf (submodule …)` and keep `flake.lib.hosts` as a read-only view; keep `memoryGiB = "unknown"` as specified. Raised from WATCH to HIGH: it is the enabler of O23, O32 and O33. Closed by type-the-fleet-host-registry.

### O11 [P1] [MEDIUM] Per-user `meta.nix` redundantly sets `meta.username = "<attribute-key>"`

- Locations:
  - `modules/home/users/crs58/meta.nix:5` (`username = "crs58"`)
  - `modules/home/users/christophersmith/meta.nix:5` (`username = "christophersmith"`)
  - `modules/home/users/janettesmith/meta.nix:5` (`username = "janettesmith"`)
  - `modules/home/users/raquel/meta.nix:5` (`username = "raquel"`)
  - `modules/home/users/tara/meta.nix:5` (`username = "tara"`)
- Current shape: every per-user meta sets `meta.username` to a string equal to the attribute name under `flake.users.<name>`. The `flake.users` submodule is declared with `({ name, config, ... }: ...)` (lib.nix:42-43), so the canonical attribute key is already available as `name`.
- Why this matters: P1 — the parametric default should derive `username` from `name` so per-user files don't restate it; aliases-fold already overrides via `meta.username = alias` (aliases-fold.nix:17), so a `default = name;` for canonical entries is the missing default.
- Approach: in `modules/home/users/lib.nix`, change the `username` option from `mkOption { type = str; description = ...; }` to `mkOption { type = str; default = name; description = ...; }`. Drop the `username = "<literal>"` line from each per-user `meta.nix`.

### O12 [P4] [MEDIUM] Structure checks under `modules/checks/structure/` lack negative-control partners

- Locations:
  - `modules/checks/structure/flake-shape.nix:22-63` (2 mkCheck invocations: `structure-fleet`, `structure-home-configurations`)
- Current shape: two literal pins under `modules/checks/structure/` without a negative control. The other falsifiability controls now live inside their positive checks rather than in `*-neg` siblings: `home-module-exports` compares `_phantomEmpty` and `_phantomAuthored` alongside the real users (`modules/checks/validation.nix:99-110`), and the hm-sops bridge assertion is a bridge-file existence test in `modules/nixos/hm-sops-bridge.nix:79-80`.
- Why this matters: P4 — these checks compare the actual flake shape to the literal expected value, but if (for example) `lib.naturalSort` were silently broken or the `attrNames` accessor became case-insensitive, the check could pass for the wrong reason. A negative control would inject a phantom mismatch and verify the diff fails.
- Approach: where a pin's comparison could be subtly wrong, add phantom entries to the same `mkCheck` comparison, following `home-module-exports`, rather than a separate derivation.
- Severity note: MEDIUM rather than HIGH because the eval-time asserts in `modules/checks/machines.nix` already require the inventory, `clan.machines`, the per-class configurations and the machine directories to agree, so most drift surfaces without the pins. Still falsifiability discipline cluster.

### O14 [P1] [RESOLVED] `modules/checks/machines.nix` hardcodes the 4-machine NixOS list rather than deriving from registered configurations

- Resolution: `47d6cab5d` (programmatic per-system derivation) and `4e93c4e18` (partition machine checks by metadata); `modules/checks/machines.nix:15-30` now derives the NixOS and darwin host sets from the clan inventory's `machineClass`, excluding the `deferred` hosts. Remove after the next merge.

### O15 [P1, P3] [MEDIUM] hm-sops-bridge per-host invocation `hm-sops-bridge.users.<u> = { };` repeats across 5 hosts

- Locations:
  - `modules/machines/nixos/cinnabar/default.nix:92`
  - `modules/machines/nixos/electrum/default.nix:94`
  - `modules/machines/nixos/galena/default.nix:90, 91`
  - `modules/machines/nixos/magnetite/default.nix:110`
  - `modules/machines/nixos/scheelite/default.nix:95, 96`
- Current shape: every nixos host enables `hm-sops-bridge.users.cameron = { };` (and galena/scheelite add `hm-sops-bridge.users.tara = { };`). The bridge module's per-user assertion already validates `flake.users.<u>.meta.sopsAgeKeyId != null`. The set of users to enable could be derived from "every user with a non-null `sopsAgeKeyId` who has home-manager content on this host".
- Why this matters: P1 — recipe at each callsite. P3 — the relationship between "a host imports this user's home-manager content" and "this user needs the bridge enabled" should be expressed once, not 5+ times.
- Approach: default `hm-sops-bridge.users` to derive from `home-manager.users`'s set on this host, filtered by `flake.users.<u>.meta.sopsAgeKeyId != null`. Hosts then write `home-manager.users.<u> = ...` once and the bridge auto-enables.
- Closed with O04's per-(host, user) record, from which `hm-sops-bridge.users` is generated (declare-host-user-relations-once).

### O16 [P2] [RESOLVED] `flake.users.<u>.meta.githubUser` declared but no module reads it

- Resolution: the slot had a reader all along: `705d67875` reads it in `modules/home/development/git.nix:61-62` (`programs.git.settings.github.user`), and `e97c897f5` added the second reader at `modules/clan/inventory/services/omnigent.nix:30` (the worker's expected GitHub login). Remove after the next merge.

### O17 [P2] [LOW] `flake.users.<u>.meta.fullname` consumed by 5 sites; `meta.email` consumed by 9 sites — verify intentional

- Location: `modules/home/users/lib.nix:51-58`
- Current shape: `meta.fullname` referenced from 5 user `default.nix` files only (each user reads their own); `meta.email` from each user's `default.nix` and `templates."allowed_signers"`. Real consumers but only via per-user-self-references — the cross-cutting consumer is missing.
- Why this matters: P2 (very mild) — fields used only locally hint that the typed registry is doing less work than its surface area suggests. WATCH: this might be intentional if the centralization is *for future consumers* but expressed at the registry layer first.
- Approach: WATCH only. After O03 lands (the smart user-content constructor), these fields will have one canonical reader and the local-only-use pattern resolves.

### O18 [P3, P5] [HIGH] Static darwin SSH host pubkeys in `system/ssh-known-hosts.nix` declared inline rather than in the host registry

- Location: `modules/system/ssh-known-hosts.nix:79, 89, 99, 109, 123` (5 inline `publicKey = "ssh-ed25519 ..."` literals)
- Current shape: for darwin and pixel7 hosts, the SSH host public key is hardcoded next to the IPs. NixOS hosts derive their keys from `flake.nixosConfigurations.<host>.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value`.
- Why this matters: P3 — these are identity-bearing data values for darwin hosts, but they live as inline literals at one site. There's no second writer today (the literals are consumed only here), but beside the mesh addresses of the same hosts in `flake.lib.hosts`, the natural shape is a further field of `flake.lib.hosts.<host>`.
- Approach: extend `flake.lib.hosts` to carry these, as the mesh addresses already are.
- Dependencies: part of the typed host registry cluster.
- Status: resolved. The darwin half: `modules/lib/darwin-host-keys.nix`. The NixOS half (stop-reading-other-hosts-configs, CAM-133): `flake.lib.hostKeys` (`modules/lib/host-keys.nix`) reads each NixOS host's committed `vars/per-machine/<h>/openssh/ssh.id_ed25519.pub/value` through `flake.lib.vars`, untrimmed as clan reads it, and merges `flake.lib.darwinHostKeys`; `modules/system/ssh-known-hosts.nix` reads only `flake.lib.hostKeys` and takes no `flake` argument. Each NixOS host asserts that its own generated key equals its entry (`flake.lib.hostKeyObligations`, judged by `checks.x86_64-linux.host-key-obligations`). Moving the keys into a typed `flake.lib.hosts` record remains with the typed host registry cluster.
- Den-readiness finding: **Cross-host evaluated-config reads** (A4), resolved. The NixOS half read each NixOS host's key through `nixosConfigurations.<h>.config.clan.core.vars…value` (`modules/system/ssh-known-hosts.nix`, imported by all ten configurations), and stibnite read magnetite's evaluated configuration for one session key (`modules/machines/darwin/stibnite/default.nix`), measured at about 0.98 s CPU, 3.7 million thunks and 423 MB of the 10.97 s stibnite toplevel (`eval-cost-baselines.md`). Both now read the committed files, stibnite's through `flake.lib.vars.public`, with `checks.x86_64-linux.nix-builders-wiring` holding the session key to magnetite's generator. Closed by stop-reading-other-hosts-configs.

### O19 [P1] [MEDIUM] `users.users.<u> = { uid; home; shell; description; openssh.authorizedKeys.keys }` recipe repeated across darwin hosts with literals

- Locations:
  - `modules/machines/darwin/argentum/default.nix:111-124` (christophersmith uid=501 home=/Users/christophersmith), (cameron uid=502 home=/Users/cameron)
  - `modules/machines/darwin/blackphos/default.nix:118-132` (crs58 uid=502, raquel uid=506)
  - `modules/machines/darwin/rosegold/default.nix:111-124` (janettesmith uid=501, cameron uid=502)
  - `modules/machines/darwin/stibnite/default.nix:129-141` (crs58 uid=501)
- Current shape: 7 user blocks, each a 5-7 line recipe with literal `uid`, literal `home = "/Users/<name>"`, literal `description = "<name>"`, literal `shell`, and `openssh.authorizedKeys.keys = inputs.self.users.<u>.meta.sshKeys`. The home directory and description literally restate the attribute key, like O11.
- Why this matters: P1 — recipe at every callsite. `home` and `description` are derivable from the user shortname; only `uid` is genuinely host-specific.
- Approach: a `flake.lib.mkDarwinUser { name, uid, ... }` smart constructor produces the block; the recipe lives once.
- Dependencies: independent of O01, but lands cleanly together.
- Den-readiness finding: **Darwin host template drift** (A13). blackphos and stibnite copy `modules/darwin/laptop.nix`, which hard-codes cameron as admin with uid 502 while those hosts use crs58; a shared `darwin-workstation` aspect with the admin as a parameter, plus a per-host delta, replaces the copies. The user blocks themselves come from O04's per-(host, user) record. The user blocks are closed by declare-host-user-relations-once.
- Status of the template: partly resolved by compose-hosts-from-cohesive-aspects (pull request 4453). `modules/darwin/darwin-workstation.nix` defines `flake.modules.darwin.darwin-workstation`, which takes each Mac's human accounts from its attachments in `flake.fleet.hosts.<host>.users`; argentum, rosegold and blackphos import it and state only their deltas (host name, casks, dnscrypt-proxy). stibnite does not import it, for the reason in O02's status.

### O20 [P1, P3] [HIGH] Inventory `extraModules` block nested-function reconstruction of inputs.self splice repeated 3 times

- Locations:
  - `modules/clan/inventory/services/users/cameron.nix:62-67`
  - `modules/clan/inventory/services/users/crs58.nix:49-54`
  - `modules/clan/inventory/services/users/tara.nix:45-50`
- Current shape: all three inventory user services restate `extraSpecialArgs = { flake = inputs.self // { inherit inputs; }; }` inside an `extraModules` lambda; the same construct is also restated in every darwin host (O01).
- Why this matters: P1 — recipe duplication across 3 inventory files plus 4 darwin hosts (= 7 sites for the same splice). P3 — this is the same `inputs.self` identity flowing through 7 different writers, each creating the same `// { inherit inputs; }` synthesis.
- Approach: a `flake.lib.flakeForHomeManager = inputs.self // { inherit inputs; };` (or pre-baked attribute on the flake) computed once. Consumers reference it.
- Den-readiness finding: **Ambient `flake` specialArg with an order-dependent merge** (A7). The splices are not the same value: `extraSpecialArgs.flake` is `config.flake // { inherit inputs; }` in `modules/darwin/laptop.nix` (now `modules/darwin/darwin-workstation.nix`), stibnite, blackphos and `mk-home.nix`, but `inputs.self // { inherit inputs; }` in the three user services, and home-manager types it `types.attrs`, so on stibnite, blackphos, argentum and rosegold the last writer wins. Raised to HIGH. Pick one value and set it once; the poisoned `flake` of `modules/checks/omnigent-workers.nix` needs a replacement guard first. Closed by declare-host-user-relations-once.

### O21 [P3] [WATCH] `home-manager.users.cameron = { imports = flakeUsers.cameron.modules; };` — alias resolution still requires consumers to know `cameron` exists in `flake.users` post-aliases-fold

- Locations:
  - `modules/machines/darwin/argentum/default.nix:155`
  - `modules/machines/darwin/rosegold/default.nix:155`
  - `modules/machines/nixos/cinnabar/default.nix:97-99`
  - `modules/machines/nixos/electrum/default.nix:99-101`
  - `modules/machines/nixos/galena/default.nix:96-98`
  - `modules/machines/nixos/magnetite/default.nix:115-117`
  - `modules/machines/nixos/scheelite/default.nix:101-103`
- Current shape: per `reference_aliases-fold-mechanism.md` post-A2, consumers read alias-keyed (`flakeUsers.cameron.modules`) and aliases-fold synthesizes the alias entry. This is the *fixed* dispatch pattern (no leakage). The remaining tension: each host still hardcodes the literal `cameron` (or `crs58` for legacy hosts) — the alias-vs-canonical relationship is encoded via *which literal the host writes*. A future host reorg requires touching every host file.
- Why this matters: P3 — borderline. The aliases-fold mechanism resolves the relationship symmetrically (good), but the *choice of which literal each host writes* still encodes alias-vs-canonical by external knowledge (the comments at sites all say "cameron is an alias for crs58"). The alias-target relationship is authoritative in `flake.userAliases`, but each host independently re-decides whether to write `cameron` or `crs58`.
- Approach: WATCH. May be intentional — the comment at each site indicates this is *consciously* alias-keyed and the orchestrator (clan inventory's user service) decides the binding. Possible future refinement: a `users` field on `flake.lib.hosts.<host>` that resolves through aliases-fold, removing per-host decisions.
- Dependencies: the typed host registry cluster (`flake.lib.hosts`).
- Closed with O04's per-(host, user) record, which names each host's users once (declare-host-user-relations-once).

### O22 [P1] [LOW] Per-user `aggregates` lists are 90% identical across 5 users but each is restated as a literal

- Locations:
  - `modules/home/users/christophersmith/meta.nix:14-23`
  - `modules/home/users/janettesmith/meta.nix:14-23`
  - `modules/home/users/raquel/meta.nix:14-23`
  - `modules/home/users/tara/meta.nix:14-23`
  - `modules/home/users/crs58/meta.nix:15-25`
- Current shape: four secondary users share an identical 8-element aggregate list (`base-sops core development packages shell terminal tools agents-md`). crs58 adds `ai`. Each meta file restates the literal list.
- Why this matters: P1 — recipe at every callsite. A sensible default ("standard user aggregates") could live on the typed registry, with users opting *in* to extras (`ai`) or out of specific entries.
- Approach: add `default = with config.flake.modules.homeManager; [ base-sops core development packages shell terminal tools agents-md ];` on the `aggregates` option in `modules/home/users/lib.nix`. Users explicitly extend (`aggregates = defaults ++ [ ai ];`) or override.

### O23 [P1, P3] [HIGH] System and class encoded four ways; name-only asserts

- Den-readiness finding: **System and class encoded four ways; name-only asserts** (A2).
- Locations: `modules/checks/machines.nix` (the Nix system table and asserts); the `-darwin` suffix tests in `modules/lib/commit-signing.nix`, `modules/checks/omnigent-fleet-obligations.nix`, `modules/system/deploy-record.nix`, `modules/system/harmonia-gc.nix`, `modules/lib/mesh-hosts.nix`; the `platform` of `modules/lib/observability-hosts.nix`; `nixpkgs.hostPlatform` in each host module and `modules/darwin/laptop.nix:69`.
- Current shape: a host's kind is written as a class, a Nix system, an inventory class and a collector platform, and the asserts compare names only.
- Why this matters: P1 — the same fact restated; P3 — no single resolution site, so a drift in one table goes unnoticed.
- Approach: declare `system` once in the typed host record (O10); derive the system table, the inventory `machineClass`, the NixOS deploy target, `nixpkgs.hostPlatform` and the class; replace the suffix tests; filter out the android members.
- Closed by type-the-fleet-host-registry.

### O24 [P3] [MEDIUM] Vars layout read ad hoc

- Den-readiness finding: **Vars layout read ad hoc** (A5).
- Locations: `modules/clan/inventory/services/tincr.nix` (beside `getPublicValue` in `modules/clan/services/tincr/flake-module.nix`), `modules/darwin/fleet-services-trust.nix`, `modules/home/users/crs58/default.nix`, `modules/nixos/workstation-ca-trust.nix`, magnetite's address read twice in `modules/checks/otel-collector-{config,darwin}.nix`, and existence, recipient and hash reads in about ten more files.
- Current shape: the committed `vars/` tree's layout is written out by hand at every reader.
- Why this matters: P3 — the layout has one owner, clan, but every reader re-derives it.
- Approach: a `modules/lib/vars.nix` accessor (`public`, `exists`, `isRecipient`, `relPath`) built on the existing `varPath`, keeping each reader's trimming behaviour.
- Closed by stop-reading-other-hosts-configs.

### O25 [P3] [MEDIUM] No seam for secret consumption; features reach into each other's generators

- Den-readiness finding: **No seam for secret consumption; features reach into each other's generators** (A6).
- Locations: `modules/nixos/nixbot.nix` reads niks3's generator, `modules/nixos/matrix.nix` reads kanidm's, `modules/home/development/vcs-signing.nix` and `modules/home/ai/omnigent/credentials.nix` read the host's `osConfig.clan`; generator names passed as settings in `modules/clan/services/{hermes-agent,openclaw}/flake-module.nix`.
- Current shape: about 55 files declare or read `clan.core.vars` directly.
- Why this matters: P3 — secret declaration and consumption have no single resolution site; replacing clan vars would touch every feature.
- Approach: a `vanixiets.secrets.<name>` option, the only writer and reader of `clan.core.vars`, propagated to homes through the sops bridge, migrated one feature at a time with generator names, owners, modes and sharing unchanged.
- Closed by seam-secrets-away-from-clan-vars.

### O26 [P1] [MEDIUM] Magnetite body holds service wiring

- Den-readiness finding: **Magnetite body holds service wiring** (A9).
- Location: `modules/machines/nixos/magnetite/default.nix` (at the audit, about 520 lines of omnigraph, GreptimeDB, Perses and fleet-alert generators, credentials and services).
- Why this matters: P1 — a host should be the list of capabilities it runs plus what is particular to it; service wiring in the host body cannot be reused.
- Approach: move each block to a new `<svc>-server` aspect in its feature file, never into the site-neutral `<svc>` key the runtime tests import; credential-holder assertions stay at host scope.
- Status: resolved by compose-hosts-from-cohesive-aspects (pull request 4461). The wiring is in `modules/nixos/{perses,fleet-alert,omnigraph,greptimedb}-server.nix`, which magnetite imports; the site-neutral `perses`, `fleet-alert`, `omnigraph` and `greptimedb` keys the runtime tests import are unchanged, and the credential-holder and unit-relation assertions stay in magnetite's `default.nix`.

### O27 [P1] [MEDIUM] Cinnabar features keyed to the host

- Den-readiness finding: **Cinnabar features keyed to the host** (A10).
- Location: the feature files under `modules/machines/nixos/cinnabar/`, each of which assigned `flake.modules.nixos."machines/nixos/cinnabar"` at the audit.
- Why this matters: P1 — the features cannot be imported by any other host.
- Approach: re-key them as `flake.modules.nixos.<feature>` and have cinnabar import them; per-machine generators stay cinnabar's.
- Status: resolved by compose-hosts-from-cohesive-aspects (pull request 4443). The eight feature files assign `flake.modules.nixos.{caddy-root-ca,caddy-root-check,caddy,fleet-alert-deadman,matrix-server,ntfy-server,radicle-node,zt-dns-server}`, which cinnabar's `default.nix` imports; only `default.nix` and `disko.nix` assign the host key.

### O28 [P1] [MEDIUM] Cloud-server boilerplate repeated five times

- Den-readiness finding: **Cloud-server boilerplate repeated five times** (A11).
- Locations: the `10-uplink` network and ZFS `devNodes` in cinnabar, electrum, galena, scheelite and magnetite; `MaxAuthTries` in six NixOS hosts against `modules/darwin/base.nix`.
- Why this matters: P1 — a shared host shape restated per host.
- Approach: a Hetzner cloud-server aspect for cinnabar, electrum and magnetite and a separate GCP cloud-server aspect for galena and scheelite; `MaxAuthTries` moves into `nixos.base`; pyrite, which uses `by-id`, is excluded.
- Status: resolved by compose-hosts-from-cohesive-aspects (pull request 4453). `modules/nixos/hetzner-cloud.nix` (imported by cinnabar, electrum and magnetite) and `modules/nixos/gcp-cloud.nix` (galena and scheelite) hold the ZFS device nodes and the `10-uplink` network, and each asserts the host's `flake.fleet.hosts.<host>.cloud.provider`; `MaxAuthTries = 20` is in `nixos.base` (`modules/system/sshd-max-auth-tries.nix`).

### O29 [P3] [LOW] Host literal in a user module

- Den-readiness finding: **Host literal in a user module** (A15).
- Location: `modules/home/users/crs58/default.nix` (`studio.enable = elem hostName [ stibnite pyrite ]`).
- Why this matters: P3 — the host↔user relation decided inside the user's module rather than at the relation's one site.
- Approach: read the flag from O04's per-(host, user) record; default `services.jj-pr-sync.enable` to `!deploysWithoutScreenSession`.
- Closed by declare-host-user-relations-once.

### O30 [P3] [MEDIUM] Omnigent worker relation hand-copied

- Den-readiness finding: **Omnigent worker relation hand-copied** (A16).
- Locations: `modules/clan/inventory/services/omnigent.nix`, `requesterNames` in `modules/lib/fleet-deployer.nix`, the shared-reference-tree participants in magnetite, pyrite and stibnite.
- Why this matters: P3 — one relation (owner → hosts) written three times.
- Approach: declare `workers.<owner>.hosts` once and derive the inventory blocks, `requesterNames` and the participants; the literal check oracles stay literal.
- Closed by declare-host-user-relations-once.

### O31 [P3] [LOW] Person and account vocabulary; file and key mismatch

- Den-readiness finding: **Person and account vocabulary; file and key mismatch** (A17).
- Locations: `modules/lib/commit-signing.nix` (cameron → crs58) against `modules/home/ai/agent-telemetry.nix` (crs58 → cameron); `modules/system/stibnite-access.nix`, whose name does not match its keys.
- Why this matters: P3 — the person/account mapping is resolved in two directions at two sites.
- Approach: add `accountOf` beside `personOf` in one file and rename `stibnite-access.nix` to match its keys; no key is renamed.
- Closed by declare-host-user-relations-once.

### O32 [P3] [MEDIUM] Role membership hand-resolved; decorative and homonym tags

- Den-readiness finding: **Role membership hand-resolved; decorative and homonym tags** (A18).
- Locations: `modules/lib/fleet-topology.nix` against `modules/checks/zerotier-mss-clamp.nix` (which ignores the `all` tag); `.machines`-only readers in `modules/checks/zerotierone-controller.nix` and `modules/apps/omnigent-worker-login.nix`; the `controller` tag on both cinnabar (ZeroTier) and stibnite (deployment); the ZeroTier `allowedIps` literal.
- Why this matters: P3 — role membership resolved three ways, two of which miss tag members.
- Approach: one `flake.lib.inventoryMembers instance role`; derive `allowedIps` from class; rename stibnite's tag to `deployer-workstation`.
- Closed by type-the-fleet-host-registry.

### O33 [P1, P2] [MEDIUM] Lifecycle and cloud facts scattered

- Den-readiness finding: **Lifecycle and cloud facts scattered** (A19).
- Locations: blackphos as a "reserved name with no machine" in the tincr peers and `modules/lib/observability-hosts.nix` beside its machine directory; cloud memory hand-copied in `modules/lib/hosts.nix` from the server types in `modules/terranix/`.
- Why this matters: P1 — cloud memory restated by hand; P2 — distinct lifecycle facts (provisioned, checked, deferred, enabled) need distinct typed fields, not one enum.
- Approach: separate typed fields in the host record, `provisioned` derived from the inventory, and a server-type → memory table.
- Closed by type-the-fleet-host-registry.

### O34 [P1] [MEDIUM] Obligation judges wired by hand

- Den-readiness finding: **Obligation judges wired by hand** (A20).
- Location: `modules/checks/machines.nix` (eleven judges, each named in several places, plus `withNetworkTargets`).
- Why this matters: P1 — each new fleet rule edits one shared file in several places.
- Approach: a registry of `{ appliesTo; failures; }` folded by concatenation, each judge registering where it is defined.
- Closed by register-fleet-obligations.

### O35 [P1] [LOW] Two pure-judge check conventions

- Den-readiness finding: **Two pure-judge check conventions** (A21).
- Locations: nine fixture checks with a hand-copied `misjudges` filter (for example `modules/checks/mesh-hosts-obligations.nix`) against `modules/lib/mk-eval-check.nix`.
- Why this matters: P1 — one test shape restated.
- Approach: one evaluation-only judge check that reports per case.
- Closed by register-fleet-obligations.

### O36 [P1] [LOW] Redundant system double gates

- Den-readiness finding: **Redundant system double gates** (A22).
- Locations: `modules/checks/pyrite-audio.nix`, `modules/checks/mesh-hosts-obligations.nix`, `modules/checks/sops-correspondence.nix`, and the size-class entries that repeat their check's system condition.
- Why this matters: P1 — the same condition written twice.
- Approach: drop the inner gate.
- Closed by register-fleet-obligations.

### O37 [P5] [MEDIUM] Dual-exported modules have no `key`

- Den-readiness finding: **Dual-exported modules have no `key`** (A23).
- Locations: `modules/home/terminal/{fd,jq,ripgrep}.nix`, `direnv.nix`, `agents-md.nix`, `modules/home/atomic/default.nix`; claude-sandbox imports both names of one module.
- Why this matters: P5 — a module's identity rests on import paths, so importing it under both names may apply it twice.
- Approach: one `flake.lib.exportAs` that sets `key`, with the parameter for parameterised content, and one key spelling.
- Closed by compose-hosts-from-cohesive-aspects.

### O38 [P5] [MEDIUM] Deploy-record order rests on import order

- Den-readiness finding: **Deploy-record order rests on import order** (A24).
- Locations: `modules/system/deploy-record.nix` against same-priority `mkAfter` snippets in `modules/darwin/casks.nix`, `modules/darwin/fleet-services-trust.nix` and the dnscrypt module; `modules/darwin/laptop.nix` (now `modules/darwin/darwin-workstation.nix`).
- Why this matters: P5 — the record is last in the darwin activation script only because of import order.
- Approach: a `flake.lib.activationOrder` placing each snippet with `mkOrder`, and a "record is last" clause with a mutant in `deploy-record-order`. Declared to change the darwin activation scripts.
- Closed by compose-hosts-from-cohesive-aspects.

### O39 [P1] [MEDIUM] Extra nixpkgs instantiations in tests

- Den-readiness finding: **Extra nixpkgs instantiations in tests** (A25).
- Locations: eleven runtime tests' `nodePkgs` (for example `modules/vm-tests/greptimedb-pipeline.nix`), `modules/checks/omnigent-workers.nix`, `modules/checks/devin-worker.nix`.
- Why this matters: P1 — the package set is rebuilt per test instead of read from the fleet's.
- Approach: use the per-system fleet package set. Declared to change the runtime tests.
- Closed by register-fleet-obligations.

### O40 [P2] [LOW] Unused import-from-derivation `patched` channel

- Den-readiness finding: **Unused import-from-derivation `patched` channel** (A26).
- Location: `modules/nixpkgs/overlays/channels.nix`.
- Why this matters: P2 — an exported channel with no reader, documented as the way to patch a package although reading it would build during evaluation.
- Approach: drop `patched` and amend ADR-0017, which sanctions the channel layer.
- Closed by register-fleet-obligations.

### O41 [no principle] [MEDIUM] otel-collector file holds three units

- Den-readiness finding: **otel-collector file holds three units** (A27).
- Location: `modules/clan/services/otel-collector/flake-module.nix` (1,743 lines: agent, ingress and service), split by pull request 4448 into `agent.nix`, `ingress.nix`, `service.nix` and `_shared.nix` in the same directory.
- Why this matters: file cohesion, which P1–P5 do not derive.
- Approach: split into `agent.nix`, `ingress.nix`, `service.nix` and an `_`-prefixed shared file, keeping the `flake.modules` names.
- Closed by compose-hosts-from-cohesive-aspects.

### O42 [P2, P4] [MEDIUM] Untyped envelope and host-facts schemas

- Den-readiness finding: **Untyped envelope and host-facts schemas** (A28).
- Locations: the envelope budget (`nullOr attrs`) in `modules/clan/services/otel-collector/flake-module.nix` (now `_shared.nix`); `modules/lib/observability-hosts.nix`.
- Why this matters: P2 — the consumer field is untyped; P4 — a malformed entry is not rejected.
- Approach: a submodule for the envelope budget and a library-level validator for the observability host table.
- Closed by register-fleet-obligations.

### O43 [P1] [MEDIUM] ZFS boot invariants written fourteen times

- Den-readiness finding: **ZFS boot invariants written fourteen times** (A29).
- Location: `modules/machines/nixos/magnetite/default.nix` (fourteen boot oneshots and their `notifiedUnits`).
- Why this matters: P1 — one recipe per dataset.
- Approach: generate the oneshots and `notifiedUnits` from a dataset table in `flake.lib`; `disko.nix` stays an independent literal so `greptimedb-envelope` still compares install time with boot time.
- Status: resolved by compose-hosts-from-cohesive-aspects (pull request 4461). Magnetite generates the fourteen oneshots from `flake.lib.zfsBootInvariants.magnetite` (`modules/lib/zfs-boot-invariants.nix`), and `modules/lib/observability-hosts.nix` reads their unit names from the same table.

### O44 [P2] [LOW] `base` and `homeManager.ai` have no named includes

- Den-readiness finding: **`base` and `homeManager.ai` have no named includes** (A30).
- Locations: the roughly 34 `darwin.base` and 28 `nixos.base` contributors; `homeManager.ai`.
- Why this matters: P2 (C3) — the aggregate's parts have no names a consumer could select.
- Approach: named sub-aspects of `base`, and one aspect per agent harness with `ai` importing them all; the obligation modules stay in base.
- Status: not done. compose-hosts-from-cohesive-aspects measured that naming the parts reorders argentum's system packages and every home importing `ai`, so `base` and `ai` stay implicit and named parts are left to a later change (that change's design D11 and Resolved Question 10).

### O45 [P1] [LOW] `darwin/caches.nix` duplicates `system/caches.nix`

- Den-readiness finding: **`darwin/caches.nix` duplicates `system/caches.nix`** (A31).
- Location: `modules/darwin/caches.nix`.
- Why this matters: P1 — the cache list written twice, so each darwin `nix.conf` lists every cache twice.
- Approach: delete the duplicate. Declared to change every darwin toplevel.
- Status: resolved by compose-hosts-from-cohesive-aspects (pull request 4452). `modules/darwin/caches.nix` is deleted; each darwin `nix.conf` lists the ten caches of `lib/caches.nix` once, followed by nix-darwin's own `https://cache.nixos.org/`.

### O46 [P5] [LOW] Magnetite-shared facts read from the host in tests

- Den-readiness finding: **Magnetite-shared facts read from the host in tests** (A32).
- Locations: `modules/vm-tests/greptimedb-pipeline.nix`, `modules/vm-tests/fleet-ingress.nix` and three more runtime tests read `databases` from magnetite's evaluated configuration.
- Why this matters: P5 — a test reads another entity's evaluated configuration for data that can be a pure value.
- Approach: lift the databases, retention and graphs into `flake.lib` data; each test still asserts that magnetite consumes it.
- Closed by stop-reading-other-hosts-configs.

## Planned decomposition as OpenSpec changes

The opportunities above are planned as the seven OpenSpec changes of the Linear project "Den-ready fleet architecture" (`den-ready-fleet`), each under `openspec/changes/<change>/` and bound to one Linear issue.
They land, and archive, in this order; each rebases onto its predecessor and is accepted by `just drv-diff <base> <candidate> openspec/changes/<change>/drv-delta.txt`, and each cost claim by `just eval-cost` against `eval-cost-baselines.md`.

1. **establish-refactor-oracle** (CAM-131): `just drv-diff`, `just eval-cost`, the baselines note, and the corrections to this document, ADR-0018/0019/0020 and the READMEs. Closes no entry; every later change depends on it.
2. **stop-reading-other-hosts-configs** (CAM-133): known hosts and stibnite's session key from committed vars, the committed-vars accessor, magnetite's test data as a pure value. Closes O18, O24, O46. Depends on 1.
3. **type-the-fleet-host-registry** (CAM-134): one typed record per host with the system, role membership and lifecycle facts derived from it; stibnite's `controller` tag renamed to `deployer-workstation`. Closes O10, O23, O32, O33. Depends on 1.
4. **register-fleet-obligations** (CAM-135): judges registered beside their code, one judge-check convention, the fleet package set in tests, the `patched` channel removed, the two schemas declared. Closes O34, O35, O36, O39, O40, O42. Depends on 1.
5. **declare-host-user-relations-once** (CAM-130): the per-(host, user) record, the home-manager integration aspect, one `flake` value, the omnigent worker relation, `accountOf`. Closes O01, O04, O09, O15, O20, O21, O29, O30, O31 and the user blocks of O19. Depends on 1, on 3 (the attachment record is a field of the typed host record) and on 2: `modules/system/ssh-known-hosts.nix` is the last system module that takes `flake`, and stop-reading-other-hosts-configs removes that.
6. **compose-hosts-from-cohesive-aspects** (CAM-132): service wiring out of host bodies, cinnabar's features re-keyed, the Hetzner and GCP cloud-server aspects, the darwin workstation aspect, host facts and flags written once, module keys and activation order, the otel-collector split, generated ZFS invariants, named includes. Closes O02, O05, O26, O27, O28, O37, O38, O41, O43, O44, O45 and the template half of O19. Depends on 1, 3 and 5. As landed, O44 was not done, and O02, O05 and the template half of O19 remain open for stibnite's documentation lines and template and the shared-reference-tree flag (see each entry's status).
7. **seam-secrets-away-from-clan-vars** (CAM-129): one secrets seam, the only writer and reader of clan vars. Closes O25. Depends on 1, 2 and 6.

O03, O06, O11, O12, O17 and O22 are outside the project and stay open.

The preceding nix-0pd epic, from which PR #1938 closed 12 of 24 children, was closed against this document: typed aggregates, the machine-meta cluster, the primary/admin user bindings, the test-collection convention, the nix-unit harness and the expected-error pattern were done or subsumed, and `meta.description` on every check, the strict freeform `meta`, a flake-compat shim and the companion-flake split were deferred; that tracker is retired, and what still matters of it is in the entries above.

## Updating this document

The document is a living artifact, not a snapshot.
Three lifecycle protocols govern updates.

**Closure of opportunities.** When an opportunity lands via PR or commit, mark the entry resolved with the merging commit's hash (or PR number) and a one-line note linking to it.
After one merge cycle of stability (the next merge-to-main following the resolution), remove the resolved entry entirely.
Git history is the snapshot trail; the document carries only live opportunities.

**Adding new opportunities.** New entries cite their parent principle(s) from P1–P5 in the bracket tag, or "no principle" where none derives them.
Severity is graded against the existing rubric (HIGH/MEDIUM/LOW/WATCH).
If a candidate doesn't cleanly map to P1–P5, surface the ambiguity rather than retrofit; it may be a signal that the principle set needs revision.

**Revising principles.** A principle is revised only when a body of evidence shows the existing set fails to be generative — that is, the existing principles cannot derive a tactic the codebase has come to require, or two principles are observed to collapse into one without loss.
Relabeling existing principles or splitting one principle into two with the same generative behavior is not revision; it is rearrangement, and it should not happen.

## Calibration

**Where the rubric may over-flag:**

- P2 (no speculative slots) is sensitive to false positives via the import-tree auto-discovery indirection. Slots like `custom.profile.{isServer,isWorkstation,isHeadless}` (O05) might have planned consumers in flight (e.g., an OpenSpec change in progress). O05 is MEDIUM partly hedging on this; O16 was such a false positive, consumed all along.
- P4 (negative controls) is a discipline that can balloon — every check could in principle have a negative-control sibling. O12 limits to the structure checks that match the new pattern's profile (those exercising a predicate or comparison that *could* be subtly wrong); pure existence checks don't need negative controls.
- P3 (eager symmetry, single resolution) is hard to score for O21. The pattern is the *fixed* version per the cluster. WATCH is the right grade until/unless someone touches host files for an alias rotation and discovers friction.

**Surfaced patterns that did not warrant new principles:**

- *Cross-host constants of identity (`flake.lib.hosts.<host>.<x>`) is the natural extension of P3.* The post-PR-#1938 fix elevated `flake.users.<u>.meta` as the registry for cross-cutting per-user identity. The same architectural shape was missing for *machines* — `cinnabar.zt`'s controller status, every host's zerotier IPv6, darwin hosts' static SSH host pubkeys lived as inline literals across multiple modules. The pattern is absorbed into the typed host registry cluster.
- *Bridging-values isomorphism*: the `inputs.self // { inherit inputs; }` synthesis appears at 7 sites (O01 + O20). This is P1 (derive once) plus P3 (one resolution site). Absorbed into O20's single `flake` value.
- *Locality of effect — invariants check where they fire.* The hm-sops-bridge per-user `assertions = [...]` inline at the bridge module's evaluation site versus structural checks under `modules/checks/` are two architectural choices for invariant placement. Folded into P4: an assertion's epistemic content depends on it firing in the same evaluation context as the configurations it constrains.

**Genuine opportunities possibly missed by the R6 pass:**

- Did not deeply audit the clan-service interface declarations under `modules/clan/services/` (kanban, openclaw and their siblings) for P2 / P4 issues — they may have speculative slots; a fuller pass would re-read each interface against its `perInstance` consumer.
- Did not audit `modules/terranix/` for P2 / P3 (cross-zone duplication, hardcoded resource names, etc.).
- Did not check `modules/checks/devshells.nix`, `modules/checks/security.nix`, `modules/checks/performance.nix`, `modules/checks/integration.nix` for P4.
- The custom darwin `services.colima.portForwards` submodule (modules/darwin/colima.nix:336) declares a typed `attrsOf submodule` consumed by stibnite — not flagged because it has a real consumer and parametric semantics, but a fuller P2 audit might check whether the wrapper layer carries metadata not consumed.
