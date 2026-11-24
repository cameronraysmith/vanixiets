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
  # Design D3, rule 5, for the repositories consumed one skill directory at a
  # time from a flat skills/ directory: the declared skills plus the ones
  # deliberately withheld here equal upstream skills/ at the declared commit, so
  # a bump that adds or removes an upstream skill fails until a group apm.yml or
  # this table names it. Upstream's listing needs the network, so the rule runs
  # here; nothing it produces reaches $out, so the output hash is unaffected.
  listedRepos = {
    "obra/superpowers".withheld = [ ];
    # Both are one-time installers of a Claude Code SessionStart hook that runs
    # a curl-driven script on every session: autosync-ic-skills rewrites
    # .claude/skills from skills.internetcomputer.org, autoupgrade-icp-cli
    # upgrades the icp and ic-wasm binaries. The skills are pinned here instead,
    # and icp, ic-wasm and mops come from pkgs/by-name/icp-cli-bin, ic-wasm-bin
    # and mops-bin.
    "dfinity/icskills".withheld = [
      "autosync-ic-skills"
      "autoupgrade-icp-cli"
    ];
  };
  listRule =
    repo:
    { withheld }:
    let
      declaredDeps = builtins.filter (d: d.repo == repo) guard.remoteDeps;
      ref = lib.head guard.refsByRepo.${repo};
      dir = "$TMPDIR/list/${repo}";
    in
    lib.optionalString (declaredDeps != [ ]) ''
      expected=${
        lib.escapeShellArg (
          lib.concatStringsSep "\n" (
            lib.sort lib.lessThan (map (d: lib.removePrefix "skills/" d.path) declaredDeps ++ withheld)
          )
        )
      }
      git init -q "${dir}"
      git -C "${dir}" fetch -q --depth 1 --filter=blob:none https://github.com/${repo} ${ref}
      upstream=$(git -C "${dir}" ls-tree -d --name-only ${ref} skills/ | sed 's|^skills/||' | LC_ALL=C sort)
      if [ "$expected" != "$upstream" ]; then
        echo "apm-deps: ${repo} skills declared in the plugin apm.yml files plus those withheld in deps.nix differ from upstream skills/ at ${ref}:" >&2
        diff <(printf '%s\n' "$expected") <(printf '%s\n' "$upstream") >&2 || true
        exit 1
      fi
    '';

  mattpocock = builtins.filter (d: d.repo == "mattpocock/skills") guard.remoteDeps;
  flowSequence = s: map lib.trim (lib.splitString "," (lib.head (builtins.match "\\[(.*)]" s)));

  # Design D7, G2: the declared mattpocock skills equal the skills of upstream's
  # .claude-plugin/plugin.json at the declared commit. Like the skills/ list
  # rule, it reads the network and writes nothing to $out.
  mattpocockListRule = lib.optionalString (mattpocock != [ ]) ''
    mp_ref=${lib.escapeShellArg (lib.head guard.refsByRepo."mattpocock/skills")}
    declared=${
      lib.escapeShellArg (
        lib.concatStringsSep "\n" (
          lib.sort lib.lessThan (lib.concatMap (d: flowSequence (d.skills or "[]")) mattpocock)
        )
      )
    }
    git init -q "$TMPDIR/mp"
    git -C "$TMPDIR/mp" fetch -q --depth 1 --filter=blob:none https://github.com/mattpocock/skills "$mp_ref"
    upstream=$(git -C "$TMPDIR/mp" show "$mp_ref:.claude-plugin/plugin.json" | yq -r '.skills[] | split("/") | last' | LC_ALL=C sort)
    if [ "$declared" != "$upstream" ]; then
      echo "apm-deps: mattpocock/skills skills declared in the plugin apm.yml files differ from upstream .claude-plugin/plugin.json at $mp_ref:" >&2
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

    ${lib.concatStrings (lib.mapAttrsToList listRule listedRepos)}
    ${mattpocockListRule}

    rm -rf apm_modules/_local
    mkdir "$out"
    cp -R apm_modules "$out/apm_modules"
    yq -y 'del(.generated_at, .apm_version) | .dependencies |= map(select(.source != "local"))' \
      apm.lock.yaml > "$out/apm.lock.yaml"
  ''
