# Derivation patterns by category

This reference provides nix expression skeletons for each check category, illustrating the structure, source filtering, and cacheability properties of each pattern.

## Formatting (treefmt-nix)

treefmt-nix integrates with flake-parts to produce a check derivation that fails if any file would be reformatted.
Formatters are declared in the treefmt module configuration.

```nix
# checks/treefmt.nix (flake-parts module)
{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem = { pkgs, ... }: {
    treefmt = {
      projectRootFile = "flake.nix";
      programs = {
        nixfmt.enable = true;
        rustfmt = {
          enable = true;
          # Use the project's rust toolchain for edition-aware formatting
          package = pkgs.rust-bin.stable.latest.rustfmt;
        };
        ruff-format.enable = true;
        ruff-check.enable = true;
        biome.enable = true;
        taplo.enable = true;
      };
    };
  };
}
```

treefmt-nix automatically produces a `checks.<system>.treefmt` derivation and sets `formatter.<system>` to the wrapped treefmt binary.
The check derivation runs all configured formatters in check mode and fails if any file differs from the formatted output.

Cacheability: the derivation depends on the full source tree, so it invalidates on any source change.
However, treefmt is fast enough that this is acceptable for most repositories.


## Security scanning (gitleaks)

gitleaks runs as a `pkgs.runCommand` derivation wrapping the scanner over the source tree.

```nix
# checks/gitleaks.nix (flake-parts module)
{ self, ... }:
{
  perSystem = { pkgs, ... }: {
    checks.gitleaks = pkgs.runCommand "gitleaks-check" {
      nativeBuildInputs = [ pkgs.gitleaks ];
      src = builtins.path {
        path = self;
        name = "source";
      };
    } ''
      gitleaks detect --no-git --source "$src" --verbose
      touch $out
    '';
  };
}
```

The `--no-git` flag is necessary because the nix store copy has no `.git` directory.
The `builtins.path` with a fixed `name` ensures the store path is content-addressed.

Cacheability: depends on `self` (the entire repository source), so the derivation invalidates on any file change.
This is inherent to the nature of secrets scanning, which must examine the full tree.
The scan itself is fast, so cache invalidation is acceptable.


## Rust (crane)

Crane provides a composable set of builders for Rust projects.
The key pattern is `buildDepsOnly` producing a shared artifact that clippy, nextest, and the final build all consume.

```nix
# checks/rust.nix (flake-parts module)
{ inputs, ... }:
{
  perSystem = { pkgs, system, ... }:
    let
      craneLib = inputs.crane.mkLib pkgs;

      src = builtins.path {
        path = craneLib.filterCargoSources ../.;
        name = "rust-source";
      };

      commonArgs = {
        inherit src;
        strictDeps = true;
        nativeBuildInputs = [ /* additional build inputs */ ];
      };

      cargoArtifacts = craneLib.buildDepsOnly commonArgs;
    in
    {
      checks = {
        rust-clippy = craneLib.cargoClippy (commonArgs // {
          inherit cargoArtifacts;
          cargoClippyExtraArgs = "--all-targets -- --deny warnings";
        });

        rust-nextest = craneLib.cargoNextest (commonArgs // {
          inherit cargoArtifacts;
          partitions = 1;
          partitionType = "count";
        });

        rust-build = craneLib.buildPackage (commonArgs // {
          inherit cargoArtifacts;
          doCheck = false; # tests run via nextest above
        });
      };
    };
}
```

`crane.filterCargoSources` includes `*.rs`, `Cargo.toml`, `Cargo.lock`, and build scripts while excluding everything else.
The `builtins.path` wrapper with a fixed name ensures content-addressed store paths.

Cacheability: `buildDepsOnly` depends only on `Cargo.toml` and `Cargo.lock`.
When only source files change, the dependency artifact is a cache hit and only the incremental compilation reruns.

### Per-crate isolation

For monorepo workspaces, `lib.genAttrs` generates per-crate check derivations:

```nix
checks = lib.genAttrs crateNames (crate:
  craneLib.cargoNextest (commonArgs // {
    inherit cargoArtifacts;
    cargoNextestExtraArgs = "-p ${crate}";
  })
);
```

This allows targeting a single failing crate without rebuilding the entire workspace.


## Python (uv2nix / pyproject-nix)

uv2nix with pyproject-nix is the preferred Python packaging approach, not nixpkgs' `buildPythonPackage`.
The workflow loads a workspace from a `uv.lock` file and produces a virtual environment.

```nix
# checks/python.nix (flake-parts module)
{ inputs, ... }:
{
  perSystem = { pkgs, system, ... }:
    let
      python = pkgs.python312;

      workspace = inputs.uv2nix.lib.workspace.loadWorkspace {
        workspaceRoot = ../.;
      };

      overlay = workspace.mkPyprojectOverlay {
        sourcePreference = "wheel";
      };

      editableOverlay = workspace.mkEditablePyprojectOverlay {
        root = "$REPO_ROOT";
      };

      pythonSet = (pkgs.callPackage inputs.pyproject-nix.build.packages {
        inherit python;
      }).overrideScope (lib.composeManyExtensions [
        inputs.pyproject-build-systems.overlays.default
        overlay
      ]);

      editablePythonSet = pythonSet.overrideScope editableOverlay;

      virtualenv = pythonSet.mkVirtualEnv "myproject-env" workspace.deps.default;

      testVirtualenv = pythonSet.mkVirtualEnv "myproject-test-env" (
        workspace.deps.default // workspace.deps.groups.dev or {}
      );
    in
    {
      packages.default = virtualenv;

      checks = {
        python-typecheck = pkgs.runCommand "basedpyright-check" {
          nativeBuildInputs = [ testVirtualenv pkgs.basedpyright ];
          src = builtins.path {
            path = ../.;
            name = "python-source";
          };
        } ''
          cd "$src"
          basedpyright
          touch $out
        '';

        python-test = pkgs.runCommand "pytest-check" {
          nativeBuildInputs = [ testVirtualenv ];
          src = builtins.path {
            path = ../.;
            name = "python-source";
          };
        } ''
          cd "$src"
          pytest --tb=short -q
          touch $out
        '';
      };
    };
}
```

The federated monorepo pattern uses independent `uv.lock` files per package, with overlays composed via `lib.composeManyExtensions` at the repository level.
Each package maintains its own dependency resolution while sharing a common Python version and build system overlay.

`mkPyprojectOverlay` produces the production overlay.
`mkEditablePyprojectOverlay` produces an editable overlay for the devshell where source changes are reflected without rebuilding.
`pyproject-build-systems.overlays.default` provides build system packages (setuptools, hatchling, maturin, etc.) that pyproject-nix needs.

Reference repos: `~/projects/nix-workspace/pyproject.nix`, `~/projects/nix-workspace/uv2nix`, `~/projects/nix-workspace/python-nix-template`.


## Rust/Python interop (crane-maturin)

crane-maturin bridges Rust compilation via crane with Python packaging via uv2nix.

```nix
let
  craneMaturinLib = inputs.crane-maturin.mkLib {
    inherit pkgs;
    crane = inputs.crane;
    rust-overlay = inputs.rust-overlay;
  };

  package = craneMaturinLib.buildMaturinPackage {
    src = ../.;
    python = pkgs.python312;
  };
in
{
  packages.default = package;
  checks = package.passthru.tests;
}
```

The `nixpkgsPrebuilt` function from pyproject-nix's hacks module (`pyproject-nix.build.hacks.nixpkgsPrebuilt`) injects the crane-maturin compiled output into the uv2nix package set, avoiding a second compilation during Python packaging.
The package exposes `passthru.tests` with pytest, clippy, documentation, formatting, and cargo test derivations.

Reference repo: `~/projects/nix-workspace/crane-maturin`.


## JavaScript/TypeScript (bun2nix)

bun2nix fetches dependencies from a `bun.lock` file and produces a reproducible `node_modules` directory.

```nix
# checks/js.nix (flake-parts module)
{ inputs, ... }:
{
  perSystem = { pkgs, ... }:
    let
      src = lib.fileset.toSource {
        root = ../.;
        fileset = lib.fileset.unions [
          ../src
          ../package.json
          ../bun.lock
          ../tsconfig.json
          ../biome.json
        ];
      };

      bunDeps = inputs.bun2nix.fetchBunDeps {
        inherit src;
        hash = "sha256-AAAA..."; # update via bun2nix
      };
    in
    {
      checks = {
        js-typecheck = pkgs.stdenv.mkDerivation {
          name = "tsc-check";
          inherit src;
          nativeBuildInputs = [ pkgs.bun pkgs.typescript ];
          configurePhase = ''
            cp -r ${bunDeps} node_modules
          '';
          buildPhase = ''
            tsc --noEmit
          '';
          installPhase = "touch $out";
        };

        js-test = pkgs.stdenv.mkDerivation {
          name = "vitest-check";
          inherit src;
          nativeBuildInputs = [ pkgs.bun ];
          configurePhase = ''
            cp -r ${bunDeps} node_modules
          '';
          buildPhase = ''
            bun run vitest run
          '';
          installPhase = "touch $out";
        };
      };
    };
}
```

`lib.fileset.toSource` with `lib.fileset.unions` precisely controls which files enter the derivation.
Changes to README files, CI configuration, or other unrelated files do not invalidate the check.

Playwright browser pinning uses the `playwright-web-flake` input to provide a browser binary whose version matches the npm package version.
See `preferences-typescript-nodejs-development` for the version parity constraint.


## `passthru.tests` wiring

Packages expose test derivations via `passthru.tests`, and the flake's `checks` output references them.

```nix
# In the package definition
packages.mypackage = pkgs.buildPackage {
  # ...
  passthru.tests = {
    unit = pkgs.runCommand "mypackage-unit-test" { /* ... */ } ''
      # run unit tests
      touch $out
    '';
    e2e = pkgs.runCommand "mypackage-e2e-test" { /* ... */ } ''
      # run e2e tests
      touch $out
    '';
  };
};

# In the checks module
checks = {
  mypackage-unit = config.packages.mypackage.passthru.tests.unit;
  mypackage-e2e = config.packages.mypackage.passthru.tests.e2e;
};
```

This pattern keeps the test definition co-located with the package it validates while making tests visible to `nix flake check` and CI fan-out.
The `config.packages` reference uses flake-parts' module system to access the package from the checks module without circular imports.
