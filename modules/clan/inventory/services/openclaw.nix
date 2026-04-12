{
  clan.inventory.instances.openclaw = {
    module = {
      name = "openclaw";
      input = "self";
    };
    roles.default.machines."cinnabar" = {
      settings = {
        homeserver = "http://localhost:8008";
        botUserName = "clawd";
        matrixServerName = "matrix.zt";
        port = 18789;
        serviceUser = "cameron";
        gatewayMode = "local";
        matrixBotPasswordGenerator = "matrix-password-clawd";
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
