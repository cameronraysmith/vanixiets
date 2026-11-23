# The two marketplace files, generated from the root apm.yml `marketplace:`
# block and the group apm.yml files (design D5 of the
# skills-single-source-marketplaces change):
#
# - .github/plugin/marketplace.json: apm's Copilot profile, every published group;
#   apm consumers read it first.
# - .claude-plugin/marketplace.json: apm's Claude profile reduced to the groups
#   that carry .apm/skills, each entry pointing Claude at that directory, with no
#   version so Claude versions installs by commit.
#
# `just agents-marketplace` copies both into the tree, and
# checks.x86_64-linux.skills-marketplace-drift fails when the committed copies
# differ. apm cannot write the Claude entries itself: its Claude mapper has a
# fixed field set and package entries refuse `skills` and `strict`. The root
# manifest's `dependencies:` block would make `apm pack` build a bundle from
# apm.lock.yaml, so the build packs a private copy without it.
{
  lib,
  runCommandLocal,
  apm,
  jq,
  yq-go,
}:
let
  groups = import ../../../lib/plugin-groups.nix;
  repoRoot = ../../..;

  strayManifests = lib.concatMap (
    group:
    map (file: "${group}/${file}") (
      lib.filter (file: builtins.pathExists (groups.root + "/${group}/${file}")) [
        "plugin.json"
        ".claude-plugin"
      ]
    )
  ) groups.all;

  src = lib.fileset.toSource {
    root = repoRoot;
    fileset = lib.fileset.unions (
      [ (repoRoot + "/apm.yml") ] ++ map (group: groups.root + "/${group}/apm.yml") groups.all
    );
  };
in
assert lib.assertMsg (strayManifests == [ ])
  "skills-marketplace: a group directory holds a manifest besides apm.yml: ${lib.concatStringsSep ", " strayManifests}";
runCommandLocal "skills-marketplace"
  {
    nativeBuildInputs = [
      apm
      jq
      yq-go
    ];
    groups = lib.concatStringsSep "\n" groups.all;
    skillGroups = builtins.toJSON groups.skills;
    meta.description = "Claude and Copilot marketplace files generated from the apm.yml manifests";
  }
  ''
    export HOME="$TMPDIR/home"
    export APM_CACHE_DIR="$TMPDIR/apm-cache"
    export APM_E2E_TESTS=1
    mkdir -p "$HOME" "$APM_CACHE_DIR"
    cp -R ${src} work
    chmod -R u+w work
    cd work

    failed=0
    fail() {
      echo "skills-marketplace: $*" >&2
      failed=1
    }
    while read -r group; do
      name=$(yq -r '.name' "modules/home/ai/plugins/$group/apm.yml")
      [ "$name" = "$group" ] || fail "group $group: its apm.yml name is $name"
    done <<< "$groups"
    published=$(yq -r '.marketplace.packages[].name' apm.yml | sort)
    for group in $(comm -23 <(sort <<< "$groups") <(echo "$published")); do
      fail "group directory $group is not in marketplace.packages"
    done
    for name in $(comm -13 <(sort <<< "$groups") <(echo "$published")); do
      fail "marketplace.packages names $name, which is not a group directory"
    done
    for name in $(yq -r '.marketplace.packages[] | select(.source != "./modules/home/ai/plugins/" + .name) | .name' apm.yml); do
      fail "marketplace.packages entry $name: its source is not ./modules/home/ai/plugins/$name"
    done
    [ "$failed" -eq 0 ] || exit 1

    yq -i 'del(.dependencies) | del(.compilation)' apm.yml
    apm pack --offline

    mkdir -p "$out/.claude-plugin" "$out/.github/plugin"
    cp .github/plugin/marketplace.json "$out/.github/plugin/marketplace.json"
    jq --arg description "$(yq -r '.description' apm.yml)" --argjson skillGroups "$skillGroups" '
      {name, owner, metadata: {description: $description}} + del(.name, .owner)
      | .plugins |= map(
          select(.name | IN($skillGroups[]))
          | del(.version) + {skills: ["./.apm/skills"], strict: false}
        )
    ' .claude-plugin/marketplace.json > "$out/.claude-plugin/marketplace.json"
  ''
