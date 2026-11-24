# Verification report: darwin-agent-session-telemetry (Linear CAM-121)

Started 2026-11-24, after #4159–#4172 merged and magnetite, pyrite (55c644f6) and stibnite (generation 240 at 55c644f6) deployed. The change stays open; `tasks.md` names each open task and what closes it.

## Migration conditionals (task 13.4)

The code this change added, `git diff 705b436c7^ 8398163ab` outside `openspec/` and `docs/`, was searched for branches that exist only to carry hosts from the old layout to the new one: activation-time removals, `rm`, `bootout`, ownership fixes, version or "previous" guards, one-shot cleanups.
None was found, so nothing is removed.
Four kinds of code look like transitions and are standing configuration:

| Code | Why it stays |
|---|---|
| The fleet receiver and `otelcol-process` on `127.0.0.1:4319` (`modules/lib/otel-collector-darwin.nix:144-147,345`) | a constant, not a branch: 4319 is the darwin fleet receiver from now on (design D2) |
| `agentTelemetry` and `langfuse` host-table flags, and the `lib.mkIf agentTelemetry` blocks in `modules/darwin/otel-collector-agent.nix` | per-host choices that let another Mac join by one row edit (operator D24) |
| `agentSpanQueueMiB` (`modules/lib/observability-hosts.nix:24,47`; 256 on stibnite) | per-host sizing (design D7) |
| The every-run `ADD COLUMN IF NOT EXISTS` and `SET FULLTEXT INDEX` statements (`spanAlters` in `modules/nixos/agent-session-store.nix:126-136`, `alters` in `modules/lib/greptimedb-log-table.nix:90`) | they no longer change anything on magnetite's tables, but they are how any table created by an older generation gains a later column; removing them would make the next added column fail with "unknown columns" (design D15) |

## C5 footprint per day (tasks 12.5, 14.1)

The operator decided on 2026-11-24 (decision record D48) that task 12.5 closes with the week-after check, task 14.1, from the footprints the agent-session envelope logs on C5's line (design D4, "C5 under real use").
Lines written before stibnite's activation of that change carry no time or footprint and are skipped, so the days counted start at that activation.
Run on stibnite (darwin's `awk` and `sort` suffice), and record the output here with the date read:

```sh
ssh stibnite.vanixiets.internal 'caffeinate -i bash -s' <<'EOF'
log=/var/log/otelcol/otel-agent-session-envelope.log
# One row per C5 line with a time: its UTC day, the daemon's logged
# footprint ("-" when the job had no pid or its footprint was not read) and limit.
awk '/^otel-envelope: C5 memory: / {
  if (!match($0, /at=[0-9-]+T/)) next
  d = substr($0, RSTART + 3, 10); fp = "-"; lim = "-"
  if (match($0, /org\.nixos\.otel-agent-session footprint_bytes=[0-9]+ limit_bytes=[0-9]+/)) {
    split(substr($0, RSTART, RLENGTH), f, /[ =]/); fp = f[3]; lim = f[5]
  }
  print d, fp, lim
}' "$log" | sort -k1,1 -k2,2n | awk '
  function flush() {
    if (day == "") return
    m = k ? (k % 2 ? v[(k + 1) / 2] : (v[k / 2] + v[k / 2 + 1]) / 2) : 0
    printf "%s runs=%d read=%d max_mib=%.1f median_mib=%.1f limit_mib=%.0f\n", day, runs, k, k ? v[k] / 1048576 : 0, m / 1048576, lim / 1048576
  }
  $1 != day { flush(); day = $1; runs = 0; k = 0; lim = 0 }
  { runs++; if ($2 != "-") { v[++k] = $2; lim = $3 } }
  END { flush() }'
ls -l /var/lib/otel-agent-session-envelope/notify.log 2>&1
EOF
```

`runs` counts the envelope's runs that UTC day (288 for a day awake throughout), and `read` those that read the daemon's footprint; the maximum and median are over the read runs.
`notify.log` exists only once the job has posted a `FAILED otel-agent-session-envelope`, one line per post.
