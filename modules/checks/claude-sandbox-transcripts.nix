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
              # The three contexts, shaped as the cloud harness writes them.
              cat > metadata/t.jsonl <<'EOF'
              {"type":"user","message":{"role":"user","content":"<system-reminder>GitHub access is scoped to: `cameronraysmith/vanixiets`; other repositories are refused.</system-reminder>"},"timestamp":"2026-11-22T05:01:00Z"}
              {"type":"api-request","headers":{"anthropic-beta":["claude-code-20250219","oauth-2025-04-20","interleaved-thinking-2025-05-14","context-management-2025-06-27"]},"timestamp":"2026-11-22T05:01:01Z"}
              {"type":"user","message":{"role":"user","content":"hello"},"turnAttributionKey":"9ff5d6d3-310d-49f5-a422-1d7254520fe4","timestamp":"2026-11-22T05:01:02Z"}
              EOF
              # The same records, each with a canary secret beside the metadata.
              cat > canary/t.jsonl <<'EOF'
              {"type":"user","message":{"role":"user","content":"access is scoped to: `cameronraysmith/vanixiets`"},"api_key":"Zq8vW3nR7tY2kP9mX4bL6cH1jD5fG0sA"}
              {"type":"api-request","headers":{"anthropic-beta":["oauth-2025-04-20","interleaved-thinking-2025-05-14"],"x-api-key":"Kp4Lm9Qr2St7Vw1Xy6Za3Bc8De5Fg0Hj"}}
              {"type":"user","turnAttributionKey":"1f323090-c29d-40ab-b2b0-dc2c4e98814d","secret_token":"Rt5Yu8Io2Pa7Sd4Fg1Hj6Kl9Zx3Cv0Bn"}
              EOF
              sed -i 's/^ *//' metadata/t.jsonl canary/t.jsonl

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
