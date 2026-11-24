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
# home-manager's default fails evaluation.
{
  flake.modules.homeManager.core =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      unclassified = lib.attrNames (
        lib.filterAttrs (_: agent: agent.enable && !agent.domainDeclared) config.launchd.agents
      );
    in
    {
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
      ];
    };
}
