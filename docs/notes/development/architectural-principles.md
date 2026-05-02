# Architectural principles for vanixiets

This document carries four generative principles for vanixiets' flake / module architecture, eight tactical corollaries derived from them, and a register of current opportunities to apply them more fully.
The principles are durable; the opportunities close as work lands and new ones may surface as the codebase evolves.

It is intended to be read at /session-plan time when the actor-critic / worker-orchestrator pair schedules architectural improvement work.
The principles, corollaries, opportunities, and the proposed initial decomposition into beads epics and PRs are all included inline so the document is self-contained.

## Provenance

The principles were distilled during the typed-`flake.users` refactor (PR #1938, merged 2026-05-02 at commit 8e334238).
Reviews R5-A through R5-D evaluated that PR along type-safety, dendritic-fidelity, adversarial whole-branch, and regression-probe axes; R6 swept the post-merge codebase against the resulting rubric.
The eight tactical corollaries were the original session-end synthesis; the four principles are the limit-point compression of those eight, with each corollary instantiating one principle.
The 22 opportunities below each instantiate one or more principles and have current-shape, aligned-shape, and approach captured inline.

## The four principles

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

22 opportunities cataloged at branch tip 8e334238 (post-PR-#1938 merge).
By principle: P1 = 9 entries, P2 = 5, P3 = 8, P4 = 3 (some entries cite multiple).
By severity: HIGH = 4, MEDIUM = 11, LOW = 4, WATCH = 3.

Severity rubric describes leverage:
- HIGH — replicates a pattern the cluster already proved was wrong, or actively misleads readers
- MEDIUM — focused tranche; not blocking new work but degrading every change in the area
- LOW — visible deviation, address opportunistically when touching the area
- WATCH — borderline; flagged for awareness, may be intentional

The cross-cutting clusters where one fix lands many entries:

- **Smart host constructor** (O01, O02, O09, O14, O19, O20) — replaces ~70% of host module body with a thin call to a `flake.lib.mkMachine{Darwin,NixOS}` constructor. ~9 hosts × ~50 lines.
- **Smart user content constructor** (O03, O11, O22, plus tail of O09) — replaces 5 per-user `default.nix` files with thin `mkUserContent` calls and removes redundant `username` / `aggregates` literals from `meta.nix`. ~5 files × ~40 lines.
- **Smart inventory user-instance constructor** (O04, O20) — collapses three near-clone clan inventory user services into one. 3 files × ~50 lines.
- **`flake.machines` typed registry** (O07, O08, O18, possibly O21) — moves zerotier IPv6, darwin SSH host pubkeys, and the controller designation into a single typed registry consumed by zerotier inventory, zt-dns, ssh-known-hosts, and home/core/ssh.nix. Removes ~20 inline literals.

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

### O02 [P1] [MEDIUM] Cross-darwin-host duplication of documentation override block

- Locations:
  - `modules/machines/darwin/argentum/default.nix:42-48`
  - `modules/machines/darwin/blackphos/default.nix:44-50`
  - `modules/machines/darwin/rosegold/default.nix:42-48`
  - `modules/machines/darwin/stibnite/default.nix:49-55`
- Current shape: every darwin host repeats the same 7-line `srvos.server.docs.enable + documentation.* + programs.{info,man}.enable = lib.mkForce true` block.
- Why this matters: P1 — recipe at every callsite when the four laptop hosts share an "isDesktop" property already.
- Approach: move into a darwin module conditioned on `config.custom.profile.isDesktop` (or a new `flake.modules.darwin.docs-for-laptops` aggregate), then drop the 7-line block from each host.

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

### O04 [P1] [HIGH] `clan/inventory/services/users/{cameron,crs58,tara}.nix` are three near-clones of the same `extraModules` recipe

- Locations:
  - `modules/clan/inventory/services/users/cameron.nix:36-71`
  - `modules/clan/inventory/services/users/crs58.nix:31-58`
  - `modules/clan/inventory/services/users/tara.nix:27-54`
- Current shape: all three define `clan.inventory.instances.user-<u>` with identical boilerplate (`module = { name = "users"; input = "clan-core"; }`, `roles.default.settings = { user = "<u>"; share = true; prompt = false; ... }`, and an `extraModules` block wiring `users.users.<u>.shell = pkgs.zsh`, `users.users.<u>.openssh.authorizedKeys.keys = inputs.self.users.<u>.meta.sshKeys`, `programs.zsh.enable = true`, and the home-manager infra block). Differences: user shortname, machine list, group set.
- Why this matters: P1 — three files restate the same `extraModules` recipe; the user shortname is a literal in every reference instead of being derived from a key.
- Approach: introduce `flake.lib.mkClanUserInstance { name, machines, groups, shell ? "zsh" }` (or a typed `attrsOf submodule` field) that emits the inventory instance from a small record. Each user file becomes a `{ machines = [...]; groups = [...]; }` literal.
- Dependencies: independent.

### O05 [P2] [MEDIUM] `custom.profile.{isServer,isWorkstation,isHeadless}` declared with no consumer

- Location: `modules/darwin/profile.nix:21-39`
- Current shape: `options.custom.profile` declares `isDesktop`, `isServer`, `isWorkstation`, `isHeadless`. `rg` for `isServer|isWorkstation|isHeadless` returns hits only in the declaration site itself; only `isDesktop` is actually written by hosts.
- Why this matters: P2 — three of four slots are speculative; no consumer references them.
- Approach: drop the unused slots; keep only `isDesktop`. Or, if a future feature is genuinely planned, capture the intended consumer in the same commit that adds the slot.

### O06 [P2] [MEDIUM] `flake.modules.nixos.k3s-server` declares a typed option set with no host enabling it

- Location: `modules/nixos/k3s-server/default.nix:34-74` and `modules/nixos/k3s-server/{kernel,networking,packages}.nix`
- Current shape: the k3s-server option set is exhaustively typed (`enable`, `role`, `clusterInit`, `serverAddr`, `clusterCidr`, `serviceCidr`, `tokenFile`). `rg` for `k3s-server\.enable` outside `modules/nixos/k3s-server/` returns zero hits.
- Why this matters: P2 — the module is speculative scaffolding with no host writing `k3s-server.enable = true;`. The CLAUDE.md indicates active prototyping work for k3s, so this may be in-flight rather than abandoned.
- Approach: either (a) wire it into a host (presumably stibnite or an electrum-substitute) so the consumer/declaration ratio reaches 1+, or (b) move it under `docs/notes/` as a draft until a host imports it.
- Severity note: classed MEDIUM rather than LOW because the option set is large and the eval cost is real even without a consumer.

### O07 [P3] [HIGH] Zerotier-controller IPv6 nameserver hardcoded in three places

- Locations:
  - `modules/clan/inventory/services/zerotier.nix:11` (controller machine "cinnabar")
  - `modules/darwin/zt-dns.nix:7` (`nameserver fddb:4344:343b:14b9:399:93db:4344:343b`)
  - `modules/system/ssh-known-hosts.nix:24` (cinnabar zt IPv6)
  - `modules/home/core/ssh.nix:46` (cinnabar zt IPv6 hostname)
- Current shape: the cinnabar controller's zerotier IPv6 (and the analogous IPv6 for every other fleet machine) is restated as a literal in clan inventory `allowedIps`, the darwin DNS resolver file, the system SSH known_hosts table, and the home SSH client config.
- Why this matters: P3 — identity-bearing data ought to flow from one authoritative writer; the IP is currently reauthored at each consumer.
- Approach: add `flake.users.<u>.meta.sshKeys`-style `flake.machines.<host>.meta.{zerotierAddr, zerotierMemberId}` records; let zerotier inventory, zt-dns, ssh-known-hosts, and home/core/ssh.nix all read from this single registry.
- Dependencies: forms a cluster with O08, O14, O18.

### O08 [P3] [HIGH] Zerotier IPv6 addresses for all 9 fleet hosts duplicated between `system/ssh-known-hosts.nix` and `home/core/ssh.nix`

- Locations:
  - `modules/system/ssh-known-hosts.nix:24-119` (9 entries with comment-tagged IPs)
  - `modules/home/core/ssh.nix:45-103` (10 entries with the same IPs)
- Current shape: each of the 9 fleet hosts plus pixel7 has its zerotier IPv6 written once in `programs.ssh.knownHosts.<host>` (system) and once in `programs.ssh.matchBlocks.<host>.hostname` (home).
- Why this matters: P3 — identity data with multiple writers and no single registry. Drift will silently break SSH for any host whose IP rotates.
- Approach: add `flake.machines.<host>.meta.zerotierAddr` and have both modules consume from there.
- Dependencies: cluster with O07; same fix lifts both.

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

### O10 [P2, P4] [WATCH] `flake.lib` typed as `lazyAttrsOf raw` carries structurally typed values

- Locations:
  - `modules/lib/option.nix:3-7` (declaration)
  - `modules/lib/md-format.nix:6` (`flake.lib.mdFormat = lib.types.submodule (...)`)
  - `modules/home/users/lib.nix:28` (`config.flake.lib.mkUserIdentity = ...`)
- Current shape: the `flake.lib` namespace is typed as `lazyAttrsOf raw`. Per `reference_flake-lib-lazyattrsof-raw.md`, this rejects nested option declarations and forbids multi-file writes at the same nested path. The current contents (`mdFormat`, `mkUserIdentity`, `mkHome`, `mkStructuralCheck`, `mkEvalCheck`, `bitwardenSocketPath`) are flat top-level keys, so no collision occurs *today*.
- Why this matters: P2 / P4 — using `raw` as a permissive escape hatch for things that *could* be properly typed (a literal collection of typed helper functions and types). When the next nested registry need surfaces (e.g., a `flake.lib.policies.<x>`), the workaround pressure will repeat.
- Approach: watch only — no immediate breakage. If the next typed-registry need under `flake.lib` arises, prefer extracting to a top-level `options.flake.<x>` field with a proper submodule type rather than nesting under `flake.lib`. Per `feedback_no-parallel-typed-registries.md`, also consider whether the consumer field can be typed against the existing native registry instead.
- Dependencies: independent.

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
  - `modules/checks/structure/flake-shape.nix:27-77` (4 mkCheck invocations: `inventory-machines`, `nixos-configurations`, `darwin-configurations`, `home-configurations`)
  - `modules/checks/structure/inventory-class-discovery.nix:36-41` (`structure-inventory-class-discovery`)
- Current shape: five structural checks under `modules/checks/structure/` without a `*-neg` partner. Compare against the post-PR pattern in `modules/checks/validation.nix:107-129` (`home-module-exports-neg`) and `modules/checks/hm-sops-bridge.nix:69-79` (`hm-sops-bridge-assertion-neg`), added in commits 532171fb / e39acd80 specifically because positive-only checks could pass given the codebase's actual configurations and never falsify the predicate they purport to test.
- Why this matters: P4 — these checks compare the actual flake shape to the literal expected list, but if (for example) `lib.naturalSort` were silently broken or the `attrNames` accessor became case-insensitive, the check could pass for the wrong reason. A negative control would inject a phantom mismatch and verify the diff fails.
- Approach: for each, add a `*-neg` sibling that constructs an artificial mismatch (e.g., feed `mkCheck` with a deliberately wrong `actual` and an `expected` that disagrees, asserting the check itself produces a failure derivation that we then capture). The `aggregate-eval-failure.nix` pattern (testing `tryEval` returns `success = false`) generalizes here.
- Severity note: MEDIUM rather than HIGH because the checks have additional severity from their inputs (the `attrNames` of clan/inventory/machines is hardcoded against the inventory file, so a literal-vs-derived drift would surface other ways). Still falsifiability discipline cluster.

### O13 [P4] [LOW] `modules/checks/structure/aggregate-eval-failure.nix` accesses `self.modules.homeManager` rather than `config.flake.modules.homeManager`

- Location: `modules/checks/structure/aggregate-eval-failure.nix:31-34`
- Current shape: the check resolves `self.modules.homeManager.deliberately-undeclared`. Per the R5-B note, this is stylistically inconsistent with `validation.nix` which uses `config.flake.modules.homeManager`. The two reach the same value but via different evaluation contexts.
- Why this matters: P4 (mild) — using `self.modules.homeManager` may evaluate against a different snapshot than the in-flake config; for falsifiability it's important the check is exercising the same registry the consumer reads.
- Approach: switch to `config.flake.modules.homeManager.deliberately-undeclared or (throw "...")` for consistency.

### O14 [P1] [MEDIUM] `modules/checks/machines.nix` hardcodes the 4-machine NixOS list rather than deriving from registered configurations

- Location: `modules/checks/machines.nix:17-22`
- Current shape: the check binds `vanixiets-nixos-{cinnabar,electrum,galena,magnetite}` as `self.nixosConfigurations.<host>.config.system.build.toplevel`. The host list is a literal four-element repetition; every line restates the same recipe.
- Why this matters: P1 — recipe at every callsite. Compare against `modules/checks/home.nix:23-34` which derives the analogous list from `config.flake.users` (filtered by aggregates).
- Approach: iterate `lib.attrNames self.nixosConfigurations`, optionally filtered by an exclusion list (the comment notes scheelite is intentionally deferred). Then drift between the inventory and the check set is impossible.

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

### O16 [P2] [MEDIUM] `flake.users.<u>.meta.githubUser` declared but no module reads it

- Location: `modules/home/users/lib.nix:59-63`
- Current shape: `meta.githubUser` is declared on the typed registry. `rg 'githubUser'` outside `lib.nix` returns zero hits.
- Why this matters: P2 — speculative slot; no consumer references it.
- Approach: either drop the field or wire it into a real consumer (e.g., a `programs.git.settings.github.user` derived value, an htop config tag, etc.).

### O17 [P2] [LOW] `flake.users.<u>.meta.fullname` consumed by 5 sites; `meta.email` consumed by 9 sites — verify intentional

- Location: `modules/home/users/lib.nix:51-58`
- Current shape: `meta.fullname` referenced from 5 user `default.nix` files only (each user reads their own); `meta.email` from each user's `default.nix` and `templates."allowed_signers"`. Real consumers but only via per-user-self-references — the cross-cutting consumer is missing.
- Why this matters: P2 (very mild) — fields used only locally hint that the typed registry is doing less work than its surface area suggests. WATCH: this might be intentional if the centralization is *for future consumers* but expressed at the registry layer first.
- Approach: WATCH only. After O03 lands (the smart user-content constructor), these fields will have one canonical reader and the local-only-use pattern resolves.

### O18 [P3] [MEDIUM] Static darwin SSH host pubkeys in `system/ssh-known-hosts.nix` declared inline rather than under `flake.machines.<host>.meta`

- Location: `modules/system/ssh-known-hosts.nix:79, 89, 99, 109, 123` (5 inline `publicKey = "ssh-ed25519 ..."` literals)
- Current shape: for darwin and pixel7 hosts, the SSH host public key is hardcoded next to the IPs. NixOS hosts derive their keys from `flake.nixosConfigurations.<host>.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value`.
- Why this matters: P3 — these are identity-bearing data values for darwin hosts, but they live as inline literals at one site. There's no second writer today (the literals are consumed only here), but combined with O07/O08 (zerotier IPs of the same darwin hosts), the natural shape is `flake.machines.<host>.meta.{zerotierAddr, sshHostPubKey}`.
- Approach: same as O07 fix — extend `flake.machines` to carry these.
- Dependencies: cluster with O07/O08.

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

### O20 [P1, P3] [MEDIUM] Inventory `extraModules` block nested-function reconstruction of inputs.self splice repeated 3 times

- Locations:
  - `modules/clan/inventory/services/users/cameron.nix:62-67`
  - `modules/clan/inventory/services/users/crs58.nix:49-54`
  - `modules/clan/inventory/services/users/tara.nix:45-50`
- Current shape: all three inventory user services restate `extraSpecialArgs = { flake = inputs.self // { inherit inputs; }; }` inside an `extraModules` lambda; the same construct is also restated in every darwin host (O01).
- Why this matters: P1 — recipe duplication across 3 inventory files plus 4 darwin hosts (= 7 sites for the same splice). P3 — this is the same `inputs.self` identity flowing through 7 different writers, each creating the same `// { inherit inputs; }` synthesis.
- Approach: a `flake.lib.flakeForHomeManager = inputs.self // { inherit inputs; };` (or pre-baked attribute on the flake) computed once. Consumers reference it.

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
- Approach: WATCH. May be intentional — the comment at each site indicates this is *consciously* alias-keyed and the orchestrator (clan inventory's user service) decides the binding. Possible future refinement: `flake.machines.<host>.users` typed list that resolves through aliases-fold, removing per-host decisions.
- Dependencies: depends on O07/O08 cluster (`flake.machines` registry).

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

## Planned decomposition into beads epics and PRs

Calibration unit: PR #1938 was one typed-registry adoption — 1 epic, 24 children of which 7 tranches landed in the merge push, 1 PR, ~5 weeks elapsed.
The opportunities decompose at that grain into one epic plus roughly five PRs.
Each entry below names the opportunity IDs it would close so the next /session-plan can wire dependencies.

### E1. Machine typed registry epic — `flake.machines.<host>.meta`

Mirrors what nix-0pd just did for users.
Introduce `options.flake.machines = attrsOf (submodule ({ name, config, ... }: ...))` carrying per-host identity-bearing data; lift zerotier IPv6, darwin SSH host pubkeys, controller designation, and (eventually) admin/primary user bindings into this typed registry; rewrite consumers to read from it; introduce a `flake.lib.mkMachine{Darwin,NixOS}` smart constructor that collapses the host-module recipe.

- Closes: O01, O02, O07, O08, O09, O14, O18, O19, plausibly O21
- Approximate tranches:
  1. Schema declaration of `flake.machines.<host>.meta`
  2. Lift zerotier IPv6 + member-id into the registry (O07, O08)
  3. Lift darwin SSH host pubkeys (O18)
  4. Smart host constructor `flake.lib.mkMachine{Darwin,NixOS}` (O01, O02)
  5. Per-host module collapse onto the smart constructor (O09, O19)
  6. Derive `modules/checks/machines.nix` host list (O14)
  7. Falsifiable structural assertion for the machine registry shape
- Indicative scope: ≈9 opportunities × 9 hosts × 50 lines = on par with nix-0pd
- Calibration uncertainty: O21 is WATCH; may be deferred or addressed via an additional `flake.machines.<host>.users` typed list

### E2. User-content smart constructor PR (no epic)

Tactical refactor inside the now-typed `flake.users` registry.
Provide `flake.lib.mkUserContent { name, packages, secrets, secretsRepoSubpath ? name }` smart constructor; derive `meta.username` default from `name`; supply default `aggregates` list at the slot.

- Closes: O03, O11, O22
- Approximate scope: 4–5 atomic commits (`meta.username` default, `aggregates` default, `mkUserContent` constructor, rewrite 5 per-user files)
- Single PR, no epic

### E3. Clan-inventory user smart constructor PR (no epic)

Domain-bounded refactor of clan inventory user services.
Introduce `flake.lib.mkClanUserInstance { name, machines, groups, shell ? "zsh" }`; collapse the three near-clones onto it.

- Closes: O04, O15, O20
- Approximate scope: 3–4 atomic commits
- Single PR, no epic

### E4. Falsifiability sweep PR — extend negative-control discipline

Extend the negative-control discipline established in 532171fb / e39acd80 across the remaining structural checks.
For each existing check, audit whether a tryEval-asserted phantom would be appropriate and add a `*-neg` partner where it is.

- Closes: O12, O13
- Likely additional under-flagged scope: `modules/checks/{devshells,security,performance,integration}.nix`
- Approximate scope: 5–10 negative-control derivations across the structure check tree
- Single PR; if the audit reveals more checks than expected, this could grow to small-epic size

### E5. Speculative-slot pruning PR

Mostly deletion work + consumer audit.
Drop the unused `custom.profile.{isServer,isWorkstation,isHeadless}` slots; either wire `k3s-server.enable` into a host or move the module under `docs/notes/`; either drop `meta.githubUser` or wire it into a real consumer.

- Closes: O05, O06, O16
- Possibly closes O17 after consumer audit confirms whether `meta.fullname` / `meta.email` cross-cutting consumers are intentional
- Approximate scope: 2–3 commits
- Single PR, no epic

### E6. flake.lib namespace migration tranche (provisional)

O10 is WATCH-grade today.
The `flake.lib` namespace is typed as `lazyAttrsOf raw` and currently carries structurally typed values.
Resolution path may be either (a) absorb into E1 if the machine-epic work surfaces a nested-typed-registry need under `flake.lib`, or (b) migrate `flake.lib` namespace independently to a top-level option with a proper submodule type.

- Closes: O10
- Recommended: file as a beads discovery issue first; the right shape is unclear without the next typed-registry use case
- Likely outcome: small standalone PR or fold into E1

### Totals

- 1 epic (E1)
- 4 tactical PRs (E2, E3, E4, E5)
- 1 provisional PR (E6) that may stand alone or fold into E1
- ≈6 branches total, ≈±1 calibration uncertainty
- The "machine typed registry" candidate principle and the "bridging-values isomorphism" pattern both surfaced during R6 as candidate principles; both are absorbed inside E1 / the host-recipe collapse and do not require principle-set expansion

## Status of preceding nix-0pd epic

PR #1938 closed 12 of nix-0pd's 24 children plus retired nix-0pd.25 (filed during T7 verification, found to be a misclassification — rosetta-builder IFD interference, not architectural breakage).
At merge time, the remaining 11 children were dispositioned as follows.

### Closed — already done or subsumed by this document

- nix-0pd.7 — typed aggregates landed in PR #1938 (done)
- nix-0pd.8 — exactly the O07/O08/O18 machine-meta cluster (subsumed by E1)
- nix-0pd.9 — primaryUser / adminUser bindings on flake.hosts (subsumed by E1)
- nix-0pd.10 — flake.tests.<name> collection convention (subsumed by E4)
- nix-0pd.11 — nix-unit and isolated-eval harness for option-system invariants (subsumed by E4)
- nix-0pd.12 — expectedError typed-error tag pattern (replaced by tryEval-with-asserts mechanism in 532171fb / e39acd80)

### Deferred — orthogonal or out of current planning horizon

- nix-0pd.1 — meta.description on every flake-parts check; small chore
- nix-0pd.6 — strict-mode freeform throw on `flake.users.<u>.meta`; may surface naturally during E1 work
- nix-0pd.3 — flake-compat input + default.nix shim; orthogonal
- nix-0pd.13 — companion-flake split design ADR; orthogonal
- nix-0pd.14 — companion-flake split implementation (gated on .13); orthogonal

### Epic itself

`nix-0pd` (epic) closed force-with-reason citing this document as the entry point for /session-plan.
Deferred children are accessible via `bd list --deferred`.

## Updating this document

The document is a living artifact, not a snapshot.
Three lifecycle protocols govern updates.

**Closure of opportunities.** When an opportunity lands via PR or commit, mark the entry resolved with the merging commit's hash (or PR number) and a one-line note linking to it.
After one merge cycle of stability (the next merge-to-main following the resolution), remove the resolved entry entirely.
Git history is the snapshot trail; the document carries only live opportunities.

**Adding new opportunities.** New entries cite their parent principle(s) from P1–P4 in the bracket tag.
Severity is graded against the existing rubric (HIGH/MEDIUM/LOW/WATCH).
If a candidate doesn't cleanly map to P1–P4, surface the ambiguity rather than retrofit; it may be a signal that the principle set needs revision.

**Revising principles.** A principle is revised only when a body of evidence shows the existing set fails to be generative — that is, the existing four principles cannot derive a tactic the codebase has come to require, or two principles are observed to collapse into one without loss.
Relabeling existing principles or splitting one principle into two with the same generative behavior is not revision; it is rearrangement, and it should not happen.

## Calibration

**Where the rubric may over-flag:**

- P2 (no speculative slots) is sensitive to false positives via the import-tree auto-discovery indirection. Slots like `meta.githubUser` (O16) and `custom.profile.{isServer,isWorkstation,isHeadless}` (O05) might have planned consumers in flight (e.g., a beads epic in progress). O05 is MEDIUM partly hedging on this; O16 is genuinely consumer-less per `rg`.
- P4 (negative controls) is a discipline that can balloon — every check could in principle have a negative-control sibling. O12 limits to the structure checks that match the new pattern's profile (those exercising a predicate or comparison that *could* be subtly wrong); pure existence checks (e.g., `home-configurations-exposed` at validation.nix:131-180) don't need negative controls.
- P3 (eager symmetry, single resolution) is hard to score for O21. The pattern is the *fixed* version per the cluster. WATCH is the right grade until/unless someone touches host files for an alias rotation and discovers friction.

**Surfaced patterns that did not warrant new principles:**

- *Cross-host constants of identity (`flake.machines.<host>.meta.<x>`) is the natural extension of P3.* The post-PR-#1938 fix elevated `flake.users.<u>.meta` as the registry for cross-cutting per-user identity. The same architectural shape is missing for *machines* — `cinnabar.zt`'s controller status, every host's zerotier IPv6, darwin hosts' static SSH host pubkeys all live as inline literals across multiple modules. The pattern is absorbed into E1.
- *Bridging-values isomorphism*: the `inputs.self // { inherit inputs; }` synthesis appears at 7 sites (O01 + O20). This is P1 (derive once) plus P3 (one resolution site). Absorbed into E1's host-recipe collapse via `flake.lib.flakeForHomeManager`.
- *Locality of effect — invariants check where they fire.* The hm-sops-bridge per-user `assertions = [...]` inline at the bridge module's evaluation site versus structural checks under `modules/checks/` are two architectural choices for invariant placement. Folded into P4: an assertion's epistemic content depends on it firing in the same evaluation context as the configurations it constrains.

**Genuine opportunities possibly missed by the R6 pass:**

- Did not deeply audit `modules/clan/services/{beads-ui,kanban,openclaw}/flake-module.nix` for P2 / P4 issues — these are clan-service interface declarations and may have speculative slots; a fuller pass would re-read each interface against its `perInstance` consumer.
- Did not audit `modules/terranix/` for P2 / P3 (cross-zone duplication, hardcoded resource names, etc.).
- Did not check `modules/checks/devshells.nix`, `modules/checks/security.nix`, `modules/checks/performance.nix`, `modules/checks/integration.nix` for P4.
- The custom darwin `services.colima.portForwards` submodule (modules/darwin/colima.nix:336) declares a typed `attrsOf submodule` consumed by stibnite — not flagged because it has a real consumer and parametric semantics, but a fuller P2 audit might check whether the wrapper layer carries metadata not consumed.
