# The home-manager integration of every NixOS and darwin host, generated from
# the host's user attachments (flake.fleet.hosts.<host>.users,
# lib/host-users.nix): one home per attachment, the secret bridge (NixOS), and
# nix-darwin's admin account, the attached accounts' uids and the
# activation-time comparison of those uids with each account's real uid
# (darwin).
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

      options.home-manager-integration.uidPreflight = lib.mkOption {
        type = lib.types.lines;
        internal = true;
        readOnly = true;
        description = "The activation-time comparison of each attached account's uid with its record (darwin; empty on NixOS).";
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
          # Clan allocates NixOS uids; there is nothing to compare.
          home-manager-integration.uidPreflight = "";
        })
        (lib.optionalAttrs (class == "darwin") {
          # nix-darwin's admin account, never inferred from the primary user.
          system.primaryUser = lib.mkIf (admins != [ ]) (lib.head admins);
          users.users = lib.mapAttrs (_: attachment: { inherit (attachment) uid; }) attachments;

          # nix-darwin warns about and skips an existing account whose uid is
          # not users.users.<a>.uid, and activation succeeds. This comparison
          # runs first in `activate` (preActivation, under set -e, before
          # nix-darwin's checks and every step that changes the Mac; also under
          # `darwin-rebuild check`, not in the boot-time activate-system
          # daemon) and fails on every attached account that exists with
          # another uid. An absent account passes: nix-darwin creates it with
          # the recorded uid. String comparison, so a non-numeric `id` output
          # is a mismatch. Order 600: after deploy-record's mkBefore read of
          # /run/current-system (system/deploy-record.nix), which changes
          # nothing, and before nix-darwin's own preActivation text at the
          # default priority, which removes a leftover /var/lib/linux-builder.
          # checks.x86_64-linux.darwin-uid-preflight runs this text under a
          # stub `id`.
          home-manager-integration.uidPreflight = ''
            # home-manager-integration: each attached account's uid against its record
            uidMismatches=()
            ${lib.concatMapStringsSep "\n" (
              account:
              let
                uid = toString attachments.${account}.uid;
              in
              ''
                u=$(id -u ${lib.escapeShellArg account} 2>/dev/null) || u=
                if [[ -n "$u" && "$u" != ${uid} ]]; then
                  uidMismatches+=(${lib.escapeShellArg "${hostName}: account ${account} has uid "}"$u"${lib.escapeShellArg ", recorded ${uid} at flake.fleet.hosts.${hostName}.users.${account}.uid"})
                fi''
            ) accounts}
            if (( ''${#uidMismatches[@]} )); then
              printf >&2 '\e[1;31merror: an attached account has a uid other than its record, aborting activation\e[0m\n'
              printf >&2 '  %s\n' "''${uidMismatches[@]}"
              printf >&2 'Correct the record in modules/lib/host-users.nix, or the account, and deploy again.\n'
              exit 1
            fi
          '';
          system.activationScripts.preActivation.text = lib.mkOrder 600 config.home-manager-integration.uidPreflight;
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
