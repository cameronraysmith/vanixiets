{
  config,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.darwin;
  inherit (config.flake.lib) hosts shellAndKeysFromUserService;
in
{
  # The shape of a Mac in the fleet: a host imports it and states only its
  # delta (hostName, casks, dnscrypt-proxy). argentum, rosegold and blackphos
  # import it; stibnite does not yet, because importing it reorders two of
  # stibnite's lists (openspec/changes/compose-hosts-from-cohesive-aspects,
  # design Open Question 11).
  flake.modules.darwin.darwin-workstation =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      inherit (config.networking) hostName;
      attachments = hosts.${hostName}.users;
      # The human accounts in ascending uid order. The order is chosen to
      # reproduce each Mac's existing users.knownUsers list and is not
      # otherwise meaningful.
      humans = lib.sort (a: b: attachments.${a}.uid < attachments.${b}.uid) (lib.attrNames attachments);
    in
    {
      # dnscrypt-proxy and fleet-services-trust are imported on every darwin host
      # so that enabling them is the per-host decision rather than importing
      # them being it. Both are inert until enabled.
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
        # Documentation on: srvos and clan-core default it off with mkDefault,
        # which a plain value overrides.
        srvos.server.docs.enable = true;
        documentation.enable = true;
        documentation.doc.enable = true;
        documentation.info.enable = true;
        documentation.man.enable = true;
        programs.info.enable = true;
        programs.man.enable = true;

        networking.computerName = hostName;

        # Remote deployment target, clan's fallback after the network peers
        # (flake.lib.hosts.<name>.targetHost, the single source).
        clan.core.networking.targetHost = hosts.${hostName}.targetHost;

        # system.primaryUser follows the admin attachment
        # (system/home-manager-integration.nix).

        # Operator claim (modules/darwin/sshd-declaration.nix): a workstation
        # accepts inbound SSH so it can be deployed to from stibnite over zerotier.
        declaredSshd.serving = true;

        users.users = lib.genAttrs humans (
          account:
          {
            home = "/Users/${account}";
            description = account;
          }
          // lib.optionalAttrs (!shellAndKeysFromUserService account) {
            shell = pkgs.zsh;
            openssh.authorizedKeys.keys = inputs.self.users.${account}.meta.sshKeys;
          }
        );

        # Darwin requires explicit knownUsers; root is deliberately unmanaged
        users.knownUsers = humans;
      };
    };
}
