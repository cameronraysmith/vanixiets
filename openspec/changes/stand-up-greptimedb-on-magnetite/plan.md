# GreptimeDB on magnetite (S1) implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run GreptimeDB 1.2.1 with its embedded Perses dashboard on magnetite, fed metrics-only by magnetite's own collector, bounded so it cannot take CI down, and reporting its own failures to ntfy.

**Architecture:** A first-party NixOS module `flake.modules.nixos.greptimedb` runs the upstream binary `greptimedb-bin` as `greptimedb.service` on loopback, with clan vars for credentials and R2, and a schema oneshot for databases and retention.
The `otel-collector` clan service runs both its `agent` and `ingress` roles on magnetite in one `opentelemetry-collector.service`, joined by an in-process `forward` connector, routing each database to its own OTLP/HTTP exporter into the store.
Evaluation-time checks with mutants, an hourly envelope oneshot and two on-demand runtime tests regulate it; a notifier template posts unit failures to ntfy.

**Tech Stack:** nix flakes with flake-parts and import-tree; clan-core services, inventory and vars; NixOS `services.opentelemetry-collector` with `opentelemetry-collector-contrib` 0.155.0; `services.prometheus.exporters.node`; nginx; ZFS; `pkgs.testers.runNixOSTest` with systemd-nspawn `containers` and QEMU `nodes`.

**Spec:** `openspec/changes/stand-up-greptimedb-on-magnetite/` — `design.md` (D1–D14), `specs/`, `tasks.md`; the decision records under `docs/notes/development/observability/` (charter v11).

## Global Constraints

- Repository: `/Users/crs58/projects/vanixiets`, jj-colocated; never relocate `@`; commit each plan task as one change off `main@origin` per the repository's jj workflow.
- Each plan task is one pull request, in the order below; each lands through the merge queue before the next task's PR is enqueued.
- Store version 1.2.1 from `greptime-linux-amd64-v1.2.1.tar.gz`, sha256 `062d5beb13de4991c4fec201b2e5071518bf4ca8f0d52947eba757a74c2a5420`; never a prerelease.
- Store listeners: HTTP `127.0.0.1:4000`, gRPC `127.0.0.1:4001`; MySQL, PostgreSQL, InfluxDB, OpenTSDB, Prometheus remote storage and Jaeger disabled; no firewall port; `http.enable_api_server` stays off in S1.
- Store envelope: `MemoryHigh = "3G"`, `MemoryMax = "4G"`, `MemorySwapMax = "0"`, `OOMScoreAdjust = 500`, `CPUWeight = 20`, `[runtime] global_rt_size = 4`, `compact_rt_size = 2`.
- Collector envelope: `memory_limiter` 384 MiB, `MemoryMax = "512M"`, `OOMScoreAdjust = 300`; sending queue in `file_storage`, at least 24 h, under 512 MiB.
- Databases and retention: `fleet` 30d, `devloop` 365d, `agent` 90d; no logs or traces table in S1.
- Passwords are hex; the users file has exactly four lines `admin:rw=`, `collector:wo=`, `perses:ro=`, `regulator:ro=`.
- No credential value in any repository file; credentials are clan vars consumed by path through `LoadCredential` or `EnvironmentFile`.
- Notices: topic `fleet-alerts` at `https://ntfy.zt`, anonymous; once per failure episode, `RESOLVED` on recovery.
- Runtime tests live under `vmTests`, never `checks`; the container test builds on magnetite (`uid-range`), the QEMU test on pyrite (`kvm`).
- nix-managed outputs are verified by `nix eval`, `nix build`, or inspecting the delivered path after activation, never by reading source.
- Long or output-heavy commands are captured: `<command> 2>&1 | tee logs/<identifier>-$(date +%Y%m%d-%H%M%S).log`, with any filter after the `tee`.
- Task 2's pull request carries the encrypted vars under `vars/per-machine/magnetite/{greptimedb-users,greptimedb-r2}/`, generated from its own branch after the human steps in Task 2, and the dataset exists on magnetite before it is enqueued, so `main` stays deployable for unrelated changes.

## Interface contract

Every task uses exactly these names.

| Kind | Name | Defined in |
|---|---|---|
| Package | `greptimedb-bin` (`mainProgram = "greptime"`, `passthru.embedsDashboard = true`, `passthru.dashboardVersion = "0.13.13"`) | Task 1 |
| Package | `ntfy-send` (`ntfy-send MESSAGE [TOPIC] [CURL_ARGS…]`, `mainProgram = "ntfy-send"`) | Task 1 |
| App | `apps.<system>.update-greptimedb-bin` | Task 1 |
| NixOS module | `flake.modules.nixos.greptimedb` at `modules/nixos/greptimedb.nix`; options `services.greptimedb.{enable,package,settings,databases}`, `databases` an attrset of database name to TTL string | Task 2 |
| Units | `greptimedb.service`, `greptimedb-schema.service` | Task 2 |
| Units | `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation`, `zfs-assert-root-greptimedb-noautosnap` | Task 2 |
| Generator | `greptimedb-users`: files `users`, `admin-password`, `collector-password`, `perses-password`, `regulator-password` | Task 2 |
| Generator | `greptimedb-r2`: prompts `access-key`, `secret-key`; file `env` | Task 2 |
| `LoadCredential` ids | `users` (store), `admin-password` (schema), `collector-password` (collector), `regulator-password` (envelope) | Tasks 2, 3, 4 |
| Check | `checks.x86_64-linux.greptimedb-envelope` at `modules/checks/greptimedb-envelope.nix` | Task 2, extended in Task 4 |
| Clan service | `clan.modules.otel-collector` at `modules/clan/services/otel-collector/flake-module.nix`, roles `agent`, `ingress` | Task 3 |
| Schema | `modules/clan/services/otel-collector/schema.nix` returning `{ systemdUnits; promotedResourceAttributes; nodeExporterKeep; process = { minBytes; maxNames; }; databases; }` | Task 3 |
| Inventory | `clan.inventory.instances.otel-collector` at `modules/clan/inventory/services/otel-collector.nix` | Task 3 |
| Notifier option | `services.observability-notify.units` (list of unit names), declared by the `agent` role; for each listed unit the role sets `OnFailure=observability-notify@%n.service` and the `RESOLVED` `ExecStopPost=`; magnetite's host config lists the units, so `greptimedb.nix` never references the notifier | Task 3 |
| Units | `observability-notify@.service`, `opentelemetry-collector.service`, `prometheus-node-exporter.service`; stamp directory `/var/lib/observability-notify` | Task 3 |
| nixbot metrics | nginx server on `127.0.0.1:9180`, `/metrics` proxied to `unix:/run/nixbot/web.sock` | Task 3 |
| Check | `checks.x86_64-linux.otel-collector-config` at `modules/checks/otel-collector-config.nix` | Task 3 |
| Units | `greptimedb-envelope.service`, `greptimedb-envelope.timer` (hourly) | Task 4 |
| vmTests | `vmTests.x86_64-linux.greptimedb-pipeline` (`modules/vm-tests/greptimedb-pipeline.nix`), `vmTests.x86_64-linux.greptimedb-oom-order` (`modules/vm-tests/greptimedb-oom-order.nix`) | Task 5 |

## Task map

| Plan task | `tasks.md` items | Pull request |
|---|---|---|
| Task 1: Packages | 1.1–1.3 | 1 |
| Task 2: Store, with its evaluation-time regulators | 2.1–2.6, 4.1–4.3, 8.1–8.3 | 2 |
| Task 3: Collector, notifier and nixbot metrics, with R3.1 and R1.2 | 3.1–3.7, 4.4 | 3 |
| Task 4: Runtime envelope | 5.1–5.2 | 4 |
| Task 5: Runtime tests and the on-demand lane | 6.1–6.2, 7.2 | 5 |
| Task 6: Deployment | 7.1, 8.4–8.6 | none (operations) |
| Task 7: Integration verification and change close-out | 9.1, `verify.md` | 6 (`verify.md`) |

---

### Task 1: Packages

**Files:**
- Create: `pkgs/by-name/greptimedb-bin/package.nix`
- Create: `pkgs/by-name/greptimedb-bin/update.sh` (executable)
- Create: `pkgs/by-name/ntfy-send/package.nix`
- Move: `modules/home/tools/commands/system/ntfy-send.sh` → `pkgs/by-name/ntfy-send/ntfy-send.sh` (content unchanged)
- Modify: `modules/apps/updates.nix:43-46` (add `apps.update-greptimedb-bin` after `apps.update-golem-binary`)
- Move: `modules/home/tools/commands/system/ntfy-send.nix` → `modules/home/tools/ntfy-send.nix` (rewritten: install `pkgs.ntfy-send`, no inline `writeShellApplication`), following the convention stated in `modules/home/tools/repo-sync.nix:1-3` that modules installing a by-name package live in `modules/home/tools/`, not under `tools/commands/`
- Modify: `modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md:196` (the script's new location)
- Modify: `openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md:3-5` (tick 1.1–1.3)
- Modify: `openspec/changes/stand-up-greptimedb-on-magnetite/proposal.md:1-15` (Linear sync ledger)
- Test: `checks.x86_64-linux.package-greptimedb-bin`, `checks.{x86_64-linux,aarch64-darwin}.package-ntfy-send` (generated per package by `modules/checks/packages.nix:37-40`), `checks.x86_64-linux.updater-repository-paths` (`modules/checks/hooks.nix:178-222`), `checks.{x86_64-linux,aarch64-darwin}.apps-build` (`modules/checks/apps.nix:20-49`), `checks.x86_64-linux.home-manager-crs58`, `checks.aarch64-darwin.darwin-stibnite`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `packages.x86_64-linux.greptimedb-bin` (and `pkgs.greptimedb-bin` on every x86_64-linux machine through `flake.overlays.default`, `modules/nixpkgs/compose.nix:33-42`): `version = "1.2.1"`, `meta.mainProgram = "greptime"`, `passthru.embedsDashboard = true`, `passthru.dashboardVersion = "0.13.13"`. The attribute is absent on `aarch64-linux` and `aarch64-darwin` (the file yields `null` there, as `pkgs/by-name/radicle-desktop/package.nix:7-8` does), so Task 2's module and checks read it only on x86_64-linux, through `self'.packages.greptimedb-bin` in checks (design D1).
  - `packages.<system>.ntfy-send` and `pkgs.ntfy-send` on every system: `ntfy-send MESSAGE [TOPIC] [CURL_ARGS…]`, `meta.mainProgram = "ntfy-send"`, posting `curl -sfk -m 5 [CURL_ARGS…] -d MESSAGE https://ntfy.zt/<TOPIC>`. On Linux it runs `curl` from `PATH` and, when `TOPIC` is omitted, `hostname -s`; a system unit running it (Task 3) must put `pkgs.curl` on the unit's `path` and pass the topic explicitly.
  - `apps.<system>.update-greptimedb-bin` on every system, including `aarch64-darwin`, pointing at the update script itself rather than at the package.

The new files must be visible to flake evaluation: in this jj-colocated checkout a new file enters the git index once jj snapshots the working copy, so every step that creates a file is followed by `jj st --no-pager >/dev/null` before the first `nix build` or `nix eval` that needs it; no `git add`.

- [ ] **Step 1: Confirm the working directory and the evidence directory**

Run:

```bash
cd /Users/crs58/projects/vanixiets && pwd && mkdir -p logs/s1-evidence
```

Expected: `/Users/crs58/projects/vanixiets`.
`logs/` is git-ignored, so the evidence directory never enters a change.

- [ ] **Step 2: Run the package check before the package exists (RED)**

Run:

```bash
nix build .#checks.x86_64-linux.package-greptimedb-bin 2>&1 | tee logs/s1-evidence/1.1-package-greptimedb-bin-red.log
```

Expected: fails with `error: flake 'git+file:///Users/crs58/projects/vanixiets' does not provide attribute 'checks.x86_64-linux.package-greptimedb-bin'` (the wording may also list the `packages.`/`legacyPackages.` candidates it tried).

- [ ] **Step 3: Write `pkgs/by-name/greptimedb-bin/package.nix`**

The tarball `greptime-linux-amd64-v1.2.1.tar.gz` unpacks to one directory `greptime-linux-amd64-v1.2.1/` holding only the executable `greptime` (upstream `.github/actions/upload-artifacts/action.yml:33-41` at `v1.2.1`).
That executable needs only `libgcc_s.so.1`, `libm.so.6`, `libc.so.6` and the glibc loader (`readelf -d`, checked while planning), so `stdenv.cc.cc.lib` is the one build input.
The SRI form of the sha256 `062d5beb13de4991c4fec201b2e5071518bf4ca8f0d52947eba757a74c2a5420` is `sha256-Bi1b6xPeSZHE/sIBsuUHFRi/TKjw1SlH66dXp0wqVCA=` (`nix hash convert --hash-algo sha256 --to sri 062d5beb…`).
`greptime --version` prints clap's long version, `GreptimeDB` followed by the lines `branch:`, `commit:`, `clean:` and `version: 1.2.1` (`src/common/version/src/lib.rs:116-124` and `src/cmd/src/bin/greptime.rs:28` at `v1.2.1`, product version from the workspace `Cargo.toml:78`), so `versionCheckHook` finds `1.2.1` on its first argument, `--version`.

Create `pkgs/by-name/greptimedb-bin/package.nix` with exactly this content:

```nix
# greptimedb-bin - upstream GreptimeDB release binary with the embedded dashboard
#
# The upstream release tarball is built with the `servers/dashboard` feature and
# embeds GreptimeDB's Perses-based web dashboard, which the nixpkgs source build
# omits. `passthru.embedsDashboard` records that property where the store
# module's evaluation-time assertion (R1.1) reads it; `passthru.dashboardVersion`
# is src/servers/dashboard/VERSION at the release tag, without its leading `v`,
# and update.sh refreshes it with the version. The `-bin` pname keeps this
# package from shadowing `pkgs.greptimedb` through the overlay merge
# (modules/nixpkgs/compose.nix).
#
# Only x86_64-linux is packaged. On other systems this file yields null, so the
# package and its package-* check are absent there rather than throwing at
# evaluation (as pkgs/by-name/radicle-desktop does for its single platform).
#
# Source: https://github.com/GreptimeTeam/greptimedb
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  versionCheckHook,
}:
if stdenv.hostPlatform.system != "x86_64-linux" then
  null
else
  stdenv.mkDerivation (finalAttrs: {
    pname = "greptimedb-bin";
    version = "1.2.1";

    src = finalAttrs.passthru.sources.${stdenv.hostPlatform.system};

    # The tarball unpacks to a single greptime-linux-amd64-v<version>/ directory
    # holding only the `greptime` executable; stdenv selects it as sourceRoot.
    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs = [ autoPatchelfHook ];

    buildInputs = [
      stdenv.cc.cc.lib # libgcc_s.so.1
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 greptime $out/bin/greptime
      runHook postInstall
    '';

    # `greptime --version` prints clap's long version, which ends in the line
    # `version: <version>`.
    nativeInstallCheckInputs = [ versionCheckHook ];
    versionCheckProgram = "${placeholder "out"}/bin/greptime";
    doInstallCheck = true;

    passthru = {
      sources = {
        "x86_64-linux" = fetchurl {
          url = "https://github.com/GreptimeTeam/greptimedb/releases/download/v${finalAttrs.version}/greptime-linux-amd64-v${finalAttrs.version}.tar.gz";
          hash = "sha256-Bi1b6xPeSZHE/sIBsuUHFRi/TKjw1SlH66dXp0wqVCA=";
        };
      };
      embedsDashboard = true;
      dashboardVersion = "0.13.13";
      updateScript = ./update.sh;
    };

    meta = {
      description = "Cloud-native time-series database (upstream release binary with the embedded dashboard)";
      homepage = "https://greptime.com/";
      changelog = "https://github.com/GreptimeTeam/greptimedb/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.asl20;
      mainProgram = "greptime";
      platforms = builtins.attrNames finalAttrs.passthru.sources;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  })
```

`passthru.updateScript = ./update.sh` names the file Step 8 creates.
A path literal is checked only when it is coerced to a string, and `passthru` does not enter the derivation, so Steps 5 and 6 build and evaluate the package before `update.sh` exists.

- [ ] **Step 4: Snapshot the new file**

Run:

```bash
jj st --no-pager >/dev/null && git ls-files pkgs/by-name/greptimedb-bin
```

Expected: `pkgs/by-name/greptimedb-bin/package.nix`.

- [ ] **Step 5: Build the package check (GREEN)**

Run:

```bash
nix build -L .#checks.x86_64-linux.package-greptimedb-bin 2>&1 | tee logs/s1-evidence/1.1-package-greptimedb-bin.log | rg 'versionCheckPhase|managed to find version|autoPatchelf|error'
```

Expected: succeeds; the filtered output contains `Successfully managed to find version 1.2.1 in the output of the command /nix/store/…-greptimedb-bin-1.2.1/bin/greptime --version` and `Finished versionCheckPhase`, and no `error`.
The build runs on an x86_64-linux remote builder; this is the `versionCheckHook` run against the patched binary that 1.1 names.

- [ ] **Step 6: Verify the package's evaluated attributes**

Run:

```bash
{
  nix eval .#packages.x86_64-linux.greptimedb-bin.version
  nix eval .#packages.x86_64-linux.greptimedb-bin.passthru.embedsDashboard
  nix eval .#packages.x86_64-linux.greptimedb-bin.passthru.dashboardVersion
  nix eval .#packages.x86_64-linux.greptimedb-bin.meta.mainProgram
  nix eval .#packages.aarch64-darwin --apply 'p: p ? greptimedb-bin'
  nix eval .#checks.aarch64-darwin --apply 'c: c ? package-greptimedb-bin'
} 2>&1 | tee logs/s1-evidence/1.1-greptimedb-bin-attributes.log
```

Expected, one per line: `"1.2.1"`, `true`, `"0.13.13"`, `"greptime"`, `false`, `false`.

- [ ] **Step 7: Evaluate the update app before it exists (RED)**

Run:

```bash
nix eval .#apps.aarch64-darwin.update-greptimedb-bin.program 2>&1 | tee logs/s1-evidence/1.2-update-app-red.log
```

Expected: fails with `error: flake 'git+file:///Users/crs58/projects/vanixiets' does not provide attribute 'apps.aarch64-darwin.update-greptimedb-bin.program'`.

- [ ] **Step 8: Write `pkgs/by-name/greptimedb-bin/update.sh`**

This follows `pkgs/by-name/worktrunk-bin/update.sh:1-61` with three differences.
GreptimeDB publishes nightlies, alphas and betas as GitHub prereleases beside its stable tags (the release list on 2026-10-16 has `v1.3.0-beta.2`, `v1.4.0-nightly-20261012` and an `alpha` before `v1.2.1`), and can cut a patch on an older line after a newer minor, so the script keeps only non-draft, non-prerelease bare semver tags and takes the numerically highest rather than the newest.
There is one platform, so there is no platform map.
It also refreshes `dashboardVersion` from `src/servers/dashboard/VERSION` at the release tag, whose content at `v1.2.1` is `v0.13.13` followed by a newline.

Create `pkgs/by-name/greptimedb-bin/update.sh` with exactly this content:

```bash
#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix
# shellcheck shell=bash

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_NIX="${REPO_ROOT}/pkgs/by-name/greptimedb-bin/package.nix"

current_version="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"
current_dashboard="$(sed -n 's/.*dashboardVersion = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"

# GreptimeDB publishes nightlies, alphas and betas as GitHub prereleases beside
# its stable tags, and can cut a patch on an older line after a newer minor.
# Keep only published, non-prerelease bare semver tags (vMAJOR.MINOR.PATCH) and
# take the numerically highest, not the most recently created.
latest_tag="$(curl -fsSL \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/GreptimeTeam/greptimedb/releases?per_page=100" \
  | jq -r '[.[] | select(.draft == false and .prerelease == false) | .tag_name | select(test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] | sort_by(ltrimstr("v") | split(".") | map(tonumber)) | last')"
latest_version="${latest_tag#v}"

if [[ -z "$latest_version" || "$latest_version" == "null" ]]; then
  echo "error: failed to discover a stable semver tag from GitHub releases" >&2
  exit 1
fi

if [[ "$current_version" == "$latest_version" ]]; then
  echo "greptimedb-bin is already at version ${current_version}; refreshing hash and dashboard version anyway"
else
  echo "Updating greptimedb-bin: ${current_version} -> ${latest_version}"
  sed -i'' -e "s/version = \"${current_version}\"/version = \"${latest_version}\"/" "$PKG_NIX"
fi

asset="greptime-linux-amd64-v${latest_version}.tar.gz"
url="https://github.com/GreptimeTeam/greptimedb/releases/download/v${latest_version}/${asset}"

echo "Prefetching x86_64-linux (${asset})..."
sri_hash="$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash)"

if [[ -z "$sri_hash" || "$sri_hash" == "null" ]]; then
  echo "error: failed to compute hash for x86_64-linux from ${url}" >&2
  exit 1
fi

# The url line names the asset as greptime-linux-amd64-v${finalAttrs.version};
# advance to the immediately-following `hash =` line and substitute.
sed -i'' -e "/greptime-linux-amd64-v/{ n; s|hash = \"sha256-[^\"]*\"|hash = \"${sri_hash}\"|; }" "$PKG_NIX"

echo "  x86_64-linux: ${sri_hash}"

# The release embeds the dashboard named by src/servers/dashboard/VERSION at its
# tag (for example "v0.13.13"); record it without the leading v.
dashboard_version="$(curl -fsSL \
  "https://raw.githubusercontent.com/GreptimeTeam/greptimedb/v${latest_version}/src/servers/dashboard/VERSION" \
  | tr -d '[:space:]')"
dashboard_version="${dashboard_version#v}"

if ! [[ "$dashboard_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: unexpected dashboard VERSION '${dashboard_version}' at v${latest_version}" >&2
  exit 1
fi

sed -i'' -e "s/dashboardVersion = \"[^\"]*\"/dashboardVersion = \"${dashboard_version}\"/" "$PKG_NIX"

if [[ "$current_dashboard" != "$dashboard_version" ]]; then
  echo "  dashboardVersion: ${current_dashboard} -> ${dashboard_version} (re-check the percli lint schema pin)"
else
  echo "  dashboardVersion: ${dashboard_version}"
fi

echo "Updated greptimedb-bin to ${latest_version}"
```

`sed -n 's/.*version = …'` cannot match the `dashboardVersion` line, because `sed` is case-sensitive and that line spells `Version`.

Then make it executable and snapshot it:

```bash
chmod 755 pkgs/by-name/greptimedb-bin/update.sh && jj st --no-pager >/dev/null && git ls-files pkgs/by-name/greptimedb-bin
```

Expected: `pkgs/by-name/greptimedb-bin/package.nix` and `pkgs/by-name/greptimedb-bin/update.sh`.

- [ ] **Step 9: Add `apps.update-greptimedb-bin`**

The package exists only on x86_64-linux, but updates are run from stibnite, so the app points at the script's own path, which the flake copies into the store with its executable bit, and needs no built package.
In `modules/apps/updates.nix`, insert after the `apps.update-golem-binary` block (after line 46):

```nix

      # greptimedb-bin exists only on x86_64-linux (its package.nix yields null
      # elsewhere); the updater is host-agnostic, so the app runs the script
      # itself and is available on every system, stibnite included.
      apps.update-greptimedb-bin = {
        type = "app";
        program = "${../../pkgs/by-name/greptimedb-bin/update.sh}";
      };
```

- [ ] **Step 10: Evaluate the app and run the updater checks (GREEN)**

Run:

```bash
{
  nix eval .#apps.aarch64-darwin.update-greptimedb-bin.program
  nix eval .#apps.x86_64-linux.update-greptimedb-bin.program
  nix build .#checks.x86_64-linux.updater-repository-paths
  nix build .#checks.x86_64-linux.apps-build
  nix build .#checks.aarch64-darwin.apps-build
} 2>&1 | tee logs/s1-evidence/1.2-update-app.log
```

Expected: both evaluations print the same `"/nix/store/…-update.sh"`; all three builds succeed.
`updater-repository-paths` iterates every `pkgs/by-name/*/update.sh` (`modules/checks/hooks.nix:189`), so it covers this script regardless of how the app refers to it: the script uses no `BASH_SOURCE` or `$0`, resolves the root with `git rev-parse --show-toplevel` and declares `git` in its `nix-shell` line, and the package has no `outputHash`.
`apps-build` on both systems shows the program is executable in the store.

- [ ] **Step 11: Show the updater restores a stale package**

Save the package, make it stale in version, hash and dashboard version, run the app, and compare:

```bash
cp pkgs/by-name/greptimedb-bin/package.nix /tmp/greptimedb-bin-package.nix
sed -i '' -e 's/version = "1.2.1"/version = "1.2.0"/' \
  -e 's|hash = "sha256-Bi1b6xPeSZHE/sIBsuUHFRi/TKjw1SlH66dXp0wqVCA="|hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="|' \
  -e 's/dashboardVersion = "0.13.13"/dashboardVersion = "0.0.0"/' \
  pkgs/by-name/greptimedb-bin/package.nix
nix run .#update-greptimedb-bin 2>&1 | tee logs/s1-evidence/1.2-updater-run.log
diff /tmp/greptimedb-bin-package.nix pkgs/by-name/greptimedb-bin/package.nix && echo IDENTICAL
```

Expected: the updater prints `Updating greptimedb-bin: 1.2.0 -> 1.2.1`, `  x86_64-linux: sha256-Bi1b6xPeSZHE/sIBsuUHFRi/TKjw1SlH66dXp0wqVCA=`, `  dashboardVersion: 0.0.0 -> 0.13.13 (re-check the percli lint schema pin)` and `Updated greptimedb-bin to 1.2.1`; `diff` prints nothing and the last line is `IDENTICAL`.
This holds while `v1.2.1` is upstream's highest stable release, as it is on 2026-10-16; if upstream has published a newer stable release by the time this runs, the updater moves the package to it, which violates the Global Constraint pinning 1.2.1, so restore the saved file with `cp /tmp/greptimedb-bin-package.nix pkgs/by-name/greptimedb-bin/package.nix` and report the new release instead of committing it.

- [ ] **Step 12: Run the ntfy-send package check before the package exists (RED)**

Run:

```bash
nix build .#checks.aarch64-darwin.package-ntfy-send 2>&1 | tee logs/s1-evidence/1.3-package-ntfy-send-red.log
```

Expected: fails with `error: flake 'git+file:///Users/crs58/projects/vanixiets' does not provide attribute 'checks.aarch64-darwin.package-ntfy-send'`.
The root nixpkgs pin has no `ntfy-send` attribute (only `ntfy`, `ntfy-alertmanager` and `ntfy-sh` under `pkgs/by-name/nt/`), so the new package shadows nothing.

- [ ] **Step 13: Copy the script into the package directory**

Run:

```bash
mkdir -p pkgs/by-name/ntfy-send && cp modules/home/tools/commands/system/ntfy-send.sh pkgs/by-name/ntfy-send/ntfy-send.sh
```

The script's content does not change.
It is copied, not moved, because the old home module still reads `./ntfy-send.sh` until Step 17 deletes both, and Step 16 evaluates that module.

- [ ] **Step 14: Write `pkgs/by-name/ntfy-send/package.nix`**

This follows `pkgs/by-name/ghq-sync/package.nix:1-23` and carries over the preamble and description that `modules/home/tools/commands/system/ntfy-send.nix:12-19` injects today.
Create `pkgs/by-name/ntfy-send/package.nix` with exactly this content:

```nix
# ntfy-send: post a push notification to the fleet's ntfy server (ntfy.zt).
# One source for every delivery: the home-manager tools command installs it,
# and system units run it from ExecStart.
#
# Endpoint security software on Darwin blocks ad-hoc signed (Nix store)
# binaries from TCP connections over ZeroTier. The preamble injects
# NTFY_CURL_BIN, the eval-time-resolved curl path, so Darwin uses /usr/bin/curl
# while Linux uses PATH curl.
{
  lib,
  stdenv,
  writeShellApplication,
}:
writeShellApplication {
  name = "ntfy-send";
  text = ''
    export NTFY_CURL_BIN=${if stdenv.hostPlatform.isDarwin then "/usr/bin/curl" else "curl"}
    ${builtins.readFile ./ntfy-send.sh}
  '';
  meta = {
    description = "Send push notification via ntfy.zt (Apple-signed curl on Darwin)";
    license = lib.licenses.mit;
    mainProgram = "ntfy-send";
  };
}
```

Then snapshot:

```bash
jj st --no-pager >/dev/null && git ls-files pkgs/by-name/ntfy-send
```

Expected: `pkgs/by-name/ntfy-send/ntfy-send.sh` and `pkgs/by-name/ntfy-send/package.nix`.

- [ ] **Step 15: Build the ntfy-send package checks (GREEN) and inspect the delivered scripts**

Run:

```bash
{
  nix build --out-link result-ntfy-send-darwin .#checks.aarch64-darwin.package-ntfy-send
  nix build --out-link result-ntfy-send-linux .#checks.x86_64-linux.package-ntfy-send
  rg -n 'NTFY_CURL_BIN=' result-ntfy-send-darwin/bin/ntfy-send result-ntfy-send-linux/bin/ntfy-send
  nix eval .#packages.x86_64-linux.ntfy-send.meta.mainProgram
} 2>&1 | tee logs/s1-evidence/1.3-package-ntfy-send.log
```

Expected: both builds succeed (each runs `shellcheck` on the script); `rg` prints `export NTFY_CURL_BIN=/usr/bin/curl` for the darwin script and `export NTFY_CURL_BIN=curl` for the linux one; the evaluation prints `"ntfy-send"`.
Remove the links afterwards with `rm result-ntfy-send-darwin result-ntfy-send-linux`.

- [ ] **Step 16: Show the home configurations do not yet install the package (RED)**

Before switching the home-manager module, compare the `ntfy-send` the homes install with the package:

```bash
{
  nix eval --json '.#homeConfigurations."crs58@x86_64-linux".config.home.packages' --apply 'ps: map (p: p.outPath) (builtins.filter (p: (p.name or "") == "ntfy-send") ps)'
  nix eval --json .#packages.x86_64-linux.ntfy-send.outPath
  nix eval --json '.#darwinConfigurations.stibnite.config.home-manager.users.crs58.home.packages' --apply 'ps: map (p: p.outPath) (builtins.filter (p: (p.name or "") == "ntfy-send") ps)'
  nix eval --json .#packages.aarch64-darwin.ntfy-send.outPath
} 2>&1 | tee logs/s1-evidence/1.3-home-ntfy-send-red.log
```

Expected: each home prints a one-element list whose store path differs from the package's `outPath` printed after it, because the home still builds its own inline `writeShellApplication`.

- [ ] **Step 17: Replace the home-manager command with one that installs the package**

Create `modules/home/tools/ntfy-send.nix` with exactly this content, following `modules/home/tools/repo-sync.nix:1-11`:

```nix
# ntfy-send: post a push notification via ntfy.zt.
# Installs the by-name writeShellApplication (pkgs/by-name/ntfy-send/), which
# system units also run, so it lives beside the other package-install modules
# here, not under tools/commands/ (inline in-tree commands).
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.ntfy-send ];
    };
}
```

Then delete the old module and the old script, and snapshot:

```bash
rm modules/home/tools/commands/system/ntfy-send.nix modules/home/tools/commands/system/ntfy-send.sh
jj st --no-pager >/dev/null && git ls-files modules/home/tools/ntfy-send.nix modules/home/tools/commands/system/ntfy-send.nix modules/home/tools/commands/system/ntfy-send.sh
```

Expected: only `modules/home/tools/ntfy-send.nix`.
import-tree registers the new file into `flake.modules.homeManager.tools` exactly as it registered the old one, so the homes still receive one `ntfy-send`.

- [ ] **Step 18: Show the homes install the package (GREEN)**

Run the four evaluations of Step 16 again:

```bash
{
  nix eval --json '.#homeConfigurations."crs58@x86_64-linux".config.home.packages' --apply 'ps: map (p: p.outPath) (builtins.filter (p: (p.name or "") == "ntfy-send") ps)'
  nix eval --json .#packages.x86_64-linux.ntfy-send.outPath
  nix eval --json '.#darwinConfigurations.stibnite.config.home-manager.users.crs58.home.packages' --apply 'ps: map (p: p.outPath) (builtins.filter (p: (p.name or "") == "ntfy-send") ps)'
  nix eval --json .#packages.aarch64-darwin.ntfy-send.outPath
} 2>&1 | tee logs/s1-evidence/1.3-home-ntfy-send.log
```

Expected: each home's one-element list holds exactly the package's `outPath` printed after it.
The paths agree because the overlay's custom packages are the perSystem `packages` themselves (`modules/nixpkgs/compose.nix:33-36`).

- [ ] **Step 19: Build the home and stibnite and inspect the delivered command**

Run:

```bash
nix build --out-link result-hm-crs58 .#checks.x86_64-linux.home-manager-crs58 2>&1 | tee logs/s1-evidence/1.3-home-manager-crs58.log
nix build --out-link result-stibnite .#checks.aarch64-darwin.darwin-stibnite 2>&1 | tee logs/s1-evidence/1.3-darwin-stibnite.log
{
  readlink -f result-hm-crs58/home-path/bin/ntfy-send
  nix path-info -r ./result-hm-crs58 | rg -- '-ntfy-send$'
  nix eval --raw .#packages.x86_64-linux.ntfy-send.outPath; echo
  nix path-info -r ./result-stibnite | rg -- '-ntfy-send$'
  nix eval --raw .#packages.aarch64-darwin.ntfy-send.outPath; echo
} 2>&1 | tee logs/s1-evidence/1.3-delivered-ntfy-send.log
rm result-hm-crs58 result-stibnite
```

Expected: both builds succeed; `readlink -f` prints `<x86_64-linux outPath>/bin/ntfy-send`; each `nix path-info -r … | rg` prints exactly one path, equal to that system's package `outPath` printed after it.
Exactly one `-ntfy-send` path in each closure shows no second, inline copy is delivered.

- [ ] **Step 20: Repoint the live documentation at the script's new location**

In `modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md`, replace line 196's opening clause

```markdown
The wrapper script lives at `modules/home/tools/commands/system/ntfy-send.sh` and uses
```

with

```markdown
The wrapper script lives at `pkgs/by-name/ntfy-send/ntfy-send.sh` (package `ntfy-send`) and uses
```

leaving the rest of the line unchanged.
Then confirm no live reference to the old location remains:

```bash
rg -n 'commands/system/ntfy-send\.sh' modules pkgs justfile docs --glob '!docs/notes/development/observability/**'
```

Expected: no output.
The decision records under `docs/notes/development/observability/` cite the old path as historical evidence, several at a pinned revision, and are left to their own amendment process.

- [ ] **Step 21: Tick 1.1–1.3 and move CAM-68 to In Progress**

In `openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md`, change the leading `- [ ]` of the 1.1, 1.2 and 1.3 lines (lines 3–5) to `- [x]`, leaving the rest of each line unchanged.
This is the change's first `- [x]`, which by `skill://openspec-linear-sync` drives Todo → In Progress for the bound story CAM-68 (team `CAM`).
Every Linear write is best-effort and never blocks the commit.

Gate on the workspace and read the current state:

```bash
linear auth whoami --workspace cameronraysmith
linear issue view CAM-68 --json --no-comments --workspace cameronraysmith | jq -r .state.name
```

Expected: `Workspace: cameronraysmith` on the first line, then the state name, `Todo` at planning time.

Strictly-behind guard: only if the printed state is `Backlog` or `Todo`, post the transition and one comment:

```bash
linear issue update CAM-68 --state "In Progress" --workspace cameronraysmith
printf 'Implementation has begun: greptimedb-bin 1.2.1 is packaged and ntfy-send moved to pkgs/by-name (tasks 1.1-1.3). The change lands as the first of the S1 pull requests.\n' > /tmp/cam68-in-progress.md
linear issue comment add CAM-68 --body-file /tmp/cam68-in-progress.md --workspace cameronraysmith
linear issue view CAM-68 --json --no-comments --workspace cameronraysmith | jq -r .state.name
date -u +%Y-%m-%dT%H:%M:%SZ
```

Expected: the last state read prints `In Progress`; the `date` output is the timestamp `<now>` used below.

Update the ledger in `openspec/changes/stand-up-greptimedb-on-magnetite/proposal.md`'s frontmatter, writing the `date` output for `<now>`:
- If the transition posted: set `linear_story_state: In Progress`, `last_synced_state: In Progress`, `last_synced_at: <now>`, and append to `attempt_log` the line `  - { at: "<now>", transition: "Todo->In Progress", outcome: "posted", note: "first - [x] in tasks.md (1.1-1.3)" }`.
- If `linear` was unavailable or a write failed: leave `linear_story_state` and `last_synced_state` at `Todo`, and append `  - { at: "<now>", transition: "Todo->In Progress", outcome: "dropped", note: "<the error, one line>" }`.
- If the guard found Linear already at or past `In Progress`: post nothing, set `linear_story_state` and `last_synced_state` to the state read and `last_synced_at: <now>`, and append no entry.

- [ ] **Step 22: Commit**

Create the task's change off `main@origin` and move this task's paths into it:

```bash
jj new --no-edit -r main@origin -m 'feat(pkgs): add greptimedb-bin 1.2.1 and move ntfy-send to pkgs/by-name'
```

Expected: `Created new commit <change-id> …`; use that change id below.

```bash
jj squash --from @ --into <change-id> --keep-emptied --use-destination-message -- \
  pkgs/by-name/greptimedb-bin \
  pkgs/by-name/ntfy-send \
  modules/apps/updates.nix \
  modules/home/tools/ntfy-send.nix \
  modules/home/tools/commands/system/ntfy-send.nix \
  modules/home/tools/commands/system/ntfy-send.sh \
  modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md \
  openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md \
  openspec/changes/stand-up-greptimedb-on-magnetite/proposal.md
jj diff --no-pager -r <change-id> --summary
```

Expected: the summary lists exactly `A pkgs/by-name/greptimedb-bin/package.nix`, `A pkgs/by-name/greptimedb-bin/update.sh`, `A pkgs/by-name/ntfy-send/package.nix`, the script's move (`R {modules/home/tools/commands/system => pkgs/by-name/ntfy-send}/ntfy-send.sh`, or `D` of the old path and `A` of the new), the home module's move (`A modules/home/tools/ntfy-send.nix` and `D modules/home/tools/commands/system/ntfy-send.nix`, or an `R`), and `M` for `modules/apps/updates.nix`, the `SKILL.md`, `tasks.md` and `proposal.md`.
The orchestrator rebases the development join onto this change, pushes it and opens the pull request; it lands through the merge queue before Task 2's pull request is enqueued.

---

---

### Task 2: Store, with its evaluation-time regulators

**Files:**
- Create: `modules/checks/greptimedb-envelope.nix`
- Create: `modules/nixos/greptimedb.nix`
- Modify: `modules/machines/nixos/magnetite/default.nix:59` (import `greptimedb`), `:263` (three ZFS oneshots after `zfs-set-root-home-reservation`), `:442` (generators, store settings and credential wiring after `services.omnigraph`)
- Modify: `modules/machines/nixos/magnetite/disko.nix:80` (dataset `root/greptimedb` after `root/cognee`)
- Create (by `clan vars generate`, Step 21): `vars/per-machine/magnetite/greptimedb-users/`, `vars/per-machine/magnetite/greptimedb-r2/`
- Modify: `openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md` (tick 2.1–2.6, 4.1–4.3, 8.1–8.3)
- Evidence (git-ignored): `logs/s1-evidence/8.3-zfs-create.log`

**Interfaces:**
- Consumes (Task 1): `pkgs.greptimedb-bin` in magnetite's package set (the NixOS `pkgs` carries the flake overlay, as `pkgs.golem-binary` does today), `version = "1.2.1"`, `meta.mainProgram = "greptime"`, `passthru.embedsDashboard = true`.
  Task 2's change is based on `main@origin`; the orchestrator rebases it onto `main` after Task 1 lands, and until then evaluation happens in the development join, which contains Task 1.
- Produces:
  - `flake.modules.nixos.greptimedb` with options `services.greptimedb.enable` (bool), `package` (default `pkgs.greptimedb-bin`), `settings` (`(pkgs.formats.toml { }).type`, rendered as `greptimedb.toml`), `databases` (`attrsOf str`, database name to TTL, default `{ }`).
    The module references no clan vars: the host sets `LoadCredential`, `EnvironmentFile`, the `[storage]` object-store stanza and `databases`, so tests import the module with their own credentials and get GreptimeDB's default `File` storage.
  - `greptimedb.service`: static `User`/`Group` `greptimedb`, `StateDirectory = "greptimedb"`, `RuntimeDirectory = "greptimedb"` (`0755`), `ExecStartPre` writing `/run/greptimedb/loaded-users.sha256` (mode `0444`, content `<sha256 hex of $CREDENTIALS_DIRECTORY/users>\n`), `user_provider = "static_user_provider:file:/run/credentials/greptimedb.service/users"`.
  - `greptimedb-schema.service`: `Type = "oneshot"`, `RemainAfterExit = true`, `requires`/`after`/`partOf` `greptimedb.service`, reads `$CREDENTIALS_DIRECTORY/admin-password`.
  - On magnetite: `systemd.services.greptimedb.serviceConfig.LoadCredential = [ "users:<greptimedb-users users path>" ]`, `systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [ "admin-password:<greptimedb-users admin-password path>" ]`, both set in `modules/machines/nixos/magnetite/default.nix`; Task 3 and Task 4 add their own `LoadCredential` entries the same way, by the generator file's `.path`.
  - Generator `greptimedb-users`: secret files `users` (owner `greptimedb`), `admin-password`, `collector-password`, `perses-password`, `regulator-password` (each `0400`, each password 64 hex characters without a trailing newline), and the public file `users-sha256` (`secret = false`, content `<sha256 hex of users>\n`, the same format as `/run/greptimedb/loaded-users.sha256`), read through `config.clan.core.vars.generators.greptimedb-users.files.<name>.path`.
    Only `users` has `restartUnits` in Task 2; `collector-password` has none until Task 3 adds `restartUnits = [ "opentelemetry-collector.service" ];` to `files.collector-password` in `modules/machines/nixos/magnetite/default.nix`, together with the unit it names.
  - Generator `greptimedb-r2`: prompts `access-key`, `secret-key`; file `env`.
  - Units `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation`, `zfs-assert-root-greptimedb-noautosnap`, built from the binding `greptimedbDataset = { name = "zroot/root/greptimedb"; mountpoint = "/var/lib/greptimedb"; quota = "16G"; reservation = "12G"; };` in the host module's `let` in `modules/machines/nixos/magnetite/default.nix` (beside `omnigraphCookbooks`); Task 4 reads the same binding for the envelope's environment, and `disko.nix` keeps its literal install-time declaration, which the envelope check's `diskoMatchesDataset` clause compares with the oneshots.
    Task 3 lists the three units, `greptimedb` and `greptimedb-schema` in `services.observability-notify.units`.
  - `checks.x86_64-linux.greptimedb-envelope`, whose R8.2 credential-holder clause is the data binding `credentialHolders` in the check's `perSystem` `let`.
    Task 2 asserts `collector-password = [ ];` and `regulator-password = [ ];`; Task 3 replaces the first line with `collector-password = [ "opentelemetry-collector" ];` and Task 4 the second with `regulator-password = [ "greptimedb-envelope" ];`.
    Holders are matched on the `LoadCredential` source path, so the id each unit chooses does not matter.
    Task 4 extends the same derivation: further sandbox checks go into the `runCommand` script before `touch "$out"`.

- [ ] **Step 1: Write the failing envelope check**

Create `modules/checks/greptimedb-envelope.nix` with exactly this content:

```nix
# Evaluation-time regulator for the telemetry store on magnetite (design D11):
# R7.1, R1.1 (amended), R1.4, R6.4's storage clause, R8.2 and the users-file
# check.
#
# Every clause reads magnetite's evaluated configuration, so it judges what
# deploys rather than a transcription of it. Mutants are pure functions over
# the extracted `view`, never re-evaluations of the host, so each costs a few
# attribute updates instead of a NixOS fixpoint. The check asserts that the
# real view fails no clause and that every mutant fails the clause it targets,
# following modules/checks/omnigent-environment.nix:98-118. The users-file
# clause runs the greptimedb-users generator in the build sandbox, because the
# store skips a malformed users line silently (design F2).
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      magnetite = self.nixosConfigurations.magnetite.config;
      store = magnetite.services.greptimedb;
      usersGenerator = magnetite.clan.core.vars.generators.greptimedb-users;

      # R8.2: magnetite's worker accounts are its omnigent workers
      # (ADR-008: "magnetite's two worker accounts").
      workerUsers = map (worker: worker.user) (
        lib.attrValues (
          lib.filterAttrs (_: worker: worker.enable) magnetite.services.omnigent-host.workers
        )
      );

      # R8.2 credential-holder clause, as data: for each greptimedb-users
      # secret, the units (systemd.services attribute names) allowed to load
      # it. Task 3 sets collector-password and Task 4 sets regulator-password;
      # until then each must have no holder.
      credentialHolders = {
        users = [ "greptimedb" ];
        admin-password = [ "greptimedb-schema" ];
        collector-password = [ ];
        perses-password = [ ];
        regulator-password = [ ];
      };

      # LoadCredential entries are "<id>:<source path>". Holders are matched on
      # the source path, because each unit chooses its own id, and an unrelated
      # unit (kanidm-site-branding) already loads an "admin-password" id.
      credentialSource = entry: lib.concatStringsSep ":" (lib.drop 1 (lib.splitString ":" entry));
      holdersOf =
        loadCredentials: path:
        lib.naturalSort (
          lib.attrNames (
            lib.filterAttrs (_: entries: lib.any (entry: credentialSource entry == path) entries) loadCredentials
          )
        );

      # ADR-007 Decision: every memory knob, set to a fixed size so the store
      # does not size itself from magnetite's RAM.
      memoryKnobs = {
        top = {
          max_in_flight_write_bytes = "128MB";
          write_bytes_exhausted_policy = "wait";
          max_concurrent_queries = 8;
        };
        query = {
          memory_pool_size = "512MB";
        };
        mito = {
          global_write_buffer_size = "256MB";
          scan_memory_limit = "512MB";
          scan_memory_on_exhausted = "fail";
          experimental_compaction_memory_limit = "256MB";
          max_background_compactions = 2;
          max_background_flushes = 2;
          page_cache_size = "256MB";
          sst_meta_cache_size = "64MB";
          vector_cache_size = "32MB";
          selector_result_cache_size = "32MB";
          range_result_cache_size = "32MB";
          prefilter_result_cache_size = "32MB";
        };
      };

      mitoOf =
        settings:
        (lib.findFirst (engine: engine ? mito) { mito = { }; } (settings.region_engine or [ ])).mito;
      knobsOf = settings: {
        top = lib.intersectAttrs memoryKnobs.top settings;
        query = lib.intersectAttrs memoryKnobs.query (settings.query or { });
        mito = lib.intersectAttrs memoryKnobs.mito (mitoOf settings);
      };
      isLoopback = addr: lib.hasPrefix "127." addr;

      # disko declares the dataset for installation only; the boot oneshots
      # enforce greptimedbDataset on the live host. The clause keeps the two
      # from drifting apart.
      oneshotCommand = unit: magnetite.systemd.services.${unit}.serviceConfig.ExecStart;

      view = {
        inherit (store) package settings;
        unit = magnetite.systemd.services.greptimedb.serviceConfig;
        usersFiles = lib.filterAttrs (_: file: file.secret) usersGenerator.files;
        loadCredentials = lib.mapAttrs (
          _: service: lib.toList (service.serviceConfig.LoadCredential or [ ])
        ) magnetite.systemd.services;
        disko = magnetite.disko.devices.zpool.zroot.datasets."root/greptimedb";
        zfsOneshots = {
          quota = oneshotCommand "zfs-set-root-greptimedb-quota";
          reservation = oneshotCommand "zfs-set-root-greptimedb-reservation";
          noautosnap = oneshotCommand "zfs-assert-root-greptimedb-noautosnap";
        };
      };

      clauses =
        v:
        let
          s = v.settings;
          storage = s.storage or { };
        in
        {
          # R7.1 (A7:135)
          memoryMax = (v.unit.MemoryMax or null) == "4G";
          memoryHigh = (v.unit.MemoryHigh or null) == "3G";
          memorySwapMax = toString (v.unit.MemorySwapMax or "unset") == "0";
          oomScoreAdjust = (v.unit.OOMScoreAdjust or null) == 500;
          memoryKnobs = knobsOf s == memoryKnobs;
          listenersLoopback =
            isLoopback (s.http.addr or "")
            && isLoopback (s.grpc.bind_addr or "")
            && (!(s.http.enable_api_server or false) || isLoopback (s.http.api_server_addr or ""));
          protocolsDisabled = lib.all (protocol: (s.${protocol}.enable or true) == false) [
            "mysql"
            "postgres"
            "opentsdb"
            "influxdb"
            "prom_store"
            "jaeger"
          ];
          userProvider =
            (s.user_provider or null) == "static_user_provider:file:/run/credentials/greptimedb.service/users";
          # Also R1.4 (A1:103-104); GreptimeDB reports usage when the key is absent.
          telemetryDisabled = (s.enable_telemetry or true) == false;
          usersRestartUnits = builtins.elem "greptimedb.service" (v.usersFiles.users.restartUnits or [ ]);

          # R1.1, amended: a stable release that declares the embedded dashboard.
          stableRelease = builtins.match "[0-9]+\\.[0-9]+\\.[0-9]+" (v.package.version or "") != null;
          embedsDashboard = (v.package.passthru.embedsDashboard or false) == true;

          # R6.4, storage clause (A6:138)
          storageDisableEc2Metadata = (storage.disable_ec2_metadata or false) == true;
          storageRegion = (storage.region or null) == "auto";
          storagePathStyle = (storage.enable_virtual_host_style or true) == false;
          storageBucket = (storage.bucket or null) == "sciexp";
          storageRoot = (storage.root or "") == "projects/vanixiets/observability/store/";

          # R8.2 (A8:139)
          usersFilesNonWorker =
            workerUsers != [ ]
            && v.usersFiles ? users
            && lib.all (file: file.mode == "0400" && !(builtins.elem file.owner workerUsers)) (
              lib.attrValues v.usersFiles
            );
          httpLoopback = isLoopback (s.http.addr or "");

          # Disk envelope (ADR-007 E7.3): disko's install-time declaration
          # equals what the boot oneshots enforce, and mounts at data_home.
          diskoMatchesDataset =
            lib.hasSuffix "/bin/zfs set quota=${v.disko.options.quota or "unset"} zroot/root/greptimedb" v.zfsOneshots.quota
            && lib.hasSuffix "/bin/zfs set reservation=${v.disko.options.reservation or "unset"} zroot/root/greptimedb" v.zfsOneshots.reservation
            && lib.hasSuffix "/bin/zfs set com.sun:auto-snapshot=${v.disko.options."com.sun:auto-snapshot" or "unset"} zroot/root/greptimedb" v.zfsOneshots.noautosnap
            && (v.disko.options.mountpoint or null) == (s.storage.data_home or "")
            && v.disko.mountpoint == (s.storage.data_home or "");
          credentialHolders =
            lib.mapAttrs (
              name: _: holdersOf v.loadCredentials usersGenerator.files.${name}.path
            ) credentialHolders == credentialHolders;
        };

      failures = v: lib.attrNames (lib.filterAttrs (_: holds: !holds) (clauses v));

      withSettings = f: v: v // { settings = f v.settings; };
      withStorage = f: withSettings (settings: settings // { storage = f settings.storage; });
      withMito =
        f:
        withSettings (
          settings:
          settings
          // {
            region_engine = map (engine: if engine ? mito then engine // { mito = f engine.mito; } else engine) (
              settings.region_engine or [ ]
            );
          }
        );

      mutants = {
        # R7.1, the seven of A7:136
        dropMemoryMax = {
          clause = "memoryMax";
          apply = v: v // { unit = removeAttrs v.unit [ "MemoryMax" ]; };
        };
        dropPageCacheSize = {
          clause = "memoryKnobs";
          apply = withMito (mito: removeAttrs mito [ "page_cache_size" ]);
        };
        httpOnAllInterfaces = {
          clause = "listenersLoopback";
          apply = withSettings (settings: lib.recursiveUpdate settings { http.addr = "0.0.0.0:4000"; });
        };
        mysqlReenabled = {
          clause = "protocolsDisabled";
          apply = withSettings (settings: lib.recursiveUpdate settings { mysql.enable = true; });
        };
        userProviderRemoved = {
          clause = "userProvider";
          apply = withSettings (settings: removeAttrs settings [ "user_provider" ]);
        };
        # Also R1.4's mutant, "key omitted".
        telemetryOmitted = {
          clause = "telemetryDisabled";
          apply = withSettings (settings: removeAttrs settings [ "enable_telemetry" ]);
        };
        restartUnitsRemoved = {
          clause = "usersRestartUnits";
          apply =
            v: v // { usersFiles = v.usersFiles // { users = removeAttrs v.usersFiles.users [ "restartUnits" ]; }; };
        };

        # R1.1
        prereleasePackage = {
          clause = "stableRelease";
          apply = v: v // { package = v.package.overrideAttrs (_: { version = "1.3.0-beta.2"; }); };
        };
        pinnedNixpkgsPackage = {
          clause = "embedsDashboard";
          apply = v: v // { package = pkgs.greptimedb; };
        };

        # R6.4
        ec2MetadataNotDisabled = {
          clause = "storageDisableEc2Metadata";
          apply = withStorage (storage: removeAttrs storage [ "disable_ec2_metadata" ]);
        };
        emptyStorageRoot = {
          clause = "storageRoot";
          apply = withStorage (storage: storage // { root = ""; });
        };

        # R8.2 (A8:140)
        workerOwnsCollectorPassword = {
          clause = "usersFilesNonWorker";
          apply =
            v:
            v
            // {
              usersFiles = v.usersFiles // {
                collector-password = v.usersFiles.collector-password // { owner = builtins.head workerUsers; };
              };
            };
        };
        # Disk envelope
        diskoQuotaDiffers = {
          clause = "diskoMatchesDataset";
          apply = v: v // { disko = lib.recursiveUpdate v.disko { options.quota = "32G"; }; };
        };

        secondAdminPasswordHolder = {
          clause = "credentialHolders";
          apply =
            v:
            v
            // {
              loadCredentials = v.loadCredentials // {
                nixbot = v.loadCredentials.nixbot ++ [ "admin-password:${usersGenerator.files.admin-password.path}" ];
              };
            };
        };
      };

      missed = lib.attrNames (
        lib.filterAttrs (_: mutant: !(builtins.elem mutant.clause (failures (mutant.apply view)))) mutants
      );

      # Users-file clause: run the generator exactly as clan does
      # (finalScript: PATH from runtimeInputs plus coreutils, then the script)
      # and require four `<user>:<mode>=<hex>` lines, then show the oracle
      # rejects a fifth line and a password containing `=`.
      usersFileCheck = ''
        valid_users_file() {
          [ "$(wc -l < "$1")" -eq 4 ] || return 1
          [ "$(cut -d '=' -f 1 "$1" | tr '\n' ' ')" = "admin:rw collector:wo perses:ro regulator:ro " ] || return 1
          ! grep -Evq '^(admin:rw|collector:wo|perses:ro|regulator:ro)=[0-9a-f]{32,}$' "$1"
        }

        generated="$TMPDIR/greptimedb-users"
        mkdir "$generated"
        out="$generated" bash ${usersGenerator.finalScript}

        if ! valid_users_file "$generated/users"; then
          echo "greptimedb-users emitted a malformed users file:" >&2
          sed 's/=.*/=<redacted>/' "$generated/users" >&2
          exit 1
        fi
        for pair in admin:rw collector:wo perses:ro regulator:ro; do
          user="''${pair%%:*}"
          if [ "$(grep "^$pair=" "$generated/users" | cut -d '=' -f 2)" != "$(cat "$generated/$user-password")" ]; then
            echo "greptimedb-users: $user-password differs from its users line" >&2
            exit 1
          fi
        done
        if [ "$(sha256sum < "$generated/users" | cut -d ' ' -f 1)" != "$(cat "$generated/users-sha256")" ]; then
          echo "greptimedb-users: users-sha256 is not the sha256 of users" >&2
          exit 1
        fi

        cp "$generated/users" fifth-line
        printf 'extra:rw=%s\n' "$(cat "$generated/admin-password")" >> fifth-line
        sed '1s/^\(admin:rw=..\)/\1=/' "$generated/users" > password-with-equals
        for mutant in fifth-line password-with-equals; do
          if valid_users_file "$mutant"; then
            echo "users-file oracle accepted mutant $mutant" >&2
            exit 1
          fi
        done
      '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        greptimedb-envelope =
          assert lib.assertMsg (
            failures view == [ ]
          ) "greptimedb envelope clauses failed on magnetite: ${builtins.toJSON (failures view)}";
          assert lib.assertMsg (
            missed == [ ]
          ) "greptimedb-envelope oracle accepted mutants: ${builtins.toJSON missed}";
          pkgs.runCommand "greptimedb-envelope" { } ''
            ${usersFileCheck}
            touch "$out"
          '';
      };
    };
}
```

- [ ] **Step 2: Confirm jj tracks the new file**

Run: `jj st --no-pager >/dev/null && jj file list modules/checks/greptimedb-envelope.nix`
Expected: `modules/checks/greptimedb-envelope.nix`.
The `jj st` snapshot puts the new file in the colocated git index, which is what makes it visible to the flake; no `git add`.
import-tree activates every tracked `.nix` file under `modules/` (`modules/README.md`), so no registration is needed.

- [ ] **Step 3: Run the check and watch it fail**

Run: `mkdir -p logs && nix build .#checks.x86_64-linux.greptimedb-envelope -L 2>&1 | tee logs/greptimedb-envelope-red-$(date +%Y%m%d-%H%M%S).log`
Expected: FAIL at evaluation with `error: attribute 'greptimedb-users' missing`, pointing at `usersGenerator` in `modules/checks/greptimedb-envelope.nix`; the `failures` view evaluates clauses in name order, and `credentialHolders` forces the missing generator before any clause reads `services.greptimedb`.

- [ ] **Step 4: Write the store module**

Create `modules/nixos/greptimedb.nix` with exactly this content:

```nix
# GreptimeDB telemetry store (design D3 to D7).
#
# Site-neutral and free of clan vars, so the runtime tests import it with
# their own credentials. The host supplies LoadCredential (`users` for the
# store, `admin-password` for the schema job), the R2 EnvironmentFile, the
# [storage] object-store stanza and `databases`; without a stanza the store
# uses GreptimeDB's local `File` storage under data_home. The memory envelope,
# listeners, worker pools and usage reporting are fixed here, and R7.1
# (modules/checks/greptimedb-envelope.nix) asserts them on magnetite.
{ ... }:
{
  flake.modules.nixos.greptimedb =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.greptimedb;
      settingsFormat = pkgs.formats.toml { };
      configFile = settingsFormat.generate "greptimedb.toml" cfg.settings;
      httpUrl = "http://${cfg.settings.http.addr}";

      # Static-user hardening following modules/nixos/omnigent.nix:147-161.
      hardening = {
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };

      # Records which users file the running store loaded, for R7.4: the
      # envelope compares it with the generator's public users-sha256. A
      # sha256 of 256-bit hex passwords is not reversible, so neither hash
      # leaks anything usable. Written via rename so a restart with a
      # preserved runtime directory never writes into a 0444 file.
      recordLoadedUsers = pkgs.writeShellApplication {
        name = "greptimedb-record-loaded-users";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          sha256sum < "$CREDENTIALS_DIRECTORY/users" | cut -d ' ' -f 1 > /run/greptimedb/loaded-users.sha256.tmp
          chmod 0444 /run/greptimedb/loaded-users.sha256.tmp
          mv -f /run/greptimedb/loaded-users.sha256.tmp /run/greptimedb/loaded-users.sha256
        '';
      };

      # CREATE ... IF NOT EXISTS is a no-op on an existing database, so the
      # ALTER is what applies a changed TTL (design F1).
      schemaStatements = lib.concatMap (database: [
        "CREATE DATABASE IF NOT EXISTS ${database}"
        "ALTER DATABASE ${database} SET 'ttl'='${cfg.databases.${database}}'"
      ]) (lib.attrNames cfg.databases);

      # The store has no readiness notification, so the job polls /health
      # (design F7). The password reaches curl on stdin through the printf
      # builtin, never on a command line.
      schema = pkgs.writeShellApplication {
        name = "greptimedb-schema";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
        ];
        text = ''
          password="$(cat "$CREDENTIALS_DIRECTORY/admin-password")"

          attempt=0
          until curl --silent --fail --output /dev/null ${httpUrl}/health; do
            attempt=$((attempt + 1))
            if [ "$attempt" -ge 60 ]; then
              echo "greptimedb-schema: ${httpUrl}/health did not answer within 120 s" >&2
              exit 1
            fi
            sleep 2
          done

          sql() {
            printf 'user = "admin:%s"\n' "$password" |
              curl --silent --show-error --fail-with-body --config - \
                --data-urlencode "sql=$1" ${httpUrl}/v1/sql
            echo
          }

          ${lib.concatMapStringsSep "\n" (statement: "sql ${lib.escapeShellArg statement}") schemaStatements}
        '';
      };
    in
    {
      options.services.greptimedb = {
        enable = lib.mkEnableOption "the GreptimeDB telemetry store";
        package = lib.mkPackageOption pkgs "greptimedb-bin" { };
        settings = lib.mkOption {
          inherit (settingsFormat) type;
          default = { };
          description = "GreptimeDB standalone configuration, rendered to TOML (upstream config/standalone.example.toml).";
        };
        databases = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          example = {
            fleet = "30d";
          };
          description = "Databases the schema job creates, each mapped to the TTL it sets with ALTER DATABASE.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = lib.hasPrefix "127." cfg.settings.grpc.bind_addr;
            message = "services.greptimedb.settings.grpc.bind_addr must be in 127.0.0.0/8: GreptimeDB 1.2.1 has no switch to disable gRPC (design D4).";
          }
        ];

        users.users.greptimedb = {
          isSystemUser = true;
          group = "greptimedb";
        };
        users.groups.greptimedb = { };

        services.greptimedb.settings = {
          enable_telemetry = false;
          user_provider = "static_user_provider:file:/run/credentials/greptimedb.service/users";
          max_in_flight_write_bytes = "128MB";
          write_bytes_exhausted_policy = "wait";
          max_concurrent_queries = 8;
          runtime = {
            global_rt_size = 4;
            compact_rt_size = 2;
          };
          http = {
            addr = "127.0.0.1:4000";
            enable_api_server = false;
          };
          grpc.bind_addr = "127.0.0.1:4001";
          mysql.enable = false;
          postgres.enable = false;
          opentsdb.enable = false;
          influxdb.enable = false;
          prom_store.enable = false;
          jaeger.enable = false;
          query.memory_pool_size = "512MB";
          storage.data_home = "/var/lib/greptimedb";
          region_engine = [
            {
              mito = {
                global_write_buffer_size = "256MB";
                scan_memory_limit = "512MB";
                scan_memory_on_exhausted = "fail";
                experimental_compaction_memory_limit = "256MB";
                max_background_compactions = 2;
                max_background_flushes = 2;
                page_cache_size = "256MB";
                sst_meta_cache_size = "64MB";
                vector_cache_size = "32MB";
                selector_result_cache_size = "32MB";
                range_result_cache_size = "32MB";
                prefilter_result_cache_size = "32MB";
                # ADR-007: the write cache is capped at 4 GiB on the 16G dataset.
                write_cache_size = "4GiB";
              };
            }
          ];
          # Journal only.
          logging.dir = "";
          # ADR-007: no event recorder, so no unrequested 90-day table.
          event_recorder.event_types = [ ];
        };

        systemd.services.greptimedb = {
          description = "GreptimeDB telemetry store";
          wantedBy = [ "multi-user.target" ];
          after = [ "network.target" ];
          startLimitIntervalSec = 0;
          # A missing dataset fails the unit instead of filling the root dataset.
          unitConfig.RequiresMountsFor = [ "/var/lib/greptimedb" ];
          serviceConfig = hardening // {
            ExecStartPre = lib.getExe recordLoadedUsers;
            ExecStart = "${lib.getExe cfg.package} standalone start --config-file ${configFile}";
            User = "greptimedb";
            Group = "greptimedb";
            StateDirectory = "greptimedb";
            StateDirectoryMode = "0700";
            RuntimeDirectory = "greptimedb";
            RuntimeDirectoryMode = "0755";
            WorkingDirectory = "/var/lib/greptimedb";
            Restart = "on-failure";
            RestartSec = 30;
            # Kill order under host OOM: evaluator 900, store 500, collector 300.
            MemoryHigh = "3G";
            MemoryMax = "4G";
            MemorySwapMax = "0";
            OOMScoreAdjust = 500;
            CPUWeight = 20;
          };
        };

        systemd.services.greptimedb-schema = {
          description = "GreptimeDB databases and retention";
          wantedBy = [ "multi-user.target" ];
          requires = [ "greptimedb.service" ];
          after = [ "greptimedb.service" ];
          partOf = [ "greptimedb.service" ];
          serviceConfig = hardening // {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe schema;
            User = "greptimedb";
            Group = "greptimedb";
          };
        };
      };
    };
}
```

Each TOML key above was confirmed against the v1.2.1 example (`/tmp/s1/standalone-v1.2.1.toml`): `enable_telemetry`, `user_provider`, `max_in_flight_write_bytes`, `write_bytes_exhausted_policy` and `max_concurrent_queries` are top-level (`:28-51`); `[runtime]` (`:54-58`); `[http] addr`, `enable_api_server` (`:64-96`); `[grpc] bind_addr` (`:102-104`); `[mysql]`, `[postgres]`, `[opentsdb]`, `[influxdb]`, `[jaeger]`, `[prom_store]` each take `enable` (`:131-221`); `[query] memory_pool_size` (`:441`); `[storage] data_home` (`:446`); `global_write_buffer_size`, `max_background_flushes`, `max_background_compactions`, `experimental_compaction_memory_limit`, `sst_meta_cache_size`, `vector_cache_size`, `page_cache_size`, `selector_result_cache_size`, `range_result_cache_size`, `prefilter_result_cache_size` (`:664`; otherwise 1/32 of OS memory up to 128MB), `write_cache_size`, `scan_memory_limit` and `scan_memory_on_exhausted` sit in `[[region_engine]]` `[region_engine.mito]` (`:579-716`); `[logging] dir` (`:850`); `[event_recorder] event_types`, where an empty array disables event recording (`:920-930`).
The event recorder is not among ADR-007's E7.1 clauses (it appears only under "Failure prevented"), so R7.1 does not assert it; Step 11 verifies the rendered value.
The `region_engine` list carries only `mito`, because v1.2.1 always builds the metric and file engines with defaults (`src/datanode/src/datanode.rs:495-546`).
The binary reads `--config-file` and the `GREPTIMEDB_STANDALONE` environment prefix (`src/cmd/src/standalone.rs:273-288`).

- [ ] **Step 5: Add the dataset to disko**

In `modules/machines/nixos/magnetite/disko.nix`, after the `"root/cognee"` block ending at line 80, insert:

```nix
          # Telemetry store WAL and caches (ADR-007; design D5). Created by hand
          # on the installed host (tasks.md 8.3); this declaration covers a
          # reinstall, and the zfs-*-root-greptimedb-* oneshots in default.nix
          # enforce the properties on every boot.
          "root/greptimedb" = {
            type = "zfs_fs";
            options = {
              mountpoint = "/var/lib/greptimedb";
              "com.sun:auto-snapshot" = "false";
              quota = "16G";
              reservation = "12G";
            };
            mountpoint = "/var/lib/greptimedb";
          };
```

- [ ] **Step 6: Import the module on magnetite**

In `modules/machines/nixos/magnetite/default.nix`, in the `with flakeModules; [ ... ]` list, after line 59 (`omnigraph`), insert:

```nix
        greptimedb
```

- [ ] **Step 7: Add the dataset binding and the three ZFS oneshots**

In `modules/machines/nixos/magnetite/default.nix`, inside the host module's `let` (lines 20-27), after the `omnigraphCookbooks` binding ending at line 26, insert:

```nix

      # The telemetry store's dataset (ADR-007 E7.3; design D5): one source for
      # the boot oneshots below and for greptimedb-envelope's environment.
      # disko.nix repeats the values as its install-time declaration, and
      # checks.x86_64-linux.greptimedb-envelope asserts the two agree.
      greptimedbDataset = {
        name = "zroot/root/greptimedb";
        mountpoint = "/var/lib/greptimedb";
        quota = "16G";
        reservation = "12G";
      };
```

Then, after the `zfs-set-root-home-reservation` block ending at line 263, insert:

```nix

      # The telemetry store's disk envelope, enforced at boot because disko
      # options apply at dataset creation only.
      systemd.services.zfs-set-root-greptimedb-quota = {
        description = "Assert quota=${greptimedbDataset.quota} on ${greptimedbDataset.name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set quota=${greptimedbDataset.quota} ${greptimedbDataset.name}";
        };
      };

      systemd.services.zfs-set-root-greptimedb-reservation = {
        description = "Assert reservation=${greptimedbDataset.reservation} on ${greptimedbDataset.name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set reservation=${greptimedbDataset.reservation} ${greptimedbDataset.name}";
        };
      };

      systemd.services.zfs-assert-root-greptimedb-noautosnap = {
        description = "Assert com.sun:auto-snapshot=false on ${greptimedbDataset.name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set com.sun:auto-snapshot=false ${greptimedbDataset.name}";
        };
      };
```

The store module keeps its own literal `/var/lib/greptimedb` (`StateDirectory`, `RequiresMountsFor`, `data_home`), because it is site-neutral; `diskoMatchesDataset` ties disko's mountpoint to the rendered `data_home`.

- [ ] **Step 8: Add the generators, store settings and credential wiring**

In `modules/machines/nixos/magnetite/default.nix`, after the `services.omnigraph` block ending at line 442, insert:

```nix

      # Store accounts for GreptimeDB (ADR-007, ADR-008; design D6). Hex
      # passwords, because a users line needs exactly one `=` and the store
      # silently skips a malformed line (design F2); written with printf '%s'
      # so no file carries a trailing newline into an HTTP basic-auth header.
      # perses-password has no consumer until S6. users-sha256 is public: the
      # sha256 of 256-bit hex passwords is not reversible, and R7.4 compares it
      # with /run/greptimedb/loaded-users.sha256.
      clan.core.vars.generators.greptimedb-users = {
        files.users = {
          owner = "greptimedb";
          mode = "0400";
          restartUnits = [ "greptimedb.service" ];
        };
        files.admin-password.mode = "0400";
        files.collector-password.mode = "0400";
        files.perses-password.mode = "0400";
        files.regulator-password.mode = "0400";
        files.users-sha256.secret = false;
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          admin="$(openssl rand -hex 32)"
          collector="$(openssl rand -hex 32)"
          perses="$(openssl rand -hex 32)"
          regulator="$(openssl rand -hex 32)"
          printf '%s' "$admin" > "$out/admin-password"
          printf '%s' "$collector" > "$out/collector-password"
          printf '%s' "$perses" > "$out/perses-password"
          printf '%s' "$regulator" > "$out/regulator-password"
          printf 'admin:rw=%s\ncollector:wo=%s\nperses:ro=%s\nregulator:ro=%s\n' \
            "$admin" "$collector" "$perses" "$regulator" > "$out/users"
          sha256sum "$out/users" | cut -d ' ' -f 1 > "$out/users-sha256"
        '';
      };

      # Cloudflare R2 credentials for the store's object data, an Object Read
      # & Write token on bucket sciexp, delivered as an EnvironmentFile in
      # GreptimeDB's GREPTIMEDB_STANDALONE__ layered-config form.
      clan.core.vars.generators.greptimedb-r2 = {
        prompts.access-key = {
          description = ''
            Cloudflare R2 S3 access key ID with Object Read & Write scope on
            bucket sciexp, for GreptimeDB. Minted in the Cloudflare dashboard;
            distinct from the omnigraph-r2 and niks3-s3 tokens.
          '';
          type = "hidden";
          persist = true;
          display = {
            group = "greptimedb";
            label = "GREPTIMEDB_STANDALONE__STORAGE__ACCESS_KEY_ID";
          };
        };

        prompts.secret-key = {
          description = "Cloudflare R2 S3 secret access key paired with the access key ID above.";
          type = "hidden";
          persist = true;
          display = {
            group = "greptimedb";
            label = "GREPTIMEDB_STANDALONE__STORAGE__SECRET_ACCESS_KEY";
          };
        };

        files.access-key.deploy = false;
        files.secret-key.deploy = false;

        files."env" = {
          restartUnits = [ "greptimedb.service" ];
        };

        script = ''
          {
            printf 'GREPTIMEDB_STANDALONE__STORAGE__ACCESS_KEY_ID=%s\n' "$(cat "$prompts/access-key")"
            printf 'GREPTIMEDB_STANDALONE__STORAGE__SECRET_ACCESS_KEY=%s\n' "$(cat "$prompts/secret-key")"
          } > "$out/env"
        '';
      };

      # Telemetry store (design D3 to D7). WAL and caches live on
      # zroot/root/greptimedb; SSTs go to R2 under one prefix of sciexp, at the
      # endpoint omnigraph already uses. Credentials arrive by path only.
      services.greptimedb = {
        enable = true;
        databases = {
          fleet = "30d";
          devloop = "365d";
          agent = "90d";
        };
        settings.storage = {
          type = "S3";
          bucket = "sciexp";
          root = "projects/vanixiets/observability/store/";
          endpoint = config.services.omnigraph.s3.endpointUrl;
          region = "auto";
          enable_virtual_host_style = false;
          disable_ec2_metadata = true;
          # ADR-007: the object-store read cache is capped at 4 GiB.
          cache_capacity = "4GiB";
        };
      };

      systemd.services.greptimedb.serviceConfig = {
        LoadCredential = [
          "users:${config.clan.core.vars.generators.greptimedb-users.files.users.path}"
        ];
        EnvironmentFile = config.clan.core.vars.generators.greptimedb-r2.files."env".path;
      };

      systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [
        "admin-password:${config.clan.core.vars.generators.greptimedb-users.files.admin-password.path}"
      ];
```

`cache_capacity` is a `[storage]` key in v1.2.1 because `ObjectStorageCacheConfig` is flattened into `S3Config` (`src/object-store/src/config.rs:169-178,361-370`); `disable_ec2_metadata` and `enable_virtual_host_style` are fields of `S3Connection` (`:119-137`).

- [ ] **Step 9: Rerun the envelope check and watch it pass**

Run: `jj st --no-pager >/dev/null && nix build .#checks.x86_64-linux.greptimedb-envelope -L 2>&1 | tee logs/greptimedb-envelope-green-$(date +%Y%m%d-%H%M%S).log`
Expected: the build succeeds and prints no `greptimedb envelope clauses failed` or `oracle accepted mutants` message.
The `jj st` snapshot makes the new `modules/nixos/greptimedb.nix` visible to the flake.
Success means the real configuration fails no clause, each of the fourteen mutants fails the clause it targets, the generator emits four valid lines with matching password files and hash, and both users-file mutants are rejected.

- [ ] **Step 10: Show one clause can fail its mutant**

Delete the line `memoryMax = (v.unit.MemoryMax or null) == "4G";` from `clauses` locally.
Run: `nix build .#checks.x86_64-linux.greptimedb-envelope 2>&1 | tee logs/greptimedb-envelope-converse-$(date +%Y%m%d-%H%M%S).log`
Expected: FAIL at evaluation with `greptimedb-envelope oracle accepted mutants: ["dropMemoryMax"]`.
Restore the line, rerun the same command, and expect success.

- [ ] **Step 11: Verify the rendered settings**

Run:

```bash
nix eval --json .#nixosConfigurations.magnetite.config.services.greptimedb.settings | jq -S . > logs/greptimedb-settings-actual.json
jq -S . > logs/greptimedb-settings-expected.json <<'EOF'
{
  "enable_telemetry": false,
  "grpc": { "bind_addr": "127.0.0.1:4001" },
  "http": { "addr": "127.0.0.1:4000", "enable_api_server": false },
  "influxdb": { "enable": false },
  "jaeger": { "enable": false },
  "event_recorder": { "event_types": [] },
  "logging": { "dir": "" },
  "max_concurrent_queries": 8,
  "max_in_flight_write_bytes": "128MB",
  "mysql": { "enable": false },
  "opentsdb": { "enable": false },
  "postgres": { "enable": false },
  "prom_store": { "enable": false },
  "query": { "memory_pool_size": "512MB" },
  "region_engine": [
    {
      "mito": {
        "experimental_compaction_memory_limit": "256MB",
        "global_write_buffer_size": "256MB",
        "max_background_compactions": 2,
        "max_background_flushes": 2,
        "page_cache_size": "256MB",
        "prefilter_result_cache_size": "32MB",
        "range_result_cache_size": "32MB",
        "scan_memory_limit": "512MB",
        "scan_memory_on_exhausted": "fail",
        "selector_result_cache_size": "32MB",
        "sst_meta_cache_size": "64MB",
        "vector_cache_size": "32MB",
        "write_cache_size": "4GiB"
      }
    }
  ],
  "runtime": { "compact_rt_size": 2, "global_rt_size": 4 },
  "storage": {
    "bucket": "sciexp",
    "cache_capacity": "4GiB",
    "data_home": "/var/lib/greptimedb",
    "disable_ec2_metadata": true,
    "enable_virtual_host_style": false,
    "endpoint": "https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com",
    "region": "auto",
    "root": "projects/vanixiets/observability/store/",
    "type": "S3"
  },
  "user_provider": "static_user_provider:file:/run/credentials/greptimedb.service/users",
  "write_bytes_exhausted_policy": "wait"
}
EOF
diff logs/greptimedb-settings-expected.json logs/greptimedb-settings-actual.json && echo settings-match
```

Expected: `settings-match` and no diff output.

- [ ] **Step 12: Inspect the delivered TOML**

Run:

```bash
unit="$(nix build --no-link --print-out-paths '.#nixosConfigurations.magnetite.config.systemd.units."greptimedb.service".unit')"
grep '^ExecStart=' "$unit/greptimedb.service"
toml="$(grep '^ExecStart=' "$unit/greptimedb.service" | sed 's/.*--config-file //')"
grep -nE '^\[|^(enable_telemetry|user_provider|addr|bind_addr|enable|page_cache_size|global_rt_size|compact_rt_size|dir|type|root|disable_ec2_metadata) ' "$toml"
```

Expected: `ExecStart=/nix/store/…-greptimedb-bin-1.2.1/bin/greptime standalone start --config-file /nix/store/…-greptimedb.toml`; the grep shows `enable_telemetry = false`, `user_provider = "static_user_provider:file:/run/credentials/greptimedb.service/users"`, `[http]` with `addr = "127.0.0.1:4000"`, `[grpc]` with `bind_addr = "127.0.0.1:4001"`, `enable = false` under each of `[influxdb]`, `[jaeger]`, `[mysql]`, `[opentsdb]`, `[postgres]`, `[prom_store]`, `[[region_engine]]` followed by `[region_engine.mito]` with `page_cache_size = "256MB"`, `[runtime]` with `compact_rt_size = 2` and `global_rt_size = 4`, `[logging]` with `dir = ""`, and `[storage]` with `type = "S3"`, `root = "projects/vanixiets/observability/store/"` and `disable_ec2_metadata = true`.

- [ ] **Step 13: Verify the store unit**

Run:

```bash
nix eval --json .#nixosConfigurations.magnetite.config.systemd.services.greptimedb.serviceConfig --apply 's: { inherit (s) User Group MemoryHigh MemoryMax MemorySwapMax OOMScoreAdjust CPUWeight Restart RestartSec StateDirectory RuntimeDirectory RuntimeDirectoryMode ProtectSystem UMask LoadCredential EnvironmentFile; }' | jq -S .
nix eval --json .#nixosConfigurations.magnetite.config.systemd.services.greptimedb.unitConfig --apply 'u: { inherit (u) RequiresMountsFor StartLimitIntervalSec; }'
```

Expected, first command:

```json
{
  "CPUWeight": 20,
  "EnvironmentFile": "/run/secrets/vars/per-machine/magnetite/greptimedb-r2/env",
  "Group": "greptimedb",
  "LoadCredential": [
    "users:/run/secrets/vars/per-machine/magnetite/greptimedb-users/users"
  ],
  "MemoryHigh": "3G",
  "MemoryMax": "4G",
  "MemorySwapMax": "0",
  "OOMScoreAdjust": 500,
  "ProtectSystem": "strict",
  "Restart": "on-failure",
  "RestartSec": 30,
  "RuntimeDirectory": "greptimedb",
  "RuntimeDirectoryMode": "0755",
  "StateDirectory": "greptimedb",
  "UMask": "0077",
  "User": "greptimedb"
}
```

Expected, second command: `{"RequiresMountsFor":["/var/lib/greptimedb"],"StartLimitIntervalSec":"0"}`; NixOS renders `startLimitIntervalSec` into `unitConfig` as a string.

- [ ] **Step 14: Verify the gRPC assertion bites**

Run:

```bash
nix eval --raw .#nixosConfigurations.magnetite.config.system.build.toplevel.drvPath >/dev/null && echo base-evaluates
nix eval --impure --raw --expr '
  let
    flake = builtins.getFlake (toString ./.);
    mutant = flake.nixosConfigurations.magnetite.extendModules {
      modules = [ { services.greptimedb.settings.grpc.bind_addr = flake.inputs.nixpkgs.lib.mkForce "0.0.0.0:4001"; } ];
    };
  in
  mutant.config.system.build.toplevel.drvPath' 2>&1 | grep -o 'grpc.bind_addr must be in 127.0.0.0/8'
```

Expected: `base-evaluates`, then `grpc.bind_addr must be in 127.0.0.0/8`.
This is a one-off demonstration and adds nothing to `checks`.

- [ ] **Step 15: Verify the schema job**

Run: `nix eval --json .#nixosConfigurations.magnetite.config.systemd.services.greptimedb-schema --apply 's: { inherit (s) after requires partOf; inherit (s.serviceConfig) Type RemainAfterExit User LoadCredential; }'`
Expected: `after`, `requires` and `partOf` each contain `"greptimedb.service"`, `Type` is `"oneshot"`, `RemainAfterExit` is `true`, `User` is `"greptimedb"`, `LoadCredential` is `["admin-password:/run/secrets/vars/per-machine/magnetite/greptimedb-users/admin-password"]`.

Run:

```bash
unit="$(nix build --no-link --print-out-paths '.#nixosConfigurations.magnetite.config.systemd.units."greptimedb-schema.service".unit')"
script="$(grep '^ExecStart=' "$unit/greptimedb-schema.service" | cut -d '=' -f 2-)"
grep -E '^(sql |until curl)' "$script"
```

Expected, in this order: `until curl --silent --fail --output /dev/null http://127.0.0.1:4000/health; do`, `sql 'CREATE DATABASE IF NOT EXISTS agent'`, `sql 'ALTER DATABASE agent SET '\''ttl'\''='\''90d'\'''`, then the same pair for `devloop` with `365d` and for `fleet` with `30d`, and no other `sql` line (in particular no logs table).

- [ ] **Step 16: Verify the generators**

Run: `nix eval --json .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files --apply 'fs: builtins.mapAttrs (_: f: { inherit (f) owner mode restartUnits; }) (builtins.removeAttrs fs [ "users-sha256" ])' | jq -S .`
Expected:

```json
{
  "admin-password": { "mode": "0400", "owner": "root", "restartUnits": [] },
  "collector-password": { "mode": "0400", "owner": "root", "restartUnits": [] },
  "perses-password": { "mode": "0400", "owner": "root", "restartUnits": [] },
  "regulator-password": { "mode": "0400", "owner": "root", "restartUnits": [] },
  "users": { "mode": "0400", "owner": "greptimedb", "restartUnits": [ "greptimedb.service" ] }
}
```

Run: `nix eval --json .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.users-sha256.secret`
Expected: `false`.

Run: `nix eval --json .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-r2 --apply 'g: { prompts = builtins.mapAttrs (_: p: { inherit (p) type persist; }) g.prompts; files = builtins.mapAttrs (_: f: { inherit (f) deploy restartUnits; }) g.files; }' | jq -S .`
Expected: `prompts` is `{"access-key":{"persist":true,"type":"hidden"},"secret-key":{"persist":true,"type":"hidden"}}`; `files` has `access-key` and `secret-key` with `deploy: false`, and `env` with `deploy: true` and `restartUnits: ["greptimedb.service"]`.
Step 13 already showed `env`'s path as `greptimedb.service`'s `EnvironmentFile`.

- [ ] **Step 17: Verify the dataset and oneshots**

Run:

```bash
nix eval --json '.#nixosConfigurations.magnetite.config.fileSystems."/var/lib/greptimedb"' --apply 'f: { inherit (f) device fsType; }'
for unit in zfs-set-root-greptimedb-quota zfs-set-root-greptimedb-reservation zfs-assert-root-greptimedb-noautosnap; do
  nix eval --raw ".#nixosConfigurations.magnetite.config.systemd.services.$unit.description"; echo
done
```

Expected: `{"device":"zroot/root/greptimedb","fsType":"zfs"}`, then `Assert quota=16G on zroot/root/greptimedb`, `Assert reservation=12G on zroot/root/greptimedb`, `Assert com.sun:auto-snapshot=false on zroot/root/greptimedb`.

- [ ] **Step 18: Build magnetite's system**

Run: `nix build .#checks.x86_64-linux.nixos-magnetite -L 2>&1 | tee logs/nixos-magnetite-greptimedb-$(date +%Y%m%d-%H%M%S).log`
Expected: success.
clan's sops backend skips secret files not yet generated (`clanCore/vars/secret/sops/generators-to-sops.nix:72`), and nothing in this task reads the public `users-sha256` value, so the build does not need Step 21's vars.

- [ ] **Step 19: Human step 8.1, mint the R2 token**

The operator, in the Cloudflare dashboard under R2 → Manage API tokens, creates an API token with permission "Object Read & Write", applied to the specific bucket `sciexp` only, with no TTL, and keeps the displayed Access Key ID and Secret Access Key for Step 21 without writing them to any file.
Verify: the operator confirms in the dashboard that the token lists exactly bucket `sciexp` and permission Object Read & Write, and states so in the session.

- [ ] **Step 20: Human step 8.3, create the dataset on magnetite**

Run:

```bash
mkdir -p logs/s1-evidence
ssh magnetite.zt 'sudo zfs create -o mountpoint=/var/lib/greptimedb -o com.sun:auto-snapshot=false zroot/root/greptimedb && zfs list -o name,mountpoint,quota,reservation,com.sun:auto-snapshot zroot/root/greptimedb' 2>&1 | tee logs/s1-evidence/8.3-zfs-create.log
```

Expected: `zroot/root/greptimedb  /var/lib/greptimedb  none  none  false`; the log is the evidence Task 7 folds into `verify.md`.
The quota and reservation read `none` until the boot oneshots run at deployment.

- [ ] **Step 21: Human step 8.2, generate the vars**

From this change's working copy (the development join's `@`, which holds Steps 1–8), the operator runs `clan vars generate magnetite` and pastes the Step 19 Access Key ID and Secret Access Key at the two hidden `greptimedb` prompts; `greptimedb-users` generates without input.
Run: `clan vars list magnetite 2>&1 | grep -E '^greptimedb-(users|r2)/'`
Expected: entries for `greptimedb-users/users`, `admin-password`, `collector-password`, `perses-password`, `regulator-password`, `users-sha256` and `greptimedb-r2/access-key`, `secret-key`, `env`, with every secret shown masked.
Run: `jj diff --name-only -- vars/`
Expected: only paths under `vars/per-machine/magnetite/greptimedb-users/` and `vars/per-machine/magnetite/greptimedb-r2/`.

- [ ] **Step 22: Tick the tasks**

In `openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md`, change `- [ ]` to `- [x]` on the lines beginning `- [ ] 2.1`, `2.2`, `2.3`, `2.4`, `2.5`, `2.6`, `4.1`, `4.2`, `4.3`, `8.1`, `8.2` and `8.3`, and nothing else.
Run: `jj diff --git -- openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md | grep -c '^+- \[x\]'`
Expected: `12`.

- [ ] **Step 23: Commit**

Run:

```bash
jj new --no-edit -r main@origin -m 'feat(greptimedb): run the telemetry store on magnetite with its evaluation-time envelope'
change="$(jj log --no-graph -r 'children(main@origin) & empty() & description(substring:"feat(greptimedb): run the telemetry store on magnetite")' -T 'change_id.shortest(8)')"
jj squash --from @ --into "$change" --keep-emptied --use-destination-message -- \
  modules/checks/greptimedb-envelope.nix \
  modules/nixos/greptimedb.nix \
  modules/machines/nixos/magnetite/default.nix \
  modules/machines/nixos/magnetite/disko.nix \
  vars/per-machine/magnetite/greptimedb-users \
  vars/per-machine/magnetite/greptimedb-r2 \
  openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md
jj diff --name-only -r "$change"
```

Expected: the last command lists the four module files, `tasks.md`, and the files under the two `vars/per-machine/magnetite/` generator directories, and nothing else.
If `jj diff -r @ -- openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md` showed hunks other than the twelve ticks before the squash, squash that file with `jj squash --from @ --into "$change" --interactive --keep-emptied --use-destination-message -- openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md` and select only the ticks.
The orchestrator rebases the development join, pushes, opens the pull request and enqueues it; the dataset from Step 20 already exists, so `main` stays deployable once it merges.

---

### Task 3: Collector, notifier and nixbot metrics, with R3.1 and R1.2

Implements `tasks.md` 3.1–3.7 and 4.4 (design D8, D9, D10, D11; specs `host-metrics-collection` and `telemetry-store-interface`).
The regulator is written first and fails, then the collector, notifier, inventory, nixbot loopback server and magnetite's unit list make it pass.

**Files:**
- Create: `modules/checks/otel-collector-config.nix`
- Create: `modules/clan/services/otel-collector/schema.nix`
- Create: `modules/clan/services/otel-collector/flake-module.nix`
- Create: `modules/clan/inventory/services/otel-collector.nix`
- Modify: `modules/checks/greptimedb-envelope.nix` (Task 2's `credentialHolders` binding, line `collector-password = [ ];`)
- Modify: `modules/nixos/nixbot.nix:216-219` (add the loopback server after the "Prometheus endpoint" block)
- Modify: `modules/machines/nixos/magnetite/default.nix` (add `services.observability-notify.units` before the comment `# Raise nix daemon free-space thresholds for a build host.`; in Task 2's `greptimedb-users` generator, give `collector-password` its `restartUnits`)
- Modify: `openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md` (tick 3.1–3.7 and 4.4)

**Interfaces:**
- Consumes:
  - `pkgs.ntfy-send` (Task 1): `ntfy-send MESSAGE [TOPIC] [CURL_ARGS…]`, `mainProgram = "ntfy-send"`, runs `curl` from `PATH` on Linux, so callers put `pkgs.curl` on `PATH` and pass the topic.
  - `services.greptimedb.package.version` (Task 2, `greptimedb-bin` 1.2.1).
  - `clan.core.vars.generators.greptimedb-users.files.collector-password.path` (Task 2, declared in magnetite's `default.nix`).
  - Units `greptimedb`, `greptimedb-schema`, `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation`, `zfs-assert-root-greptimedb-noautosnap` (Task 2) and the six existing ZFS oneshots (`default.nix:193-263`).
  - Task 2's `credentialHolders` binding in `modules/checks/greptimedb-envelope.nix`, whose holders are matched by `LoadCredential` source path.
- Produces:
  - `flake.lib.otelCollectorSchema = { systemdUnits; ownerAliases; promotedResourceAttributes; nodeExporterKeep; process = { minBytes; maxNames; }; databases; }` from `modules/clan/services/otel-collector/schema.nix` (a flake-parts module, because import-tree imports every `.nix` file under `modules/`); consumed as `config.flake.lib.otelCollectorSchema` in flake modules and `self.lib.otelCollectorSchema` in checks and tests, never imported by path.
  - Plain NixOS modules `flake.modules.nixos.otel-collector-agent` and `flake.modules.nixos.otel-collector-ingress`; the clan service `clan.modules.otel-collector` with roles `agent` and `ingress` imports them, and only the clan `ingress` role adds `LoadCredential = [ "collector-password:<clan vars path>" ]`.
  - Option `services.observability-notify.units` (list of `systemd.services` attribute names, without `.service`), declared by `otel-collector-agent`, which itself contributes `"opentelemetry-collector"`; for each listed unit it sets `unitConfig.OnFailure = [ "observability-notify@%n.service" ]` and `serviceConfig.ExecStopPost = [ "-+/nix/store/<hash>-observability-notify-resolved %n" ]`.
  - Unit `observability-notify@.service`: skips while `/var/lib/observability-notify/%i` exists, otherwise posts `FAILED <unit> on <host>` to `https://ntfy.zt/fleet-alerts` and creates the stamp; the hook posts `RESOLVED <unit> on <host>` and removes the stamp when the unit exits with `SERVICE_RESULT=success` and the stamp exists.
  - Collector names: pipelines `metrics/host`, `metrics/process` (agent), `metrics/ingress`, `metrics/fleet`, `metrics/devloop`, `metrics/agent` (ingress); processors `memory_limiter`, `transform/omnigent-alias`, `resource/agent`, `groupbyattrs/compact`, `metrics_transform/process`, `filter/process-min`, `transform/exphist`, `resource/strip-database`; connectors `forward`, `routing`; exporters `otlp_http/fleet|devloop|agent`; extensions `file_storage` (directory `/var/lib/opentelemetry-collector/queue`) and `basicauth/store` (`password_file = /run/credentials/opentelemetry-collector.service/collector-password`).
  - `checks.x86_64-linux.otel-collector-config` with the literal `notifiedUnits` binding (12 names here; Task 4 adds `"greptimedb-envelope"`).
  - nginx server `nixbot-metrics-loopback` on `127.0.0.1:9180`, `/metrics` proxied to `http://unix:/run/nixbot/web.sock`.

Source facts this task relies on, confirmed against `opentelemetry-collector-contrib` and `opentelemetry-collector` at tag `v0.155.0` (the pinned `otelcol-contrib-src-0.155.0`):
component types are `host_metrics`, `otlp_http`, `memory_limiter`, `file_storage`, `metrics_transform`, `basicauth`, `routing`, `forward`, `transform`, `filter`, `groupbyattrs`, `resource`, `nginx`, `prometheus`, `systemd` (each component's `metadata.yaml`);
the systemd receiver takes `scope` (`system`|`user`) and `units` (systemd patterns), sets `systemd.unit.name` to the full unit name with `.service` (`receiver/systemdreceiver/config.go`, `scraper.go:181`), and ships `systemd.service.restarts` disabled and `systemd.service.cpu.time` enabled by default (`metadata.yaml`);
the paging scraper defines `system.paging.usage`, `.operations`, `.faults` (enabled) and `.utilization` (disabled); the memory scraper ships `system.linux.memory.available` disabled; the process scraper's resource attributes and metrics are toggled by `resource_attributes.<name>.enabled` and `metrics.<name>.enabled`, and only `process.cpu.time`, `process.disk.io`, `process.memory.usage` and `process.memory.virtual` are on by default;
the routing connector takes `table: [{ context, condition, pipelines }]`;
`basicauth` `client_auth` has `username` and `password_file`, and its `Validate` does not open the file (`extension/basicauthextension/config.go:36,50-60`);
`file_storage` `Validate` stats `directory` unless `create_directory` is set;
the prometheus receiver's `Validate` stats `authorization.credentials_file` (`receiver/prometheusreceiver/config.go:211-231`), so the zerotierone job's credential path cannot exist at build time and is replaced for validation only;
`--set` values are YAML and arrays are overridden (`otelcol/flags.go:39-48`);
`convert_exponential_histogram_to_histogram(distribution, [ExplicitBounds])` is a metric-context OTTL function (`processor/transformprocessor/README.md:475-552`);
the persistent queue is `sending_queue.storage` with `sizer` one of `requests|items|bytes` (`exporter/exporterhelper/README.md`).
GreptimeDB v1.2.1 splits `x-greptime-otlp-metric-promote-resource-attrs` on `;` (`src/servers/src/http/extractor.rs:179`) and serves `/metrics` outside `/v1` (`src/servers/src/http.rs:1132`).
zerotierone reads `enableMetrics` from `local.conf` (`ZeroTierOne@899352e3 service/OneService.cpp:3292`) and accepts the metrics token as a bearer token (`:2162-2181`).
On magnetite today: `services.nginx.statusPage = true` (the `localhost` vhost, `/nginx_status`), zerotierone 1.16.0 enabled with no metrics setting, gitea on port 3002 with `[metrics] ENABLED = true`, niks3 on `127.0.0.1:5752`, and the units `omnigent-host-cameron` and `omnigent-host-janettesmith`.

- [ ] **Step 1: Write the failing regulator**

Create `modules/checks/otel-collector-config.nix`.
Four of ADR-003's five R3.1 mutants (A3:233) apply here: the unknown component key, a receiver endpoint of `0.0.0.0:4318`, an exporter `listenAddress` of `0.0.0.0`, and `process.command_line` enabled; the darwin node_exporter mutant belongs to S5.

```nix
# R3.1 and R1.2 over magnetite's collector (design D11; tasks.md 4.4).
#
# R3.1 reads the evaluated collector configuration, node_exporter, the
# owner-alias transform and the failure-notifier wiring; R1.2 requires the
# exponential-histogram conversion while the store is below 1.3.0 (ADR-001).
# Each mutant edits the evaluated input and must produce a non-empty failure
# list (modules/checks/omnigent-environment.nix pattern), so a successful
# build shows every mutant failing. The derivation depends on the validated
# configuration file, so building the check runs `otelcol-contrib validate`
# on what magnetite deploys, and it runs the unknown-key mutant through the
# same validator, which must reject it. Of ADR-003's five R3.1 mutants
# (A3:233), the darwin node_exporter one belongs to S5; the other four are
# here.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      magnetite = self.nixosConfigurations.magnetite.config;
      collector = magnetite.services.opentelemetry-collector;

      mib = n: n * 1024 * 1024;

      # Unmeasured estimate of magnetite's `fleet` export rate: about 2000
      # series (ADR-004's ~800 host-level series per NixOS host plus the
      # scraped service endpoints) at 128 bytes per OTLP number point with its
      # resource and attribute overhead, one point per minute. The deployment
      # measurement (logs/s1-evidence/8.5-queue-rate.log) replaces it.
      fleetBytesPerMinute = 256000;

      # The units the failure path wires (design "Failure path"). A literal,
      # so dropping a unit from services.observability-notify.units fails.
      notifiedUnits = [
        "greptimedb"
        "greptimedb-schema"
        "opentelemetry-collector"
        "zfs-assert-root-docker-noautosnap"
        "zfs-assert-root-greptimedb-noautosnap"
        "zfs-assert-root-nix-noautosnap"
        "zfs-assert-root-podman-noautosnap"
        "zfs-set-root-greptimedb-quota"
        "zfs-set-root-greptimedb-reservation"
        "zfs-set-root-home-reservation"
        "zfs-set-root-nix-quota"
        "zfs-set-root-nixos-reservation"
      ];

      sixProcessAttributes = [
        "process.pid"
        "process.parent_pid"
        "process.command"
        "process.command_line"
        "process.executable.path"
        "process.owner"
      ];

      expectedScrapeTargets = [
        "127.0.0.1:3002"
        "127.0.0.1:4000"
        "127.0.0.1:5752"
        "127.0.0.1:9100"
        "127.0.0.1:9180"
        "127.0.0.1:9993"
      ];

      expectedNodeFlags = [
        "--collector.disable-defaults"
        "--collector.zfs"
        "--collector.vmstat"
        "--collector.vmstat.fields=^oom_kill$"
      ];

      isLoopback =
        s:
        builtins.match "(https?://)?(127\\.[0-9]+\\.[0-9]+\\.[0-9]+|\\[::1]|localhost)(:[0-9]+)?(/.*)?" s
        != null;

      # Every `endpoint` string anywhere under a component section.
      collectEndpoints =
        value:
        if builtins.isAttrs value then
          lib.concatLists (
            lib.mapAttrsToList (
              name: inner:
              if name == "endpoint" && builtins.isString inner then [ inner ] else collectEndpoints inner
            ) value
          )
        else if builtins.isList value then
          lib.concatMap collectEndpoints value
        else
          [ ];

      # systemd unit patterns as regular expressions over attribute names.
      unitRegex = pattern: builtins.replaceStrings [ "." "*" ] [ "\\." ".*" ] pattern;
      matchesAllowList =
        patterns: name: lib.any (p: builtins.match (unitRegex p) "${name}.service" != null) patterns;

      resolvedHook = "-\\+/nix/store/[a-z0-9]{32}-observability-notify-resolved %n";

      input = {
        settings = collector.settings;
        overrides = collector.validateConfigOverrides;
        collectorService = magnetite.systemd.services.opentelemetry-collector.serviceConfig;
        node = magnetite.services.prometheus.exporters.node;
        nodeService = magnetite.systemd.services.prometheus-node-exporter.serviceConfig;
        nginxStatusPage = magnetite.services.nginx.statusPage;
        zerotierMetrics = magnetite.services.zerotierone.localConf.settings.enableMetrics or false;
        services = magnetite.systemd.services;
        notifyUnits = magnetite.services.observability-notify.units;
        schema = self.lib.otelCollectorSchema;
        storeVersion = magnetite.services.greptimedb.package.version;
      };

      failures =
        i:
        let
          s = i.settings;
          r = s.receivers;
          p = s.processors;
          e = s.exporters;
          pipelines = s.service.pipelines;
          check = name: ok: lib.optional (!ok) name;
          dbs = i.schema.databases;
          exporterNames = map (db: "otlp_http/${db}") dbs;
          process = r."host_metrics/process".scrapers.process;
          memory = r."host_metrics/memory".scrapers;
          promTargets = lib.concatMap (
            name:
            lib.concatMap (job: lib.concatMap (sc: sc.targets) job.static_configs) r.${name}.config.scrape_configs
          ) (builtins.filter (lib.hasPrefix "prometheus") (builtins.attrNames r));
          nodeJob = lib.findFirst (job: job.job_name == "node") null r.prometheus.config.scrape_configs;
          queueSizes = map (n: e.${n}.sending_queue.queue_size or 0) exporterNames;
          hostUnits = builtins.attrNames i.services;
          owners = lib.concatMap (
            name:
            let
              m = builtins.match "omnigent-host-(.+)" name;
            in
            lib.optional (m != null) (builtins.head m)
          ) hostUnits;
          aliasStatements = p."transform/omnigent-alias".metric_statements or [ ];
          aliasStatement =
            owner:
            ''set(resource.attributes["systemd.unit.name"], "omnigent-host-${i.schema.ownerAliases.${owner}}.service") where resource.attributes["systemd.unit.name"] == "omnigent-host-${owner}.service"'';
          zerotierJobs = map (job: builtins.removeAttrs job [ "authorization" ]) (
            r."prometheus/zerotier".config.scrape_configs or [ ]
          );
          overrideParts = map (builtins.match "([^=]*)=(.*)") i.overrides;
          unitWired =
            name:
            let
              u =
                i.services.${name} or {
                  unitConfig = { };
                  serviceConfig = { };
                };
            in
            (u.unitConfig.OnFailure or null) == [ "observability-notify@%n.service" ]
            && lib.any (hook: builtins.match resolvedHook hook != null) (
              lib.toList (u.serviceConfig.ExecStopPost or [ ])
            );
          notifier = i.services."observability-notify@".serviceConfig.ExecStart or "";
          exphist = p."transform/exphist".metric_statements or [ ];
        in
        lib.concatLists [
          # Loopback (R3.1; telemetry-store-interface "Scrape targets are reached on loopback").
          (check "R3.1: receiver or exporter endpoint off loopback" (
            lib.all isLoopback (collectEndpoints r ++ collectEndpoints e)
          ))
          (check "R3.1: scrape targets differ from the loopback set" (
            lib.naturalSort promTargets == expectedScrapeTargets
          ))
          (check "R3.1: nginx stub_status not collected" (
            i.nginxStatusPage && (r.nginx.endpoint or "") == "http://127.0.0.1:80/nginx_status"
          ))
          (check "R3.1: zerotierone metrics not enabled" (i.zerotierMetrics == true))
          (check "R3.1: node_exporter not on loopback" (
            i.node.enable && i.node.listenAddress == "127.0.0.1" && !i.node.openFirewall
          ))
          (check "R3.1: node_exporter collectors or envelope" (
            i.node.extraFlags == expectedNodeFlags && (i.nodeService.MemoryMax or null) == "64M"
          ))
          (check "R3.1: node_exporter keep-list" (
            nodeJob != null
            && (nodeJob.metric_relabel_configs or [ ]) == [
              {
                source_labels = [ "__name__" ];
                regex = lib.concatStringsSep "|" i.schema.nodeExporterKeep;
                action = "keep";
              }
            ]
          ))

          # Bounds (host-metrics-collection "Series cardinality stays bounded").
          (check "R3.1: process identity attribute enabled" (
            lib.all (a: (process.resource_attributes.${a}.enabled or true) == false) sixProcessAttributes
          ))
          (check "R3.1: process metrics other than memory usage" (
            process.metrics == {
              "process.memory.usage".enabled = true;
              "process.cpu.time".enabled = false;
              "process.disk.io".enabled = false;
              "process.memory.virtual".enabled = false;
            }
          ))
          (check "R3.1: process 64 MiB filter" (
            i.schema.process.minBytes == mib 64
            && i.schema.process.maxNames == 30
            && (p."filter/process-min".metric_conditions or [ ]) == [
              ''metric.name == "process.memory.usage" and datapoint.value_int < ${toString i.schema.process.minBytes}''
            ]
            && builtins.elem "filter/process-min" pipelines."metrics/process".processors
          ))
          (check "R3.1: paging beyond usage" (
            memory.paging.metrics == {
              "system.paging.usage".enabled = true;
              "system.paging.operations".enabled = false;
              "system.paging.faults".enabled = false;
              "system.paging.utilization".enabled = false;
            }
          ))
          (check "R3.1: available memory not collected" (
            (memory.memory.metrics."system.linux.memory.available".enabled or false) == true
          ))
          (check "R3.1: systemd units differ from schema.nix" (
            r.systemd.units == i.schema.systemdUnits && r.systemd.scope == "system"
          ))
          (check "R3.1: systemd metrics" (
            r.systemd.metrics == {
              "systemd.service.restarts".enabled = true;
              "systemd.service.cpu.time".enabled = false;
            }
          ))
          (check "R3.1: more than 40 allow-listed units" (
            builtins.length i.schema.systemdUnits <= 40
            && builtins.length (builtins.filter (matchesAllowList i.schema.systemdUnits) hostUnits) <= 40
          ))
          (check "R3.1: omnigent-host owner without alias" (
            lib.all (o: i.schema.ownerAliases ? ${o} && builtins.elem (aliasStatement o) aliasStatements) owners
            && builtins.elem "transform/omnigent-alias" pipelines."metrics/host".processors
          ))
          (check "R3.1: an alias carries an owner name" (
            lib.all (alias: lib.all (o: !(lib.hasInfix o alias)) owners) (
              builtins.attrValues i.schema.ownerAliases
            )
          ))

          # Ingest (telemetry-store-interface "Ingest is OTLP over HTTP with a database header").
          (check "R3.1: a logs or traces pipeline" (
            lib.all (lib.hasPrefix "metrics/") (builtins.attrNames pipelines)
          ))
          (check "R3.1: routing table" (
            lib.all (
              db:
              lib.any (
                t: t.condition == ''attributes["vanixiets.database"] == "${db}"'' && t.pipelines == [ "metrics/${db}" ]
              ) s.connectors.routing.table
            ) dbs
          ))
          (check "R3.1: exporter endpoint, headers or auth" (
            lib.all (
              db:
              let
                x = e."otlp_http/${db}";
              in
              x.endpoint == "http://127.0.0.1:4000/v1/otlp"
              && x.headers == {
                "x-greptime-db-name" = db;
                "x-greptime-otlp-metric-promote-resource-attrs" = lib.concatStringsSep ";" i.schema.promotedResourceAttributes;
              }
              && x.auth.authenticator == "basicauth/store"
            ) dbs
          ))
          (check "R3.1: store credential" (
            s.extensions."basicauth/store".client_auth == {
              username = "collector";
              password_file = "/run/credentials/opentelemetry-collector.service/collector-password";
            }
          ))

          # Queue (host-metrics-collection "Collection survives a telemetry store restart").
          (check "R3.1: queue not in file_storage" (
            lib.all (
              n:
              (e.${n}.sending_queue.storage or null) == "file_storage"
              && (e.${n}.sending_queue.sizer or null) == "bytes"
              && (e.${n}.retry_on_failure.max_elapsed_time or null) == "0s"
            ) exporterNames
          ))
          (check "R3.1: queue directory" (
            lib.hasPrefix "/var/lib/opentelemetry-collector/" s.extensions.file_storage.directory
            && s.extensions.file_storage.create_directory == true
          ))
          (check "R3.1: fleet queue below 24 h" (
            (e."otlp_http/fleet".sending_queue.queue_size or 0) >= 24 * 60 * fleetBytesPerMinute
          ))
          (check "R3.1: queues at or above 512 MiB" (lib.foldl' builtins.add 0 queueSizes < mib 512))

          # Envelope (telemetry-store-interface "run inside a declared envelope").
          (check "R3.1: collector envelope" (
            p.memory_limiter.limit_mib == 384
            && builtins.head pipelines."metrics/ingress".processors == "memory_limiter"
            && (i.collectorService.MemoryMax or null) == "512M"
            && (i.collectorService.OOMScoreAdjust or null) == 300
          ))

          # Validation override: only the zerotierone job's authorization.
          (check "R3.1: validation override beyond the zerotierone authorization" (
            zerotierJobs != [ ]
            && builtins.length overrideParts == 1
            && lib.all (m: m != null) overrideParts
            && builtins.elemAt (builtins.head overrideParts) 0
              == "receivers::prometheus/zerotier::config::scrape_configs"
            && builtins.fromJSON (builtins.elemAt (builtins.head overrideParts) 1) == zerotierJobs
          ))

          # Failure wiring (telemetry-store-interface "Failure notices are posted to one topic").
          (check "R3.1: notified units differ" (lib.naturalSort i.notifyUnits == notifiedUnits))
          (check "R3.1: a named unit is not wired to the notifier" (lib.all unitWired notifiedUnits))
          (check "R3.1: notifier does not post to fleet-alerts with ntfy-send" (
            lib.hasInfix "/bin/ntfy-send " notifier && lib.hasInfix " fleet-alerts" notifier
          ))

          # R1.2 (ADR-001): below 1.3.0 the store needs explicit-bucket histograms.
          (lib.optional (
            lib.versionOlder i.storeVersion "1.3.0"
            && !(
              builtins.elem "transform/exphist" pipelines."metrics/ingress".processors
              && lib.any (lib.hasPrefix "convert_exponential_histogram_to_histogram(") exphist
            )
          ) "R1.2: exponential-histogram conversion missing below store 1.3.0")
        ];

      actual = failures input;

      onSettings = update: i: i // { settings = lib.recursiveUpdate i.settings update; };

      mutants = {
        # A3:233: a receiver endpoint of 0.0.0.0:4318.
        receiverEndpointWildcard = onSettings {
          receivers.otlp.protocols.http.endpoint = "0.0.0.0:4318";
        };
        # A3:233: an exporter listenAddress of 0.0.0.0.
        exporterListenWildcard = i: i // { node = i.node // { listenAddress = "0.0.0.0"; }; };
        # A3:233: process.command_line enabled.
        commandLineEnabled = onSettings {
          receivers."host_metrics/process".scrapers.process.resource_attributes."process.command_line".enabled =
            true;
        };
        scrapeTargetOffLoopback =
          i:
          onSettings {
            receivers.prometheus.config.scrape_configs = map (
              job:
              if job.job_name == "node" then job // { static_configs = [ { targets = [ "10.147.17.1:9100" ]; } ]; } else job
            ) i.settings.receivers.prometheus.config.scrape_configs;
          } i;
        systemdUnitsDiverge =
          i: onSettings { receivers.systemd.units = i.settings.receivers.systemd.units ++ [ "user@*.service" ]; } i;
        systemdUnitsOverCap =
          i:
          let
            units = i.schema.systemdUnits ++ map (n: "cap-${toString n}.service") (lib.range 1 20);
          in
          (onSettings { receivers.systemd.units = units; } i)
          // {
            schema = i.schema // {
              systemdUnits = units;
            };
          };
        ownerWithoutAlias =
          i:
          i
          // {
            schema = i.schema // {
              ownerAliases = builtins.removeAttrs i.schema.ownerAliases [ "cameron" ];
            };
          };
        queueInMemory =
          i:
          i
          // {
            settings = i.settings // {
              exporters = i.settings.exporters // {
                "otlp_http/fleet" = i.settings.exporters."otlp_http/fleet" // {
                  sending_queue = builtins.removeAttrs i.settings.exporters."otlp_http/fleet".sending_queue [
                    "storage"
                  ];
                };
              };
            };
          };
        queueUnder24h = onSettings { exporters."otlp_http/fleet".sending_queue.queue_size = mib 64; };
        queueOver512MiB = onSettings { exporters."otlp_http/fleet".sending_queue.queue_size = mib 448; };
        overrideTouchesAnotherReceiver =
          i: i // { overrides = i.overrides ++ [ "receivers::host_metrics/memory::collection_interval=1s" ]; };
        onFailureDropped =
          i:
          i
          // {
            services = i.services // {
              opentelemetry-collector = i.services.opentelemetry-collector // {
                unitConfig = builtins.removeAttrs i.services.opentelemetry-collector.unitConfig [ "OnFailure" ];
              };
            };
          };
        # R1.2's mutant.
        conversionRemoved = onSettings { processors."transform/exphist".metric_statements = [ ]; };
      };

      # hostmetricsreceiver ignores unknown top-level keys (receiver/hostmetricsreceiver/config.go Unmarshal, WithIgnoreUnused, v0.155.0), so the probe targets a strictly decoded component.
      unknownKeyConfig = (pkgs.formats.yaml { }).generate "otel-collector-unknown-key.yaml" (
        lib.recursiveUpdate collector.settings { processors.memory_limiter.unknown_key = true; }
      );
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        otel-collector-config =
          assert lib.assertMsg (actual == [ ]) "otel-collector-config failures: ${builtins.toJSON actual}";
          assert lib.assertMsg (lib.all (mutant: failures (mutant input) != [ ]) (lib.attrValues mutants))
            "otel-collector-config accepted a mutant: ${
              builtins.toJSON (builtins.attrNames (lib.filterAttrs (_: m: failures (m input) == [ ]) mutants))
            }";
          pkgs.runCommand "otel-collector-config"
            {
              # The configuration magnetite deploys, validated by nixpkgs'
              # module with `otelcol-contrib validate` at build time.
              validated = magnetite.system.build.opentelemetryCollectorConfig;
              passthru = { inherit failures; };
            }
            ''
              test -s "$validated"
              # A3:233: an unknown component key must be rejected by the same
              # validator with the same overrides.
              if result=$(${lib.getExe collector.package} validate --config=file:${unknownKeyConfig} ${
                lib.escapeShellArgs (map (o: "--set=${o}") collector.validateConfigOverrides)
              } 2>&1); then
                echo "otelcol-contrib validate accepted an unknown key" >&2
                exit 1
              fi
              if ! printf '%s\n' "$result" | grep -q unknown_key; then
                echo "validation failed for a reason other than the unknown key:" >&2
                printf '%s\n' "$result" >&2
                exit 1
              fi
              touch "$out"
            '';
      };
    };
}
```

Snapshot the new file so the flake source sees it (jj adds it to the git index when it snapshots):

```bash
jj st --no-pager >/dev/null
```

- [ ] **Step 2: Extend Task 2's credential-holder data**

In `modules/checks/greptimedb-envelope.nix`, inside the `credentialHolders` binding, replace the line

```nix
          collector-password = [ ];
```

with

```nix
          collector-password = [ "opentelemetry-collector" ];
```

- [ ] **Step 3: Run both checks to see them fail**

Run:

```bash
mkdir -p logs
nix build .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/t3-otel-collector-config-red-$(date +%Y%m%d-%H%M%S).log | tail -n 20
nix build .#checks.x86_64-linux.greptimedb-envelope 2>&1 | tee logs/t3-greptimedb-envelope-red-$(date +%Y%m%d-%H%M%S).log | tail -n 20
```

Expected: the first fails at evaluation with `error: attribute '…' missing`, naming `otelCollectorSchema`, `receivers` or `observability-notify` (none of them exists yet).
The second fails on Task 2's R8.2 credential-holder assertion for `collector-password`, because no unit loads it yet.

- [ ] **Step 4: Write the schema**

Create `modules/clan/services/otel-collector/schema.nix`:

```nix
# Single source of the collector's allow-lists and bounds (ADR-004
# "Implementation surface"; design D8, D9). The otel-collector clan service
# builds its receivers, transforms and exporter headers from it, and
# checks.x86_64-linux.otel-collector-config compares magnetite's evaluated
# configuration against it. import-tree loads every .nix file under
# modules/, so this is a flake-parts module exposing the data as
# flake.lib.otelCollectorSchema; nothing imports it by path. S1 carries the
# keys S1 deploys; later slices add theirs here.
{ ... }:
{
  flake.lib.otelCollectorSchema = {
    # ADR-004's systemd unit allow-list, `.service` units only, as systemd
    # unit patterns. At most 40 units may match on one host (ADR-004 Q12).
    systemdUnits = [
      "gitea.service"
      "gitea-mq.service"
      "nixbot*.service"
      "niks3*.service"
      "nix-daemon.service"
      "nix-grpc-daemon.service"
      "harmonia-gc.service"
      "postgresql.service"
      "nginx.service"
      "greptimedb.service"
      "opentelemetry-collector.service"
      "zerotierone.service"
      "omnigent-host-*.service"
      "omnigraph.service"
      "otel-envelope.service"
      "devloop-reconcile.service"
      "greptimedb-envelope.service"
      "greptimedb-export.service"
      "greptimedb-schema.service"
      "prometheus-node-exporter.service"
      "prometheus-smartctl-exporter.service"
      "zfs-assert-*.service"
      "zfs-set-*.service"
    ];

    # omnigent-host-<owner>.service is stored as omnigent-host-<alias>.service
    # (ADR-003 item 17), so no owner's name becomes a label value. Opaque and
    # stable: a new owner takes the next number and no alias is renumbered.
    ownerAliases = {
      cameron = "owner-1";
      janettesmith = "owner-2";
    };

    # Resource attributes the store promotes to labels (ADR-003 item 15).
    promotedResourceAttributes = [
      "host.name"
      "systemd.unit.name"
      "process.executable.name"
    ];

    # node_exporter series kept; every other is dropped (ADR-004).
    nodeExporterKeep = [
      "node_zfs_zpool_state"
      "node_zfs_arc_size"
      "node_zfs_arc_c"
      "node_zfs_arc_c_min"
      "node_zfs_arc_c_max"
      "node_zfs_arc_hits"
      "node_zfs_arc_misses"
      "node_zfs_arc_memory_throttle_count"
      "node_vmstat_oom_kill"
    ];

    # process.memory.usage is stored only for executables holding at least
    # minBytes after same-name aggregation (ADR-003 item 16). maxNames is the
    # per-host bound on distinct names (ADR-004), observed at deployment and
    # regulated at runtime from S4; no collector stage enforces it.
    process = {
      minBytes = 67108864;
      maxNames = 30;
    };

    # Store databases, one otlp_http exporter each (design D8).
    databases = [
      "fleet"
      "devloop"
      "agent"
    ];
  };
}
```

Run:

```bash
jj st --no-pager >/dev/null
nix eval --json .#lib.otelCollectorSchema --apply 's: { units = builtins.length s.systemdUnits; inherit (s) databases ownerAliases; }'
```

Expected: `{"databases":["fleet","devloop","agent"],"ownerAliases":{"cameron":"owner-1","janettesmith":"owner-2"},"units":23}`.

- [ ] **Step 5: Write the clan service and its two NixOS modules**

Create `modules/clan/services/otel-collector/flake-module.nix`:

```nix
# Fleet metrics collection as one clan service (ADR-003; design D8 to D10).
#
# Both roles' NixOS fragments merge into one services.opentelemetry-collector,
# because the NixOS module runs one collector per host. On magnetite, which
# holds both roles, the agent pipelines export to an in-process `forward`
# connector that the ingress pipeline receives from. The ingress converts
# exponential histograms while the store is below 1.3.0 (ADR-001 R1.2), routes
# on the `vanixiets.database` resource attribute, and writes each database
# through its own otlp_http exporter with a persistent queue, authenticating
# as the store's write-only `collector` user.
#
# The fragments are plain NixOS modules, flake.modules.nixos.otel-collector-
# agent and -ingress, so the container test imports them without clan; only
# the clan ingress role reads the collector password from clan vars.
#
# The agent also owns the failure notifier (ADR-009 item 11):
# observability-notify@.service posts once per failure episode to ntfy's
# fleet-alerts topic, guarded by a stamp per unit, and every unit listed in
# services.observability-notify.units gets OnFailure= and an ExecStopPost=
# hook that posts RESOLVED on the unit's next successful exit. ntfy has no
# authentication, so the notifier holds no credential.
#
# Build-time validation (nixpkgs' `otelcol-contrib validate`) runs before
# /run/credentials exists. basicauth's password_file is not opened by
# validation; the prometheus receiver does stat its credentials_file, so the
# one validateConfigOverrides entry replaces the zerotierone job with itself
# minus `authorization`, for validation only.
{ config, ... }:
let
  nixosModules = config.flake.modules.nixos;
  schema = config.flake.lib.otelCollectorSchema;

  stateDir = "/var/lib/opentelemetry-collector";
  credentialsDir = "/run/credentials/opentelemetry-collector.service";

  mib = n: n * 1024 * 1024;

  # Persistent queue per database: at least 24 h of fleet and under 512 MiB
  # in total (ADR-003 envelope), asserted by
  # checks.x86_64-linux.otel-collector-config.
  queueBytes = {
    fleet = mib 400;
    devloop = mib 48;
    agent = mib 48;
  };

  # Imported by both roles. `package` accepts a single definition, and the
  # shared key makes the module system load this module once on a machine
  # holding both roles. Every pipeline starts with this limiter (ADR-003
  # item 8; envelope 384 MiB under MemoryMax 512M).
  collectorCore = {
    key = "vanixiets#otel-collector-core";
    imports = [
      (
        { pkgs, ... }:
        {
          services.opentelemetry-collector = {
            enable = true;
            package = pkgs.opentelemetry-collector-contrib;
            settings.processors.memory_limiter = {
              check_interval = "1s";
              limit_mib = 384;
            };
          };
        }
      )
    ];
  };
in
{
  flake.modules.nixos.otel-collector-agent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.observability-notify;
      hostName = config.networking.hostName;
      stampDir = "/var/lib/observability-notify";
      ntfySend = lib.getExe pkgs.ntfy-send;

      # Runs as root (`+`) after every stop of a notified unit; a failed post
      # leaves the stamp for the next successful exit and never fails the unit.
      resolved = pkgs.writeShellScript "observability-notify-resolved" ''
        export PATH=${
          lib.makeBinPath [
            pkgs.curl
            pkgs.coreutils
          ]
        }:$PATH
        unit="$1"
        stamp="${stampDir}/$unit"
        if [ "''${SERVICE_RESULT:-}" = success ] && [ -e "$stamp" ]; then
          ${ntfySend} "RESOLVED $unit on ${hostName}" fleet-alerts && rm -f "$stamp"
        fi
        exit 0
      '';

      scrape = job: target: extra: {
        job_name = job;
        scrape_interval = "60s";
        static_configs = [ { targets = [ target ]; } ];
      } // extra;

      zerotierScrape = scrape "zerotierone" "127.0.0.1:9993" {
        authorization = {
          type = "Bearer";
          credentials_file = "${credentialsDir}/zerotier-metricstoken";
        };
        # Per-peer series carry node ids (ADR-003 item 20).
        metric_relabel_configs = [
          {
            source_labels = [ "__name__" ];
            regex = "zt_peer_.*";
            action = "drop";
          }
        ];
      };
    in
    {
      imports = [ collectorCore ];

      options.services.observability-notify.units = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          systemd.services attribute names (without `.service`) whose failure
          posts a notice to ntfy's fleet-alerts topic through
          observability-notify@.service, and whose next successful exit after
          a notice posts RESOLVED.
        '';
      };

      config = lib.mkMerge [
        {
          services.opentelemetry-collector = {
            settings = {
              processors = {
                "transform/omnigent-alias".metric_statements = lib.mapAttrsToList (
                  owner: alias:
                  ''set(resource.attributes["systemd.unit.name"], "omnigent-host-${alias}.service") where resource.attributes["systemd.unit.name"] == "omnigent-host-${owner}.service"''
                ) schema.ownerAliases;
                "resource/agent".attributes = [
                  {
                    key = "host.name";
                    value = hostName;
                    action = "upsert";
                  }
                  {
                    key = "vanixiets.database";
                    value = "fleet";
                    action = "upsert";
                  }
                ];
                # Compaction (empty keys) merges same-named processes before
                # the sum (ADR-003 item 16).
                "groupbyattrs/compact".keys = [ ];
                "metrics_transform/process".transforms = [
                  {
                    include = "process.memory.usage";
                    match_type = "strict";
                    action = "update";
                    operations = [
                      {
                        action = "aggregate_labels";
                        label_set = [ ];
                        aggregation_type = "sum";
                      }
                    ];
                  }
                ];
                "filter/process-min" = {
                  error_mode = "ignore";
                  metric_conditions = [
                    ''metric.name == "process.memory.usage" and datapoint.value_int < ${toString schema.process.minBytes}''
                  ];
                };
              };

              receivers = {
                "host_metrics/memory" = {
                  collection_interval = "60s";
                  scrapers = {
                    memory.metrics."system.linux.memory.available".enabled = true;
                    paging.metrics = {
                      "system.paging.usage".enabled = true;
                      "system.paging.operations".enabled = false;
                      "system.paging.faults".enabled = false;
                      "system.paging.utilization".enabled = false;
                    };
                  };
                };
                "host_metrics/process" = {
                  collection_interval = "60s";
                  scrapers.process = {
                    # DynamicUser cannot read other users' exe links or io.
                    mute_process_all_errors = true;
                    resource_attributes = {
                      "process.pid".enabled = false;
                      "process.parent_pid".enabled = false;
                      "process.command".enabled = false;
                      "process.command_line".enabled = false;
                      "process.executable.path".enabled = false;
                      "process.owner".enabled = false;
                    };
                    metrics = {
                      "process.memory.usage".enabled = true;
                      "process.cpu.time".enabled = false;
                      "process.disk.io".enabled = false;
                      "process.memory.virtual".enabled = false;
                    };
                  };
                };
                systemd = {
                  collection_interval = "60s";
                  scope = "system";
                  units = schema.systemdUnits;
                  metrics = {
                    "systemd.service.restarts".enabled = true;
                    "systemd.service.cpu.time".enabled = false;
                  };
                };
                prometheus.config.scrape_configs = [
                  (scrape "node" "127.0.0.1:9100" {
                    metric_relabel_configs = [
                      {
                        source_labels = [ "__name__" ];
                        regex = lib.concatStringsSep "|" schema.nodeExporterKeep;
                        action = "keep";
                      }
                    ];
                  })
                  (scrape "gitea" "127.0.0.1:3002" { })
                  (scrape "niks3" "127.0.0.1:5752" { })
                  (scrape "nixbot" "127.0.0.1:9180" { })
                  (scrape "greptimedb" "127.0.0.1:4000" { })
                ];
              };

              connectors.forward = { };

              service.pipelines = {
                "metrics/host" = {
                  receivers = [
                    "host_metrics/memory"
                    "systemd"
                    "prometheus"
                  ];
                  processors = [
                    "memory_limiter"
                    "transform/omnigent-alias"
                    "resource/agent"
                  ];
                  exporters = [ "forward" ];
                };
                "metrics/process" = {
                  receivers = [ "host_metrics/process" ];
                  processors = [
                    "memory_limiter"
                    "groupbyattrs/compact"
                    "metrics_transform/process"
                    "filter/process-min"
                    "resource/agent"
                  ];
                  exporters = [ "forward" ];
                };
              };
            };
          };

          services.prometheus.exporters.node = {
            enable = true;
            listenAddress = "127.0.0.1";
            openFirewall = false;
            extraFlags = [
              "--collector.disable-defaults"
              "--collector.zfs"
              "--collector.vmstat"
              "--collector.vmstat.fields=^oom_kill$"
            ];
          };

          services.observability-notify.units = [ "opentelemetry-collector" ];

          systemd.services = lib.mkMerge [
            (lib.genAttrs cfg.units (_: {
              unitConfig.OnFailure = [ "observability-notify@%n.service" ];
              serviceConfig.ExecStopPost = [ "-+${resolved} %n" ];
            }))
            {
              prometheus-node-exporter.serviceConfig.MemoryMax = "64M";

              "observability-notify@" = {
                description = "Post a failure notice for %i to ntfy";
                path = [ pkgs.curl ];
                serviceConfig = {
                  Type = "oneshot";
                  StateDirectory = "observability-notify";
                  # One post per failure episode: skip while the stamp exists.
                  ExecCondition = "${pkgs.coreutils}/bin/test ! -e ${stampDir}/%i";
                  ExecStart = ''${ntfySend} "FAILED %i on ${hostName}" fleet-alerts'';
                  ExecStartPost = "${pkgs.coreutils}/bin/touch ${stampDir}/%i";
                };
              };
            }
          ];
        }

        (lib.mkIf (config.services.nginx.enable && config.services.nginx.statusPage) {
          services.opentelemetry-collector.settings = {
            receivers.nginx = {
              endpoint = "http://127.0.0.1:80/nginx_status";
              collection_interval = "60s";
            };
            service.pipelines."metrics/host".receivers = [ "nginx" ];
          };
        })

        (lib.mkIf config.services.zerotierone.enable {
          # Explicit, so an upgrade past 1.16.0 (default off) keeps the
          # mesh-health signal (ADR-003 item 5).
          services.zerotierone.localConf.settings.enableMetrics = true;

          systemd.services.opentelemetry-collector = {
            after = [ "zerotierone.service" ];
            serviceConfig.LoadCredential = [
              "zerotier-metricstoken:/var/lib/zerotier-one/metricstoken.secret"
            ];
          };

          services.opentelemetry-collector = {
            settings = {
              receivers."prometheus/zerotier".config.scrape_configs = [ zerotierScrape ];
              service.pipelines."metrics/host".receivers = [ "prometheus/zerotier" ];
            };
            validateConfigOverrides = [
              "receivers::prometheus/zerotier::config::scrape_configs=${
                builtins.toJSON [ (builtins.removeAttrs zerotierScrape [ "authorization" ]) ]
              }"
            ];
          };
        })
      ];
    };

  flake.modules.nixos.otel-collector-ingress =
    { lib, ... }:
    {
      imports = [ collectorCore ];

      services.opentelemetry-collector = {
        settings = {
          extensions = {
            file_storage = {
              directory = "${stateDir}/queue";
              create_directory = true;
            };
            "basicauth/store".client_auth = {
              username = "collector";
              password_file = "${credentialsDir}/collector-password";
            };
          };

          processors = {
            # The store accepts explicit-bucket histograms only below 1.3.0
            # (ADR-001 R1.2); the bounds are Prometheus' default buckets.
            "transform/exphist".metric_statements = [
              "convert_exponential_histogram_to_histogram(\"upper\", [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]) where metric.type == METRIC_DATA_TYPE_EXPONENTIAL_HISTOGRAM"
            ];
            "resource/strip-database".attributes = [
              {
                key = "vanixiets.database";
                action = "delete";
              }
            ];
          };

          connectors.routing.table = map (db: {
            context = "resource";
            condition = ''attributes["vanixiets.database"] == "${db}"'';
            pipelines = [ "metrics/${db}" ];
          }) schema.databases;

          exporters = lib.listToAttrs (
            map (
              db:
              lib.nameValuePair "otlp_http/${db}" {
                endpoint = "http://127.0.0.1:4000/v1/otlp";
                headers = {
                  "x-greptime-db-name" = db;
                  "x-greptime-otlp-metric-promote-resource-attrs" = lib.concatStringsSep ";" schema.promotedResourceAttributes;
                };
                auth.authenticator = "basicauth/store";
                sending_queue = {
                  storage = "file_storage";
                  sizer = "bytes";
                  queue_size = queueBytes.${db};
                };
                # A persistent queue drops an item whose retries run out, so
                # retries never stop while the store is down.
                retry_on_failure = {
                  enabled = true;
                  max_interval = "60s";
                  max_elapsed_time = "0s";
                };
              }
            ) schema.databases
          );

          service = {
            extensions = [
              "file_storage"
              "basicauth/store"
            ];
            pipelines = {
              "metrics/ingress" = {
                receivers = [ "forward" ];
                processors = [
                  "memory_limiter"
                  "transform/exphist"
                ];
                exporters = [ "routing" ];
              };
            }
            // lib.listToAttrs (
              map (
                db:
                lib.nameValuePair "metrics/${db}" {
                  receivers = [ "routing" ];
                  processors = [ "resource/strip-database" ];
                  exporters = [ "otlp_http/${db}" ];
                }
              ) schema.databases
            );
          };
        };
      };

      # Killed after the evaluator (900) and the store (500), so it survives
      # the store's death and queues (A7:100,127).
      systemd.services.opentelemetry-collector.serviceConfig = {
        MemoryMax = "512M";
        OOMScoreAdjust = 300;
      };
    };

  clan.modules.otel-collector =
    { ... }:
    {
      _class = "clan.service";
      manifest = {
        name = "otel-collector";
        description = "Fleet metrics collection into the telemetry store";
        categories = [ "System" ];
        readme = ''
          OpenTelemetry collector for the fleet. `agent` collects the
          machine's host, process, unit and service metrics, runs
          node_exporter on loopback, and owns the observability-notify@
          failure notifier. `ingress` converts, routes and writes metrics
          into GreptimeDB on 127.0.0.1:4000, one otlp_http exporter per
          database with a persistent queue. On a machine holding both
          roles they share one collector, joined by a `forward` connector.
        '';
      };

      roles.agent = {
        description = "Collects the machine's own metrics and posts unit failures to ntfy";
        interface = { };
        perInstance =
          { ... }:
          {
            nixosModule.imports = [ nixosModules.otel-collector-agent ];
          };
      };

      roles.ingress = {
        description = "Writes collected metrics into the telemetry store";
        interface = { };
        perInstance =
          { ... }:
          {
            nixosModule =
              { config, ... }:
              {
                imports = [ nixosModules.otel-collector-ingress ];
                systemd.services.opentelemetry-collector.serviceConfig.LoadCredential = [
                  "collector-password:${config.clan.core.vars.generators.greptimedb-users.files.collector-password.path}"
                ];
              };
          };
      };
    };
}
```

- [ ] **Step 6: Assign both roles to magnetite**

Create `modules/clan/inventory/services/otel-collector.nix`:

```nix
# Collector roles. magnetite runs both in one collector process: its agent
# pipelines feed the ingress in-process (design D8). Other hosts join the
# agent role in S4, with the ZeroTier ingress listener.
{
  clan.inventory.instances.otel-collector = {
    module = {
      name = "otel-collector";
      input = "self";
    };

    roles.agent.machines.magnetite = { };
    roles.ingress.machines.magnetite = { };
  };
}
```

Run:

```bash
jj st --no-pager >/dev/null
nix eval --json .#clan.inventory.instances.otel-collector.roles --apply 'r: { agent = builtins.attrNames r.agent.machines; ingress = builtins.attrNames r.ingress.machines; }'
```

Expected: `{"agent":["magnetite"],"ingress":["magnetite"]}`.

- [ ] **Step 7: Add nixbot's loopback metrics server**

In `modules/nixos/nixbot.nix`, after the block ending at line 219 (`config.services.nginx.virtualHosts.${config.services.nixbot.domain};`), insert:

```nix

      # Loopback-only scrape endpoint for magnetite's collector (design D9).
      # nixbot binds no TCP port, and a scrape through the public vhost's
      # /metrics would not arrive from loopback.
      services.nginx.virtualHosts."nixbot-metrics-loopback" = {
        listen = [
          {
            addr = "127.0.0.1";
            port = 9180;
          }
        ];
        locations."/metrics".proxyPass = "http://unix:/run/nixbot/web.sock";
      };
```

Run:

```bash
nix eval --json .#nixosConfigurations.magnetite.config.services.nginx.virtualHosts.nixbot-metrics-loopback --apply 'v: { listen = map (l: "${l.addr}:${toString l.port}") v.listen; proxy = v.locations."/metrics".proxyPass; }'
```

Expected: `{"listen":["127.0.0.1:9180"],"proxy":"http://unix:/run/nixbot/web.sock"}`.

- [ ] **Step 8: List magnetite's notified units**

In `modules/machines/nixos/magnetite/default.nix`, immediately before the comment line `      # Raise nix daemon free-space thresholds for a build host.`, insert:

```nix
      # Units whose failure posts to ntfy's fleet-alerts topic and whose
      # recovery posts RESOLVED (design "Failure path"). The otel-collector
      # agent role adds opentelemetry-collector itself and applies the wiring,
      # so greptimedb.nix never references the notifier.
      services.observability-notify.units = [
        "greptimedb"
        "greptimedb-schema"
        "zfs-assert-root-docker-noautosnap"
        "zfs-assert-root-greptimedb-noautosnap"
        "zfs-assert-root-nix-noautosnap"
        "zfs-assert-root-podman-noautosnap"
        "zfs-set-root-greptimedb-quota"
        "zfs-set-root-greptimedb-reservation"
        "zfs-set-root-home-reservation"
        "zfs-set-root-nix-quota"
        "zfs-set-root-nixos-reservation"
      ];

```

In the same file, inside Task 2's `greptimedb-users` generator, replace the line

```nix
        files.collector-password.mode = "0400";
```

with

```nix
        files.collector-password = {
          mode = "0400";
          restartUnits = [ "opentelemetry-collector.service" ];
        };
```

The collector reads the password from its `LoadCredential` copy, taken at unit start, so a rotated password takes effect only after a restart; this task adds that unit, so it adds the restart with it.

- [ ] **Step 9: Confirm the evaluated wiring**

Run:

```bash
nix eval --json .#nixosConfigurations.magnetite.config --apply 'c: { units = c.services.observability-notify.units; onFailure = map (u: c.systemd.services.${u}.unitConfig.OnFailure) c.services.observability-notify.units; hooks = map (u: c.systemd.services.${u}.serviceConfig.ExecStopPost) [ "greptimedb" "opentelemetry-collector" ]; }' 2>&1 | tee logs/t3-notify-wiring-$(date +%Y%m%d-%H%M%S).log
nix eval --raw '.#nixosConfigurations.magnetite.config.systemd.services."observability-notify@".serviceConfig.ExecStart'
nix eval --json .#nixosConfigurations.magnetite.config.services.prometheus.exporters.node --apply 'n: { inherit (n) listenAddress openFirewall extraFlags; }'
nix eval --json .#nixosConfigurations.magnetite.config.services.zerotierone.localConf.settings.enableMetrics
nix eval --json .#nixosConfigurations.magnetite.config.systemd.services.opentelemetry-collector.serviceConfig --apply 's: { inherit (s) LoadCredential MemoryMax OOMScoreAdjust; }'
nix eval --json .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.collector-password.restartUnits
```

Expected:
`units` holds the eleven names above plus `"opentelemetry-collector"`, and `onFailure` is twelve copies of `["observability-notify@%n.service"]`;
each `hooks` entry is a list ending in `"-+/nix/store/<hash>-observability-notify-resolved %n"`;
`ExecStart` is `/nix/store/<hash>-ntfy-send-<version>/bin/ntfy-send "FAILED %i on magnetite" fleet-alerts`;
the exporter shows `"listenAddress":"127.0.0.1"`, `"openFirewall":false` and the four flags;
`enableMetrics` is `true`;
`LoadCredential` lists `collector-password:<path>`, where `<path>` is what `nix eval --raw .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.collector-password.path` prints, and `zerotier-metricstoken:/var/lib/zerotier-one/metricstoken.secret`, with `"MemoryMax":"512M"` and `"OOMScoreAdjust":300`.
`restartUnits` for `collector-password` is `["opentelemetry-collector.service"]` (Task 2 left it `[]`).

- [ ] **Step 10: Show build-time validation passes without a credential placeholder**

Run:

```bash
nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.validateConfigOverrides --apply 'map (o: builtins.head (builtins.match "([^=]*)=.*" o))'
nix build --print-out-paths .#nixosConfigurations.magnetite.config.system.build.opentelemetryCollectorConfig 2>&1 | tee logs/t3-otelcol-validate-$(date +%Y%m%d-%H%M%S).log | tail -n 5
rg -n 'password_file|credentials_file|queue_size' "$(nix build --print-out-paths .#nixosConfigurations.magnetite.config.system.build.opentelemetryCollectorConfig)"
```

Expected: the overrides list is exactly `["receivers::prometheus/zerotier::config::scrape_configs"]`, so no `basicauth` placeholder is passed;
the build prints one `/nix/store/<hash>-config.yaml` path, which the nixpkgs module produces only after `otelcol-contrib validate` exits 0;
`rg` shows `password_file: /run/credentials/opentelemetry-collector.service/collector-password`, `credentials_file: /run/credentials/opentelemetry-collector.service/zerotier-metricstoken` and the three `queue_size` values `419430400`, `50331648`, `50331648` in the delivered file.
If validation rejects a key, the build log names it; fix the key in `flake-module.nix` against the 0.155.0 source cited at the top of this task, never by adding an override.
Build-time validation proves only that the configuration's keys and values are accepted; the first runtime proof of the `file_storage` queue with the `bytes` sizer, the `metrics_transform` aggregation with an empty `label_set`, and the zerotierone validation override is Task 5's container test.

- [ ] **Step 11: Run the checks to see them pass**

Run:

```bash
nix build .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/t3-otel-collector-config-green-$(date +%Y%m%d-%H%M%S).log | tail -n 20
nix build .#checks.x86_64-linux.greptimedb-envelope 2>&1 | tee logs/t3-greptimedb-envelope-green-$(date +%Y%m%d-%H%M%S).log | tail -n 20
nix build .#checks.x86_64-linux.nixos-magnetite 2>&1 | tee logs/t3-nixos-magnetite-$(date +%Y%m%d-%H%M%S).log | tail -n 20
```

Expected: all three exit 0.
`otel-collector-config` passing means magnetite's configuration has no R3.1 or R1.2 failure, all thirteen evaluation mutants fail, the delivered configuration validated, and the validator rejected the unknown-key mutant.
`greptimedb-envelope` passing means `collector-password` is loaded only by `opentelemetry-collector`.

- [ ] **Step 12: Show the regulator can fail (converse once)**

In `modules/checks/otel-collector-config.nix`, delete the line `(check "R3.1: fleet queue below 24 h" (` and the two lines that follow it (through its closing `))`), then run:

```bash
nix build .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/t3-otel-collector-config-converse-$(date +%Y%m%d-%H%M%S).log | tail -n 5
```

Expected: evaluation fails with `otel-collector-config accepted a mutant: ["queueUnder24h"]`.
Restore the three lines exactly, rerun the same command, and expect exit 0.

- [ ] **Step 13: Tick the task items**

In `openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md`, change `- [ ]` to `- [x]` on the lines of items 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7 and 4.4.

Run:

```bash
rg -c '^- \[x\] (3\.[1-7]|4\.4) ' openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md
```

Expected: `8`.

- [ ] **Step 14: Commit**

Run:

```bash
jj new --no-edit -r main@origin -m 'feat(observability): collect magnetite metrics into greptimedb with failure notices'
```

Expected: `Created new commit <change-id> ...`; note `<change-id>` as `T3`.

Run:

```bash
jj squash --from @ --into T3 --keep-emptied --use-destination-message -- \
  modules/checks/otel-collector-config.nix \
  modules/checks/greptimedb-envelope.nix \
  modules/clan/services/otel-collector/schema.nix \
  modules/clan/services/otel-collector/flake-module.nix \
  modules/clan/inventory/services/otel-collector.nix \
  modules/nixos/nixbot.nix \
  modules/machines/nixos/magnetite/default.nix \
  openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md
jj log -r T3 --no-graph -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"' --stat
```

Expected: `T3` shows the eight files.
The orchestrator rebases the development join onto `T3`, pushes, and owns pull request 3; do not push.

---

### Task 4: Runtime envelope

**Files:**
- Create: `modules/lib/greptimedb-envelope.nix` (`flake.lib.greptimedbSql`, `flake.lib.greptimedbEnvelope`)
- Modify: `modules/nixos/greptimedb.nix` (outer arguments; `let` bindings; `greptimedb-envelope.service`, `greptimedb-envelope.timer`, one assertion)
- Modify: `modules/machines/nixos/magnetite/default.nix` (envelope credential and host environment; `greptimedb-envelope` in `services.observability-notify.units`)
- Modify: `modules/checks/greptimedb-envelope.nix` (R8.2 holder literal; the 5.2 query rehearsal)
- Modify: `modules/checks/otel-collector-config.nix` (`notifiedUnits` gains `greptimedb-envelope`, so R3.1's failure-wiring clause covers 13 units)
- Modify: `openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md` (tick 5.1 and 5.2)

**Interfaces:**
- Consumes (Task 2): `flake.modules.nixos.greptimedb` shaped `{ ... }: { flake.modules.nixos.greptimedb = { config, lib, pkgs, ... }: let cfg = config.services.greptimedb; … in { options…; config = lib.mkIf cfg.enable { …; assertions = [ … ]; … }; }; }`, referencing no clan vars; `cfg.settings.http.addr = "127.0.0.1:4000"`; `cfg.databases` (`fleet`, `devloop`, `agent`); `greptimedb.service` with `serviceConfig.MemoryHigh = "3G"` and an `ExecStartPre` that writes the sha256 of `$CREDENTIALS_DIRECTORY/users` to `/run/greptimedb/loaded-users.sha256` (`0444`, `RuntimeDirectory = "greptimedb"`, mode `0755`); generator `greptimedb-users` files `regulator-password` (secret, `0400`, no `restartUnits`) and `users-sha256` (`secret = false`, the hex sha256 of `users` plus a newline); in magnetite's module `let` block the binding `greptimedbDataset = { name = "zroot/root/greptimedb"; mountpoint = "/var/lib/greptimedb"; quota = "16G"; reservation = "12G"; }`, which the three ZFS oneshots apply; in `modules/checks/greptimedb-envelope.nix` the `let` binding `credentialHolders` with the line `regulator-password = [ ];`, and the check's final `pkgs.runCommand "greptimedb-envelope" { … } '' … touch "$out" ''`.
- Consumes (Task 3): `services.observability-notify.units` in `modules/machines/nixos/magnetite/default.nix` (systemd service attribute names without `.service`, sorted, the agent role adding `opentelemetry-collector` itself); the role sets `unitConfig.OnFailure = [ "observability-notify@%n.service" ]` and the `RESOLVED` `ExecStopPost=` on every listed unit; in `modules/checks/otel-collector-config.nix` the `let` binding `notifiedUnits`, a sorted literal of 12 names.
- Produces: `flake.lib.greptimedbSql pkgs { url; user; }`, a `writeShellApplication` named `greptimedb-sql` taking one SQL statement, reading `$CREDENTIALS_DIRECTORY/<user>-password`, printing the rows of the single records result as TSV (`NULL` for null), exiting 1 on a transport failure, a non-200 answer, a body that is not one records result, or zero rows.
- Produces: `flake.lib.greptimedbEnvelope pkgs { url; databases; unit; loadedUsersHashFile; zfsPackage; systemdPackage; }`, a `writeShellApplication` named `greptimedb-envelope`; each failed property prints `FAIL <id>: …` to stderr, the run exits 1 if any failed, and a clean run prints `greptimedb-envelope: all checks passed`.
- Produces: units `greptimedb-envelope.service` (oneshot, `DynamicUser`, `LoadCredential=regulator-password`) and `greptimedb-envelope.timer` (hourly).
- Produces: `Environment=` names `GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES` (`3221225472`, from `MemoryHigh`), `GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT` (`80`), `GREPTIMEDB_ENVELOPE_SST_MAX_BYTES` (`53687091200`), set by the module; `GREPTIMEDB_ENVELOPE_DATASET`, `GREPTIMEDB_ENVELOPE_QUOTA_BYTES` (`17179869184`), `GREPTIMEDB_ENVELOPE_RESERVATION_BYTES` (`12884901888`), `GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE`, set by magnetite. Task 6 (8.6) forces R7.2 with a runtime drop-in `Environment=GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES=1` and matches `FAIL R7.2: memory.peak`.

Facts this task rests on, each confirmed against the cited source:

- `/v1/sql` takes `sql` from the query string or a form body, on GET or POST (GreptimeDB v1.2.1 `src/servers/src/http.rs:1310`, `src/servers/src/http/handler.rs:118-140`).
- A success is `GreptimedbV1Response`, `{"output":[{"records":{"schema":{"column_schemas":[…]},"rows":[…],"total_rows":N}}],"execution_time_ms":N}` (`src/servers/src/http/result/greptime_result_v1.rs:30-39`, `src/servers/src/http.rs:331-400`); an empty result keeps that shape with `"rows":[]` and `"total_rows":0` (`tests-integration/tests/http.rs:576-579`).
- A failure is `ErrorResponse`, `{"code":N,"error":"…","execution_time_ms":N}` (`src/servers/src/http/result/error_result.rs:25-30`); a missing table is code 4001 `TableNotFound` (`src/common/error/src/status_code.rs:66`), HTTP 400 (`src/servers/src/error.rs:933-957`), message `Failed to plan SQL: Table not found: <catalog>.<schema>.<table>` (`tests/cases/standalone/common/catalog/schema.result:135`).
- `/ready` and `/health` are outside `/v1` and need no credential (`src/servers/src/http.rs:166-171,943-953`).
- `information_schema.region_statistics` has `region_id` and `sst_size` (`src/catalog/src/system_schema/information_schema/region_statistics.rs:39-53`); `information_schema.tables` has `table_schema`, `table_name`, `table_type`, `create_options` (`…/information_schema/tables.rs:49-72`), and `create_options` renders table options as space-separated `key=value`, with `ttl=` only when the table sets its own (`src/table/src/requests.rs:219-240`).
- Auto-created tables do not inherit the database's TTL (`src/operator/src/insert.rs:1193-1263`, `src/operator/src/statement/ddl.rs:288-289`); the legacy `sst_format` value is `primary_key` (`src/mito2/src/sst.rs:60-68`; ADR-006:62,134).
- systemd 261.3, the pinned version, logs `MESSAGE_ID=fe6faa94e7774663a0da52717891d8ef` with `UNIT=<unit>` when the kernel OOM killer kills in a unit (`src/core/cgroup.c:3099-3102`, `src/systemd/sd-messages.h:198-199`); `NRestarts` counts automatic restarts and resets on any explicit start (`src/core/service.c:3015,3437-3439`).
- On magnetite, `/dev/zfs` is mode `0666` and `zfs get -Hp` works unprivileged; clan vars secrets sit under `/run/secrets/vars/per-machine/magnetite/<generator>/` behind `0751` directories, and sops-nix rewrites them, with a fresh mtime, on every activation, which is why R7.4 compares hashes rather than mtimes.
- `memory.events` and `memory.peak` belong to the unit's cgroup and restart from zero with each invocation, so R7.2 keeps a baseline keyed by `InvocationID` and, across invocations, reads the journal and `NRestarts` instead of the counters.

- [ ] **Step 1: Write the failing query rehearsal and the R8.2 holder**

In `modules/checks/greptimedb-envelope.nix`, change the `regulator-password` line of `credentialHolders` from `regulator-password = [ ];` to:

```nix
        regulator-password = [ "greptimedb-envelope" ];
```

In the same file's `perSystem` `let` block, after `credentialHolders`, add:

```nix
      # Runtime regulators treat absent evidence as failure (5.2; F3). The
      # envelope's every query goes through self.lib.greptimedbSql, so this
      # builds that function the way modules/nixos/greptimedb.nix does and
      # runs it against recorded GreptimeDB v1.2.1 /v1/sql answers served by a
      # loopback stub (curl reaches it through http_proxy, as in
      # omnigraph-readiness-rehearsal.nix). Shapes: GreptimedbV1Response and
      # HttpRecordsOutput (src/servers/src/http/result/greptime_result_v1.rs:30-39,
      # src/servers/src/http.rs:331-400), ErrorResponse
      # (src/servers/src/http/result/error_result.rs:25-30); TableNotFound is
      # code 4001 answered as HTTP 400 (src/servers/src/error.rs:933-957), with
      # the message tests/cases/standalone/common/catalog/schema.result:135
      # records. The renamed-table row is the mutant: the regulator queries a
      # table that does not exist and must fail.
      sqlHelper = self.lib.greptimedbSql pkgs {
        url = "http://greptimedb.rehearsal.invalid:4000";
        user = "regulator";
      };
      regionColumns = [
        {
          name = "region_id";
          data_type = "UInt64";
        }
        {
          name = "sst_size";
          data_type = "UInt64";
        }
      ];
      records = rows: {
        output = [
          {
            records = {
              schema.column_schemas = regionColumns;
              inherit rows;
              total_rows = builtins.length rows;
            };
          }
        ];
        execution_time_ms = 2;
      };
      regionQuery = "SELECT region_id, sst_size FROM information_schema.region_statistics";
      renamedRegionQuery = "SELECT region_id, sst_size FROM information_schema.region_statistic";

      sqlStub = pkgs.writeText "greptimedb-sql-stub.py" ''
        import base64, sys
        from http.server import BaseHTTPRequestHandler, HTTPServer
        from urllib.parse import parse_qs, urlsplit

        port_path, log_path, status, reply = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]

        class Handler(BaseHTTPRequestHandler):
            def answer(self):
                length = int(self.headers.get("Content-Length", "0"))
                form = parse_qs(self.rfile.read(length).decode())
                auth = self.headers.get("Authorization", "")
                user = "-"
                if auth.startswith("Basic "):
                    user = base64.b64decode(auth[6:]).decode().split(":", 1)[0]
                with open(log_path, "a") as log:
                    log.write(" ".join([self.command, urlsplit(self.path).path, user, form.get("sql", ["-"])[0]]) + "\n")
                data = reply.encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            do_GET = answer
            do_POST = answer

            def log_message(self, *args):
                pass

        server = HTTPServer(("127.0.0.1", 0), Handler)
        with open(port_path, "w") as f:
            f.write(str(server.server_port))
        server.serve_forever()
      '';

      sqlRow =
        {
          name,
          sql,
          httpStatus,
          reply,
          exit,
          expect,
        }:
        ''
          echo "--- ${name}"
          rm -f "$TMPDIR/port" "$TMPDIR/requests" "$TMPDIR/output"
          touch "$TMPDIR/requests"
          python3 ${sqlStub} "$TMPDIR/port" "$TMPDIR/requests" ${toString httpStatus} ${lib.escapeShellArg (builtins.toJSON reply)} &
          stub_pid=$!
          for _ in $(seq 100); do [ -s "$TMPDIR/port" ] && break; sleep 0.1; done
          [ -s "$TMPDIR/port" ] || fail "sql stub did not start"
          code=0
          env -u no_proxy -u NO_PROXY -u HTTP_PROXY \
            CREDENTIALS_DIRECTORY="$TMPDIR/credentials" \
            http_proxy="http://127.0.0.1:$(cat "$TMPDIR/port")" \
            ${lib.getExe sqlHelper} ${lib.escapeShellArg sql} > "$TMPDIR/output" 2>&1 || code=$?
          kill "$stub_pid"
          wait "$stub_pid" || true
          stub_pid=
          cat "$TMPDIR/output"
          [ "$code" = ${toString exit} ] || fail "${name}: exit status $code, expected ${toString exit}"
          ${lib.concatMapStrings (line: ''
            grep -qF -- ${lib.escapeShellArg line} "$TMPDIR/output" \
              || fail ${lib.escapeShellArg "${name}: output lacks: ${line}"}
          '') expect}
          [ "$(cat "$TMPDIR/requests")" = ${lib.escapeShellArg "POST /v1/sql regulator ${sql}"} ] \
            || fail "${name}: stub saw: $(cat "$TMPDIR/requests")"
        '';

      sqlRows = [
        {
          name = "a records result with rows passes and prints them as TSV";
          sql = regionQuery;
          httpStatus = 200;
          reply = records [
            [
              4398046511104
              1048576
            ]
          ];
          exit = 0;
          expect = [ "4398046511104\t1048576" ];
        }
        {
          name = "an empty records result fails";
          sql = regionQuery;
          httpStatus = 200;
          reply = records [ ];
          exit = 1;
          expect = [ "greptimedb-sql: empty result: ${regionQuery}" ];
        }
        {
          name = "a renamed table fails on TableNotFound";
          sql = renamedRegionQuery;
          httpStatus = 400;
          reply = {
            code = 4001;
            error = "Failed to plan SQL: Table not found: greptime.information_schema.region_statistic";
            execution_time_ms = 0;
          };
          exit = 1;
          expect = [ "greptimedb-sql: HTTP 400: 4001 Failed to plan SQL: Table not found" ];
        }
      ];

      greptimedbSqlRehearsal =
        pkgs.runCommand "greptimedb-sql-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.python3
            ];
            meta.description = "behavioural check: the envelope's SQL helper fails on an empty result and on a missing table";
          }
          ''
            set -euo pipefail
            stub_pid=
            trap '[ -z "$stub_pid" ] || kill "$stub_pid" 2>/dev/null || true' EXIT
            fail() {
              echo "FAIL: $*" >&2
              exit 1
            }
            mkdir "$TMPDIR/credentials"
            printf '%s' 00112233445566778899aabbccddeeff > "$TMPDIR/credentials/regulator-password"

            ${lib.concatMapStrings sqlRow sqlRows}
            touch "$out"
          '';
```

In the check's final `pkgs.runCommand "greptimedb-envelope"` script, insert immediately before its `touch "$out"` line:

```bash
              # 5.2: the envelope's SQL helper fails on absent evidence.
              test -e ${greptimedbSqlRehearsal}
```

- [ ] **Step 2: Write the failing R3.1 wiring entry**

In `modules/checks/otel-collector-config.nix`, in the `notifiedUnits` literal, insert after the `"greptimedb"` line:

```nix
        "greptimedb-envelope"
```

The literal now holds 13 names in `lib.naturalSort` order (`"greptimedb"`, `"greptimedb-envelope"`, `"greptimedb-schema"`, …).

- [ ] **Step 3: Run both checks to verify they fail**

Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.greptimedb-envelope 2>&1 | tee logs/t4-envelope-red-$(date +%Y%m%d-%H%M%S).log
nix build .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/t4-otel-red-$(date +%Y%m%d-%H%M%S).log
```

Expected: both fail at evaluation.
`greptimedb-envelope` fails its real-configuration assertion, whose failure list names the credential-holder clause, because no unit on magnetite loads `regulator-password` yet.
`otel-collector-config` fails its failure-wiring clause, because `services.observability-notify.units` lacks `greptimedb-envelope` and the unit does not exist.

- [ ] **Step 4: Create the envelope library**

Create `modules/lib/greptimedb-envelope.nix`:

```nix
# The telemetry store's hourly runtime envelope (design D12) and the SQL
# helper its every query goes through.
#
# greptimedbSql posts one statement to GreptimeDB's /v1/sql as `user`,
# reading the password from $CREDENTIALS_DIRECTORY/<user>-password and
# passing it to curl on stdin so it never appears in argv, and prints the
# rows of the one records result as TSV with NULL for null. It exits 1 on a
# transport failure, on any answer but 200 (a missing table is HTTP 400 with
# code 4001 TableNotFound), on a body that is not exactly one records
# result, and on zero rows: a regulator query that matches nothing fails
# instead of passing vacuously (F3). modules/checks/greptimedb-envelope.nix
# runs this function's output against recorded v1.2.1 answers.
#
# greptimedbEnvelope is greptimedb-envelope.service's ExecStart. It reports
# every failed property as one `FAIL <id>: ...` line on stderr and exits 1
# if any failed:
#
# - R6.4 readiness: GET <url>/ready answers 200.
# - R6.2: information_schema.region_statistics reports sst_size for at least
#   one region, and the sum is under GREPTIMEDB_ENVELOPE_SST_MAX_BYTES.
# - R6.3 and per-table retention: the base tables of `databases` exist, none
#   sets sst_format=primary_key (the legacy format) and none sets a ttl of
#   its own, which would override its database's (F1).
# - R7.2: the unit cgroup's memory.peak is under
#   GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES; memory.events oom_kill and max
#   have not risen since the last run of the same invocation. Both files
#   restart from zero with each invocation, so across invocations the run
#   instead fails if systemd logged a kernel OOM kill in the unit since the
#   last run, or if NRestarts rose (an automatic restart). The baseline is
#   rewritten on every run, so one rise fails one run. The first run only
#   records a baseline.
# - R7.3: the dataset's quota and reservation equal
#   GREPTIMEDB_ENVELOPE_{QUOTA,RESERVATION}_BYTES and used space is under
#   GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT of the quota.
# - R7.4: the sha256 the running store recorded for the users file it loaded
#   (`loadedUsersHashFile`) equals the deployed users file's public sha256
#   (GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE). sops-nix rewrites every secret,
#   with a new mtime, on each activation while restartUnits restarts only on
#   a changed value, so a hash comparison is the one that holds.
#
# Thresholds and host facts come from the environment so a runtime drop-in
# can force a failure (tasks.md 8.6).
{ lib, ... }:
let
  greptimedbSql =
    pkgs:
    { url, user }:
    pkgs.writeShellApplication {
      name = "greptimedb-sql";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ];
      text = ''
        if [ "$#" -ne 1 ]; then
          echo "usage: greptimedb-sql SQL" >&2
          exit 2
        fi
        sql=$1
        password_file="''${CREDENTIALS_DIRECTORY:?CREDENTIALS_DIRECTORY is unset}/${user}-password"
        body=$(mktemp)
        trap 'rm -f "$body"' EXIT
        if ! status=$(printf 'user = "%s:%s"\n' ${lib.escapeShellArg user} "$(< "$password_file")" \
          | curl --config - --silent --show-error --max-time 30 \
              --output "$body" --write-out '%{http_code}' \
              --data-urlencode "sql=$sql" ${lib.escapeShellArg "${url}/v1/sql"}); then
          printf 'greptimedb-sql: request failed: %s\n' "$sql" >&2
          exit 1
        fi
        if [ "$status" != 200 ]; then
          printf 'greptimedb-sql: HTTP %s: %s: %s\n' "$status" \
            "$(jq -r '"\(.code) \(.error)"' "$body" 2>/dev/null || cat "$body")" "$sql" >&2
          exit 1
        fi
        if ! jq -e '(.output | length) == 1 and (.output[0].records.rows | type) == "array"' "$body" > /dev/null; then
          printf 'greptimedb-sql: not one records result: %s: %s\n' "$sql" "$(cat "$body")" >&2
          exit 1
        fi
        if jq -e '(.output[0].records.rows | length) == 0' "$body" > /dev/null; then
          printf 'greptimedb-sql: empty result: %s\n' "$sql" >&2
          exit 1
        fi
        jq -r '.output[0].records.rows[] | map(if . == null then "NULL" else tostring end) | @tsv' "$body"
      '';
    };

  # systemd 261.3 src/systemd/sd-messages.h:198-199, logged with UNIT= by
  # src/core/cgroup.c:3099-3102 when the kernel OOM killer kills in a unit.
  unitOutOfMemoryMessageId = "fe6faa94e7774663a0da52717891d8ef";

  greptimedbEnvelope =
    pkgs:
    {
      url,
      databases,
      unit,
      loadedUsersHashFile,
      zfsPackage,
      systemdPackage,
    }:
    let
      sql = greptimedbSql pkgs {
        inherit url;
        user = "regulator";
      };
      schemaList = lib.concatMapStringsSep ", " (db: "'${db}'") databases;
    in
    pkgs.writeShellApplication {
      name = "greptimedb-envelope";
      runtimeInputs = [
        sql
        pkgs.coreutils
        pkgs.curl
        pkgs.gawk
        pkgs.gnugrep
        pkgs.jq
        zfsPackage
        systemdPackage
      ];
      text = ''
        : "''${GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES:?}"
        : "''${GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT:?}"
        : "''${GREPTIMEDB_ENVELOPE_SST_MAX_BYTES:?}"
        : "''${GREPTIMEDB_ENVELOPE_DATASET:?}"
        : "''${GREPTIMEDB_ENVELOPE_QUOTA_BYTES:?}"
        : "''${GREPTIMEDB_ENVELOPE_RESERVATION_BYTES:?}"
        : "''${GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE:?}"
        : "''${STATE_DIRECTORY:?}"

        failed=0
        fail() {
          printf 'FAIL %s\n' "$*" >&2
          failed=1
        }
        field() {
          awk -v key="$1" '$1 == key { print $2 }'
        }

        # R6.4 readiness
        if ! curl --fail --silent --show-error --max-time 10 --output /dev/null ${lib.escapeShellArg "${url}/ready"}; then
          fail "R6.4: ${url}/ready did not answer 200"
        fi

        # R6.2
        if regions=$(greptimedb-sql 'SELECT region_id, sst_size FROM information_schema.region_statistics'); then
          read -r reported sst_bytes < <(awk -F '\t' '$2 != "NULL" { n++; s += $2 } END { printf "%d %.0f\n", n, s }' <<< "$regions")
          if [ "$reported" -eq 0 ]; then
            fail "R6.2: no region in information_schema.region_statistics reports sst_size"
          elif [ "$sst_bytes" -ge "$GREPTIMEDB_ENVELOPE_SST_MAX_BYTES" ]; then
            fail "R6.2: summed sst_size $sst_bytes >= GREPTIMEDB_ENVELOPE_SST_MAX_BYTES $GREPTIMEDB_ENVELOPE_SST_MAX_BYTES"
          fi
        else
          fail "R6.2: information_schema.region_statistics gave no rows"
        fi

        # R6.3 and per-table retention
        if tables=$(greptimedb-sql "SELECT table_schema, table_name, create_options FROM information_schema.tables WHERE table_schema IN (${schemaList}) AND table_type = 'BASE TABLE'"); then
          while IFS=$'\t' read -r schema table options; do
            if [[ " $options " == *" sst_format=primary_key "* ]]; then
              fail "R6.3: $schema.$table uses the legacy sst_format=primary_key"
            fi
            if [[ " $options " == *" ttl="* ]]; then
              fail "TTL: $schema.$table sets a ttl of its own ($options), overriding its database's"
            fi
          done <<< "$tables"
        else
          fail "R6.3: information_schema.tables gave no base table in ${schemaList}"
        fi

        # R7.2
        cgroup=/sys/fs/cgroup/system.slice/${unit}
        if ! peak=$(< "$cgroup/memory.peak"); then
          fail "R7.2: cannot read $cgroup/memory.peak"
        elif [ "$peak" -ge "$GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES" ]; then
          fail "R7.2: memory.peak $peak >= GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES $GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES"
        fi
        oom_kill=$(field oom_kill < "$cgroup/memory.events" || true)
        max=$(field max < "$cgroup/memory.events" || true)
        invocation=$(systemctl show --property=InvocationID --value ${unit} || true)
        nrestarts=$(systemctl show --property=NRestarts --value ${unit} || true)
        now=$(date +%s)
        if [ -z "$oom_kill" ] || [ -z "$max" ]; then
          fail "R7.2: $cgroup/memory.events lacks oom_kill or max"
        elif [ -z "$invocation" ] || [ -z "$nrestarts" ]; then
          fail "R7.2: ${unit} has no current invocation"
        else
          baseline="$STATE_DIRECTORY/memory-baseline"
          if [ -s "$baseline" ]; then
            read -r base_invocation base_oom_kill base_max base_nrestarts base_time < "$baseline"
            if [ "$invocation" = "$base_invocation" ]; then
              if [ "$oom_kill" -gt "$base_oom_kill" ]; then
                fail "R7.2: memory.events oom_kill rose from $base_oom_kill to $oom_kill"
              fi
              if [ "$max" -gt "$base_max" ]; then
                fail "R7.2: memory.events max rose from $base_max to $max"
              fi
            else
              # systemd logged the new invocation's start with UNIT=, so an
              # empty answer means the journal is unreadable, not quiet.
              if ! ids=$(journalctl --quiet --since "@$base_time" --output=json --output-fields=MESSAGE_ID UNIT=${unit} | jq -r '.MESSAGE_ID // "-"') || [ -z "$ids" ]; then
                fail "R7.2: no journal entries for ${unit} since @$base_time; the journal is unreadable"
              elif grep -qx ${unitOutOfMemoryMessageId} <<< "$ids"; then
                fail "R7.2: the kernel OOM killer killed processes in ${unit} since @$base_time"
              fi
              if [ "$nrestarts" -gt "$base_nrestarts" ]; then
                fail "R7.2: ${unit} restarted automatically since @$base_time (NRestarts $base_nrestarts -> $nrestarts)"
              fi
            fi
          fi
          printf '%s %s %s %s %s\n' "$invocation" "$oom_kill" "$max" "$nrestarts" "$now" > "$baseline"
        fi

        # R7.3
        if ! props=$(zfs get -Hp -o property,value used,quota,reservation "$GREPTIMEDB_ENVELOPE_DATASET"); then
          fail "R7.3: zfs get failed for $GREPTIMEDB_ENVELOPE_DATASET"
        else
          used=$(field used <<< "$props")
          quota=$(field quota <<< "$props")
          reservation=$(field reservation <<< "$props")
          if [ -z "$used" ] || [ -z "$quota" ] || [ -z "$reservation" ]; then
            fail "R7.3: zfs get answered without used, quota or reservation: $props"
          else
            if [ "$quota" != "$GREPTIMEDB_ENVELOPE_QUOTA_BYTES" ]; then
              fail "R7.3: quota $quota != GREPTIMEDB_ENVELOPE_QUOTA_BYTES $GREPTIMEDB_ENVELOPE_QUOTA_BYTES"
            fi
            if [ "$reservation" != "$GREPTIMEDB_ENVELOPE_RESERVATION_BYTES" ]; then
              fail "R7.3: reservation $reservation != GREPTIMEDB_ENVELOPE_RESERVATION_BYTES $GREPTIMEDB_ENVELOPE_RESERVATION_BYTES"
            fi
            if [ $((used * 100)) -ge $((quota * GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT)) ]; then
              fail "R7.3: used $used >= $GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT% of quota $quota"
            fi
          fi
        fi

        # R7.4
        if ! current=$(< "$GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE"); then
          fail "R7.4: cannot read $GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE"
        elif ! loaded=$(< ${loadedUsersHashFile}); then
          fail "R7.4: ${loadedUsersHashFile} is missing; the store has not recorded the users file it loaded"
        elif [ -z "$current" ] || [ "$current" != "$loaded" ]; then
          fail "R7.4: the running store loaded users file sha256 '$loaded', the deployed one is '$current'; restart ${unit}"
        fi

        if [ "$failed" -ne 0 ]; then
          exit 1
        fi
        echo "greptimedb-envelope: all checks passed"
      '';
    };
in
{
  flake.lib = {
    inherit greptimedbSql greptimedbEnvelope;
  };
}
```

- [ ] **Step 5: Add the envelope units to the store module**

In `modules/nixos/greptimedb.nix`, change the outer function head from `{ ... }:` to the form `modules/nixos/omnigraph.nix:1-5` uses:

```nix
{ config, ... }:
let
  flakeLib = config.flake.lib;
in
{
```

In the inner `let` block, after `configFile`, add:

```nix
      # MemoryHigh as systemd parses it: a G suffix is a power of 1024.
      memoryHigh = config.systemd.services.greptimedb.serviceConfig.MemoryHigh;
      memoryHighGiB = builtins.match "([0-9]+)G" memoryHigh;

      envelope = flakeLib.greptimedbEnvelope pkgs {
        url = "http://${cfg.settings.http.addr}";
        databases = lib.attrNames cfg.databases;
        unit = "greptimedb.service";
        loadedUsersHashFile = "/run/greptimedb/loaded-users.sha256";
        zfsPackage = config.boot.zfs.package;
        systemdPackage = config.systemd.package;
      };
```

Append this element to the module's `assertions` list:

```nix
          {
            assertion = memoryHighGiB != null;
            message = "services.greptimedb: greptimedb.service MemoryHigh must be whole gibibytes (\"<n>G\"); greptimedb-envelope derives its memory.peak threshold from it";
          }
```

Inside `config = lib.mkIf cfg.enable { … }`, after `systemd.services.greptimedb-schema`, add:

```nix
        # Runtime envelope (design D12), run hourly as the regulator account.
        # The host supplies LoadCredential=regulator-password and the
        # GREPTIMEDB_ENVELOPE_{DATASET,QUOTA_BYTES,RESERVATION_BYTES,USERS_SHA256_FILE}
        # environment, so this module stays free of clan vars. /dev/zfs stays
        # visible (no PrivateDevices) for `zfs get`, and systemd-journal lets
        # the run read the unit's OOM records.
        systemd.services.greptimedb-envelope = {
          description = "GreptimeDB runtime envelope";
          after = [ "greptimedb.service" ];
          environment = {
            GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES = toString (
              lib.toInt (builtins.head memoryHighGiB) * 1024 * 1024 * 1024
            );
            GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT = "80";
            GREPTIMEDB_ENVELOPE_SST_MAX_BYTES = toString (50 * 1024 * 1024 * 1024);
          };
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe envelope;
            DynamicUser = true;
            SupplementaryGroups = [ "systemd-journal" ];
            StateDirectory = "greptimedb-envelope";
            UMask = "0077";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            RestrictSUIDSGID = true;
            RestrictAddressFamilies = [
              "AF_UNIX"
              "AF_INET"
              "AF_INET6"
            ];
          };
        };

        systemd.timers.greptimedb-envelope = {
          description = "Hourly GreptimeDB runtime envelope";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            Persistent = true;
            RandomizedDelaySec = "5m";
          };
        };
```

- [ ] **Step 6: Wire the envelope on magnetite**

In `modules/machines/nixos/magnetite/default.nix`, immediately after Task 2's `systemd.services.greptimedb-schema.serviceConfig.LoadCredential` definition, add the following.
It reads Task 2's binding `greptimedbDataset = { name = "zroot/root/greptimedb"; mountpoint = "/var/lib/greptimedb"; quota = "16G"; reservation = "12G"; };`, the one source the three ZFS oneshots also read, and converts its sizes to bytes the way `zfs get -Hp` reports them (a `G` suffix is a power of 1024).

```nix
      # The regulator credential and the host facts greptimedb-envelope checks.
      # Quota and reservation come from greptimedbDataset, the binding the
      # zfs-set-root-greptimedb-{quota,reservation} oneshots apply, so R7.3
      # compares the dataset against the value this host declares.
      systemd.services.greptimedb-envelope = {
        serviceConfig.LoadCredential = [
          "regulator-password:${config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path}"
        ];
        environment =
          let
            gibibytes =
              size:
              let
                m = builtins.match "([0-9]+)G" size;
              in
              assert lib.assertMsg (m != null) "greptimedbDataset sizes must be whole gibibytes (\"<n>G\"), got ${size}";
              toString (lib.toInt (builtins.head m) * 1024 * 1024 * 1024);
          in
          {
            GREPTIMEDB_ENVELOPE_DATASET = greptimedbDataset.name;
            GREPTIMEDB_ENVELOPE_QUOTA_BYTES = gibibytes greptimedbDataset.quota;
            GREPTIMEDB_ENVELOPE_RESERVATION_BYTES = gibibytes greptimedbDataset.reservation;
            GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE = "${config.clan.core.vars.generators.greptimedb-users.files.users-sha256.path}";
          };
      };
```

In the same file's `services.observability-notify.units` list, insert after `"greptimedb"`:

```nix
        "greptimedb-envelope"
```

- [ ] **Step 7: Run both checks to verify they pass**

Run:

```bash
jj st --no-pager >/dev/null  # snapshot so the new modules/lib/greptimedb-envelope.nix is in the git index the flake reads
nix build .#checks.x86_64-linux.greptimedb-envelope -L 2>&1 | tee logs/t4-envelope-green-$(date +%Y%m%d-%H%M%S).log | rg -- '^greptimedb-sql-rehearsal> (---|FAIL)'
nix build .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/t4-otel-green-$(date +%Y%m%d-%H%M%S).log
```

Expected: both succeed; the first prints the three `---` row names and no `FAIL` line.

- [ ] **Step 8: Show the rehearsal can fail (the converse)**

Locally delete the four-line `if jq -e '(.output[0].records.rows | length) == 0' …; fi` block from `greptimedbSql` in `modules/lib/greptimedb-envelope.nix`, then run:

```bash
nix build .#checks.x86_64-linux.greptimedb-envelope -L 2>&1 | tee logs/t4-envelope-converse-$(date +%Y%m%d-%H%M%S).log | rg -- 'FAIL'
```

Expected: the build fails with `FAIL: an empty records result fails: exit status 0, expected 1`.
Re-add the four deleted lines exactly as Step 4 shows them, and rerun the Step 7 command for `greptimedb-envelope`, expecting success.

- [ ] **Step 9: Verify the evaluated units**

Run:

```bash
nix eval --json .#nixosConfigurations.magnetite.config.systemd.timers.greptimedb-envelope.timerConfig
nix eval --json .#nixosConfigurations.magnetite.config.systemd.services.greptimedb-envelope \
  --apply 's: { inherit (s) environment after; onFailure = s.unitConfig.OnFailure; stopPost = s.serviceConfig.ExecStopPost; inherit (s.serviceConfig) DynamicUser SupplementaryGroups StateDirectory LoadCredential; }'
nix eval --raw .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.users-sha256.path
```

Expected:
- the timer config is `{"OnCalendar":"hourly","Persistent":true,"RandomizedDelaySec":"5m"}`;
- `environment` contains `GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES` `"3221225472"`, `GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT` `"80"`, `GREPTIMEDB_ENVELOPE_SST_MAX_BYTES` `"53687091200"`, `GREPTIMEDB_ENVELOPE_DATASET` `"zroot/root/greptimedb"`, `GREPTIMEDB_ENVELOPE_QUOTA_BYTES` `"17179869184"`, `GREPTIMEDB_ENVELOPE_RESERVATION_BYTES` `"12884901888"`, and `GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE` equal to the third command's output;
- `after` contains `"greptimedb.service"`, `onFailure` is `["observability-notify@%n.service"]`, `stopPost` contains the `observability-notify-resolved %n` entry;
- `DynamicUser` true, `SupplementaryGroups` `["systemd-journal"]`, `StateDirectory` `"greptimedb-envelope"`, and `LoadCredential` the single entry `regulator-password:/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password`.

- [ ] **Step 10: Build magnetite's system with the envelope script**

Run:

```bash
nix build .#checks.x86_64-linux.nixos-magnetite 2>&1 | tee logs/t4-nixos-magnetite-$(date +%Y%m%d-%H%M%S).log
```

Expected: success; the build runs `writeShellApplication`'s shellcheck over `greptimedb-sql` and `greptimedb-envelope`, so a shellcheck finding fails here.
The envelope's runtime behaviour is verified on magnetite by Task 6 (8.6) and Task 7 (9.1).

- [ ] **Step 11: Tick the tasks**

In `openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md`, change `- [ ] 5.1` to `- [x] 5.1` and `- [ ] 5.2` to `- [x] 5.2`.

- [ ] **Step 12: Commit**

```bash
jj new --no-edit -r main@origin -m 'feat(greptimedb): add hourly runtime envelope'
jj squash --from @ --into 'description(substring:"feat(greptimedb): add hourly runtime envelope") & mutable()' --keep-emptied --use-destination-message -- \
  modules/lib/greptimedb-envelope.nix \
  modules/nixos/greptimedb.nix \
  modules/machines/nixos/magnetite/default.nix \
  modules/checks/greptimedb-envelope.nix \
  modules/checks/otel-collector-config.nix \
  openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md
```

Expected: one new change off `main@origin` holding the six paths, with `@` left empty.
The orchestrator rebases the development join onto it, pushes, and opens the pull request.

---

### Task 5: Runtime tests and the on-demand lane

Covers `tasks.md` 6.1, 6.2 and 7.2.
Both tests live under `vmTests`, never `checks`, so nixbot never evaluates them on a pull request (design D13, `modules/vm-tests/default.nix:1-10`).
`greptimedb-pipeline` is a systemd-nspawn `containers` test: its derivation requires `nixos-test` and `uid-range`, which only magnetite advertises (`modules/clan/inventory/services/nix-builders.nix:34-45`), so a dispatcher such as stibnite routes it there, or it is built on magnetite directly.
`greptimedb-oom-order` is a QEMU `nodes` test requiring `kvm` and `nixos-test` with `qemu.forceAccel = true`, which routes only to pyrite (`nix-builders.nix:52-60`).
Evidence goes to `logs/s1-evidence/6.1-greptimedb-pipeline.log` and `logs/s1-evidence/6.2-greptimedb-oom-order.log`; Task 7 folds them into `verify.md`.

Facts this task relies on, read from the root nixpkgs pin and upstream sources:

- `runNixOSTest` turns `containers.<name>` into `systemd-nspawn` machines (`nixos/lib/testing/driver-configuration.nix:68-71`), and `requiredFeatures.uid-range` defaults to true and `kvm` to false when only containers are present (`nixos/lib/testing/run.nix:47-60`).
- A container shares the host kernel, so its OOM killer is the build host's: the kill order can only be tested in a VM (`nixos/doc/manual/development/writing-nixos-tests.section.md`, "Virtual machines vs. containers"; design D13).
  Containers also cannot activate a `specialisation` (`nixos/modules/virtualisation/nspawn-container/default.nix`, assertion), so the changed-TTL re-run uses a runtime drop-in built from a second evaluation through `extendModules`, not a specialisation.
- A heavily hardened `DynamicUser` unit runs in an nspawn test node at this pin: `nixos/tests/victoriametrics/remote-write.nix:17` runs `services.victoriametrics` (`DynamicUser`, `ProtectSystem`, `PrivateDevices`, `PrivateUsers`, `RestrictNamespaces`; `nixos/modules/services/databases/victoriametrics.nix:186-232`) under `containers`.
- Container commands run through `nsenter` as root with `set -eo pipefail` and `/etc/profile` sourced (`nixos/lib/test-driver/src/test_driver/machine/__init__.py:1761-1802`); `retry` and `subtest` are test-script globals (`driver.py:320-345`).
- GreptimeDB v1.2.1 answers no or wrong credentials with 401 and a permission-mode violation with 403 (`src/servers/src/error.rs:959-966`); upstream's own test asserts a `wo` user's read is `FORBIDDEN` (`tests-integration/tests/http.rs:241-305`).
- `/health` and `/dashboard/` need no credentials; every other `/v1/` path does (`src/servers/src/http/authorize.rs:336-346`); the database comes from `x-greptime-db-name` before the `db` query parameter (`authorize.rs:161-179`).
- `SHOW CREATE DATABASE` prints the TTL normalised (`'7d'` is shown as `'7days'`, `tests/cases/standalone/common/show/show_create.result:44`), so the test compares a database's TTL with a reference database created with the same TTL string rather than with a literal.
- The kernel's victim summary is one line, `oom-kill:constraint=<c>,nodemask=<n>,cpuset=<cs>,mems_allowed=<m>,global_oom,task_memcg=<cgroup path>,task=<comm>,pid=<pid>,uid=<uid>` (Linux v6.18 `mm/oom_kill.c:447-457`, `kernel/cgroup/cpuset.c:4433-4446`, `mm/memcontrol.c:1539-1553`, where a cgroup-limit OOM prints `,oom_memcg=<path>` instead of `,global_oom`), followed by `Out of memory: Killed process <pid> (<comm>) total-vm:…, UID:<uid> pgtables:<n>kB oom_score_adj:<adj>` (`mm/oom_kill.c:960-966`, message `"Out of memory"` for a host-wide OOM at `:1184`, `"Memory cgroup out of memory"` otherwise).
  magnetite and the test VM both run kernel 6.18.55 from the root pin.
- systemd 261.3 (magnetite's and the pin's) logs `<unit>: The kernel OOM killer killed some processes in this unit.` whenever a unit's `memory.events` `oom_kill` count rises (`src/core/cgroup.c:3057-3105`), including when the cgroup empties first (`cgroup.c:2960-2962`).
  With the default `OOMPolicy=stop` (`src/core/manager.c:5384`), a service still `running` after the kill is stopped with result `oom-kill` (`src/core/service.c:4513-4545`) and logs `<unit>: Failed with result 'oom-kill'.` (`src/core/unit.c:6261-6268`, `service.c:6400`).
  A unit whose only process was the victim may record `signal` instead, depending on whether SIGCHLD or the `memory.events` notification is dispatched first, so only `greptimedb.service`, whose main process survives the kill of the consumer in its cgroup, is asserted to fail with `oom-kill`.

**Files:**
- Create: `modules/vm-tests/greptimedb-pipeline.nix`
- Create: `modules/vm-tests/greptimedb-oom-order.nix`
- Modify: `modules/README.md:32` (the `vm-tests/` entry) and `modules/README.md:50-55` (the "On-demand VM tests" commands), plus two new paragraphs after `:59`
- Modify: `openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md` (tick 6.1, 6.2, 7.2)

**Interfaces:**
- Consumes:
  - `flake.modules.nixos.greptimedb` (Task 2) with `services.greptimedb.{enable,databases}`; the module sets no credential, so the test sets `systemd.services.greptimedb.serviceConfig.LoadCredential = [ "users:<path>" ]` and `systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [ "admin-password:<path>" ]`; with no `[storage]` stanza from the host, the store uses its default `File` storage under `/var/lib/greptimedb`.
  - `greptimedb-schema.service` (Task 2): `Type = "oneshot"`, `RemainAfterExit = true`, re-applies every database's TTL on `systemctl restart`.
  - `self.nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.finalScript` (Task 2), run as `out=<dir> bash <finalScript>`, writing `users`, `admin-password`, `collector-password`, `perses-password`, `regulator-password` (hex, no trailing newline) and `users-sha256`.
  - magnetite's evaluated `services.greptimedb.databases` (`{ fleet = "30d"; devloop = "365d"; agent = "90d"; }`), `systemd.services.greptimedb.serviceConfig.OOMScoreAdjust` (500), `systemd.services.opentelemetry-collector.serviceConfig.OOMScoreAdjust` (300) and `services.memoryPressureGuards.enable`.
  - `flake.modules.nixos.otel-collector-agent` and `flake.modules.nixos.otel-collector-ingress` (Task 3): the agent module sets `services.opentelemetry-collector.enable`, the pipeline `metrics/host` (processors `memory_limiter`, `transform/omnigent-alias`, `resource/agent` upserting `host.name = config.networking.hostName` and `vanixiets.database = "fleet"`, exporter `forward`) and the systemd receiver on `self.lib.otelCollectorSchema.systemdUnits`, which contains `omnigent-host-*.service`; only the clan `ingress` role adds `LoadCredential=collector-password`, so the test supplies it.
  - `self.lib.otelCollectorSchema.ownerAliases` (Task 3): owner to alias, baked into `transform/omnigent-alias` as `omnigent-host-<owner>.service` → `omnigent-host-<alias>.service`.
  - `flake.modules.nixos.nix-eval-lock` and `self.lib.mkNixEvalLockWrapper` (`modules/nixos/nix-eval-lock.nix`, `modules/lib/nix-eval-lock.nix:14-34`): the wrapper raises its own `oom_score_adj` to 900 and execs the evaluator (`modules/lib/nix-eval-lock.sh`, last lines).
  - `flake.modules.nixos.memory-pressure-guards` (`modules/nixos/memory-pressure-guards.nix`).
- Produces:
  - `vmTests.x86_64-linux.greptimedb-pipeline` at `modules/vm-tests/greptimedb-pipeline.nix`.
  - `vmTests.x86_64-linux.greptimedb-oom-order` at `modules/vm-tests/greptimedb-oom-order.nix`.
  - The `modules/README.md` lane entries Task 7 cites.

- [ ] **Step 1: Confirm the pipeline test does not exist yet**

Run:

```bash
nix eval --raw .#vmTests.x86_64-linux.greptimedb-pipeline.drvPath
```

Expected: FAIL with `error: attribute 'greptimedb-pipeline' missing`.

- [ ] **Step 2: Confirm the collector names the test extends**

The test appends to the agent's `metrics/host` pipeline and relies on the alias statement and the allow-list pattern; confirm all three against magnetite's evaluated configuration before writing the test.

Run:

```bash
nix eval --json '.#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.service.pipelines."metrics/host".exporters'
nix eval --json '.#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.processors."transform/omnigent-alias".metric_statements' | jq -r '.[0]'
nix eval --json .#lib.otelCollectorSchema.systemdUnits | jq 'index("omnigent-host-*.service") != null'
nix eval --json .#nixosConfigurations.magnetite.config.services.greptimedb.databases
```

Expected, in order: `["forward"]`; a statement of the form `set(resource.attributes["systemd.unit.name"], "omnigent-host-owner-1.service") where resource.attributes["systemd.unit.name"] == "omnigent-host-cameron.service"`; `true`; `{"agent":"90d","devloop":"365d","fleet":"30d"}`.
If any differs, stop and reconcile the names with Task 3 or Task 2 before continuing; the test below hard-codes `metrics/host`.

- [ ] **Step 3: Write the pipeline test**

Create `modules/vm-tests/greptimedb-pipeline.nix` with exactly this content:

```nix
# Runtime pipeline test for the telemetry store and its collector
# (openspec/changes/stand-up-greptimedb-on-magnetite, design D13, tasks 6.1).
#
# What this establishes, in one systemd-nspawn container on a builder that
# advertises uid-range (magnetite):
#   1. greptimedb-bin answers /health and serves its embedded dashboard at
#      /dashboard/ (R1.1's runtime side);
#   2. greptimedb-schema creates magnetite's databases with their TTLs, and a
#      re-run with a changed TTL changes the stored TTL (F1);
#   3. the users file written by magnetite's real greptimedb-users generator is
#      enforced: no or wrong credentials are 401, a write-only read and a
#      read-only write (perses and regulator) are 403, permitted calls are 200;
#   4. an OTLP point entering the agent pipeline crosses the forward and
#      routing connectors into `fleet` and no other database, and reads back
#      through PromQL with x-greptime-db-name carrying host_name;
#   5. the systemd receiver reaches D-Bus under DynamicUser, and an
#      omnigent-host-<owner> unit is stored only under its alias;
#   6. a point emitted while greptimedb.service is stopped reaches the store
#      once it starts again.
#
# What it does not establish: R2 storage (the S3 stanza is magnetite's host
# configuration; the store here uses its default File storage), the ZFS
# envelope, the OOM kill order (a container shares the build host's kernel;
# see greptimedb-oom-order), ntfy delivery, or anything about magnetite's
# deployed credentials. It lives in the non-gating vmTests lane: on-demand
# evidence, not pull-request coverage.
{ self, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        greptimedb-pipeline =
          let
            # perSystem `pkgs` lacks the flake overlay that carries
            # greptimedb-bin and ntfy-send.
            nodePkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
              overlays = [ self.overlays.default ];
            };
            # Databases, TTLs and the users generator are read from the machine
            # that declares them, so an inventory change cannot drift past this
            # test silently.
            reference = self.nixosConfigurations.magnetite.config;
            inherit (reference.services.greptimedb) databases;
            usersGenerator = reference.clan.core.vars.generators.greptimedb-users;
            schema = self.lib.otelCollectorSchema;
            owner = lib.head (lib.attrNames schema.ownerAliases);
            alias = schema.ownerAliases.${owner};
            changedTtl = "7d";
            vars = "/run/greptimedb-test-vars";
            credentialConsumers = [
              "greptimedb.service"
              "greptimedb-schema.service"
              "opentelemetry-collector.service"
            ];
          in
          assert lib.assertMsg (databases ? fleet && databases.fleet != changedTtl)
            "greptimedb-pipeline: magnetite must declare fleet with a TTL other than ${changedTtl}";
          pkgs.testers.runNixOSTest {
            name = "greptimedb-pipeline";
            requiredFeatures = {
              nixos-test = true;
              uid-range = true;
            };
            node.pkgs = lib.mkForce nodePkgs;
            containers.store =
              {
                extendModules,
                pkgs,
                ...
              }:
              let
                # The schema oneshot's command as it would be built with
                # fleet's TTL changed; installed at runtime as a drop-in,
                # because an nspawn node cannot switch to a specialisation.
                changedSchemaExecStart =
                  (extendModules {
                    modules = [ { services.greptimedb.databases.fleet = lib.mkForce changedTtl; } ];
                  }).config.systemd.services.greptimedb-schema.serviceConfig.ExecStart;
              in
              {
                imports = [
                  self.modules.nixos.greptimedb
                  self.modules.nixos.otel-collector-agent
                  self.modules.nixos.otel-collector-ingress
                ];
                system.stateVersion = lib.trivial.release;
                environment.systemPackages = [ pkgs.curl ];

                services.greptimedb = {
                  enable = true;
                  inherit databases;
                };

                # Credentials come from magnetite's own generator script, run
                # at boot, so no credential value exists in the repository and
                # the users file has exactly the deployed shape. The netrc
                # files keep passwords out of the test driver's command log.
                systemd.services.greptimedb-test-vars = {
                  description = "Test credentials from magnetite's greptimedb-users generator";
                  requiredBy = credentialConsumers;
                  before = credentialConsumers;
                  path = [
                    pkgs.bash
                    pkgs.coreutils
                  ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = ''
                    install -d -m 0700 ${vars}
                    out=${vars} bash ${usersGenerator.finalScript}
                    for user in admin collector perses regulator; do
                      printf 'machine 127.0.0.1 login %s password %s\n' \
                        "$user" "$(cat "${vars}/$user-password")" > "${vars}/$user.netrc"
                    done
                    printf 'machine 127.0.0.1 login admin password %s\n' 0000 > ${vars}/wrong.netrc
                  '';
                };
                systemd.services.greptimedb.serviceConfig.LoadCredential = [ "users:${vars}/users" ];
                systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [
                  "admin-password:${vars}/admin-password"
                ];
                systemd.services.opentelemetry-collector.serviceConfig.LoadCredential = [
                  "collector-password:${vars}/collector-password"
                ];

                # A loopback OTLP entry into the agent pipeline that stamps
                # host.name and vanixiets.database, so a synthetic point takes
                # the same forward and routing path as host metrics.
                services.opentelemetry-collector.settings = {
                  receivers.otlp.protocols.http.endpoint = "127.0.0.1:4318";
                  service.pipelines."metrics/host".receivers = [ "otlp" ];
                };

                # An owner-named unit inside the allow-list pattern; only its
                # alias may reach the store.
                systemd.services."omnigent-host-${owner}" = {
                  description = "Stand-in for an Omnigent host unit named by its owner";
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig.ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
                };

                environment.etc."greptimedb-test/schema-changed-ttl.conf".text = ''
                  [Service]
                  ExecStart=
                  ${lib.concatMapStringsSep "\n" (command: "ExecStart=${command}") (
                    lib.toList changedSchemaExecStart
                  )}
                '';
              };
            testScript = ''
              import datetime as dt
              import json
              import re
              import shlex

              VARS = "${vars}"
              DATABASES = json.loads(${builtins.toJSON (builtins.toJSON databases)})
              CHANGED_TTL = "${changedTtl}"
              OWNER = "${owner}"
              ALIAS_UNIT = "omnigent-host-${alias}.service"
              DROP_IN = "/run/systemd/system/greptimedb-schema.service.d/zz-changed-ttl.conf"


              def request(path, netrc=None, db=None, params=()):
                  cmd = ["curl", "-sS", "-o", "/tmp/response", "-w", "%{http_code}", "--get"]
                  if netrc is not None:
                      cmd += ["--netrc-file", f"{VARS}/{netrc}.netrc"]
                  if db is not None:
                      cmd += ["-H", f"x-greptime-db-name: {db}"]
                  for key, value in params:
                      cmd += ["--data-urlencode", f"{key}={value}"]
                  cmd.append(f"http://127.0.0.1:4000{path}")
                  status = int(store.succeed(shlex.join(cmd)))
                  return status, store.succeed("cat /tmp/response")


              def sql_status(user, db, statement):
                  return request("/v1/sql", netrc=user, db=db, params=[("sql", statement)])[0]


              def sql(db, statement, user="admin"):
                  status, body = request("/v1/sql", netrc=user, db=db, params=[("sql", statement)])
                  assert status == 200, (statement, status, body)
                  return json.loads(body)["output"][0]["records"]["rows"]


              def promql_status(query, db="fleet"):
                  status, body = request(
                      "/v1/prometheus/api/v1/query", netrc="perses", db=db, params=[("query", query)]
                  )
                  result = json.loads(body)["data"]["result"] if status == 200 else []
                  return status, result


              def promql(query, db="fleet"):
                  status, result = promql_status(query, db)
                  assert status == 200, (query, status)
                  return result


              def ttl(db):
                  rows = sql("public", f"SHOW CREATE DATABASE {db}")
                  match = re.search(r"ttl = '([^']+)'", rows[0][1])
                  assert match is not None, (db, rows)
                  return match.group(1)


              def emit(probe):
                  now = store.succeed("date +%s%N").strip()
                  point = {
                      "asDouble": 1.0,
                      "timeUnixNano": now,
                      "attributes": [{"key": "probe", "value": {"stringValue": probe}}],
                  }
                  metric = {"name": "s1_probe", "gauge": {"dataPoints": [point]}}
                  scope = {"scope": {"name": "greptimedb-pipeline"}, "metrics": [metric]}
                  payload = json.dumps(
                      {"resourceMetrics": [{"resource": {"attributes": []}, "scopeMetrics": [scope]}]}
                  )
                  store.succeed(
                      "curl -sSf -H 'Content-Type: application/json' "
                      f"--data {shlex.quote(payload)} http://127.0.0.1:4318/v1/metrics"
                  )


              def restart_probe_count():
                  status, body = request(
                      "/v1/sql",
                      netrc="admin",
                      db="fleet",
                      params=[("sql", "SELECT count(*) FROM s1_probe WHERE probe = 'restart'")],
                  )
                  if status != 200:
                      return 0
                  return json.loads(body)["output"][0]["records"]["rows"][0][0]


              start_all()
              store.wait_for_unit("greptimedb.service")
              store.wait_until_succeeds(
                  "curl -sf http://127.0.0.1:4000/health", timeout=dt.timedelta(minutes=2)
              )
              store.wait_for_unit("greptimedb-schema.service")
              store.wait_for_unit("opentelemetry-collector.service")
              hostname = store.succeed("hostname").strip()

              with subtest("the store answers /health and serves its embedded dashboard"):
                  status, _ = request("/health")
                  assert status == 200, status
                  status, body = request("/dashboard/")
                  assert status == 200, status
                  assert "<html" in body.lower(), body[:200]

              with subtest("the schema oneshot creates each database with its TTL"):
                  for db, want in DATABASES.items():
                      sql("public", f"CREATE DATABASE IF NOT EXISTS ttl_reference_{db} WITH (ttl = '{want}')")
                      assert ttl(db) == ttl(f"ttl_reference_{db}"), (db, ttl(db), want)

              with subtest("a re-run with a changed TTL alters the stored TTL"):
                  sql(
                      "public",
                      f"CREATE DATABASE IF NOT EXISTS ttl_reference_changed WITH (ttl = '{CHANGED_TTL}')",
                  )
                  store.succeed(
                      f"install -D -m 0444 /etc/greptimedb-test/schema-changed-ttl.conf {DROP_IN}",
                      "systemctl daemon-reload",
                      "systemctl restart greptimedb-schema.service",
                  )
                  assert ttl("fleet") == ttl("ttl_reference_changed"), ttl("fleet")
                  assert ttl("fleet") != ttl("ttl_reference_fleet"), ttl("fleet")
                  for db in DATABASES:
                      if db != "fleet":
                          assert ttl(db) == ttl(f"ttl_reference_{db}"), (db, ttl(db))
                  store.succeed(f"rm {DROP_IN}", "systemctl daemon-reload")

              with subtest("the users file is enforced per role"):
                  read = "SHOW TABLES"

                  def create(user):
                      return f"CREATE TABLE IF NOT EXISTS auth_{user} (ts TIMESTAMP TIME INDEX)"

                  assert request("/v1/sql", db="public", params=[("sql", read)])[0] == 401
                  assert sql_status("wrong", "public", read) == 401
                  assert sql_status("admin", "public", read) == 200
                  assert sql_status("admin", "public", create("admin")) == 200
                  assert sql_status("perses", "public", read) == 200
                  assert sql_status("perses", "public", create("perses")) == 403
                  assert sql_status("regulator", "public", read) == 200
                  assert sql_status("regulator", "public", create("regulator")) == 403
                  assert sql_status("collector", "public", read) == 403
                  assert sql_status("collector", "public", create("collector")) == 200

              with subtest("an OTLP point is routed into fleet and read back through PromQL"):
                  emit("ingest")
                  retry(
                      lambda _last: len(promql_status('s1_probe{probe="ingest"}')[1]) > 0,
                      timeout=dt.timedelta(minutes=3),
                  )
                  series = promql('s1_probe{probe="ingest"}')
                  assert series[0]["metric"]["host_name"] == hostname, series
                  for db in DATABASES:
                      if db != "fleet":
                          tables = [row[0] for row in sql(db, "SHOW TABLES")]
                          assert "s1_probe" not in tables, (db, tables)

              with subtest("the systemd receiver stores unit state under DynamicUser, owners only as aliases"):
                  dynamic = store.succeed("systemctl show -P DynamicUser opentelemetry-collector.service")
                  assert dynamic.strip() == "yes", dynamic
                  unit_query = f'systemd_unit_state{{host_name="{hostname}",systemd_unit_name="{ALIAS_UNIT}"}}'
                  retry(
                      lambda _last: len(promql_status(unit_query)[1]) > 0,
                      timeout=dt.timedelta(minutes=5),
                  )
                  states = promql(unit_query)
                  assert any(state["value"][1] == "1" for state in states), states
                  names = [row[0] for row in sql("fleet", "SELECT DISTINCT systemd_unit_name FROM systemd_unit_state")]
                  assert ALIAS_UNIT in names, names
                  assert not any(OWNER in name for name in names), names

              with subtest("a point emitted while the store is stopped arrives after it starts"):
                  store.succeed("systemctl stop greptimedb.service")
                  store.fail("curl -sf http://127.0.0.1:4000/health")
                  emit("restart")
                  store.succeed("systemctl start greptimedb.service")
                  store.wait_until_succeeds(
                      "curl -sf http://127.0.0.1:4000/health", timeout=dt.timedelta(minutes=2)
                  )
                  retry(lambda _last: restart_probe_count() >= 1, timeout=dt.timedelta(minutes=5))
            '';
          };
      };
    };
}
```

- [ ] **Step 4: Snapshot the new file and confirm the test evaluates**

Run:

```bash
jj st --no-pager >/dev/null
nix eval --raw .#vmTests.x86_64-linux.greptimedb-pipeline.drvPath
nix eval --json '.#vmTests.x86_64-linux.greptimedb-pipeline.config.containers.store.services.opentelemetry-collector.settings.service.pipelines."metrics/host".receivers'
nix eval --json .#vmTests.x86_64-linux.greptimedb-pipeline.config.containers.store.systemd.services.greptimedb.serviceConfig.LoadCredential
nix eval --raw '.#vmTests.x86_64-linux.greptimedb-pipeline.config.containers.store.environment.etc."greptimedb-test/schema-changed-ttl.conf".text'
```

Expected, in order: a `/nix/store/…-container-test-run-greptimedb-pipeline.drv` path; a JSON list that contains `"otlp"` beside the agent role's receivers; `["users:/run/greptimedb-test-vars/users"]`; a drop-in whose first lines are `[Service]` and `ExecStart=`, followed by one `ExecStart=/nix/store/…` line naming a different store path from `nix eval --json .#vmTests.x86_64-linux.greptimedb-pipeline.config.containers.store.systemd.services.greptimedb-schema.serviceConfig.ExecStart`.

- [ ] **Step 5: Run the pipeline test on magnetite**

From stibnite (which cannot build `x86_64-linux` itself and dispatches to the only builder advertising `uid-range`), run:

```bash
mkdir -p logs/s1-evidence
nix build -L --no-link --max-jobs 0 .#vmTests.x86_64-linux.greptimedb-pipeline 2>&1 | tee logs/s1-evidence/6.1-greptimedb-pipeline.log
```

Alternatively, on magnetite from a checkout of the same revision: `nix build -L --no-link .#vmTests.x86_64-linux.greptimedb-pipeline 2>&1 | tee logs/s1-evidence/6.1-greptimedb-pipeline.log`.
Expected: the build is dispatched to magnetite (`grpc://[fddb:4344:343b:14b9:399:930f:39db:40d2]:50051` in the log when run from stibnite), all seven subtests log as entered with no assertion error (the users-file subtest asserts the matrix no credential 401, wrong password 401, `admin` read and write 200, `perses` read 200 and write 403, `regulator` read 200 and write 403, `collector` read 403 and write 200), the driver prints `test script finished in`, and `nix build` exits 0.
If a subtest fails, the failing assertion's tuple names the status or value; fix the cause in the module under test, not the assertion, and rerun.

- [ ] **Step 6: Confirm the OOM-order test does not exist yet**

Run:

```bash
nix eval --raw .#vmTests.x86_64-linux.greptimedb-oom-order.drvPath
```

Expected: FAIL with `error: attribute 'greptimedb-oom-order' missing`.

- [ ] **Step 7: Write the OOM-order test**

Create `modules/vm-tests/greptimedb-oom-order.nix` with exactly this content:

```nix
# Kernel OOM kill order between the CI evaluator, the telemetry store and the
# collector (openspec/changes/stand-up-greptimedb-on-magnetite, design D3 and
# D13, tasks 6.2; world assumption A32).
#
# What this establishes, in one QEMU VM with forced KVM (pyrite):
#   1. the real nix-eval-jobs lock wrapper raises its evaluator to
#      oom_score_adj 900, and the real greptimedb.service runs its process at
#      magnetite's evaluated OOMScoreAdjust (500);
#   2. when three equally growing consumers exhaust memory (one under the
#      wrapper, one inside greptimedb.service's cgroup at the unit's value, one
#      at magnetite's evaluated collector OOMScoreAdjust, 300), the kernel kills
#      them in that order (host-wide OOMs, not cgroup-limit OOMs), systemd
#      records a kernel OOM kill in each owning unit, and greptimedb.service
#      fails with result 'oom-kill' under the default OOMPolicy=stop.
#
# What it does not establish: the collector's own unit is not the third
# consumer, because its MemoryMax (512M) makes a hog inside its cgroup die to
# the cgroup's own OOM before any host-wide OOM, so a stand-in unit carries
# the collector's evaluated OOMScoreAdjust instead; nothing about magnetite's
# zram swap (the VM has none) or nixbot's bubblewrap sandbox; nothing about the
# store's real memory use, which R7.2 measures hourly on magnetite. It lives in
# the non-gating vmTests lane: on-demand evidence, not pull-request coverage.
{ self, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        greptimedb-oom-order =
          let
            nodePkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
              overlays = [ self.overlays.default ];
            };
            reference = self.nixosConfigurations.magnetite.config;
            storeAdj = reference.systemd.services.greptimedb.serviceConfig.OOMScoreAdjust;
            collectorAdj = reference.systemd.services.opentelemetry-collector.serviceConfig.OOMScoreAdjust;
            usersGenerator = reference.clan.core.vars.generators.greptimedb-users;
            vars = "/run/greptimedb-test-vars";
            credentialConsumers = [
              "greptimedb.service"
              "greptimedb-schema.service"
            ];
            # Records its pid, waits for the shared gate, then grows by 8 MiB
            # of touched memory every 20 ms until killed, so all three
            # consumers grow at the same rate.
            memoryHog = pkgs.writeScriptBin "memory-hog" ''
              #!${pkgs.python3.interpreter}
              import os
              import sys
              import time

              name = sys.argv[1]
              with open(f"/run/memory-hog/{name}.pid.tmp", "w") as ready:
                  ready.write(str(os.getpid()))
              os.rename(f"/run/memory-hog/{name}.pid.tmp", f"/run/memory-hog/{name}.pid")
              while not os.path.exists("/run/memory-hog/go"):
                  time.sleep(0.1)
              held = []
              while True:
                  held.append(b"\x01" * (8 << 20))
                  time.sleep(0.02)
            '';
          in
          pkgs.testers.runNixOSTest {
            name = "greptimedb-oom-order";
            requiredFeatures = {
              kvm = true;
              nixos-test = true;
            };
            qemu.forceAccel = true;
            node.pkgs = lib.mkForce nodePkgs;
            nodes.machine =
              { config, pkgs, ... }:
              let
                evaluator = self.lib.mkNixEvalLockWrapper pkgs {
                  evaluator = "${memoryHog}/bin/memory-hog";
                  inherit (config.services.nixEvalLock) lockFile;
                };
              in
              {
                imports = [
                  self.modules.nixos.greptimedb
                  self.modules.nixos.nix-eval-lock
                  self.modules.nixos.memory-pressure-guards
                ];
                system.stateVersion = lib.trivial.release;
                virtualisation.memorySize = 2048;
                virtualisation.cores = 2;
                environment.systemPackages = [
                  pkgs.curl
                  memoryHog
                ];

                services.greptimedb = {
                  enable = true;
                  inherit (reference.services.greptimedb) databases;
                };
                services.nixEvalLock.enable = true;
                services.memoryPressureGuards.enable = reference.services.memoryPressureGuards.enable;

                systemd.services.greptimedb-test-vars = {
                  description = "Test credentials from magnetite's greptimedb-users generator";
                  requiredBy = credentialConsumers;
                  before = credentialConsumers;
                  path = [
                    pkgs.bash
                    pkgs.coreutils
                  ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = ''
                    install -d -m 0700 ${vars}
                    out=${vars} bash ${usersGenerator.finalScript}
                  '';
                };
                systemd.services.greptimedb.serviceConfig.LoadCredential = [ "users:${vars}/users" ];
                systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [
                  "admin-password:${vars}/admin-password"
                ];

                systemd.tmpfiles.rules = [ "d /run/memory-hog 0755 root root -" ];

                # The evaluator behind the same wrapper magnetite installs; the
                # wrapper, not this unit, sets oom_score_adj 900.
                systemd.services.evaluator-standin = {
                  description = "nix-eval-jobs stand-in behind the host evaluation lock wrapper";
                  serviceConfig.ExecStart = "${evaluator}/bin/nix-eval-jobs evaluator";
                };
                systemd.services.collector-standin = {
                  description = "Collector stand-in at the collector's evaluated OOMScoreAdjust";
                  serviceConfig = {
                    ExecStart = "${memoryHog}/bin/memory-hog collector";
                    OOMScoreAdjust = collectorAdj;
                  };
                };
              };
            testScript = ''
              import datetime as dt
              import re

              EVALUATOR_ADJ = 900
              STORE_ADJ = ${toString storeAdj}
              COLLECTOR_ADJ = ${toString collectorAdj}
              EXPECTED = [
                  ("evaluator", EVALUATOR_ADJ, "/system.slice/evaluator-standin.service"),
                  ("store", STORE_ADJ, "/system.slice/greptimedb.service"),
                  ("collector", COLLECTOR_ADJ, "/system.slice/collector-standin.service"),
              ]
              KILLED = "Out of memory: Killed process"

              start_all()
              machine.wait_for_unit("greptimedb.service")
              machine.wait_until_succeeds(
                  "curl -sf http://127.0.0.1:4000/health", timeout=dt.timedelta(minutes=2)
              )
              assert KILLED not in machine.succeed("journalctl -k -o cat --no-pager")

              with subtest("each consumer runs at its envelope's oom_score_adj"):
                  main_pid = machine.succeed("systemctl show -P MainPID greptimedb.service").strip()
                  assert int(machine.succeed(f"cat /proc/{main_pid}/oom_score_adj")) == STORE_ADJ
                  machine.succeed("systemctl start evaluator-standin.service collector-standin.service")
                  machine.succeed(
                      "setsid sh -c 'echo $$ > /sys/fs/cgroup/system.slice/greptimedb.service/cgroup.procs"
                      f" && echo {STORE_ADJ} > /proc/$$/oom_score_adj && exec memory-hog store'"
                      " </dev/null >/dev/null 2>&1 &"
                  )
                  pids = {}
                  for name, adj, cgroup in EXPECTED:
                      machine.wait_for_file(f"/run/memory-hog/{name}.pid")
                      pids[name] = machine.succeed(f"cat /run/memory-hog/{name}.pid").strip()
                      assert int(machine.succeed(f"cat /proc/{pids[name]}/oom_score_adj")) == adj, name
                      assert machine.succeed(f"cat /proc/{pids[name]}/cgroup").strip() == f"0::{cgroup}", name

              with subtest("the kernel kills evaluator, store and collector in that order"):
                  machine.succeed("touch /run/memory-hog/go")
                  machine.wait_until_succeeds(
                      f"[ \"$(journalctl -k -o cat --no-pager | grep -c '{KILLED}')\" -ge 3 ]",
                      timeout=dt.timedelta(minutes=5),
                  )
                  kernel = machine.succeed("journalctl -k -o cat --no-pager")
                  # mm/oom_kill.c:447-457 at v6.18, with mm/memcontrol.c:1539-1553: only
                  # host-wide OOMs carry ",global_oom"; a cgroup-limit OOM carries ",oom_memcg=".
                  victims = re.findall(
                      r"^oom-kill:constraint=[^\n]*,global_oom,task_memcg=([^,\n]+),task=[^,\n]*,pid=(\d+),uid=\d+$",
                      kernel,
                      re.MULTILINE,
                  )
                  # mm/oom_kill.c:960-966 and :1184 at v6.18.
                  adjs = [
                      int(adj)
                      for adj in re.findall(r"^Out of memory: Killed process \d+ \([^\n]*\) [^\n]* oom_score_adj:(-?\d+)$", kernel, re.MULTILINE)
                  ]
                  assert "oom_memcg=" not in kernel, "a cgroup-limit OOM preceded the host-wide ones"
                  assert victims == [(cgroup, pids[name]) for name, _, cgroup in EXPECTED], victims
                  assert adjs == [adj for _, adj, _ in EXPECTED], adjs

              with subtest("systemd records the OOM kill in each owning unit"):
                  # systemd v261.3 src/core/cgroup.c:3098-3101.
                  for unit in ("evaluator-standin", "greptimedb", "collector-standin"):
                      machine.wait_until_succeeds(
                          f"journalctl -u {unit}.service -o cat --no-pager"
                          " | grep -F 'The kernel OOM killer killed some processes in this unit.'",
                          timeout=dt.timedelta(minutes=1),
                      )
                  # systemd v261.3 src/core/service.c:4538-4543 and src/core/unit.c:6261-6268:
                  # greptimedb's main process survives, so OOMPolicy=stop stops it with oom-kill.
                  machine.wait_until_succeeds(
                      "journalctl -u greptimedb.service -o cat --no-pager"
                      " | grep -F \"Failed with result 'oom-kill'.\"",
                      timeout=dt.timedelta(minutes=1),
                  )
            '';
          };
      };
    };
}
```

- [ ] **Step 8: Snapshot the new file and confirm the test evaluates with magnetite's values**

Run:

```bash
jj st --no-pager >/dev/null
nix eval --raw .#vmTests.x86_64-linux.greptimedb-oom-order.drvPath
nix eval .#vmTests.x86_64-linux.greptimedb-oom-order.config.nodes.machine.systemd.services.collector-standin.serviceConfig.OOMScoreAdjust
nix eval .#vmTests.x86_64-linux.greptimedb-oom-order.config.nodes.machine.systemd.services.greptimedb.serviceConfig.OOMScoreAdjust
nix eval .#vmTests.x86_64-linux.greptimedb-oom-order.config.nodes.machine.virtualisation.qemu.forceAccel
```

Expected, in order: a `/nix/store/…-vm-test-run-greptimedb-oom-order.drv` path; `300`; `500`; `true`.

- [ ] **Step 9: Run the OOM-order test on pyrite**

From stibnite, run:

```bash
mkdir -p logs/s1-evidence
nix build -L --no-link --max-jobs 0 .#vmTests.x86_64-linux.greptimedb-oom-order 2>&1 | tee logs/s1-evidence/6.2-greptimedb-oom-order.log
```

Expected: the build is dispatched to pyrite (`grpc://[fddb:4344:343b:14b9:399:937e:8067:8028]:50051`), the log shows three kernel lines `oom-kill:constraint=…,global_oom,task_memcg=/system.slice/<unit>,task=…,pid=…,uid=0` naming `evaluator-standin.service`, `greptimedb.service` and `collector-standin.service` in that order, each followed by `Out of memory: Killed process … oom_score_adj:900`, `…:500` and `…:300` respectively, all three subtests pass, the driver prints `test script finished in`, and `nix build` exits 0.
If pyrite is offline the build fails with `missing system features` and `Required features: {kvm}`; that is not a pass, so rerun when pyrite is reachable.

- [ ] **Step 10: Show the kill-order assertion able to fail**

Edit `modules/vm-tests/greptimedb-oom-order.nix` locally, replacing `OOMScoreAdjust = collectorAdj;` with `OOMScoreAdjust = 950;` and `COLLECTOR_ADJ = ${toString collectorAdj}` with `COLLECTOR_ADJ = 950`, so the stand-in now outranks the evaluator while the expected order stays evaluator, store, collector.
Run:

```bash
nix build -L --no-link --max-jobs 0 .#vmTests.x86_64-linux.greptimedb-oom-order 2>&1 | tee logs/s1-evidence/6.2-greptimedb-oom-order-mutant.log
```

Expected: FAIL in the subtest `the kernel kills evaluator, store and collector in that order`, with the `victims` assertion printing `/system.slice/collector-standin.service` first.
Then restore both lines exactly to `OOMScoreAdjust = collectorAdj;` and `COLLECTOR_ADJ = ${toString collectorAdj}`, and confirm with `nix eval .#vmTests.x86_64-linux.greptimedb-oom-order.config.nodes.machine.systemd.services.collector-standin.serviceConfig.OOMScoreAdjust` printing `300`.

- [ ] **Step 11: Correct the `vm-tests/` entry**

In `modules/README.md`, replace line 32:

```markdown
- `vm-tests/` — on-demand KVM-only tests exported as `vmTests.<system>.<name>`, outside PR gating.
```

with:

```markdown
- `vm-tests/` — on-demand runtime tests exported as `vmTests.<system>.<name>`, outside PR gating: QEMU VM tests needing `kvm`, and systemd-nspawn container tests needing `uid-range`.
```

- [ ] **Step 12: Add both tests to the on-demand lane**

In `modules/README.md`, replace lines 50-55:

````markdown
Run a runtime test on a reachable KVM-capable Linux host, such as Pyrite, from its checkout of the intended revision:

```sh
nix build .#vmTests.x86_64-linux.zerotier-mss-clamp-runtime
nix build .#vmTests.x86_64-linux.omnigent-worker-isolation
```
````

with:

````markdown
A runtime test builds only on a builder advertising the features its derivation requires: QEMU VM tests need `kvm`, which only Pyrite advertises, and systemd-nspawn container tests need `uid-range`, which only Magnetite advertises.
Run one from a checkout of the intended revision on that host, or from a dispatcher such as Stibnite, which routes it to the only builder with those features:

```sh
nix build .#vmTests.x86_64-linux.zerotier-mss-clamp-runtime   # Pyrite, kvm
nix build .#vmTests.x86_64-linux.omnigent-worker-isolation    # Pyrite, kvm
nix build .#vmTests.x86_64-linux.greptimedb-pipeline          # Magnetite, uid-range
nix build .#vmTests.x86_64-linux.greptimedb-oom-order         # Pyrite, kvm
```
````

Then insert after line 59 (the paragraph ending "`checks.x86_64-linux.omnigent-worker-linux` remains the fleet-wide regulator for the precondition script's own behaviour."), with a blank line before each paragraph:

```markdown
`greptimedb-pipeline` runs the telemetry store and both collector roles in one systemd-nspawn container, with credentials written at boot by Magnetite's own `greptimedb-users` generator script and Magnetite's databases and TTLs.
It establishes that the store answers `/health` and serves its embedded dashboard at `/dashboard/`, that the schema oneshot creates each database with its TTL and that a re-run with a changed TTL changes it, that no or wrong credentials are answered 401 while a write-only read and a read-only write, by `perses` and by `regulator`, are answered 403, that an OTLP point crosses the forward and routing connectors into `fleet` only and reads back through PromQL with `x-greptime-db-name` carrying `host_name`, that the systemd receiver reaches D-Bus under `DynamicUser` and stores an `omnigent-host-<owner>` unit only under its alias, and that a point emitted while the store is stopped arrives after it restarts.
It uses local `File` storage, so it establishes nothing about R2, and a container shares the build host's kernel, so it establishes nothing about OOM behaviour.

`greptimedb-oom-order` runs one QEMU VM in which three equally growing memory consumers exhaust memory: one behind the real `nix-eval-jobs` lock wrapper, one inside `greptimedb.service`'s cgroup at that unit's `oom_score_adj`, and a collector stand-in at the collector's evaluated `OOMScoreAdjust`.
It establishes that the kernel kills them in the order evaluator (900), store (500), collector (300), that systemd records the OOM kill in each owning unit, and that `greptimedb.service` fails with result `oom-kill` under the default `OOMPolicy=stop`.
The collector's own unit is not the third consumer, because its `MemoryMax` of 512M makes a consumer inside its cgroup die to the cgroup's own OOM first; the VM has no swap, unlike Magnetite's zram.
```

- [ ] **Step 13: Verify the README entries**

Run:

```bash
rg -n "greptimedb-pipeline|greptimedb-oom-order|vm-tests/" modules/README.md
```

Expected: line 32 shows the corrected `vm-tests/` entry naming both `kvm` and `uid-range`; the code block shows `nix build .#vmTests.x86_64-linux.greptimedb-pipeline          # Magnetite, uid-range` and `nix build .#vmTests.x86_64-linux.greptimedb-oom-order         # Pyrite, kvm`; and the two new paragraphs begin with `` `greptimedb-pipeline` `` and `` `greptimedb-oom-order` ``.

- [ ] **Step 14: Format and lint**

Run: `just lint 2>&1 | tee logs/lint-greptimedb-vm-tests-$(date +%Y%m%d-%H%M%S).log`
Expected: passes, including nixfmt on both new files and the secret scan (the files contain no credential value).

- [ ] **Step 15: Tick the task items**

In `openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md`, change the leading `- [ ] 6.1`, `- [ ] 6.2` and `- [ ] 7.2` to `- [x] 6.1`, `- [x] 6.2` and `- [x] 7.2`.
Run: `rg -n "^- \[x\] (6\.1|6\.2|7\.2) " openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md`
Expected: exactly three lines.

- [ ] **Step 16: Commit**

Create the change off `main@origin` and move this task's paths into it:

```bash
jj new --no-edit -r main@origin -m 'test(greptimedb): add pipeline and OOM-order runtime tests to the on-demand lane'
change=$(jj log --no-graph -r 'children(main@origin) & description(substring:"add pipeline and OOM-order runtime tests")' -T 'change_id.short()')
jj squash --from @ --into "$change" --keep-emptied --use-destination-message -- \
  modules/vm-tests/greptimedb-pipeline.nix \
  modules/vm-tests/greptimedb-oom-order.nix \
  modules/README.md \
  openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md
jj log --no-graph -r "$change" --stat
```

Expected: `jj log` shows the one change with the message above and exactly the four paths.
The orchestrator rebases the development join onto it, pushes it and opens the pull request; it is enqueued only after Task 4's pull request has landed.

---

---

### Task 6: Deployment

This task is operations only and opens no pull request.
It runs after the Task 5 pull request has merged, so `origin/main` carries Tasks 1–5.
Every observation is captured as command and output into `logs/s1-evidence/<tasks.md id>-<slug>.log` in the main repository (`logs/` is git-ignored); Task 7 folds these files into `verify.md` and ticks 7.1 and 8.4–8.6 in `tasks.md`.
`verify.md` is not created here, because its creation fires the In Progress → In Review transition for CAM-68.

**Files:**
- Create (git-ignored evidence, not committed): `logs/s1-evidence/7.1-charter-v11.log`, `logs/s1-evidence/8.4-paths.log`, `logs/s1-evidence/8.4-queue.log`, `logs/s1-evidence/8.4-clan-update.log`, `logs/s1-evidence/8.4-units.log`, `logs/s1-evidence/8.4-users-hash.log`, `logs/s1-evidence/8.5-zfs.log`, `logs/s1-evidence/8.5-promql-host-name.log`, `logs/s1-evidence/8.5-process-name-bound.log`, `logs/s1-evidence/8.5-sql-host-name.log`, `logs/s1-evidence/8.5-zram-paging.log`, `logs/s1-evidence/8.5-no-log-trace-tables.log`, `logs/s1-evidence/8.5-dashboard.log`, `logs/s1-evidence/8.5-r2.log`, `logs/s1-evidence/8.5-queue-rate.log`, `logs/s1-evidence/8.6-baseline.log`, `logs/s1-evidence/8.6-forced-failure.log`, `logs/s1-evidence/8.6-repeat-failure.log`, `logs/s1-evidence/8.6-resolved.log`
- Create (git-ignored helper): `logs/s1-evidence/gq.sh`
- Temporary: worktree `/tmp/wt-main` at `origin/main`, removed at the end of the task

**Interfaces:**
- Consumes: `greptimedb.service`, `greptimedb-schema.service`, `greptimedb-envelope.service` and `greptimedb-envelope.timer` (Tasks 2, 4); `opentelemetry-collector.service`, `prometheus-node-exporter.service`, `observability-notify@.service`, stamp directory `/var/lib/observability-notify` (Task 3); the generators `greptimedb-users` (files `users`, public `users-sha256`, `admin-password`, `collector-password`, `perses-password`, `regulator-password`) and `greptimedb-r2` (file `env`) (Task 2); `/run/greptimedb/loaded-users.sha256` written by `greptimedb.service`'s `ExecStartPre` (Task 2); the envelope's `Environment=GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES=3221225472`, its stderr line `FAIL R7.2: memory.peak <peak> >= GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES <threshold>` and its success line `greptimedb-envelope: all checks passed` (Task 4); the databases `fleet`, `devloop`, `agent` (Task 2); the dataset `zroot/root/greptimedb` created by hand in Task 2 (8.3).
- Produces: magnetite running S1 from `origin/main`; the evidence logs above, which Task 7 records in `verify.md` §9; the helper `logs/s1-evidence/gq.sh` (`gq.sh promql DB QUERY`, `gq.sh promql_range DB QUERY START END STEP`, `gq.sh sql DB SQL`), which Task 7 reuses for 9.1.

- [ ] **Step 1: Create the fresh worktree of `origin/main`**

Run from `/Users/crs58/projects/vanixiets`:

```bash
test ! -e /tmp/wt-main || git worktree remove /tmp/wt-main
git fetch -q origin && git worktree add -q --detach /tmp/wt-main origin/main
git -C /tmp/wt-main log --oneline -1
test -f /tmp/wt-main/modules/nixos/greptimedb.nix && test -f /tmp/wt-main/modules/vm-tests/greptimedb-oom-order.nix && echo "tasks 1-5 present"
```

Expected: the first line is the current `origin/main` commit; the last line is `tasks 1-5 present`.
If `git worktree remove` refuses because the old worktree has changes, stop and ask the orchestrator; never pass `--force`.

- [ ] **Step 2: Set the evidence directory**

Run, in the shell used for the rest of this task and Task 7:

```bash
export EV=/Users/crs58/projects/vanixiets/logs/s1-evidence
mkdir -p "$EV"
```

Expected: no output.

- [ ] **Step 3: Confirm the charter v11 amendments (tasks.md 7.1)**

Run:

```bash
cd /tmp/wt-main/docs/notes/development/observability && {
  echo '$ rg -n "v11" charter.md'; rg -n "v11" charter.md
  echo '$ rg -n "v1\.3\.0-alpha\.1" decisions/ADR-002-dashboard-layer.md research'; rg -n "v1\.3\.0-alpha\.1" decisions/ADR-002-dashboard-layer.md research
  echo '$ rg -n "embedded|percli" decisions/ADR-002-dashboard-layer.md'; rg -n "embedded|percli" decisions/ADR-002-dashboard-layer.md
  echo '$ rg -n "no .pkgs/by-name. entry|gRPC disabled|cutover" decisions components'; rg -n "no .pkgs/by-name. entry|gRPC disabled|cutover" decisions components
  echo '$ rg -n "greptimedb-bin|embedsDashboard" decisions/ADR-001-store.md decisions/ADR-007-packaging-placement-and-clan-service.md components/greptimedb.md'; rg -n "greptimedb-bin|embedsDashboard" decisions/ADR-001-store.md decisions/ADR-007-packaging-placement-and-clan-service.md components/greptimedb.md
  echo '$ rg -n "observability-notify" architecture/reference-architecture.md'; rg -n "observability-notify" architecture/reference-architecture.md
} 2>&1 | tee "$EV/7.1-charter-v11.log"; cd /tmp/wt-main
```

Expected:
- `charter.md` shows a v11 entry dated 2026-10-16 naming ADR-002, R1.1, the gRPC bind and the `observability-notify@` move.
- The `v1.3.0-alpha.1` search prints no line claiming `/v1/dashboards` first appears there.
- ADR-002 names the embedded dashboard as the dashboard layer and `percli` as tooling.
- The `no pkgs/by-name entry|gRPC disabled|cutover` search prints no unamended line.
- ADR-001, ADR-007 and `components/greptimedb.md` each show the amended R1.1 clause naming `greptimedb-bin` or `embedsDashboard`.
- `observability-notify` appears under S1 and nowhere under S3.

If any expectation fails, stop: the amendment is missing on `main` and Task 7 cannot tick 7.1.

- [ ] **Step 4: Resolve the deployed paths from the evaluated configuration**

Run from `/tmp/wt-main`:

```bash
{
  for f in regulator-password users-sha256; do
    echo "\$ nix eval --raw .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.$f.path"
    nix eval --raw ".#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.$f.path"; echo
  done
  echo '$ nix eval --raw .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-r2.files.env.path'
  nix eval --raw .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-r2.files.env.path; echo
  echo '$ nix eval --json .#nixosConfigurations.magnetite.config.services.greptimedb.settings.storage'
  nix eval --json .#nixosConfigurations.magnetite.config.services.greptimedb.settings.storage
} 2>&1 | tee "$EV/8.4-paths.log"
```

Expected (secret files follow the existing `omnigraph-r2` path `/run/secrets/vars/per-machine/magnetite/omnigraph-r2/env`):
- `/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password`
- a `/nix/store/...` or `/var/lib/...` path for the public `users-sha256` (record it; Step 8 reads it)
- `/run/secrets/vars/per-machine/magnetite/greptimedb-r2/env`
- the storage object with `"bucket":"sciexp"`, `"root":"projects/vanixiets/observability/store/"`, `"region":"auto"`, `"endpoint":"https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com"`, `"enable_virtual_host_style":false`, `"disable_ec2_metadata":true`

If the regulator or R2 path differs, use the printed path in Steps 9 and 16 in place of the expected one and note the difference in the log.

- [ ] **Step 5: Wait for an empty build queue (tasks.md 8.4)**

Run:

```bash
nixbot-logs queue 2>&1 | tee "$EV/8.4-queue.log"
grep -q 'Queue is empty' "$EV/8.4-queue.log" && echo "deploy allowed" || echo "queue busy: wait and rerun this step"
```

Expected: `Queue is empty on <url>.` followed by `deploy allowed`.
`nixbot-logs` prints the empty-queue line on stderr, which is why the `2>&1` precedes the `tee`.
Rerun this step until it prints `deploy allowed`; a deployment restarts units on the host that runs the evaluator and builds.

- [ ] **Step 6: Deploy magnetite from the worktree**

Run from `/tmp/wt-main`:

```bash
mkdir -p logs
clan machines update magnetite --upload-inputs 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log
cp "$(ls -t logs/magnetite-*.log | head -n1)" "$EV/8.4-clan-update.log"
```

Expected: the update completes with exit status 0 and the log ends with the activation summary, listing `greptimedb.service`, `greptimedb-schema.service`, `opentelemetry-collector.service`, `prometheus-node-exporter.service` and `greptimedb-envelope.timer` among the started units.
If activation reports a failed unit, keep the log and run Step 7 to see which; a failure here is the notifier's first real exercise and should also appear on `fleet-alerts`.

- [ ] **Step 7: Confirm the units are up (tasks.md 8.4)**

Run:

```bash
ssh magnetite.zt '
  echo "\$ systemctl is-active greptimedb opentelemetry-collector"; systemctl is-active greptimedb opentelemetry-collector
  echo "\$ systemctl show greptimedb-schema -p Result -p ExecMainStatus -p ActiveState"; systemctl show greptimedb-schema -p Result -p ExecMainStatus -p ActiveState
  echo "\$ systemctl status greptimedb-schema --no-pager"; systemctl status greptimedb-schema --no-pager
  echo "\$ systemctl is-active prometheus-node-exporter greptimedb-envelope.timer"; systemctl is-active prometheus-node-exporter greptimedb-envelope.timer
  echo "\$ systemctl show -p Result zfs-set-root-greptimedb-quota zfs-set-root-greptimedb-reservation zfs-assert-root-greptimedb-noautosnap"; systemctl show -p Result zfs-set-root-greptimedb-quota zfs-set-root-greptimedb-reservation zfs-assert-root-greptimedb-noautosnap
  echo "\$ systemctl list-units --failed --no-legend"; systemctl list-units --failed --no-legend
' 2>&1 | tee "$EV/8.4-units.log"
```

Expected:
- `active` printed twice for `greptimedb` and `opentelemetry-collector`.
- `Result=success`, `ExecMainStatus=0`; `systemctl status greptimedb-schema` shows `status=0/SUCCESS`.
- `active` twice for the node exporter and the envelope timer.
- `Result=success` three times for the ZFS oneshots.
- No failed units.

- [ ] **Step 8: Confirm the running store loaded the deployed users file**

Run, replacing `USERS_SHA256_PATH` with the public path recorded in Step 4:

```bash
ssh magnetite.zt '
  echo "\$ cat USERS_SHA256_PATH"; cat USERS_SHA256_PATH
  echo "\$ cat /run/greptimedb/loaded-users.sha256"; cat /run/greptimedb/loaded-users.sha256
  echo "\$ stat -c %a /run/greptimedb/loaded-users.sha256"; stat -c %a /run/greptimedb/loaded-users.sha256
' 2>&1 | tee "$EV/8.4-users-hash.log"
```

Expected: both files hold the same 64-hex-digit sha256 and the runtime file's mode is `444`.

- [ ] **Step 9: Write the read helper**

Create `logs/s1-evidence/gq.sh` (git-ignored) with:

```bash
#!/usr/bin/env bash
# Read from the store on magnetite as regulator:ro over 127.0.0.1:4000.
# Usage:
#   gq.sh promql DB QUERY
#   gq.sh promql_range DB QUERY START END STEP
#   gq.sh sql DB SQL
# The password is read with sudo on magnetite and handed to curl through a
# config file descriptor, so it never appears in a process argument list.
set -euo pipefail
ssh magnetite.zt "bash -s -- $(printf '%q ' "$@")" <<'REMOTE'
set -euo pipefail
pw_file=/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password
auth() { printf 'user = "regulator:%s"\n' "$(sudo cat "$pw_file")"; }
base=http://127.0.0.1:4000
case "$1" in
  promql)
    curl -sS -G -K <(auth) -H "x-greptime-db-name: $2" \
      --data-urlencode "query=$3" "$base/v1/prometheus/api/v1/query" ;;
  promql_range)
    curl -sS -G -K <(auth) -H "x-greptime-db-name: $2" \
      --data-urlencode "query=$3" --data-urlencode "start=$4" \
      --data-urlencode "end=$5" --data-urlencode "step=$6" \
      "$base/v1/prometheus/api/v1/query_range" ;;
  sql)
    curl -sS -K <(auth) --data-urlencode "sql=$3" "$base/v1/sql?db=$2" ;;
  *)
    echo "unknown mode: $1" >&2; exit 2 ;;
esac
REMOTE
```

Then run:

```bash
chmod +x "$EV/gq.sh"
"$EV/gq.sh" promql fleet 'up' | jq -r '.status'
```

Expected: `success`.
If the Step 4 regulator path differed, edit `pw_file` before running.

- [ ] **Step 10: Record the dataset's quota and reservation (tasks.md 8.5)**

Run:

```bash
ssh magnetite.zt '
  echo "\$ zfs get quota,reservation zroot/root/greptimedb"; zfs get quota,reservation zroot/root/greptimedb
  echo "\$ zfs get -Hp used,quota zroot/root/greptimedb"; zfs get -Hp used,quota zroot/root/greptimedb
  echo "\$ findmnt -no SOURCE /var/lib/greptimedb"; findmnt -no SOURCE /var/lib/greptimedb
' 2>&1 | tee "$EV/8.5-zfs.log"
```

Expected: `quota 16G` and `reservation 12G`, both with source `local`; `used` well under `17179869184`; `/var/lib/greptimedb` mounted from `zroot/root/greptimedb`.

- [ ] **Step 11: Read `host_name="magnetite"` series through PromQL (tasks.md 8.5)**

Run:

```bash
{
  echo "\$ gq.sh promql fleet 'count by (__name__) ({host_name=\"magnetite\"})'"
  "$EV/gq.sh" promql fleet 'count by (__name__) ({host_name="magnetite"})' \
    | jq -r '.status, (.data.result | length), (.data.result[] | "\(.metric.__name__) \(.value[1])")'
} 2>&1 | tee "$EV/8.5-promql-host-name.log"
```

Expected: `success`, a count above zero, and one line per metric name, including `process_memory_usage_bytes` and `systemd_unit_state`.

Then record the process-name bound, S1's discharge of "at most 30 names per host" until S4's otel-envelope.
Run:

```bash
{
  q1='count(count by (process_executable_name) (process_memory_usage_bytes{host_name="magnetite"}))'
  q2='count(count by (process_executable_name) (count_over_time(process_memory_usage_bytes{host_name="magnetite"}[1h])))'
  for q in "$q1" "$q2"; do
    echo "\$ gq.sh promql fleet '$q'"
    n=$("$EV/gq.sh" promql fleet "$q" | jq -r '.data.result[0].value[1]')
    echo "$n"
    [ -n "$n" ] && [ "$n" != null ] && [ "$n" -ge 1 ] && [ "$n" -le 30 ] && echo "PASS: $n distinct names <= 30" || echo "FAIL: $n distinct names"
  done
} 2>&1 | tee "$EV/8.5-process-name-bound.log"
```

Expected: two `PASS` lines; the first is the instant count (the query as specified), the second counts every name seen in the last hour, which is the bound's actual claim.
An empty or `null` result is a `FAIL`, not a pass, because absent evidence must not discharge the bound.
Task 7 records this log in `verify.md` §9.4.

- [ ] **Step 12: Read `host_name="magnetite"` series through SQL (tasks.md 8.5)**

Run:

```bash
{
  echo "\$ gq.sh sql fleet \"SELECT host_name, count(*) AS points, max(greptime_timestamp) AS latest FROM process_memory_usage_bytes WHERE greptime_timestamp > now() - INTERVAL '1 hour' GROUP BY host_name\""
  "$EV/gq.sh" sql fleet "SELECT host_name, count(*) AS points, max(greptime_timestamp) AS latest FROM process_memory_usage_bytes WHERE greptime_timestamp > now() - INTERVAL '1 hour' GROUP BY host_name" | jq -c '.output[0].records.rows'
} 2>&1 | tee "$EV/8.5-sql-host-name.log"
```

Expected: exactly one row whose first column is `"magnetite"`, with a positive point count and a recent `latest`.

- [ ] **Step 13: Confirm the zram paging series (tasks.md 8.5)**

Run:

```bash
{
  echo "\$ gq.sh promql fleet 'system_paging_usage_bytes{host_name=\"magnetite\",device=\"/dev/zram0\"}'"
  "$EV/gq.sh" promql fleet 'system_paging_usage_bytes{host_name="magnetite",device="/dev/zram0"}' \
    | jq -c '.status, [.data.result[] | {metric, value}]'
} 2>&1 | tee "$EV/8.5-zram-paging.log"
```

Expected: `success` and at least one series carrying `device="/dev/zram0"` (magnetite sets `zramSwap.enable = true`).

- [ ] **Step 14: Confirm no log or trace tables exist in any database (tasks.md 8.5)**

Run:

```bash
{
  q="SELECT table_schema, table_name FROM information_schema.tables WHERE table_name IN ('opentelemetry_logs', 'opentelemetry_traces') OR table_name LIKE '%logs' OR table_name LIKE '%traces%'"
  echo "\$ gq.sh sql fleet \"$q\""
  "$EV/gq.sh" sql fleet "$q" | jq -c '.output[0].records.rows'
  q2="SELECT table_schema, count(*) FROM information_schema.tables WHERE table_schema IN ('fleet', 'devloop', 'agent') GROUP BY table_schema"
  echo "\$ gq.sh sql fleet \"$q2\""
  "$EV/gq.sh" sql fleet "$q2" | jq -c '.output[0].records.rows'
} 2>&1 | tee "$EV/8.5-no-log-trace-tables.log"
```

Expected: the first query returns `[]`; the second shows `fleet` with tables, which proves the regulator can see the catalogue, so the empty first result is not vacuous.
`opentelemetry_logs` and `opentelemetry_traces` are the store's default OTLP log and trace table names (`src/servers/src/otlp/logs.rs:53`, `src/common/catalog/src/consts.rs:223` upstream).

- [ ] **Step 15: Open the embedded dashboard over an SSH tunnel (tasks.md 8.5 record)**

In a second terminal on the workstation, run and leave open:

```bash
ssh -N -L 4000:127.0.0.1:4000 magnetite.zt
```

In the first terminal run:

```bash
{
  echo '$ curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:4000/dashboard/'
  curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4000/dashboard/
} 2>&1 | tee "$EV/8.5-dashboard.log"
open http://127.0.0.1:4000/dashboard/
```

Expected: `200`, and the browser renders GreptimeDB's dashboard.
Append the operator's observation to the log, attributed:

```bash
printf '[operator] %s: dashboard at http://127.0.0.1:4000/dashboard/ rendered over ssh -L 4000:127.0.0.1:4000 magnetite.zt; observed: %s\n' "$(date -u +%FT%TZ)" "<what the page showed, e.g. the query view loaded and a PromQL query for up against fleet returned series>" >> "$EV/8.5-dashboard.log"
```

The `<…>` text is the operator's own description, written at the time; close the tunnel afterwards.

- [ ] **Step 16: Confirm object data reaches R2 (tasks.md 8.5, world assumption A29)**

The store flushes memtables to SST files on `[region_engine.mito] auto_flush_interval = "1h"` (the v1.2.1 default), so run this step at least 70 minutes after `greptimedb.service` started.
Run:

```bash
ssh magnetite.zt 'systemctl show greptimedb -p ActiveEnterTimestamp'
```

When that timestamp is at least 70 minutes old, run:

```bash
{
  echo '$ list s3://sciexp/projects/vanixiets/observability/store/ with the greptimedb-r2 credential'
  ssh magnetite.zt sudo bash -s <<'REMOTE'
set -euo pipefail
set -a; . /run/secrets/vars/per-machine/magnetite/greptimedb-r2/env; set +a
export AWS_ACCESS_KEY_ID="$GREPTIMEDB_STANDALONE__STORAGE__ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$GREPTIMEDB_STANDALONE__STORAGE__SECRET_ACCESS_KEY"
nix run nixpkgs#awscli2 -- s3 ls --recursive --summarize \
  --endpoint-url https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com --region auto \
  s3://sciexp/projects/vanixiets/observability/store/ | tail -n 5
REMOTE
  echo "\$ gq.sh sql fleet \"SELECT sum(sst_size) FROM information_schema.region_statistics\""
  "$EV/gq.sh" sql fleet "SELECT sum(sst_size) FROM information_schema.region_statistics" | jq -c '.output[0].records.rows'
} 2>&1 | tee "$EV/8.5-r2.log"
```

Expected: the listing shows object keys under `projects/vanixiets/observability/store/` and ends with `Total Objects:` above zero; `sum(sst_size)` is above zero.
If the listing is empty or the store logs an S3 error (`journalctl -u greptimedb --no-pager | rg -i 's3|opendal'`), stop and report: the fallback in design D5 (local `File` storage with a quota increase) is a design change for the orchestrator, not a deployment fix.

- [ ] **Step 17: Measure the collector's real `fleet` volume against the queue size (tasks.md 8.5)**

R3.1 sizes the `fleet` sending queue (400 MiB, bytes sizer) from an explicit, unmeasured constant `fleetBytesPerMinute = 256000`, so this step measures the real rate on magnetite.
The measurement stops the store for ten minutes, so the queue fills with exactly the bytes a store outage accumulates.
First resolve the collector's internal telemetry endpoint, its exporter ids and the `file_storage` directory, from `/tmp/wt-main`:

```bash
{
  echo '$ nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.service.telemetry'
  nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.service.telemetry
  echo '$ nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.exporters --apply builtins.attrNames'
  nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.exporters --apply builtins.attrNames
  echo '$ nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.extensions'
  nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.extensions
  echo '$ nix eval --json .#lib.otelCollectorSchema'
  nix eval --json .#lib.otelCollectorSchema
} 2>&1 | tee "$EV/8.5-queue-rate.log"
```

Expected: telemetry metrics either unset (the collector's default pull endpoint `127.0.0.1:8888`) or an explicit loopback address, which replaces `127.0.0.1:8888` below; three exporters, one per database, the `fleet` one containing `fleet` in its id; one `file_storage` extension with its `directory`.
Confirm the envelope timer will not fire during the outage, so R6.4's readiness probe does not post a notice:

```bash
ssh magnetite.zt 'systemctl list-timers greptimedb-envelope.timer --no-pager' | tee -a "$EV/8.5-queue-rate.log"
```

Expected: `NEXT` is at least 20 minutes away; otherwise wait until the run has passed.
Then run, replacing `FILE_STORAGE_DIR` with the directory printed above:

```bash
snap() {
  ssh magnetite.zt '
    date -u +%FT%TZ
    curl -s http://127.0.0.1:8888/metrics | grep -E "^otelcol_exporter_(queue_size|queue_capacity|sent_metric_points_total|send_failed_metric_points_total)\{" | grep fleet
    sudo du -sb FILE_STORAGE_DIR
  '
}
{
  echo "# before stop"; snap
  echo '$ sudo systemctl stop greptimedb'; ssh magnetite.zt 'sudo systemctl stop greptimedb; systemctl is-active greptimedb || true'
  sleep 600
  echo "# after 600 s stopped"; snap
  echo '$ sudo systemctl start greptimedb'; ssh magnetite.zt 'sudo systemctl start greptimedb; systemctl is-active greptimedb'
  sleep 300
  echo "# 300 s after start"; snap
} 2>&1 | tee -a "$EV/8.5-queue-rate.log"
```

Expected: before the stop, `otelcol_exporter_queue_size` for the `fleet` exporter is near `0` and `otelcol_exporter_queue_capacity` is `419430400`; after ten minutes stopped, `queue_size` has grown, in bytes because the queue uses the bytes sizer; five minutes after the start it is back near `0`, showing the queue drained into the store; `greptimedb` is `inactive` while stopped and `active` after.
Compute and record the rate:

```bash
{
  read -r -p 'fleet queue_size before stop (bytes): ' q0
  read -r -p 'fleet queue_size after 600 s (bytes): ' q1
  per_min=$(( (q1 - q0) / 10 )); per_day=$(( per_min * 1440 ))
  echo "measured fleetBytesPerMinute=$per_min"
  echo "measured 24h volume=$per_day bytes; queue size=419430400 bytes (400 MiB); assumed constant 256000 B/min gives 368640000 bytes"
  [ "$per_day" -le 419430400 ] && echo "PASS: 24 h of fleet fits the 400 MiB queue" || echo "FAIL: 24 h of fleet exceeds the 400 MiB queue"
} 2>&1 | tee -a "$EV/8.5-queue-rate.log"
```

Expected: `PASS`.
The `du -sb` delta of `FILE_STORAGE_DIR` and the growth in `otelcol_exporter_sent_metric_points_total` (points sent in the five minutes after the start) are recorded alongside as cross-checks; bbolt preallocates, so `du` bounds the on-disk cost from above rather than measuring the rate.
If the result is `FAIL`, stop before Task 7: the measured `fleetBytesPerMinute` replaces `256000` and the `fleet` queue size is raised to cover 24 h at that rate (keeping the total under the collector's 512 MiB envelope or amending that envelope explicitly), in a follow-up commit through its own pull request that lands before `verify.md` is created.
If the rate is `0`, the measurement is void (nothing was queued), not a pass; check the exporter id and rerun.

- [ ] **Step 18: Record the R7.2 baseline (tasks.md 8.6)**

Run:

```bash
{
  echo '$ cat /sys/fs/cgroup/system.slice/greptimedb.service/memory.peak'
  ssh magnetite.zt 'cat /sys/fs/cgroup/system.slice/greptimedb.service/memory.peak'
  echo '$ systemctl show greptimedb-envelope -p Environment -p Result'
  ssh magnetite.zt 'systemctl show greptimedb-envelope -p Environment -p Result'
  echo '$ sudo ls -la /var/lib/observability-notify'
  ssh magnetite.zt 'sudo ls -la /var/lib/observability-notify'
  echo "\$ curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=10m'"
  curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=10m' | jq -c 'select(.event == "message") | {time, message}'
  echo "T0=$(date -u +%FT%TZ)"
} 2>&1 | tee "$EV/8.6-baseline.log"
```

Expected: a `memory.peak` value in bytes above `1`; `Environment=` containing `GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES=3221225472` and `Result=success`; no stamp file `/var/lib/observability-notify/greptimedb-envelope.service`; no recent `fleet-alerts` message about `greptimedb-envelope.service`.
The workstation is a ZeroTier member; `-k` matches `ntfy-send`'s own `-sfk` (`pkgs/by-name/ntfy-send`, moved in Task 1).
Steps 19–21 must complete within ten minutes of this step so each `since=10m` poll covers the whole experiment.

- [ ] **Step 19: Force R7.2 to fail and observe one notice (tasks.md 8.6)**

Run:

```bash
{
  echo '$ printf "[Service]\nEnvironment=GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES=1\n" | sudo systemctl edit --runtime --stdin --drop-in=r7-2-force greptimedb-envelope'
  ssh magnetite.zt 'printf "[Service]\nEnvironment=GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES=1\n" | sudo systemctl edit --runtime --stdin --drop-in=r7-2-force greptimedb-envelope'
  echo '$ sudo systemctl start greptimedb-envelope'
  ssh magnetite.zt 'sudo systemctl start greptimedb-envelope; echo "exit=$?"'
  sleep 15
  echo '$ systemctl status greptimedb-envelope --no-pager'
  ssh magnetite.zt 'systemctl status greptimedb-envelope --no-pager; journalctl -u greptimedb-envelope -n 20 --no-pager'
  echo '$ sudo ls -la /var/lib/observability-notify'
  ssh magnetite.zt 'sudo ls -la /var/lib/observability-notify'
  echo "\$ curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=10m'"
  curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=10m' | jq -c 'select(.event == "message") | {time, message}'
} 2>&1 | tee "$EV/8.6-forced-failure.log"
```

Expected:
- `exit=1` from `systemctl start`, and `systemctl status` showing `Active: failed` with the drop-in `/run/systemd/system/greptimedb-envelope.service.d/r7-2-force.conf` listed.
- The journal contains `FAIL R7.2: memory.peak <peak> >= GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES 1`.
- The stamp file `/var/lib/observability-notify/greptimedb-envelope.service`, written by the template's `ExecStartPost` after a successful post.
- Exactly one `fleet-alerts` message, with body `FAILED greptimedb-envelope.service on magnetite`.

`systemctl edit --stdin` exists from systemd 256; magnetite runs systemd 261.3 (`nix eval --raw .#nixosConfigurations.magnetite.config.systemd.package.version`).

- [ ] **Step 20: Start it again and observe no second notice (tasks.md 8.6)**

Run:

```bash
{
  echo '$ sudo systemctl start greptimedb-envelope'
  ssh magnetite.zt 'sudo systemctl start greptimedb-envelope; echo "exit=$?"'
  sleep 15
  echo '$ systemctl show greptimedb-envelope -p Result -p ExecMainStatus'
  ssh magnetite.zt 'systemctl show greptimedb-envelope -p Result -p ExecMainStatus'
  echo '$ journalctl -u "observability-notify@greptimedb-envelope.service" -n 20 --no-pager'
  ssh magnetite.zt 'journalctl -u "observability-notify@greptimedb-envelope.service" -n 20 --no-pager'
  echo "\$ curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=10m'"
  curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=10m' | jq -c 'select(.event == "message") | {time, message}'
} 2>&1 | tee "$EV/8.6-repeat-failure.log"
```

Expected: `exit=1`, `Result=exit-code`, `ExecMainStatus=1`; the notifier journal shows the second `observability-notify@greptimedb-envelope.service` run skipped by its unmet `ExecCondition=` because the stamp exists; the poll still returns exactly the one message from Step 19.

- [ ] **Step 21: Remove the drop-in and observe one `RESOLVED` notice (tasks.md 8.6)**

Run:

```bash
{
  echo '$ sudo systemctl revert greptimedb-envelope'
  ssh magnetite.zt 'sudo systemctl revert greptimedb-envelope'
  echo '$ systemctl show greptimedb-envelope -p Environment -p DropInPaths'
  ssh magnetite.zt 'systemctl show greptimedb-envelope -p Environment -p DropInPaths'
  echo '$ sudo systemctl start greptimedb-envelope'
  ssh magnetite.zt 'sudo systemctl start greptimedb-envelope; echo "exit=$?"'
  sleep 15
  echo '$ systemctl status greptimedb-envelope --no-pager'
  ssh magnetite.zt 'systemctl status greptimedb-envelope --no-pager; journalctl -u greptimedb-envelope -n 5 --no-pager'
  echo '$ sudo ls -la /var/lib/observability-notify'
  ssh magnetite.zt 'sudo ls -la /var/lib/observability-notify'
  echo "\$ curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=10m'"
  curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=10m' | jq -c 'select(.event == "message") | {time, message}'
} 2>&1 | tee "$EV/8.6-resolved.log"
```

Expected:
- `revert` reports removing `/run/systemd/system/greptimedb-envelope.service.d/r7-2-force.conf`; `Environment=` is back to `GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES=3221225472` and `DropInPaths=` no longer lists the runtime drop-in.
- `exit=0`; `systemctl status` shows `status=0/SUCCESS` and the journal shows `greptimedb-envelope: all checks passed`.
- No stamp file `/var/lib/observability-notify/greptimedb-envelope.service`; the `RESOLVED` `ExecStopPost=` removes it only when `SERVICE_RESULT=success`.
- The poll returns exactly two messages: `FAILED greptimedb-envelope.service on magnetite` from Step 19 and `RESOLVED greptimedb-envelope.service on magnetite`.

If Step 21 itself fails on another assertion (for example R7.2 against the real peak), record the line and stop; the store's real peak above `MemoryHigh` is R7.2 evidence for the orchestrator (design risk "real peak RSS is unmeasured"), not something to tune here.

- [ ] **Step 22: Remove the worktree**

Run from `/Users/crs58/projects/vanixiets`:

```bash
cp /tmp/wt-main/logs/magnetite-*.log "$EV/"
git worktree remove /tmp/wt-main
ls "$EV"
```

Expected: the listing shows `gq.sh`, the `magnetite-*.log` deployment log and every evidence file named under **Files**.

- [ ] **Step 23: No commit**

This task changes no repository file and opens no pull request.
The `tasks.md` ticks for 7.1, 8.4, 8.5 and 8.6 are made in Task 7's change, together with `verify.md`, which records this task's evidence.

---

### Task 7: Integration verification and change close-out

This task closes the loop on magnetite (tasks.md 9.1), creates `verify.md` once (firing In Progress → In Review for CAM-68), passes the two In Review sub-gates (roborev, then documenter), writes the retrospective, archives the change with its spec sync and Linear document mirror, and fires In Review → Done.
All of it lands as one change and one pull request (pull request 6); per the openspec-linear-sync lifecycle, archive precedes the pull request, so the merged diff carries the complete archived cycle.

**Files:**
- Create: `openspec/changes/stand-up-greptimedb-on-magnetite/verify.md`
- Create: `openspec/changes/stand-up-greptimedb-on-magnetite/retrospective.md`
- Modify: `openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md` (tick 7.1, 8.4, 8.5, 8.6, 9.1)
- Modify: `openspec/changes/stand-up-greptimedb-on-magnetite/proposal.md` (frontmatter sync ledger only)
- Create (by spec sync): `openspec/specs/host-metrics-collection/spec.md`, `openspec/specs/telemetry-store/spec.md`, `openspec/specs/telemetry-store-interface/spec.md`
- Modify (by spec sync): `openspec/specs/world-assumptions/spec.md` (A29–A33 added, the grounded-vocabulary requirement modified)
- Move (by archive): `openspec/changes/stand-up-greptimedb-on-magnetite/` → `openspec/changes/archive/<YYYY-MM-DD>-stand-up-greptimedb-on-magnetite/`
- Modify: `openspec/linear.yaml` (`projects."fleet-observability".archive_documents` gains the three new capability document ids)
- Create (git-ignored evidence): `logs/s1-evidence/9.1-process-memory.log`, `logs/s1-evidence/9.1-unit-state.log`, `logs/s1-evidence/9.1-owner-aliases.log`, `logs/s1-evidence/9.1-envelope-scheduled.log`, `logs/s1-evidence/9.1-restart-no-gap.log`, `logs/s1-evidence/roborev-out.json`

**Interfaces:**
- Consumes: Task 6's evidence under `logs/s1-evidence/` and its helper `logs/s1-evidence/gq.sh`; the deployed units `greptimedb.service`, `greptimedb-envelope.service`/`.timer`, `opentelemetry-collector.service`, `observability-notify@.service`; the metrics `process_memory_usage_bytes`, `systemd_unit_state` with label `host_name`; CAM-68 in Linear team `CAM`, project `fleet-observability` (slugId `aeed302bea3b`), workspace `cameronraysmith`; proposal.md's ledger as left by Task 1 (`linear_story_state: In Progress`, `last_synced_state: In Progress`).
- Produces: `verify.md` with the schema's §1–§8 and the evidence ledger §9–§10; the archived change; four main specs under `openspec/specs/`; Linear documents `OpenSpec: host-metrics-collection`, `OpenSpec: telemetry-store`, `OpenSpec: telemetry-store-interface` in project `fleet-observability`, and the existing `OpenSpec: world-assumptions` document (`a7f9d24e-8fe2-4120-9ba0-e7d4d3a23fe1`) updated in place; CAM-68 in `Done`.

- [ ] **Step 1: Confirm Task 6's evidence is present**

Run from `/Users/crs58/projects/vanixiets`:

```bash
export EV=/Users/crs58/projects/vanixiets/logs/s1-evidence
ls "$EV"
rg -c 'FAIL R7.2' "$EV/8.6-forced-failure.log"; rg -c 'all checks passed' "$EV/8.6-resolved.log"
```

Expected: every Task 6 evidence file listed, and `1` or more from each `rg -c`.

- [ ] **Step 2: Query process memory for the last hour (tasks.md 9.1)**

Run:

```bash
{
  echo "\$ gq.sh promql fleet 'count_over_time(process_memory_usage_bytes{host_name=\"magnetite\"}[1h])'"
  "$EV/gq.sh" promql fleet 'count_over_time(process_memory_usage_bytes{host_name="magnetite"}[1h])' \
    | jq -r '.status, (.data.result | length), (.data.result[] | "\(.metric.process_executable_name) \(.value[1])")'
} 2>&1 | tee "$EV/9.1-process-memory.log"
```

Expected: `success`, between 1 and 30 series (the per-host cap), and each series with a count near 60 (one point a minute for an hour), including `greptime` and `otelcol-contrib`.

- [ ] **Step 3: Query unit state for the last hour (tasks.md 9.1)**

Run:

```bash
{
  echo "\$ gq.sh promql fleet 'count_over_time(systemd_unit_state{host_name=\"magnetite\"}[1h])'"
  "$EV/gq.sh" promql fleet 'count_over_time(systemd_unit_state{host_name="magnetite"}[1h])' \
    | jq -r '.status, (.data.result | length), ([.data.result[].metric.systemd_unit_name] | unique | join(" "))'
} 2>&1 | tee "$EV/9.1-unit-state.log"
```

Expected: `success`, a positive series count, and unit names drawn only from the allow-list `nix eval --json .#lib.otelCollectorSchema.systemdUnits` prints, including `greptimedb.service` and `opentelemetry-collector.service`.

Then confirm the owner-to-alias transform (ADR-003 item 17) on the real host.
Run:

```bash
{
  echo '$ systemctl list-units "omnigent-host-*" --all --plain --no-legend'
  owners=$(ssh magnetite.zt 'systemctl list-units "omnigent-host-*" --all --plain --no-legend' | awk '{print $1}' | sed -n 's/^omnigent-host-\(.*\)\.service$/\1/p')
  echo "$owners"
  echo '$ nix eval --json .#lib.otelCollectorSchema.ownerAliases'
  aliases=$(nix eval --json .#lib.otelCollectorSchema.ownerAliases); echo "$aliases"
  for o in $owners; do
    a=$(jq -r --arg o "$o" '.[$o] // empty' <<<"$aliases")
    [ -n "$a" ] && echo "PASS: owner $o has alias $a" || echo "FAIL: owner $o has no alias"
    for m in systemd_unit_state systemd_service_restarts_total; do
      q="count_over_time($m{host_name=\"magnetite\", systemd_unit_name=~\".*$o.*\"}[1h])"
      echo "\$ gq.sh promql fleet '$q'"
      n=$("$EV/gq.sh" promql fleet "$q" | jq -r '.status + " " + (.data.result | length | tostring)')
      [ "$n" = "success 0" ] && echo "PASS: no stored $m systemd_unit_name contains $o" || echo "FAIL: $m $n"
    done
    q="count_over_time(systemd_unit_state{host_name=\"magnetite\", systemd_unit_name=~\".*$a.*\"}[1h])"
    echo "\$ gq.sh promql fleet '$q'"
    n=$("$EV/gq.sh" promql fleet "$q" | jq -r '.status + " " + (.data.result | length | tostring)')
    [ "${n#success }" -ge 1 ] 2>/dev/null && echo "PASS: alias $a stored ($n)" || echo "FAIL: alias $a not stored ($n)"
  done
} 2>&1 | tee "$EV/9.1-owner-aliases.log"
```

Run it from `/Users/crs58/projects/vanixiets` with `origin/main` checked out in the evaluated flake (the development join carries it).
Expected: the owners deployed today are `cameron` and `janettesmith` (`nix eval --json .#nixosConfigurations.magnetite.config.systemd.services --apply builtins.attrNames` lists `omnigent-host-cameron` and `omnigent-host-janettesmith`); four `PASS` lines per owner and no `FAIL`.
The owner queries match `systemd_unit_name` on both systemd receiver metrics, `systemd_unit_state` and `systemd_service_restarts_total`, so an owner name surviving the transform in either fails the check; the alias query requires the aliased `systemd_unit_state` series to be present, so an empty store cannot pass vacuously.

- [ ] **Step 4: Observe the next scheduled envelope run (tasks.md 9.1)**

Run:

```bash
ssh magnetite.zt 'systemctl list-timers greptimedb-envelope.timer --no-pager'
```

Wait until the `NEXT` time shown has passed by at least two minutes, then run:

```bash
{
  echo '$ systemctl list-timers greptimedb-envelope.timer --no-pager'
  ssh magnetite.zt 'systemctl list-timers greptimedb-envelope.timer --no-pager'
  echo '$ systemctl status greptimedb-envelope --no-pager'
  ssh magnetite.zt 'systemctl status greptimedb-envelope --no-pager'
  echo '$ systemctl show greptimedb-envelope -p Result -p ExecMainStatus -p ExecMainExitTimestamp'
  ssh magnetite.zt 'systemctl show greptimedb-envelope -p Result -p ExecMainStatus -p ExecMainExitTimestamp'
  echo '$ journalctl -u greptimedb-envelope --since "-10min" --no-pager'
  ssh magnetite.zt 'journalctl -u greptimedb-envelope --since "-10min" --no-pager'
} 2>&1 | tee "$EV/9.1-envelope-scheduled.log"
```

Expected: `LAST` equals the earlier `NEXT`; `Result=success`, `ExecMainStatus=0`, an `ExecMainExitTimestamp` matching the scheduled time; the journal shows `greptimedb-envelope: all checks passed` triggered by the timer, not by a manual start.

- [ ] **Step 5: Restart the store and confirm no gap in `fleet` (tasks.md 9.1)**

Run:

```bash
T0=$(date +%s); echo "T0=$T0" | tee "$EV/9.1-restart-no-gap.log"
ssh magnetite.zt 'sudo systemctl restart greptimedb; systemctl is-active greptimedb' 2>&1 | tee -a "$EV/9.1-restart-no-gap.log"
```

Expected: `active`.
Wait 15 minutes, so the collector's `file_storage` queue has drained the interval it held while the store was down, then run:

```bash
{
  q='count(count_over_time(systemd_unit_state{host_name="magnetite"}[2m]))'
  echo "\$ gq.sh promql_range fleet '$q' $((T0 - 600)) $((T0 + 900)) 60"
  "$EV/gq.sh" promql_range fleet "$q" "$((T0 - 600))" "$((T0 + 900))" 60 \
    | jq -c '.status, (.data.result[0].values | length), ([.data.result[0].values[][1] | tonumber] | {min: min, max: max})'
  echo '$ systemctl show greptimedb -p ActiveEnterTimestamp -p NRestarts'
  ssh magnetite.zt 'systemctl show greptimedb -p ActiveEnterTimestamp -p NRestarts'
} 2>&1 | tee -a "$EV/9.1-restart-no-gap.log"
```

Expected: `success`, `26` points (every minute from ten minutes before the restart to fifteen after), and `min` equal to `max`, so every two-minute window across the restart holds samples for the same number of unit series.
A missing point or a lower `min` is a gap; record it and stop, because the design's survival claim (R3.1 queue clause, the container test's restart case) would then be contradicted on the real host.

- [ ] **Step 6: Run the verify precheck**

Run from `/Users/crs58/projects/vanixiets`:

```bash
git log --oneline $(git merge-base HEAD origin/main 2>/dev/null || git merge-base HEAD origin/master 2>/dev/null)..HEAD | wc -l
tasks_file=$(openspec status --change "stand-up-greptimedb-on-magnetite" --json | jq -r '.artifactPaths.tasks.existingOutputPaths[0] // empty')
[ -n "$tasks_file" ] && grep -c '^- \[x\]' "$tasks_file"
git log --oneline origin/main -- pkgs/by-name/greptimedb-bin modules/nixos/greptimedb.nix modules/clan/services/otel-collector modules/checks/greptimedb-envelope.nix modules/checks/otel-collector-config.nix modules/vm-tests/greptimedb-pipeline.nix modules/vm-tests/greptimedb-oom-order.nix
```

Expected: the first count is at least `1` (`HEAD` is the development join, one commit ahead of `origin/main`); the second is the number of items Tasks 1–5 ticked (at least `1`); the last command lists the Task 1–5 commits on `origin/main`, which are the implementation evidence because each task landed as its own pull request.
If either count is `0`, stop: apply has not produced reviewable changes.

- [ ] **Step 7: Create the change**

Run:

```bash
jj new --no-edit -r main@origin -m 'docs(observability): verify and archive S1 greptimedb on magnetite'
```

Expected: `Created new commit <change-id> ...`; note `<change-id>` as `VERIFY` for the squash steps below.
The orchestrator adds `VERIFY` as a parent of the development join; Step 14 waits for that.

- [ ] **Step 8: Write `verify.md` in the working copy**

Invoke the `openspec-verify-change` skill for `stand-up-greptimedb-on-magnetite`; it renders the template from `openspec instructions verify --change stand-up-greptimedb-on-magnetite --json`.
Fill §1–§8 by running the instruction's checks:
- §1: `openspec validate --all --json`, pasting the `summary` totals.
- §2: the unchecked items; after Step 9 only none should remain.
- §3: one row per path from `openspec status --change stand-up-greptimedb-on-magnetite --json | jq -r '.artifactPaths.specs.existingOutputPaths[]'`, all `pending sync` before archive (`host-metrics-collection`, `telemetry-store`, `telemetry-store-interface` new; `world-assumptions` adds A29–A33 and modifies one requirement).
- §4: sample D3, D4, D6, D10, D12 against their requirements.
- §5: the commit range is the Task 1–5 commits listed in Step 6.
- §6: `ls docs/superpowers/specs/*.md 2>/dev/null`.
- §7: plan.md rows marked `[~]`, if any, each with its covering automated test.
- §8: the instruction's 8a designation lint, 8b discharge table over every ADDED and MODIFIED requirement (each `Discharges:` clause in `tasks.md` names its requirement), and 8c alphabet check.

Then append the evidence ledger after §8 and before `## Overall Decision`, using exactly these headings and the opening lines below, and pasting each named log's commands and outputs verbatim as a fenced `text` block under its heading:

```markdown
## 9. Deployment record

Sections 9 and 10 are the evidence ledger that `tasks.md` 8.3–8.6 and 9.1 require this file to hold.
`[operator]` marks an observation only the operator could make; every other entry gives the command and its output.

### 9.1 Dataset created by hand (tasks.md 8.3)
<!-- logs/s1-evidence/8.3-zfs-create.log -->

### 9.2 Charter v11 amendments present (tasks.md 7.1)
<!-- logs/s1-evidence/7.1-charter-v11.log -->

### 9.3 Deployment from origin/main (tasks.md 8.4)
<!-- logs/s1-evidence/8.4-paths.log, 8.4-queue.log, the tail of 8.4-clan-update.log, 8.4-units.log, 8.4-users-hash.log -->

### 9.4 Deployment-time items (tasks.md 8.5)
<!-- 8.5-r2.log (A29), 8.5-queue-rate.log, 8.5-zfs.log, 8.5-zram-paging.log, 8.5-promql-host-name.log, 8.5-process-name-bound.log, 8.5-sql-host-name.log, 8.5-no-log-trace-tables.log, 8.5-dashboard.log -->

### 9.5 R7.2 shown able to fail, with one notice and one RESOLVED (tasks.md 8.6)
<!-- 8.6-baseline.log, 8.6-forced-failure.log, 8.6-repeat-failure.log, 8.6-resolved.log -->

## 10. Integration verification (tasks.md 9.1)

### 10.1 Process memory and unit state from the last hour
<!-- 9.1-process-memory.log, 9.1-unit-state.log, 9.1-owner-aliases.log -->

### 10.2 The next scheduled envelope run
<!-- 9.1-envelope-scheduled.log -->

### 10.3 No gap in fleet across a store restart
<!-- 9.1-restart-no-gap.log -->

### 10.4 The failure notice and its RESOLVED pair
<!-- the two fleet-alerts messages from 8.6-resolved.log, quoted with their times -->
```

Each HTML comment names the logs to paste in its place; replace each comment with those logs' contents and delete the comment.
Before pasting, check every log for credential values: `rg -n '[0-9a-f]{32,}' "$EV"/*.log` must print only the sha256 lines of `8.4-users-hash.log`, which are public.
Check `(pass) PASS` when every section holds and §2 has no open item, `(warn) PASS WITH WARNINGS` with the warning named when §4 or §8 records drift, and `(fail) FAIL` when any 8.x or 9.1 expectation failed.

- [ ] **Step 9: Tick the items this task and Task 6 discharged**

In `openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md`, change `- [ ]` to `- [x]` at the start of items 7.1, 8.4, 8.5, 8.6 and 9.1, and nothing else.
Run:

```bash
rg -n '^- \[ \]' openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md
```

Expected: no output; every item is now ticked (Tasks 1–5 ticked theirs; Task 2 ticked 8.1–8.3).
If a line prints, record it in `verify.md` §2 with its reason.

- [ ] **Step 10: Validate**

Run:

```bash
openspec validate --all --json 2>&1 | tee logs/openspec-validate-$(date +%Y%m%d-%H%M%S).log | jq -c '.summary.totals'
```

Expected: `"failed":0`; the totals match what §1 records.

- [ ] **Step 11: Fire In Progress → In Review for CAM-68**

Run:

```bash
linear auth whoami --workspace cameronraysmith
CUR=$(linear issue view CAM-68 --json --workspace cameronraysmith | jq -r '.state.name'); echo "$CUR"
```

Expected: `whoami` confirms the `cameronraysmith` workspace; `CUR` is `In Progress`.
Proceed only if `CUR` is `Backlog`, `Todo` or `In Progress` (strictly behind In Review); if it is `In Review` or `Done`, skip to Step 12 and record the no-op in the ledger.
Run:

```bash
linear issue update CAM-68 --state "In Review" --workspace cameronraysmith
printf 'S1 is deployed on magnetite and verify.md records the deployment and closed-loop evidence. The change is ready for roborev and documenter review.\n' > /tmp/cam68-c.md
linear issue comment add CAM-68 --body-file /tmp/cam68-c.md --workspace cameronraysmith
```

Expected: both commands succeed.
A `NotFoundError` from `issue update` means team `CAM` has no `In Review` state; record it as a dropped write in Step 12 and leave the issue In Progress.

- [ ] **Step 12: Update the sync ledger in proposal.md**

In the frontmatter of `openspec/changes/stand-up-greptimedb-on-magnetite/proposal.md`, set `linear_story_state: In Review`, `last_synced_state: In Review`, `last_synced_at:` to the output of `date -u +%FT%TZ`, and append one `attempt_log` entry in the existing flow style:

```yaml
  - { at: "<the same timestamp>", transition: "In Progress->In Review", outcome: "posted", note: "T3 verify.md created; deployment and 9.1 evidence recorded" }
```

If Step 11 dropped the write, use `outcome: "dropped"` with the error text in `note`, and leave `linear_story_state` and `last_synced_state` at `In Progress`.
`review_round` stays `0`.

- [ ] **Step 13: Commit the verification**

Run:

```bash
jj squash --from @ --into VERIFY --keep-emptied --use-destination-message -- \
  openspec/changes/stand-up-greptimedb-on-magnetite/verify.md \
  openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md \
  openspec/changes/stand-up-greptimedb-on-magnetite/proposal.md
jj log -r VERIFY --no-graph -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"' --stat
```

Expected: `VERIFY` shows the three files.
The orchestrator rebases the development join onto `VERIFY`, pushes and owns the pull request; do not push.

- [ ] **Step 14: Wait for `VERIFY` in the working copy**

Run:

```bash
jj log -r 'VERIFY & ::@' --no-graph -T 'change_id.short() ++ "\n"'
test -f openspec/changes/stand-up-greptimedb-on-magnetite/verify.md && echo present
```

Expected: the change id, then `present`.
Until the orchestrator has added `VERIFY` to the join, the squash has moved `verify.md` out of the working copy; do not recreate it.

- [ ] **Step 15: roborev sub-gate (codex review of S1's merged implementation)**

S1's code landed in five pull requests on `main`, so roborev reviews the S1 paths between the parent of Task 1's first commit and `origin/main`.
Run:

```bash
S1_PATHS='pkgs/by-name/greptimedb-bin pkgs/by-name/ntfy-send modules/home/tools/commands/system/ntfy-send.nix modules/apps/updates.nix modules/nixos/greptimedb.nix modules/nixos/nixbot.nix modules/machines/nixos/magnetite modules/clan/services/otel-collector modules/clan/inventory/services/otel-collector.nix modules/checks/greptimedb-envelope.nix modules/checks/otel-collector-config.nix modules/vm-tests/greptimedb-pipeline.nix modules/vm-tests/greptimedb-oom-order.nix modules/README.md'
FIRST=$(git log --reverse --format=%H origin/main -- pkgs/by-name/greptimedb-bin | head -n1)
BASE=$(git rev-parse "$FIRST^"); TIP=$(git rev-parse origin/main)
git cat-file -t "$BASE"
git cat-file -t "$TIP"
git diff --stat "$BASE" "$TIP" -- $S1_PATHS | tail -n1
```

Expected: `commit` twice and a diffstat summary line.
Write the output schema from `skill://agentic-planning-development-workflow/references/codex-review.md` ("The output schema") to `/tmp/roborev-schema.json`, then run:

```bash
WRAPPER_PROMPT=$(printf 'You are reviewing a single change set as a code reviewer from a different model family than the author.\n\nObtain the change set by running exactly these two commands and review ONLY their output:\n\n    git diff %s %s -- %s\n    git log --no-patch %s..%s -- %s\n\nThe first is the change'"'"'s diff; the second is the in-range commit messages that state what the\nchange claims to accomplish. The design it implements is openspec/changes/stand-up-greptimedb-on-magnetite/design.md.\n\nDo not inspect uncommitted or working-copy changes, the HEAD commit, the index, or any commit\noutside the range. Reviewing anything outside the output of those two commands and the design is an error.\n\nReview for two things:\n  1. Correctness bugs in the diff.\n  2. Spec and scope discipline: does the change accomplish what its commit messages claim,\n     no more and no less?\n\nSet `overall_correctness` to EXACTLY one of the enum values "correct" or "incorrect", with no other phrasing.\n\nYour final message MUST be a single JSON object matching the provided output schema, and nothing else.\n' "$BASE" "$TIP" "$S1_PATHS" "$BASE" "$TIP" "$S1_PATHS")
printf '%s' "$WRAPPER_PROMPT" \
  | codex exec -C /Users/crs58/projects/vanixiets -s read-only -m gpt-5.5 \
      -c model_reasoning_effort=xhigh \
      --output-schema /tmp/roborev-schema.json \
      -o "$EV/roborev-out.json" 2>&1 | tee logs/roborev-s1-$(date +%Y%m%d-%H%M%S).log
jq -r '.overall_correctness, (.findings | sort_by(.priority)[] | "P\(.priority) \(.code_location) \(.title)")' "$EV/roborev-out.json"
```

Expected: `correct` or `incorrect`, then the findings sorted by priority.
The level is `xhigh` because this review gates the archive; on a contested verdict run panel mode (K=3) as the runbook describes.
Present the findings to the human; P0 and P1 with `incorrect` are the recommended-blocking set.
Post a summary of this run's verdict, at most two sentences, written from the actual result:

```bash
printf '%s\n' "<this run's verdict and recommended-blocking count, two sentences at most; full findings kept in logs/s1-evidence/roborev-out.json>" > /tmp/cam68-c.md
linear issue comment add CAM-68 --body-file /tmp/cam68-c.md --workspace cameronraysmith
```

If the human approves, continue to Step 16.
If the human re-queues: in `verify.md` check `- [x] (fail) FAIL` under Overall Decision; in proposal.md set `review_round` to its value plus one, `linear_story_state` and `last_synced_state` to `In Progress`, and append `{ at: "<iso>", transition: "In Review->In Progress", outcome: "posted", note: "roborev re-queue: <chosen findings>" }`; run `linear issue update CAM-68 --state "In Progress" --workspace cameronraysmith`; squash `verify.md` and `proposal.md` into `VERIFY` as in Step 13; the chosen findings become fix tasks for the orchestrator, after which verify re-runs from Step 8.
When `review_round` would exceed `max_review_rounds` (3), post one escalation comment instead and stop.

- [ ] **Step 16: documenter sub-gate**

Ask the human to review `verify.md`, the decision records amended in charter v11, `modules/README.md`'s on-demand lane entries (Task 5) and the change's design.md for agreement with what was deployed.
Record the outcome in `verify.md` under `**Next step**:` as one line: `documenter: approved by <name> on <date>` or the rejection with its reason.
A rejection re-queues exactly as in Step 15.

- [ ] **Step 17: Write the retrospective**

Run:

```bash
verify_file=$(openspec status --change "stand-up-greptimedb-on-magnetite" --json | jq -r '.artifactPaths.verify.existingOutputPaths[0] // empty')
test -n "$verify_file" && test -f "$verify_file" && ! grep -q '^- \[x\] (fail) FAIL' "$verify_file" && echo "retrospective allowed"
openspec instructions retrospective --change stand-up-greptimedb-on-magnetite --json | jq -r '.instruction'
```

Expected: `retrospective allowed`, then the instruction.
Invoke `openspec-continue-change` for the `retrospective` artifact and write `openspec/changes/stand-up-greptimedb-on-magnetite/retrospective.md` from the evidence in `verify.md`, following the printed instruction; every undischarged row of §8b and every real gap of §7 appears in it with a follow-up.

- [ ] **Step 18: Archive readiness**

Run:

```bash
openspec status --change stand-up-greptimedb-on-magnetite --json | jq -c '[.artifacts[] | {id, status}]'
openspec list --json | jq -c '.changes[] | select(.name == "stand-up-greptimedb-on-magnetite") | {totalTasks, completedTasks}'
planning_root=$(openspec status --change "stand-up-greptimedb-on-magnetite" --json | jq -r 'select(.planningHome.kind=="repo") | .planningHome.root'); echo "$planning_root"
caps=$(openspec status --change "stand-up-greptimedb-on-magnetite" --json | jq -r '.artifactPaths.specs.existingOutputPaths[] | split("/")[-2]'); echo $caps
```

Expected: every artifact `done`; `totalTasks` equal to `completedTasks`; `/Users/crs58/projects/vanixiets`; `host-metrics-collection telemetry-store telemetry-store-interface world-assumptions` (in the CLI's order).
Keep `planning_root` and `caps` in the shell for Step 21; `openspec status` stops resolving the change once it is archived.

- [ ] **Step 19: Sync the delta specs**

Invoke `openspec-archive-change` for `stand-up-greptimedb-on-magnetite` and choose "Sync now (recommended)" at its prompt; it runs `openspec-sync-specs` inline.
Run afterwards:

```bash
rg -n '^## (ADDED|MODIFIED|REMOVED|RENAMED) Requirements' openspec/specs/host-metrics-collection openspec/specs/telemetry-store openspec/specs/telemetry-store-interface openspec/specs/world-assumptions
rg -c '^### Requirement: A(29|30|31|32|33) ' openspec/specs/world-assumptions/spec.md
head -n1 openspec/specs/telemetry-store/spec.md
```

Expected: no output from the first command; `5` from the second; `# telemetry-store Specification` from the third.

- [ ] **Step 20: Archive**

Let the same skill invocation perform the move, or run:

```bash
openspec archive stand-up-greptimedb-on-magnetite -y 2>&1 | tee logs/openspec-archive-s1-$(date +%Y%m%d-%H%M%S).log
ARCHIVED=openspec/changes/archive/$(date +%F)-stand-up-greptimedb-on-magnetite
test -d "$ARCHIVED" && test ! -e openspec/changes/stand-up-greptimedb-on-magnetite && echo archived
```

Expected: `archived`.
Use the CLI only when the specs were not already synced in Step 19; after a skill sync, the skill's own move is the archive.

- [ ] **Step 21: Mirror the main specs to Linear documents**

Run:

```bash
linear auth whoami --workspace cameronraysmith
for cap in $caps; do
  if [ "$cap" = world-assumptions ]; then
    # Shared capability: its one mirror is parented to pyrite-baremetal-nixos (openspec/linear.yaml comment); update it in place.
    linear document update a7f9d24e-8fe2-4120-9ba0-e7d4d3a23fe1 --title "OpenSpec: world-assumptions" --content-file "$planning_root/openspec/specs/world-assumptions/spec.md" --workspace cameronraysmith
    continue
  fi
  DOC_ID=$(yq -r ".projects.\"fleet-observability\".archive_documents.\"$cap\".id // \"\"" openspec/linear.yaml)
  if [ -z "$DOC_ID" ]; then
    DOC_ID=$(linear document list --project aeed302bea3b --json --workspace cameronraysmith \
      | jq -r --arg t "OpenSpec: $cap" '.nodes[] | select(.title == $t) | .id')
  fi
  if [ -n "$DOC_ID" ]; then
    linear document update "$DOC_ID" --title "OpenSpec: $cap" --content-file "$planning_root/openspec/specs/$cap/spec.md" --workspace cameronraysmith
  else
    linear document create --project aeed302bea3b --title "OpenSpec: $cap" --content-file "$planning_root/openspec/specs/$cap/spec.md" --workspace cameronraysmith
    DOC_ID=$(linear document list --project aeed302bea3b --json --workspace cameronraysmith \
      | jq -r --arg t "OpenSpec: $cap" '.nodes[] | select(.title == $t) | .id')
  fi
  printf '%s %s\n' "$cap" "$DOC_ID" >> "$EV/linear-doc-ids.txt"
done
cat "$EV/linear-doc-ids.txt"
```

Expected: one update for `world-assumptions`, one create for each of the three new capabilities, and `linear-doc-ids.txt` listing one non-empty id each for `host-metrics-collection`, `telemetry-store` and `telemetry-store-interface`.
`aeed302bea3b` is the project slugId; a UUID would make `document list` return zero nodes and duplicate every document.
The read-only `yq -r` lookup leaves the file untouched; the ids are written by the edit below, never by `yq -i`, because `kislyuk/yq` rewrites the whole file and drops its comments.

With the edit tool, in `openspec/linear.yaml` under `projects` → `"fleet-observability"`, replace the single line

```yaml
    archive_documents: {}
```

with the following block, substituting each id from `linear-doc-ids.txt`:

```yaml
    archive_documents:
      "host-metrics-collection":
        id: "<id for host-metrics-collection>"
      "telemetry-store":
        id: "<id for telemetry-store>"
      "telemetry-store-interface":
        id: "<id for telemetry-store-interface>"
```

The `<…>` markers are filled from the ids the loop just printed; no other line of the file changes.
Run:

```bash
jj diff --git openspec/linear.yaml
yq -r '.projects."fleet-observability".archive_documents' openspec/linear.yaml
```

Expected: the diff removes only `archive_documents: {}` under `fleet-observability` and adds the seven lines above with real ids, with every comment intact; `yq` prints the three ids.
`world-assumptions` gets no entry here, because its one mirror is registered under `pyrite-baremetal-nixos`.

- [ ] **Step 22: Fire In Review → Done for CAM-68**

Run:

```bash
CUR=$(linear issue view CAM-68 --json --workspace cameronraysmith | jq -r '.state.name'); echo "$CUR"
linear issue update CAM-68 --state "Done" --workspace cameronraysmith
printf 'The S1 change is archived and its canonical specs are mirrored to the Fleet observability project documents.\n' > /tmp/cam68-c.md
linear issue comment add CAM-68 --body-file /tmp/cam68-c.md --workspace cameronraysmith
```

Expected: `CUR` is `In Review` (or `In Progress` if Step 11 was dropped); the update and comment succeed.
Skip the update and comment if `CUR` is already `Done`.
In the archived `proposal.md` frontmatter set `linear_story_state: Done`, `last_synced_state: Done`, `last_synced_at:` to `date -u +%FT%TZ`, `review_round: 0`, and append `{ at: "<iso>", transition: "In Review->Done", outcome: "posted", note: "T4 archive; spec sync and document mirror done" }`.

- [ ] **Step 23: Commit the close-out**

Run:

```bash
jj squash --from @ --into VERIFY --keep-emptied --use-destination-message -- \
  openspec/changes/stand-up-greptimedb-on-magnetite \
  "openspec/changes/archive/$(date +%F)-stand-up-greptimedb-on-magnetite" \
  openspec/specs/host-metrics-collection openspec/specs/telemetry-store openspec/specs/telemetry-store-interface openspec/specs/world-assumptions \
  openspec/linear.yaml
jj log -r VERIFY --no-graph -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"' --stat
```

Expected: `VERIFY` shows the deletion of `openspec/changes/stand-up-greptimedb-on-magnetite/*`, the same files added under `openspec/changes/archive/<date>-stand-up-greptimedb-on-magnetite/` with `retrospective.md`, the four main specs and `openspec/linear.yaml`.
If the archive date differs from today's (the archive ran before midnight UTC/local rollover), use the directory name Step 20 printed.
The orchestrator rebases the join, pushes and opens pull request 6, which lands through the merge queue; do not push.

---
