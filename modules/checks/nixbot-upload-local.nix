# Behavioural check of nixbot-upload-local-outputs.patch (F81): in a build
# of a push to the default branch, an attribute whose outputs were already in
# the store (skipped_local) queues all of them to every uploader, in one
# batch, and a buildDependenciesOnly attribute queues nothing; pull request
# builds and pushes to other branches queue nothing. The cases are in
# ./nixbot-upload-local/test_upload_local.py and run against nixbot built
# from the pinned input with flake.lib.nixbotPatches, the same list
# magnetite's nixbot is built with; the database and the forge are stubbed.
# The mutants, each of which the cases must reject: unpatched (the pin
# without the patch), anyBuild (no condition on the event), anyBranch (pull
# requests left out, other branches not) and pullRequests (other branches
# left out, pull requests not). Defined for x86_64-linux only: nixbot runs
# on magnetite.
{ config, inputs, ... }:
let
  flakeLib = config.flake.lib;
in
{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    let
      patch = ../nixos/nixbot-upload-local-outputs.patch;
      others = lib.remove patch flakeLib.nixbotPatches;
      condition = "event.pr_number is not None or event.branch != event.repo.default_branch";
      mutate =
        name: replacement:
        let
          text = builtins.readFile patch;
        in
        assert lib.assertMsg (lib.hasInfix condition text)
          "nixbot-upload-local check: mutant ${name} found nothing to replace";
        others
        ++ [
          (pkgs.writeText "${name}.patch" (builtins.replaceStrings [ condition ] [ replacement ] text))
        ];
      mutants = {
        unpatched = others;
        anyBuild = mutate "anyBuild" "False";
        anyBranch = mutate "anyBranch" "event.pr_number is not None";
        pullRequests = mutate "pullRequests" "event.branch != event.repo.default_branch";
      };

      # Mutants only need importable code, so they skip nixbot's own tests.
      pythonWith =
        patches: extra:
        let
          nixbot = inputs.nixbot.packages.${system}.nixbot.overridePythonAttrs (
            old:
            {
              patches = (old.patches or [ ]) ++ patches;
            }
            // extra
          );
        in
        nixbot.pythonModule.withPackages (ps: [
          nixbot
          ps.pytest
        ]);
      pytest = python: "${python}/bin/python -m pytest -p no:cacheprovider -q test_upload_local.py";

      nixbot-upload-local =
        pkgs.runCommand "nixbot-upload-local"
          {
            meta.description = "behavioural check: nixbot uploads the default branch's outputs of attributes already in the store, with four mutants";
          }
          ''
            cp ${./nixbot-upload-local/test_upload_local.py} test_upload_local.py
            export HOME=$TMPDIR
            ${pytest (pythonWith flakeLib.nixbotPatches { })} 2>&1 | tee result.txt
            test "''${PIPESTATUS[0]}" -eq 0
            ${lib.concatStrings (
              lib.mapAttrsToList (name: patches: ''
                if ${pytest (pythonWith patches { doCheck = false; })} > mutant.txt 2>&1; then
                  cat mutant.txt
                  echo "FAIL: mutant ${name} was accepted" >&2
                  exit 1
                fi
                echo "mutant ${name} rejected: $(tail -1 mutant.txt)" | tee -a result.txt
              '') mutants
            )}
            mkdir -p $out
            cp result.txt $out/
          '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit nixbot-upload-local;
      };
    };
}
