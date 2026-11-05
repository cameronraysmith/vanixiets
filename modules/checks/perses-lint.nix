# perses-lint - the view files lint clean at the shipped plugins.
#
# percli and the plugin archives come from the same perses-bin the dashboard
# server runs, so lint judges the files against the schemas the server loads.
# Three legs:
# - valid: every file in modules/nixos/perses/resources passes lint with the
#   curated archives as --plugin.path and the custom rules;
# - mutants: every file in modules/nixos/perses/mutants fails, printing its
#   expected message, so the curated archive directory and each rule
#   discriminate;
# - bareLintTautological: lint without --plugin.path accepts the extra-field
#   mutant, so a percli change that makes bare lint discriminate is noticed and
#   the invocation re-examined.
#
# The curated set is defined here and read by the NixOS module, so the server
# and the check load the same seven archives.
{ config, lib, ... }:
{
  flake.lib.persesCuratedPlugins = [
    "Prometheus"
    "GreptimeDB"
    "TimeSeriesChart"
    "StatChart"
    "GaugeChart"
    "Table"
    "Markdown"
  ];
  flake.lib.persesCuratedArchives =
    pkgs: perses-bin:
    pkgs.linkFarm "perses-plugins-curated" (
      map (n: rec {
        name = "${n}-${perses-bin.passthru.plugins.${n}}.tar.gz";
        path = "${perses-bin.passthru.pluginsArchive}/${name}";
      }) config.flake.lib.persesCuratedPlugins
    );

  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    {
      # The files and the lint are identical on every system; x86_64-linux is
      # where nixbot builds.
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        perses-lint =
          let
            # The perSystem pkgs does not carry flake.overlays.default
            # (modules/checks/apps.nix), so the package is read from self'.
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
            # percli writes plugin-modules.json into --plugin.path and extracts
            # the archives there, so it needs a writable copy, not the store path.
            cp -rL --no-preserve=mode ${curated} plugins
            for f in ${resources}/*.json; do
              ${percli} lint -f "$f" --plugin.path plugins --custom-rule.path ${rules} \
                || { echo "valid file rejected: $f"; exit 1; }
            done
            [ "$(ls ${mutants} | sort)" = "$(printf '%s.json\n' ${lib.escapeShellArgs (lib.attrNames expected)} | sort)" ] \
              || { echo "the mutant files differ from the expected-message table"; exit 1; }
            ${lib.concatStrings (
              lib.mapAttrsToList (n: m: ''
                if msg=$(${percli} lint -f ${mutants}/${n}.json --plugin.path plugins --custom-rule.path ${rules} 2>&1); then
                  echo "mutant accepted: ${n}.json"; exit 1
                fi
                grep -qF ${lib.escapeShellArg m} <<<"$msg" \
                  || { echo "mutant ${n}.json rejected for another reason: $msg"; exit 1; }
                echo ${lib.escapeShellArg "rejected: ${n}.json: ${m}"}
              '') expected
            )}
            ${percli} lint -f ${mutants}/extra-field.json \
              || { echo "bare lint rejected a mutant; re-examine which invocation discriminates"; exit 1; }
            echo "ok: bare lint accepts extra-field.json"
            touch $out
          '';
      };
    };
}
