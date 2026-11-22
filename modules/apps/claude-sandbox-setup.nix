# The Claude Code cloud environment's setup step for the claude-sandbox profile,
# with its co-located .sh sidecar. The environment's setup box holds only this
# bootstrap, which runs the app from main (the `claude-sandbox-setup-script`
# check holds this comment and the profile's README to it):
#
#   #!/bin/bash
#   nix run \
#     --option substituters 'https://cache.nixos.org https://cache.scientistexperience.net?priority=45' \
#     --option trusted-public-keys 'cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= cache.scientistexperience.net-1:N9ZeWasooJLXEwaN+rd4MMyBuGpAtcUAXrEUPBT5cXI=' \
#     --option accept-flake-config false \
#     'git+https://github.com/cameronraysmith/vanixiets?ref=main&shallow=1#claude-sandbox-setup'
#   exit 0
#
# It is one command split by `\` continuations, since the platform refuses a
# setup-script line wider than 200 columns, a tab counting 8 (A187). To pin one
# closure, end its last line with `-- /nix/store/…-home-manager-generation`.
# Only bash and the image's nix are trusted; every command the app calls comes
# from runtimeInputs, our nix included, and the preamble passes the caches and
# keys from lib/caches.nix to it explicitly, whatever the image's nix.conf says.
# bashOptions is empty because the script must never abort before `exit 0`: a
# setup step that exits non-zero stops the session from starting (A170).
{ lib, ... }:
let
  caches = import ../../lib/caches.nix;
  hosts = [
    "cache.scientistexperience.net"
    "cache.nixos.org"
  ];
  pick = prefix: lib.filter (e: lib.any (h: lib.hasPrefix (prefix h) e) hosts);
  substituters = pick (h: "https://${h}") caches.substituters;
  publicKeys = pick (h: "${h}-") caches.publicKeys;
in
{
  perSystem =
    {
      pkgs,
      config,
      ...
    }:
    {
      packages.claude-sandbox-setup = pkgs.writeShellApplication {
        name = "claude-sandbox-setup";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gawk
          pkgs.git
          pkgs.nix
        ];
        bashOptions = [ ];
        text = ''
          R=https://github.com/cameronraysmith/vanixiets
          C=${lib.escapeShellArg (lib.head (lib.filter (lib.hasPrefix "https://${lib.head hosts}") substituters))}
          S=(${lib.escapeShellArgs substituters})
          K=(${lib.escapeShellArgs publicKeys})
          ${builtins.readFile ./claude-sandbox-setup.sh}
        '';

        # Build locally; never ask a remote cache for this path (see
        # apm-context-compile.nix). In the cloud session this wrapper is the
        # one local build, a printf and a shellcheck.
        derivationArgs = {
          preferLocalBuild = true;
          allowSubstitutes = false;
        };
      };

      apps.claude-sandbox-setup = {
        type = "app";
        program = lib.getExe config.packages.claude-sandbox-setup;
      };
    };
}
