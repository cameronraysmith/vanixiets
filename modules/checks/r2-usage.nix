# checks.x86_64-linux.r2-usage (openspec change track-r2-usage, design D9).
#
# - format: the poller (flake.lib.r2Usage.poller) formats
#   ./r2-usage/response.json, a GraphQL Analytics API response written to
#   the r2StorageAdaptiveGroups and r2OperationsAdaptiveGroups schema of
#   cloudflare-docs src/content/docs/r2/platform/metrics-analytics.mdx, the
#   query's shape validated against the live schema on 2026-11-20, at
#   2026-11-20T15:00:00Z into exactly ./r2-usage/expected.prom: each
#   bucket's latest storage sample and not an older one, idle-archive's
#   sampled two hours before, exactly storageFreshSeconds, and kept;
#   deleted-scratch's last sample 2 h 10 min old, so no storage series,
#   and its operations kept with gone="true"; operations summed by pricing
#   class from flake.lib.r2Usage.classes, every action type of the live
#   period of 2026-11-20 among them, with ListBuckets under (account),
#   DeleteObject and DeleteBucket as free, and DeleteObjects,
#   GetBucketNotificationConfiguration and GetBucketSippyConfiguration,
#   which the pricing page does not name, as unclassified; and the billing
#   period Oct 23 - Nov 23.
# - Five mutants must each change a named line of that file:
#   unitConfusion reads the sizes as KiB, classMapping prices ListObjects
#   as class B, bucketDropped keeps only the rows at the newest sample's
#   time, which drops idle-archive, noFreshness widens the bound to the
#   query's whole day, and deleteObjectsFree counts DeleteObjects as free.
# - The judge of flake.lib.r2UsageObligations accepts the polling host, the
#   host awaiting its token, and another host with the poller off; it finds
#   exactly one problem in each mutant: notEnabled, awaitingButEnabled,
#   secretsMissing, unitNotNotified, otherHost, tokenOwned and tokenShared.
# - The R2 usage dashboard's cost panel carries flake.lib.r2Usage.costQueries,
#   so its prices and free tiers are the ones the rules use.
#
# Per-host facts are asserted by modules/checks/machines.nix. The fixtures
# are literals, so the check runs on x86_64-linux only.
{ config, lib, ... }:
let
  r2 = config.flake.lib.r2Usage;
  o = config.flake.lib.r2UsageObligations;
  now = "1795186800";

  accepted = {
    isHost = true;
    enable = true;
    awaiting = false;
    secretsGenerated = true;
    notifiedUnits = [
      "otel-envelope"
      r2.unit
    ];
    tokenOwner = "root";
    tokenConsumers = [ r2.unit ];
  };
  with' = f: accepted // f accepted // { problems = 1; };
  cases = {
    accepted = accepted // {
      problems = 0;
    };
    awaitingSecrets = accepted // {
      enable = false;
      awaiting = true;
      secretsGenerated = false;
      problems = 0;
    };
    otherHostOff = accepted // {
      isHost = false;
      enable = false;
      problems = 0;
    };
    notEnabled = with' (_: {
      enable = false;
    });
    awaitingButEnabled = with' (_: {
      awaiting = true;
    });
    secretsMissing = with' (_: {
      secretsGenerated = false;
    });
    unitNotNotified = with' (a: {
      notifiedUnits = lib.remove r2.unit a.notifiedUnits;
    });
    otherHost = with' (_: {
      isHost = false;
    });
    tokenOwned = with' (_: {
      tokenOwner = "node-exporter";
    });
    tokenShared = with' (a: {
      tokenConsumers = a.tokenConsumers ++ [ "nixbot" ];
    });
  };

  dashboard = lib.importJSON ../nixos/perses/resources/dashboard-r2-usage.json;
  costPanelQueries = map (q: q.spec.plugin.spec.query) dashboard.spec.panels.cost.spec.queries;
  costQueries = with r2.costQueries; [
    classA
    classB
    storage
    total
  ];

  mutateText =
    name: from: to: text:
    assert lib.assertMsg (lib.hasInfix from text)
      "r2-usage check: mutant ${name} found nothing to replace";
    builtins.replaceStrings [ from ] [ to ] text;
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      source = builtins.readFile ../nixos/r2-usage/poller.py;
      pollerOf =
        name: text:
        lib.getExe (
          pkgs.writers.writePython3Bin "r2-usage-poller-${name}" { flakeIgnore = [ "E501" ]; } text
        );
      configOf = name: c: pkgs.writeText "r2-usage-${name}.json" (builtins.toJSON c);

      # Formats the fixture with a poller and a configuration, and compares
      # it with expected.prom; `mutant` names the line the mutant must change.
      format =
        name: poller: configFile: mutant:
        pkgs.runCommand "r2-usage-format-${name}" { nativeBuildInputs = [ pkgs.diffutils ]; } (
          ''
            ${poller} --format ${configFile} ${./r2-usage/response.json} ${now} > got.prom
          ''
          + (
            if mutant == null then
              ''
                diff -u ${./r2-usage/expected.prom} got.prom
              ''
            else
              ''
                if diff -u ${./r2-usage/expected.prom} got.prom > diff.log; then
                  echo "FAIL: the ${name} mutant formats the fixture as expected.prom" >&2
                  exit 1
                fi
                cat diff.log
                grep -qxF ${lib.escapeShellArg "-${mutant}"} diff.log \
                  || { echo "FAIL: the ${name} mutant did not change ${mutant}" >&2; exit 1; }
                echo "mutant ${name} rejected"
              ''
          )
          + ''
            touch $out
          ''
        );

      config' = configOf "accepted" r2.pollerConfig;
      legs = {
        format = format "accepted" (pollerOf "accepted" source) config' null;
        unitConfusion = format "unitConfusion" (pollerOf "unit-confusion" (
          mutateText "unitConfusion" "value = int(latest[bucket][1][field])"
            "value = int(latest[bucket][1][field]) // 1024"
            source
        )) config' ''vanixiets_r2_bucket_payload_bytes{bucket="sciexp"} 88412736512'';
        classMapping = format "classMapping" (pollerOf "accepted" source) (configOf "class-mapping" (
          r2.pollerConfig
          // {
            classes = r2.pollerConfig.classes // {
              A = lib.remove "ListObjects" r2.pollerConfig.classes.A;
              B = r2.pollerConfig.classes.B ++ [ "ListObjects" ];
            };
          }
        )) ''vanixiets_r2_operations{bucket="sciexp",class="A"} 799167'';
        bucketDropped = format "bucketDropped" (pollerOf "bucket-dropped" (
          mutateText "bucketDropped" "if bucket not in latest or moment > latest[bucket][0]:"
            ''if moment == account["storage"][0]["dimensions"]["datetime"]:''
            source
        )) config' ''vanixiets_r2_bucket_payload_bytes{bucket="idle-archive"} 0'';
        noFreshness = format "noFreshness" (pollerOf "no-freshness" (
          mutateText "noFreshness" "<= fresh" "<= fresh * 12" source
        )) config' ''vanixiets_r2_operations{bucket="deleted-scratch",class="A",gone="true"} 6'';
        deleteObjectsFree = format "deleteObjectsFree" (pollerOf "accepted" source) (configOf
          "delete-objects-free"
          (
            r2.pollerConfig
            // {
              classes = r2.pollerConfig.classes // {
                free = r2.pollerConfig.classes.free ++ [ "DeleteObjects" ];
              };
            }
          )
        ) ''vanixiets_r2_operations{bucket="sciexp",class="unclassified"} 55752'';
      };
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        r2-usage = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        r2-usage =
          config.flake.lib.judgeCases
            {
              name = "r2-usage";
              judge = case: o.problems (removeAttrs case [ "problems" ]);
              inherit cases;
              assertions = [
                {
                  assertion = costPanelQueries == costQueries;
                  message = "the dashboard's cost panel queries ${builtins.toJSON costPanelQueries}, not flake.lib.r2Usage.costQueries ${builtins.toJSON costQueries}";
                }
              ];
            }
            (
              pkgs.runCommand "r2-usage"
                {
                  passthru = legs;
                  meta.description = "the R2 usage poller formats a recorded GraphQL response and rejects three mutants; the poller's obligation judge; the dashboard's cost queries";
                }
                ''
                  ${lib.concatMapStrings (leg: "test -e ${leg}\n") (lib.attrValues legs)}
                  touch $out
                ''
            );
      };
    };
}
