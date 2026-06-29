# Caching strategies

This reference documents the three tiers of caching in nix CI pipelines, the source filtering patterns that drive nix-layer cache efficiency, shared artifact patterns that avoid redundant computation, binary cache configuration, and the CI job-result cache that operates above the nix layer.


## Content-addressed source patterns

Derivation hashes determine cache identity.
When a derivation's inputs change, it invalidates and must be rebuilt.
Source filtering controls which file changes actually propagate to derivation inputs, making it the primary lever for cache efficiency.

`builtins.path` with a fixed `name` parameter produces content-addressed store paths.
The store path is derived from the content hash, not the filesystem path.
Without a fixed name, the store path includes the checkout directory name, causing unnecessary rebuilds when the checkout location changes (different CI runner paths, different developer home directories).

```nix
src = builtins.path {
  path = ./.;
  name = "ironstar-src";
  filter = path: type:
    # include only files relevant to this derivation
    ...;
};
```

`crane.filterCargoSources` applies Rust-specific filtering.
It includes `*.rs` files, `Cargo.toml`, `Cargo.lock`, and build scripts while excluding tests, benches, examples, and documentation.
Changes to a README, a test file, or a CI configuration do not invalidate the Rust build cache.
This filter is the standard for crane-based Rust builds and should be used unless the derivation genuinely depends on excluded files.

`lib.fileset.toSource` combined with `lib.fileset.unions` provides precise file set composition for JavaScript, TypeScript, and other ecosystems.
Rather than filtering out unwanted files, this approach declares exactly which files and directories constitute the source.
The resulting store path reflects only the declared contents:

```nix
src = lib.fileset.toSource {
  root = ./.;
  fileset = lib.fileset.unions [
    ./src
    ./package.json
    ./tsconfig.json
    ./bun.lock
  ];
};
```

Lockfile-based dependency fetchers derive their store paths from lockfile contents.
`bun2nix.fetchBunDeps` with a `bun.nix` lockfile, uv2nix workspace overlays resolving from `uv.lock`, and `npmDeps` from `package-lock.json` all produce dependency store paths that change only when the lockfile changes.
Source code changes that do not modify the lockfile result in cache hits for the dependency fetch phase, which is typically the most expensive phase of a JavaScript or Python build.


## Shared artifact patterns

Several patterns allow expensive intermediate artifacts to be computed once and shared across multiple downstream derivations.

Crane's `buildDepsOnly` produces a compiled-dependencies artifact from `Cargo.lock` and `Cargo.toml` without compiling workspace source code.
This artifact is shared across `cargoClippy`, `cargoNextest`, and `buildPackage`.
Compiling dependencies is the most expensive phase of a Rust build.
Sharing the artifact across clippy (lint), nextest (test), and the final binary (build) avoids tripling the dependency compilation time.
The artifact invalidates only when `Cargo.lock` or `Cargo.toml` changes.

```nix
cargoArtifacts = craneLib.buildDepsOnly { inherit src pname version; };

clippy = craneLib.cargoClippy { inherit cargoArtifacts src pname version; };
nextest = craneLib.cargoNextest { inherit cargoArtifacts src pname version; };
package = craneLib.buildPackage { inherit cargoArtifacts src pname version; };
```

`bun2nix.fetchBunDeps` produces a node_modules tree from `bun.nix` that is shared across build, lint, test, and typecheck derivations for JavaScript/TypeScript packages.
The same pattern applies to `npmDeps` for npm-based projects and `yarnDeps` for yarn-based projects.

uv2nix workspace overlays resolve the full Python dependency graph from `uv.lock` into a package set.
Individual packages and their test derivations share this resolved dependency set, avoiding redundant resolution and download.


## Binary cache configuration

Binary caches store pre-built derivations indexed by store path hash.
When a derivation's store path matches an entry in a binary cache, the pre-built result is downloaded instead of building locally.

niks3 is a NixOS module (`nix/nixosModules/niks3.nix`) that provides a binary cache backed by S3-compatible storage.
Cloudflare R2 is the recommended backend for self-hosted deployments.
niks3 handles signing (derivations are signed with the cache's private key before upload), garbage collection (removing derivations that are no longer referenced), and serving (HTTP endpoint that nix clients query for narinfo and nar files).

Cachix provides a managed binary cache service.
The `cachix/cachix-action` GitHub Action handles authentication and upload.
The free tier has storage limits that cause eviction under sustained CI load.
For CI-heavy projects with many derivations, the free tier's storage ceiling can result in cache misses for derivations that were recently pushed but have been evicted to make room for newer ones.

Substituter ordering in `nix.conf` determines lookup priority:

```
substituters = https://niks3.example.com https://mycache.cachix.org https://cache.nixos.org
```

The order matters: nix tries each substituter in sequence and uses the first one that has the derivation.
Placing the self-hosted cache first ensures that project-specific derivations are served from the fast, local cache rather than falling through to cache.nixos.org (which only has nixpkgs derivations).

`nixConfig.extra-substituters` in `flake.nix` makes project-specific caches available to any user who builds the flake:

```nix
nixConfig = {
  extra-substituters = [ "https://niks3.example.com" ];
  extra-trusted-public-keys = [ "niks3.example.com:AAAA..." ];
};
```

This allows contributors to benefit from the project's binary cache without manually configuring their `nix.conf`.
The `extra-` prefix appends to the user's existing configuration rather than overriding it.


## GitHub Actions job-result cache

The `cached-ci-job` composite action provides a caching layer above the nix layer.
It computes SHA256 hashes of glob-matched source files (e.g., `src/**/*.rs`, `Cargo.lock`, `Cargo.toml`) to produce a cache key.
When the key matches a prior successful run, the entire GitHub Actions job exits early without invoking nix at all.

This caching is orthogonal to nix store caching.
Even if every nix derivation would be a cache hit, the CI job still spends time on checkout, nix setup, nix-fast-build invocation, and cache push.
The job-result cache eliminates all of that overhead for unchanged source sets.

The glob patterns for cache key computation should match the source filtering patterns used in the nix derivations.
If a Rust check uses `crane.filterCargoSources` to filter its input, the job-result cache should hash `src/**/*.rs`, `Cargo.toml`, and `Cargo.lock`.
Misalignment between the two filtering layers (job-result cache key includes files the nix derivation ignores, or vice versa) reduces cache hit rates.


## The `cache-overlay-packages` anti-pattern

Some CI configurations include a dedicated `cache-overlay-packages` job that builds overlay packages before other jobs run.
The intent is to warm the binary cache so that subsequent jobs hit the cache instead of building from source.

Under nix-fast-build, this dedicated job is unnecessary.
nix-fast-build's `--skip-cached` flag checks the binary cache before building each derivation.
Derivations that exist in the cache are skipped; derivations that do not exist are built and (with `--niks3-server`) pushed to the cache.
This cache-warming behavior is integrated into the normal build pipeline.

The dedicated job adds wall time to CI runs (it must complete before dependent jobs start) without providing any benefit that nix-fast-build does not already provide.
Removing it simplifies the workflow and reduces total CI execution time.


## niks3 vs cachix tradeoff analysis

niks3 on Cloudflare R2 provides self-sovereign storage.
There is no free-tier storage ceiling, so derivations are never evicted due to usage limits.
Retention is controlled by the operator (via niks3's garbage collection configuration), not by the service provider.
Cost is proportional to usage: R2 charges for storage and egress, but there are no per-derivation or per-organization fees.
The tradeoff is operational overhead: the operator must provision and maintain the niks3 NixOS module, R2 bucket, DNS records, and signing keys.

Cachix provides a managed service.
Setup is minimal: create an account, create a cache, add the `cachix/cachix-action` to GitHub Actions.
The free tier provides a useful starting point for small projects.
The tradeoff is that the free tier's storage limit (currently 5 GB) causes eviction under sustained CI load.
Projects that build many derivations frequently (monorepos, projects with many check categories, projects with cross-compilation) can exceed the free tier and experience declining cache hit rates as older derivations are evicted.

For projects that have already provisioned niks3 infrastructure (e.g., as part of a buildbot-nix deployment), using niks3 as the binary cache adds negligible operational overhead since the infrastructure already exists.
For projects without existing infrastructure, cachix provides faster time-to-value at the cost of the storage ceiling.

A hybrid approach is viable: use cachix for small projects and niks3 for CI-heavy projects, with both configured as substituters in the appropriate order.
