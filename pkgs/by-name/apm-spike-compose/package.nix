{
  inputs,
  stdenv,
  runCommandLocal,
}:
let
  system = stdenv.hostPlatform.system;
  apm = inputs.llm-agents.packages.${system}.apm;
  superpowers = inputs.self.packages.${system}.agent-plugins-superpowers;
in
runCommandLocal "apm-spike-compose"
  {
    src = ../../../modules/home/ai/plugins/apm-spike;
    nativeBuildInputs = [ apm ];
    meta = {
      description = "Phase-1 de-risk spike: hermetic nix+apm compose emitting flat .claude/skills and .agents/skills trees alongside upstream superpowers skills. Safe to delete after Phase 1.";
    };
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    export APM_CACHE_DIR="$TMPDIR/apm-cache"
    export APM_E2E_TESTS=1
    mkdir -p "$HOME" "$APM_CACHE_DIR" "$out"

    cp -RL "$src" ./spike-apm-marketplace-probe
    chmod -R u+w ./spike-apm-marketplace-probe

    cp -RL ${superpowers} ./superpowers-src
    chmod -R u+w ./superpowers-src

    cat > apm.yml <<EOF
    name: apm-spike-consumer
    version: 0.0.0
    type: skill
    dependencies:
      apm:
        - ./spike-apm-marketplace-probe
        - ./superpowers-src
      mcp: []
    EOF

    apm install --root "$out" -t agent-skills,claude

    if [ -f "$out/apm.lock.yaml" ]; then
      sed -i -e '/^generated_at:/d' -e '/^apm_version:/d' "$out/apm.lock.yaml"
    fi

    for expected in \
      "$out/.claude/skills/spike-apm-marketplace-probe/SKILL.md" \
      "$out/.agents/skills/spike-apm-marketplace-probe/SKILL.md" \
      "$out/.claude/skills/systematic-debugging/SKILL.md" \
      "$out/.agents/skills/brainstorming/SKILL.md"; do
      if [ ! -f "$expected" ]; then
        echo "apm-spike-compose assertion failed: missing $expected" >&2
        exit 1
      fi
    done
  ''
