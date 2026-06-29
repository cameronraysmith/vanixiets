{
  inputs,
  stdenv,
  runCommandLocal,
  jq,
  writeText,
}:
let
  system = stdenv.hostPlatform.system;
  apm = inputs.llm-agents.packages.${system}.apm;
  superpowers = inputs.self.packages.${system}.agent-plugins-superpowers;
  consumerManifest = writeText "apm-spike-canonical-consumer.yml" ''
    name: apm-spike-canonical-consumer
    version: 0.0.0
    type: skill
    dependencies:
      apm:
        - ./mkt/plugins/spike-canonical-probe
        - ./superpowers-src
      mcp: []
  '';
in
runCommandLocal "apm-spike-canonical-compose"
  {
    src = ../../../modules/home/ai/plugins/apm-spike-canonical;
    nativeBuildInputs = [
      apm
      jq
    ];
    meta = {
      description = "Phase-1b de-risk fixture: hermetic nix+apm compose proving a canonical-shape marketplace. Producer path runs `apm pack` to emit marketplace.json (packages->plugins rename); consumer path installs a MARKETPLACE_PLUGIN, asserting .apm/skills flat promotion alongside offline superpowers skills. Safe to delete after Phase 1b.";
    };
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    export APM_CACHE_DIR="$TMPDIR/apm-cache"
    export APM_E2E_TESTS=1
    mkdir -p "$HOME" "$APM_CACHE_DIR" "$out"

    cp -RL "$src" ./mkt
    chmod -R u+w ./mkt

    cp -RL ${superpowers} ./superpowers-src
    chmod -R u+w ./superpowers-src

    # Producer path: pack the marketplace root into a Claude marketplace.json.
    ( cd ./mkt && apm pack )
    test -f ./mkt/.claude-plugin/marketplace.json
    jq -e '.plugins[] | select(.name=="spike-canonical-probe")' \
      ./mkt/.claude-plugin/marketplace.json >/dev/null
    mkdir -p "$out/producer/.claude-plugin"
    cp ./mkt/.claude-plugin/marketplace.json "$out/producer/.claude-plugin/marketplace.json"

    # Best-effort marketplace check; may recurse into the deliberately-bogus
    # plugin devDependency, so never gate the build on its exit status.
    apm marketplace check || echo "[spike] marketplace check non-zero (best-effort)"

    # Consumer path: install the packed plugin plus superpowers.
    cp ${consumerManifest} ./apm.yml
    apm install --root "$out" -t agent-skills,claude

    if [ -f "$out/apm.lock.yaml" ]; then
      sed -i -e '/^generated_at:/d' -e '/^apm_version:/d' "$out/apm.lock.yaml"
    fi

    for expected in \
      "$out/.claude/skills/spike-canonical-probe/SKILL.md" \
      "$out/.agents/skills/spike-canonical-probe/SKILL.md" \
      "$out/.claude/skills/systematic-debugging/SKILL.md" \
      "$out/.agents/skills/brainstorming/SKILL.md" \
      "$out/producer/.claude-plugin/marketplace.json"; do
      if [ ! -f "$expected" ]; then
        echo "apm-spike-canonical-compose assertion failed: missing $expected" >&2
        exit 1
      fi
    done
  ''
