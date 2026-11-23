# checks.x86_64-linux.skills-cli-discovery: the skills CLI (vercel-labs/skills,
# `npx skills`, pinned through llm-agents) lists exactly the first-party skills
# of a copy of this repository, and `--skill` installs one of them unchanged.
#
# `npx skills add cameronraysmith/vanixiets` clones the repository and runs the
# same discovery as this check's local-path source (src/add.ts:1674-1676). It
# finds our skills only through the root skills.sh.json: each group's
# .apm/skills sits below the depth its default containers reach. The check
# fails when that file stops leading the CLI to every skill (a path missing, or
# one parent path instead of the 18 group paths), when a listed name differs
# from its directory, and when the CLI changes its discovery or install
# semantics on an llm-agents bump. The 51 remote skills are not in the
# repository, so equality with the first-party directories also shows none is
# offered.
#
# One system: the repository tree does not depend on the platform.
{ inputs, lib, ... }:
{
  perSystem =
    {
      pkgs,
      system,
      ...
    }:
    let
      repo = lib.fileset.toSource {
        root = ../..;
        fileset = lib.fileset.unions [
          ../../skills.sh.json
          ../../.claude-plugin/marketplace.json
          ../home/ai/plugins
        ];
      };
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        skills-cli-discovery =
          pkgs.runCommand "skills-cli-discovery"
            {
              nativeBuildInputs = [ inputs.llm-agents.packages.${system}.skills ];
              passthru.meta.description = "The skills CLI lists exactly the first-party skills and installs one with --skill";
            }
            ''
              export HOME="$TMPDIR/home"
              export DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 NO_COLOR=1 TERM=dumb
              mkdir -p "$HOME" proj
              cp -R ${repo} repo
              chmod -R u+w repo
              ls -d repo/modules/home/ai/plugins/*/.apm/skills/*/ | xargs -n1 basename | LC_ALL=C sort > want

              (cd proj && skills add ../repo --list) > list.log 2>&1 || { cat list.log; exit 1; }
              sed -n 's/^│    \([^ ]*\)$/\1/p' list.log | LC_ALL=C sort > got
              if ! diff -u --label "first-party skill directories" --label "listed by skills" want got; then
                cat list.log
                echo "FAIL: skills lists other skills than the first-party directories" >&2
                exit 1
              fi

              skill=$(head -1 want)
              (cd proj && skills add ../repo --skill "$skill" -a codex -y) > add.log 2>&1 || { cat add.log; exit 1; }
              installed=$(ls proj/.agents/skills)
              if [ "$installed" != "$skill" ]; then
                cat add.log
                echo "FAIL: --skill $skill installed: $installed" >&2
                exit 1
              fi
              diff -r repo/modules/home/ai/plugins/*/.apm/skills/"$skill" "proj/.agents/skills/$skill"
              echo "listed $(wc -l < got) skills; --skill $skill installed unchanged" | tee "$out"
            '';
      };
    };
}
