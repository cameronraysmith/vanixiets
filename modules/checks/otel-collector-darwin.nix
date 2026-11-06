# checks.x86_64-linux.otel-collector-darwin: the darwin agent's and
# otelcol-process's configurations, rendered by flake.lib.otelCollectorDarwin
# from flake.lib data only, judged by R3.1's darwin clauses (ADR-003:240) and
# validated by the root pin's otelcol-contrib 0.155.0, the version stibnite
# runs: validation reads component configuration, not the platform. Later
# cases run the probe's parser over launchctl and smartctl output recorded
# on stibnite at macOS 26.7.1, and the notifier wrapper over a recording
# ntfy-send. Each clause names its two value sources; each mutant changes
# one input and runs only its own clause or case, printed as
# `mutant <name> rejected: <case>`. Relations within one host are the darwin
# fragment's assertions, not clauses here. Stubbed packages enter as
# `pkgs // { … }`, never pkgs.extend, which re-evaluates nixpkgs (design D13).
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      pki = self.lib.otelTestPki pkgs;
      render =
        args:
        self.lib.otelCollectorDarwin (
          {
            hostName = "stibnite";
            certFile = "${pki}/agent.crt";
            keyFile = "${pki}/agent.key";
            caFile = "${pki}/ca.crt";
          }
          // args
        );

      # A library file with the line after `# mutant: <name>` changed from
      # `from` to `to`, imported as the flake-parts module it is (as
      # modules/checks/otel-envelope.nix does for the envelope).
      mutatedLib =
        file: name: from: to:
        let
          source = builtins.readFile file;
          marker = "# mutant: ${name}\n";
          parts = builtins.split marker source;
          line = builtins.head (lib.splitString "\n" (builtins.elemAt parts 2));
          marked = builtins.length parts == 3 && lib.hasInfix from line;
          mutated =
            builtins.replaceStrings
              [ (marker + line) ]
              [
                (marker + builtins.replaceStrings [ from ] [ to ] line)
              ]
              source;
        in
        assert lib.assertMsg marked "mutant ${name}: the line after its marker does not hold ${from}";
        (import (builtins.toFile "${name}.nix" mutated) {
          inherit lib;
          config.flake.lib = self.lib;
        }).flake.lib;

      input = {
        r = render { };
        # Source A of the exporter clause: the address clan's ZeroTier service
        # assigned to magnetite, not the registry the renderer reads.
        ztAddress = lib.trim (
          builtins.readFile "${self}/vars/shared/zerotier-ip-magnetite-zerotier/ip/value"
        );
        # Compared with their store-path context discarded: lib.hasInfix
        # matches by regular expression, which rejects a string with context.
        credentialPaths = map builtins.unsafeDiscardStringContext [
          "${pki}/agent.crt"
          "${pki}/agent.key"
          "${pki}/ca.crt"
          "/run/secrets"
        ];
        # stibnite's evaluated daemon labels on 2026-11-05 (tasks.md 1.2), the
        # fragment's five, and a decoy that matches only if a dot is unescaped.
        daemonLabels = [
          "org.nixos.activate-system"
          "org.nixos.dnscrypt-pin-dns"
          "org.nixos.dnscrypt-proxy"
          "org.nixos.harmonia-gc"
          "org.nixos.nix-cleanup-gcroots"
          "org.nixos.nix-daemon"
          "org.nixos.nix-grpc-client-identity"
          "org.nixos.nix-grpc-daemon"
          "org.nixos.omnigent-host-cameron"
          "org.nixos.sops-install-secrets"
          "org.nixos.otelcol"
          "org.nixos.otelcol-process"
          "org.nixos.otel-host-probe"
          "org.nixos.otel-envelope"
          "org.nixos.prometheus-node-exporter"
          "orgXnixosXnix-daemon"
        ];
        probeLabels = self.lib.otelHostProbeLabels;
      };

      isLoopback =
        s:
        builtins.match "(https?://)?(127\\.[0-9]+\\.[0-9]+\\.[0-9]+|\\[::1]|localhost)(:[0-9]+)?(/.*)?" s
        != null;

      # Every `endpoint` string anywhere under a component section.
      collectEndpoints =
        value:
        if builtins.isAttrs value then
          lib.concatLists (
            lib.mapAttrsToList (
              name: inner:
              if name == "endpoint" && builtins.isString inner then [ inner ] else collectEndpoints inner
            ) value
          )
        else if builtins.isList value then
          lib.concatMap collectEndpoints value
        else
          [ ];

      # ADR-004:89's six identity attributes, typed here from the decision
      # record, not read from the renderer.
      identity = [
        "process.pid"
        "process.parent_pid"
        "process.command"
        "process.command_line"
        "process.executable.path"
        "process.owner"
      ];

      # Value sources, per clause: nodeTextfileOnLoopback, the renderer's
      # `node` against ADR-003 item 23's flags typed here;
      # processIdentityOff, the rendered scraper against ADR-004:89's list;
      # processNoListenerNoCredential, the rendered otelcol-process
      # configuration against the telemetry level read from the collector's
      # service module v0.155.0 (otelconftelemetry/metrics.go:28-30) and the
      # credential paths this check passes in; strictIncludes, the rendered
      # scrapers against ADR-003 item 21 and ADR-004:100; loopbackButIngress,
      # the rendered endpoints against the loopback pattern and against the
      # address in vars/, where the renderer reads flake.lib.hosts;
      # probeLabelsSelected, flake.lib.otelHostProbeLabels over schema.nix's
      # launchdLabels and the fixture labels, against ADR-004:121's selection.
      clauses = i: {
        nodeTextfileOnLoopback =
          i.r.node.listenAddress == "127.0.0.1"
          && i.r.node.port == 9100
          &&
            i.r.node.extraFlags == [
              "--collector.disable-defaults"
              "--collector.textfile"
              "--collector.textfile.directory=/var/lib/prometheus-node-exporter/textfile"
            ];
        processIdentityOff =
          let
            a = i.r.process.receivers."host_metrics/process".scrapers.process.resource_attributes;
          in
          lib.all (n: (a.${n}.enabled or true) == false) identity
          && lib.all (n: builtins.elem n identity || (a.${n}.enabled or false) == false) (
            builtins.attrNames a
          );
        processNoListenerNoCredential =
          collectEndpoints i.r.process.receivers == [ ]
          && (i.r.process.service.telemetry.metrics.level or null) == "none"
          && !(i.r.process.service.telemetry.metrics ? readers)
          && lib.all (
            p: !(lib.hasInfix p (builtins.unsafeDiscardStringContext (builtins.toJSON i.r.process)))
          ) i.credentialPaths
          && i.r.process.exporters."otlp_http/agent".endpoint == "http://127.0.0.1:4318";
        strictIncludes =
          let
            s = i.r.agent.receivers."host_metrics/memory".scrapers;
          in
          s.disk.include == {
            devices = [ "disk0" ];
            match_type = "strict";
          }
          && s.disk.metrics."system.disk.io_time".enabled == false
          && s.disk.metrics."system.disk.pending_operations".enabled == false
          &&
            s.filesystem.include_mount_points == {
              mount_points = [ "/System/Volumes/Data" ];
              match_type = "strict";
            }
          && !(s ? paging)
          && !(i.r.agent.receivers ? systemd);
        loopbackButIngress =
          lib.all isLoopback (
            collectEndpoints i.r.agent.receivers
            ++ lib.concatMap (
              j: lib.concatMap (c: c.targets) j.static_configs
            ) i.r.agent.receivers.prometheus.config.scrape_configs
            ++ map (r: "${r.pull.exporter.prometheus.host}") i.r.agent.service.telemetry.metrics.readers
          )
          && lib.all (n: i.r.agent.exporters.${n}.endpoint == "https://[${i.ztAddress}]:4318") [
            "otlp_http/ingress"
            "otlp_http/ingress-logs"
          ]
          &&
            builtins.attrNames i.r.agent.exporters == [
              "otlp_http/ingress"
              "otlp_http/ingress-logs"
            ];
        probeLabelsSelected =
          lib.sort lib.lessThan (
            i.probeLabels {
              inherit (self.lib.otelCollectorSchema) launchdLabels;
              inherit (i) daemonLabels;
            }
          ) == lib.sort lib.lessThan [
            "org.nixos.dnscrypt-proxy"
            "org.nixos.harmonia-gc"
            "org.nixos.nix-cleanup-gcroots"
            "org.nixos.nix-daemon"
            "org.nixos.nix-grpc-daemon"
            "org.nixos.omnigent-host-cameron"
            "org.nixos.otelcol"
            "org.nixos.otelcol-process"
            "org.nixos.otel-envelope"
            "org.nixos.prometheus-node-exporter"
            "org.nixos.sops-install-secrets"
          ];
      };

      mutants = {
        nodeListenEmpty = {
          clause = "nodeTextfileOnLoopback";
          apply = i: i // { r = lib.recursiveUpdate i.r { node.listenAddress = ""; }; };
        };
        seventhIdentityAttribute = {
          clause = "processIdentityOff";
          apply =
            i:
            i
            // {
              r = lib.recursiveUpdate i.r {
                process.receivers."host_metrics/process".scrapers.process.resource_attributes."process.cgroup".enabled =
                  true;
              };
            };
        };
        processEndpoint = {
          clause = "processNoListenerNoCredential";
          apply =
            i:
            i
            // {
              r = lib.recursiveUpdate i.r { process.receivers.otlp.protocols.http.endpoint = "127.0.0.1:4319"; };
            };
        };
        diskIncludeAll = {
          clause = "strictIncludes";
          apply =
            i:
            i
            // {
              r = lib.recursiveUpdate i.r {
                agent.receivers."host_metrics/memory".scrapers.disk.include = {
                  devices = [ ".*" ];
                  match_type = "regexp";
                };
              };
            };
        };
        exporterAddressOther = {
          clause = "loopbackButIngress";
          apply = i: i // { ztAddress = "fddb:4344:343b:14b9:399:930f:39db:40d3"; };
        };
        labelDotUnescaped = {
          clause = "probeLabelsSelected";
          apply =
            i:
            i
            // {
              probeLabels =
                (mutatedLib ../lib/otel-collector-darwin.nix "labelDotUnescaped" ''"[.]"'' ''"."'')
                .otelHostProbeLabels;
            };
        };
      };

      held = clauses input;
      failing = builtins.attrNames (lib.filterAttrs (_: v: !v) held);
      unrejected = builtins.attrNames (
        lib.filterAttrs (_: m: (clauses (m.apply input)).${m.clause}) mutants
      );
      clauseReport =
        assert lib.assertMsg (
          failing == [ ]
        ) "otel-collector-darwin: clauses fail: ${builtins.toJSON failing}";
        assert lib.assertMsg (
          unrejected == [ ]
        ) "otel-collector-darwin: mutants not rejected: ${builtins.toJSON unrejected}";
        lib.concatStrings (map (c: "ok: ${c}\n") (builtins.attrNames held))
        + lib.concatStrings (lib.mapAttrsToList (n: m: "mutant ${n} rejected: ${m.clause}\n") mutants);

      yaml = pkgs.formats.yaml { };
      agentYaml = yaml.generate "otelcol-agent.yaml" input.r.agent;
      processYaml = yaml.generate "otelcol-process.yaml" input.r.process;
      # The validation's negative control: an unknown key must be refused.
      badYaml = yaml.generate "otelcol-agent-bad.yaml" (
        lib.recursiveUpdate input.r.agent { exporters."otlp_http/ingress".sending_queue.queue_sizee = 1; }
      );

      # The probe over launchctl and smartctl replies recorded on stibnite
      # at macOS 26.7.1, without their environment blocks. Value sources: the
      # expected files, written by hand from ADR-004:92-95 and the
      # recordings, against the probe's output from the same recordings.
      fixtures = ./otel-collector-darwin;
      launchctlStub = pkgs.writeShellScript "launchctl-stub" ''
        if [ "$#" != 2 ] || [ "$1" != print ]; then echo "launchctl stub: unexpected argv $*" >&2; exit 64; fi
        l=''${2#system/}
        sed '1{/^#/d}' "${fixtures}/launchctl/$l.txt"
        exit "$(cat "${fixtures}/launchctl/$l.rc")"
      '';
      smartctlStub = pkgs.writeShellScriptBin "smartctl" ''
        if [ "$*" = "-j -H -A disk0" ]; then cat ${fixtures}/smartctl-disk0.json; exit 0; fi
        echo "smartctl stub: unexpected argv $*" >&2
        exit 2
      '';
      probe =
        labels: devices:
        self.lib.otelHostProbe (pkgs // { smartmontools = smartctlStub; }) {
          inherit labels devices;
          inherit (self.lib.otelCollectorSchema) ownerAliases;
          textfileDir = "@TEXTFILE@";
          launchctl = "${launchctlStub}";
        };
      launchdCase = label: {
        labels = [ label ];
        devices = [ ];
        file = "launchd.prom";
        expected = "launchd-${label}.prom";
      };
      probeCases = {
        runningJob = launchdCase "org.nixos.nix-daemon";
        exitCode78 = launchdCase "org.nixos.exit-78";
        omnigentAlias = launchdCase "org.nixos.omnigent-host-cameron" // {
          noOwnerName = true;
        };
        notLoaded = launchdCase "org.nixos.otelcol";
        idleExit = launchdCase "org.nixos.jetsam-idle";
        nonIdleNoExitCode = launchdCase "org.nixos.signal-killed";
        smartctl = {
          labels = [ ];
          devices = [ "disk0" ];
          file = "smartctl.prom";
          expected = "smartctl.prom";
        };
        renamedIntoPlace = {
          labels = [
            "org.nixos.nix-daemon"
            "org.nixos.exit-78"
            "org.nixos.omnigent-host-cameron"
            "org.nixos.otelcol"
            "org.nixos.jetsam-idle"
            "org.nixos.signal-killed"
          ];
          devices = [ "disk0" ];
          file = null;
        };
      };
      # Each replaces the line after its `# mutant: <name>` marker in the
      # built probe and runs only its case.
      probeMutants = {
        aliasDropped = {
          case = "omnigentAlias";
          to = "shown=$label";
        };
        pidWritten = {
          case = "runningJob";
          to = ''[[ $runs =~ ^[0-9]+$ ]] && echo "launchd_job_runs_total{launchd_label=\"$shown\"} $runs" >> "$tmp/runs"; echo "launchd_job_pid{launchd_label=\"$shown\"} $(field pid)" >> "$tmp/runs"'';
        };
        missingExitCodeAsZero = {
          case = "nonIdleNoExitCode";
          to = ''case $code in "(never exited)" | "") code=0 ;; *[!0-9-]* | -) code=-1 ;; esac'';
        };
        idleExitAsFailure = {
          case = "idleExit";
          to = ":";
        };
      };
      probeBin = c: "${probe c.labels c.devices}/bin/otel-host-probe";
      mutateProbe =
        name: m:
        pkgs.runCommand "otel-host-probe-mutant-${name}"
          {
            nativeBuildInputs = [ pkgs.gawk ];
            # From the environment, which awk reads without escape processing.
            to = m.to;
          }
          ''
            awk -v marker='# mutant: ${name}' '
              replace { print ENVIRON["to"]; replace = 0; done = 1; next }
              index($0, marker) { replace = 1 }
              { print }
              END { exit !done }' ${probeBin probeCases.${m.case}} > $out
          '';
      # A shell function body: runs SCRIPT with @TEXTFILE@ replaced by a
      # fresh directory and judges its output; 2 when the probe itself
      # failed, so a mutant counts as rejected only by its output.
      probeCaseScript = name: c: script: ''
        d=$(mktemp -d)
        sed "s|@TEXTFILE@|$d|g" ${script} > "$d.sh"
        if ! bash "$d.sh" > "$d.out" 2>&1; then cat "$d.out" >&2; echo "probe case ${name}: the probe exited non-zero" >&2; return 2; fi
        ${
          if c.file == null then
            ''[ "$(ls -A "$d" | sort | tr '\n' ' ')" = "launchd.prom smartctl.prom " ] || { ls -la "$d" >&2; return 1; }''
          else
            ''
              diff -u ${fixtures}/expected/${c.expected} "$d/${c.file}" >&2 || return 1
              ${lib.optionalString (c.noOwnerName or false
              ) ''[ "$(grep -c cameron "$d/${c.file}" || true)" = 0 ] || return 1''}
            ''
        }
      '';
      probeRuns =
        lib.concatStrings (
          lib.mapAttrsToList (n: c: ''
            pc_${n}() { ${probeCaseScript n c (probeBin c)} }
            if pc_${n}; then echo "ok: ${n}"; else echo "FAIL: ${n}"; exit 1; fi
          '') probeCases
        )
        + lib.concatStrings (
          lib.mapAttrsToList (n: m: ''
            pm_${n}() { ${probeCaseScript m.case probeCases.${m.case} (mutateProbe n m)} }
            rc=0; pm_${n} 2> "$TMPDIR/mutant.err" || rc=$?
            if [ "$rc" = 1 ]; then echo "mutant ${n} rejected: ${m.case}"; grep -E '^[-+][^-+]' "$TMPDIR/mutant.err" | head -n 4 | sed 's/^/  /' || true; else cat "$TMPDIR/mutant.err"; echo "FAIL: mutant ${n} on ${m.case} returned $rc"; exit 1; fi
          '') probeMutants
        );

      # The notifier wrapper over a recording ntfy-send. Value sources: the
      # stub's log of ntfy-send calls against the notice texts typed here
      # from the failure-notice requirement (`FAILED <label> on <host>`,
      # `RESOLVED <label> on <host>`, topic fleet-alerts), and the token's
      # path this check passes against the stub's NTFY_TOKEN_FILE and argv.
      ntfyStub = pkgs.writeShellScriptBin "ntfy-send" ''
        # One line per post: the title, the topic, NTFY_TOKEN_FILE, and the argv.
        printf '%s|%s|%s|%s\n' "$1" "$2" "''${NTFY_TOKEN_FILE:-}" "$*" >> "$NTFY_STUB_LOG"
      '';
      notifyPkgs = pkgs // {
        ntfy-send = ntfyStub;
      };
      tokenFile = pkgs.writeText "alerter-token" "tk_fixture00000000000000000000000";
      wrapperArgs = {
        label = "otel-envelope";
        host = "stibnite";
        inherit tokenFile;
        # Expanded when the wrapper runs, so each case has its own directory.
        stateDir = "$NOTIFY_STATE";
        logFile = "$NOTIFY_STATE/notify.log";
      };
      wrapper = self.lib.observabilityNotifyRun notifyPkgs wrapperArgs;
      # postEveryFailure: the episode stamp's guard removed, built with
      # minIntervalSec = 0 so the suppression interval cannot hide it.
      wrapperMutant =
        let
          source = builtins.readFile ../lib/observability-notify-run.nix;
          from = ''if [ -e "$stamp" ]; then'';
          mutated =
            assert lib.assertMsg (
              builtins.length (builtins.split (lib.escapeRegex from) source) == 3
            ) "postEveryFailure: the replaced text must occur exactly once";
            import (builtins.toFile "observability-notify-run-postEveryFailure.nix" (
              builtins.replaceStrings [ from ] [ "if false; then" ] source
            )) { inherit lib; };
        in
        mutated.flake.lib.observabilityNotifyRun notifyPkgs (wrapperArgs // { minIntervalSec = 0; });
      titles = ''cut -d'|' -f1 "$NTFY_STUB_LOG" | tr '\n' ';' '';
      wrapperCases = {
        passFailFailPass = {
          runs = [
            "true"
            "false"
            "false"
            "true"
          ];
          judge = ''
            [ "$(${titles})" = "FAILED otel-envelope on stibnite;RESOLVED otel-envelope on stibnite;" ] || return 1
            [ "$(cut -d'|' -f2 "$NTFY_STUB_LOG" | sort -u)" = fleet-alerts ] || return 1
            [ "$(wc -l < "$NOTIFY_STATE/notify.log")" = 1 ] && grep -qE '^[0-9]+ otel-envelope stibnite$' "$NOTIFY_STATE/notify.log" || return 1
          '';
        };
        secondEpisodeInsideInterval = {
          runs = [
            "false"
            "true"
            "false"
            "true"
          ];
          judge = ''[ "$(${titles})" = "FAILED otel-envelope on stibnite;RESOLVED otel-envelope on stibnite;" ] || return 1'';
        };
        firstRunFails = {
          runs = [ "false" ];
          judge = ''[ "$(${titles})" = "FAILED otel-envelope on stibnite;" ] || return 1'';
        };
        tokenAsFile = {
          runs = [ "false" ];
          judge = ''
            [ "$(cut -d'|' -f3 "$NTFY_STUB_LOG" | sort -u)" = ${tokenFile} ] || return 1
            ! cut -d'|' -f4 "$NTFY_STUB_LOG" | grep -q tk_fixture || return 1
          '';
        };
        exitCodeKept = {
          runs = [ ];
          judge = ''
            rc=0; "$WRAPPER" -- sh -c 'exit 3' || rc=$?
            [ "$rc" = 3 ] || return 1
            "$WRAPPER" -- true || return 1
          '';
        };
      };
      wrapperCaseScript = c: ''
        NOTIFY_STATE=$(mktemp -d); NTFY_STUB_LOG=$(mktemp); export NOTIFY_STATE NTFY_STUB_LOG
        ${lib.concatMapStrings (r: "\"$WRAPPER\" -- ${r} || true\n") c.runs}
        ${c.judge}
      '';
      wrapperRuns = ''
        WRAPPER=${lib.getExe wrapper}
        ${lib.concatStrings (
          lib.mapAttrsToList (n: c: ''
            wc_${n}() { ${wrapperCaseScript c} }
            if wc_${n}; then echo "ok: ${n}"; else echo "FAIL: ${n}"; cat "$NTFY_STUB_LOG"; exit 1; fi
          '') wrapperCases
        )}
        WRAPPER=${lib.getExe wrapperMutant}
        wm() { ${wrapperCaseScript wrapperCases.passFailFailPass} }
        if wm; then echo "FAIL: mutant postEveryFailure survived passFailFailPass"; exit 1; fi
        echo "mutant postEveryFailure rejected: passFailFailPass"
        echo "  posts: $(${titles})"
      '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        otel-collector-darwin =
          pkgs.runCommand "otel-collector-darwin"
            {
              nativeBuildInputs = [
                pkgs.opentelemetry-collector-contrib
                pkgs.diffutils
                pkgs.gawk
              ];
            }
            ''
              set -uo pipefail
              printf '%s' ${lib.escapeShellArg clauseReport}
              for c in agent:${agentYaml} process:${processYaml}; do
                if otelcol-contrib validate --config "''${c#*:}" > "$TMPDIR/v.out" 2>&1; then
                  echo "ok: validate ''${c%%:*}"
                else
                  cat "$TMPDIR/v.out"; echo "FAIL: validate ''${c%%:*}"; exit 1
                fi
              done
              if otelcol-contrib validate --config ${badYaml} > "$TMPDIR/v.out" 2>&1; then
                echo "FAIL: control validateRejectsUnknownKey accepted"; exit 1
              else
                echo "control validateRejectsUnknownKey rejected"
              fi
              ${probeRuns}
              ${wrapperRuns}
              touch $out
            '';
      };
    };
}
