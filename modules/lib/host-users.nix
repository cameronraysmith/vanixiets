# Host-user attachments: flake.fleet.hosts.<host>.users.<account>, one record
# per account a person holds on a host, declared here once for every host.
# The option merges into lib/hosts.nix's host submodule. From these records
# are generated: the clan user instances' machine lists (hostsOfAccount),
# each host's primaryUser (lib/hosts.nix), nix-darwin's admin account and the
# darwin uids, the secret bridge and the homes (system/home-manager-
# integration.nix), and the home checks' user lists (checks/home.nix).
# Omnigent worker accounts have no attachment: they belong to the worker
# relation (lib/fleet-workers.nix) and the omnigent-host modules.
#
# A field that contradicts the host's class, or an account that is not a
# flake.users key, throws when it is read, naming the field, as the
# registry's other class constraints do.
{ config, lib, ... }:
let
  inherit (lib) types;
  flakeConfig = config;
  homeModules = config.flake.modules.homeManager;

  hostUsersModule =
    { name, config, ... }:
    let
      host = config;
      where = "flake.fleet.hosts.${name}.users";
      attachmentModule =
        { name, ... }:
        let
          at = "${where}.${name}";
        in
        {
          options = {
            primary = lib.mkOption {
              type = types.bool;
              default = false;
              description = "Whether this account is the person the host belongs to.";
            };
            admin = lib.mkOption {
              type = types.bool;
              default = false;
              apply =
                v:
                assert lib.assertMsg (!v || host.class == "darwin")
                  "${at}.admin: true on a ${host.class} host; only a darwin host has an admin attachment (NixOS administration is the clan user instance's groups)";
                v;
              description = "Whether this account is nix-darwin's admin account (system.primaryUser).";
            };
            sopsBridge = lib.mkOption {
              type = types.bool;
              default = host.class == "nixos";
              defaultText = lib.literalExpression ''class == "nixos"'';
              apply =
                v:
                assert lib.assertMsg (!v || host.class == "nixos")
                  "${at}.sopsBridge: true on a ${host.class} host, which has no age-key bridge (the darwin hm-sops-bridge module sets only the secrets view)";
                v;
              description = "Whether the person's personal age key is bridged to the account (hm-sops-bridge).";
            };
            uid = lib.mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              apply =
                v:
                assert lib.assertMsg (
                  (v != null) == (host.class == "darwin")
                ) "${at}.uid: ${builtins.toJSON v} does not fit a ${host.class} host (darwin a uid, nixos null)";
                v;
              description = "The account's uid on a darwin host; null on NixOS, where clan allocates it.";
            };
            shellAndKeysFromUserService = lib.mkOption {
              type = types.bool;
              default = false;
              description = "Whether the account's clan user service sets its login shell and SSH authorized keys (modules/clan/inventory/services/users/cameron.nix and users/tara.nix do), so the host modules must not set them. A fact about the account: every attachment of one account states the same value (flake.lib.shellAndKeysFromUserService).";
            };
            extraImports = lib.mkOption {
              # raw, not deferredModule: a deferredModule list wraps each
              # module in a fresh one, losing its key, so a module also
              # imported by the person's aggregates would apply twice and
              # reorder the home's lists.
              type = types.listOf types.raw;
              default = [ ];
              description = "Home modules this pair imports beyond the person's own.";
            };
            overrides = lib.mkOption {
              type = types.deferredModule;
              default = { };
              description = "A home-manager module for this pair; it may take osConfig and pkgs.";
            };
          };
        };
    in
    {
      options.users = lib.mkOption {
        type = types.attrsOf (types.submodule attachmentModule);
        default = { };
        apply =
          users:
          let
            names = lib.attrNames users;
            unknown = lib.filter (n: !(flakeConfig.flake.users ? ${n})) names;
            admins = lib.filter (n: users.${n}.admin) names;
          in
          assert lib.assertMsg (
            unknown == [ ]
          ) "${where}: ${lib.concatStringsSep ", " unknown} is not a flake.users key";
          assert lib.assertMsg (host.class != "darwin" || lib.length admins == 1)
            "${where}: a darwin host has exactly one attachment with admin = true, found ${toString (lib.length admins)} (${lib.concatStringsSep ", " admins})";
          users;
        description = "The accounts people hold on the host, keyed by account name (a flake.users key).";
      };
    };
in
{
  options.flake.fleet.hosts = lib.mkOption {
    type = types.attrsOf (types.submodule hostUsersModule);
  };

  config.flake.fleet.hosts = {
    cinnabar.users.cameron.shellAndKeysFromUserService = true;
    electrum.users.cameron.shellAndKeysFromUserService = true;
    galena.users = {
      cameron.shellAndKeysFromUserService = true;
      tara = {
        shellAndKeysFromUserService = true;
        overrides.programs.agents-md.enable = false;
      };
    };
    scheelite.users = {
      cameron.shellAndKeysFromUserService = true;
      tara = {
        shellAndKeysFromUserService = true;
        overrides.programs.agents-md.enable = false;
      };
    };
    magnetite.users.cameron.shellAndKeysFromUserService = true;
    pyrite.users.cameron = {
      primary = true;
      shellAndKeysFromUserService = true;
      extraImports = with homeModules; [
        niri
        dms
        zen-browser
        bitwarden-key-pins
        linux-workstation
        night-light
      ];
      overrides =
        { osConfig, ... }:
        {
          # Validate with the exact derivation installed by nixpkgs' NixOS module.
          programs.niri.package = osConfig.programs.niri.package;
          # The omnigraph desktop client, on a workstation used at a display.
          programs.omnigraph.studio.enable = true;
        };
    };
    stibnite.users.crs58 = {
      primary = true;
      admin = true;
      uid = 501;
      extraImports = [ homeModules.bitwarden-key-pins ];
      overrides =
        { pkgs, lib, ... }:
        {
          # mkAfter places these after the person's own packages: modules are collected
          # breadth-first and merged in reverse, so a module's own list definitions
          # follow only those of its direct imports (world assumption A344).
          home.packages = lib.mkAfter [
            pkgs.aeneas
            (lib.hiPrio pkgs.charon)
            pkgs.elan
          ];
          # Incus k3s profiles (see ADR-004): instance profiles for k3s
          # clusters in Colima.
          incus.k3sProfiles.k3s-dev.ip = "192.100.0.10";
          programs.omnigraph.studio.enable = true;
        };
    };
    # raquel is deployed while she has no screen session on blackphos, so her
    # home may run no gui-domain launchd agent.
    blackphos.users = {
      crs58 = {
        admin = true;
        uid = 502;
      };
      raquel = {
        primary = true;
        uid = 506;
        overrides.deploysWithoutScreenSession = true;
      };
    };
    # Both laptop accounts are deployed while they have no screen session on
    # the laptop, so neither may run a gui-domain launchd agent.
    argentum.users = {
      christophersmith = {
        primary = true;
        uid = 501;
        overrides.deploysWithoutScreenSession = true;
      };
      cameron = {
        admin = true;
        uid = 502;
        shellAndKeysFromUserService = true;
        overrides.deploysWithoutScreenSession = true;
      };
    };
    rosegold.users = {
      janettesmith = {
        primary = true;
        uid = 501;
        overrides.deploysWithoutScreenSession = true;
      };
      cameron = {
        admin = true;
        uid = 502;
        shellAndKeysFromUserService = true;
        overrides.deploysWithoutScreenSession = true;
      };
    };
  };

  # The sorted names of the hosts with an attachment for `account`.
  config.flake.lib.hostsOfAccount =
    account:
    lib.attrNames (lib.filterAttrs (_: host: host.users ? ${account}) config.flake.fleet.hosts);

  # Whether `account`'s clan user service sets its login shell and SSH
  # authorized keys, read from its attachments. The fact is the account's, so
  # every attachment of the account must state the same value; reading it
  # fails, naming the hosts on each side, when they disagree.
  config.flake.lib.shellAndKeysFromUserService =
    account:
    let
      byValue = lib.partition (
        host: config.flake.fleet.hosts.${host}.users.${account}.shellAndKeysFromUserService
      ) (config.flake.lib.hostsOfAccount account);
    in
    assert lib.assertMsg (byValue.right == [ ] || byValue.wrong == [ ])
      "flake.fleet.hosts.<host>.users.${account}.shellAndKeysFromUserService: the attachments of ${account} disagree: true on ${lib.concatStringsSep ", " byValue.right}, false on ${lib.concatStringsSep ", " byValue.wrong}";
    byValue.right != [ ];
}
