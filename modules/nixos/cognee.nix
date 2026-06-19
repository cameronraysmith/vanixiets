# cognee knowledge-graph and memory service for magnetite.
#
# Credential generator catalog (slots; values populated as marked):
#   - cognee-jwt-secret: auto-generated (FastAPI Users JWT signing secret)
#   - cognee-default-user-password: auto-generated (bootstrap superuser password)
#   - cognee-openai-api-key: manual `clan vars set` (OpenAI API key for LLM + embeddings)
{
  config,
  inputs,
  ...
}:
let
  inherit (config.flake.lib.hosts) magnetite;
in
{
  flake.modules.nixos.cognee =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # The /64 ZeroTier prefix of magnetite's mesh address; the no-public-bind
      # assertion admits any address inside this prefix.
      ztPrefix = "fddb:4344:343b:14b9:";
      isLoopbackOrMesh = addr: addr == "127.0.0.1" || addr == "::1" || lib.hasPrefix ztPrefix addr;
      restBind = config.services.cognee.listenAddress;
      frontendBind = config.services.cognee.frontend.listenAddress;
      postgresBind = config.services.postgresql.settings.listen_addresses;
    in
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

      # PostgreSQL role password for the cognee role over loopback TCP
      # (auto-generated). Emitted twice from one value: `password` (plaintext,
      # consumed by the postgresql-setup ALTER ROLE below) and `env`
      # (DB_PASSWORD=... line, delivered to cognee via EnvironmentFile).
      clan.core.vars.generators.cognee-db-password = {
        files."password" = {
          owner = "postgres";
          restartUnits = [
            "cognee.service"
            "postgresql.service"
          ];
        };
        files."env" = {
          owner = "cognee";
          restartUnits = [
            "cognee.service"
            "postgresql.service"
          ];
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          password=$(openssl rand -hex 32)
          echo -n "$password" > $out/password
          echo -n "DB_PASSWORD=$password" > $out/env
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
        # Loopback TCP (not the /run/postgresql socket): a TCP host has no
        # leading "/", so cognee's alembic URL render-to-string round-trips
        # correctly and the pgvector engine's DB_PASSWORD gate is satisfiable.
        database.host = "127.0.0.1";

        vectorStore.backend = "pgvector";
        graphStore.backend = "ladybug";

        llm.provider = "openai";
        llm.model = "openai/gpt-5-mini";
        llm.embeddingModel = "openai/text-embedding-3-large";

        auth.multiTenant = false;
        # Provisional bootstrap account; confirm the canonical operator email.
        auth.defaultUserEmail = "cameron@scientistexperience.net";

        # The cognee MCP is abandoned entirely (client and server): the plugin
        # and cognee-cli talk REST directly, and codex/opencode declare no cognee
        # MCP, so nothing consumes the server-side MCP.
        mcp.enable = false;
        # The same-origin browser UI (D7/D10/§4.4). cognee-frontend is exposed
        # only as a flake `packages.<system>` output (the cognee-nix overlay puts
        # cognee in pythonPackagesExtensions but not the frontend), so
        # `pkgs.cognee-frontend` is null and the package must be taken from the
        # input directly. Bound loopback `127.0.0.1:3000` (listenAddress is the
        # hostname; the port stays at its 3000 default); the sso-gateway proxies
        # `/` to it. The runtime backend URL the frontend's server-side route
        # handlers read is wired below.
        frontend.enable = true;
        frontend.package = inputs.cognee-nix.packages.${config.nixpkgs.hostPlatform.system}.cognee-frontend;
        frontend.listenAddress = "127.0.0.1";
        openFirewall = false;
        workers = 1;

        # Bind the REST API to magnetite's deterministic ZeroTier IPv6 so the
        # always-on plugin and the cognee-cli wrapper reach the central graph
        # over the mesh, fail-closed (single types.str, no dual-bind): reachable
        # only over ZeroTier, never on the public interface. The public path
        # reaches REST exclusively through the kb nginx /api/ location behind the
        # oauth2-proxy gate.
        listenAddress = magnetite.zt;
        port = 9270;

        settings = {
          KUZU_BUFFER_POOL_SIZE = 2147483648;
          KUZU_MAX_DB_SIZE = 34359738368;
          KUZU_NUM_THREADS = 2;
          JWT_LIFETIME_SECONDS = 315360000;
          # Demand a logged-in user on every request (else HTTP 401, no
          # default-user fallback), mitigating the surface widening from binding
          # the full REST surface to the mesh. Rendered last into the unit env,
          # overriding the base env, with zero fork change. Multi-tenancy stays
          # off (auth.multiTenant = false keeps ENABLE_BACKEND_ACCESS_CONTROL
          # false), so all data remains in one global graph and vector store.
          REQUIRE_AUTHENTICATION = "true";
        };

        auth.jwtSecretFile = config.clan.core.vars.generators.cognee-jwt-secret.files."secret".path;
        auth.defaultUserPasswordFile =
          config.clan.core.vars.generators.cognee-default-user-password.files."password".path;
        llm.apiKeyFile = config.clan.core.vars.generators.cognee-openai-api-key.files."api-key".path;
        llm.embeddingApiKeyFile =
          config.clan.core.vars.generators.cognee-openai-api-key.files."api-key".path;
        environmentFile = config.clan.core.vars.generators.cognee-db-password.files."env".path;
      };

      # The retained ip_nonlocal_bind sysctl below makes a wrong public bind
      # silent, so promote the no-public-bind invariant to a build-time gate: the
      # REST API, the frontend, and postgres must each bind loopback or the
      # ZeroTier prefix. nginx 443 is the only public surface, reaching cognee
      # only through the oauth2-proxy.
      assertions = [
        {
          assertion =
            isLoopbackOrMesh restBind && isLoopbackOrMesh frontendBind && isLoopbackOrMesh postgresBind;
          message = ''
            cognee no-public-bind invariant violated: every cognee listener must
            bind loopback (127.0.0.1/::1) or the ZeroTier prefix ${ztPrefix}*/64.
            Resolved binds:
              REST listenAddress = ${restBind}
              frontend listenAddress = ${frontendBind}
              postgres listen_addresses = ${postgresBind}
            A public bind would be silent under the retained ip_nonlocal_bind=1.
          '';
        }
      ];

      # Loopback TCP for the local postgres provisioned by createLocally, with
      # scram-password auth for the cognee role (merges additively with the
      # upstream createLocally block).
      services.postgresql = {
        # Loopback only: magnetite is multi-homed (public + ZeroTier), so 5432
        # must never leave 127.0.0.1. enableTCPIP would set listen_addresses="*".
        settings.listen_addresses = lib.mkForce "127.0.0.1";
        settings.password_encryption = "scram-sha-256";
        # First-match-wins: this scram rule for the cognee role must precede the
        # broad `host all all 127.0.0.1/32 md5` default (added via mkAfter).
        authentication = lib.mkBefore ''
          host cognee cognee 127.0.0.1/32 scram-sha-256
          host cognee cognee ::1/128      scram-sha-256
        '';
      };

      # Set the cognee role password idempotently after postgresql-setup creates
      # the role (ALTER ROLE is idempotent). Reads the plaintext from the
      # clan-vars file and feeds the SQL via stdin heredoc so the secret never
      # appears in psql's argv. Runs in the postgresql-setup context as the
      # postgres superuser over the local socket.
      systemd.services.postgresql-setup.serviceConfig.ExecStartPost = lib.mkAfter [
        (pkgs.writeShellScript "cognee-set-role-password" ''
          set -eu
          password="$(cat ${config.clan.core.vars.generators.cognee-db-password.files."password".path})"
          ${lib.getExe' config.services.postgresql.package "psql"} -d postgres -v ON_ERROR_STOP=1 <<EOF
          ALTER ROLE cognee PASSWORD '$password';
          EOF
        '')
      ];

      # Resource caps for a colocated build host (merges additively with the
      # serviceConfig the cognee module already sets; no key collisions).
      systemd.services.cognee.serviceConfig = {
        MemoryMax = "4G";
        MemoryHigh = "3G";
        CPUWeight = 20;
        IOWeight = 20;
        Nice = 10;
      };

      # The frontend's two server-side Node route handlers read
      # NEXT_PUBLIC_LOCAL_API_URL at runtime (Turbopack preserves the process.env
      # read for server code), so they reach the backend over the mesh REST URL.
      # The browser client already has same-origin "" baked in at build time
      # (D11) and ignores this runtime value. Merges additively with the
      # environment the cognee-frontend service already sets.
      systemd.services.cognee-frontend.environment.NEXT_PUBLIC_LOCAL_API_URL =
        "http://[${magnetite.zt}]:9270";

      # Permit cognee to bind magnetite's ZeroTier-assigned IPv6 REST address
      # before zerotierone settles on cold boot (mirrors
      # modules/machines/nixos/cinnabar/caddy.nix). Load-bearing for the REST
      # ZeroTier bind, not the (now-removed) MCP. The zt+ firewall below remains
      # the access boundary, and the no-public-bind assertion above is the
      # build-time gate that a non-local bind would otherwise pass silently.
      boot.kernel.sysctl = {
        "net.ipv6.ip_nonlocal_bind" = 1;
        "net.ipv4.ip_nonlocal_bind" = 1;
      };

      # Expose the cognee REST API on the ZeroTier mesh only.
      networking.firewall.interfaces."zt+".allowedTCPPorts = [ 9270 ];
    };
}
