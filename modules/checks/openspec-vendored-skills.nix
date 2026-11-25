# openspec-vendored-skills - the vendored OpenSpec skills are exactly what the
# pinned OpenSpec CLI generates.
#
# The OpenSpec skills in planning-and-development are refreshed by hand with
# `nix run .#openspec-refresh-vendored-artifacts`, so an llm-agents bump that
# changes OpenSpec's skill text went unnoticed until someone refreshed. This
# check regenerates the skills offline from the pinned package and fails with
# the diff when the vendored copies differ, so that bump fails until the
# refresh is committed alongside it.
#
# The check does not run `openspec init`, which writes into a project's skills
# folders. It runs modules/home/ai/openspec/generate-skills.mjs, the generator
# the refresh also uses, which calls `expectedSkillFiles` from the package's own
# dist (the map `init` installs every skill file from), so it needs no network
# and no import-from-derivation.
#
# The vendored set is every skill whose frontmatter carries upstream's
# `author: openspec`, the marker that distinguishes generated skills from the
# hand-authored ones beside them; the comparison covers names and every file's
# contents in both directions.
{ inputs, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      # The generated text is the same on every system; x86_64-linux is where
      # nixbot builds.
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 1 run, too few to class (design D4)
        openspec-vendored-skills = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        openspec-vendored-skills =
          let
            openspec = inputs.llm-agents.packages.${system}.openspec;
            skills = lib.fileset.toSource {
              root = ../home/ai/plugins/planning-and-development/.apm/skills;
              fileset = ../home/ai/plugins/planning-and-development/.apm/skills;
            };
            generate = ../home/ai/openspec/generate-skills.mjs;
            packageRoot = "${openspec}/lib/node_modules/@fission-ai/openspec";
          in
          pkgs.runCommand "openspec-vendored-skills"
            {
              nativeBuildInputs = [
                pkgs.nodejs
                pkgs.diffutils
                pkgs.gawk
              ];
            }
            ''
              export HOME="$TMPDIR"
              node ${generate} ${packageRoot} "$TMPDIR/expected" ${lib.escapeShellArg openspec.version}

              mkdir -p "$TMPDIR/vendored"
              for dir in ${skills}/*/; do
                name="$(basename "$dir")"
                if awk 'NR == 1 && $0 == "---" { inside = 1; next }
                        inside && $0 == "---" { exit }
                        inside && /^[[:space:]]+author:[[:space:]]*openspec[[:space:]]*$/ { found = 1 }
                        END { exit !found }' "$dir/SKILL.md"; then
                  cp -R "$dir" "$TMPDIR/vendored/$name"
                fi
              done

              count="$(ls "$TMPDIR/expected" | wc -l)"
              if [ "$count" -ne 13 ]; then
                echo "openspec ${openspec.version} generates $count skills, not 13; review the refresh script and this check" >&2
                exit 1
              fi

              if ! diff -ru "$TMPDIR/vendored" "$TMPDIR/expected"; then
                echo "" >&2
                echo "The vendored OpenSpec skills differ from what openspec ${openspec.version} generates" >&2
                echo "(--- vendored, +++ generated). Run: nix run .#openspec-refresh-vendored-artifacts" >&2
                exit 1
              fi
              touch "$out"
            '';
      };
    };
}
