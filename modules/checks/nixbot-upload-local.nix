# Behavioural check of nixbot-upload-local-outputs.patch (F81): in every
# build (pull requests, pushes to the default branch and to other branches),
# an attribute whose outputs were already in the store (skipped_local) queues
# all of them to every uploader, in one batch per build, and a
# buildDependenciesOnly attribute queues nothing. The cases are in
# ./nixbot-upload-local/test_upload_local.py and run against nixbot built
# from the pinned input with flake.lib.nixbotPatches, the same list
# magnetite's nixbot is built with; the database and the forge are stubbed.
# The mutants, each of which the cases must reject: unpatched (the pin
# without the patch) and perResult (./nixbot-upload-local/per-result.patch on
# top: each attribute's outputs queued as its result is recorded). Defined
# for x86_64-linux only: nixbot runs on magnetite.
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
      mutants = {
        unpatched = lib.remove patch flakeLib.nixbotPatches;
        perResult = flakeLib.nixbotPatches ++ [ ./nixbot-upload-local/per-result.patch ];
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
            meta.description = "behavioural check: every nixbot build uploads the outputs of attributes already in the store, in one batch, with two mutants";
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
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        nixbot-upload-local = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        inherit nixbot-upload-local;
      };
    };
}
