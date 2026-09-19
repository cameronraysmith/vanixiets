---
title: Nix packaging status of the observability candidates
status: research v1
date: 2026-09-18
sources:
  - NixOS/nixpkgs@85f62611 (vanixiets root `nixpkgs` lock node, commit date 2026-08-04)
  - NixOS/nixpkgs@c6bdd285 (nixpkgs `master`, fetched 2026-09-18)
  - GreptimeTeam/greptimedb@20d87cff
  - juspay/services-flake@1c9142a
  - nix-darwin/nix-darwin@4cff07de (the flake's locked `nix-darwin` input, read from its store source)
  - https://api.github.com/repos/GreptimeTeam/greptimedb/releases (fetched 2026-09-18)
  - https://github.com/NixOS/nixpkgs/pull/560084 (fetched 2026-09-18)
---

# Nix packaging status of the observability candidates

## Candidate matrix

Versions are from `nix eval` against the flake's root `nixpkgs` input, `NixOS/nixpkgs@85f62611`.
Module paths are `nixos/modules/...` in that same revision.
"Darwin" is `aarch64-darwin ∈ meta.platforms` with `meta.broken = false` and a successful evaluation.

| Candidate attr | Version at pin | NixOS module path | Option prefix | Darwin | Packaging work required |
|---|---|---|---|---|---|
| `perses` | 0.53.1 | `services/monitoring/perses.nix` | `services.perses` | yes | none |
| `opentelemetry-collector` | 0.155.0 | `services/monitoring/opentelemetry-collector.nix` | `services.opentelemetry-collector` | yes | none |
| `opentelemetry-collector-contrib` | 0.155.0 | same module, not the default `package` | `services.opentelemetry-collector` | yes | set `package` to the contrib attr |
| `vector` | 0.57.0 | `services/logging/vector.nix` | `services.vector` | yes | none |
| `grafana-alloy` | 1.17.1 | `services/monitoring/alloy.nix` | `services.alloy` | yes | none |
| `alloy` | 5.1.0 | none | none | yes | not the Grafana product (see Flags) |
| `victoriametrics` | 1.148.0 | `services/databases/victoriametrics.nix` | `services.victoriametrics` | yes | none |
| `victorialogs` | 1.52.0 | `services/databases/victorialogs.nix` | `services.victorialogs` | yes | none |
| `victoriatraces` | 0.10.0 | `services/databases/victoriatraces.nix` | `services.victoriatraces` | yes | none |
| `clickhouse` | 26.7.1.1315-stable | `services/databases/clickhouse.nix` | `services.clickhouse` | yes | none |
| `grafana` | 13.1.1 | `services/monitoring/grafana.nix` | `services.grafana` | yes | none |
| `prometheus` | 3.13.2 | `services/monitoring/prometheus/default.nix` | `services.prometheus` | yes | none |
| `grafana-loki` | 3.7.4 | `services/monitoring/loki.nix` | `services.loki` | yes | none |
| `loki` | 0.1.7 | none | none | yes | not the log store (see Flags) |
| `tempo` | 3.0.2 | `services/tracing/tempo.nix` | `services.tempo` | yes | none |
| `mimir` | 3.1.4 | `services/monitoring/mimir.nix` | `services.mimir` | yes | none |
| `grafana-tempo`, `grafana-mimir` | absent | — | — | — | attribute names do not exist |
| `greptimedb` | absent at pin | none, at the pin or on `master` | — | `platforms = unix` on `master` | one of three routes below |

## Findings

F1.
The flake's root `nixpkgs` input resolves to lock node `nixpkgs_9`, a `nixos/unstable-small` tarball at rev `85f62611fa3f3eacbcfe3bc7a6d6518b443ca442`, whose commit date is 2026-08-04 (`flake.lock`; `git log -1 85f62611` in the local nixpkgs checkout).
F2.
The lock also contains a distinct node literally named `nixpkgs` at `044bfe75bfe4c7bbe043dc17b5e42ea823b84a09`, which every other input's `nixpkgs` resolves to, so "the pinned nixpkgs" is ambiguous unless the lock node is named (`flake.lock`).
F3.
`perses` is 0.53.1 with `aarch64-darwin` in `meta.platforms`, defined at `NixOS/nixpkgs@85f62611:pkgs/by-name/pe/perses/package.nix`, confirming W4.
F4.
The Perses NixOS module is 131 lines with `options.services.perses` at `NixOS/nixpkgs@85f62611:nixos/modules/services/monitoring/perses.nix:30`, a freeform `settings` option at `:51`, `loadCredential` support at `:25`, and a `DynamicUser` unit with `StateDirectory = "perses"` at `:91` and `:95`.
F5.
Both `opentelemetry-collector` and `opentelemetry-collector-contrib` are 0.155.0, generated from `opentelemetry-collector-releases` v0.155.0 through upstream's `ocb` builder as a fixed-output source derivation feeding `buildGoModule` (`NixOS/nixpkgs@85f62611:pkgs/tools/misc/opentelemetry-collector/releases.nix:19-52`), confirming W6 for the collector.
F6.
The collector module's `package` default is the core distribution, not contrib (`NixOS/nixpkgs@85f62611:nixos/modules/services/monitoring/opentelemetry-collector.nix:42`), so any receiver or exporter outside the core distro requires an explicit `package` assignment.
F7.
`vector` is 0.57.0 with a module whose `package` default is `pkgs.vector` (`NixOS/nixpkgs@85f62611:nixos/modules/services/logging/vector.nix:11-14`), confirming W6 for Vector.
F8.
The NixOS module named `alloy` sets `package = lib.mkPackageOption pkgs "grafana-alloy"` (`NixOS/nixpkgs@85f62611:nixos/modules/services/monitoring/alloy.nix:18-21`), and `grafana-alloy` is 1.17.1 (`pkgs/by-name/gr/grafana-alloy/package.nix`).
F9.
`greptimedb` does not exist as an attribute at the pin on either `aarch64-darwin` or `x86_64-linux`, and `git ls-tree -r 85f62611 | grep -i greptime` returns nothing, confirming W5 as stated at that revision.
F10.
`greptimedb` was added to nixpkgs at 1.1.4 in commit `c6b2f0a1dd0c` dated 2026-08-30, twenty-six days after the pin's commit date, with a follow-up `c6bdd2851bc9` on 2026-09-04 disabling release debug info; neither commit is an ancestor of the pin (`git merge-base --is-ancestor`).
F11.
The upstream derivation is a from-source `rustPlatform.buildRustPackage` with `cargoBuildFlags = ["--package" "cmd"]`, `nativeBuildInputs = [cmake pkg-config protobuf rustPlatform.bindgenHook]`, `buildInputs = [zlib]`, `doCheck = false`, `versionCheckHook`, `meta.license = asl20`, `meta.platforms = lib.platforms.unix`, and `maintainers = [happysalada]` (`NixOS/nixpkgs@c6bdd285:pkgs/by-name/gr/greptimedb/package.nix`).
F12.
It carries three source workarounds: neutralising `otel-arrow-rust`'s `build.rs`, rewriting `std::sync::Exclusive` to `SyncView`, and raising the frontend crate's recursion limit, plus `RUSTC_BOOTSTRAP = 1` to satisfy the crates' nightly feature gates on stable rustc (`NixOS/nixpkgs@c6bdd285:pkgs/by-name/gr/greptimedb/package.nix:31-41`, `:56-61`).
F13.
GreptimeDB's own `rust-toolchain.toml` pins `nightly-2026-03-21` and its in-tree `flake.nix` supplies that channel through `fenix` plus `libgit2`, `zlib`, `clang`, `protobuf` and `mold` in a dev shell only, exposing no package output (`GreptimeTeam/greptimedb@20d87cff:rust-toolchain.toml`, `GreptimeTeam/greptimedb@20d87cff:flake.nix`).
F14.
Build magnitude: `Cargo.lock` holds 1404 `[[package]]` entries and the workspace declares 69 `src/` members (`GreptimeTeam/greptimedb@20d87cff:Cargo.lock`, `GreptimeTeam/greptimedb@20d87cff:Cargo.toml`), and the debug-info PR reports wall-clock 42m51s before and 34m26s after on an eight-core machine (https://github.com/NixOS/nixpkgs/pull/560084 fetched 2026-09-18).
F15.
The `-bin` route is supported by upstream artifacts: release v1.2.1 of 2026-09-16 publishes `greptime-darwin-arm64-v1.2.1.tar.gz` (153.6 MB), `greptime-darwin-amd64` (161.5 MB), `greptime-linux-amd64` (168.8 MB), `greptime-linux-arm64` (177.3 MB) and a `.sha256sum` beside each, and a darwin-arm64 tarball is present in each of the six most recent releases (https://api.github.com/repos/GreptimeTeam/greptimedb/releases fetched 2026-09-18).
F16.
That artifact supply is nevertheless conditional rather than contractual: the macOS matrix job is gated on `inputs.build_macos_artifacts || push || schedule` and the release-creation job accepts `needs.build-macos-artifacts.result == 'skipped'` (`GreptimeTeam/greptimedb@20d87cff:.github/workflows/release.yml:297`, `:622`).
F17.
No NixOS module for GreptimeDB exists at the pin or on `master`: `git ls-tree -r origin/master -- nixos/modules/services | grep -i greptime` returns nothing (nixpkgs checkout, fetched 2026-09-18).
F18.
The house `-bin` convention is a per-triple `fetchurl` table keyed on `stdenv.hostPlatform.system` with `autoPatchelfHook` on Linux, `versionCheckHook`, `sourceProvenance = [binaryNativeCode]`, and an `update.sh` (`pkgs/by-name/worktrunk-bin/package.nix:9-73`).
F19.
The convention's decision rule is written down in two places: `-bin` is chosen when a source build cannot reproduce upstream's release identity or build pipeline, as when the version is stamped at release time (`pkgs/by-name/mergify-cli-bin/package.nix:1-7`) or the assets come from a GoReleaser/cargo-zigbuild pipeline (`pkgs/by-name/uncomment-bin/package.nix:1-4`); hashes are transcribed from upstream's published sums rather than prefetched (`pkgs/by-name/mergify-cli-bin/package.nix:16-18`).
F20.
The from-source Rust convention is `rustPlatform.buildRustPackage` with a vendored `cargoLock.lockFile = ./Cargo.lock` copied over the source tree in `postPatch`, native inputs listed explicitly, and Darwin-specific `preBuild` fixups where the vendored C sources need them (`pkgs/by-name/xsra/package.nix:18-49`).
F21.
The by-name tree is flat with `pkgsNameSeparator = "-"`, so the path would be `pkgs/by-name/greptimedb/` with no two-letter shard (`modules/nixpkgs/per-system.nix:51-52`).
F22.
Every by-name package silently becomes a `nix flake check` entry named `package-<attr>` on every configured system unless blacklisted, and the blacklist already carries a precedent category for "thin upstream re-package, fully cache-resident on cache.nixos.org" (`modules/checks/packages.nix:15-39`).
F23.
The overlay layer exposes `pkgs.stable` and `pkgs.unstable` from the `nixpkgs-{darwin,linux}-stable` and `nixpkgs` inputs (`modules/nixpkgs/overlays/channels.nix:39-57`), and `stable-fallbacks.nix` is the sanctioned place to swap a single attribute per platform (`modules/nixpkgs/overlays/stable-fallbacks.nix:15-34`); there is no node newer than the root `nixpkgs`, so pulling `greptimedb` from a later nixpkgs means either bumping the root pin or adding an input.
F24.
Precedent exists for pinning a nightly Rust channel inside an overlay via `rust-overlay` and a committed channel marker (`modules/nixpkgs/overlays/aeneas.nix:77-79`, `modules/nixpkgs/overlays/rust-toolchain`), so the nightly question is not a blocker even if `RUSTC_BOOTSTRAP` were rejected.
F25.
nix-darwin ships no collector or telemetry-agent module: its `modules/services/monitoring/` contains exactly `netdata.nix`, `telegraf.nix` and `prometheus-node-exporter.nix` out of 42 service entries, with no Vector, OpenTelemetry Collector or Alloy module (`nix-darwin/nix-darwin@4cff07de:modules/services/monitoring/`, read 2026-09-18).
F26.
`juspay/services-flake@1c9142a` (2026-07-05, present locally) provides `clickhouse`, `grafana` and `loki` services but no `greptimedb`, `perses`, `vector` or `opentelemetry-collector` (`juspay/services-flake@1c9142a:nix/services/`).
F27.
No third-party flake providing a GreptimeDB or Perses NixOS module was found; `ghq list -p` shows only `GreptimeTeam/greptimedb`, `GreptimeTeam/dashboard` and `perses/perses` locally, and web search returned no `services.greptimedb` implementation, only the nixpkgs package and unrelated flake tutorials (fetched 2026-09-18).
F28.
GreptimeDB's tree carries both `LICENSE` and `LICENSE-ENTERPRISE` (`GreptimeTeam/greptimedb@20d87cff`), while the nixpkgs derivation declares `meta.license = lib.licenses.asl20` alone (F11), so the packaging metadata asserts nothing about the enterprise boundary W7 flags.

## Bearing on decisions

D1 (store).
Packaging cost no longer discriminates against GreptimeDB as strongly as RK6 assumes: the derivation exists upstream, maintained by a nixpkgs maintainer, and only the pin's age keeps it out (F9, F10, F11).
The residual cost is that no NixOS module exists anywhere (F17), so the service unit is first-party work for whichever route is chosen, whereas VictoriaMetrics/VictoriaLogs/VictoriaTraces, ClickHouse and the Grafana stack all arrive with both package and module at the pin (matrix).
This would reverse if the root pin cannot be bumped for unrelated fleet reasons and a cherry-pick overlay is judged more ceremony than a store with zero packaging work.

D3 (collection topology).
On NixOS every collector candidate has an upstream module with a `DynamicUser` unit, so a per-host agent is close to free (F4, F6, F7, F8).
On `aarch64-darwin` there is no module for any of them, so a nix-darwin host needs a first-party `launchd` module regardless of which collector is chosen (F25), and `services-flake` does not shorten that path for the fleet case (F26).
This would reverse if the Darwin hosts are instead treated as emitters shipping straight to a central gateway, which removes the launchd module from the critical path.

D7 (packaging, host placement, clan service shape).
Three routes exist for GreptimeDB, in ascending first-party cost: bump the root `nixpkgs` pin past 2026-08-30 and consume `pkgs.greptimedb`; add a newer nixpkgs input and select the attribute in an overlay, following the `stable-fallbacks.nix` shape (F23); or write `pkgs/by-name/greptimedb/` ourselves, either vendoring the upstream expression (F11, F12) or as a `-bin` proxy over the release tarballs (F15).
C6's own criterion — "a `-bin` proxy only where upstream ships reliable release artifacts" — is satisfied on artifact availability and checksums but weakened by the conditional macOS job (F16), so a `-bin` proxy is defensible for Linux and fragile for Darwin.
A from-source route costs a 1404-crate vendor fetch and a roughly half-hour eight-core build (F14) plus a `package-greptimedb` flake check on every configured system unless blacklisted under the existing "thin upstream re-package" precedent (F22).
This would reverse toward `-bin` if the store must run on a Darwin host, and toward the pin bump if the fleet is already due one.

D2 (dashboard layer).
Perses needs no packaging work at the pin and its module exposes freeform `settings` plus `loadCredential`, which is the surface a datasource secret would use (F3, F4).

## Flags

Charter W6 is wrong on Alloy.
`alloy` at the pin is 5.1.0 of alloytools.org, "Language & tool for relational models", MIT-licensed; the Grafana product is `grafana-alloy` 1.17.1 under Apache-2.0, which is what `services.alloy` defaults to (F8).
Any design text that writes "alloy 5.1.0" as a collector candidate is naming the wrong program.

The same attribute-name hazard applies to Loki.
`loki` at the pin is 0.1.7, the C++ design-patterns library; the log store is `grafana-loki` 3.7.4, which `services.loki` defaults to (matrix, F8-adjacent module reading).
`grafana-tempo` and `grafana-mimir` are not attribute names at all; the store attrs are `tempo` and `mimir`.

Charter W5 is correct at the pin but its risk framing RK6 is not.
RK6's confirming observation — "no reliable upstream release artifact exists for our platforms, forcing a from-source build into the critical path" — is not observed: upstream ships checksummed Linux and Darwin tarballs (F15), and in addition nixpkgs already carries a from-source derivation that someone else maintains (F10, F11).
The live risk is narrower: the pin predates that derivation by twenty-six days (F10), and no NixOS module exists in any revision (F17).

W4's citation of the lock node is correct but the lock is ambiguous.
Two distinct nixpkgs revisions appear in `flake.lock`, one named `nixpkgs` and the root's own node `nixpkgs_9`, and only the latter is the repository's nixpkgs (F1, F2).

Vendor prose versus source.
Upstream's own `flake.nix` advertises only a dev shell and no package output (F13), so any statement that GreptimeDB "supports Nix" means a development environment, not a deployable derivation.
GreptimeDB's marketing position as a single OpenTelemetry backend is not contradicted by anything here, but the packaging metadata says nothing about which capabilities fall under `LICENSE-ENTERPRISE` (F28).

Absences reported explicitly: no GreptimeDB NixOS module upstream, no third-party flake for one, no `services-flake` entry for GreptimeDB, Perses, Vector or the OpenTelemetry Collector, and no nix-darwin module for any collector candidate (F17, F26, F27, F25).

## Questions

1. Is bumping the root `nixpkgs` pin past 2026-08-30 in scope for this design, or must the design assume `85f62611` and therefore carry a first-party `greptimedb` derivation or a second nixpkgs input?
2. If a first-party derivation is chosen, does C6's "reliable upstream release artifacts" test pass on artifacts produced by a conditionally-skipped CI job (F16), or does that conditionality force the from-source route?
3. Must the store run on `aarch64-darwin` at all, or is Darwin only an emitter host, since the answer decides whether a `-bin` proxy's Darwin asset matters?
4. Should a new `package-greptimedb` check be blacklisted under the existing "thin upstream re-package" category if the derivation is a `-bin` proxy, or is a half-hour source build acceptable inside the closure operator?
