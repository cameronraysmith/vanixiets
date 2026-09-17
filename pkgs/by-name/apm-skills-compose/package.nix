{
  inputs,
  lib,
  stdenv,
  runCommandLocal,
  ripgrep,
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

  # Upstream additive co-ship deps. Empty now that superpowers is a regular remote
  # apm dep declared in planning-and-development/apm.yml and resolved offline via
  # the git-cache pre-warm below (design.md D11).
  upstreamDeps ? [ ],

  # Flake-pinned superpowers tree feeding apm's git checkout cache so the remote
  # dep resolves with zero network. superpowersRev is the single SHA source of
  # truth (the fetchFromGitHub rev), reconciled against the apm.yml pin by the
  # drift guard in the build script.
  superpowersSrc ? inputs.self.packages.${stdenv.hostPlatform.system}.agent-plugins-superpowers,
  superpowersRev ? superpowersSrc.rev,

  # Flake-pinned agency tree feeding apm's git checkout cache so the skills-subset
  # remote dep resolves with zero network. agencyRev is the single SHA source of
  # truth (the fetchFromGitHub rev), reconciled against the apm.yml pin by the
  # drift guard in the build script.
  agencySrc ? inputs.self.packages.${stdenv.hostPlatform.system}.agent-plugins-agency,
  agencyRev ? agencySrc.rev,

  # Flake-pinned worktrunk tree feeding apm's git checkout cache so the skills-subset
  # remote dep resolves with zero network. worktrunkRev is the single SHA source of
  # truth (the fetchFromGitHub rev), reconciled against the apm.yml pin by the drift
  # guard in the build script.
  worktrunkSrc ? inputs.self.packages.${stdenv.hostPlatform.system}.agent-plugins-worktrunk,
  worktrunkRev ? worktrunkSrc.rev,

  # Flake-pinned mattpocock/skills tree feeding apm's git checkout cache so the
  # whole-plugin remote dep resolves with zero network. mattpocockRev is the single
  # SHA source of truth (the fetchFromGitHub rev), reconciled against the apm.yml pin
  # by the drift guard in the build script.
  mattpocockSrc ? inputs.self.packages.${stdenv.hostPlatform.system}.agent-plugins-mattpocock-skills,
  mattpocockRev ? mattpocockSrc.rev,

  # Flake-pinned theclaymethod/unslop tree feeding apm's git checkout cache so the
  # bare-skill remote dep resolves with zero network. unslopRev is the single SHA
  # source of truth (the fetchFromGitHub rev), reconciled against the apm.yml pin by
  # the drift guard in the build script.
  unslopSrc ? inputs.self.packages.${stdenv.hostPlatform.system}.agent-plugins-unslop,
  unslopRev ? unslopSrc.rev,

  # Flake-pinned github/gh-stack tree feeding apm's git checkout cache so the
  # skill-bundle remote dep resolves with zero network. ghStackRev is the single SHA
  # source of truth (the fetchFromGitHub rev), reconciled against the apm.yml pin by
  # the drift guard in the build script.
  ghStackSrc ? inputs.self.packages.${stdenv.hostPlatform.system}.agent-plugins-gh-stack,
  ghStackRev ? ghStackSrc.rev,

  mergifyCliSrc ? inputs.self.packages.${stdenv.hostPlatform.system}.agent-plugins-mergify-cli,
  mergifyCliRev ? mergifyCliSrc.rev,

  targets ? [
    "agent-skills"
    "claude"
  ],
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
in
runCommandLocal "apm-skills-compose"
  {
    nativeBuildInputs = [
      apm
      ripgrep
    ];
    meta = {
      description = "Consumer apm compose over all auto-discovered first-party plugin packages, emitting flat .claude/skills and .agents/skills trees for the vanixiets marketplace; superpowers resolves as a regular remote apm dep offline via a pre-warmed git checkout cache.";
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

    # Pre-seed apm's git checkout cache from the flake-pinned superpowers tree so
    # the regular remote dep in planning-and-development/apm.yml resolves with zero
    # network (design.md D11). Shard = first 16 hex of sha256 of the repo URL; the
    # stub .git/HEAD pins the full 40-hex SHA apm matches against the declared ref.
    SP_SHA=${superpowersRev}
    SHARD=$(printf '%s' 'https://github.com/obra/superpowers' | sha256sum | cut -c1-16)
    CK="$APM_CACHE_DIR/git/checkouts_v1/$SHARD/$SP_SHA/full"
    mkdir -p "$CK"
    cp -RL ${superpowersSrc}/. "$CK"/
    chmod -R u+w "$CK"
    mkdir -p "$CK/.git"
    printf '%s\n' "$SP_SHA" > "$CK/.git/HEAD"

    # A drifted apm.yml pin would silently fall back to a network fetch of the
    # declared SHA, breaking the hermetic offline compose; fail loudly instead.
    if ! grep -q "$SP_SHA" ./planning-and-development/apm.yml; then
      echo "apm-skills-compose: superpowers SHA drift — planning-and-development/apm.yml does not pin $SP_SHA" >&2
      exit 1
    fi

    # Same offline pre-seed for the agency skills-subset remote dep.
    AG_SHA=${agencyRev}
    SHARD_AG=$(printf '%s' 'https://github.com/srid/agency' | sha256sum | cut -c1-16)
    CK_AG="$APM_CACHE_DIR/git/checkouts_v1/$SHARD_AG/$AG_SHA/full"
    mkdir -p "$CK_AG"
    cp -RL ${agencySrc}/. "$CK_AG"/
    chmod -R u+w "$CK_AG"
    mkdir -p "$CK_AG/.git"
    printf '%s\n' "$AG_SHA" > "$CK_AG/.git/HEAD"

    if ! grep -q "$AG_SHA" ./planning-and-development/apm.yml; then
      echo "apm-skills-compose: agency SHA drift — planning-and-development/apm.yml does not pin $AG_SHA" >&2
      exit 1
    fi

    # Same offline pre-seed for the worktrunk skills-subset remote dep declared in
    # version-control-and-forge/apm.yml.
    WT_SHA=${worktrunkRev}
    SHARD_WT=$(printf '%s' 'https://github.com/max-sixty/worktrunk' | sha256sum | cut -c1-16)
    CK_WT="$APM_CACHE_DIR/git/checkouts_v1/$SHARD_WT/$WT_SHA/full"
    mkdir -p "$CK_WT"
    cp -RL ${worktrunkSrc}/. "$CK_WT"/
    chmod -R u+w "$CK_WT"
    mkdir -p "$CK_WT/.git"
    printf '%s\n' "$WT_SHA" > "$CK_WT/.git/HEAD"

    if ! grep -q "$WT_SHA" ./version-control-and-forge/apm.yml; then
      echo "apm-skills-compose: worktrunk SHA drift — version-control-and-forge/apm.yml does not pin $WT_SHA" >&2
      exit 1
    fi

    # Same offline pre-seed for the mattpocock/skills whole-plugin remote dep declared
    # in planning-and-development/apm.yml. apm types it MARKETPLACE_PLUGIN (plugin.json,
    # no apm.yml) and normalizes its plugin.json-declared skills into .apm/skills/ at
    # install time.
    MP_SHA=${mattpocockRev}
    SHARD_MP=$(printf '%s' 'https://github.com/mattpocock/skills' | sha256sum | cut -c1-16)
    CK_MP="$APM_CACHE_DIR/git/checkouts_v1/$SHARD_MP/$MP_SHA/full"
    mkdir -p "$CK_MP"
    cp -RL ${mattpocockSrc}/. "$CK_MP"/
    chmod -R u+w "$CK_MP"
    mkdir -p "$CK_MP/.git"
    printf '%s\n' "$MP_SHA" > "$CK_MP/.git/HEAD"

    if ! grep -q "$MP_SHA" ./planning-and-development/apm.yml; then
      echo "apm-skills-compose: mattpocock SHA drift — planning-and-development/apm.yml does not pin $MP_SHA" >&2
      exit 1
    fi

    # Same offline pre-seed for the unslop remote dep declared in
    # preferences-code-and-collaboration-conventions/apm.yml. apm types it
    # CLAUDE_SKILL (SKILL.md at the repo root, no plugin.json or apm.yml) and installs
    # the root tree as a single skill, carrying its scripts/ and references/ siblings.
    US_SHA=${unslopRev}
    SHARD_US=$(printf '%s' 'https://github.com/theclaymethod/unslop' | sha256sum | cut -c1-16)
    CK_US="$APM_CACHE_DIR/git/checkouts_v1/$SHARD_US/$US_SHA/full"
    mkdir -p "$CK_US"
    cp -RL ${unslopSrc}/. "$CK_US"/
    chmod -R u+w "$CK_US"
    mkdir -p "$CK_US/.git"
    printf '%s\n' "$US_SHA" > "$CK_US/.git/HEAD"

    if ! grep -q "$US_SHA" ./preferences-code-and-collaboration-conventions/apm.yml; then
      echo "apm-skills-compose: unslop SHA drift — preferences-code-and-collaboration-conventions/apm.yml does not pin $US_SHA" >&2
      exit 1
    fi

    # Same offline pre-seed for the gh-stack remote dep declared in
    # version-control-and-forge/apm.yml. apm types it SKILL_BUNDLE (nested
    # skills/<name>/SKILL.md, no plugin manifest and no apm.yml) and installs the
    # skills/gh-stack/ directory with its references/ siblings.
    GH_SHA=${ghStackRev}
    SHARD_GH=$(printf '%s' 'https://github.com/github/gh-stack' | sha256sum | cut -c1-16)
    CK_GH="$APM_CACHE_DIR/git/checkouts_v1/$SHARD_GH/$GH_SHA/full"
    mkdir -p "$CK_GH"
    cp -RL ${ghStackSrc}/. "$CK_GH"/
    chmod -R u+w "$CK_GH"
    mkdir -p "$CK_GH/.git"
    printf '%s\n' "$GH_SHA" > "$CK_GH/.git/HEAD"

    if ! grep -q "$GH_SHA" ./version-control-and-forge/apm.yml; then
      echo "apm-skills-compose: gh-stack SHA drift — version-control-and-forge/apm.yml does not pin $GH_SHA" >&2
      exit 1
    fi

    MF_SHA=${mergifyCliRev}
    SHARD_MF=$(printf '%s' 'https://github.com/mergifyio/mergify-cli' | sha256sum | cut -c1-16)
    CK_MF="$APM_CACHE_DIR/git/checkouts_v1/$SHARD_MF/$MF_SHA/full"
    mkdir -p "$CK_MF"
    cp -RL ${mergifyCliSrc}/. "$CK_MF"/
    chmod -R u+w "$CK_MF"
    mkdir -p "$CK_MF/.git"
    printf '%s\n' "$MF_SHA" > "$CK_MF/.git/HEAD"

    if ! rg -q "ref: $MF_SHA" ./version-control-and-forge/apm.yml; then
      echo "apm-skills-compose: mergify-cli SHA drift — version-control-and-forge/apm.yml does not pin $MF_SHA" >&2
      exit 1
    fi

    # APM 0.31 rejects HEAD-only cache seeds to rematerialize older CRLF checkouts.
    for checkout in "$CK" "$CK_AG" "$CK_WT" "$CK_MP" "$CK_US" "$CK_GH" "$CK_MF"; do
      printf '[core]\n\tautocrlf = false\n' > "$checkout/.git/config"
    done

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
      "$out/.agents/skills/mergify-stack/SKILL.md"; do
      if [ ! -f "$expected" ]; then
        echo "apm-skills-compose assertion failed: missing $expected" >&2
        exit 1
      fi
    done
  ''
