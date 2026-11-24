# Design D6: for each CLI whose agent skill ships in the same upstream release,
# the skill's apm.yml ref must equal the commit the CLI package records. The
# refs come from the apm-deps guard's parse of the plugin manifests. The
# compared values do not depend on the build system, so the checks exist only
# on x86_64-linux.
{ lib, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    let
      refs = self'.packages.apm-skills-compose.deps.guard.refsByRepo;
      refOf = repo: lib.concatStringsSep "," (refs.${repo} or [ "<undeclared>" ]);
      pairs = {
        mergify-cli = {
          repo = "Mergifyio/mergify-cli";
          rev = self'.packages.mergify-cli-bin.sourceRev;
        };
        linear-cli = {
          repo = "schpet/linear-cli";
          rev = self'.packages.linear-cli.skillSrc.rev;
        };
        playwright-cli = {
          repo = "microsoft/playwright-cli";
          rev = self'.packages.playwright-cli.src.rev;
        };
        worktrunk = {
          repo = "max-sixty/worktrunk";
          rev = self'.packages.worktrunk-bin.sourceRev;
        };
        gh-stack = {
          repo = "github/gh-stack";
          rev = pkgs.gh-stack.sourceRev;
        };
      };
      # One comparison, shared by the pair checks and the negative control, so
      # the control exercises exactly the logic the pairs rely on.
      compare = pkgs.writeShellScript "release-alignment-compare" ''
        # usage: compare <label> <declared apm.yml ref> <recorded release commit>
        if [ "$2" != "$3" ]; then
          echo "release alignment: $1: apm.yml ref $2 != recorded release commit $3" >&2
          exit 1
        fi
      '';
      align =
        name:
        { repo, rev }:
        pkgs.runCommand "structure-release-alignment-${name}" { } ''
          ${compare} ${
            lib.escapeShellArgs [
              repo
              (refOf repo)
              rev
            ]
          }
          touch $out
        '';
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: median 1.9 s, slowest 49 s, 16 runs in 30 days
        structure-playwright-skill-parity.class = "small";
        # nixbot: 0 runs, too few to class (design D4)
        structure-release-alignment-gh-stack = {
          class = "medium";
          measured = false;
        };
        # nixbot: 0 runs, too few to class (design D4)
        structure-release-alignment-gh-stack-tag = {
          class = "medium";
          measured = false;
        };
        # nixbot: 0 runs, too few to class (design D4)
        structure-release-alignment-linear-cli = {
          class = "medium";
          measured = false;
        };
        # nixbot: 0 runs, too few to class (design D4)
        structure-release-alignment-mergify-cli = {
          class = "medium";
          measured = false;
        };
        # nixbot: 0 runs, too few to class (design D4)
        structure-release-alignment-negative-control = {
          class = "medium";
          measured = false;
        };
        # nixbot: 0 runs, too few to class (design D4)
        structure-release-alignment-playwright-cli = {
          class = "medium";
          measured = false;
        };
        # nixbot: 0 runs, too few to class (design D4)
        structure-release-alignment-worktrunk = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") (
        lib.mapAttrs' (n: p: lib.nameValuePair "structure-release-alignment-${n}" (align n p)) pairs
        // {
          structure-release-alignment-negative-control =
            pkgs.runCommand "structure-release-alignment-negative-control" { }
              ''
                a=1111111111111111111111111111111111111111
                b=2222222222222222222222222222222222222222
                if ${compare} fixture/repo "$a" "$b" 2> err; then
                  echo "negative control: the comparison accepted unequal fixtures" >&2
                  exit 1
                fi
                if ! grep -q "$a" err || ! grep -q "$b" err; then
                  echo "negative control: the diagnostic does not name both fixtures" >&2
                  cat err >&2
                  exit 1
                fi
                touch $out
              '';
          # Equal content proves sourceRev is the commit nixpkgs' tag names. The
          # name carries the commit, so a different sourceRev is a different
          # output path and is fetched rather than found in the store.
          structure-release-alignment-gh-stack-tag = pkgs.fetchFromGitHub {
            name = "gh-stack-source-${pkgs.gh-stack.sourceRev}";
            owner = "github";
            repo = "gh-stack";
            rev = pkgs.gh-stack.sourceRev;
            hash = pkgs.gh-stack.src.outputHash;
          };
          # apm 0.36 carries the repository LICENSE into each installed skill.
          structure-playwright-skill-parity = pkgs.runCommand "structure-playwright-skill-parity" { } ''
            for t in .claude .agents; do
              diff -r -x LICENSE ${self'.packages.playwright-cli.src}/skills/playwright-cli \
                ${self'.packages.apm-skills-compose}/$t/skills/playwright-cli
            done
            touch $out
          '';
        }
      );
    };
}
