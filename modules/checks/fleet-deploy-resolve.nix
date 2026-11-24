# checks.x86_64-linux.fleet-deploy-resolve: the forced command's real resolve
# (pkgs/by-name/fleet-deploy-request, `--resolve`) against a fixture flake,
# the regulator for F80.
#
# The fixture's machine toplevel is its own source path, `${self}`, so it
# changes with whatever the flake reference copies. Its source is committed
# to a repository, mirrored to a bare repository and checked out as a
# detached worktree, the layout the deployer uses, whose `.git` is a file.
# The check requires:
# - the resolved toplevel equals a `git+file` evaluation of the original
#   repository at the commit, which is what nixbot builds;
# - a `path:` evaluation of the worktree differs, so the fixture is
#   sensitive to `.git` and the first clause is not vacuous;
# - a mutant of the request command resolving through `path:` gets the other
#   path, and is rejected.
# Nix runs inside the build against a store under $TMPDIR; the fixture has no
# inputs, so nothing is fetched.
{ lib, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 1 run, too few to class (design D4)
        fleet-deploy-resolve = {
          class = "medium";
          measured = false;
        };
      };
      checks.fleet-deploy-resolve =
        pkgs.runCommand "fleet-deploy-resolve"
          {
            nativeBuildInputs = [
              self'.packages.fleet-deploy-request
              pkgs.git
              pkgs.nix
              pkgs.jq
              pkgs.python3
            ];
            source = ../../pkgs/by-name/fleet-deploy-request/fleet_deploy_request.py;
          }
          ''
            set -euo pipefail
            export HOME=$TMPDIR
            export NIX_REMOTE="local?root=$TMPDIR/nix"
            export NIX_CONFIG="experimental-features = nix-command flakes"
            git config --global user.email check@example.invalid
            git config --global user.name check
            git config --global init.defaultBranch main
            git config --global safe.directory '*'

            mkdir src && cd src
            cat > flake.nix <<'EOF'
            {
              outputs = { self }: {
                nixosConfigurations.m.config.system.build.toplevel.outPath = "''${self}";
                clan.inventory.machines.m.deploy.targetHost = "root@m";
              };
            }
            EOF
            git init -q && git add flake.nix && git commit -q -m fixture
            commit=$(git rev-parse HEAD)
            src=$PWD
            git clone -q --bare . "$TMPDIR/mirror.git"
            git --git-dir="$TMPDIR/mirror.git" worktree add -q --detach "$TMPDIR/tree" "$commit"
            test -f "$TMPDIR/tree/.git"
            cd "$TMPDIR"

            attr='#nixosConfigurations.m.config.system.build.toplevel.outPath'
            want=$(nix eval --raw "git+file://$src?rev=$commit$attr")
            viaPath=$(nix eval --raw "path:$TMPDIR/tree$attr")
            echo "git+file of the repository: $want"
            echo "path: of the worktree:      $viaPath"
            [ "$want" != "$viaPath" ] || { echo "the fixture is not sensitive to .git; the check would be vacuous"; exit 1; }

            got=$(fleet-deploy-request --resolve "$TMPDIR/tree" nixos m | jq -r .closure)
            echo "fleet-deploy-request:       $got"
            [ "$got" = "$want" ] || { echo "the request command resolves $got, not what CI builds ($want)"; exit 1; }

            # Mutant: the resolve before F80, through path:.
            sed 's|return f"git+file://{tree}?rev={commit}"|return f"path:{tree}"|' "$source" > mutant.py
            ! cmp -s "$source" mutant.py || { echo "the mutant did not change the flake reference"; exit 1; }
            mutant=$(python3 mutant.py --resolve "$TMPDIR/tree" nixos m | jq -r .closure)
            echo "path: mutant:               $mutant"
            [ "$mutant" != "$want" ] || { echo "the path: mutant was not rejected"; exit 1; }
            echo "mutant 'path-resolve' rejected as expected"
            touch $out
          '';
    };
}
