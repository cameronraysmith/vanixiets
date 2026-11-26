# services.omnigraph: omnigraph-server over one cluster storage root, with the
# create-once bootstrap, the operator-run apply unit and optional seed units.
#
# Recreating an example-data root (a cluster graph keeps the storage format
# it was created with, and `omnigraph upgrade` refuses cluster graphs):
#   1. point services.omnigraph.storageUri at a new root and set
#      services.omnigraph.cluster.createdAtFormat to the format the packaged
#      omnigraph writes (`omnigraph version --json`, internal_schema.writes).
#      A root in the `sciexp` bucket is named by
#      flake.lib.omnigraphClusterRoots.name from that format, `<family>-f<N>`
#      (modules/lib/omnigraph-cluster-roots.nix); a deliberate fresh copy at
#      the same format, to replay the seeds, takes `-r2`, `-r3`, and so on;
#   2. deploy: the bootstrap initializes the new root and marks each seeded
#      graph's seed pending, and omnigraph-seed-<graph> loads it once the
#      server serves;
#   3. the old root and its markers stay in place, untouched, as the way
#      back: list it in flake.lib.omnigraphClusterRoots.rollback;
#   4. once nothing will roll back to it, move it to
#      flake.lib.omnigraphClusterRoots.retired in a later change, and apply
#      the terraform configuration, whose lifecycle rules then delete its
#      data and its markers from the bucket.
{ config, lib, ... }:
let
  flakeLib = config.flake.lib;

  # The server's listen address as `host:port`, an IPv6 host in brackets.
  bindTargetOf =
    bindAddress: port:
    if lib.hasInfix ":" bindAddress then
      "[${bindAddress}]:${toString port}"
    else
      "${bindAddress}:${toString port}";

  # A storage URI's scheme, lowercased, or null for a plain path.
  storageSchemeOf =
    uri:
    let
      m = builtins.match "([A-Za-z][A-Za-z0-9+.-]*)://.*" uri;
    in
    if m == null then null else lib.toLower (builtins.head m);

  # The directory of a local storage root, a plain path or a file:// URI,
  # or null for a root in an object store.
  localRootOf =
    uri:
    let
      scheme = storageSchemeOf uri;
    in
    if scheme == null || scheme == "file" then
      lib.removeSuffix "/" (lib.removePrefix "file://" uri)
    else
      null;
in
{
  flake.lib.omnigraphServer = {
    inherit bindTargetOf localRootOf;
  };

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

      bindTarget = bindTargetOf cfg.bindAddress cfg.port;

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
          pkgs.coreutils
          pkgs.gnused
          pkgs.jq
        ];
        text = ''
          storage=${lib.escapeShellArg cfg.storageUri}
          applyErr=$(mktemp)
          trap 'rm -f -- "$applyErr"' EXIT

          # A fresh root needs no import: a direct apply creates the ledger and
          # the declared graphs. It exits nonzero unless the deployment
          # completed and converged.
          applyStatus=0
          applyOutput=$(omnigraph --as ${lib.escapeShellArg cfg.cluster.actor} --target "$storage" \
            cluster apply --config ${clusterConfigDir} --json 2>"$applyErr") || applyStatus=$?
          cat "$applyErr" >&2
          printf '%s\n' "$applyOutput"
          if [ "$applyStatus" -ne 0 ] \
            || ! jq -e '.status == "complete" and .result.converged' <<<"$applyOutput" >/dev/null; then
            printf 'omnigraph cluster apply did not converge (exit %s)\n' "$applyStatus" >&2
            jq -r '.diagnostics[]? | "\(.severity) \(.code) \(.path): \(.message)"' \
              <<<"$applyOutput" >&2 || true
            exit 1
          fi

          # A converged apply on a local or S3 root releases its admission
          # lock itself, and a release it cannot confirm fails the apply
          # above. A lock still held here was either retained by this apply,
          # as omnigraph 0.16 does on an Azure root, or belongs to another
          # holder; the server refuses to boot past either. This process has
          # exited, so its storage I/O has settled and the lock it reported
          # (`Admission lock: <LOCK_ID>` on stderr) may be released; any other
          # holder (a server's leased lock, an earlier writer) is left alone
          # for an operator to investigate.
          appliedLock=$(sed -n 's/^Admission lock: \([^;]*\).*/\1/p' "$applyErr")
          if ! statusOutput=$(omnigraph --target "$storage" cluster status --json); then
            printf '%s\n' "$statusOutput" >&2
            printf 'omnigraph cluster status failed after apply; the admission lock %s was not released\n' \
              "''${appliedLock:-(unreported)}" >&2
            exit 1
          fi
          heldLock=$(jq -r '.lock_id // empty' <<<"$statusOutput")
          if [ -z "$heldLock" ]; then
            exit 0
          fi
          if [ -z "$appliedLock" ] || [ "$heldLock" != "$appliedLock" ]; then
            printf '%s\n' "$statusOutput" >&2
            printf 'the cluster admission lock %s is not the one this apply reported (%s); not releasing it\n' \
              "$heldLock" "''${appliedLock:-none}" >&2
            exit 1
          fi
          omnigraph --target "$storage" cluster force-unlock "$heldLock" --json
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
          ${lib.optionalString storageIsLocal ''
            # A local root's files belong to the units' static user, so
            # every write runs as that user, never as the invoking root.
            chown ${lib.escapeShellArg "${cfg.user}:${cfg.group}"} "$OMNIGRAPH_HOME"
          ''}
          cd ${lib.escapeShellArg clusterEtcPath}
          # Every verb but validate addresses the storage root through
          # --target. Only plan, apply and upgrade-ledger take --as; the
          # others reject it rather than ignoring it.
          targetArgs=(--target ${lib.escapeShellArg cfg.storageUri})
          case "''${1-}" in
            validate)
              targetArgs=()
              ;;
            plan | apply | upgrade-ledger)
              targetArgs+=(--as ${lib.escapeShellArg cfg.cluster.actor})
              ;;
          esac
          ${
            if storageIsLocal then
              "${pkgs.util-linux}/bin/runuser -u ${lib.escapeShellArg cfg.user} -- omnigraph \"\${targetArgs[@]}\" cluster \"$@\""
            else
              "omnigraph \"\${targetArgs[@]}\" cluster \"$@\""
          }
        '';
      };

      # Graphs the applied cluster revision declares. A revision applied from
      # elsewhere with fewer graphs (an empty cluster included) boots and
      # passes /readyz, even under --require-all-graphs, so the probe holds the
      # registered count to this number when the server is meant to serve the
      # whole cluster.
      declaredGraphCount = builtins.length (lib.attrNames (cfg.cluster.settings.graphs or { }));

      # Fails the start job within seconds when the server process has
      # already exited (any boot failure is fatal before the listener binds,
      # and systemd otherwise waits on a running ExecStartPost for its whole
      # budget) or when it serves fewer graphs than declared (no runtime
      # registration, so that never improves without an apply and restart).
      readinessProbe = flakeLib.omnigraphReadinessProbe pkgs {
        url = "http://${bindTarget}";
        timeout = cfg.readinessTimeout;
        expectedGraphCount =
          if cfg.requireAllGraphs && cfg.cluster.enable then declaredGraphCount else null;
      };

      bootstrapEnabled = cfg.cluster.enable && cfg.cluster.bootstrap.enable;

      # The bootstrap library derives the create-once marker location from
      # the storage URI itself; this only classifies the scheme for the
      # eval-time assertions.
      storageScheme = storageSchemeOf cfg.storageUri;
      storageIsS3 = storageScheme == "s3";
      storageIsLocal = localRootOf cfg.storageUri != null;

      # Every unit runs with ProtectSystem=strict, and none
      # carries ReadWritePaths, so the only writable local storage is the
      # StateDirectory. A local root works only beneath it, which also puts
      # the marker directory `<parent>/_omnigraph-markers` inside it.
      stateDirectoryPath = "/var/lib/omnigraph";
      localStorageRoot = lib.removeSuffix "/" (lib.removePrefix "file://" cfg.storageUri);
      localRootUnderStateDirectory = lib.hasPrefix "${stateDirectoryPath}/" localStorageRoot;

      # A local root's parent: RequiresMountsFor on it requires every mount
      # on its path, a dataset mounted at the state directory included.
      localRootParent = builtins.dirOf localStorageRoot;
      mountRequirement = lib.optionalAttrs storageIsLocal { RequiresMountsFor = [ localRootParent ]; };

      # Clears the lock a killed server leaves on a local root, only when it
      # is provably stale (modules/lib/omnigraph-lock-recovery.nix). Run with
      # `+`, as root outside the sandbox: ProtectProc=invisible and
      # PrivateUsers would hide other users' processes, a direct writer run
      # as root among them.
      lockRecovery = flakeLib.omnigraphLockRecovery pkgs (
        {
          omnigraph = cfg.package;
          root = localStorageRoot;
          hostName = config.networking.hostName;
          ntfySend = lib.getExe pkgs.ntfy-send;
          tokenFile = config.services.observability-notify.tokenFile or null;
          runAs = cfg.user;
        }
        // lib.optionalAttrs cfg.cluster.enable { manualCli = "omnigraph-cluster"; }
      );

      seededGraphs = lib.filterAttrs (_: graph: graph.seed != null) cfg.cluster.graphs;

      bootstrapScript = flakeLib.omnigraphBootstrap pkgs {
        omnigraph = cfg.package;
        applyProgram = lib.getExe applyScript;
        storageUri = cfg.storageUri;
        seededGraphs = lib.attrNames seededGraphs;
      };

      seedTokenCredential = "seed-token";
      seedUnitName = graph: "omnigraph-seed-${graph}";

      # Bearer tokens of the seed actors, each kept in its own file so that
      # adding one never regenerates the tokens file and the tokens in it.
      seedTokenFiles = lib.mapAttrs' (
        _: graph: lib.nameValuePair graph.seed.actor graph.seed.tokenFile
      ) seededGraphs;
      # The extra actors' tokens are kept the same way
      # (services.omnigraph.extraBearerTokenFiles); an extra actor that is
      # also a seed actor is refused by an assertion below.
      bearerTokenFiles = seedTokenFiles // cfg.extraBearerTokenFiles;
      tokenCredentialName = actor: "bearer-token-${actor}";

      # omnigraph-server reads one tokens file, so the server's ExecStartPre
      # assembles it from the tokens file, the seed actors' tokens and the
      # extra actors' tokens into its RuntimeDirectory, readable by the
      # service user alone. An actor already in the tokens file is refused
      # rather than overwritten. Tokens stay out of every argv: jq reads them
      # from the credential files.
      assembleBearerTokens = pkgs.writeShellApplication {
        name = "omnigraph-server-bearer-tokens";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          umask 0077
          jq -ce \
            ${
              lib.concatMapStringsSep " " (
                actor:
                "--rawfile ${lib.escapeShellArg actor} \"$CREDENTIALS_DIRECTORY/\"${lib.escapeShellArg (tokenCredentialName actor)}"
              ) (lib.attrNames bearerTokenFiles)
            } \
            --argjson actors ${lib.escapeShellArg (builtins.toJSON (lib.attrNames bearerTokenFiles))} '
            if type != "object" then error("the bearer tokens file is not a JSON object")
            else reduce $actors[] as $actor (.;
              if has($actor) then error("the bearer tokens file already names the actor \($actor)")
              else . + {($actor): ($ARGS.named[$actor] | rtrimstr("\n"))} end)
            end' "$CREDENTIALS_DIRECTORY/bearer-tokens" > "$RUNTIME_DIRECTORY/bearer-tokens.json"
        '';
      };

      # The root this host serves, when it lies in the bucket prefix whose
      # retired roots the terraform configuration deletes.
      servedClusterRoot = flakeLib.omnigraphClusterRoots.rootOf cfg.storageUri;
      retiredRootConflicts = lib.optionals (servedClusterRoot != null) (
        flakeLib.omnigraphClusterRoots.conflicts { keptRoots = [ servedClusterRoot ]; }
      );

      createdAtFormat = cfg.cluster.createdAtFormat;
      servesFloor = cfg.cluster.servesFloor;

      # The seed unit each seed unit waits for: the one of the seeded graph
      # before it in id order, or none for the first.
      seedPredecessor =
        let
          ids = lib.attrNames seededGraphs;
        in
        lib.listToAttrs (
          lib.zipListsWith (id: previous: lib.nameValuePair id previous) (lib.drop 1 ids) ids
        );

      seedUnits = lib.mapAttrs' (
        id: graph:
        lib.nameValuePair (seedUnitName id) {
          description = "Load the omnigraph seed of graph ${id} once its root was created";
          # Started with the server, and restarted with it (PartOf), so a
          # server restart onto a newly created root runs the load. After the
          # server's start job, which ends only once its readiness probe sees
          # the graphs serving; Requires, so a server that fails to start
          # fails this unit too rather than letting the load meet no server.
          wantedBy = [ "omnigraph-server.service" ];
          partOf = [ "omnigraph-server.service" ];
          requires = [ "omnigraph-server.service" ];
          # The loads run one at a time, in graph id order. Every load is
          # written by the server over the same link to the store as its lease
          # heartbeat, and a store whose requests stall for seconds at a time
          # would hold all of them in flight together; one after another keeps
          # at most one commit beside the heartbeat, for a few seconds per
          # small seed. Ordering only, so a failed load leaves the next to run.
          after = [
            "omnigraph-server.service"
            "network-online.target"
          ]
          ++ lib.optional (seedPredecessor ? ${id}) "${seedUnitName seedPredecessor.${id}}.service";
          wants = [ "network-online.target" ];
          # A deploy that changes only this unit does not run it; it runs at
          # the next server start, the only time a pending seed can appear.
          restartIfChanged = false;

          environment = {
            OMNIGRAPH_HOME = "%T/omnigraph";
          }
          // storageEnvironment
          // cfg.extraEnvironment;

          unitConfig = mountRequirement;

          serviceConfig = hardening // {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe (
              flakeLib.omnigraphSeed pkgs {
                omnigraph = cfg.package;
                storageUri = cfg.storageUri;
                graph = id;
                seedFile = graph.seed.file;
                serverUrl = "http://${bindTarget}";
                tokenCredential = seedTokenCredential;
                environmentFile = cfg.environmentFile;
                environment = storageEnvironment;
              }
            );
            EnvironmentFile = environmentFiles;
            LoadCredential = [ "${seedTokenCredential}:${graph.seed.tokenFile}" ];
            StateDirectory = "omnigraph";
            User = cfg.user;
            Group = cfg.group;
          };
        }
      ) seededGraphs;

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
      # The seed units are named per graph, which a `systemd.services`
      # attribute set beside the fixed `systemd.services.<name>` definitions
      # below cannot hold, so they come from a module of their own.
      imports = [
        { config = lib.mkIf cfg.enable { systemd.services = seedUnits; }; }
      ];

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
            Refuse to serve unless every graph in the applied revision opens.

            With this set, no graph serves until all of them have opened, and a
            single graph that fails to open stops the server. By default a
            failed graph stays registered as blocked and the healthy graphs
            still serve.

            Such failures do not clear by retrying — they clear through a
            corrective `cluster apply` or a storage restore — so enabling this
            also caps `omnigraph-server` at five start attempts, after which it
            stays `failed` until `systemctl reset-failed`. Left off, the unit is
            left to restart indefinitely, because the failures it can then
            still fail on are transient ones that do clear.
          '';
        };

        readinessTimeout = lib.mkOption {
          type = lib.types.ints.positive;
          default = 600;
          description = ''
            Seconds the readiness probe waits for `/readyz` to answer before
            failing the `omnigraph-server` start job.

            `omnigraph-server` binds its listener before it opens the graphs,
            answers `/readyz` with 503 while any graph is still loading, and
            implements no `sd_notify` handshake, so systemd would otherwise
            report the unit active while no graph can be served yet. An
            `ExecStartPost` probe closes the gap, which makes this bound the
            unit's effective startup budget: `TimeoutStartSec` is derived from
            it with five minutes of headroom, so that an unready server fails
            through the probe's own diagnostic rather than through systemd's
            generic timeout.

            The probe does not spend this budget on a server that cannot come
            up. A boot failure — a missing or unapplied cluster state, a held
            admission lock, a strict
            {option}`services.omnigraph.requireAllGraphs` refusal, a cluster
            whose graphs all fail — exits the server, and the probe fails the
            start job within seconds once the main process is gone, rather than
            polling until the deadline. It also fails at once when loading has
            finished with a graph blocked, and, with
            {option}`services.omnigraph.requireAllGraphs` and
            {option}`services.omnigraph.cluster.enable` both set, when `/readyz`
            reports fewer registered graphs than `cluster.settings.graphs`
            declares: the server opens graphs only at startup, so neither
            resolves without an apply or restore and a restart.

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

            At each start the server's `ExecStartPre` adds the token of every
            seed actor ({option}`services.omnigraph.cluster.graphs.<graph>.seed`)
            and of every actor in
            {option}`services.omnigraph.extraBearerTokenFiles` to it, refusing
            an actor the file already names, and writes the result to the
            server's RuntimeDirectory, readable by the service user alone,
            which the server then reads.

            The server refuses to start without at least one bearer token, so
            this is required.
          '';
        };

        extraBearerTokenFiles = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = { };
          example = lib.literalExpression ''{ monitor = "/run/secrets/omnigraph-monitor-token"; }'';
          description = ''
            Bearer-token actors beyond {option}`services.omnigraph.bearerTokensFile`
            and the seed actors, each mapped to a file holding its token
            alone. The server's `ExecStartPre` adds each to the tokens file
            as it adds a seed actor's, refusing an actor the tokens file
            already names, so adding one never regenerates the tokens file.
            What an actor may do is set by the applied policy, not here.

            The actor `monitor`, when present, is the one
            `omnigraph-probe.service` reads per-graph state as; it receives
            the same file through systemd credentials.
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
              that the recovery commands (`status`, `force-unlock <LOCK_ID>`,
              `upgrade-ledger --writers-stopped`) are runnable ad hoc. The
              wrapper runs from `${clusterEtcPath}`, so `--config` defaults to
              the rendered directory; addresses every subcommand but `validate`
              to {option}`services.omnigraph.storageUri` with `--target`; passes
              {option}`services.omnigraph.cluster.actor` as `--as` on `plan`,
              `apply` and `upgrade-ledger` alone, since the other verbs reject
              that flag; and reads
              {option}`services.omnigraph.environmentFile` for the storage
              credentials, which omnigraph accepts only from the process
              environment. That file is readable by root alone, so the wrapper
              must run as root; it refuses with that instruction rather than
              falling through to the instance metadata service and hanging.

              Stop `omnigraph-server` before any direct write: a direct writer
              needs the cluster's admission lock, which the server holds while
              it runs. A converged `omnigraph-cluster apply` on a local or S3
              root releases that lock when it exits. Every other direct writer
              (`optimize`, recovery, and an apply whose accepted work does not
              converge or that runs on an Azure root) retains it,
              and the server refuses to boot past it: release the lock the
              command reported with `omnigraph-cluster force-unlock <LOCK_ID>`
              before starting the server again. The `omnigraph-cluster-apply`
              unit releases a lock its own converged apply retained.

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
              Actor passed as `--as` by `omnigraph cluster apply` (the
              `omnigraph-cluster-apply` unit and the `omnigraph-cluster`
              wrapper) and by the `omnigraph-optimize` unit, and recorded
              against every change they make.

              omnigraph judges a direct write to a cluster graph by the policy
              the cluster applied to that graph, and denies an actor that
              policy does not permit. Each graph's policy must therefore grant
              this actor `schema_apply` on `main` for a schema change or its
              recovery, `read` and `schema_apply` for deleting the graph, and
              `maintain` for optimize. Policy changes themselves are not judged
              by the applied policy on a direct apply.
            '';
          };

          apply.auto = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Whether to run `omnigraph cluster apply` automatically: at boot,
              and again whenever the rendered configuration directory changes.

              A direct apply requires the server stopped; a converged apply on
              a local or S3 root releases the cluster's admission lock itself,
              and the unit releases one its apply retained (on an Azure root).
              A run while `omnigraph-server` holds the cluster's lock
              is refused, so a configuration change re-triggered on a running
              server fails until the server is stopped.

              Left off, converging is an operator action (stop
              `omnigraph-server`, `systemctl restart
              omnigraph-cluster-apply.service`, then start `omnigraph-server`).
              The verb is `restart`, not `start`: the unit sets
              `RemainAfterExit`, without which a changed configuration directory
              could never re-trigger it, so once it has run it stays
              `active (exited)` and `start` returns 0 without converging
              anything. Activation never starts or restarts the unit: nothing
              wants it, and it sets `restartIfChanged = false`, so a deploy that
              changes the rendered configuration while it is `active (exited)`
              leaves it alone rather than running an apply that the running
              server's lock would refuse.

              Off is the safer default because apply initializes a root that
              holds no cluster state without ceremony: were the storage root
              lost out of band, an automatic apply would recreate it empty and
              report an ordinary deployment. First initialization of a fresh
              root does not need this on:
              {option}`services.omnigraph.cluster.bootstrap.enable` applies
              exactly once, and refuses to when the root was initialized
              before and has since gone missing.
            '';
          };

          bootstrap.enable = lib.mkOption {
            type = lib.types.bool;
            default = cfg.cluster.enable;
            defaultText = lib.literalExpression "config.services.omnigraph.cluster.enable";
            description = ''
              Whether to run the `omnigraph-cluster-bootstrap` unit before
              `omnigraph-cluster-apply` and `omnigraph-server`. It initializes a
              fresh storage root exactly once, so a new deployment serves
              without a manual apply, while keeping the lost-root protection
              that {option}`services.omnigraph.cluster.apply.auto` being off
              provides.

              The cluster state lives only inside the root, so nothing in the
              root can say whether it was initialized before. The unit records
              that in a marker outside the root instead, under a
              `_omnigraph-markers` prefix beside it: the storage URI with
              trailing slashes removed is split into parent and name, and the
              marker is `<parent>/_omnigraph-markers/<name>.initialized` (for
              `s3://bucket/clusters/dev` the object
              `s3://bucket/clusters/_omnigraph-markers/dev.initialized`, for a
              directory the corresponding file). It does not share the root's
              key prefix, so deleting the root by prefix leaves it in place.
              The unit then acts on the cluster state
              (`omnigraph cluster status`) and the marker:

              - state present, marker present: nothing to do.
              - state present, marker absent: an existing root is adopted by
                writing the marker; nothing is applied.
              - state absent, marker absent: first initialization — the
                `omnigraph-cluster-apply` program runs, and the marker is
                written only once it converges.
              - state absent, marker present: the root was initialized before
                and is now missing. The unit refuses, fails, and never
                applies, so a lost root is not silently recreated empty.
                Restore the root from backup; or, to start empty
                deliberately, delete the marker and run
                `systemctl restart omnigraph-cluster-bootstrap.service`.

              An `s3://` root requires {option}`services.omnigraph.s3.endpointUrl`
              and {option}`services.omnigraph.s3.region`, which the marker's
              path-style signed requests need; other roots must be a plain path
              or a `file://` URI.
            '';
          };

          graphs = lib.mkOption {
            type = lib.types.attrsOf (
              lib.types.submodule {
                options = {
                  exampleDataOnly = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = ''
                      Whether the graph holds example data only, which may be
                      loaded automatically and recreated with its storage root.
                      {option}`seed` is refused on a graph without this.
                    '';
                  };

                  seed = lib.mkOption {
                    type = lib.types.nullOr (
                      lib.types.submodule {
                        options = {
                          file = lib.mkOption {
                            type = lib.types.path;
                            description = "NDJSON seed loaded into the graph's `main` branch with `--mode append`.";
                          };
                          actor = lib.mkOption {
                            type = lib.types.str;
                            example = "seeder";
                            description = ''
                              Bearer-token actor the load runs as. The graph's
                              policy must grant it `change` on `main`, which is
                              all a served load into an existing branch needs.
                            '';
                          };
                          tokenFile = lib.mkOption {
                            type = lib.types.path;
                            description = ''
                              File holding the actor's bearer token alone. The
                              server adds it to
                              {option}`services.omnigraph.bearerTokensFile` at
                              start, and the seed unit reads it through systemd
                              credentials, so it never enters the Nix store or a
                              command line.
                            '';
                          };
                        };
                      }
                    );
                    default = null;
                    description = ''
                      Seed loaded once into the graph when the bootstrap creates
                      its storage root, through the running server.

                      On first initialization (no cluster state and no marker)
                      `omnigraph-cluster-bootstrap` writes
                      `<parent>/_omnigraph-markers/<name>.<graph>.seed-pending`
                      beside its `.initialized` marker, before the apply. Adopting
                      an existing root and the nothing-to-do case never write it,
                      so a root initialized earlier is never seeded.

                      `omnigraph-seed-<graph>.service` runs after
                      `omnigraph-server` has started, which its readiness probe
                      makes mean serving. With no pending marker it exits without
                      a request. Otherwise it posts the seed to
                      `/graphs/<graph>/load/ndjson?mode=append&branch=main` as
                      {option}`actor`, and deletes the marker when the load
                      commits, or when it is refused with `key_conflict` and no
                      effect, which means an earlier attempt already committed
                      it. Any other outcome fails the unit and keeps the marker:
                      one load is one commit, all or nothing, and `append` never
                      replaces an existing id, so the retry on the next start
                      commits the seed, or, when an earlier load committed it,
                      is refused. That refusal is the `key_conflict` above,
                      except for a seed that writes edges under a `@card`
                      maximum: omnigraph 0.16.0 refuses its replay as a `@card`
                      violation with effects `unknown`, so its unit fails at
                      every start. The unit then prints the graph, the marker
                      and the command that clears it, to run as root once the
                      graph's snapshot shows it holds the seed.

                      The unit is wanted by and part of `omnigraph-server`, so it
                      runs whenever the server starts or restarts, and sets
                      `restartIfChanged = false`, so a deploy that changes only
                      the seed unit does not run it. With several seeded graphs
                      the units run one at a time, in graph id order, each
                      after the one before it has finished, whatever its
                      outcome. Nothing in this path applies, deletes or
                      recreates a graph or a root.
                    '';
                  };
                };
              }
            );
            default = { };
            example = lib.literalExpression ''
              {
                cookbook-dev-graph = {
                  exampleDataOnly = true;
                  seed = {
                    file = "''${pkgs.omnigraph-cookbooks}/dev-graph/seed.jsonl";
                    actor = "seeder";
                    tokenFile = "/run/secrets/omnigraph-seeder-token";
                  };
                };
              }
            '';
            description = ''
              Facts about graphs declared in
              {option}`services.omnigraph.cluster.settings` `graphs`, by graph
              id, that are not part of `cluster.yaml`.
            '';
          };

          createdAtFormat = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.positive;
            default = null;
            example = 16;
            description = ''
              Storage format (omnigraph's internal schema version) the graphs
              of {option}`services.omnigraph.storageUri` were created at: a
              fact about the existing root, changed only together with the
              root's URI.

              A cluster graph keeps the format it was created with, and
              `omnigraph upgrade` refuses cluster graphs, so once the packaged
              omnigraph no longer reads this format the server cannot open the
              root, and the only way forward is a new root. The
              `omnigraph-format-window` check fails when this format is outside
              the range the packaged binary reads, and the configuration warns
              while it equals {option}`servesFloor`.

              To recreate an example-data root: point
              {option}`services.omnigraph.storageUri` at a new root and set
              this to the format the packaged omnigraph writes
              (`omnigraph version --json`, `internal_schema.writes`), then
              deploy. A root in the `sciexp` bucket is named
              `<family>-f<format>` from this value by
              `flake.lib.omnigraphClusterRoots.name`, and a deliberate fresh
              copy at the same format takes `-r2`, `-r3`, and so on. The
              bootstrap initializes the new root and marks each seeded graph's
              seed pending, and the seed units load them once the server is
              serving. The old root and its markers stay in place, untouched,
              as the way back, listed in
              `flake.lib.omnigraphClusterRoots.rollback` until a later change
              moves them to its `retired` list. A root holding data that is
              not example data must first be exported with the binary that
              still reads it.
            '';
          };

          servesFloor = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.positive;
            default = null;
            example = 14;
            description = ''
              Lowest storage format the packaged omnigraph reads
              (`omnigraph version --json`, `internal_schema.serves[0]`).
              Evaluation cannot run the binary, so the value is recorded here,
              and the `omnigraph-format-window` check fails when it differs from
              the binary's. While {option}`createdAtFormat` equals it, the next
              omnigraph release that raises the floor will no longer open the
              root, and evaluating the configuration warns so.
            '';
          };
        };

        optimize = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
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

              Off by default because optimize runs only directly against
              storage, never through the server, and a direct writer needs the
              cluster's admission lock: it is refused while `omnigraph-server`
              holds that lock, and a run while the server is stopped retains
              its own lock, which then blocks the server's next start until
              `omnigraph-cluster force-unlock <LOCK_ID>` releases it. On a
              local root that next start's stale-lock recovery refuses such a
              lock, so an assertion refuses this option there.

              The unit runs as {option}`services.omnigraph.cluster.actor`
              (`--as`), which the policy applied to each graph in
              {option}`services.omnigraph.optimize.graphs` must grant
              `maintain`; a denied run changes nothing but still retains the
              lock.
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
          {
            assertion =
              !bootstrapEnabled || !storageIsS3 || (cfg.s3.endpointUrl != null && cfg.s3.region != null);
            message = ''
              services.omnigraph.cluster.bootstrap.enable is set for the s3://
              storage root ${cfg.storageUri}, but services.omnigraph.s3.endpointUrl
              and services.omnigraph.s3.region are not both set. The bootstrap
              marker is read and written with path-style SigV4 requests, which
              need both.
            '';
          }
          {
            assertion = !bootstrapEnabled || storageIsS3 || storageIsLocal;
            message = ''
              services.omnigraph.cluster.bootstrap.enable does not support the
              storage URI scheme "${toString storageScheme}://" of
              ${cfg.storageUri}. Its create-once marker can live only beside an
              s3:// root, a plain path or a file:// root. Disable the bootstrap
              for this root.
            '';
          }
          {
            assertion = !bootstrapEnabled || !storageIsLocal || localRootUnderStateDirectory;
            message = ''
              services.omnigraph.cluster.bootstrap.enable is set for the local
              storage root ${cfg.storageUri}, which is not beneath
              ${stateDirectoryPath}/. The omnigraph units run with
              ProtectSystem=strict and are granted no
              ReadWritePaths, so their StateDirectory is the only local storage
              they can write, and the bootstrap marker directory
              (<parent>/_omnigraph-markers) must lie inside it. Place the root
              beneath ${stateDirectoryPath}/, or disable the bootstrap.
            '';
          }
          {
            assertion = !(storageIsLocal && cfg.optimize.enable);
            message = ''
              services.omnigraph.optimize.enable is set for the local storage
              root ${cfg.storageUri}. `omnigraph optimize` runs directly
              against storage and, on a local root, leaves its cluster
              admission lock behind when it exits; omnigraph-server's next
              start then meets a direct writer's lock, which its stale-lock
              recovery refuses to clear, and the server stays down until an
              operator runs `omnigraph-cluster force-unlock <LOCK_ID>`.
              Disable the optimize timer for a local root.
            '';
          }
        ]
        ++ lib.concatLists (
          lib.mapAttrsToList (id: graph: [
            {
              assertion = lib.hasAttr id (cfg.cluster.settings.graphs or { });
              message = ''
                services.omnigraph.cluster.graphs.${id} describes a graph that
                services.omnigraph.cluster.settings.graphs does not declare.
              '';
            }
            {
              assertion = graph.seed == null || graph.exampleDataOnly;
              message = ''
                services.omnigraph.cluster.graphs.${id}.seed is set, but the
                graph is not declared to hold example data only
                (services.omnigraph.cluster.graphs.${id}.exampleDataOnly).
                A seed is loaded automatically into a newly created root, which
                only an example graph may receive.
              '';
            }
            {
              assertion = graph.seed == null || bootstrapEnabled;
              message = ''
                services.omnigraph.cluster.graphs.${id}.seed needs
                services.omnigraph.cluster.bootstrap.enable: only the bootstrap's
                first initialization of a root marks a seed pending.
              '';
            }
            {
              assertion = graph.seed == null || builtins.match "[A-Za-z_][A-Za-z0-9_]*" graph.seed.actor != null;
              message = ''
                services.omnigraph.cluster.graphs.${id}.seed.actor
                (${toString (graph.seed.actor or "")}) must match
                [A-Za-z_][A-Za-z0-9_]*.
              '';
            }
            {
              assertion =
                graph.seed == null
                || lib.all (
                  other:
                  other.seed == null
                  || other.seed.actor != graph.seed.actor
                  || other.seed.tokenFile == graph.seed.tokenFile
                ) (lib.attrValues cfg.cluster.graphs);
              message = ''
                services.omnigraph.cluster.graphs.${id}.seed.actor is the actor
                of another graph's seed with a different tokenFile; one actor has
                one bearer token.
              '';
            }
          ]) cfg.cluster.graphs
        )
        ++ lib.concatLists (
          lib.mapAttrsToList (actor: _: [
            {
              assertion = builtins.match "[A-Za-z_][A-Za-z0-9_]*" actor != null;
              message = ''
                services.omnigraph.extraBearerTokenFiles names the actor
                "${actor}", which must match [A-Za-z_][A-Za-z0-9_]*.
              '';
            }
            {
              assertion = !(seedTokenFiles ? ${actor});
              message = ''
                services.omnigraph.extraBearerTokenFiles names the actor
                ${actor}, which is also a seed actor
                (services.omnigraph.cluster.graphs.<graph>.seed.actor); one
                actor has one bearer token.
              '';
            }
          ]) cfg.extraBearerTokenFiles
        )
        ++ [
          {
            assertion = (createdAtFormat == null) == (servesFloor == null);
            message = ''
              services.omnigraph.cluster.createdAtFormat and
              services.omnigraph.cluster.servesFloor are recorded together: the
              format window compares the one with the other.
            '';
          }
          {
            assertion = retiredRootConflicts == [ ];
            message = ''
              services.omnigraph.storageUri (${cfg.storageUri}) is a root the
              terraform configuration deletes from its bucket
              (flake.lib.omnigraphClusterRoots.retired):
              ${lib.concatStringsSep "; " retiredRootConflicts}.
            '';
          }
        ];

        # Printed by every evaluation of the system configuration, while
        # checks.omnigraph-format-window holds servesFloor to the binary.
        warnings = lib.optional (createdAtFormat != null && createdAtFormat == servesFloor) (
          lib.concatStringsSep " " [
            "services.omnigraph: the graphs of ${cfg.storageUri} were created at storage format"
            "${toString createdAtFormat}, the lowest format the packaged omnigraph ${cfg.package.version}"
            "reads (services.omnigraph.cluster.servesFloor). The next omnigraph release that raises"
            "that floor will not open this root, and a cluster graph cannot be upgraded in place:"
            "plan to recreate the root under a new suffix (exporting it first with the binary that"
            "still reads it if it holds anything but example data) before taking that release."
          ]
        );

        environment.systemPackages = lib.optionals cfg.cluster.enable [
          cfg.package
          clusterCli
        ];

        # Every unit runs as this static user, on either store, never as a
        # DynamicUser. It owns a local root's files on disk, so a direct
        # writer, a backup restore and every unit agree on their owner (a
        # DynamicUser state directory is an id-mapped mount in systemd 262,
        # which fails with a dataset mounted beneath it and leaves files owned
        # by `nobody`). And it keeps the state directory a plain directory
        # under both stores: a DynamicUser unit moves a plain
        # /var/lib/omnigraph into /var/lib/private by rename(2), which a
        # dataset mounted there refuses, so switching a host that served
        # locally back to an object store would fail every unit
        # (setup_exec_directory, src/core/exec-invoke.c). A unit started
        # under DynamicUser before leaves the symlink to
        # /var/lib/private/omnigraph, which systemd moves back at the static
        # unit's first start.
        users.users.${cfg.user} = {
          isSystemUser = true;
          inherit (cfg) group;
        };
        users.groups.${cfg.group} = { };

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
          after = [
            "network-online.target"
          ]
          ++ lib.optional bootstrapEnabled "omnigraph-cluster-bootstrap.service";
          # Wants, not Requires: a refused bootstrap stays visible as a failed
          # unit, and the server then fails fast through the readiness probe.
          wants = [
            "network-online.target"
          ]
          ++ lib.optional bootstrapEnabled "omnigraph-cluster-bootstrap.service";
          restartTriggers = lib.optional (cfg.cluster.enable && cfg.cluster.apply.auto) clusterConfigDir;

          environment = {
            OMNIGRAPH_SERVER_BEARER_TOKENS_FILE = "%t/omnigraph-server/bearer-tokens.json";
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
            ExecStartPre = lib.optional storageIsLocal "+${lib.getExe lockRecovery}" ++ [
              (lib.getExe assembleBearerTokens)
            ];
            ExecStartPost = lib.getExe readinessProbe;
            EnvironmentFile = environmentFiles;
            LoadCredential =
              lib.optional (cfg.bearerTokensFile != null) "bearer-tokens:${cfg.bearerTokensFile}"
              ++ lib.mapAttrsToList (
                actor: tokenFile: "${tokenCredentialName actor}:${tokenFile}"
              ) bearerTokenFiles;
            RuntimeDirectory = "omnigraph-server";
            StateDirectory = "omnigraph";
            User = cfg.user;
            Group = cfg.group;
            Restart = "on-failure";
            RestartSec = serverRestartSec;
            # Load-bearing: the readiness probe runs inside the start job, and
            # opening the datasets outruns systemd's 90s default, which would
            # kill a healthy server into a Restart=on-failure loop. A server
            # that exits during boot does not consume this budget: the probe
            # sees the main process gone and fails the job at once.
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
            mountRequirement
            // (
              if cfg.requireAllGraphs then
                {
                  StartLimitIntervalSec = (serverStartLimitBurst + 1) * serverStartCycleSec;
                  StartLimitBurst = serverStartLimitBurst;
                }
              else
                { StartLimitIntervalSec = 0; }
            );
        };

        systemd.services.omnigraph-cluster-apply = lib.mkIf cfg.cluster.enable {
          description = "Converge the omnigraph cluster to its declared configuration";
          before = [ "omnigraph-server.service" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = lib.optional cfg.cluster.apply.auto "multi-user.target";
          restartTriggers = lib.optional cfg.cluster.apply.auto clusterConfigDir;
          # Left off, only an operator runs the unit. Nothing wants it, so
          # activation never starts it, and this keeps activation from
          # restarting it while it is `active (exited)` from a run by hand.
          restartIfChanged = cfg.cluster.apply.auto;

          environment = {
            OMNIGRAPH_HOME = "%T/omnigraph";
          }
          // storageEnvironment
          // cfg.extraEnvironment;

          unitConfig = mountRequirement;

          serviceConfig = hardening // {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe applyScript;
            EnvironmentFile = environmentFiles;
            StateDirectory = "omnigraph";
            User = cfg.user;
            Group = cfg.group;
          };
        };

        systemd.services.omnigraph-cluster-bootstrap = lib.mkIf bootstrapEnabled {
          description = "Initialize the omnigraph cluster storage root once";
          wantedBy = [ "multi-user.target" ];
          before = [
            "omnigraph-server.service"
            "omnigraph-cluster-apply.service"
          ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          environment = {
            OMNIGRAPH_HOME = "%T/omnigraph";
          }
          // storageEnvironment
          // cfg.extraEnvironment;

          unitConfig = mountRequirement;

          serviceConfig = hardening // {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe bootstrapScript;
            EnvironmentFile = environmentFiles;
            StateDirectory = "omnigraph";
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

          unitConfig = mountRequirement;

          serviceConfig = hardening // {
            Type = "oneshot";
            ExecStart = map (
              graph:
              lib.escapeShellArgs [
                (lib.getExe cfg.package)
                "--as"
                cfg.cluster.actor
                "optimize"
                "--target"
                cfg.storageUri
                "--graph"
                graph
                "--json"
              ]
            ) cfg.optimize.graphs;
            EnvironmentFile = environmentFiles;
            StateDirectory = "omnigraph";
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
