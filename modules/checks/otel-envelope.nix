# checks.x86_64-linux.otel-envelope: the clauses of flake.lib.otelEnvelope
# (ADR-003 R3.2; S4 design D7) over recorded collector telemetry.
#
# otel-envelope/stub.py serves one fixture from otel-envelope/fixtures/ as
# the collector's telemetry endpoint, and /ok and /slow as a scrape target;
# a stopped stub stands for a stopped collector or exporter. The metric and
# label names are the collector's at 0.155.0, read live on magnetite on
# 2026-10-29: otelcol_exporter_queue_size and _capacity each carry
# `exporter` and `data_type`, the counters have no `_total` suffix, and the
# memory receiver is host_metrics/memory. A case is a sequence of runs
# against one fresh state directory, each with the exit code it must have;
# the check prints `ok: <case>` for each. Each mutant is the script, or
# modules/lib/otel-envelope.nix for a `source` mutant, with one line marked
# `# mutant: <name>` replaced, built for every variant; it runs its named
# case alone, which must fail, printed as `mutant <name> rejected: <case>`.
# budgetOnlyHourly holds the hourly clauses to the minute and to `budget`:
# with a store that does not answer, a run at minute 05 is judged by C1 to
# C4 alone, as is one at minute 00 without `budget`, and one at minute 00
# with it fails B1.
# vmTests.x86_64-linux.fleet-ingress runs the unit itself on a real store,
# and the budget's clauses there.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      telemetryPort = 18888;
      targetPort = 19100;
      # Nothing listens here, so a target there is down.
      secondTargetPort = 19101;
      # Nothing listens here, so every budget query fails.
      closedStorePort = 14000;
      target = path: [
        {
          job = "node";
          url = "http://127.0.0.1:${toString targetPort}${path}";
        }
      ];
      envelope =
        args:
        self.lib.otelEnvelope pkgs (
          {
            hostName = "electrum";
            telemetryUrl = "http://127.0.0.1:${toString telemetryPort}/metrics";
            targets = [ ];
            # The agent fixtures' exporters.
            exporters = [
              "otlp_http/ingress"
              "otlp_http/ingress-logs"
            ];
          }
          // args
        );
      # Receivers with one job of two targets, the second down.
      twoTargets.prometheus.config.scrape_configs = [
        {
          job_name = "node";
          metrics_path = "/ok";
          static_configs = [
            {
              targets = [
                "127.0.0.1:${toString targetPort}"
                "127.0.0.1:${toString secondTargetPort}"
              ];
            }
          ];
        }
      ];
      # The script as each case runs it, with receivers' targets rendered by
      # targetsOf.
      variantsWith = targetsOf: {
        agent = envelope { };
        agentOk = envelope { targets = target "/ok"; };
        agentSlow = envelope { targets = target "/slow"; };
        agentTwoTargets = envelope { targets = targetsOf twoTargets; };
        ingress = envelope {
          hostName = "magnetite";
          ingress = true;
          exporters = [ "otlp_http/fleet" ];
        };
        budget = envelope {
          budget = {
            storeUrl = "http://127.0.0.1:${toString closedStorePort}";
            notifiedUnits = { };
            databases.fleet = "30d";
          };
        };
      };
      variants = variantsWith self.lib.otelEnvelopeTargets;
      variantsDir =
        name: scripts:
        pkgs.runCommand name { } ''
          mkdir "$out"
          ${lib.concatStrings (lib.mapAttrsToList (v: drv: "ln -s ${drv} \"$out/${v}\"\n") scripts)}
        '';

      # Each mutant replaces the line after its marker; `from` is that line.
      # A `source` mutant marks a line of modules/lib/otel-envelope.nix
      # itself rather than of the script.
      mutants = {
        meshRefusalIsLoss = {
          case = "ingressMeshRefused";
          from = ''if [ "$ingress" = 1 ] && [[ $series == otelcol_receiver_refused_*'receiver="otlp/mesh"'* ]]; then continue; fi'';
          to = ":";
        };
        missingCounterFails = {
          case = "missingSendFailed";
          from = ''{ grep -E "$loss_re" "$tmp/now" || true; } | while read -r series value; do'';
          to = ''grep -E "$loss_re" "$tmp/now" | while read -r series value; do'';
        };
        resetNegative = {
          case = "resetThenFailure";
          from = ''inc=$(awk -v n="$value" -v p="$was" 'BEGIN { print (n < p) ? n : n - p }')'';
          to = ''inc=$(awk -v n="$value" -v p="$was" 'BEGIN { print n - p }')'';
        };
        targetDownOneRun = {
          case = "targetDownOnce";
          from = ''if [ "$(prev "down:$job")" = 1 ]; then down="$down $job"; fi'';
          to = ''down="$down $job"'';
        };
        noCarryForward = {
          case = "missThenSame";
          from = ''{ grep -E '^otelcol_' "$state" 2> /dev/null || true; } >> "$next"'';
          to = ":";
        };
        queueSeriesOptional = {
          case = "queueSizeAbsent";
          from = ''n = NR ? split(exporters, configured, " ") : 0'';
          to = "n = 0";
        };
        firstTargetOnly = {
          case = "secondTargetDown";
          source = true;
          from = "hostPorts = lib.concatMap (c: c.targets) job.static_configs;";
          to = "hostPorts = [ (builtins.head (builtins.head job.static_configs).targets) ];";
        };
      };
      mutate = name: m: if m.source or false then mutateSource name m else mutateScript name m;
      mutateScript =
        name: m:
        lib.mapAttrs (
          v: drv:
          pkgs.runCommand "otel-envelope-${name}-${v}" { } ''
            script=${lib.getExe drv}
            # The marked line is the one replaced.
            awk -v marker=${lib.escapeShellArg "# mutant: ${name}"} -v line=${lib.escapeShellArg m.from} '
              found { if (index($0, line)) ok = 1; exit }
              index($0, marker) { found = 1 }
              END { exit !ok }' "$script" || { echo "mutant ${name}: the line after its marker is not the one replaced" >&2; exit 1; }
            mkdir -p "$out/bin"
            cp "$script" "$out/bin/otel-envelope"
            chmod +w "$out/bin/otel-envelope"
            substituteInPlace "$out/bin/otel-envelope" --replace-fail ${lib.escapeShellArg m.from} ${lib.escapeShellArg m.to}
          ''
        ) variants;
      # The library file with the marked line replaced, imported as the
      # flake-parts module it is, renders every variant's targets.
      mutateSource =
        name: m:
        let
          source = builtins.readFile ../lib/otel-envelope.nix;
          parts = builtins.split "# mutant: ${name}\n" source;
          marked =
            builtins.length parts == 3
            && lib.hasInfix m.from (builtins.head (lib.splitString "\n" (builtins.elemAt parts 2)));
          mutated =
            import
              (builtins.toFile "otel-envelope-${name}.nix" (builtins.replaceStrings [ m.from ] [ m.to ] source))
              {
                inherit lib;
                config.flake.lib = self.lib;
              };
        in
        assert lib.assertMsg marked "mutant ${name}: the line after its marker is not the one replaced";
        variantsWith mutated.flake.lib.otelEnvelopeTargets;

      # cases VARIANTS CASE...: runs each case with the scripts under
      # VARIANTS, printing `$RESULT_PREFIX<ok|FAIL>: <case>` and appending
      # each failed case to $FAILED_CASES.
      cases = pkgs.writeShellScript "otel-envelope-cases" ''
        set -euo pipefail
        variants=$1
        shift
        fixtures=${./otel-envelope/fixtures}
        work=$(mktemp -d)
        export STUB_FIXTURE="$work/current.prom"
        pids=()
        current=
        elapsed=0

        start_stub() {
          STUB_PORT=$1 python3 ${./otel-envelope/stub.py} &
          pids+=("$!")
          for _ in $(seq 100); do
            curl -s -o /dev/null "http://127.0.0.1:$1/ok" && return 0
            sleep 0.1
          done
          echo "stub on $1 did not start" >&2
          return 1
        }
        stop_stubs() {
          for pid in "''${pids[@]}"; do
            kill "$pid" 2> /dev/null || true
            wait "$pid" 2> /dev/null || true
          done
          pids=()
        }
        trap stop_stubs EXIT

        # run VARIANT STATE FIXTURE|down up|down EXIT: one run; the
        # telemetry stub serves FIXTURE (none if `down`), the target stub
        # runs if `up`.
        run() {
          local variant=$1 state=$2 fixture=$3 tgt=$4 want=$5 got=0 start
          if [ "$fixture" != down ]; then
            install -m 0644 "$fixtures/$fixture.prom" "$STUB_FIXTURE" || return 1
            start_stub ${toString telemetryPort} || return 1
          fi
          if [ "$tgt" = up ]; then start_stub ${toString targetPort} || return 1; fi
          start=$(date +%s)
          STATE_DIRECTORY=$state "$variants/$variant/bin/otel-envelope" > "$work/out" 2>&1 || got=$?
          elapsed=$(($(date +%s) - start))
          stop_stubs
          sed "s/^/    $current: /" "$work/out"
          if [ "$got" != "$want" ]; then
            echo "    $current: $fixture, target $tgt: exit $got, expected $want"
            return 1
          fi
        }

        case_healthy() {
          local s
          s=$(mktemp -d)
          run agentOk "$s" agent-healthy up 0 && run agentOk "$s" agent-healthy up 0
        }
        case_missingSendFailed() {
          local s
          s=$(mktemp -d)
          run agent "$s" agent-healthy down 0 && run agent "$s" agent-healthy down 0
        }
        case_noTelemetry() {
          local s
          s=$(mktemp -d)
          run agent "$s" down down 0 && run agent "$s" down down 1 && grep -q '^otel-envelope: C1 telemetry: FAIL' "$work/out"
        }
        case_queueFull() {
          local s
          s=$(mktemp -d)
          run agent "$s" agent-healthy down 0 && run agent "$s" agent-full down 1 && grep -q '^otel-envelope: C3 queue: FAIL' "$work/out"
        }
        # A configured exporter whose queue size series is absent, as after
        # a release renaming it.
        case_queueSizeAbsent() {
          run agent "$(mktemp -d)" agent-no-logs-queue-size down 1 \
            && grep -q '^otel-envelope: C3 queue: FAIL otlp_http/ingress-logs otelcol_exporter_queue_size absent' "$work/out"
        }
        case_agentEnqueueFailed() {
          local s
          s=$(mktemp -d)
          run agent "$s" agent-enqueue-1 down 0 && run agent "$s" agent-enqueue-2 down 1 \
            && grep -q '^otel-envelope: C4 loss: FAIL .*enqueue_failed' "$work/out"
        }
        case_ingressEnqueueFailed() {
          local s
          s=$(mktemp -d)
          run ingress "$s" ingress-enqueue-1 down 0 && run ingress "$s" ingress-enqueue-2 down 0
        }
        case_ingressMeshRefused() {
          local s
          s=$(mktemp -d)
          run ingress "$s" ingress-mesh-refused-1 down 0 && run ingress "$s" ingress-mesh-refused-2 down 0
        }
        case_ingressOwnRefused() {
          local s
          s=$(mktemp -d)
          run ingress "$s" ingress-memory-refused-1 down 0 && run ingress "$s" ingress-memory-refused-2 down 1 \
            && grep -q '^otel-envelope: C4 loss: FAIL .*host_metrics/memory' "$work/out"
        }
        case_resetAfterRecorded() {
          local s
          s=$(mktemp -d)
          run agent "$s" agent-sendfail-0 down 0 && run agent "$s" agent-sendfail-reset down 0
        }
        # A restart between two runs with new failures, fewer than recorded.
        case_resetThenFailure() {
          local s
          s=$(mktemp -d)
          run agent "$s" agent-sendfail-0 down 0 && run agent "$s" agent-sendfail-reset-fail down 1 \
            && grep -q '^otel-envelope: C4 loss: FAIL .*send_failed.* +3' "$work/out"
        }
        case_targetDownOnce() {
          local s
          s=$(mktemp -d)
          run agentOk "$s" agent-healthy up 0 && run agentOk "$s" agent-healthy down 0
        }
        case_targetDownTwice() {
          local s
          s=$(mktemp -d)
          run agentOk "$s" agent-healthy down 0 && run agentOk "$s" agent-healthy down 1 \
            && grep -q '^otel-envelope: C2 targets: FAIL node' "$work/out"
        }
        case_secondTargetDown() {
          local s
          s=$(mktemp -d)
          run agentTwoTargets "$s" agent-healthy up 0 && run agentTwoTargets "$s" agent-healthy up 1 \
            && grep -q '^otel-envelope: C2 targets: FAIL node@127.0.0.1:${toString secondTargetPort} down' "$work/out"
        }
        case_missThenSame() {
          local s
          s=$(mktemp -d)
          run agent "$s" agent-sendfail-0 down 0 && run agent "$s" down down 0 && run agent "$s" agent-sendfail-0 down 0
        }
        # A target answering after 15 s: each run ends within the unit's
        # 4 min, fails on C2 only, and the state does not grow.
        case_longRun() {
          local s n want lines first=
          s=$(mktemp -d)
          for n in 1 2 3; do
            want=1
            [ "$n" != 1 ] || want=0
            run agentSlow "$s" agent-sendfail-0 up "$want" || return 1
            if [ "$elapsed" -ge 240 ]; then
              echo "    $current: run $n took ''${elapsed}s"
              return 1
            fi
            [ "$n" != 1 ] || continue
            if [ "$(grep -c ': FAIL' "$work/out")" != 1 ] || ! grep -q '^otel-envelope: C2 targets: FAIL' "$work/out"; then
              echo "    $current: run $n failed on more than C2"
              return 1
            fi
            lines=$(wc -l < "$s/state")
            if [ -n "$first" ] && [ "$lines" != "$first" ]; then
              echo "    $current: the state grew from $first to $lines lines"
              return 1
            fi
            first=$lines
          done
          return 0
        }
        case_budgetOnlyHourly() {
          local s
          s=$(mktemp -d)
          local -x CREDENTIALS_DIRECTORY
          CREDENTIALS_DIRECTORY=$(mktemp -d)
          printf placeholder > "$CREDENTIALS_DIRECTORY/regulator-password"
          local -x OTEL_ENVELOPE_FORCE_HOURLY=0 OTEL_ENVELOPE_MINUTE=05
          run budget "$s" agent-healthy down 0 || return 1
          if grep -q '^otel-envelope: B' "$work/out"; then
            echo "    $current: minute 05 ran the budget clauses"
            return 1
          fi
          OTEL_ENVELOPE_MINUTE=00
          run agent "$(mktemp -d)" agent-healthy down 0 || return 1
          if grep -q '^otel-envelope: B' "$work/out"; then
            echo "    $current: minute 00 without budget ran the budget clauses"
            return 1
          fi
          run budget "$s" agent-healthy down 1 && grep -q '^otel-envelope: B1 active-series: FAIL' "$work/out"
        }

        for c in "$@"; do
          current=$c
          if "case_$c"; then
            echo "''${RESULT_PREFIX:-}ok: $c"
          else
            echo "''${RESULT_PREFIX:-}FAIL: $c"
            echo "$c" >> "$FAILED_CASES"
          fi
        done
      '';

      caseNames = [
        "healthy"
        "missingSendFailed"
        "noTelemetry"
        "queueFull"
        "queueSizeAbsent"
        "agentEnqueueFailed"
        "ingressEnqueueFailed"
        "ingressMeshRefused"
        "ingressOwnRefused"
        "resetAfterRecorded"
        "resetThenFailure"
        "targetDownOnce"
        "targetDownTwice"
        "secondTargetDown"
        "missThenSame"
        "longRun"
        "budgetOnlyHourly"
      ];
      allCases = lib.concatStringsSep " " caseNames;
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        otel-envelope =
          pkgs.runCommand "otel-envelope"
            {
              nativeBuildInputs = [
                pkgs.curl
                pkgs.python3
              ];
              passthru = { inherit variants; };
            }
            ''
              set -euo pipefail
              export FAILED_CASES=$PWD/failed
              : > "$FAILED_CASES"
              ${cases} ${variantsDir "otel-envelope-variants" variants} ${allCases}
              if [ -s "$FAILED_CASES" ]; then
                echo "FAIL: cases failed: $(tr '\n' ' ' < "$FAILED_CASES")" >&2
                exit 1
              fi
              ${lib.concatStrings (
                lib.mapAttrsToList (name: m: ''
                  : > "$FAILED_CASES"
                  RESULT_PREFIX="  under ${name}: " ${cases} ${variantsDir "otel-envelope-${name}" (mutate name m)} ${m.case} > ${name}.log
                  if grep -qx ${m.case} "$FAILED_CASES"; then
                    echo "mutant ${name} rejected: ${m.case}"
                  else
                    cat ${name}.log
                    echo "FAIL: mutant ${name} passed ${m.case}" >&2
                    exit 1
                  fi
                '') mutants
              )}
              touch "$out"
            '';
      };
    };
}
