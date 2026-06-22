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
          # Chat: OpenRouter primary (burn glm-5.2 credits) -> Nous first
          # fallback. base_url pinned so the activation merge overwrites the
          # imperative leftover (the Portal interactive setup wrote a Nous
          # base_url); runtime_provider honors model.base_url only for
          # auto/custom providers, so for openrouter this only cleans the
          # stale leaf. OPENROUTER_API_KEY is wired via clan-vars.
          model = {
            provider = "openrouter";
            default = "z-ai/glm-5.2";
            base_url = "https://openrouter.ai/api/v1";
          };

          # Full ordered fallback chain. The settings merge replaces lists
          # wholesale (recursiveUpdate / configMergeScript dict-only recursion),
          # so the whole chain is declared here; a nous entry missing `model`
          # is silently dropped (hermes_cli/fallback_config.py).
          fallback_providers = [
            {
              provider = "openrouter";
              model = "z-ai/glm-5.2";
            }
            {
              provider = "nous";
              model = "z-ai/glm-5.2";
            }
            {
              provider = "openrouter";
              model = "openai/gpt-5.5";
            }
          ];

          # Auxiliary model client + subagent delegation -> Nous first-line.
          # The built-in "auto" chain prefers the main provider (OpenRouter)
          # before Nous, so explicit provider=nous per task is required.
          auxiliary = {
            vision.provider = "nous";
            web_extract.provider = "nous";
            compression.provider = "nous";
            skills_hub.provider = "nous";
            approval.provider = "nous";
            mcp.provider = "nous";
            title_generation.provider = "nous";
            tts_audio_tags.provider = "nous";
            triage_specifier.provider = "nous";
            kanban_decomposer.provider = "nous";
            profile_describer.provider = "nous";
            curator.provider = "nous";
            monitor.provider = "nous";
          };
          delegation.provider = "nous";

          # Nous Tool Gateway: every managed capability on Nous's recommended
          # providers, billed to the subscription (no per-vendor keys).
          # use_gateway routes through the gateway regardless of direct keys;
          # inert until `hermes auth add nous` + tool_gateway entitlement.
          web = {
            backend = "firecrawl";
            use_gateway = true;
          };
          image_gen = {
            provider = "fal";
            use_gateway = true;
          };
          video_gen = {
            provider = "fal";
            use_gateway = true;
          };
          tts = {
            provider = "openai";
            use_gateway = true;
          };
          # Local on-box STT via faster-whisper (from the `voice` extra +
          # ffmpeg/portaudio service deps), NOT the gateway. Model weights
          # (tiny/base/small/medium/large-v3) fetch from HuggingFace on first
          # use; larger = more accurate, slower, bigger download.
          stt = {
            enabled = true;
            provider = "local";
            local.model = "base";
          };
          browser = {
            cloud_provider = "browser-use";
            use_gateway = true;
          };

          # Dashboard theme (lowercase canonical per hermes_cli/config.py:1010-1012;
          # valid values: default, midnight, ember, mono, cyberpunk, rose).
          dashboard.theme = "mono";
        };
      };
    };
  };
}
