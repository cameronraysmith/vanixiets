# Holds the claude-sandbox transcript hook's gitleaks configuration
# (modules/home/users/claude-sandbox/transcript-gitleaks.toml) to what the hook
# needs from it, on synthesised transcript records:
#
# - the harness metadata gitleaks' generic-api-key rule misread in real cloud
#   transcripts on 2026-11-22 (the GitHub scope notice, the anthropic-beta list,
#   the turn attribution key) yields no finding, or the hook would never push;
# - a canary secret planted in the same records is still found, or the
#   allowlist would hide real secrets that share a line with that metadata.
#
# The build runs gitleaks with the config; it fails on any finding in the
# metadata fixture and on a canary fixture with no finding.
{ lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        claude-sandbox-transcripts = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        claude-sandbox-transcripts =
          pkgs.runCommand "claude-sandbox-transcripts"
            {
              nativeBuildInputs = [
                pkgs.gitleaks
                pkgs.jq
              ];
              config = ../home/users/claude-sandbox/transcript-gitleaks.toml;
            }
            ''
              mkdir metadata canary
              # Every context and canary is assembled here from split pieces,
              # so that no token- or context-shaped literal is in the tree for
              # the repository-wide checks.gitleaks scan to find.
              scope="$(printf '%s%s' 'acc' 'ess is scoped to: ')"'`cameronraysmith/vanixiets`'
              beta="$(printf '%s%s' '"oa' 'uth-2025-04-20","interleaved-thinking-2025-05-14"')"
              turn="$(printf '%s%s' '"turnAttri' 'butionKey"')"
              k1="$(printf '%s%s' 'api' '_key')" v1="$(printf '%s%s' 'Zq8vW3nR7tY2' 'kP9mX4bL6cH1jD5fG0sA')"
              k2="$(printf '%s%s' 'x-api' '-key')" v2="$(printf '%s%s' 'Kp4Lm9Qr2St7' 'Vw1Xy6Za3Bc8De5Fg0Hj')"
              k3="$(printf '%s%s' 'secret' '_token')" v3="$(printf '%s%s' 'Rt5Yu8Io2Pa7' 'Sd4Fg1Hj6Kl9Zx3Cv0Bn')"

              # The three contexts, shaped as the cloud harness writes them.
              {
                printf '{"type":"user","message":{"role":"user","content":"<system-reminder>GitHub %s; other repositories are refused.</system-reminder>"}}\n' "$scope"
                printf '{"type":"api-request","headers":{"anthropic-beta":["claude-code-20250219",%s,"context-management-2025-06-27"]}}\n' "$beta"
                printf '{"type":"user","message":{"role":"user","content":"hello"},%s:"9ff5d6d3-310d-49f5-a422-1d7254520fe4"}\n' "$turn"
              } >metadata/t.jsonl
              # The same records, each with a canary secret beside the metadata.
              {
                printf '{"type":"user","message":{"role":"user","content":"%s"},"%s":"%s"}\n' "$scope" "$k1" "$v1"
                printf '{"type":"api-request","headers":{"anthropic-beta":[%s],"%s":"%s"}}\n' "$beta" "$k2" "$v2"
                printf '{"type":"user",%s:"1f323090-c29d-40ab-b2b0-dc2c4e98814d","%s":"%s"}\n' "$turn" "$k3" "$v3"
              } >canary/t.jsonl

              scan() {
                gitleaks dir "$1/t.jsonl" --config "$config" --no-banner --log-level error \
                  --report-format json --report-path "$1.json" --exit-code 0
                jq -r '.[] | "  line \(.StartLine): \(.RuleID): \(.Match)"' "$1.json"
              }

              scan metadata
              if [ "$(jq length metadata.json)" != 0 ]; then
                echo "transcript-gitleaks.toml: the harness metadata above is reported as secrets; the hook would never push" >&2
                exit 1
              fi
              scan canary
              found=$(jq '[.[].StartLine] | unique | length' canary.json)
              if [ "$found" != 3 ]; then
                echo "transcript-gitleaks.toml: found canaries on $found of 3 lines; the allowlist hides secrets beside the metadata" >&2
                exit 1
              fi
              # Not vacuous: gitleaks' defaults alone do misread the metadata fixture.
              gitleaks dir metadata/t.jsonl --no-banner --log-level error \
                --report-format json --report-path defaults.json --exit-code 0
              if [ "$(jq length defaults.json)" -lt 3 ]; then
                echo "the metadata fixture no longer reproduces the defaults' false positives" >&2
                exit 1
              fi
              mkdir "$out"
              cp metadata.json canary.json "$out/"
            '';
      };
    };
}
