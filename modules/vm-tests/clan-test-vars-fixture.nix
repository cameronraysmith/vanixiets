# flake.lib.clanTestVarsFixture: a module for a NixOS test built on
# clan-core's clanTest that reads every machine's vars from the committed
# directory modules/vm-tests/<test name>/clan-vars instead of generating them
# during evaluation.
#
# clanTest points clan.varsDirectory and each node's
# clan.core.settings.directory at a derivation that runs the generators, and
# the nodes read that derivation's output while they evaluate
# (import-from-derivation). This module overrides both with mkForce, the
# override clanTest leaves for tests with their own fixtures.
#
# The committed directory is the output of clan-core's own executor
# (lib/clanTest/vars-executor.nix, generateVarsDerivation) run on the test's
# nodes, secrets age-encrypted to clan-core's test key, as clanTest does.
# `nix run .#regenerate-clan-test-vars -- <test>` writes it from the test's
# `generatedClanVars` attribute; the files are never edited by hand.
#
# Every node depends on a build-time comparison, so the test fails to build
# when the directory is stale:
# - its file list equals the files the nodes' generators declare;
# - a fresh run of the generators gives the same file list;
# - every public value and every decrypted secret has the same shape as the
#   fresh one: runs of 20 or more base64 characters (keys) compare as one
#   token, everything else compares byte for byte;
# - every secret decrypts with clan-core's test key, the key clanTest gives
#   each node.
{ inputs, ... }:
{
  flake.lib.clanTestVarsFixture =
    {
      config,
      lib,
      hostPkgs,
      ...
    }:
    let
      name = config.name;
      path = ./. + "/${name}/clan-vars";
      regenerate = "nix run .#regenerate-clan-test-vars -- ${name}";
      exists = builtins.pathExists path;
      # Without the directory the nodes read an empty one, so the generators
      # still evaluate for the first `regenerate`; the comparison below, which
      # every node depends on, refuses to evaluate.
      directory =
        if exists then
          path
        else
          builtins.path {
            name = "empty";
            path = ./.;
            filter = _: _: false;
          };
      fixture =
        if exists then
          path
        else
          throw "vmTests ${name}: modules/vm-tests/${name}/clan-vars does not exist; run `${regenerate}`";

      testAgeKey = "${inputs.clan-core}/nixosModules/clanCore/vars/tests/age-fixtures/key.txt";
      testAgeRecipient = lib.removePrefix "# public key: " (
        lib.findFirst (lib.hasPrefix "# public key: ") (throw "no public key line in ${testAgeKey}") (
          lib.splitString "\n" (builtins.readFile testAgeKey)
        )
      );

      executor = import "${inputs.clan-core}/lib/clanTest/vars-executor.nix" { inherit lib; };
      generated = executor.generateVarsDerivation hostPkgs config.nodes testAgeRecipient;

      declared = lib.unique (
        lib.concatLists (
          lib.mapAttrsToList (
            machine: node:
            lib.concatLists (
              lib.mapAttrsToList (
                generator: g:
                let
                  dir = if g.share then "shared/${generator}" else "per-machine/${machine}/${generator}";
                in
                lib.mapAttrsToList (
                  file: f:
                  if f.secret then "secrets/clan-vars/${dir}/${file}/${file}.age" else "vars/${dir}/${file}/value"
                ) g.files
              ) node.clan.core.vars.generators
            )
          ) config.nodes
        )
      );

      check =
        hostPkgs.runCommand "clan-vars-fixture-check-${name}"
          {
            nativeBuildInputs = [ hostPkgs.age ];
            declared = lib.concatLines declared;
            passAsFile = [ "declared" ];
          }
          ''
            set -euo pipefail
            stale() {
              echo "modules/vm-tests/${name}/clan-vars is stale: $1" >&2
              echo "regenerate it with \`${regenerate}\`" >&2
              exit 1
            }
            files() { (cd "$1" && find . -type f | sed 's|^\./||' | sort); }
            shape() { sed -E 's|[A-Za-z0-9+/=]{20,}|<base64>|g'; }
            content() {
              case "$2" in
                *.age) age -d -i ${testAgeKey} "$1/$2" | shape ;;
                *) shape < "$1/$2" ;;
              esac
            }

            sort "$declaredPath" > declared
            files ${fixture} > committed
            files ${generated} > fresh
            diff -u declared committed || stale "its files differ from the files the generators declare"
            diff -u fresh committed || stale "its files differ from a fresh run of the generators"
            while read -r f; do
              content ${generated} "$f" > fresh-value || stale "$f of a fresh run does not decrypt with the test key"
              content ${fixture} "$f" > committed-value || stale "$f does not decrypt with clan-core's test key"
              diff -u fresh-value committed-value || stale "$f differs in shape from a fresh run"
            done < committed
            cp committed "$out"
          '';
    in
    {
      clan.varsDirectory = lib.mkForce directory;
      defaults = {
        clan.core.settings.directory = lib.mkForce directory;
        environment.etc."clan-vars-fixture-check".source = check;
      };
      passthru.generatedClanVars = generated;
    };
}
