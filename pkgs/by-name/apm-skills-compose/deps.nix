# apm-deps-<digest>: every remote apm dependency the first-party plugin
# manifests declare, downloaded by `apm lock` into one fixed-output derivation
# (design D1). The name carries the guard's digest of the remote entries and
# apm's version (design D2), so a pin or apm change without an apmDepsHash
# update fails with a hash mismatch instead of reusing a stale output.
{
  lib,
  runCommand,
  apm,
  git,
  cacert,
  yq,
  apmDepsHash,
}:
let
  pluginGroups = import ../../../lib/plugin-groups.nix;
  pluginsDir = pluginGroups.root;
  # Every skill group, independent of the compose's firstPartyPackages, so a
  # narrowed package list cannot change the content under an unchanged name.
  manifests = lib.genAttrs (builtins.filter (
    p: builtins.pathExists (pluginsDir + "/${p}/apm.yml")
  ) pluginGroups.skills) (p: builtins.readFile (pluginsDir + "/${p}/apm.yml"));
  guard = import ./guard.nix { inherit lib; } {
    inherit manifests;
    apmVersion = apm.version;
  };
  plugins = builtins.path {
    path = pluginsDir;
    name = "apm-plugins";
  };
  superpowers = builtins.filter (d: d.repo == "obra/superpowers") guard.remoteDeps;

  # Design D3, rule 5: the declared superpowers skills equal upstream skills/ at
  # the declared commit. Upstream's listing needs the network, so the rule runs
  # here; nothing it produces reaches $out, so the output hash is unaffected.
  superpowersListRule = lib.optionalString (superpowers != [ ]) ''
    sp_ref=${lib.escapeShellArg (lib.head guard.refsByRepo."obra/superpowers")}
    declared=${
      lib.escapeShellArg (
        lib.concatStringsSep "\n" (
          lib.sort lib.lessThan (map (d: lib.removePrefix "skills/" d.path) superpowers)
        )
      )
    }
    git init -q "$TMPDIR/sp"
    git -C "$TMPDIR/sp" fetch -q --depth 1 --filter=blob:none https://github.com/obra/superpowers "$sp_ref"
    upstream=$(git -C "$TMPDIR/sp" ls-tree --name-only "$sp_ref" skills/ | sed 's|^skills/||' | LC_ALL=C sort)
    if [ "$declared" != "$upstream" ]; then
      echo "apm-deps: superpowers skills declared in the plugin apm.yml files differ from upstream skills/ at $sp_ref:" >&2
      diff <(printf '%s\n' "$declared") <(printf '%s\n' "$upstream") >&2 || true
      exit 1
    fi
  '';
in
runCommand "apm-deps-${guard.digest}"
  {
    nativeBuildInputs = [
      apm
      git
      cacert
      yq
    ];
    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = apmDepsHash;
    passthru = { inherit guard; };
  }
  ''
    export HOME=$TMPDIR/home APM_CACHE_DIR=$TMPDIR/apm-cache APM_E2E_TESTS=1
    mkdir -p "$HOME" w && cd w
    for d in ${plugins}/*/; do
      n=$(basename "$d")
      if [ -d "$d/.apm/skills" ]; then
        cp -RL "$d" "./$n"
        chmod -R u+w "./$n"
      fi
    done
    {
      printf 'name: apm-skills-consumer\nversion: 0.0.0\ntype: skill\ndependencies:\n  apm:\n'
      for d in */; do printf '    - ./%s\n' "''${d%/}"; done
      printf '  mcp: []\n'
    } > apm.yml
    apm lock -t agent-skills,claude

    ${superpowersListRule}

    rm -rf apm_modules/_local
    mkdir "$out"
    cp -R apm_modules "$out/apm_modules"
    yq -y 'del(.generated_at, .apm_version) | .dependencies |= map(select(.source != "local"))' \
      apm.lock.yaml > "$out/apm.lock.yaml"
  ''
