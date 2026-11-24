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
