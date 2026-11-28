# The account's R2 usage in the fleet store (openspec change
# track-r2-usage, design D1-D9).
#
# Where vanixiets.r2Usage.enable is set, on flake.lib.r2Usage.host alone:
# - r2-usage.service, hourly at :07 UTC, asks Cloudflare's GraphQL Analytics
#   API for every bucket's latest storage sample and the operations since
#   the billing period began, by bucket and action type, and writes
#   ./r2-usage/poller.py's series to a record under /var/lib/r2-usage (D2,
#   D3). It reads its token as a systemd credential from the
#   `vanixiets.secrets` entry cloudflare-analytics (prompted, hidden), an Account Analytics
#   Read token, and no other unit names it (D5).
# - r2-usage-publish.service copies the record every minute into the host's
#   one textfile directory (./node-exporter-textfile.nix) as r2-usage.prom,
#   so the file stays fresh for HostProbeStale between hourly polls, and
#   seeds the record with only its last-success time when none exists, so a
#   poller that never succeeds ages too. fleet-alert's R2UsageStale fires
#   2 h after the last successful poll (D7).
#
# The series reach the store through node_exporter and the collector's
# keep-list (flake.lib.otelCollectorSchema.nodeExporterKeep), the path every
# textfile probe takes; no receiver or exporter is added (D2).
#
# The option is off by default: declaring the generator makes `clan machines
# update` prompt for the token before a deploy. The host turns it on in the
# commit that adds its generated vars, removes itself from
# flake.lib.r2Usage.awaitingSecrets and adds r2-usage to its notifiedUnits
# (D6, as back-up-postgresql-off-host D16). flake.lib.r2UsageObligations,
# asserted on every machine check by modules/checks/machines.nix, fails the
# poller host when it neither polls nor awaits its secrets, any other host
# that polls, and an enabled poller without its vars in the repository, not
# notified on failure, or whose token another unit loads;
# checks.x86_64-linux.r2-usage judges the judge over literal fixtures, and
# runs the poller's formatting against a recorded response.
#
# Imported by the host that enables it (machines/nixos/magnetite); the judge
# reads every other host's vanixiets.r2Usage.enable with `or false`.
{ config, lib, ... }:
let
  schema = config.flake.lib.otelCollectorSchema;
  inherit (config.flake.lib) vars;
  inherit (config.flake.lib.nodeExporterTextfile) flag;

  host = "magnetite";
  unit = "r2-usage";
  publishUnit = "r2-usage-publish";
  writer = "r2-usage";
  generator = "cloudflare-analytics";
  stateDirectory = "r2-usage";
  # Hosts whose cloudflare-analytics token the operator has not yet entered;
  # such a host runs with the poller off and the obligation accepts it.
  awaitingSecrets = [ ];

  seriesNames = [
    "vanixiets_r2_bucket_payload_bytes"
    "vanixiets_r2_bucket_metadata_bytes"
    "vanixiets_r2_bucket_objects"
    "vanixiets_r2_bucket_pending_uploads"
    "vanixiets_r2_operations"
    "vanixiets_r2_billing_period_start_timestamp_seconds"
    "vanixiets_r2_billing_period_end_timestamp_seconds"
    "vanixiets_r2_last_success_timestamp_seconds"
  ];

  # Cloudflare's R2 pricing page (cloudflare-docs src/content/docs/r2/
  # pricing.mdx), Standard storage, as read on 2026-11-20. Usage is rounded
  # up to the next billing unit: 1,000,001 operations bill as two million,
  # 1.1 GB-month as 2 (D4).
  pricing = {
    storagePerGBMonth = 0.015;
    classAPerMillion = 4.5;
    classBPerMillion = 0.36;
  };
  freeTier = {
    storageGBMonth = 10;
    classA = 1000000;
    classB = 10000000;
  };
  classes = {
    A = [
      "ListBuckets"
      "PutBucket"
      "ListObjects"
      "PutObject"
      "CopyObject"
      "CompleteMultipartUpload"
      "CreateMultipartUpload"
      "LifecycleStorageTierTransition"
      "ListMultipartUploads"
      "UploadPart"
      "UploadPartCopy"
      "ListParts"
      "PutBucketEncryption"
      "PutBucketCors"
      "PutBucketLifecycleConfiguration"
    ];
    B = [
      "HeadBucket"
      "HeadObject"
      "GetObject"
      "UsageSummary"
      "GetBucketEncryption"
      "GetBucketLocation"
      "GetBucketCors"
      "GetBucketLifecycleConfiguration"
    ];
    free = [
      "DeleteObject"
      "DeleteBucket"
      "AbortMultipartUpload"
    ];
    # Seen in the live operations of 2026-10-23 to 2026-11-20 and named
    # nowhere in pricing.mdx (nor elsewhere in the R2 docs), so counted as
    # `unclassified`:
    # - DeleteObjects (multi-object delete): 55,752 on sciexp, 611 on
    #   sciexp-nix-cache. The dashboard's 1.22M Class A and 1.58M Class B
    #   for the period match our A and B without them, so Cloudflare does
    #   not appear to bill them, but no page says so.
    # - GetBucketNotificationConfiguration: 2 on sciexp-nix-cache.
    # - GetBucketSippyConfiguration: 3 on sciexp-nix-cache.
  };

  # The storage the account may hold before R2CostProjected warns, in
  # GB-month for a billing period (operator decision, 2026-11-20). Set
  # against the operator's dashboard for Oct 23 - Nov 23 2026: 257.39 GB
  # stored, 1.22M Class A and 1.58M Class B operations, $7.76 billable, of
  # which $3.26 storage and $4.50 Class A (the 0.22M over the free tier,
  # rounded up to one million). Storage above the free tier costs linearly,
  # so this budget, not the free tier, is the edge worth a notice.
  storageBudgetGBMonth = 300;

  # The billing period begins on this day of the month at 00:00 UTC: the
  # operator's dashboard shows Oct 23 - Nov 23, and the free tier and the
  # rounding apply per billing period, not per calendar month (D3).
  billingAnchorDay = 23;

  accountTag = "1ece4a9a8f092f8cbdd679d22b9ecb1f";

  # A bucket whose latest storage sample is older than this is gone. On
  # 2026-11-18 to 2026-11-20 Cloudflare sampled every bucket every 10 to 60
  # minutes, the empty omicsberg hourly, the busiest every 10; two hours is
  # twice the longest gap seen. R2BucketUndeclared's `for` exceeds this
  # plus the hourly poll, so a deleted bucket never fires it.
  storageFreshSeconds = 7200;

  pollerConfig = {
    inherit
      accountTag
      billingAnchorDay
      classes
      storageFreshSeconds
      ;
    endpoint = "https://api.cloudflare.com/client/v4/graphql";
  };

  # The R2 buckets terranix declares, read from modules/terranix/cloudflare.nix
  # itself: its bucket resources are literals, so applying the module to
  # placeholder arguments evaluates no provider data (D8). The file, not
  # flake.modules.terranix.cloudflare, whose value flake-parts wraps.
  declaredBuckets = lib.sort lib.lessThan (
    lib.mapAttrsToList (_: r: r.name)
      ((import ../terranix/cloudflare.nix).flake.modules.terranix.cloudflare {
        config = throw "r2Usage.declaredBuckets: a bucket's name must be a literal";
        pkgs = throw "r2Usage.declaredBuckets: a bucket's name must be a literal";
        inherit lib;
      }).resource.cloudflare_r2_bucket
  );

  # Buckets in the account that terranix deliberately does not manage, by
  # name, each with its owner and why, e.g.
  #   some-bucket = "owned by <project>'s own state; not managed here";
  # (F87). R2BucketUndeclared fires on a bucket in neither list, and on a
  # bucket listed here that holds an object or a byte, so an entry made for
  # an empty bucket cannot go stale silently. Empty: on 2026-11-20 the
  # account held only the three buckets terranix declares, after the
  # operator deleted the empty, unmanaged omicsberg.
  externalBuckets = { };

  # The cost of the billing period so far at R2's prices, each class rounded
  # up to whole millions beyond its free tier as Cloudflare bills it, and
  # storage held at today's level for the whole period (D4). The dashboard's
  # cost panel carries these strings; checks.x86_64-linux.r2-usage compares.
  num = builtins.toJSON;
  costQueries = rec {
    classA = ''${num pricing.classAPerMillion} * ceil(clamp_min(sum(vanixiets_r2_operations{class="A"}) - ${num freeTier.classA}, 0) / 1000000)'';
    classB = ''${num pricing.classBPerMillion} * ceil(clamp_min(sum(vanixiets_r2_operations{class="B"}) - ${num freeTier.classB}, 0) / 1000000)'';
    storage = "${num pricing.storagePerGBMonth} * ceil(clamp_min(sum(vanixiets_r2_bucket_payload_bytes + vanixiets_r2_bucket_metadata_bytes) / 1000000000 - ${num freeTier.storageGBMonth}, 0))";
    total = "(${classA}) + (${classB}) + (${storage})";
  };

  poller =
    pkgs:
    pkgs.writers.writePython3Bin "r2-usage-poller" {
      flakeIgnore = [ "E501" ];
    } (builtins.readFile ./r2-usage/poller.py);

  # The pure judge (design D6). `facts`:
  #   isHost           the host is flake.lib.r2Usage.host
  #   enable           vanixiets.r2Usage.enable
  #   awaiting         the host is in awaitingSecrets
  #   secretsGenerated the generator's deployed token is in the repository
  #   notifiedUnits    the host's row in flake.lib.observabilityHosts
  #   tokenOwner       the deployed token file's owner
  #   tokenConsumers   the units whose LoadCredential or EnvironmentFile
  #                    names the token file
  problems =
    {
      isHost,
      enable,
      awaiting,
      secretsGenerated,
      notifiedUnits,
      tokenOwner,
      tokenConsumers,
    }:
    if !enable then
      lib.optional (
        isHost && !awaiting
      ) "the R2 usage poller is off, and the host is not in flake.lib.r2Usage.awaitingSecrets"
    else
      lib.optional (!isHost)
        "vanixiets.r2Usage.enable is set on a host other than ${host}; two pollers would write every series twice"
      ++ lib.optional awaiting "vanixiets.r2Usage.enable is set but the host is still in flake.lib.r2Usage.awaitingSecrets"
      ++
        lib.optional (!secretsGenerated)
          "vanixiets.r2Usage.enable is set but the ${generator} vars are not in the repository; run `clan vars generate` for it first"
      ++ lib.optional (!lib.elem unit notifiedUnits) "${unit} is not in the host's notifiedUnits"
      ++
        lib.optional (tokenOwner != "root")
          "the ${generator} token is owned by ${tokenOwner}, not root; only ${unit}.service may read it, as a credential"
      ++ lib.optional (
        tokenConsumers != [ unit ]
      ) "the ${generator} token is loaded by ${builtins.toJSON tokenConsumers}, not by ${unit} alone";

  factsOf =
    name: hostConfig:
    let
      secret = hostConfig.vanixiets.secrets.${generator} or null;
      # Without the secret backend the entry has no path and no resolved
      # owner, which reads as no token, as before the seam.
      token = if secret == null || secret.resolved == null then null else secret.files.token or null;
      names = v: toString (lib.toList v);
      loads =
        s:
        token != null
        && lib.hasInfix token.path (
          names (s.serviceConfig.LoadCredential or [ ]) + " " + names (s.serviceConfig.EnvironmentFile or [ ])
        );
    in
    {
      isHost = name == host;
      enable = hostConfig.vanixiets.r2Usage.enable or false;
      awaiting = lib.elem name awaitingSecrets;
      secretsGenerated = vars.exists {
        machine = name;
        inherit generator;
        file = "token";
      };
      notifiedUnits = config.flake.lib.observabilityHosts.${name}.notifiedUnits or [ ];
      tokenOwner = if token == null then "root" else secret.resolved.files.token.owner;
      tokenConsumers = lib.attrNames (lib.filterAttrs (_: loads) hostConfig.systemd.services);
    };

  module =
    {
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.vanixiets.r2Usage;
      node = config.services.prometheus.exporters.node;
      directory = config.vanixiets.nodeExporter.textfileDirectory;
      record = "/var/lib/${stateDirectory}/r2-usage.prom";
      published = "${directory}/${writer}.prom";
      configFile = pkgs.writeText "r2-usage.json" (builtins.toJSON pollerConfig);
      seriesName = "vanixiets_r2_last_success_timestamp_seconds";

      # Seeds a missing record with its last-success time alone, then
      # copies it into the textfile directory by write-then-rename.
      publish = pkgs.writeShellScript "r2-usage-publish" ''
        set -eu
        if [ ! -e ${record} ]; then
          {
            echo "# HELP ${seriesName} Unix time of the last poll whose response gave both datasets."
            echo "# TYPE ${seriesName} gauge"
            echo "${seriesName} $(${pkgs.coreutils}/bin/date +%s)"
          } > ${record}.tmp
          ${pkgs.coreutils}/bin/mv -f ${record}.tmp ${record}
        fi
        ${pkgs.coreutils}/bin/install -m 0644 ${record} ${published}.tmp
        ${pkgs.coreutils}/bin/mv -f ${published}.tmp ${published}
      '';

      hardening = {
        User = node.user;
        Group = node.group;
        StateDirectory = stateDirectory;
        StateDirectoryMode = "0755";
        ReadWritePaths = [ directory ];
        UMask = "0022";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    in
    {
      options.vanixiets.r2Usage.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Poll Cloudflare's GraphQL Analytics API hourly for the account's R2 usage. Set it on ${host} in the commit that adds the generated ${generator} vars.";
      };

      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            assertions = [
              {
                assertion =
                  node.enable
                  && lib.all (n: lib.elem n schema.nodeExporterKeep) seriesNames
                  && lib.elem "${flag}=${directory}" node.extraFlags;
                message = "r2-usage: node_exporter must run its textfile collector on ${directory} and nodeExporterKeep must keep ${lib.concatStringsSep ", " seriesNames}, or the usage never reaches the store.";
              }
            ];

            vanixiets.nodeExporter.textfileWriters = [ writer ];

            systemd.services.${unit} = {
              description = "R2 usage from Cloudflare's GraphQL Analytics API";
              wants = [ "network-online.target" ];
              after = [ "network-online.target" ];
              serviceConfig = hardening // {
                Type = "oneshot";
                ExecStart = "${lib.getExe (poller pkgs)} ${configFile} %d/token ${record}";
                # After observability-notify's resolve hook: the resolve notice is
                # sent first, so a failed publish reaches OnFailure after it.
                ExecStartPost = lib.mkAfter [ "${publish}" ];
                LoadCredential = [ "token:${config.vanixiets.secrets.${generator}.files.token.path}" ];
                MemoryMax = "128M";
              };
            };

            # The timer of a notified unit names its zone
            # (modules/nixos/observability-notify.nix).
            systemd.timers.${unit} = {
              description = "Hourly: R2 usage";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "*-*-* *:07:00 UTC";
                RandomizedDelaySec = "5m";
                Persistent = true;
              };
            };

            systemd.services.${publishUnit} = {
              description = "Seed and publish the R2 usage record";
              wantedBy = [ "multi-user.target" ];
              serviceConfig = hardening // {
                Type = "oneshot";
                ExecStart = "${publish}";
                MemoryMax = "32M";
              };
            };

            systemd.timers.${publishUnit} = {
              description = "Every minute: publish the R2 usage record";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnBootSec = "1min";
                OnUnitActiveSec = "60s";
                AccuracySec = "5s";
              };
            };
          }
          {
            vanixiets.secrets.${generator} = {
              prompts.api-token = {
                description = ''
                  Cloudflare API token with the single permission Account >
                  Account Analytics > Read on account ${accountTag}, for the
                  R2 usage poller on ${host}. Minted in the Cloudflare
                  dashboard (My Profile > API Tokens); used by no other
                  service.
                '';
                type = "hidden";
                persist = true;
                display = {
                  group = "r2-usage";
                  label = "Account Analytics Read token";
                };
              };
              files.api-token.deploy = false;
              files.token = { };
              script = ''
                token=$(cat "$prompts/api-token")
                case "$token" in
                  "" | *[[:space:]]*)
                    echo "cloudflare-analytics: the token is empty or holds whitespace" >&2
                    exit 1
                    ;;
                esac
                printf '%s' "$token" > "$out/token"
              '';
            };
          }
        ]
      );
    };
in
{
  flake.lib.r2Usage = {
    inherit
      host
      unit
      writer
      generator
      awaitingSecrets
      seriesNames
      pricing
      freeTier
      classes
      storageBudgetGBMonth
      billingAnchorDay
      storageFreshSeconds
      pollerConfig
      declaredBuckets
      externalBuckets
      costQueries
      poller
      ;
  };

  flake.lib.r2UsageObligations = {
    inherit problems factsOf;
    failures = name: hostConfig: problems (factsOf name hostConfig);
  };

  fleetObligations.r2UsageObligations.failures = config.flake.lib.r2UsageObligations.failures;

  flake.modules.nixos.r2-usage = module;
}
