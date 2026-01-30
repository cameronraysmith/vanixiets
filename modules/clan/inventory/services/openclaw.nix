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
      };
    };
  };
}
