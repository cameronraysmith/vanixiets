{ ... }:
{
  flake.modules.nixos.omnigraph =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.omnigraph;

      yaml = pkgs.formats.yaml { };

      bindTarget =
        if lib.hasInfix ":" cfg.bindAddress then
          "[${cfg.bindAddress}]:${toString cfg.port}"
        else
          "${cfg.bindAddress}:${toString cfg.port}";

      storageEnvironment =
        lib.optionalAttrs (cfg.s3.region != null) { AWS_REGION = cfg.s3.region; }
        // lib.optionalAttrs (cfg.s3.endpointUrl != null) {
          AWS_ENDPOINT_URL = cfg.s3.endpointUrl;
          AWS_ENDPOINT_URL_S3 = cfg.s3.endpointUrl;
        };

      environmentFiles = lib.optional (cfg.environmentFile != null) cfg.environmentFile;

      clusterConfigDir =
        pkgs.runCommand "omnigraph-cluster-config"
          {
            nativeBuildInputs = [ cfg.package ];
            clusterYaml = yaml.generate "cluster.yaml" cfg.cluster.settings;
          }
          ''
            export HOME="$NIX_BUILD_TOP"
            mkdir -p "$out"
            cp "$clusterYaml" "$out/cluster.yaml"
            ${lib.concatLines (
              lib.mapAttrsToList (name: source: ''
                mkdir -p "$(dirname "$out/${name}")"
                cp -rL ${source} "$out/${name}"
              '') cfg.cluster.extraFiles
            )}
            chmod -R u+rwX "$out"
            omnigraph cluster validate --config "$out"
          '';

      applyScript = pkgs.writeShellApplication {
        name = "omnigraph-cluster-apply";
        runtimeInputs = [
          cfg.package
          pkgs.jq
        ];
        text = ''
          if ! importOutput=$(omnigraph cluster import --config ${clusterConfigDir} --json); then
            printf '%s\n' "$importOutput"
            jq -e '.diagnostics[]? | select(.code == "state_already_exists")' \
              <<<"$importOutput" >/dev/null
          fi
          applyStatus=0
          applyOutput=$(omnigraph --as ${lib.escapeShellArg cfg.cluster.actor} \
            cluster apply --config ${clusterConfigDir} --json) || applyStatus=$?
          printf '%s\n' "$applyOutput"

          # `ok` is `!has_errors`, so the warnings that leave changes unapplied
          # — approval_required, apply_dependency_blocked,
          # dependency_not_applied, cluster_recovery_pending — all exit 0. Each
          # rides a Blocked disposition and leaves a residual, which `converged`
          # catches. cluster_recovery_pending also fires standalone out of the
          # recovery sweep, which only marks the graph Drifted and leaves the
          # ledger digests `converged` compares untouched — yet the server
          # quarantines that graph — so that code needs its own check.
          if [ "$applyStatus" -ne 0 ] \
            || ! jq -e '.ok and .converged and ([.diagnostics[]?
                        | select(.code == "cluster_recovery_pending")] | length == 0)' \
              <<<"$applyOutput" >/dev/null; then
            printf 'omnigraph cluster apply did not converge (exit %s)\n' \
              "$applyStatus" >&2
            jq -r '.diagnostics[]? | "\(.severity) \(.code) \(.path): \(.message)"' \
              <<<"$applyOutput" >&2 || true
            jq -r '.changes[]? | select(.disposition != "applied" and .disposition != "derived")
                   | "\(.disposition // "unplanned") \(.resource): \(.reason // "")"' \
              <<<"$applyOutput" >&2 || true
            exit 1
          fi
        '';
      };

      clusterEtcName = "omnigraph/cluster";
      clusterEtcPath = "/etc/${clusterEtcName}";

      clusterCli = pkgs.writeShellApplication {
        name = "omnigraph-cluster";
        runtimeInputs = [
          cfg.package
          pkgs.coreutils
        ];
        text = ''
          ${lib.concatLines (
            lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") storageEnvironment
          )}
          ${lib.optionalString (cfg.environmentFile != null) ''
            if [ ! -r ${lib.escapeShellArg (toString cfg.environmentFile)} ]; then
              printf 'omnigraph-cluster: cannot read %s, which holds the storage credentials. Re-run as root: sudo omnigraph-cluster %s\n' \
                ${lib.escapeShellArg (toString cfg.environmentFile)} "$*" >&2
              exit 1
            fi
            # Read as data, the way systemd reads the same file for the units.
            # Sourcing it would evaluate `$`, backticks and quotes in a
            # credential as shell, as root.
            while IFS='=' read -r credentialKey credentialValue || [ -n "$credentialKey" ]; do
              case "$credentialKey" in
                "" | "#"*) continue ;;
              esac
              export "$credentialKey=$credentialValue"
            done < ${lib.escapeShellArg (toString cfg.environmentFile)}
          ''}
          # Matches OMNIGRAPH_HOME on the units, which keeps operator
          # configuration under /root out of a recovery run.
          OMNIGRAPH_HOME=$(mktemp -d)
          export OMNIGRAPH_HOME
          trap 'rm -rf -- "$OMNIGRAPH_HOME"' EXIT
          cd ${lib.escapeShellArg clusterEtcPath}
          # Only apply and approve are actor-bound; the read-only verbs
          # (validate, plan, observe, status, refresh, import, force-unlock)
          # reject --as outright rather than ignoring it.
          actorArgs=()
          case "''${1-}" in
            apply | approve)
              actorArgs=(--as ${lib.escapeShellArg cfg.cluster.actor})
              ;;
          esac
          omnigraph "''${actorArgs[@]}" cluster "$@"
        '';
      };

      readinessProbe = pkgs.writeShellApplication {
        name = "omnigraph-server-wait-ready";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.curl
        ];
        text = ''
          url="http://${bindTarget}/healthz"
          deadline=$(( $(date +%s) + ${toString cfg.readinessTimeout} ))
          until curl --fail --silent --max-time 5 --output /dev/null "$url"; do
            if [ "$(date +%s)" -ge "$deadline" ]; then
              printf 'omnigraph-server did not answer %s within %s seconds\n' \
                "$url" '${toString cfg.readinessTimeout}' >&2
              curl --fail --silent --show-error --max-time 5 --output /dev/null "$url" || true
              exit 1
            fi
            sleep 2
          done
        '';
      };

      serverRestartSec = 60;
      serverStartLimitBurst = 5;
      serverTimeoutStartSec = cfg.readinessTimeout + 300;
      serverTimeoutStopSec = 120;

      # Wall time of one failed start at its worst: the start job burns its
      # whole budget, the stop job burns its whole budget killing it, then
      # RestartSec elapses before the next attempt.
      serverStartCycleSec = serverTimeoutStartSec + serverTimeoutStopSec + serverRestartSec;

      hardening = {
        CapabilityBoundingSet = [ "" ];
        DeviceAllow = "";
        DevicePolicy = "closed";
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@resources"
          "~@privileged"
        ];
        UMask = "0077";
      };
    in
    {
      options.services.omnigraph = {
        enable = lib.mkEnableOption "omnigraph, a lakehouse graph database server";

        package = lib.mkPackageOption pkgs "omnigraph" { };

        storageUri = lib.mkOption {
          type = lib.types.str;
          example = "s3://bucket/prefix/clusters/dev-graph";
          description = ''
            Cluster storage root URI, and the sole boot source of
            `omnigraph-server`. Everything the cluster stores lives beneath it:
            the state ledger and lock under `__cluster/`, the content-addressed
            resource catalog, approval artifacts, and the derived graph roots at
            `<storageUri>/graphs/<id>.omni`.

            A directory path serves a filesystem-backed cluster; an `s3://` URI
            serves from object storage, with credentials supplied exclusively
            through the `AWS_*` process environment — see
            {option}`services.omnigraph.environmentFile`.

            Exactly one `omnigraph-server` may serve a given storage root.
            Omnigraph is a single-writer store, and a second writer over the
            same prefix corrupts the graph.

            The server reads the applied cluster revision once, at startup.
            Applying a new revision therefore requires a server restart before
            it serves.
          '';
        };

        bindAddress = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = ''
            Address the HTTP API listens on. An IPv6 literal is bracketed
            automatically when the `--bind` argument is assembled.
          '';
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8080;
          description = "Port the HTTP API listens on.";
        };

        requireAllGraphs = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Refuse to serve unless the cluster boots entirely clean.

            Broader than the quarantine framing upstream's server documentation
            gives it: the server bails whenever the boot snapshot carries any
            diagnostic at all, of any severity and about any resource, before it
            has opened a single dataset. A warning that leaves every graph
            healthy is fatal too. Skipped graphs and graphs that fail to open
            are then also fatal, at the later stages that detect them.

            By default those same diagnostics are logged as warnings and the
            healthy graphs still serve.

            None of them clear by retrying — they clear through a cluster
            `refresh` or `apply` — so enabling this also caps `omnigraph-server`
            at five start attempts, after which it stays `failed` until
            `systemctl reset-failed`. Left off, the unit is left to restart
            indefinitely, because the failures it can then still fail on are
            transient ones that do clear.
          '';
        };

        readinessTimeout = lib.mkOption {
          type = lib.types.ints.positive;
          default = 600;
          description = ''
            Seconds the readiness probe waits for `/healthz` to answer before
            failing the `omnigraph-server` start job.

            `omnigraph-server` opens every dataset in the cluster from storage
            before it binds its listener, and it implements no `sd_notify`
            handshake, so systemd would otherwise report the unit active for
            the whole of that window while the port still refuses connections.
            An `ExecStartPost` probe closes the gap, which makes this bound the
            unit's effective startup budget: `TimeoutStartSec` is derived from
            it with five minutes of headroom, so that an unready server fails
            through the probe's own diagnostic rather than through systemd's
            generic timeout.

            Scale it with the cluster. Startup cost grows with the number of
            datasets and with the latency of the store they are read from.
          '';
        };

        bearerTokensFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Path to a JSON file mapping actor names to bearer tokens, for
            example `{"admin": "…"}`. Passed to the server through systemd
            credentials, so the file is read by the service manager before
            privilege drop and need not be readable by the service user.

            The server refuses to start without at least one bearer token, so
            this is required.
          '';
        };

        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Path to a systemd `EnvironmentFile` holding the S3 credentials for
            an `s3://` storage root, as `AWS_ACCESS_KEY_ID=…` and
            `AWS_SECRET_ACCESS_KEY=…` lines.

            Process environment variables are the only credential source
            omnigraph resolves. It builds its object store with
            `object_store`'s `from_env`, which has no shared-credentials-file
            provider: `AWS_PROFILE` and `AWS_SHARED_CREDENTIALS_FILE` are
            silently discarded and the process then falls through to the
            instance metadata service.
          '';
        };

        s3 = {
          endpointUrl = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "https://accountid.r2.cloudflarestorage.com";
            description = ''
              Endpoint of an S3-compatible object store. Exported as both
              `AWS_ENDPOINT_URL_S3` and `AWS_ENDPOINT_URL`: omnigraph's own
              storage adapter prefers the former, while the datasets underneath
              resolve their store through `object_store`'s environment key
              table, and which variable that table honours is version-dependent.

              Leave unset to address AWS S3 itself.
            '';
          };

          region = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "auto";
            description = ''
              Value of `AWS_REGION`. Unset, `object_store` defaults to
              `us-east-1`, which most S3-compatible stores reject.
            '';
          };
        };

        cluster = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Whether to render the cluster configuration directory from
              {option}`services.omnigraph.cluster.settings` and provide the
              `omnigraph-cluster-apply` unit that converges the storage root to
              it.

              Also exposes that directory at `${clusterEtcPath}` and installs
              the `omnigraph` CLI along with an `omnigraph-cluster` wrapper, so
              that the recovery commands (`status`, `refresh`, `force-unlock
              <LOCK_ID>`) are runnable ad hoc. Every `omnigraph cluster`
              subcommand is addressed by configuration directory alone — there
              is no storage-URI form — and the rendered directory is an
              anonymous store path. The wrapper runs from `${clusterEtcPath}`,
              passes {option}`services.omnigraph.cluster.actor` as `--as` on
              the actor-bound subcommands alone (`apply`, `approve`), since
              the read-only verbs reject that flag, and reads
              {option}`services.omnigraph.environmentFile` for the storage
              credentials, which omnigraph accepts only from the process
              environment. That file is readable by root alone, so the wrapper
              must run as root; it refuses with that instruction rather than
              falling through to the instance metadata service and hanging.

              Disable to serve a cluster whose configuration is applied from
              elsewhere; {option}`services.omnigraph.storageUri` alone is then
              enough to serve.
            '';
          };

          settings = lib.mkOption {
            type = lib.types.submodule {
              freeformType = yaml.type;

              options = {
                version = lib.mkOption {
                  type = lib.types.ints.unsigned;
                  default = 1;
                  description = "Cluster configuration schema version.";
                };

                storage = lib.mkOption {
                  type = lib.types.str;
                  description = ''
                    Storage root the cluster converges. Defaults to
                    {option}`services.omnigraph.storageUri`, and an assertion
                    holds the two equal so that the applied revision and the
                    served revision cannot diverge.
                  '';
                };
              };
            };
            default = { };
            example = lib.literalExpression ''
              {
                metadata.name = "dev-graph";
                graphs.dev = {
                  schema = "schema.pg";
                  queries = "queries/";
                };
              }
            '';
            description = ''
              Contents of `cluster.yaml`, rendered into a store directory that
              `omnigraph cluster apply` reads. See
              <https://github.com/ModernRelay/omnigraph/blob/main/docs/user/clusters/config.md>.

              Paths under `graphs.<id>.schema`, `graphs.<id>.queries`, and
              `policies.<name>.file` resolve relative to that directory; supply
              their contents through
              {option}`services.omnigraph.cluster.extraFiles`.

              The file carries no credentials and is world-readable in the Nix
              store. Omnigraph rejects an inline `api_key` under
              `providers.embedding.<name>`; use `''${VAR}` interpolation
              resolved from the server's environment instead.
            '';
          };

          extraFiles = lib.mkOption {
            type = lib.types.attrsOf lib.types.path;
            default = { };
            example = lib.literalExpression ''
              {
                "schema.pg" = ./schema.pg;
                "queries" = ./queries;
              }
            '';
            description = ''
              Files and directories copied into the rendered cluster
              configuration directory under the given relative names, alongside
              the generated `cluster.yaml`.
            '';
          };

          actor = lib.mkOption {
            type = lib.types.str;
            default = "system";
            description = ''
              Actor recorded against every change `omnigraph cluster apply`
              executes, and against the approval artifacts it consumes.
            '';
          };

          apply.auto = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether to run `omnigraph cluster apply` automatically: at boot,
              and again whenever the rendered configuration directory changes.

              Left off, converging is an operator action
              (`systemctl restart omnigraph-cluster-apply.service`, then restart
              `omnigraph-server`). The verb is `restart`, not `start`: the unit
              sets `RemainAfterExit`, without which a changed configuration
              directory could never re-trigger it, so once it has run it stays
              `active (exited)` and `start` returns 0 without converging
              anything.

              Off is the safer default because apply creates a missing graph
              without ceremony: were the storage root lost out of band, an
              automatic apply would recreate it empty and report an ordinary
              create.
            '';
          };
        };

        optimize = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = ''
              Whether to run `omnigraph optimize` on a timer. Omnigraph commits
              with Lance's automatic cleanup disabled, so fragment and index
              maintenance is entirely operator-driven and storage otherwise
              grows monotonically.

              The command is non-destructive: it compacts fragments, restores
              index coverage, and builds declared-but-missing indexes, but never
              collects old versions. Reclaiming versions needs `omnigraph
              cleanup`, which is destructive and is deliberately not automated
              here.
            '';
          };

          graphs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = lib.attrNames (cfg.cluster.settings.graphs or { });
            defaultText = lib.literalExpression ''
              lib.attrNames config.services.omnigraph.cluster.settings.graphs
            '';
            description = "Graph ids to optimize.";
          };

          interval = lib.mkOption {
            type = lib.types.str;
            default = "weekly";
            description = "`OnCalendar` expression driving the optimize timer.";
          };
        };

        extraEnvironment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          example = {
            RUST_LOG = "info";
          };
          description = "Extra environment variables for every omnigraph unit.";
        };

        extraFlags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra command-line arguments for `omnigraph-server`.";
        };

        user = lib.mkOption {
          type = lib.types.str;
          default = "omnigraph";
          description = "User the omnigraph units run as.";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = "omnigraph";
          description = "Group the omnigraph units run as.";
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.bearerTokensFile != null;
            message = ''
              services.omnigraph.bearerTokensFile is not set. omnigraph-server
              refuses to start with neither bearer tokens nor a policy bundle,
              rather than serve an open API.
            '';
          }
          {
            assertion = !(lib.hasPrefix "s3://" cfg.storageUri) || cfg.environmentFile != null;
            message = ''
              services.omnigraph.storageUri is an s3:// URI but
              services.omnigraph.environmentFile is not set. S3 credentials
              reach omnigraph only as process environment variables; without
              them the process falls through to the instance metadata service
              and hangs rather than failing.
            '';
          }
          {
            assertion = !cfg.cluster.enable || cfg.cluster.settings.storage == cfg.storageUri;
            message = ''
              services.omnigraph.cluster.settings.storage
              (${cfg.cluster.settings.storage}) differs from
              services.omnigraph.storageUri (${cfg.storageUri}). The applied
              revision would then live somewhere the server never reads.
            '';
          }
        ];

        environment.systemPackages = lib.optionals cfg.cluster.enable [
          cfg.package
          clusterCli
        ];

        environment.etc = lib.mkIf cfg.cluster.enable {
          ${clusterEtcName}.source = clusterConfigDir;
        };

        services.omnigraph.cluster.settings = {
          storage = lib.mkDefault cfg.storageUri;
          metadata = lib.mkDefault { };
          state = lib.mkDefault {
            backend = "cluster";
            lock = true;
          };
        };

        systemd.services.omnigraph-server = {
          description = "omnigraph graph database server";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          restartTriggers = lib.optional (cfg.cluster.enable && cfg.cluster.apply.auto) clusterConfigDir;

          environment = {
            OMNIGRAPH_SERVER_BEARER_TOKENS_FILE = "%d/bearer-tokens";
          }
          // storageEnvironment
          // cfg.extraEnvironment;

          serviceConfig = hardening // {
            ExecStart = lib.escapeShellArgs (
              [
                (lib.getExe' cfg.package "omnigraph-server")
                "--cluster"
                cfg.storageUri
                "--bind"
                bindTarget
              ]
              ++ lib.optional cfg.requireAllGraphs "--require-all-graphs"
              ++ cfg.extraFlags
            );
            ExecStartPost = lib.getExe readinessProbe;
            EnvironmentFile = environmentFiles;
            LoadCredential = lib.optional (
              cfg.bearerTokensFile != null
            ) "bearer-tokens:${cfg.bearerTokensFile}";
            StateDirectory = "omnigraph";
            DynamicUser = true;
            User = cfg.user;
            Group = cfg.group;
            Restart = "on-failure";
            RestartSec = serverRestartSec;
            # Load-bearing: the readiness probe runs inside the start job, and
            # opening the datasets outruns systemd's 90s default, which would
            # kill a healthy server into a Restart=on-failure loop.
            TimeoutStartSec = serverTimeoutStartSec;
            TimeoutStopSec = serverTimeoutStopSec;
          };

          # systemd's start rate limiter is a tumbling window opened by the
          # first attempt in it, so the attempt that trips the limit is the
          # (burst + 1)th, arriving one whole burst of cycles in. Anything
          # shorter — including systemd's 10s default, which is shorter than a
          # single cycle here — reopens the window first and retries forever.
          # Sizing the window at (burst + 1) cycles leaves a full cycle of
          # margin even when every attempt burns its entire budget.
          unitConfig =
            if cfg.requireAllGraphs then
              {
                StartLimitIntervalSec = (serverStartLimitBurst + 1) * serverStartCycleSec;
                StartLimitBurst = serverStartLimitBurst;
              }
            else
              { StartLimitIntervalSec = 0; };
        };

        systemd.services.omnigraph-cluster-apply = lib.mkIf cfg.cluster.enable {
          description = "Converge the omnigraph cluster to its declared configuration";
          before = [ "omnigraph-server.service" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = lib.optional cfg.cluster.apply.auto "multi-user.target";
          restartTriggers = lib.optional cfg.cluster.apply.auto clusterConfigDir;

          environment = {
            OMNIGRAPH_HOME = "%T/omnigraph";
          }
          // storageEnvironment
          // cfg.extraEnvironment;

          serviceConfig = hardening // {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe applyScript;
            EnvironmentFile = environmentFiles;
            StateDirectory = "omnigraph";
            DynamicUser = true;
            User = cfg.user;
            Group = cfg.group;
          };
        };

        systemd.services.omnigraph-optimize = lib.mkIf (cfg.optimize.enable && cfg.optimize.graphs != [ ]) {
          description = "Compact and reindex omnigraph graph storage";

          environment = {
            OMNIGRAPH_HOME = "%T/omnigraph";
          }
          // storageEnvironment
          // cfg.extraEnvironment;

          serviceConfig = hardening // {
            Type = "oneshot";
            ExecStart = map (
              graph:
              lib.escapeShellArgs [
                (lib.getExe cfg.package)
                "--cluster"
                cfg.storageUri
                "--graph"
                graph
                "optimize"
                "--json"
              ]
            ) cfg.optimize.graphs;
            EnvironmentFile = environmentFiles;
            StateDirectory = "omnigraph";
            DynamicUser = true;
            User = cfg.user;
            Group = cfg.group;
          };
        };

        systemd.timers.omnigraph-optimize = lib.mkIf (cfg.optimize.enable && cfg.optimize.graphs != [ ]) {
          description = "Periodic omnigraph storage maintenance";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = cfg.optimize.interval;
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
        };
      };
    };
}
