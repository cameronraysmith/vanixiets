{
  lib,
  callPackage,
  runCommandLocal,
  jq,
  writeText,
  nix,

  apm,

  firstPartyPackages ? (import ../../../lib/plugin-groups.nix).skills,

  # Upstream source trees composed as additional local packages. Empty: remote
  # apm dependencies are declared in the plugin apm.yml files and come from
  # apmDeps.
  upstreamDeps ? [ ],

  # NAR hash of the apm-deps download, in hashes.json, which the realizer
  # rewrites as mergify-cli-bin's fixedOutputHash companion. After a remote ref
  # or apm version change the download is renamed and fails with a hash
  # mismatch printing the new value to put there.
  apmDepsHash ? (lib.importJSON ./hashes.json).apmDepsHash,

  # Every remote apm dependency, downloaded once (deps.nix, design D1).
  apmDeps ? callPackage ./deps.nix { inherit apm apmDepsHash; },

  targets ? [
    "agent-skills"
    "claude"
  ],

  # Committed index: `names`, the skill directories this compose emits under
  # .claude/skills and .agents/skills, so consumers enumerate skills at eval time
  # without reading the build output (no import-from-derivation); `remote`, the
  # `nix hash path` of every skill no first-party group carries. The tree oracle
  # fails when the output drifts from it; `just agents-skills-index` regenerates
  # it. null disables the index comparisons: `passthru.unindexed`, which that
  # recipe and realize-pin's remoteSkillHashes companion build.
  skillIndex ? lib.importJSON ./skills.json,
}:
let
  pluginsDir = (import ../../../lib/plugin-groups.nix).root;

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

  firstPartySkills = lib.concatMap (
    group:
    map
      (name: {
        inherit name;
        src = "${pluginsDir + "/${group}"}/.apm/skills/${name}";
      })
      (
        lib.attrNames (
          lib.filterAttrs (_: t: t == "directory") (builtins.readDir (pluginsDir + "/${group}/.apm/skills"))
        )
      )
  ) firstPartyPackages;

  remoteSkills = lib.subtractLists (map (s: s.name) firstPartySkills) skillIndex.names;

  hashPath = path: ''nix-hash --type sha256 --sri "${path}" || echo missing'';

  # Design D7, G1. Records every difference, naming the skill, then fails.
  treeOracle = ''
    oracle_status=0
    oracle_fail() {
      echo "apm-skills-compose: $*" >&2
      oracle_status=1
    }
  ''
  + lib.optionalString (skillIndex != null) ''
    for target in .claude .agents; do
      actual=$(find "$out/$target/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort | jq -R . | jq -s .)
      if [ "$(jq -c . <<<"$actual")" != ${lib.escapeShellArg (builtins.toJSON skillIndex.names)} ]; then
        oracle_fail "$target/skills names differ from skills.json names; run 'just agents-skills-index' or set them to:"
        echo "$actual" >&2
      fi
    done
  ''
  + lib.concatMapStrings (s: ''
    diff -r ${s.src} "$out/.claude/skills/${s.name}" >&2 || oracle_fail "first-party skill ${s.name} differs from its source ${s.src}"
  '') firstPartySkills
  + lib.optionalString (skillIndex != null) (
    lib.concatMapStrings (
      n:
      let
        recorded = skillIndex.remote.${n} or "unrecorded";
      in
      ''
        actual=$(${hashPath "$out/.claude/skills/${n}"})
        [ "$actual" = ${lib.escapeShellArg recorded} ] || oracle_fail "remote skill ${n} hashes to $actual, skills.json records ${recorded}; review the change, then run 'just agents-skills-index'"
      ''
    ) remoteSkills
    + lib.concatMapStrings (n: ''
      oracle_fail "skills.json records a remote hash for ${n}, which is not a remote skill"
    '') (lib.subtractLists remoteSkills (lib.attrNames skillIndex.remote))
  )
  + ''
    if [ "$(${hashPath "$out/.claude/skills"})" != "$(${hashPath "$out/.agents/skills"})" ]; then
      diff -r "$out/.claude/skills" "$out/.agents/skills" >&2 || true
      oracle_fail ".claude/skills differs from .agents/skills"
    fi
    exit "$oracle_status"
  '';
in
runCommandLocal "apm-skills-compose"
  {
    nativeBuildInputs = [
      apm
      jq
      nix
    ];
    meta = {
      description = "Consumer apm compose over all auto-discovered first-party plugin packages, emitting flat .claude/skills and .agents/skills trees for the vanixiets marketplace; offline consumer of the apm-deps download.";
    };
    passthru = {
      skillNames = if skillIndex == null then null else skillIndex.names;
      firstPartySkills = map (s: s.name) firstPartySkills;
      deps = apmDeps;
    }
    // lib.optionalAttrs (skillIndex != null) {
      unindexed = callPackage ./package.nix {
        inherit
          apm
          firstPartyPackages
          upstreamDeps
          apmDepsHash
          apmDeps
          targets
          ;
        skillIndex = null;
      };
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
    # apm defaults to --frozen when CI is set and apm.lock.yaml exists; this
    # lock holds only the remote entries, so frozen mode refuses the local ones.
    apm install --no-frozen --root "$out" -t ${lib.concatStringsSep "," targets}

    # A random id apm writes on every install.
    rm -f "$out/.apm-local/installation"

    # generated_at and apm_version are nondeterministic; strip both so $out is
    # byte-reproducible across builds.
    if [ -f "$out/apm.lock.yaml" ]; then
      sed -i -e '/^generated_at:/d' -e '/^apm_version:/d' "$out/apm.lock.yaml"
    fi

    ${treeOracle}
  ''
