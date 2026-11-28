## ADDED Requirements

### Requirement: Each aspect is one definition importing its listed parts

`flake.modules.nixos.base`, `flake.modules.darwin.base` and `flake.modules.homeManager.ai` SHALL each have exactly one definition, in its list file, importing the class's modules named by `flake.lib.nixosBaseParts`, `flake.lib.darwinBaseParts` or `flake.lib.aiParts`, in list order.

Trust boundary: this fixes where membership is written and that each part is a separately importable module. It does not fix the order list options take, which import depth decides (A344, A375).

#### Scenario: The aspects' definitions are read

- **WHEN** the flake's `modules` output's `nixos.base`, `darwin.base` and `homeManager.ai` are applied to `{ }` and the `_file` of each merged definition is read
- **THEN** each aspect has one, naming `modules/nixos/base.nix`, `modules/darwin/base.nix` and `modules/home/ai/default.nix` respectively

#### Scenario: The lists are read

- **WHEN** `flake.lib.nixosBaseParts`, `flake.lib.darwinBaseParts` and `flake.lib.aiParts` are evaluated
- **THEN** they hold 33, 29 and 15 names, each an attribute of `flake.modules.nixos`, `flake.modules.darwin` or `flake.modules.homeManager`

#### Scenario: Every former contribution has a name

- **WHEN** the modules the aspects held before are looked for
- **THEN** each is defined as `flake.modules.<class>.base-<concern>`, `flake.modules.homeManager.ai-<harness>`, or under a name it already had, and is in its class's list

#### Scenario: A part is imported alone

- **WHEN** a NixOS configuration imports `flake.modules.nixos.base-zram-swap` and no other part
- **THEN** it evaluates with `zramSwap.enable = true` and without any other part's settings

### Requirement: A file adding to base, ai or an existing part, or an unlisted part, fails a small check

`checks.x86_64-linux.structure-aspect-parts` SHALL fail, naming each violation, when an aspect is defined outside its list file, a listed part is defined outside its own file (or a multi-file part outside its listed files), or a `base-` or `ai-` module is in no list. This relies on A375.

Trust boundary: definition sites and listing only; not whether a part belongs, nor any derivation.

#### Scenario: The check's form and size

- **WHEN** `modules/checks/structure/aspect-parts.nix` and `testSizes.checks.structure-aspect-parts` are read
- **THEN** the check is `self.lib.mkStructuralCheck` with `expected = [ ]` under a literal name, it reads the modules only in its value, its size is `{ class = "small"; measured = false; }`, `ai-skills` and `ai-skills-compose` are exempt from the listing rule because `ai-capabilities` imports them, and the multi-file parts it lists are exactly `base-system-defaults` (the nine `modules/darwin/system-defaults/*.nix`) and `ai-claude-code` (`modules/home/ai/claude-code/{default,ccstatusline-settings,hooks,mcp-servers,wrappers}.nix`)

#### Scenario: A file assigns into base directly

- **WHEN** a throwaway tree adds a file assigning `flake.modules.nixos.base = { }`
- **THEN** `structure-aspect-parts` fails naming that file

#### Scenario: A part is in no list

- **WHEN** a throwaway tree removes `base-zram-swap` from `flake.lib.nixosBaseParts`, or adds `flake.modules.darwin.base-unlisted = { }`
- **THEN** `structure-aspect-parts` fails naming `base-zram-swap`, or `base-unlisted`

#### Scenario: A second file assigns into an existing part

- **WHEN** a throwaway tree adds a file assigning `flake.modules.nixos.base-zram-swap = { }`, or a tenth file assigning into `flake.modules.darwin.base-system-defaults`
- **THEN** `structure-aspect-parts` fails naming that file and the part

#### Scenario: The key set is read

- **WHEN** `nix eval .#checks.x86_64-linux --apply builtins.attrNames` runs
- **THEN** it lists `structure-aspect-parts` without evaluating any module the check reads

### Requirement: Each step is accepted on its own derivation comparison

Each step SHALL be one commit accepted by `just drv-diff` against an allow-list naming exactly the attributes it changes, and by `drv-order-trace.py` over every changed toplevel and home, which accepts at a leaf only `chosenOutputs` order of a named profile build or the order of the three `gh-dash` bindings.

Trust boundary: no attribute moves undeclared and no other field differs; what profiles link is compared on builds before landing (A376).

#### Scenario: A leaf differs in another field

- **WHEN** `drv-order-trace.py` finds a leaf derivation differing in any field other than `structuredAttrs.chosenOutputs` of `system-path`, `system-applications`, `home-manager-path`, `home-manager-fonts` or `home-manager-applications`, or `structuredAttrs.value.keybindings.prs` of `gh-dash-config.yml` holding exactly the three measured bindings, even when it holds the same entries, words or lines
- **THEN** it exits non-zero naming the field, the step is not accepted, and the field is never added to an allow-list

#### Scenario: The reordered profiles are built

- **WHEN** every build the trace accepts under `chosenOutputs` order is built at the step's parent and at its commit
- **THEN** every symlink, listed without following links, has the same path and the same `readlink` target in both

#### Scenario: The NixOS step

- **WHEN** the NixOS step's drv-diff runs
- **THEN** no toplevel and no home differs, `checks.x86_64-linux.structure-aspect-parts` is added and `checks.x86_64-linux.fleet-alert` changes, and nothing else outside the base allow-list differs

#### Scenario: The darwin step

- **WHEN** the darwin step's drv-diff runs
- **THEN** exactly the four darwin toplevels and `checks.aarch64-darwin.darwin-{argentum,blackphos,rosegold,stibnite}` change, and each Mac's `environment.systemPackages` holds the same members while `users.knownUsers`, `users.knownGroups` and every uid and gid are equal

#### Scenario: The ai step

- **WHEN** the ai step's drv-diff runs
- **THEN** the ten toplevels, the homes `cameron@*` and `crs58@*`, `checks.x86_64-linux.nixos-{cinnabar,electrum,galena,magnetite,pyrite}`, `checks.aarch64-darwin.darwin-*` and `checks.{x86_64-linux,aarch64-darwin}.home-manager-crs58` change, each reached `home.packages` holds the same members, and no other home changes
