{
  clan.inventory.instances.hermes-agent = {
    module = {
      name = "hermes-agent";
      input = "self";
    };
    roles.default.machines."cinnabar" = {
      settings = {
        serviceUser = "cameron";
        stateDir = "/home/cameron/.hermes";
        openrouterApiKeyGenerator = "hermes-openrouter-api-key";
        matrixBotPasswordGenerator = "matrix-password-hermes";
        matrixServerName = "matrix.zt";
        matrixUserName = "hermes";
        port = 18791;
        dashboardPort = 18790;
        channelsAllowlist = [ "@cameron:matrix.zt" ];
        configOverrides = {
          # Mirror openclaw's autoJoin posture so the bot accepts DM invites.
          channels.matrix.autoJoin = "always";
        };
      };
    };
  };
}
