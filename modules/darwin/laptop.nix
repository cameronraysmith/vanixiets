{
  config,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.darwin;
  inherit (config.flake.lib) hosts;
in
{
  flake.modules.darwin.laptop =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      inherit (config.networking) hostName;
      # The login user at uid 501, from the host's attachments.
      inherit (hosts.${hostName}) primaryUser;
    in
    {
      # dnscrypt-proxy and fleet-services-trust are imported on every darwin host
      # so that enabling them is the per-host decision rather than importing
      # them being it. Both are inert until enabled; laptops enable
      # dnscrypt-proxy and not fleet-services-trust.
      imports = [
        inputs.home-manager.darwinModules.home-manager
        inputs.srvos.darwinModules.server
      ]
      ++ (with flakeModules; [
        base
        home-manager-integration
        deploy-record
        ssh-ca-trust
        ssh-known-hosts
        dnscrypt-proxy
        zt-dns
        fleet-services-trust
      ]);

      config = {
        # Override both srvos and clan-core defaults, which disable documentation
        srvos.server.docs.enable = lib.mkForce true;
        documentation.enable = lib.mkForce true;
        documentation.doc.enable = lib.mkForce true;
        documentation.info.enable = lib.mkForce true;
        documentation.man.enable = lib.mkForce true;
        programs.info.enable = lib.mkForce true;
        programs.man.enable = lib.mkForce true;

        networking.computerName = hostName;

        # Remote deployment target, clan's fallback after the network peers
        # (flake.lib.hosts.<name>.targetHost, the single source).
        clan.core.networking.targetHost = hosts.${hostName}.targetHost;

        # Override base.nix which sets stateVersion = 5
        system.stateVersion = lib.mkForce 4;

        # cameron is the admin user and manages homebrew: system.primaryUser
        # follows the admin attachment (system/home-manager-integration.nix).

        custom.profile.isDesktop = true;

        # Omitted developer casks: dbeaver-community, docker-desktop,
        # gpg-suite, inkscape, keycastr, meld, postgres-app
        custom.homebrew = {
          enable = true;
          additionalCasks = [
            "zerotier-one"
          ];
        };

        # Operator claim (modules/darwin/sshd-declaration.nix): laptops accept
        # inbound SSH so they can be deployed to from stibnite over zerotier.
        declaredSshd.serving = true;

        services.localDnscryptProxy = {
          enable = true;
          providers = [
            "quad9"
          ];
          userHome = "/private/var/lib/dnscrypt-proxy";
        };

        users.users.${primaryUser} = {
          home = "/Users/${primaryUser}";
          shell = pkgs.zsh;
          description = primaryUser;
          openssh.authorizedKeys.keys = inputs.self.users.${primaryUser}.meta.sshKeys;
        };

        users.users.cameron = {
          home = "/Users/cameron";
          # shell and authorizedKeys provided by cameron inventory service
          description = "cameron";
        };

        # Darwin requires explicit knownUsers; root is deliberately unmanaged
        users.knownUsers = [
          primaryUser
          "cameron"
        ];
      };
    };
}
