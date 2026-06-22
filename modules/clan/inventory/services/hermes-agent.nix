{
  clan.inventory.instances.hermes-agent = {
    module = {
      name = "hermes-agent";
      input = "self";
    };
    roles.default.machines."cinnabar" = {
      settings = {
        serviceUser = "cameron";
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
        # Matrix home channel — receives cron-job results and cross-platform
        # messages. The "cron" room (!Tthf05aI9YvVVsCF2d:matrix.zt) has the
        # hermes user as a member; the bot joined on invite per upstream's
        # hardcoded _on_invite handler (matrix.py:1979-1988).
        homeRoom = "!Tthf05aI9YvVVsCF2d:matrix.zt";
        homeRoomName = "cron";
        configOverrides = {
          # Mirror openclaw's autoJoin posture so the bot accepts DM invites.
          channels.matrix.autoJoin = "always";
          # Default model for the gateway. Dict form per upstream
          # hermes_cli/inventory.py:88-97; wimpysworld follows the same shape
          # at hermes/default.nix:750-753. OPENROUTER_API_KEY is wired via
          # clan-vars (commit mkuxxzwl). Slug verified in the dashboard model
          # picker (31 OpenRouter models listed).
          model = {
            provider = "openrouter";
            default = "z-ai/glm-5.2";
          };
          # Dashboard theme (lowercase canonical per hermes_cli/config.py:1010-1012;
          # valid values: default, midnight, ember, mono, cyberpunk, rose).
          dashboard.theme = "mono";
        };
      };
    };
  };
}
