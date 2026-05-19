{ inputs, ... }:
{
  clan.modules.hermes-agent =
    { ... }:
    {
      _class = "clan.service";
      manifest.name = "hermes-agent";
      manifest.description = "Hermes Agent (NousResearch) deployed as a clan service, importing upstream's nixosModule and adapting clan-vars secrets to environmentFiles";
      manifest.categories = [
        "AI"
        "Communication"
      ];
      manifest.readme = builtins.readFile ./README.md;

      roles.default = {
        description = "Runs the hermes-agent gateway and dashboard, importing upstream's NixOS module";

        interface =
          { lib, ... }:
          {
            options = {
              serviceUser = lib.mkOption {
                type = lib.types.str;
                default = "cameron";
                description = "Unix user to run hermes-agent as (createUser=false posture)";
              };

              openrouterApiKeyGenerator = lib.mkOption {
                type = lib.types.str;
                default = "hermes-openrouter-api-key";
                description = "Name of the clan-vars generator producing the OPENROUTER_API_KEY env file (wired by nix-gyy.3, populated by nix-gyy.4)";
              };

              matrixBotPasswordGenerator = lib.mkOption {
                type = lib.types.str;
                default = "matrix-password-hermes";
                description = "Name of the clan-vars generator producing the MATRIX_PASSWORD env file (wired by nix-gyy.3, populated by nix-gyy.4)";
              };

              matrixServerName = lib.mkOption {
                type = lib.types.str;
                default = "matrix.zt";
                description = "Matrix homeserver hostname for the bot user_id localpart suffix";
              };

              matrixUserName = lib.mkOption {
                type = lib.types.str;
                default = "hermes";
                description = "Matrix bot username (localpart of the bot's MXID)";
              };

              matrixHomeserverUrl = lib.mkOption {
                type = lib.types.str;
                default = "http://localhost:8008";
                description = ''
                  API endpoint the hermes-agent matrix adapter uses to talk to the matrix
                  homeserver. Set to the matrix server's client-server API URL (typically
                  http://localhost:8008 for a colocated tuwunel/Synapse on the standard
                  port, or https://matrix.example.com for a remote homeserver).

                  Note: distinct from the protocol-level server_name (which is encoded in
                  user_ids via matrixServerName). For colocated deployments where the
                  bot reaches the homeserver via loopback HTTP, the bot bypasses
                  public-facing TLS termination (e.g. caddy with tls internal) avoiding
                  cert-verification failures against the system trust store.
                '';
              };

              port = lib.mkOption {
                type = lib.types.port;
                default = 18791;
                description = "Hermes gateway listen port (loopback bind; adjacent to openclaw 18789)";
              };

              dashboardPort = lib.mkOption {
                type = lib.types.port;
                default = 18790;
                description = "Hermes dashboard listen port (loopback bind; reverse-proxied by nginx on hermes.zt)";
              };

              channelsAllowlist = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                example = [ "@cameron:matrix.zt" ];
                description = "Matrix MXIDs allowed to DM the bot";
              };

              configOverrides = lib.mkOption {
                type = lib.types.attrs;
                default = { };
                description = "Additional config merged on top of the generated hermes-agent settings via lib.recursiveUpdate";
              };
            };
          };

        perInstance =
          { settings, ... }:
          {
            nixosModule =
              {
                config,
                lib,
                pkgs,
                ...
              }:
              let
                # Derive service user's $HOME from the canonical NixOS option.
                # Upstream's services.hermes-agent.stateDir semantically means "service user's
                # $HOME" (upstream description: "Contains .hermes/ subdir (HERMES_HOME)"). We
                # derive instead of hardcoding `/home/<user>` so the value is filesystem-layout-
                # aware (Linux /home/<user>, Darwin /Users/<user>, custom paths if user record
                # overrides).
                userHome = config.users.users.${settings.serviceUser}.home;

                # ─── clan-vars → environmentFiles adapter (nix-gyy.3) ───────
                # Openclaw's wrapper-cat pattern (export VAR="$(cat path)" at exec)
                # does NOT translate to hermes-agent: upstream's activation script
                # cat-appends each environmentFiles entry into
                # ${stateDir}/.hermes/.env (see nixosModules.nix:826-838) which
                # load_hermes_dotenv() reads at python startup. systemd
                # EnvironmentFile= is not consulted.
                #
                # Contract for clan-vars generator output (enforced in nix-gyy.4):
                #   - Each generator's file content MUST be `KEY=value\n` env-file
                #     format. The contents are concatenated verbatim into .env.
                #   - Raw secret material (no `KEY=` prefix) would corrupt the file.
                #
                # Secret-rotation constraint:
                #   - Rotating a secret requires `nixos-rebuild switch` because
                #     activation bakes file contents into stateDir/.hermes/.env.
                #   - `systemctl restart hermes-agent` alone WILL NOT pick up new
                #     secret material; the .env file remains the previous content.
                varsDir = config.clan.core.vars.generators;
                openrouterEnvPath = varsDir.${settings.openrouterApiKeyGenerator}.files."OPENROUTER_API_KEY".path;
                matrixPasswordEnvPath = varsDir.${settings.matrixBotPasswordGenerator}.files."MATRIX_PASSWORD".path;
              in
              {
                imports = [ inputs.hermes-agent.nixosModules.default ];

                # Issue nix-gyy.2 only scaffolds the wrapper. Issues 3, 4, 5, 6, 7 fill in:
                #   - clan-vars-to-environmentFiles adapter (nix-gyy.3)
                #   - clan-vars generators (nix-gyy.4)
                #   - mkForce hardening tuning (nix-gyy.5)
                #   - sibling hermes-agent-dashboard systemd unit (nix-gyy.6)
                #   - matrix wiring & deep settings merge (nix-gyy.7)

                services.hermes-agent = {
                  enable = true;
                  # Add the hermes binary to environment.systemPackages and
                  # export HERMES_HOME via environment.variables (upstream
                  # nixosModules.nix:548-556). Guarantees interactive shell
                  # `hermes` invocations share .env, config.yaml, workspace,
                  # sessions, and plugins with the running gateway/dashboard
                  # by using a byte-identical store-path. Wimpysworld follows
                  # the same pattern (hermes/default.nix:693).
                  addToSystemPackages = true;
                  createUser = false;
                  user = settings.serviceUser;
                  group = "users";
                  stateDir = userHome;

                  # Deep-merge into config.yaml — populated incrementally by later issues.
                  # Populates config.yaml channels.matrix.* for policy/allowlist code paths.
                  # The hermes-agent matrix adapter reads bootstrap vars (HOMESERVER, USER_ID,
                  # ALLOWED_USERS) only from environment — see services.hermes-agent.environment
                  # below. Keep both populated so policy and bootstrap stay consistent.
                  settings = lib.mkMerge [
                    {
                      # Operationally-critical defaults for headless matrix-bot posture.
                      # See docs/notes/agents/ for rationale per key (TODO: extend deployment note).
                      approvals.mode = "smart"; # default "manual" would deadlock; no TTY for prompts
                      display.skin = "mono"; # CLI parity with dashboard.theme = "mono"
                      sessions = {
                        auto_prune = true; # upstream default false; long-lived gateway accumulates state.db
                        retention_days = 90; # upstream's documented suggested value
                      };
                      lsp.install_strategy = "manual"; # upstream default "auto" leaks into sealed nix venv
                      security.allow_lazy_installs = false; # sealed nix venv — lazy installs fail; disable cleanly
                      stt.enabled = false; # no whisper model bundled on cinnabar
                      kanban.dispatch_in_gateway = false; # kanban dispatcher ticks every 60s; unused on cinnabar

                      # Local SQLite-backed holographic memory provider (memory.provider).
                      # memory_enabled and user_profile_enabled already default true upstream
                      # (hermes_cli/config.py:1128-1129); explicit setting would be redundant.
                      # plugins.hermes-memory-store sub-keys at defaults; override here if needed
                      # (db_path defaults to ${HERMES_HOME}/memory_store.db).
                      memory.provider = "holographic";
                      plugins.hermes-memory-store = {
                        auto_extract = false; # upstream default; opt-in fact extraction at session end
                        default_trust = 0.5; # upstream default
                      };

                      channels.matrix = {
                        homeserver = "https://${settings.matrixServerName}";
                        user_id = "@${settings.matrixUserName}:${settings.matrixServerName}";
                        # Additional matrix wiring added by nix-gyy.7.
                      };
                    }
                    (lib.mkIf (settings.channelsAllowlist != [ ]) {
                      # Mirrors openclaw's channels.matrix.dm.allowFrom pattern.
                      # Upstream migration doc (migrate-from-openclaw.md:138-146) confirms
                      # `channels.<platform>.allowFrom` is the convergent allowlist path.
                      channels.matrix.allowFrom = settings.channelsAllowlist;
                    })
                    settings.configOverrides
                  ];

                  # environmentFiles wired by the clan-vars adapter (nix-gyy.3).
                  # Order: openrouter first, then matrix password. mkForce overrides
                  # the scaffold's prior mkDefault sentinel value.
                  environmentFiles = lib.mkForce [
                    openrouterEnvPath
                    matrixPasswordEnvPath
                  ];

                  # Include the upstream `matrix` optional dependency group in the
                  # sealed venv so the mautrix adapter can import mautrix-python.
                  # Per upstream pyproject.toml:87 the `matrix` group declares
                  # `mautrix[encryption]==0.21.0` (plus Markdown, aiosqlite,
                  # asyncpg, aiohttp-socks). Upstream's nixosModule exposes
                  # extraDependencyGroups as the documented lever to add an
                  # optional group to the immutable venv (nix-setup.md:659).
                  # The journal's "Run: pip install mautrix[encryption]" hint is
                  # unusable here — the Nix venv is sealed at build time.
                  extraDependencyGroups = [ "matrix" ];

                  # Matrix bootstrap vars: the hermes-agent matrix adapter reads
                  # MATRIX_HOMESERVER, MATRIX_USER_ID, and MATRIX_ALLOWED_USERS
                  # exclusively from process environment via os.getenv() (upstream
                  # gateway/config.py:1391-1414, gateway/platforms/matrix.py:234).
                  # Upstream's activation script cat-appends cfg.environment entries
                  # alongside environmentFiles into ${stateDir}/.hermes/.env, the
                  # file load_hermes_dotenv() reads at python startup.
                  environment = {
                    MATRIX_HOMESERVER = settings.matrixHomeserverUrl;
                    MATRIX_USER_ID = "@${settings.matrixUserName}:${settings.matrixServerName}";
                    MATRIX_ALLOWED_USERS = lib.concatStringsSep "," settings.channelsAllowlist;
                  };
                };

                # ─── clan-vars generators (nix-gyy.4) ───────────────────────
                # Each generator writes `KEY=value\n` env-file format to its
                # output file. This is the contract enforced by the adapter
                # (nix-gyy.3): upstream's activation script concatenates each
                # environmentFiles entry into ${stateDir}/.hermes/.env verbatim,
                # so raw secret material would corrupt the .env file.
                #
                # Generators (catalog emitted to nix-gyy.4 surfacing #4):
                #   - hermes-openrouter-api-key (interactive, requires human generate)
                #   - matrix-password-hermes    (auto via xkcdpass)
                clan.core.vars.generators.${settings.openrouterApiKeyGenerator} = {
                  files."OPENROUTER_API_KEY" = {
                    neededFor = "services";
                    owner = settings.serviceUser;
                    mode = "0440";
                  };
                  prompts.api-key = {
                    description = "OpenRouter API key for hermes-agent (https://openrouter.ai/keys)";
                    type = "hidden";
                  };
                  runtimeInputs = [ pkgs.coreutils ];
                  script = ''
                    printf 'OPENROUTER_API_KEY=%s\n' "$(cat "$prompts/api-key")" > "$out/OPENROUTER_API_KEY"
                  '';
                };

                clan.core.vars.generators.${settings.matrixBotPasswordGenerator} = {
                  files."MATRIX_PASSWORD" = {
                    neededFor = "services";
                    owner = settings.serviceUser;
                    mode = "0440";
                  };
                  runtimeInputs = [
                    pkgs.coreutils
                    pkgs.xkcdpass
                  ];
                  script = ''
                    printf 'MATRIX_PASSWORD=%s\n' "$(xkcdpass -n 4 -d -)" > "$out/MATRIX_PASSWORD"
                  '';
                };

                # ─── Systemd hardening tuning for login-user posture (nix-gyy.5) ───
                # Upstream hermes-agent nixosModule already sets defaults compatible
                # with our login-user model (see nixosModules.nix:901-910):
                #   - ProtectHome     = false      (permissive; REQUIRED for /home/cameron access — no override needed)
                #   - ProtectSystem   = "strict"   (compatible; ReadWritePaths auto-extended to stateDir + workingDirectory)
                #   - NoNewPrivileges = true       (acceptable)
                #   - PrivateTmp      = true       (acceptable)
                #   - UMask           = "0007"     (acceptable; shared-state group-writable)
                #   - ReadWritePaths  = [ stateDir workingDirectory ]
                # Upstream does NOT set RestrictNamespaces (Claude CLI may use namespaces; no override).
                # Upstream does NOT set kernel-hardening directives — we add them defensively below.
                #
                # Net effect: NO mkForce override for ProtectHome / ProtectSystem /
                # RestrictNamespaces is required. Upstream defaults already align
                # with the posture. The briefing's mkForce trio (ProtectHome/
                # ProtectSystem/RestrictNamespaces) was approximate; recon shows
                # the actual override set is narrower (kernel-hardening only).
                #
                # PrivateDevices intentionally NOT set — Claude CLI may use /dev/null
                # and /dev/urandom for entropy/IO; matching openclaw's posture which
                # also omits PrivateDevices for the same reason.
                systemd.services.hermes-agent.serviceConfig = {
                  # Defensive kernel hardening (rationale per directive):
                  ProtectKernelTunables = true; # block /proc/sys, /sys writes (hermes doesn't tune kernel)
                  ProtectKernelModules = true; # block module load/unload (hermes is not a kernel modprobe consumer)
                  ProtectKernelLogs = true; # block dmesg/kmsg access (hermes doesn't read kernel ring buffer)
                  ProtectControlGroups = true; # cgroupfs read-only (hermes doesn't reconfigure cgroups)
                  RestrictSUIDSGID = true; # block setuid/setgid file creation (hermes only writes regular files)
                  RestrictRealtime = true; # block SCHED_FIFO/RR (hermes is not RT-scheduled)
                  SystemCallArchitectures = "native"; # block non-native syscall ABIs (defensive sandbox)
                };

                # ─── Sibling hermes-agent-dashboard systemd unit (nix-gyy.6) ───
                # Upstream nixosModule does NOT expose the dashboard (confirmed by
                # recon: nixosModules.nix only defines systemd.services.hermes-agent
                # running `hermes gateway`). Author a sibling unit mirroring
                # wimpysworld-nix-config/nixos/_mixins/server/hermes/default.nix:882-920,
                # adapted to our login-user posture and dashboardPort setting.
                #
                # Binds 127.0.0.1 (NOT [::1]) — nginx reverse-proxy on hermes.zt
                # (wired in nix-gyy.8) will target this loopback address.
                systemd.services.hermes-agent-dashboard = {
                  description = "Hermes Agent web dashboard";
                  wantedBy = [ "multi-user.target" ];
                  wants = [ "network-online.target" ];
                  after = [
                    "network-online.target"
                    "hermes-agent.service"
                  ];

                  environment = {
                    HERMES_HOME = "${userHome}/.hermes";
                    HERMES_MANAGED = "true";
                    HOME = userHome;
                  };

                  serviceConfig = {
                    Type = "exec";
                    User = settings.serviceUser;
                    Group = "users";
                    WorkingDirectory = "${userHome}/workspace";
                    ExecStart = "${config.services.hermes-agent.package}/bin/hermes dashboard --host 127.0.0.1 --port ${toString settings.dashboardPort} --no-open";
                    Restart = "always";
                    RestartSec = 5;
                    UMask = "0007";

                    # Hardening parallel to main service's tuned posture (login-user-aware).
                    NoNewPrivileges = true;
                    ProtectSystem = "strict";
                    ProtectHome = false;
                    PrivateTmp = true;
                    ReadWritePaths = [
                      userHome
                      "${userHome}/workspace"
                    ];
                    ProtectKernelTunables = true;
                    ProtectKernelModules = true;
                    ProtectKernelLogs = true;
                    ProtectControlGroups = true;
                    RestrictSUIDSGID = true;
                    RestrictRealtime = true;
                    SystemCallArchitectures = "native";
                  };
                };
              };
          };
      };
    };
}
