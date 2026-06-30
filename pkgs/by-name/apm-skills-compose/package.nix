{
  inputs,
  lib,
  stdenv,
  runCommandLocal,
  writeText,
}:
let
  system = stdenv.hostPlatform.system;
  apm = inputs.llm-agents.packages.${system}.apm;
  superpowers = inputs.self.packages.${system}.agent-plugins-superpowers;

  pluginsDir = ../../../modules/home/ai/plugins;

  firstPartyPackages = [
    "agent-orchestration-and-meta-tooling"
    "beads-issue-tracking-and-session-workflow"
    "document-authoring-and-visualization"
    "event-modeling-workflow"
    "formal-specification-and-refinement"
    "nix-build-operations"
    "planning-and-development"
    "preferences-code-and-collaboration-conventions"
    "preferences-data-and-scientific-computing"
    "preferences-domain-driven-architecture"
    "preferences-event-driven-systems"
    "preferences-functional-programming-theory"
    "preferences-nix-and-secrets"
    "preferences-operations-and-reliability"
    "preferences-programming-languages"
    "preferences-web-platform-and-deployment"
    "version-control-and-forge"
  ];

  consumerApmDeps = lib.concatStringsSep "\n" (
    map (n: "    - ./${n}") firstPartyPackages ++ [ "    - ./superpowers-src" ]
  );

  rootConsumerManifest = writeText "apm-skills-consumer.yml" ''
    name: apm-skills-consumer
    version: 0.0.0
    type: skill
    dependencies:
      apm:
    ${consumerApmDeps}
      mcp: []
  '';

  copyFirstPartyPackages = lib.concatMapStringsSep "\n" (n: ''
    cp -RL ${pluginsDir + "/${n}"} ./${n}
    chmod -R u+w ./${n}'') firstPartyPackages;
in
runCommandLocal "apm-skills-compose"
  {
    nativeBuildInputs = [ apm ];
    meta = {
      description = "Consumer apm compose over all 17 first-party plugin packages plus superpowers, emitting flat .claude/skills and .agents/skills trees. Generalizes the Phase-1 apm-spike-compose proof across the full marketplace.";
    };
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    export APM_CACHE_DIR="$TMPDIR/apm-cache"
    export APM_E2E_TESTS=1
    mkdir -p "$HOME" "$APM_CACHE_DIR" "$out"

    # Store paths are read-only but apm writes into each dependency tree during
    # install, so copy with cp -RL (dereferencing symlinks) then restore write
    # permission before composing.
    ${copyFirstPartyPackages}

    cp -RL ${superpowers} ./superpowers-src
    chmod -R u+w ./superpowers-src

    cp ${rootConsumerManifest} ./apm.yml
    # agent-skills,claude only: the codex/hermes/opencode/droid harnesses are
    # fanned out nix-side from this composed $out in a later task, not by apm.
    apm install --root "$out" -t agent-skills,claude

    # generated_at and apm_version are nondeterministic; strip both so $out is
    # byte-reproducible across builds.
    if [ -f "$out/apm.lock.yaml" ]; then
      sed -i -e '/^generated_at:/d' -e '/^apm_version:/d' "$out/apm.lock.yaml"
    fi

    for expected in \
      "$out/.claude/skills/nix-flake-pr-cycle/SKILL.md" \
      "$out/.agents/skills/nix-flake-pr-cycle/SKILL.md" \
      "$out/.claude/skills/systematic-debugging/SKILL.md" \
      "$out/.agents/skills/brainstorming/SKILL.md"; do
      if [ ! -f "$expected" ]; then
        echo "apm-skills-compose assertion failed: missing $expected" >&2
        exit 1
      fi
    done
  ''
