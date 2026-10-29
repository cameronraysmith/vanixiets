# otel-envelope: each agent host's collector judged from its own telemetry
# endpoint every five minutes (ADR-003 R3.2; S4 design D7).
#
# flake.lib.otelEnvelope pkgs { hostName; telemetryUrl; targets; ingress; }
# is otel-envelope.service's ExecStart. `targets` is a list of
# { job; url; credential ? null; }, the collector's own scrape targets; a
# target with a credential is probed with `Authorization: Bearer` read from
# $CREDENTIALS_DIRECTORY/<credential> and passed to curl on stdin. Each run
# prints one `otel-envelope: <clause> <name>: ok|FAIL <detail>` line per
# clause and exits 1 if any failed:
#
# - C1 telemetry: the endpoint did not answer within 10 s on this run and
#   the previous one.
# - C2 targets: a target did not answer GET with 200 within 10 s on this run
#   and the previous one.
# - C3 queue: an exporter's otelcol_exporter_queue_size reached 90 % of its
#   otelcol_exporter_queue_capacity, or the capacity is absent.
# - C4 loss: since the previous run, otelcol_exporter_send_failed_* rose on
#   any exporter, otelcol_receiver_refused_* on any receiver but the
#   ingress's otlp/mesh, or, off the ingress host, any
#   otelcol_exporter_enqueue_failed_*. On the ingress host otlp/mesh
#   refusals and the store exporters' enqueue failures are back-pressure
#   that the agents' queues absorb; a full store queue fails C3.
#
# $STATE_DIRECTORY/state holds one `<key> <value>` line per loss series,
# keyed without the labels that change at every collector start, plus
# `telemetry 0|1` and `down:<job> 0|1`; it is replaced as a whole at the end
# of each run. checks.x86_64-linux.otel-envelope replaces each line marked
# `# mutant: <name>` and requires one of its cases to fail.
#
# flake.lib.otelEnvelopeTargets receivers renders `targets` from a
# collector's evaluated receivers: every job of every `prometheus*`
# receiver, so the envelope probes what the collector scrapes, and a job's
# authorization.credentials_file becomes the credential of that file's name.
{ lib, ... }:
{
  flake.lib.otelEnvelopeTargets =
    receivers:
    lib.concatMap (
      name:
      map (job: {
        job = job.job_name;
        url = "${job.scheme or "http"}://${builtins.head (builtins.head job.static_configs).targets}${job.metrics_path or "/metrics"}";
        credential =
          if job ? authorization.credentials_file then
            baseNameOf job.authorization.credentials_file
          else
            null;
      }) receivers.${name}.config.scrape_configs
    ) (builtins.filter (lib.hasPrefix "prometheus") (builtins.attrNames receivers));

  flake.lib.otelEnvelope =
    pkgs:
    {
      hostName,
      telemetryUrl ? "http://127.0.0.1:8888/metrics",
      targets,
      ingress ? false,
    }:
    pkgs.writeShellApplication {
      name = "otel-envelope";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.gawk
        pkgs.gnugrep
        pkgs.gnused
      ];
      text = ''
        # The collector of ${hostName}.
        telemetry_url=${lib.escapeShellArg telemetryUrl}
        ingress=${if ingress then "1" else "0"}
        targets=${
          lib.escapeShellArg (
            lib.concatMapStrings (
              t: "${t.job} ${t.url} ${if t.credential or null == null then "-" else t.credential}\n"
            ) targets
          )
        }

        : "''${STATE_DIRECTORY:?}"
        tmp=$(mktemp -d)
        trap 'rm -rf "$tmp"' EXIT
        state="$STATE_DIRECTORY/state"
        next="$STATE_DIRECTORY/state.next"
        : > "$next"
        # A first run, with no state file, records the baseline and judges C1
        # to C3 only, so a host whose counters were already non-zero before the
        # envelope existed does not fail its first run.
        baseline=0
        [ -e "$state" ] || baseline=1
        failed=0

        ok() { echo "otel-envelope: $1: ok"; }
        fail() {
          echo "otel-envelope: $1: FAIL $2"
          failed=1
        }
        prev() {
          if [ -e "$state" ]; then
            awk -v k="$1" '$1 == k { v = $2; f = 1 } END { print f ? v : "absent" }' "$state"
          else
            echo absent
          fi
        }
        # A series' key: its name and labels without the per-start identity.
        normalise() { sed -E 's/(service_instance_id|service_name|service_version|otel_scope_[a-z_]+)="[^"]*",?//g; s/,}/}/; s/\{\}//'; }

        # C1: a run without telemetry fails only if the previous run had none.
        if curl -fsS --max-time 10 "$telemetry_url" -o "$tmp/now" 2> "$tmp/c1"; then
          echo "telemetry 0" >> "$next"
          ok "C1 telemetry"
        else
          echo "telemetry 1" >> "$next"
          : > "$tmp/now"
          # One missed read keeps the previous counters, so the next run does
          # not see their whole cumulative value as an increase.
          # mutant: noCarryForward
          { grep -E '^otelcol_' "$state" 2> /dev/null || true; } >> "$next"
          if [ "$(prev telemetry)" = 1 ]; then
            fail "C1 telemetry" "no answer from $telemetry_url on this run and the previous one: $(tr '\n' ' ' < "$tmp/c1")"
          else
            ok "C1 telemetry"
          fi
        fi

        # C2: each declared target, down on this run and the previous one.
        down=""
        while read -r job url credential; do
          [ -n "$job" ] || continue
          if [ "$credential" = - ]; then
            code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" || true)
          else
            code=$(printf 'header = "Authorization: Bearer %s"\n' "$(cat "$CREDENTIALS_DIRECTORY/$credential")" \
              | curl -s -o /dev/null -w '%{http_code}' --max-time 10 --config - "$url" || true)
          fi
          if [ "$code" = 200 ]; then
            echo "down:$job 0" >> "$next"
          else
            echo "down:$job 1" >> "$next"
            # mutant: targetDownOneRun
            if [ "$(prev "down:$job")" = 1 ]; then down="$down $job"; fi
          fi
        done <<< "$targets"
        if [ -n "$down" ]; then
          fail "C2 targets" "''${down# } down on this run and the previous one"
        else
          ok "C2 targets"
        fi

        # C3: size against capacity per exporter and data type.
        full=$(awk '
          function label(s, k) {
            return match(s, "[{,]" k "=\"[^\"]*\"") ? substr(s, RSTART + length(k) + 3, RLENGTH - length(k) - 4) : ""
          }
          /^otelcol_exporter_queue_(size|capacity)\{/ {
            id = label($1, "exporter") "/" label($1, "data_type")
            if ($1 ~ /^otelcol_exporter_queue_size\{/) size[id] = $2; else capacity[id] = $2
          }
          END {
            for (id in size) {
              if (!(id in capacity)) printf "%s capacity absent; ", id
              else if (size[id] * 10 >= capacity[id] * 9) printf "%s %s of %s; ", id, size[id], capacity[id]
            }
          }' "$tmp/now")
        if [ -n "$full" ]; then fail "C3 queue" "$full"; else ok "C3 queue"; fi

        # C4: an absent counter reads 0; a value below the recorded one is a
        # restart, and the current value is the increase.
        loss_re='^otelcol_exporter_send_failed_|^otelcol_receiver_refused_'
        [ "$ingress" = 1 ] || loss_re="$loss_re|^otelcol_exporter_enqueue_failed_"
        : > "$tmp/loss"
        if [ -s "$tmp/now" ]; then
          # The braces keep an empty match from failing the run under pipefail.
          # mutant: missingCounterFails
          { grep -E "$loss_re" "$tmp/now" || true; } | while read -r series value; do
            # mutant: meshRefusalIsLoss
            if [ "$ingress" = 1 ] && [[ $series == otelcol_receiver_refused_*'receiver="otlp/mesh"'* ]]; then continue; fi
            key=$(printf '%s' "$series" | normalise)
            was=$(prev "$key")
            echo "$key $value" >> "$next"
            [ "$baseline" = 0 ] || continue
            [ "$was" != absent ] || was=0
            # mutant: resetNegative
            inc=$(awk -v n="$value" -v p="$was" 'BEGIN { print (n < p) ? n : n - p }')
            if awk -v i="$inc" 'BEGIN { exit !(i > 0) }'; then echo "$key +$inc" >> "$tmp/loss"; fi
          done
        fi
        if [ -s "$tmp/loss" ]; then fail "C4 loss" "$(tr '\n' ' ' < "$tmp/loss")"; else ok "C4 loss"; fi

        mv "$next" "$state"
        exit "$failed"
      '';
    };
}
