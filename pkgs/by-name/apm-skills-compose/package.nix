{
  lib,
  callPackage,
  runCommandLocal,
  jq,
  writeText,

  apm,

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

  # Upstream source trees composed as additional local packages. Empty: remote
  # apm dependencies are declared in the plugin apm.yml files and come from
  # apmDeps.
  upstreamDeps ? [ ],

  # NAR hash of the apm-deps download. After a remote ref or apm version change
  # the download is renamed and fails with a hash mismatch printing the new
  # value to put here.
  apmDepsHash ? "sha256-8tHi1PGBMMfychJrcbSstFOkvYNNTC4CkI1uLbrZc+U=",

  # Every remote apm dependency, downloaded once (deps.nix, design D1).
  apmDeps ? callPackage ./deps.nix {
    inherit apm apmDepsHash;
    pluginsDir = ../../../modules/home/ai/plugins;
  },

  targets ? [
    "agent-skills"
    "claude"
  ],

  # Committed index of the skill directory names this compose emits under
  # .claude/skills and .agents/skills, so consumers enumerate skills at eval time
  # without reading the build output (no import-from-derivation). The build fails
  # when the output drifts from it; `just agents-skills-index` regenerates it.
  # null disables the guard (used only by that recipe).
  skillNames ? lib.importJSON ./skills.json,
}:
let
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

  # Fails the build, printing the corrected index, when either skills tree's
  # directory names differ from skillNames.
  skillIndexGuard = lib.optionalString (skillNames != null) ''
    for target in .claude .agents; do
      actual=$(find "$out/$target/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort | jq -R . | jq -s .)
      if [ "$(jq -c . <<<"$actual")" != ${lib.escapeShellArg (builtins.toJSON skillNames)} ]; then
        echo "apm-skills-compose: $target/skills differs from pkgs/by-name/apm-skills-compose/skills.json." >&2
        echo "Run 'just agents-skills-index' or replace skills.json with:" >&2
        echo "$actual" >&2
        exit 1
      fi
    done
  '';
in
runCommandLocal "apm-skills-compose"
  {
    nativeBuildInputs = [
      apm
      jq
    ];
    meta = {
      description = "Consumer apm compose over all auto-discovered first-party plugin packages, emitting flat .claude/skills and .agents/skills trees for the vanixiets marketplace; offline consumer of the apm-deps download.";
    };
    passthru = {
      inherit skillNames;
      deps = apmDeps;
    };
  }
  ''
    set -euo pipefail
    export HOME="$TMPDIR/home"
    export APM_CACHE_DIR="$TMPDIR/apm-cache"
    export APM_E2E_TESTS=1
    mkdir -p "$HOME" "$APM_CACHE_DIR" "$out"

    # Without git, apm cannot fetch, so a dependency missing from the
    # download fails the build instead of reaching the network.
    if command -v git >/dev/null; then
      echo "apm-skills-compose: git is on PATH; the compose must not be able to fetch" >&2
      exit 1
    fi

    # Store paths are read-only but apm writes into each dependency tree during
    # install, so copy with cp -RL (dereferencing symlinks) then restore write
    # permission before composing.
    ${copyFirstPartyPackages}

    ${copyUpstreamDeps}

    # apm reads apm_modules/ and apm.lock.yaml under the install root.
    cp -R ${apmDeps}/apm_modules "$out/apm_modules"
    cp ${apmDeps}/apm.lock.yaml "$out/apm.lock.yaml"
    chmod -R u+w "$out/apm_modules" "$out/apm.lock.yaml"

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
      "$out/.claude/skills/brainstorming/SKILL.md" \
      "$out/.agents/skills/brainstorming/SKILL.md" \
      "$out/.claude/skills/worktrunk/SKILL.md" \
      "$out/.claude/skills/wt-switch-create/SKILL.md" \
      "$out/.claude/skills/tdd/SKILL.md" \
      "$out/.claude/skills/code-review/SKILL.md" \
      "$out/.claude/skills/unslop/SKILL.md" \
      "$out/.agents/skills/unslop/SKILL.md" \
      "$out/.claude/skills/unslop/scripts/banned_phrase_scan.py" \
      "$out/.claude/skills/gh-stack/SKILL.md" \
      "$out/.agents/skills/gh-stack/SKILL.md" \
      "$out/.claude/skills/gh-stack/references/commands.md" \
      "$out/.claude/skills/mergify-stack/SKILL.md" \
      "$out/.agents/skills/mergify-stack/SKILL.md" \
      "$out/.claude/skills/greptimedb-perses-dashboard/SKILL.md" \
      "$out/.agents/skills/greptimedb-perses-dashboard/SKILL.md" \
      "$out/.claude/skills/greptimedb-perses-dashboard/reference.md" \
      "$out/.claude/skills/greptimedb-perses-dashboard/catalog.md" \
      "$out/.claude/skills/greptimedb-perses-dashboard/scripts/save-dashboard.sh" \
      "$out/.claude/skills/linear-cli/SKILL.md" \
      "$out/.agents/skills/linear-cli/SKILL.md" \
      "$out/.claude/skills/playwright-cli/SKILL.md" \
      "$out/.agents/skills/playwright-cli/SKILL.md"; do
      if [ ! -f "$expected" ]; then
        echo "apm-skills-compose assertion failed: missing $expected" >&2
        exit 1
      fi
    done

    ${skillIndexGuard}
  ''
