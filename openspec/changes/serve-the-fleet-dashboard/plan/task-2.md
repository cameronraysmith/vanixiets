### Task 2: The package and the lint check

Implements `tasks.md` 2.1–2.5 (design D1, D6's curated set, D11).
Pull request 1.

**Files:**
- Create: `pkgs/by-name/perses-bin/package.nix`, `pkgs/by-name/perses-bin/sources.json`, `pkgs/by-name/perses-bin/update.sh`
- Modify: `modules/apps/updates.nix` (`apps.update-perses-bin`)
- Create: `modules/nixos/perses/lint-rules.yaml`, `modules/nixos/perses/resources/dashboard-fixture.json`, `modules/nixos/perses/mutants/*.json`
- Create: `modules/checks/perses-lint.nix`, which also defines `flake.lib.persesCuratedPlugins` and `flake.lib.persesCuratedArchives`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `pkgs.perses-bin` with `passthru.plugins` and `passthru.pluginsArchive`; `apps.update-perses-bin`; `flake.lib.persesCuratedPlugins`; `flake.lib.persesCuratedArchives`; `checks.x86_64-linux.perses-lint`, whose resource directory Task 4 fills.

**Grounding:**
- Release `v0.55.1` (tag commit `34599751521f9b91ccffbf2fb198d727e1ccdc83`), published 2026-11-02T17:19:07Z, `prerelease=false`; its notes include "Reject dashboard and panel links with a disallowed URL scheme (#4696)", Go 1.27.3, `golang.org/x/net` and echo upgrades, and "percli lint and migrate: extract the plugin archives found in --plugin.path (#4660)".
- `perses_0.55.1_checksums.txt` lists `linux_amd64` `7c38ace5ce665e22d7d4f823b8bc0c8e91f9bcef381f218d8c564e0fe62ba750` (`sha256-fDis5c5mXiLX1PgjuLwMjpH5vO84HyGNjFZOD+Yrp1A=`) and `darwin_arm64` `fa8424c68b0d1acce07869dec8967d102dd9d926f6a7e8ebaebd5ba292a97dcf` (`sha256-+oQkxosNGszgeGneyJZ9EC3Z2Sb2p+jrrr1bopKpfc8=`), converted with `nix hash convert --hash-algo sha256 --to sri` on 2026-11-05.
- `perses/perses@v0.55.1:scripts/plugin/plugin.yaml` lists 32 pins, each one patch above 0.55.0's, among them `Prometheus 0.59.1`, `GreptimeDB 0.2.1`, `TimeSeriesChart 0.14.1`, `StatChart 0.15.1`, `GaugeChart 0.14.1`, `Table 0.14.1`, `Markdown 0.13.1`, `StaticListVariable 0.10.1` (`logs/cam73-evidence/1.1-proto-update-20261104T234549Z.log`, run 1).
- At 0.55.0 the tarball's top level held `CHANGELOG.md`, `LICENSE`, `README.md`, `config.yaml`, `percli`, `perses` and `plugins-archive/` with 32 `<Name>-<version>.tar.gz`, both Linux binaries statically linked, and `percli version` printed `version: 0.55.0` with no server; Step 2's install and version checks confirm the same at 0.55.1.
- Lint at 0.55.1 (`logs/cam73-evidence/1.1-v0551-lint-20261104T234645Z.log`, `darwin_arm64` `percli`): with `--plugin.path` at the archive directory the valid fixture exits 0 and the extra-field mutant exits 1; bare lint passes the extra-field mutant; with the seven curated 0.55.1 archives as `--plugin.path` and the custom rules, both valid fixtures pass and the seven mutants of Step 1 exit 1.
- `percli lint` writes `plugin-modules.json` into `--plugin.path`, so a store path fails every file with "permission denied" (`logs/cam73-evidence/1.1-proto-lint-fixed-20261104T233624Z.log`).
- Custom lint rules are a JSONPath `target` and a CEL `assertion` (`perses/perses@v0.55.0:pkg/model/api/config/dashboard.go:27-114`) and run only on Dashboards; a GlobalDatasource is checked only against its plugin's schema, and a GlobalSecret or a Project is not validated (`internal/cli/cmd/lint/lint.go:121-171`).
- The perSystem `pkgs` does not carry `flake.overlays.default` (`modules/checks/apps.nix:3-7`), so a check reads this repository's package as `self'.packages.perses-bin`.

- [ ] **Step 1: The 0.55.1 probe, then lint fixtures, rules and mutants (tasks.md 2.1)**

Before writing any file, re-run the plan review's runtime probe at 0.55.1: `logs/cam73-evidence/1.1-runtime-probe.sh`, with the setup its log records (Perses from the `darwin_arm64` release tarball run with nixpkgs' argument list, design D2's settings plus the container test's overrides, the stub upstream on `127.0.0.1:4000`), now from the 0.55.1 tarball, both with and without the anchors stripped.

```bash
L=logs/cam73-evidence/2.1-probe-0551-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
bash logs/cam73-evidence/1.1-runtime-probe.sh 2>&1 | tee -a "$L"   # once per run of the 0.55.0 log, with that run's configuration
```

Expected: for each run of `1.1-runtime-probe-20261104T234415Z.log`, every numbered case answers the same status and the stub records the same requests and headers at 0.55.1, recorded case by case in the log; a difference stops the task until the operator decides.

`modules/nixos/perses/resources/dashboard-fixture.json`, the probe's valid fixture with the global datasource named:

```json
{"kind":"Dashboard","metadata":{"name":"fixture","project":"fleet"},"spec":{"display":{"name":"fixture"},"duration":"1h","variables":[],"layouts":[],
 "panels":{"p":{"kind":"Panel","spec":{"display":{"name":"up"},"plugin":{"kind":"TimeSeriesChart","spec":{}},
 "queries":[{"kind":"TimeSeriesQuery","spec":{"plugin":{"kind":"PrometheusTimeSeriesQuery","spec":{"datasource":{"kind":"PrometheusDatasource","name":"greptimedb-promql"},"query":"up"}}}}]}}}}}
```

`modules/nixos/perses/lint-rules.yaml`, the rules the plan review's prototype showed rejecting their mutants:

```yaml
- name: datasource-names
  target: '$.spec.panels[*].spec.queries[*].spec.plugin.spec.datasource.name'
  assertion: 'dyn(value).all(n, n in ["greptimedb-promql", "greptimedb-sql"])'
  message: "a query names a datasource other than greptimedb-promql or greptimedb-sql"
- name: sql-no-select-star
  target: '$.spec.panels[*].spec.queries[*].spec.plugin'
  assertion: 'dyn(value).all(p, p.kind != "GreptimeDBTimeSeriesQuery" || !p.spec.query.matches("(?i)select\\s+\\*"))'
  message: "an SQL query selects *"
- name: sql-qualified-tables
  target: '$.spec.panels[*].spec.queries[*].spec.plugin'
  assertion: 'dyn(value).all(p, p.kind != "GreptimeDBTimeSeriesQuery" || !p.spec.query.matches("(?i)\\b(from|join)\\s+(\"[^\"]*\"\\s*([^.\\s]|$)|[^\"(\\s])"))'
  message: "an SQL query names a table without its database; views use no CTEs, whose names cannot carry one"
```

`modules/nixos/perses/mutants/`, each the fixture with one change, and the substring each must print:

| Mutant | Change | Expected message |
|---|---|---|
| `empty-query.json` | `"query": ""` | `MinRunes(1)` |
| `extra-field.json` | `"bogus": 1` in the query spec | `field not allowed` |
| `unknown-kind.json` | query kind `NopeQuery` | `schema not found for plugin NopeQuery` |
| `static-list-variable.json` | a `ListVariable` with plugin `StaticListVariable` | `schema not found for plugin StaticListVariable` |
| `select-star.json` | a `GreptimeDBTimeSeriesQuery` `SELECT * FROM "devloop"."ci_build"` | `an SQL query selects *` |
| `unqualified-table.json` | a `GreptimeDBTimeSeriesQuery` `SELECT count(*) AS n FROM "ci_build"` | `an SQL query names a table without its database` |
| `third-datasource.json` | datasource name `other` | `a query names a datasource other than` |

The plan review's log shows percli printing the first four messages, and shows nothing for the three custom-rule mutants (`1.1-proto-lint-fixed-20261104T233624Z.log`, last run); show each rule rejecting its mutant and record what percli prints before fixing the table, and if percli prints no message for a custom-rule failure, stop and ask the operator.

`modules/checks/perses-lint.nix`:

```nix
{ config, lib, ... }:
{
  flake.lib.persesCuratedPlugins = [ "Prometheus" "GreptimeDB" "TimeSeriesChart" "StatChart" "GaugeChart" "Table" "Markdown" ];
  flake.lib.persesCuratedArchives =
    pkgs: perses-bin:
    pkgs.linkFarm "perses-plugins-curated" (
      map (n: rec {
        name = "${n}-${perses-bin.passthru.plugins.${n}}.tar.gz";
        path = "${perses-bin.passthru.pluginsArchive}/${name}";
      }) config.flake.lib.persesCuratedPlugins
    );
  perSystem = { pkgs, self', system, ... }: {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
      perses-lint =
        let
          perses-bin = self'.packages.perses-bin;
          percli = lib.getExe' perses-bin "percli";
          curated = config.flake.lib.persesCuratedArchives pkgs perses-bin;
          rules = ../nixos/perses/lint-rules.yaml;
          resources = ../nixos/perses/resources;
          mutants = ../nixos/perses/mutants;
          expected = {
            empty-query = "MinRunes(1)";
            extra-field = "field not allowed";
            unknown-kind = "schema not found for plugin NopeQuery";
            static-list-variable = "schema not found for plugin StaticListVariable";
            select-star = "an SQL query selects *";
            unqualified-table = "an SQL query names a table without its database";
            third-datasource = "a query names a datasource other than";
          };
        in
        pkgs.runCommand "perses-lint" { } ''
          export HOME=$TMPDIR
          # percli writes into --plugin.path and, at 0.55.1, extracts the archives there.
          cp -rL --no-preserve=mode ${curated} plugins
          for f in ${resources}/*.json; do
            ${percli} lint -f "$f" --plugin.path plugins --custom-rule.path ${rules} \
              || { echo "valid file rejected: $f"; exit 1; }
          done
          [ "$(ls ${mutants} | sort)" = "$(printf '%s.json\n' ${lib.escapeShellArgs (lib.attrNames expected)} | sort)" ] \
            || { echo "the mutant files differ from the expected-message table"; exit 1; }
          ${lib.concatStrings (lib.mapAttrsToList (n: m: ''
            if msg=$(${percli} lint -f ${mutants}/${n}.json --plugin.path plugins --custom-rule.path ${rules} 2>&1); then
              echo "mutant accepted: ${n}.json"; exit 1
            fi
            grep -qF ${lib.escapeShellArg m} <<<"$msg" \
              || { echo "mutant ${n}.json rejected for another reason: $msg"; exit 1; }
            echo ${lib.escapeShellArg "rejected: ${n}.json: ${m}"}
          '') expected)}
          ${percli} lint -f ${mutants}/extra-field.json \
            || { echo "bare lint rejected a mutant; re-examine which invocation discriminates"; exit 1; }
          echo "ok: bare lint accepts extra-field.json"
          touch $out
        '';
    };
  };
}
```

No shell variable in the check is named `out`, which would clobber `$out`.

Run: `jj st --no-pager >/dev/null; nix build .#checks.x86_64-linux.perses-lint -L 2>&1 | tee logs/cam73-evidence/2.1-lint-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log`

Expected: evaluation fails with `attribute 'perses-bin' missing`, raised on `self'.packages`, which Step 2 removes.

- [ ] **Step 2: The package (tasks.md 2.2)**

`pkgs/by-name/perses-bin/sources.json`, the version, both hashes and the 32 pins of `plugin.yaml` at `v0.55.1`:

```json
{
  "version": "0.55.1",
  "hashes": {
    "x86_64-linux": "sha256-fDis5c5mXiLX1PgjuLwMjpH5vO84HyGNjFZOD+Yrp1A=",
    "aarch64-darwin": "sha256-+oQkxosNGszgeGneyJZ9EC3Z2Sb2p+jrrr1bopKpfc8="
  },
  "plugins": {
    "AlertManager": "0.2.1", "BarChart": "0.14.1", "Canvas": "0.1.1", "ClickHouse": "0.7.1",
    "DatasourceVariable": "0.7.1", "FlameChart": "0.7.1", "GaugeChart": "0.14.1", "GreptimeDB": "0.2.1",
    "HeatMapChart": "0.6.1", "HistogramChart": "0.13.1", "Jaeger": "0.2.1", "Json": "0.1.1",
    "LogExplorer": "0.2.1", "LogsTable": "0.4.1", "Loki": "0.7.1", "Markdown": "0.13.1",
    "OpenSearch": "0.2.1", "PieChart": "0.15.1", "Prometheus": "0.59.1", "Pyroscope": "0.7.1",
    "ScatterChart": "0.12.1", "Splunk": "0.2.1", "StatChart": "0.15.1", "StaticListVariable": "0.10.1",
    "StatusHistoryChart": "0.14.1", "Table": "0.14.1", "Tempo": "0.60.1", "TimeSeriesChart": "0.14.1",
    "TimeSeriesTable": "0.13.1", "TraceTable": "0.12.1", "TracingGanttChart": "0.14.1", "VictoriaLogs": "0.5.1"
  }
}
```

`pkgs/by-name/perses-bin/package.nix`:

```nix
# perses-bin - upstream Perses release binaries with the plugin archives the
# release tag pins (scripts/plugin/plugin.yaml). nixpkgs carries 0.54.0, whose
# advisories 0.55.0 fixes; 0.55.1 adds further security fixes. sources.json
# holds the version, the release checksums file's hashes in SRI form and the
# plugin pins; update.sh rewrites all three together.
#
# Only x86_64-linux and aarch64-darwin are packaged. On other systems this file
# yields null, as pkgs/by-name/greptimedb-bin does, so the package and its
# package-* check are absent there rather than throwing at evaluation.
{ lib, stdenv, fetchurl, versionCheckHook }:
let
  sources = lib.importJSON ./sources.json;
  systemToAsset = {
    "x86_64-linux" = "linux_amd64";
    "aarch64-darwin" = "darwin_arm64";
  };
  inherit (stdenv.hostPlatform) system;
in
if !(systemToAsset ? ${system}) then
  null
else
  stdenv.mkDerivation (finalAttrs: {
    pname = "perses-bin";
    inherit (sources) version;
    src = fetchurl {
      url = "https://github.com/perses/perses/releases/download/v${finalAttrs.version}/perses_${finalAttrs.version}_${systemToAsset.${system}}.tar.gz";
      hash = sources.hashes.${system};
    };
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      install -Dm755 perses $out/bin/perses
      install -Dm755 percli $out/bin/percli
      mkdir -p $out/share/perses
      cp -r plugins-archive $out/share/perses/plugins-archive
      runHook postInstall
    '';
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      expected=$(printf '%s\n' ${lib.escapeShellArgs (lib.mapAttrsToList (n: v: "${n}-${v}.tar.gz") finalAttrs.passthru.plugins)} | sort)
      actual=$(ls $out/share/perses/plugins-archive | sort)
      if [ "$expected" != "$actual" ]; then
        echo "perses-bin: installed archives differ from passthru.plugins"; diff <(echo "$expected") <(echo "$actual"); exit 1
      fi
      runHook postInstallCheck
    '';
    nativeInstallCheckInputs = [ versionCheckHook ];
    versionCheckProgram = "${placeholder "out"}/bin/percli";
    versionCheckProgramArg = "version";
    passthru = {
      inherit (sources) plugins;
      pluginsArchive = "${finalAttrs.finalPackage}/share/perses/plugins-archive";
      updateScript = ./update.sh;
    };
    meta = {
      description = "Perses dashboard server and percli (upstream release binaries with the tag's plugin archives)";
      homepage = "https://perses.dev/";
      changelog = "https://github.com/perses/perses/releases/tag/v${finalAttrs.version}";
      license = lib.licenses.asl20;
      mainProgram = "perses";
      platforms = lib.attrNames systemToAsset;
      sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    };
  })
```

`passthru.pluginsArchive` is built from `finalAttrs.finalPackage`, so it is a store path outside the build; `placeholder "out"` would evaluate to a hash-named path that does not exist (the plan review's F2).
`versionCheckHook` reads `versionCheckProgram` and `versionCheckProgramArg` at the nixpkgs pin and runs from `preInstallCheckHooks` (`pkgs/by-name/ve/versionCheckHook/hook.sh`), as the plan review confirmed at 0.55.0.

Run from the workstation, the x86_64-linux build through the remote builder, so the build is of this commit and not of magnetite's checkout; then the mutant `"Prometheus": "0.59.0"` in `sources.json`; then restore:

```bash
L=logs/cam73-evidence/2.2-package-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix build .#packages.aarch64-darwin.perses-bin -L 2>&1 | tee -a "$L" && ./result/bin/percli version | tee -a "$L"
nix build .#packages.x86_64-linux.perses-bin -L 2>&1 | tee -a "$L"
nix eval --raw .#packages.x86_64-linux.perses-bin.passthru.pluginsArchive | tee -a "$L"
nix eval .#checks.aarch64-linux --apply 'c: c ? package-perses-bin' | tee -a "$L"
```

Expected: both builds succeed and print `version: 0.55.1`; `pluginsArchive` is a `/nix/store/…-perses-bin-0.55.1/share/perses/plugins-archive` path; `false` for aarch64-linux; the mutant fails with "installed archives differ" and a diff naming `Prometheus-0.59.0` and `Prometheus-0.59.1`.

- [ ] **Step 3: update.sh (tasks.md 2.3)**

`pkgs/by-name/perses-bin/update.sh`, a `nix-shell --pure` script in the shape of `pkgs/by-name/worktrunk-bin/update.sh`:

```bash
#!/usr/bin/env nix-shell
#!nix-shell --pure -i bash -p curl jq cacert git nix yq-go gawk
set -euo pipefail
SOURCES="$(git rev-parse --show-toplevel)/pkgs/by-name/perses-bin/sources.json"
before="$(cat "$SOURCES")"
latest_tag="$(curl -fsSL -H 'Accept: application/vnd.github+json' \
  'https://api.github.com/repos/perses/perses/releases?per_page=100' \
  | jq -r '[.[] | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] | .[0].tag_name')"
latest="${latest_tag#v}"
[[ -n "$latest" && "$latest" != null ]] || { echo "error: no semver release found" >&2; exit 1; }
sums="$(curl -fsSL "https://github.com/perses/perses/releases/download/v${latest}/perses_${latest}_checksums.txt")"
sri() {
  local hex
  hex="$(awk -v f="perses_${latest}_$1.tar.gz" '$2 == f {print $1}' <<<"$sums")"
  [[ ${#hex} -eq 64 ]] || { echo "error: no checksum for $1" >&2; exit 1; }
  nix hash convert --hash-algo sha256 --to sri "$hex"
}
linux="$(sri linux_amd64)"
darwin="$(sri darwin_arm64)"
plugins="$(curl -fsSL "https://raw.githubusercontent.com/perses/perses/v${latest}/scripts/plugin/plugin.yaml" \
  | yq -o=json '[.[] | {(.name): .version}] | .[] as $p ireduce ({}; . * $p)')"
jq -n --arg v "$latest" --arg l "$linux" --arg d "$darwin" --argjson p "$plugins" \
  '{version: $v, hashes: {"x86_64-linux": $l, "aarch64-darwin": $d}, plugins: $p}' > "$SOURCES"
# The version and both hashes move together: all changed, or none did.
jq -e -n --argjson a "$before" --slurpfile b "$SOURCES" '
  [($a.version != $b[0].version), ($a.hashes["x86_64-linux"] != $b[0].hashes["x86_64-linux"]), ($a.hashes["aarch64-darwin"] != $b[0].hashes["aarch64-darwin"])]
  | all or (any | not)' >/dev/null \
  || { echo "error: a partial update: the version and the hashes did not all change, or all stay the same" >&2; exit 1; }
```

The plugin pins are rewritten wholesale from the tag and are not part of the all-or-none comparison, because a release may leave a plugin's pin unchanged.
`nix fmt` does not reformat `sources.json` in a way that breaks the script, because the script writes the whole file.

In `modules/apps/updates.nix`, beside `apps.update-greptimedb-bin`, `apps.update-perses-bin = { type = "app"; program = "${../../pkgs/by-name/perses-bin/update.sh}"; };`, with a comment that the package is absent on aarch64-linux and the updater is host-agnostic.

Run in a scratch worktree at Step 2's commit, recording `git diff --exit-code pkgs/by-name/perses-bin` and the script's exit after each run:

1. `nix run .#update-perses-bin` unchanged.
2. `sources.json` replaced by 0.55.0's values (version `0.55.0`, hashes `sha256-18Vb0kItFE7M73Xl70+sHJZDGIVI8BGfvjqOUBP3IFQ=` and `sha256-eIV/AiG3+Cj6ZwTAQzRB70/05dSlpcYv6pbjbSEP2pQ=`, and 0.55.0's pins), then the app.
3. Only the darwin hash corrupted, then the app.

Expected: runs 1 and 2 exit 0 and leave no diff against Step 2's file, run 2 restoring 0.55.1, both hashes and the pins; run 3 leaves no diff and exits non-zero with "a partial update".

- [ ] **Step 4: The lint check passes (tasks.md 2.4)**

```bash
L=logs/cam73-evidence/2.4-lint-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix build .#checks.x86_64-linux.perses-lint -L 2>&1 | tee -a "$L"   # through the remote builder
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/perses-lint-stats.json \
  nix eval --option eval-cache false --raw .#.checks.x86_64-linux.perses-lint.drvPath >/dev/null
jq '.gc.totalBytes, .cpuTime' /tmp/perses-lint-stats.json | tee -a "$L"
```

Expected: seven `rejected:` lines, each with its expected message; `ok: bare lint accepts extra-field.json`; the build succeeds; `totalBytes` below 536,870,912, near the plan review's 100,601,904 B.

- [ ] **Step 5: Pull request 1 (tasks.md 2.5)**

`nix fmt 2>&1 | tee logs/cam73-evidence/2.5-fmt-<ts>.log`; `nix fmt -- --fail-on-change`; commit; open the pull request titled "Package the Perses 0.55.1 release and lint dashboards against its plugins", its body naming the three legs, the seven mutants and their messages.

Expected: nixbot green.
