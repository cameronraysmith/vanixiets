# cognee knowledge-graph and memory service for magnetite.
#
# Credential generator catalog (slots; values populated as marked):
#   - cognee-jwt-secret: auto-generated (FastAPI Users JWT signing secret)
#   - cognee-default-user-password: auto-generated (bootstrap superuser password)
#   - cognee-openai-api-key: manual `clan vars set` (OpenAI API key for LLM + embeddings)
{
  config,
  ...
}:
{
  flake.modules.nixos.cognee =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      # FastAPI Users JWT signing secret (auto-generated)
      clan.core.vars.generators.cognee-jwt-secret = {
        files."secret" = {
          owner = "cognee";
          restartUnits = [ "cognee.service" ];
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          openssl rand -hex 32 > $out/secret
        '';
      };

      # Bootstrap default superuser password (auto-generated)
      clan.core.vars.generators.cognee-default-user-password = {
        files."password" = {
          owner = "cognee";
          restartUnits = [ "cognee.service" ];
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          openssl rand -hex 32 > $out/password
        '';
      };

      # OpenAI API key for LLM and embeddings (populated manually via clan vars set)
      clan.core.vars.generators.cognee-openai-api-key = {
        files."api-key" = {
          owner = "cognee";
          restartUnits = [ "cognee.service" ];
        };
        script = ''
          echo "cognee OpenAI API key: populate via clan vars set" >&2
          exit 1
        '';
      };

      services.cognee = {
        enable = true;

        database.createLocally = true;
        database.enablePgvector = true;

        vectorStore.backend = "pgvector";
        graphStore.backend = "ladybug";

        llm.provider = "openai";
        llm.model = "openai/gpt-5-mini";
        llm.embeddingModel = "openai/text-embedding-3-large";

        auth.multiTenant = false;
        # Provisional bootstrap account; confirm the canonical operator email.
        auth.defaultUserEmail = "cameron@scientistexperience.net";

        mcp.enable = false;
        frontend.enable = false;
        openFirewall = false;
        workers = 1;

        # Binds magnetite's deterministic ZeroTier IPv6. The cognee-nix gunicorn
        # `--bind ${listenAddress}:${port}` does not bracket an IPv6 literal, so a
        # correct runtime bind requires the in-flight IPv6-bracket fix on the
        # cognee-v112 fork; until that fork is re-pinned the rendered --bind is
        # malformed at runtime only (nix eval/build are unaffected).
        listenAddress = "fddb:4344:343b:14b9:399:930f:39db:40d2";

        settings = {
          KUZU_BUFFER_POOL_SIZE = 2147483648;
          KUZU_MAX_DB_SIZE = 34359738368;
          KUZU_NUM_THREADS = 2;
          JWT_LIFETIME_SECONDS = 315360000;
        };

        auth.jwtSecretFile = config.clan.core.vars.generators.cognee-jwt-secret.files."secret".path;
        auth.defaultUserPasswordFile =
          config.clan.core.vars.generators.cognee-default-user-password.files."password".path;
        llm.apiKeyFile = config.clan.core.vars.generators.cognee-openai-api-key.files."api-key".path;
        llm.embeddingApiKeyFile = config.clan.core.vars.generators.cognee-openai-api-key.files."api-key".path;
      };

      # Resource caps for a colocated build host (merges additively with the
      # serviceConfig the cognee module already sets; no key collisions).
      systemd.services.cognee.serviceConfig = {
        MemoryMax = "4G";
        MemoryHigh = "3G";
        CPUWeight = 20;
        IOWeight = 20;
        Nice = 10;
      };

      # Permit binding the ZeroTier-assigned address before zerotierone settles
      # on cold boot (mirrors modules/machines/nixos/cinnabar/caddy.nix). The zt+
      # firewall below remains the access boundary.
      boot.kernel.sysctl = {
        "net.ipv6.ip_nonlocal_bind" = 1;
        "net.ipv4.ip_nonlocal_bind" = 1;
      };

      # Expose the cognee API port on the ZeroTier mesh only.
      networking.firewall.interfaces."zt+".allowedTCPPorts = [ 8000 ];
    };
}
