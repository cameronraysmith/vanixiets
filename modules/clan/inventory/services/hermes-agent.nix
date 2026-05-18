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
        # Colocated tuwunel listens on 127.0.0.1 + ::1 at matrixPort (8008 as
        # configured at modules/machines/nixos/cinnabar/matrix.nix). The
        # clan inventory layer is pure-static (no `config.*` visibility), so
        # the port is duplicated here as a literal rather than derived from
        # config.services.matrix-tuwunel.settings.global.port. Keep this
        # value in sync with matrixPort in matrix.nix if the tuwunel port
        # is ever reconfigured.
        matrixHomeserverUrl = "http://localhost:8008";
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
