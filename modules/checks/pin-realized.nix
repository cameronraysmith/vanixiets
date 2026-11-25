# checks.<system>.pin-realized (openspec change automate-package-version-bumps,
# design D4): every pkgs/by-name/<p>/pin.json carries a `realizedVersion`
# equal to its `version`. realize-pin writes `realizedVersion` as its last
# write, so a pin whose `version` Renovate moved without a completed
# realization keeps the old `realizedVersion` and fails here, naming the pin
# and both values.
#
# The comparison runs in the builder, never at evaluation: an evaluation error
# drops the attribute from nixbot's evaluation instead of failing it, so the
# pins enter as a source path filtered to `<p>/pin.json` and are read with jq.
# The derivation evaluates whatever the pins contain.
{ lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      byName = ../../pkgs/by-name;
      pinFile = rel: builtins.match "[^/]+/pin\\.json" rel != null;
      pinsSrc = builtins.path {
        name = "pins";
        path = byName;
        filter =
          path: type:
          let
            rel = lib.removePrefix "${toString byName}/" (toString path);
          in
          if type == "directory" then !lib.hasInfix "/" rel else type == "regular" && pinFile rel;
      };
    in
    lib.optionalAttrs (system == "x86_64-linux" || system == "aarch64-darwin") {
      testSizes.checks.pin-realized = {
        class = "small";
        # nixbot: no run yet (design D9)
        measured = false;
      };
      checks.pin-realized =
        pkgs.runCommand "pin-realized"
          {
            nativeBuildInputs = [ pkgs.jq ];
          }
          ''
            set -euo pipefail
            failed=0
            count=0
            for f in ${pinsSrc}/*/pin.json; do
              [ -e "$f" ] || continue
              count=$((count + 1))
              pin=''${f#${pinsSrc}/}
              problem=$(jq -r '
                if has("realizedVersion") | not then
                  "realizedVersion is missing, version is \(.version | tojson)"
                elif .realizedVersion != .version then
                  "realizedVersion \(.realizedVersion | tojson) differs from version \(.version | tojson)"
                else empty end
              ' "$f")
              if [ -n "$problem" ]; then
                echo "pkgs/by-name/$pin: $problem; realize-pin did not complete for this version; see the Renovate artifact comment" >&2
                failed=1
              fi
            done
            [ "$count" -gt 0 ] || { echo "no pkgs/by-name/*/pin.json found" >&2; exit 1; }
            [ "$failed" = 0 ] || exit 1
            echo "ok: $count pins realized at their version"
            touch $out
          '';
    };
}
