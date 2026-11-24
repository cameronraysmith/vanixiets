# checks.x86_64-linux.skills-spec-conformance: every first-party skill under
# modules/home/ai/plugins/*/.apm/skills passes skill-validator's offline
# `validate structure` (the Agent Skills specification) without errors.
#
# It fails on the errors that break a skill for some consumer: frontmatter that
# does not parse as YAML, a `name` that differs from the skill's directory
# (npx skills and the Agent Skills spec key on it), a missing or overlong
# description, an invalid name, an unclosed code fence, a broken relative link.
# Warnings (exit 2: body length, keyword-list descriptions, unreferenced files)
# are printed and do not fail the check.
#
# Two flags relax rules that do not hold for this corpus: frontmatter fields
# beyond the spec stay (Claude Code reads `argument-hint` and
# `disable-model-invocation`), and files at a skill's root count as skill
# content, so the flat layouts of preferences-rust-development and
# preferences-hypermedia-development pass instead of failing the "not structured
# as a skill" ratio.
#
# One system: the skill sources do not depend on the platform.
{ lib, ... }:
{
  perSystem =
    {
      self',
      pkgs,
      system,
      ...
    }:
    let
      plugins = ../home/ai/plugins;
      skills = lib.fileset.toSource {
        root = plugins;
        fileset = lib.fileset.unions (
          map (group: plugins + "/${group}/.apm/skills") (import ../../lib/plugin-groups.nix).skills
        );
      };
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: median 8.9 s, slowest 10 s, 7 runs in 30 days
        skills-spec-conformance.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        skills-spec-conformance =
          pkgs.runCommand "skills-spec-conformance"
            {
              nativeBuildInputs = [ self'.packages.skill-validator ];
              passthru.meta.description = "Every first-party skill passes skill-validator's structure validation without errors";
            }
            ''
              status=0
              count=0
              for skill in ${skills}/*/.apm/skills/*/; do
                count=$((count + 1))
                rc=0
                skill-validator validate structure --allow-extra-frontmatter --allow-flat-layouts \
                  -o compact "$skill" > report 2>&1 || rc=$?
                case "$rc" in
                  0) ;;
                  2) cat report ;;
                  *)
                    cat report
                    echo "FAIL: $skill (skill-validator exit $rc)" >&2
                    status=1
                    ;;
                esac
              done
              [ "$status" -eq 0 ] || exit 1
              # Naming the validator makes it a reference of $out, so the upload
              # of this check carries it to the cache; nothing else builds it.
              echo "validated $count skills with ${self'.packages.skill-validator}" | tee "$out"
            '';
      };
    };
}
