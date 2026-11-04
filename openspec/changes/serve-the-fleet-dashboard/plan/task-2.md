### Task 2: The package and the lint check

Implements `tasks.md` 2.1–2.5 (design D1, D11).
Pull request 1.

**Files:**
- Create: `pkgs/by-name/perses-bin/package.nix`, `pkgs/by-name/perses-bin/update.sh`
- Create: `modules/nixos/perses/lint-rules.yaml`, `modules/nixos/perses/resources/dashboard-fixture.json`, `modules/nixos/perses/mutants/*.json`
- Create: `modules/checks/perses-lint.nix`, which also defines `flake.lib.persesCuratedPlugins` and `flake.lib.persesExtractedPlugins`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `pkgs.perses-bin` with `passthru.plugins` and `passthru.pluginsArchive`; `flake.lib.persesCuratedPlugins`; `flake.lib.persesExtractedPlugins`; `checks.x86_64-linux.perses-lint`, whose resource directory Task 4 fills.

**Grounding:**
- Release `v0.55.0`, published 2026-10-21; `perses_0.55.0_checksums.txt` lists `linux_amd64` `d7c55bd2422d144eccef75e5ef4fac1c9643188548f0119fbe3a8e5013f72054` (`sha256-18Vb0kItFE7M73Xl70+sHJZDGIVI8BGfvjqOUBP3IFQ=`, matching `nix hash file` of the downloaded tarball) and `darwin_arm64` `78857f0221b7f828fa6704c0433441ef4ff4e5d4a5a5c62fea96e36d210fda94` (`sha256-eIV/AiG3+Cj6ZwTAQzRB70/05dSlpcYv6pbjbSEP2pQ=`).
- The tarball's top level holds `CHANGELOG.md`, `LICENSE`, `README.md`, `config.yaml`, `percli`, `perses` and `plugins-archive/` with 32 `<Name>-<version>.tar.gz`; both Linux binaries are statically linked.
- `perses/perses@v0.55.0:scripts/plugin/plugin.yaml` lists the 32 pins, among them `Prometheus 0.59.0`, `GreptimeDB 0.2.0`, `TimeSeriesChart 0.14.0`, `StatChart 0.15.0`, `GaugeChart 0.14.0`, `Table 0.14.0`, `Markdown 0.13.0`, `StaticListVariable 0.10.0`.
- `percli version` prints `version: 0.55.0` and exits 0 with no server; `perses` has no version flag.
- Lint probe, 2026-11-04, `darwin_arm64` `percli`, invocation `percli lint -f <file> [--plugin.path <dir>]`: bare lint passes every fixture; the archive directory fails the valid fixture with "variable schemas are not loaded"; per-archive extraction passes the valid fixture and rejects `spec.bogus` ("field not allowed") and `NopeQuery` ("schema not found for plugin").

- [ ] **Step 1: Lint fixtures, rules and mutants (tasks.md 2.1)**

`modules/nixos/perses/resources/dashboard-fixture.json`, the probe's valid fixture with the global datasource named:

```json
{"kind":"Dashboard","metadata":{"name":"fixture","project":"fleet"},"spec":{"display":{"name":"fixture"},"duration":"1h","variables":[],"layouts":[],
 "panels":{"p":{"kind":"Panel","spec":{"display":{"name":"up"},"plugin":{"kind":"TimeSeriesChart","spec":{}},
 "queries":[{"kind":"TimeSeriesQuery","spec":{"plugin":{"kind":"PrometheusTimeSeriesQuery","spec":{"datasource":{"kind":"PrometheusDatasource","name":"greptimedb-promql"},"query":"up"}}}}]}}}}}
```

`modules/nixos/perses/lint-rules.yaml`: custom rules, each targeting a scalar (CH:192-196), that reject: a datasource `name` other than `greptimedb-promql` or `greptimedb-sql`; an SQL `query` matching `(?i)select\s+\*`; an SQL `query` naming a table in `FROM` or `JOIN` without a `"<db>".` qualifier; an `allowedEndpoints[].endpointPattern` not matching `^\^.*\$$`; any `basicAuth.password`.
Write the rule syntax against `percli lint --help`'s `--custom-rule.path` and Perses' lint-rule documentation at the tag, and show each rule rejecting its mutant before moving on.

`modules/nixos/perses/mutants/`: `empty-query.json`, `extra-field.json` (`"bogus": 1` in the query spec), `unknown-kind.json` (`NopeQuery`), `static-list-variable.json`, `select-star.json`, `unqualified-table.json`, `third-datasource.json`, `unanchored-endpoint.json` (a GlobalDatasource), `literal-password.json` (a GlobalSecret).

`modules/checks/perses-lint.nix`:

```nix
{ config, lib, ... }:
{
  flake.lib.persesCuratedPlugins = [ "Prometheus" "GreptimeDB" "TimeSeriesChart" "StatChart" "GaugeChart" "Table" "Markdown" ];
  flake.lib.persesExtractedPlugins =
    pkgs:
    pkgs.runCommand "perses-plugins-extracted" { } (
      lib.concatMapStrings (name: ''
        mkdir -p $out/${name}
        tar -xzf ${pkgs.perses-bin.passthru.pluginsArchive}/${name}-${pkgs.perses-bin.passthru.plugins.${name}}.tar.gz -C $out/${name}
      '') config.flake.lib.persesCuratedPlugins
    );
  perSystem = { pkgs, system, ... }: {
    checks = lib.optionalAttrs (system == "x86_64-linux") {
      perses-lint =
        let
          percli = lib.getExe' pkgs.perses-bin "percli";
          ext = config.flake.lib.persesExtractedPlugins pkgs;
          rules = ../nixos/perses/lint-rules.yaml;
          resources = ../nixos/perses/resources;
          mutants = ../nixos/perses/mutants;
        in
        pkgs.runCommand "perses-lint" { } ''
          export HOME=$TMPDIR
          for f in ${resources}/*.json; do
            ${percli} lint -f "$f" --plugin.path ${ext} --custom-rule.path ${rules} \
              || { echo "valid file rejected: $f"; exit 1; }
          done
          for f in ${mutants}/*.json; do
            if ${percli} lint -f "$f" --plugin.path ${ext} --custom-rule.path ${rules}; then
              echo "mutant accepted: $f"; exit 1
            fi
            echo "rejected: $(basename "$f")"
          done
          if ${percli} lint -f ${resources}/dashboard-fixture.json --plugin.path ${pkgs.perses-bin.passthru.pluginsArchive}; then
            echo "archive-directory form accepted a valid file; re-examine which invocation discriminates"; exit 1
          fi
          ${percli} lint -f ${mutants}/extra-field.json \
            || { echo "bare lint rejected a mutant; re-examine which invocation discriminates"; exit 1; }
          touch $out
        '';
    };
  };
}
```

Run: `jj st --no-pager >/dev/null; nix build .#checks.x86_64-linux.perses-lint -L 2>&1 | tee logs/cam73-evidence/2.1-lint-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log`

Expected: evaluation fails with `attribute 'perses-bin' missing`.

- [ ] **Step 2: The package (tasks.md 2.2)**

`pkgs/by-name/perses-bin/package.nix`:

```nix
# perses-bin - upstream Perses release binaries with the plugin archives the
# release tag pins (scripts/plugin/plugin.yaml). nixpkgs carries 0.54.0, whose
# advisories 0.55.0 fixes. Hashes are the release's checksums file in SRI form;
# update.sh refreshes them and passthru.plugins together.
{ lib, stdenv, fetchurl, versionCheckHook }:
let
  inherit (stdenv.hostPlatform) system;
  systemToAsset = {
    "x86_64-linux" = { asset = "linux_amd64"; hash = "sha256-18Vb0kItFE7M73Xl70+sHJZDGIVI8BGfvjqOUBP3IFQ="; };
    "aarch64-darwin" = { asset = "darwin_arm64"; hash = "sha256-eIV/AiG3+Cj6ZwTAQzRB70/05dSlpcYv6pbjbSEP2pQ="; };
  };
  platform = systemToAsset.${system} or (throw "perses-bin: unsupported platform ${system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "perses-bin";
  version = "0.55.0";
  src = fetchurl {
    url = "https://github.com/perses/perses/releases/download/v${finalAttrs.version}/perses_${finalAttrs.version}_${platform.asset}.tar.gz";
    inherit (platform) hash;
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
    plugins = {
      AlertManager = "0.2.0"; BarChart = "0.14.0"; Canvas = "0.1.0"; ClickHouse = "0.7.0";
      DatasourceVariable = "0.7.0"; FlameChart = "0.7.0"; GaugeChart = "0.14.0"; GreptimeDB = "0.2.0";
      HeatMapChart = "0.6.0"; HistogramChart = "0.13.0"; Jaeger = "0.2.0"; Json = "0.1.0";
      LogExplorer = "0.2.0"; LogsTable = "0.4.0"; Loki = "0.7.0"; Markdown = "0.13.0";
      OpenSearch = "0.2.0"; PieChart = "0.15.0"; Prometheus = "0.59.0"; Pyroscope = "0.7.0";
      ScatterChart = "0.12.0"; Splunk = "0.2.0"; StatChart = "0.15.0"; StaticListVariable = "0.10.0";
      StatusHistoryChart = "0.14.0"; Table = "0.14.0"; Tempo = "0.60.0"; TimeSeriesChart = "0.14.0";
      TimeSeriesTable = "0.13.0"; TraceTable = "0.12.0"; TracingGanttChart = "0.14.0"; VictoriaLogs = "0.5.0";
    };
    pluginsArchive = "${placeholder "out"}/share/perses/plugins-archive";
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

`pluginsArchive` uses `placeholder` only inside the derivation; consumers read `"${pkgs.perses-bin}/share/perses/plugins-archive"`, so set `passthru.pluginsArchive` with `finalAttrs.finalPackage` instead if `placeholder` does not resolve outside the build, and record which form was used.

The `versionCheckHook` argument name is read from NP's `pkgs/by-name/ve/versionCheckHook` at the pin before use; if it takes no argument, call `percli version` in `installCheckPhase` and grep `version: ${finalAttrs.version}`.

Run, then the mutant `Prometheus = "0.58.0"`, then restore:

```bash
L=logs/cam73-evidence/2.2-package-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix build .#packages.aarch64-darwin.perses-bin -L 2>&1 | tee -a "$L" && ./result/bin/percli version | tee -a "$L"
ssh magnetite.zt 'bash -c "cd ~/projects/vanixiets && nix build .#packages.x86_64-linux.perses-bin -L"' 2>&1 | tee -a "$L"
```

Expected: both builds succeed and print `version: 0.55.0`; the mutant fails with "installed archives differ" and a diff line naming `Prometheus`.
The x86_64-linux build may run from the workstation through the remote builder instead of ssh, if the workstation's builders list magnetite; record which.

- [ ] **Step 3: update.sh (tasks.md 2.3)**

`pkgs/by-name/perses-bin/update.sh`, a `nix-shell --pure` script in the shape of `pkgs/by-name/worktrunk-bin/update.sh`, `-p curl jq cacert git nix yq-go`:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
PKG_NIX="${REPO_ROOT}/pkgs/by-name/perses-bin/package.nix"
current="$(sed -n 's/.*version = "\(.*\)";/\1/p' "$PKG_NIX" | head -1)"
latest_tag="$(curl -fsSL -H 'Accept: application/vnd.github+json' \
  'https://api.github.com/repos/perses/perses/releases?per_page=100' \
  | jq -r '[.[] | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))] | .[0].tag_name')"
latest="${latest_tag#v}"
[[ -n "$latest" && "$latest" != null ]] || { echo "error: no semver release found" >&2; exit 1; }
sed -i'' -e "s/version = \"${current}\"/version = \"${latest}\"/" "$PKG_NIX"
sums="$(curl -fsSL "https://github.com/perses/perses/releases/download/v${latest}/perses_${latest}_checksums.txt")"
for asset in linux_amd64 darwin_arm64; do
  hex="$(awk -v f="perses_${latest}_${asset}.tar.gz" '$2 == f {print $1}' <<<"$sums")"
  [[ ${#hex} -eq 64 ]] || { echo "error: no checksum for ${asset}" >&2; exit 1; }
  sri="$(nix hash convert --hash-algo sha256 --to sri "$hex")"
  sed -i'' -e "/asset = \"${asset}\";/ s|hash = \"sha256-[^\"]*\"|hash = \"${sri}\"|" "$PKG_NIX"
done
pins="$(curl -fsSL "https://raw.githubusercontent.com/perses/perses/v${latest}/scripts/plugin/plugin.yaml" \
  | yq -r '.[] | "      " + .name + " = \"" + .version + "\";"')"
# replace the body of `plugins = { … };` with $pins
```

The `plugins` block is rewritten between the line `plugins = {` and the next line consisting of `};`, so `package.nix` keeps that block one entry per line after the first run; `nix fmt` then formats it.

Run in a scratch worktree at Step 2's commit: once unchanged, once with `version = "0.54.0"`; `git diff --exit-code pkgs/by-name/perses-bin` after each.

Expected: both runs leave no diff against Step 2's file.

- [ ] **Step 4: The lint check passes (tasks.md 2.4)**

```bash
L=logs/cam73-evidence/2.4-lint-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix build .#checks.x86_64-linux.perses-lint -L 2>&1 | tee -a "$L"   # on magnetite or through the builder
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/perses-lint-stats.json \
  nix eval --option eval-cache false --raw .#.checks.x86_64-linux.perses-lint.drvPath >/dev/null
jq '.gc.totalBytes, .cpuTime' /tmp/perses-lint-stats.json | tee -a "$L"
```

Expected: nine `rejected:` lines; the build succeeds; `totalBytes` below 536,870,912.

- [ ] **Step 5: Pull request 1 (tasks.md 2.5)**

`nix fmt 2>&1 | tee logs/cam73-evidence/2.5-fmt-<ts>.log`; `nix fmt -- --fail-on-change`; commit; open the pull request titled "Package the Perses 0.55.0 release and lint dashboards against its plugins", its body naming the four legs and nine mutants.

Expected: nixbot green.
