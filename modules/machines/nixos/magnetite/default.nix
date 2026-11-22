{
  config,
  inputs,
  ...
}:
let
  flakeModules = config.flake.modules.nixos;
  flakeUsers = config.flake.users;
  inherit (config.flake.lib.hosts) magnetite;
  inherit (config.flake.lib) fleet;
  inherit (config.flake.lib) meshInterfaces;
  collectorSchema = config.flake.lib.otelCollectorSchema;
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
      omnigraphCookbooks = pkgs.fetchFromGitHub {
        owner = "ModernRelay";
        repo = "omnigraph-cookbooks";
        rev = "c13bac144fcf5692fab38b83fc09705d37789d6e";
        hash = "sha256-807iN/pe/JVlPPcKuz8+KfGXv72UJGl18fo5x4ElpWQ=";
      };

      # The telemetry store's dataset (ADR-007 E7.3; design D5): one source for
      # the boot oneshots below and for greptimedb-envelope's environment.
      # disko.nix repeats the values as its install-time declaration, and
      # checks.x86_64-linux.greptimedb-envelope asserts the two agree.
      greptimedbDataset = {
        name = "zroot/root/greptimedb";
        mountpoint = "/var/lib/greptimedb";
        quota = "16G";
        reservation = "12G";
      };
    in
    {
      imports = [
        inputs.srvos.nixosModules.server
        inputs.srvos.nixosModules.hardware-hetzner-cloud
        inputs.srvos.nixosModules.mixins-nginx
        inputs.home-manager.nixosModules.home-manager
        inputs.niks3.nixosModules.niks3
        inputs.nixbot.nixosModules.nixbot
        inputs.gitea-mq.nixosModules.default
      ]
      ++ (with flakeModules; [
        base
        deploy-record
        hm-sops-bridge
        kvm-declaration
        magnetite-user-slice-guard
        memory-pressure-guards
        niks3
        nix-eval-lock
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
      ]);

      services.shared-reference-tree = {
        enable = true;
        participants = [
          "cameron"
          "omnigent-cameron"
          "omnigent-janettesmith"
        ];
      };

      # Make flake available to all modules (required by ssh-known-hosts)
      _module.args.flake = inputs.self;

      nixpkgs.hostPlatform = "x86_64-linux";

      # ZFS device node path - more stable for cloud VMs
      boot.zfs.devNodes = "/dev/disk/by-path";

      # Bootloader: GRUB BIOS mode (CX53 has legacy BIOS only, not UEFI)
      # srvos hardware-hetzner-cloud handles GRUB BIOS configuration

      networking.hostName = "magnetite";

      networking.search = [ ];

      system.stateVersion = "25.05";

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
      # nixbot also builds checks.aarch64-darwin through these builders, as
      # best-effort: the darwin builders are laptops without guaranteed
      # availability, so each darwin check carries ignoreFailure and a
      # sleeping machine leaves a notice rather than gating CI
      # (modules/checks/nixbot-best-effort-darwin.nix).

      # The build and session keys are separately authorized for independent
      # revocation and rotation. Only the build key is confined to the Nix
      # protocol by `restrict` and a forced command. The session key is broader:
      # it grants an unrestricted login as admin-group crs58, already a Nix
      # trusted user, with build authority plus shell.
      services.stibnite-session.enable = true;

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

      # The removed cognee server's database and root/cognee dataset are kept.
      # The database is unreadable without pgvector (F63), so the collector's
      # collation drift receiver and the backup set leave it out. Drop this
      # together with that database.
      vanixiets.postgresqlCollation.parkedDatabases = [ "cognee" ];

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

      # Disko's `options."com.sun:auto-snapshot" = "false"` on reproducible-content
      # datasets (root/nix, root/docker, root/podman; see disko.nix) is honored only
      # at dataset CREATION time. For already-provisioned hosts, the property is not
      # re-asserted by `nixos-rebuild switch` or `clan machines update`. These oneshots
      # make the declared intent a runtime invariant by issuing `zfs set` at boot.
      # `zfs set` is a no-op when the value already matches, so the units are
      # idempotent and side-effect-free on repeat boots.
      systemd.services.zfs-assert-root-nix-noautosnap = {
        description = "Assert com.sun:auto-snapshot=false on zroot/root/nix";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set com.sun:auto-snapshot=false zroot/root/nix";
        };
      };

      systemd.services.zfs-assert-root-docker-noautosnap = {
        description = "Assert com.sun:auto-snapshot=false on zroot/root/docker";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set com.sun:auto-snapshot=false zroot/root/docker";
        };
      };

      systemd.services.zfs-assert-root-podman-noautosnap = {
        description = "Assert com.sun:auto-snapshot=false on zroot/root/podman";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set com.sun:auto-snapshot=false zroot/root/podman";
        };
      };

      # Pool-starvation guardrails (2026-06-10 incident: /nix consumed the
      # entire 304G pool and wedged every dataset). The quota caps /nix below
      # pool capacity; the reservations guarantee / and /home writable
      # headroom even when /nix hits its quota. Mirrored create-time in
      # disko.nix; these oneshots enforce the values on the already-
      # provisioned host because disko options apply at dataset creation only.
      systemd.services.zfs-set-root-nix-quota = {
        description = "Assert quota=250G on zroot/root/nix";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set quota=250G zroot/root/nix";
        };
      };

      systemd.services.zfs-set-root-nixos-reservation = {
        description = "Assert reservation=10G on zroot/root/nixos";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set reservation=10G zroot/root/nixos";
        };
      };

      systemd.services.zfs-set-root-home-reservation = {
        description = "Assert reservation=4G on zroot/root/home";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set reservation=4G zroot/root/home";
        };
      };

      # The telemetry store's disk envelope, enforced at boot because disko
      # options apply at dataset creation only.
      systemd.services.zfs-set-root-greptimedb-quota = {
        description = "Assert quota=${greptimedbDataset.quota} on ${greptimedbDataset.name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set quota=${greptimedbDataset.quota} ${greptimedbDataset.name}";
        };
      };

      systemd.services.zfs-set-root-greptimedb-reservation = {
        description = "Assert reservation=${greptimedbDataset.reservation} on ${greptimedbDataset.name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set reservation=${greptimedbDataset.reservation} ${greptimedbDataset.name}";
        };
      };

      systemd.services.zfs-assert-root-greptimedb-noautosnap = {
        description = "Assert com.sun:auto-snapshot=false on ${greptimedbDataset.name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "zfs-import.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.zfs}/bin/zfs set com.sun:auto-snapshot=false ${greptimedbDataset.name}";
        };
      };

      # Nightly PostgreSQL backups to R2 (back-up-postgresql-off-host design
      # D16), on with this host's postgresql-backup-r2 and
      # postgresql-backup-restic vars in the repository and the dataset
      # zroot/root/postgresql-dumps created by hand (tasks.md 2.1).
      vanixiets.postgresqlBackup.enable = true;

      # The account's R2 usage, polled hourly (openspec change
      # track-r2-usage, design D6), on with this host's cloudflare-analytics
      # vars in the repository.
      vanixiets.r2Usage.enable = true;

      # The PostgreSQL dumps' dataset (disko.nix, back-up-postgresql-off-host
      # design D5), enforced at boot because disko options apply at dataset
      # creation only; present only with the backup on, as is the dataset.
      systemd.services.zfs-set-root-postgresql-dumps-quota =
        lib.mkIf config.vanixiets.postgresqlBackup.enable
          {
            description = "Assert quota=16G on zroot/root/postgresql-dumps";
            wantedBy = [ "multi-user.target" ];
            after = [ "zfs-import.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${pkgs.zfs}/bin/zfs set quota=16G zroot/root/postgresql-dumps";
            };
          };

      systemd.services.zfs-assert-root-postgresql-dumps-noautosnap =
        lib.mkIf config.vanixiets.postgresqlBackup.enable
          {
            description = "Assert com.sun:auto-snapshot=false on zroot/root/postgresql-dumps";
            wantedBy = [ "multi-user.target" ];
            after = [ "zfs-import.target" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${pkgs.zfs}/bin/zfs set com.sun:auto-snapshot=false zroot/root/postgresql-dumps";
            };
          };

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
      # unrooted output daily, so yesterday's builds stay cached. `40%` is of
      # the size statfs reports for the quota-bounded /nix dataset (A152).
      # noVacuum, as upstream recommends for busy builders: concurrent daemon
      # readers stop the post-GC VACUUM's WAL from being cleaned up.
      services.harmonia-dev.gc = {
        ensureFree = "40%";
        noVacuum = true;
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

      # Cloudflare R2 S3 credentials scoped to the sciexp bucket, delivered as an
      # EnvironmentFile. object_store has no shared-credentials-file provider, so
      # process environment variables are the only source omnigraph resolves.
      clan.core.vars.generators.omnigraph-r2 = {
        prompts.access-key = {
          description = ''
            Cloudflare R2 S3 access key ID with read and write scope on bucket
            sciexp. Minted in the Cloudflare dashboard; distinct from the
            niks3-s3 token, which is scoped to sciexp-nix-cache.
          '';
          type = "hidden";
          persist = true;
          display = {
            group = "omnigraph";
            label = "AWS_ACCESS_KEY_ID";
          };
        };

        prompts.secret-key = {
          description = "Cloudflare R2 S3 secret access key paired with the access key ID above.";
          type = "hidden";
          persist = true;
          display = {
            group = "omnigraph";
            label = "AWS_SECRET_ACCESS_KEY";
          };
        };

        files.access-key.deploy = false;
        files.secret-key.deploy = false;

        files."env" = {
          restartUnits = [ "omnigraph-server.service" ];
        };

        script = ''
          {
            printf 'AWS_ACCESS_KEY_ID=%s\n' "$(cat "$prompts/access-key")"
            printf 'AWS_SECRET_ACCESS_KEY=%s\n' "$(cat "$prompts/secret-key")"
          } > "$out/env"
        '';
      };

      clan.core.vars.generators.omnigraph-bearer-tokens = {
        files."tokens.json" = {
          restartUnits = [ "omnigraph-server.service" ];
        };
        runtimeInputs = [
          pkgs.openssl
          pkgs.jq
        ];
        script = ''
          jq -n --arg token "$(openssl rand -hex 32)" '{admin: $token}' > "$out/tokens.json"
        '';
      };

      services.omnigraph = {
        enable = true;

        # A fresh root for omnigraph 0.15, initialized by the bootstrap unit.
        # The previous root, s3://sciexp/omnigraph/clusters/dev-graph-v9, held
        # only disposable stub data written by 0.11, so nothing was exported
        # into this one.
        storageUri = "s3://sciexp/omnigraph/clusters/dev-graph-v10";

        s3 = {
          endpointUrl = "https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com";
          region = "auto";
        };

        # omnigraph-server takes one --bind, and cinnabar's TLS fronts reach
        # it on both magnetite's ZeroTier and tincr addresses, so it binds the
        # wildcard; 8090 is opened only on the mesh interfaces below and is
        # absent from the global allowedTCPPorts, so the firewall keeps it off
        # the public interface.
        bindAddress = "::";
        port = 8090;
        requireAllGraphs = true;
        # Clients reach /mcp through cinnabar's omnigraph TLS fronts, and the
        # server refuses an MCP request whose Host it does not list.
        extraFlags = [
          "--mcp-allowed-host"
          "omnigraph.zt"
          "--mcp-allowed-host"
          "omnigraph.${fleet.domain}"
        ];

        environmentFile = config.clan.core.vars.generators.omnigraph-r2.files."env".path;
        bearerTokensFile =
          config.clan.core.vars.generators.omnigraph-bearer-tokens.files."tokens.json".path;

        cluster = {
          settings = {
            metadata.name = "dev-graph";
            graphs.dev = {
              schema = "schema.pg";
              queries = "queries/";
            };
            policies = {
              dev = {
                file = "policies/dev.policy.yaml";
                applies_to = [ "dev" ];
              };
              server = {
                file = "policies/server.policy.yaml";
                applies_to = [ "cluster" ];
              };
            };
          };

          extraFiles = {
            "schema.pg" = "${omnigraphCookbooks}/dev-graph/schema.pg";
            "queries" = "${omnigraphCookbooks}/dev-graph/queries";
            "policies/dev.policy.yaml" = ./omnigraph/dev.policy.yaml;
            "policies/server.policy.yaml" = ./omnigraph/server.policy.yaml;
          };

          actor = "magnetite";
        };
      };

      # Store accounts for GreptimeDB (ADR-007, ADR-008; design D6). Hex
      # passwords, because a users line needs exactly one `=` and the store
      # silently skips a malformed line (design F2); written with printf '%s'
      # so no file carries a trailing newline into an HTTP basic-auth header.
      # perses-password is loaded by perses.service, which restarts on its
      # rotation. users-sha256 is public: the sha256 of 256-bit hex passwords
      # is not reversible, and R7.4 compares it with
      # /run/greptimedb/loaded-users.sha256.
      clan.core.vars.generators.greptimedb-users = {
        files.users = {
          owner = "greptimedb";
          mode = "0400";
          restartUnits = [ "greptimedb.service" ];
        };
        files.admin-password.mode = "0400";
        files.collector-password = {
          mode = "0400";
          restartUnits = [ "opentelemetry-collector.service" ];
        };
        files.perses-password = {
          mode = "0400";
          restartUnits = [ "perses.service" ];
        };
        files.regulator-password.mode = "0400";
        files.users-sha256.secret = false;
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          admin="$(openssl rand -hex 32)"
          collector="$(openssl rand -hex 32)"
          perses="$(openssl rand -hex 32)"
          regulator="$(openssl rand -hex 32)"
          printf '%s' "$admin" > "$out/admin-password"
          printf '%s' "$collector" > "$out/collector-password"
          printf '%s' "$perses" > "$out/perses-password"
          printf '%s' "$regulator" > "$out/regulator-password"
          printf 'admin:rw=%s\ncollector:wo=%s\nperses:ro=%s\nregulator:ro=%s\n' \
            "$admin" "$collector" "$perses" "$regulator" > "$out/users"
          sha256sum "$out/users" | cut -d ' ' -f 1 > "$out/users-sha256"
        '';
      };

      # Perses signs its session tokens with this key (design D8); 32 bytes,
      # as Perses requires, and replaced only by regeneration, which restarts
      # perses.service.
      clan.core.vars.generators.perses-encryption-key = {
        files.key = {
          mode = "0400";
          restartUnits = [ "perses.service" ];
        };
        runtimeInputs = [ pkgs.openssl ];
        script = ''
          printf '%s' "$(openssl rand -hex 16)" > "$out/key"
        '';
      };

      # The three files flake.modules.nixos.perses reads, each under
      # /run/credentials/perses.service/.
      systemd.services.perses.serviceConfig.LoadCredential = [
        "kanidm-client-secret:${config.clan.core.vars.generators.kanidm-oauth2-perses.files.secret.path}"
        "encryption-key:${config.clan.core.vars.generators.perses-encryption-key.files.key.path}"
        "perses-password:${config.clan.core.vars.generators.greptimedb-users.files.perses-password.path}"
      ];

      # Cloudflare R2 credentials for the store's object data, an Object Read
      # & Write token on bucket sciexp, delivered as an EnvironmentFile in
      # GreptimeDB's GREPTIMEDB_STANDALONE__ layered-config form.
      clan.core.vars.generators.greptimedb-r2 = {
        prompts.access-key = {
          description = ''
            Cloudflare R2 S3 access key ID with Object Read & Write scope on
            bucket sciexp, for GreptimeDB. Minted in the Cloudflare dashboard;
            distinct from the omnigraph-r2 and niks3-s3 tokens.
          '';
          type = "hidden";
          persist = true;
          display = {
            group = "greptimedb";
            label = "GREPTIMEDB_STANDALONE__STORAGE__ACCESS_KEY_ID";
          };
        };

        prompts.secret-key = {
          description = "Cloudflare R2 S3 secret access key paired with the access key ID above.";
          type = "hidden";
          persist = true;
          display = {
            group = "greptimedb";
            label = "GREPTIMEDB_STANDALONE__STORAGE__SECRET_ACCESS_KEY";
          };
        };

        files.access-key.deploy = false;
        files.secret-key.deploy = false;

        files."env" = {
          restartUnits = [ "greptimedb.service" ];
        };

        script = ''
          {
            printf 'GREPTIMEDB_STANDALONE__STORAGE__ACCESS_KEY_ID=%s\n' "$(cat "$prompts/access-key")"
            printf 'GREPTIMEDB_STANDALONE__STORAGE__SECRET_ACCESS_KEY=%s\n' "$(cat "$prompts/secret-key")"
          } > "$out/env"
        '';
      };

      # Telemetry store (design D3 to D7). WAL and caches live on
      # zroot/root/greptimedb; SSTs go to R2 under one prefix of sciexp, at the
      # endpoint omnigraph already uses. Credentials arrive by path only.
      services.greptimedb = {
        enable = true;
        # One source with the collector's routing (review F4).
        inherit (collectorSchema) databases;
        settings.storage = {
          type = "S3";
          bucket = "sciexp";
          root = "projects/vanixiets/observability/store/";
          endpoint = config.services.omnigraph.s3.endpointUrl;
          region = "auto";
          enable_virtual_host_style = false;
          disable_ec2_metadata = true;
          # ADR-007: the object-store read cache is capped at 4 GiB.
          cache_capacity = "4GiB";
        };
      };

      systemd.services.greptimedb.serviceConfig = {
        LoadCredential = [
          "users:${config.clan.core.vars.generators.greptimedb-users.files.users.path}"
        ];
        EnvironmentFile = config.clan.core.vars.generators.greptimedb-r2.files."env".path;
      };

      systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [
        "admin-password:${config.clan.core.vars.generators.greptimedb-users.files.admin-password.path}"
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
          usersFiles = config.clan.core.vars.generators.greptimedb-users.files;
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

      # The regulator credential and the host facts greptimedb-envelope checks.
      # Quota and reservation come from greptimedbDataset, the binding the
      # zfs-set-root-greptimedb-{quota,reservation} oneshots apply, so R7.3
      # compares the dataset against the value this host declares.
      systemd.services.greptimedb-envelope = {
        serviceConfig.LoadCredential = [
          "regulator-password:${config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path}"
        ];
        environment =
          let
            gibibytes =
              size:
              let
                m = builtins.match "([0-9]+)G" size;
              in
              assert lib.assertMsg (
                m != null
              ) "greptimedbDataset sizes must be whole gibibytes (\"<n>G\"), got ${size}";
              toString (lib.toInt (builtins.head m) * 1024 * 1024 * 1024);
          in
          {
            GREPTIMEDB_ENVELOPE_DATASET = greptimedbDataset.name;
            GREPTIMEDB_ENVELOPE_QUOTA_BYTES = gibibytes greptimedbDataset.quota;
            GREPTIMEDB_ENVELOPE_RESERVATION_BYTES = gibibytes greptimedbDataset.reservation;
            GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE = "${config.clan.core.vars.generators.greptimedb-users.files.users-sha256.path
            }";
          };
      };

      # devloop-reconcile's store credential, the third regulator-password
      # holder (S2 design D11); devloop-collection.nix stays free of clan vars.
      systemd.services.devloop-reconcile.serviceConfig.LoadCredential = [
        "regulator-password:${config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path}"
      ];

      # Fleet alert evaluator (ADR-009; design D3, D12): queries `fleet` as
      # the regulator account and posts to fleet-alerts with the shared
      # alerter token, which the failure notifier's template and resolve
      # hooks use too. magnetite holds only the token side of ntfy-alerter;
      # cinnabar holds the server's ntfy-alerter-env.
      services.fleet-alert.evaluator = {
        enable = true;
        tokenFile = config.clan.core.vars.generators.ntfy-alerter.files.token.path;
        regulatorPasswordFile =
          config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path;
      };

      # nixbot's `8 x 4096` nix-eval-jobs configuration peaks at 31.4 GiB of
      # swap (logs/magnetite-zram-headroom-experiment.md §6.2), above the
      # 30.6 GiB a single zram0 at the fleet default of 100 % provides, and an
      # eval that exhausts swap is OOM-killed into a permanent PR failure.
      # 150 % is 45.9 GiB; holding that peak costs ~6.9 GiB of real RAM at the
      # measured 4.55x. Machine-scoped, not fleet-wide: pyrite is a 15 GiB
      # laptop that livelocked under zram pressure. mkForce because base sets
      # the percentage as a plain value (modules/system/zram-swap.nix).
      zramSwap.memoryPercent = lib.mkForce 150;

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
      services.memoryPressureGuards.enable = true;

      # Permit binding magnetite's ZeroTier-assigned IPv6 before zerotierone
      # settles on cold boot (mirrors modules/machines/nixos/cinnabar/caddy.nix).
      boot.kernel.sysctl."net.ipv6.ip_nonlocal_bind" = 1;

      # srvos hardware-hetzner-cloud sets useNetworkd=true and useDHCP=false; configure primary interface explicitly.
      systemd.network.networks."10-uplink" = {
        matchConfig.Name = "en*";
        networkConfig = {
          DHCP = "yes";
          IPv6AcceptRA = true;
        };
        dhcpV4Config.UseDNS = true;
        dhcpV6Config.UseDNS = true;
      };

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

      # Increase MaxAuthTries to accommodate agent forwarding with many keys
      # Default is 6, but Bitwarden SSH agent may have 10+ keys loaded
      services.openssh.settings.MaxAuthTries = 20;

      # nix-fast-build --remote opens one ssh connection per build, so a client
      # with N cores offers up to N concurrent pre-auth connections. sshd's
      # default MaxStartups of 10:30:100 starts dropping past ten, and a dropped
      # handshake surfaces as `kex_exchange_identification: Connection reset by
      # peer` and an exit status of 255 attributed to whichever build owned the
      # connection -- a red check naming a package that is not at fault. An
      # 18-core client reliably lost a random handful of checks per run this way.
      services.openssh.settings.MaxStartups = "64:30:256";

      # Bridge NixOS-level sops to home-manager for user secret key delivery.
      # sopsIdentity defaults to flake.users.cameron.meta.sopsAgeKeyId
      # ("crs58" via alias-fold inheritance).
      hm-sops-bridge.users.cameron = { };

      # cameron is an alias for crs58; alias-keyed reads keep this
      # call site ignorant of the alias->target relationship.
      # Infrastructure settings provided by the cameron inventory service.
      home-manager.users.cameron = {
        imports = flakeUsers.cameron.modules;
      };
    };
}
