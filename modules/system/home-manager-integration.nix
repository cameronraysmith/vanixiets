# The home-manager integration of every NixOS and darwin host, generated from
# the host's user attachments (flake.fleet.hosts.<host>.users,
# lib/host-users.nix): one home per attachment, the secret bridge (NixOS), and
# nix-darwin's admin account and the attached accounts' uids (darwin).
#
# Each host imports home-manager's own module at machine level, beside this
# aspect; importing it from the clan user services duplicated catppuccin's
# imports when clan deploys.
#
# flake.lib.homeFlake is the one `flake` value a home receives. It reaches a
# home only through that home's own `_module.args.flake`, set by what composes
# it: this aspect for host homes, flake.lib.mkHome for standalone homes, and
# the omnigent-worker aspect, with a restricted value, for worker homes. A
# host-wide `home-manager.extraSpecialArgs.flake` would shadow every one of
# them (specialArgs take precedence over `_module.args`), so the aspect asserts
# there is none. It never forces or replaces extraSpecialArgs, which also
# carries home-manager's own nixosConfig/darwinConfig.
{
  config,
  inputs,
  lib,
  ...
}:
let
  flakeConfig = config;
  inherit (config.flake.lib) hosts homeFlake;

  integration =
    class:
    { config, lib, ... }:
    let
      inherit (config.networking) hostName;
      attachments = config.home-manager-integration.attachments;
      accounts = lib.attrNames attachments;
      admins = lib.filter (account: attachments.${account}.admin) accounts;
    in
    {
      options.home-manager-integration.attachments = lib.mkOption {
        type = lib.types.raw;
        internal = true;
        default = (hosts.${hostName} or { users = { }; }).users;
        defaultText = lib.literalExpression "flake.fleet.hosts.\${networking.hostName}.users";
        description = "The host's user attachments; a fixture without a registry entry sets its own.";
      };

      config = lib.mkMerge [
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            # Back up conflicting files instead of failing.
            backupFileExtension = "before-home-manager";
            # The pair's overrides are imported after the person's modules and
            # the attachment's extra imports.
            users = lib.mapAttrs (account: attachment: {
              imports =
                flakeConfig.flake.users.${account}.modules ++ attachment.extraImports ++ [ attachment.overrides ];
              _module.args.flake = homeFlake;
            }) attachments;
          };

          assertions = [
            {
              assertion = !(config.home-manager.extraSpecialArgs ? flake);
              message = "home-manager-integration: home-manager.extraSpecialArgs.flake is set on ${hostName}; it would shadow each home's own `flake` (flake.lib.homeFlake, or the omnigent worker's restricted value). Remove it.";
            }
          ];
        }
        (lib.optionalAttrs (class == "nixos") {
          hm-sops-bridge.users = lib.genAttrs (lib.filter (
            account: attachments.${account}.sopsBridge
          ) accounts) (_: { });
        })
        (lib.optionalAttrs (class == "darwin") {
          # nix-darwin's admin account, never inferred from the primary user.
          system.primaryUser = lib.mkIf (admins != [ ]) (lib.head admins);
          users.users = lib.mapAttrs (_: attachment: { inherit (attachment) uid; }) attachments;
        })
      ];
    };
in
{
  flake.lib.homeFlake = config.flake // {
    inherit inputs;
  };

  flake.modules.nixos.home-manager-integration = integration "nixos";
  flake.modules.darwin.home-manager-integration = integration "darwin";
}
