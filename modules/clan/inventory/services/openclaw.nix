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
          # Disable health monitor: v2026.3.2 stale-socket false positive.
          # Matrix provider lacks setStatus callback so lastEventAt is never
          # updated, triggering a restart every 30 minutes. Fixed in HEAD.
          gateway.channelHealthCheckMinutes = 0;
        };
      };
    };
  };
}
