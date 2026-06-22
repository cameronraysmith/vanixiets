{
  clan.inventory.instances.openclaw = {
    module = {
      name = "openclaw";
      input = "self";
    };
    roles.default.machines."cinnabar" = {
      settings = {
        # Deprecation toggle: flip to false to disable openclaw on cinnabar
        # (gateway, config, generators, vhost, and DNS) while retaining this
        # inventory instance for a later removal phase.
        enable = true;
        homeserver = "http://localhost:8008";
        botUserName = "clawd";
        matrixServerName = "matrix.zt";
        port = 18789;
        serviceUser = "cameron";
        gatewayMode = "local";
        matrixBotPasswordGenerator = "matrix-password-clawd";
        listenAddresses = [
          "fddb:4344:343b:14b9:399:93db:4344:343b"
          "10.147.17.1"
        ];
        configOverrides = {
          channels.matrix.groupPolicy = "open";
          channels.matrix.network.dangerouslyAllowPrivateNetwork = true;
          # clawd defaults to autoJoin "off", ignoring DM invites
          channels.matrix.autoJoin = "always";
          channels.matrix.dm = {
            enabled = true;
            policy = "allowlist";
            allowFrom = [ "@cameron:matrix.zt" ];
          };
          gateway.controlUi.allowedOrigins = [ "https://openclaw.zt" ];
        };
      };
    };
  };
}
