# Dendritic module composition: import-tree and flake-parts module validity

Reference for the import-tree + flake-parts deferred-module-composition pattern used across the nix repos (vanixiets, ironstar, python-nix-template, Hodosome.jl).
Read this when structuring a flake's `modules/` tree, deciding where a `.nix` file belongs, or diagnosing why a file fails to load.

## Contents

- The pattern
- Two separate concerns: discovery vs merge
- import-tree file selection and API
- What qualifies as a valid flake-parts module (function form, attrset form, the option gate, `_class`)
- Litmus test
- Common crash causes and fixes
- flake-parts modules vs NixOS/home-manager modules
- Placement contract

## The pattern

The dendritic pattern composes a flake from many small flake-parts modules with no manual import list.
`flake.nix` is a thin trunk:

    outputs = inputs@{ flake-parts, ... }:
      flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);

`import-tree ./modules` walks the directory and returns a flake-parts module whose effect is `{ imports = [ ...every discovered .nix... ]; }`.
flake-parts loads that list with `lib.evalModules { class = "flake"; ... }` (see `evalFlakeModule` in flake-parts `lib.nix`), so all discovered files merge into one module-system fixpoint.
Adding a cross-cutting concern means dropping a `.nix` file into the tree; there is no import list to maintain.

## Two separate concerns: discovery vs merge

Keep these distinct; conflating them causes most confusion.

Merge is location-independent.
The NixOS module system composes by `imports` and folds every module into one fixpoint, so a module's directory has no bearing on how its options and config merge.
A `flake-module.nix` in `models/foo/` merges identically to one in `modules/`.

Discovery is location-bound.
import-tree only sees files under the root(s) you give it.
With `import-tree ./modules`, a module elsewhere in the tree is never found — no error, just silently unwired.

## import-tree file selection and API

Selection: import-tree recursively imports every `*.nix` file under the root, excluding any whose path contains the infix `/_` (so `_`-prefixed files and directories are hidden).
The filter is purely path-based — `andNot (lib.hasInfix "/_") (lib.hasSuffix ".nix")` applied to each leaf's root-relative path.
It is content-blind: every matching file is added to `imports` unconditionally, so a non-module file under the root crashes evaluation (see crash causes).

API for distributing modules across roots:

- Multiple roots: `import-tree [ ./modules ./other ]` (nested lists are flattened) or `(import-tree.addPath ./other)`.
- Filename filter (keeps auto-discovery while letting modules live beside their components): `import-tree.filter (lib.hasSuffix "/flake-module.nix") [ ./modules ./models ./platform ]`.
- Other fluent methods: `.filterNot`, `.match` / `.matchNot` (regex over the path), `.map`, `.addAPI`, `.withLib`, `.leafs`.

The `/_` exclusion is also an escape hatch: park a helper under a `_`-prefixed directory inside the root and it is discovered-but-skipped, importable manually by the modules that need it.

## What qualifies as a valid flake-parts module

A file is import-tree-safe iff, after `import`, its value is a module of one of the two forms below, and every config value it defines lands on a declared option or a freeform type.

### Function form

`args: body`, subject to two requirements enforced by `applyModuleArgs` in nixpkgs `lib/modules.nix`:

- The pattern must end in `...`.
  The module system applies the function to the full standard args set (`lib`, `options`, `config`, plus specialArgs `self` / `inputs` / `flake-parts-lib` / `moduleLocation`), so a pattern without `...` (e.g. `{ lib }:`) is rejected by the evaluator as "called with unexpected argument".
- Every named formal must resolve to a flake-level module argument.
  Each formal is resolved as `args.<name> or config._module.args.<name>`; a formal that is neither (e.g. `stdenv`, or `pkgs` at the flake top level) throws a missing-argument error.
  At flake class the resolvable names are `lib`, `options`, `config`, `self`, `inputs`, `flake-parts-lib`, `moduleLocation`, and anything registered in `config._module.args` (`getSystem`, `withSystem`, `moduleWithSystem`).

`pkgs`, `stdenv`, `system`, `self'`, `inputs'` are not flake-level args; they are injected only inside a `perSystem` evaluation.
Reference them by nesting `perSystem = { pkgs, ... }: { ... }`, never as a top-level formal.

Minimal valid function module: `{ ... }: { }`.

### Attrset form

Classified by `unifyModuleSyntax` in `lib/modules.nix`:

- Explicit form — has `config` and/or `options`.
  Then every other top-level key must come only from the structural set `{ _class, _file, key, disabledModules, imports, options, config, meta, freeformType }`.
  Mixing a non-reserved key with `config` / `options` throws "has an unsupported attribute ... caused by introducing a top-level config or options attribute".
- Shorthand form — has neither `config` nor `options`.
  Then every non-structural top-level key is reinterpreted as a `config` definition.

Minimal valid attrset modules: `{ }`, `{ imports = [ ]; }`.

### The option-must-exist gate and `_class`

Every resulting `config.<path>` must match a declared option or a freeform type, or the merge throws "The option `<path>` does not exist".
At the flake root the declared top-level options include `flake`, `perSystem`, `systems`, `transposition`, `debug`, `_module`.
The freeform escape hatches are `flake.<anything>` (its freeformType is `lazyAttrsOf (unique raw)`, so arbitrary flake outputs like `flake.lib.foo` are accepted) and `perSystem.<declared-option>` (`packages`, `checks`, `apps`, `devShells`, `formatter`, `legacyPackages`).
For anything else, declare the option yourself with `options.<path> = lib.mkOption { ... }` in the same file.

`_class`: `checkModule` accepts a module iff its `_class` is null or equals the evaluation class (`"flake"`).
Omit `_class` for portability; a file tagged `_class = "nixos"` or `"perSystem"` is rejected at the flake root.

## Litmus test

Before placing a file under the import-tree root, ask: imported, is it an attrset or function-to-attrset whose only top-level keys are structural keys or flake-parts-declared options (or options it declares itself), and — if a function — does it end in `...` requesting only flake-level args?
If yes, it is safe.
If no, it belongs outside the root (in `lib/`, `pkgs/by-name/`, or a `_`-prefixed directory).

## Common crash causes and fixes

| File | Why it crashes | Fix |
|---|---|---|
| `{ stdenv, ... }: stdenv.mkDerivation { ... }` (a callPackage package) | `stdenv` is a perSystem / package-set arg, unresolvable at flake class, so resolution throws a missing module argument | Keep it in `pkgs/by-name/<name>/package.nix` outside the root; instantiate from a module: `perSystem = { pkgs, ... }: { packages.foo = pkgs.callPackage ../../pkgs/foo.nix { }; }` |
| `{ lib }: someFn` (a plain helper) | No `...`, so the full args set makes it "called with unexpected argument"; and a function returning a non-attrset is not a module | Keep it in `lib/` outside the root and `import` it; or expose it via `flake.lib.foo = ...` inside a module |
| `{ foo = 1; }` (a bare data attrset) | Shorthand turns it into `config.foo = 1`; `foo` is no declared option, so the merge says "option does not exist" | Nest under a freeform/declared option: `{ flake.foo = 1; }`; or declare `options.foo` |

## flake-parts modules vs NixOS/home-manager modules

Both are called "modules" and both use the NixOS module system, but they evaluate in different classes with different available options and arguments.

- A flake-parts module (class `flake`) defines flake-level outputs: `flake.*`, `perSystem = { ... }: { packages.*; checks.*; ... }`, `systems`.
  This is what import-tree discovers under the flake's `modules/` root.
- A NixOS / home-manager module (class `nixos` / `homeManager`) defines system options such as `services.*`, `networking.*`, `home.*`, with the signature `{ config, lib, pkgs, ... }:`.
  These are consumed by `nixosConfigurations` / `homeConfigurations`, not placed directly in the flake's import-tree root.

Dropping a NixOS module into the flake root fails the option-must-exist gate, because its `services.*` / `networking.*` definitions are not flake-level options.

## Placement contract

| Directory | Holds | Pulled in by |
|---|---|---|
| `modules/` (import-tree root) | flake-parts modules only | auto-discovered by import-tree |
| `lib/` | plain functions, data attrsets | `import ../lib/foo.nix` / `pkgs.callPackage` from a module |
| `pkgs/by-name/<name>/package.nix` | package derivations | `pkgs-by-name-for-flake-parts` via `pkgsDirectory` |
| `_`-prefixed paths, `*.nix.txt` | parked / helper code | discovered-but-excluded; manual `import` |

Concrete house example: Hodosome.jl places its pure `lock-freshness.nix` in `nix/lib/` (not `nix/modules/`) precisely so import-tree does not load it as a module; `nix/modules/julia.nix` imports it explicitly.

For how checks fan in across these modules into the CCV closure, see preferences-nix-checks-architecture.
For CI execution of those checks, see preferences-nix-ci-cd-integration.
