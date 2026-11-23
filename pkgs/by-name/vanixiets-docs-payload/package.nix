# The docs site as deployed: the vanixiets-docs build plus the Agent Skills
# discovery index under dist/client/.well-known/agent-skills/, so
# `npx skills add https://infra.cameronraysmith.net` lists and installs the
# first-party skills (cloudflare/agent-skills-discovery-rfc v0.2.0).
#
# `index` is its own derivation over the first-party skill directories
# (<group>/.apm/skills/*, lib/plugin-groups.nix), so a skill edit rebuilds the
# index and this copy and never the astro build or its e2e checks. The remote
# skills apm adds from other repositories are not in those directories, so they
# are never republished here.
#
# deploy-docs deploys this payload (modules/apps/docs/deploy.nix);
# checks.x86_64-linux.agent-skills-index regulates the index.
{
  lib,
  python3,
  runCommand,
  vanixiets-docs,
}:
let
  groups = import ../../../lib/plugin-groups.nix;

  skills = lib.fileset.toSource {
    inherit (groups) root;
    fileset = lib.fileset.unions (map (group: groups.root + "/${group}/.apm/skills") groups.skills);
  };

  generator = ./agent-skills-index.py;
  python = python3.withPackages (ps: [ ps.pyyaml ]);

  index =
    runCommand "agent-skills-index"
      {
        nativeBuildInputs = [ python ];
        passthru = { inherit skills generator python; };
        meta.description = "Agent Skills discovery index of the first-party skills";
      }
      ''
        python3 ${generator} ${skills} $out/.well-known/agent-skills
      '';
in
runCommand "vanixiets-docs-payload"
  {
    passthru = { inherit index; };
    meta.description = "vanixiets-docs with the Agent Skills discovery index, as deployed";
  }
  ''
    cp -R ${vanixiets-docs} $out
    chmod -R u+w $out
    if [ -e $out/dist/client/.well-known ]; then
      echo "vanixiets-docs already serves .well-known/; the index would merge into it" >&2
      exit 1
    fi
    cp -R ${index}/.well-known $out/dist/client/.well-known
  ''
