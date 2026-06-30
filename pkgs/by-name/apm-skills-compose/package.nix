{
  inputs,
  lib,
  stdenv,
  runCommandLocal,
  writeText,

  # Auto-discover every apm package dir (one containing .apm/skills) under the
  # plugins root. readDir over a source path → no IFD. Sorted == alphabetical,
  # reproducing the prior hardcoded order.
  firstPartyPackages ?
    let
      root = ../../../modules/home/ai/plugins;
    in
    lib.attrNames (
      lib.filterAttrs (n: t: t == "directory" && builtins.pathExists (root + "/${n}/.apm/skills")) (
        builtins.readDir root
      )
    ),

  # Upstream additive co-ship deps; Phase 4 appends the bridge fork.
  upstreamDeps ? [
    {
      name = "superpowers-src";
      src = inputs.self.packages.${stdenv.hostPlatform.system}.agent-plugins-superpowers;
    }
  ],

  targets ? [
    "agent-skills"
    "claude"
  ],
}:
let
  system = stdenv.hostPlatform.system;
  apm = inputs.llm-agents.packages.${system}.apm;

  pluginsDir = ../../../modules/home/ai/plugins;

  consumerApmDeps = lib.concatStringsSep "\n" (
    map (n: "    - ./${n}") firstPartyPackages ++ map (d: "    - ./${d.name}") upstreamDeps
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

  copyUpstreamDeps = lib.concatMapStringsSep "\n" (d: ''
    cp -RL ${d.src} ./${d.name}
    chmod -R u+w ./${d.name}'') upstreamDeps;
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

    ${copyUpstreamDeps}

    cp ${rootConsumerManifest} ./apm.yml
    # agent-skills,claude only: the codex/hermes/opencode/droid harnesses are
    # fanned out nix-side from this composed $out in a later task, not by apm.
    apm install --root "$out" -t ${lib.concatStringsSep "," targets}

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
