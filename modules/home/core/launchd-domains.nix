# home-manager bootstraps a launchd agent into gui/<uid> unless the agent sets
# `domain`. That bootstrap fails with "125: Domain does not support specified
# action" when the account has no screen session on the Mac, and the failure
# fails the whole activation (home-manager modules/launchd/default.nix,
# bootstrapAgent). An agent in the `user` domain is bootstrapped into
# user/<uid>, which exists without a screen session, and the nix-darwin module
# bootstraps it again at every boot (launchd-primer daemon).
#
# Every agent of a darwin home therefore states its domain where it is
# defined: `user` for a background job, `gui` only for one that needs the
# graphical session. A darwin home with an enabled agent left at
# home-manager's default fails evaluation, and so does a home marked
# `deploysWithoutScreenSession` that enables any `gui` agent: such an agent
# is turned off for that account where the account is defined.
{
  flake.modules.homeManager.core =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      enabled = lib.filterAttrs (_: agent: agent.enable) config.launchd.agents;
      unclassified = lib.attrNames (lib.filterAttrs (_: agent: !agent.domainDeclared) enabled);
      graphical = lib.attrNames (lib.filterAttrs (_: agent: agent.domain == "gui") enabled);
    in
    {
      options.deploysWithoutScreenSession = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether this account is activated on its Mac while it has no screen
          session there. Such a home may enable no launchd agent in the `gui`
          domain, whose bootstrap would fail the activation.
        '';
      };

      options.launchd.agents = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule (
            { options, ... }:
            {
              options.domainDeclared = lib.mkOption {
                type = lib.types.bool;
                internal = true;
                readOnly = true;
                default = options.domain.highestPrio < (lib.mkOptionDefault null).priority;
                description = "Whether a module defines this agent's `domain` instead of leaving home-manager's default.";
              };
            }
          )
        );
      };

      config.assertions = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin [
        {
          assertion = unclassified == [ ];
          message = "launchd agents without an explicit launchd.agents.<name>.domain (\"user\" unless the agent needs the graphical session): ${lib.concatStringsSep ", " unclassified}";
        }
        {
          assertion = config.deploysWithoutScreenSession -> graphical == [ ];
          message = "launchd agents in the gui domain on an account marked deploysWithoutScreenSession, whose activation they would fail with Bootstrap failed: 125; turn them off for this account: ${lib.concatStringsSep ", " graphical}";
        }
      ];
    };
}
