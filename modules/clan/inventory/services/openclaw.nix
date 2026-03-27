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
          channels.matrix.allowPrivateNetwork = true;
          gateway.controlUi.allowedOrigins = [ "https://openclaw.zt" ];
          gateway.auth.mode = "trusted-proxy";
          gateway.auth.trustedProxy.userHeader = "x-forwarded-user";
        };
      };
    };
  };
}
