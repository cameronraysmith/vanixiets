{
  config,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.nixos;
  inherit (config.flake.lib) workerAccountsOn;
  inherit (config.flake.lib.hosts) magnetite;
  inherit (config.flake.lib) meshInterfaces;
  inherit (config.flake.lib) zfsBootInvariants;
in
{
  flake.modules.nixos."machines/nixos/magnetite" =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      # Where magnetite's omnigraph root lives (vanixiets.omnigraphRootStore,
      # declared by the omnigraph-server aspect): "local" or "r2".
      omnigraphRootStore = config.vanixiets.omnigraphRootStore;
    in
    {
      imports = [
        inputs.srvos.nixosModules.server
        inputs.srvos.nixosModules.mixins-nginx
        inputs.home-manager.nixosModules.home-manager
        inputs.niks3.nixosModules.niks3
        inputs.nixbot.nixosModules.nixbot
        inputs.gitea-mq.nixosModules.default
      ]
      ++ (with flakeModules; [
        hetzner-cloud
        base
        home-manager-integration
        deploy-record
        kvm-declaration
        magnetite-user-slice-guard
        memory-pressure-guards
        niks3
        ssh-known-hosts
        stibnite-session
        zt-dns
        nixbot
        gitea-mq
        renovate
        gitea
        sso-gateway
        perses
        gitea-actions-runner
        docker
        kanidm
        matrix
        omnigraph
        greptimedb
        devloop-collection
        agent-session-store
        fleet-alert
        ntfy-alerter
        effects-vanixiets-secrets
        effects-ironstar-secrets
        shared-reference-tree
        postgresql-backup
        r2-usage
        perses-server
        fleet-alert-server
        omnigraph-server
        greptimedb-server
      ]);

      services.shared-reference-tree = {
        participants = [ "cameron" ] ++ workerAccountsOn "magnetite";
      };

      # Bootloader: GRUB BIOS mode (CX53 has legacy BIOS only, not UEFI)
      # The hetzner-cloud aspect (srvos's Hetzner hardware module) handles GRUB BIOS configuration

      networking.hostName = "magnetite";

      networking.search = [ ];

      # Hetzner CX53 with no nested virtualisation, so no /dev/kvm.
      declaredKvm.present = false;

      # systemd-nspawn-flavor NixOS tests require uid-range, auto-allocate-uids, and cgroups.
      # See nixos/doc/manual/development/running-nixos-tests.section.md in nixpkgs.
      nix.settings = {
        auto-allocate-uids = true;
        extra-system-features = [ "uid-range" ];
        experimental-features = [
          "auto-allocate-uids"
          "cgroups"
        ];
      };

      # magnetite is x86_64-linux and cannot build aarch64-darwin derivations,
      # so darwin work is dispatched to the fleet's darwin machines through the
      # nix-builders clan service (modules/clan/inventory/services/nix-builders.nix),
      # which also makes magnetite the builder stibnite sends x86_64-linux work
      # to. Two mechanisms, two callers:
      #   nix.buildMachines, set by the service — a local nix build by an
      #     operator who wants the darwin result in magnetite's store.
      #   /etc/nix/<builder>-store-uri — a caller that wants the build to happen
      #     entirely in that builder's store with nothing copied back.
      # nixbot also builds checks.aarch64-darwin through these builders, and
      # requires them like every other check.

      # The build and session keys are separately authorized for independent
      # revocation and rotation. Only the build key is confined to the Nix
      # protocol by `restrict` and a forced command. The session key is broader:
      # it grants an unrestricted login as admin-group crs58, already a Nix
      # trusted user, with build authority plus shell.

      # User configuration managed via clan inventory users service (modules/clan/inventory/services/users/cameron.nix).

      security.sudo.wheelNeedsPassword = false;

      security.acme = {
        acceptTerms = true;
        defaults.email = "cameron@scientistexperience.net";
      };

      # Parked, not removed: the shared kanidm-OIDC SSO gateway
      # (modules/nixos/sso-gateway.nix) stays imported and off, and its
      # generated vars (sso-cookie-secret, kanidm-oauth2-sso) are kept. It has
      # no public DNS record any more (modules/terranix/cloudflare.nix). To
      # revive it, set its enable below, restore its auth. CNAME and declare it
      # in modules/lib/topology-facts.nix. Its auth-root redirect to the kanidm
      # portal and its apps-portal icon were dropped with "chore: expunge
      # buildbot and kanban, park sso-gateway and cognee"; recover them from
      # that commit's parent.
      sso.enable = false;

      # Tune ZFS auto-snapshot retention for a single-disk cloud VPS without
      # off-site snapshot replication. The nixpkgs defaults (frequent=4,
      # hourly=24, daily=7, weekly=4, monthly=1 via srvos mkDefault) are
      # calibrated for workstations with USB backup targets and produce
      # excessive snapshot churn on a cloud node. `/nix` is opted out via
      # the disko `com.sun:auto-snapshot=false` property; the remaining
      # datasets (/nixos, /home, /docker, /podman) retain a short window.
      services.zfs.autoSnapshot = {
        frequent = 0;
        hourly = 4;
        daily = 3;
        weekly = 1;
        monthly = lib.mkForce 0;
      };

      # The ZFS dataset properties magnetite enforces at boot, one oneshot per
      # entry of flake.lib.zfsBootInvariants.magnetite
      # (modules/lib/zfs-boot-invariants.nix). Disko's options (disko.nix) are
      # honored only at dataset CREATION time and are not re-asserted on an
      # already-provisioned host by `nixos-rebuild switch` or `clan machines
      # update`; these oneshots make the declared values a runtime invariant
      # by issuing `zfs set` at boot. `zfs set` is a no-op when the value
      # already matches, so the units are idempotent and side-effect-free on
      # repeat boots. An entry's `when` names the condition under which its
      # dataset exists.
      systemd.services =
        let
          enabled = {
            postgresqlBackup = config.vanixiets.postgresqlBackup.enable;
            omnigraphLocalRoot = omnigraphRootStore == "local";
          };
        in
        lib.listToAttrs (
          map (
            invariant:
            lib.nameValuePair invariant.unit (
              lib.mkIf (invariant.when == null || enabled.${invariant.when}) {
                description = "Assert ${invariant.property}=${invariant.value} on ${invariant.dataset}";
                wantedBy = [ "multi-user.target" ];
                after = [ "zfs-import.target" ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  ExecStart = "${pkgs.zfs}/bin/zfs set ${invariant.property}=${invariant.value} ${invariant.dataset}";
                };
              }
            )
          ) zfsBootInvariants.magnetite
        );

      # Nightly PostgreSQL backups to R2 (back-up-postgresql-off-host design
      # D16), on with this host's postgresql-backup-r2 and
      # postgresql-backup-restic vars in the repository and the dataset
      # zroot/root/postgresql-dumps created by hand (tasks.md 2.1).
      vanixiets.postgresqlBackup.enable = true;

      # The account's R2 usage, polled hourly (openspec change
      # track-r2-usage, design D6), on with this host's cloudflare-analytics
      # vars in the repository.
      vanixiets.r2Usage.enable = true;

      # Nightly backups of the local omnigraph root to R2 (openspec change
      # serve-omnigraph-from-local-disk), with this host's
      # omnigraph-backup-r2 and omnigraph-backup-restic vars in the
      # repository and the dataset zroot/root/omnigraph created by hand; a
      # root in the bucket has no snapshot to back up.
      vanixiets.omnigraphBackup.enable = omnigraphRootStore == "local";

      # Raise nix daemon free-space thresholds for a build host. clan-core and
      # srvos both set 512 MiB / 3 GiB via mkDefault, which is undersized for
      # build workers materializing large closures on a CX53 with niks3
      # GC pressure. Trigger GC at 30 GiB free, free until 80 GiB available.
      #
      # http-connections and max-substitution-jobs raise the daemon's ceiling on
      # concurrent cache round trips. Both were at their nix defaults, and the
      # daemon is where every substituter byte originates: nixbot.service sets
      # RestrictAddressFamilies=AF_UNIX and runs nix-eval-jobs under bwrap, so
      # the evaluator reaches the network only by asking the daemon over its
      # UNIX socket. nixbot hard-codes --check-cache-status in that invocation
      # (nix_eval.py), so every evaluated attribute's closure is resolved
      # against all nine configured substituters before the evaluation can
      # finish, and neither the flag nor nixbot's eval_concurrency is reachable
      # from its NixOS module.
      #
      # Measured on 2026-09-02, build 172 (117 attributes, 490 s): a ~75-90 s
      # burst where six nix-eval-jobs workers each hold 75-85% of a core, then
      # 6.5-7 min in which the master has no children at all and sits in
      # unix_stream_read on the daemon socket with a flat
      # voluntary_ctxt_switches count, taking ~48 reads/s, while the daemon
      # itself idles at a few percent CPU holding established TLS connections
      # to the caches. 85% of that evaluation's wall clock is this wait. Host
      # load was 1.11 of 16 CPUs with vmstat wa=0, so it is neither CPU nor IO
      # saturation. A path absent from every cache costs the sum over the nine
      # endpoints, ~1.27 s of serial-equivalent latency measured by curl, of
      # which TLS is only 30-65 ms: the cost is round trips, not handshakes,
      # and keep-alive reuse was confirmed working (6 ms warm hit).
      #
      # Both dials therefore oversubscribe relative to the 16 cores on purpose,
      # because the work they bound is latency-bound rather than CPU-bound.
      # Neither is bounded by RAM: they live in nix-daemon.service, outside the
      # eval cgroup. That cgroup's memory.max is not the binding ceiling either
      # (nixbot sizes it above physical RAM; MemoryHigh 12G on the service is
      # what binds, nixbot.nix), and host memory is shared with every other
      # evaluator, which is why evaluations are serialised by the host
      # evaluation lock (modules/nixos/nix-eval-lock.nix). A curl handle costs
      # tens of KiB, so 100 connections is single-digit MiB.
      nix.settings = {
        min-free = 30 * 1024 * 1024 * 1024;
        max-free = 80 * 1024 * 1024 * 1024;

        # Default 25. Bounded by file descriptors and outbound sockets.
        http-connections = 100;

        # Default 16. Bounded by CPU for decompression and by network for the
        # transfers themselves; unlike http-connections this one is not measured
        # as binding, because the wait above is evaluation-time narinfo
        # resolution rather than build-time substitution.
        max-substitution-jobs = 32;

        # Trivial builders (bun2nix's per-package derivations, runCommandLocal)
        # set allowSubstitutes = false because building locally is cheaper than
        # fetching. magnetite cannot build their aarch64-darwin variants, so
        # each one becomes a remote build; fetching from niks3 is far cheaper.
        always-allow-substitutes = true;
      };

      # A warm store (bound-fleet-garbage-collection D8): harmonia-gc stops
      # once 40 % of the store's filesystem is free instead of deleting every
      # unrooted output, so recent builds stay cached. `40%` is of the size
      # statfs reports for the quota-bounded /nix dataset (A152). It was sized
      # for one run a day, which let the store grow unchecked for up to 24
      # hours (197 GiB against the 250G quota on 2026-11-25); reconsider it
      # against a week of vanixiets_zfs_dataset_used_bytes for zroot/root/nix
      # under the hourly schedule.
      # Hourly: a run with enough free space exits without taking gc.lock, so
      # an idle run costs milliseconds and growth between runs is bounded by
      # an hour's builds. The 2 h bound stays; systemd does not start a run
      # while the previous one is still active.
      # Three days of generations: at magnetite's deploy rate 10 days kept
      # about 60 system generations across several nixpkgs versions, whose
      # closures the free-space target then had to make room for by deleting
      # recent build outputs. harmonia-gc keeps the current generation and
      # the newest one older than the cutoff.
      # noVacuum, as upstream recommends for busy builders: concurrent daemon
      # readers stop the post-GC VACUUM's WAL from being cleaned up.
      services.harmonia-dev.gc = {
        ensureFree = "40%";
        noVacuum = true;
        dates = "hourly UTC";
        deleteOlderThan = "3d";
      };

      # Nix >= 2.30 keeps build sandboxes in /nix/var/nix/builds; the only
      # reaper is the Nix package's tmpfiles rule (nix-daemon.conf, age 7d).
      # A 7d window let a nix-daemon ENOSPC crash-loop orphan 201 sandboxes
      # (232 GiB) on 2026-06-10. This entry renders into 00-nixos.conf, which
      # sorts before nix-daemon.conf, so per tmpfiles.d(5) precedence the 1d
      # age wins for this path. Active sandboxes (<= 3h nixbot build
      # timeout) never enter the 1d window.
      systemd.tmpfiles.rules = [
        "d /nix/var/nix/builds 0755 root root 1d -"
      ];

      # R8.2 credential holders (ADR-008; review F5): for each greptimedb-users
      # secret, the units allowed to load it, and no others. Entries are
      # "<id>:<source path>" and matched on the path, because each unit
      # chooses its own id and kanidm-site-branding already loads an unrelated
      # "admin-password" id. An assertion rather than a flake check, because
      # the toplevel already forces every unit's LoadCredential, while a check
      # forcing them again cost about 1.6 GiB of evaluation.
      assertions =
        let
          usersFiles = config.vanixiets.secrets.greptimedb-users.files;
          allowed = {
            users = [ "greptimedb" ];
            admin-password = [ "greptimedb-schema" ];
            collector-password = [ "opentelemetry-collector" ];
            perses-password = [ "perses" ];
            # Sorted, because `actual` is naturalSorted: the four regulators
            # that read the store, devloop-reconcile, fleet-alert,
            # greptimedb-envelope and otel-envelope's hourly budget.
            regulator-password = [
              "devloop-reconcile"
              "fleet-alert"
              "greptimedb-envelope"
              "otel-envelope"
            ];
          };
          credentialSource = entry: lib.concatStringsSep ":" (lib.drop 1 (lib.splitString ":" entry));
          holdersOf =
            path:
            lib.naturalSort (
              lib.attrNames (
                lib.filterAttrs (
                  _: service:
                  lib.any (entry: credentialSource entry == path) (
                    lib.toList (service.serviceConfig.LoadCredential or [ ])
                  )
                ) config.systemd.services
              )
            );
          actual = lib.mapAttrs (name: _: holdersOf usersFiles.${name}.path) allowed;
        in
        [
          {
            assertion = actual == allowed;
            message = "magnetite: greptimedb-users credentials are loaded by ${builtins.toJSON actual}; R8.2 allows only ${builtins.toJSON allowed}";
          }
        ]
        # Relations among magnetite's own units, asserted here rather than in
        # a flake check: a relation within one host is a module assertion,
        # which CI already pays for when it evaluates the host (S1 review F5).
        ++ (
          let
            # systemd memory sizes with an M or G suffix, which systemd reads
            # as powers of 1024.
            sizeBytes =
              size:
              let
                m = builtins.match "([0-9]+)([MG])" (toString size);
              in
              if m == null then
                null
              else
                lib.toInt (builtins.head m)
                * (if builtins.elemAt m 1 == "G" then 1024 * 1024 * 1024 else 1024 * 1024);
            store = config.systemd.services.greptimedb.serviceConfig;
            high = sizeBytes (store.MemoryHigh or "");
            max = sizeBytes (store.MemoryMax or "");

            # The evaluator's oom_score_adj is set by the nix-eval-lock wrapper
            # script, not by a unit, so it is read from that script.
            evaluatorAdj =
              let
                matches = lib.concatMap (
                  line:
                  let
                    m = builtins.match "[[:space:]]*echo ([0-9]+) >/proc/self/oom_score_adj" line;
                  in
                  if m == null then [ ] else m
                ) (lib.splitString "\n" (builtins.readFile ../../../lib/nix-eval-lock.sh));
              in
              if builtins.length matches == 1 then lib.toInt (builtins.head matches) else null;
            # An absent unit or setting reads as 1000, so the order fails.
            unitAdj =
              name:
              ((config.systemd.services.${name} or { serviceConfig = { }; }).serviceConfig.OOMScoreAdjust or 1000
              );
            order = {
              nix-eval-jobs = evaluatorAdj;
              otel-agent-session = unitAdj "otel-agent-session";
              perses = unitAdj "perses";
              greptimedb = unitAdj "greptimedb";
              opentelemetry-collector = unitAdj "opentelemetry-collector";
              fleet-alert = unitAdj "fleet-alert";
            };
          in
          [
            # R7.1: the store is throttled before its ceiling and never swaps.
            {
              assertion =
                high != null && max != null && high < max && toString (store.MemorySwapMax or "unset") == "0";
              message = "magnetite: R7.1 requires greptimedb.service to run with MemoryHigh below MemoryMax and MemorySwapMax = 0; it has MemoryHigh = ${
                builtins.toJSON (store.MemoryHigh or null)
              }, MemoryMax = ${builtins.toJSON (store.MemoryMax or null)}, MemorySwapMax = ${
                builtins.toJSON (store.MemorySwapMax or null)
              }.";
            }
            # R7.1 (A7:100,127), S3 design D12 and CAM-73 design D8: under host
            # OOM the kernel kills the evaluator, then the agent-session
            # collector (agent-session-telemetry design D14), whose loss costs
            # only agent telemetry, then the dashboard service, then the
            # store, then the collector, so the collector outlives the store
            # and queues; the alert evaluator, which reports OOM kills, is
            # taken after all of them. nixbot's evaluator is iets
            # (CAM-111), which fails the whole evaluation when one of its
            # workers is killed, so being first does not make it cheap: its
            # headroom is kept by CAM-111 design D9's capacity decisions, and
            # nixbot's one-line revert to nix-eval-jobs is the safety valve.
            {
              assertion =
                config.services.nixEvalLock.enable
                && evaluatorAdj != null
                && evaluatorAdj > order.otel-agent-session
                && order.otel-agent-session > order.perses
                && order.perses > order.greptimedb
                && order.greptimedb > order.opentelemetry-collector
                && order.opentelemetry-collector > order.fleet-alert;
              message = "magnetite: R7.1, S3 design D12, CAM-73 design D8 and agent-session-telemetry design D14 require the evaluation lock and oom_score_adj nix-eval-jobs > otel-agent-session > perses > greptimedb > opentelemetry-collector > fleet-alert; the lock is ${
                if config.services.nixEvalLock.enable then "enabled" else "disabled"
              } and the values are ${builtins.toJSON order}.";
            }
          ]
        );

      # nixbot's `8 x 4096` nix-eval-jobs configuration peaks at 31.4 GiB of
      # swap (logs/magnetite-zram-headroom-experiment.md §6.2), above the
      # 30.6 GiB a single zram0 at the fleet default of 100 % provides, and an
      # eval that exhausts swap is OOM-killed into a permanent PR failure.
      # 150 % is 45.9 GiB; holding that peak costs ~6.9 GiB of real RAM at the
      # measured 4.55x. Machine-scoped, not fleet-wide: pyrite is a 15 GiB
      # laptop that livelocked under zram pressure. base sets the fleet default
      # with lib.mkDefault (modules/system/zram-swap.nix).
      zramSwap.memoryPercent = 150;

      # The 60 default is calibrated for disk swap. Nothing reaches zram
      # without reclaim pressure, and the measured runs used 100, which is also
      # what clan-infra sets on its zram hosts.
      boot.kernel.sysctl."vm.swappiness" = 100;

      # Memory-pressure governance. nixbot's evaluation overlapping a remote
      # `just check-fast` evaluation OOM-killed this host twice (2026-09-27,
      # 2026-10-01). The evaluation lock serialises every nix-eval-jobs here
      # (nixbot, ssh users) and makes the running evaluator the OOM
      # killer's first choice; MGLRU thrash protection turns a working-set
      # collapse into an OOM kill. Rationale: modules/nixos/nix-eval-lock.nix,
      # modules/nixos/memory-pressure-guards.nix.
      services.nixEvalLock.enable = true;

      # Sessions here take this path with flock(1) directly; the link puts
      # them on the same lock as nix-build-locked.
      services.nixBuildLock.legacyLockFile = "/tmp/cam124-build.lock";

      # Permit binding magnetite's ZeroTier-assigned IPv6 before zerotierone
      # settles on cold boot (mirrors modules/machines/nixos/cinnabar/caddy.nix).
      boot.kernel.sysctl."net.ipv6.ip_nonlocal_bind" = 1;

      # Firewall configuration: dual-zone (public + mesh)
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [
          22
          80
          443
        ];
        # Admin and internal services accessible over the mesh only
        interfaces = lib.genAttrs (meshInterfaces config) (_: {
          allowedTCPPorts = [ 8090 ]; # omnigraph; further ports added by service modules
        });
      };

      # nix-fast-build --remote opens one ssh connection per build, so a client
      # with N cores offers up to N concurrent pre-auth connections. sshd's
      # default MaxStartups of 10:30:100 starts dropping past ten, and a dropped
      # handshake surfaces as `kex_exchange_identification: Connection reset by
      # peer` and an exit status of 255 attributed to whichever build owned the
      # connection -- a red check naming a package that is not at fault. An
      # 18-core client reliably lost a random handful of checks per run this way.
      services.openssh.settings.MaxStartups = "64:30:256";
    };
}
