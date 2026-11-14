Group 1 is the implementation, done in the working copy on 2026-11-14; group 2 is the pull request, which may merge before the gate; group 3 is magnetite's deploy, which waits on the gate of 3.1; group 4 is acceptance.
Nix-managed outputs are verified by evaluating (`nix eval`) or building (`nix build`, x86_64-linux on magnetite with `--eval-store auto --store ssh-ng://magnetite.zt`), or on magnetite after activation; each item names which.
Every query of `device_grants` in these tasks is read-only, prints no token hash, code or grant id, and goes to a log under `logs/`.

## 1. Implementation

- [x] 1.1 Set `OMNIGENT_GRANT_MAX_LIFETIME_DAYS` to `"90"` in `systemd.services.omnigent.environment` in `modules/nixos/omnigent.nix`, from the binding the expiry query also reads (D1). — verify: `nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.omnigent.environment.OMNIGENT_GRANT_MAX_LIFETIME_DAYS` prints `90` (evaluation).
- [x] 1.2 Add the role `opentelemetry-collector` to `services.postgresql.ensureUsers`, the oneshot `omnigent-pg-grants` granting `SELECT` on the four columns, and the receiver `sqlquery/omnigent-grants` in `metrics/host`, each only when the collector is enabled, with the two assertions of D4 (D2, D3). — verify: `nix eval --json` of magnetite's collector settings shows the receiver in `metrics/host` and the query of D3; the column grant and the query, run as the role on PostgreSQL 16 over a seeded `device_grants`, return one row per owner with the earliest expiry and exclude revoked and non-CLI grants, and the role's read of `refresh_token_hash` is denied (evaluation, command).
- [x] 1.3 Add `OmnigentLoginGrantExpiring` to `modules/nixos/fleet-alert/rules.nix` with its presence selector expected from the collecting NixOS hosts in `[ "magnetite" ]` (D4).
- [x] 1.4 Add to `promtoolRehearsal` in `modules/checks/fleet-alert.nix` a `promtool test rules` case on the rule and the mutant `grantThresholdInDays`, run only on the firing case. — verify: `nix build .#checks.x86_64-linux.fleet-alert.promtoolRehearsal` passes, printing `SUCCESS` for the rule test and `mutant grantThresholdInDays rejected` after the mutant's failure at `alertname: OmnigentLoginGrantExpiring, time: 2h` (build).
- [x] 1.5 Update `modules/clan/services/omnigent/README.md`'s lifetime and renewal lines to name `OMNIGENT_GRANT_MAX_LIFETIME_DAYS`, 90 days once deployed, and `OmnigentLoginGrantExpiring`.
- [x] 1.6 Build magnetite and the affected checks. — verify: `nix build` of `checks.x86_64-linux.nixos-magnetite`, `fleet-alert`, `otel-collector-config`, `otel-envelope` and `structure-fleet` passes (build).
  Done 2026-11-14: `logs/streamA-builds-20261114-150029.log`, rc 0, built on magnetite from the working copy; the two assertions of D4 fail under `extendModules` overrides removing the pipeline's exporters and renaming the host, and hold unmutated (`logs/streamA-assert-mutants-20261114-150429.log`).
- [x] 1.7 Run the expiry query read-only on magnetite as `omnigent` in a read-only session. — verify: one row per owner alias with its expiry (command).

## 2. Pull request

- [x] 2.1 Record the evaluation cost of `fleet-alert` with `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=<file> nix eval --option eval-cache false --raw .#checks.x86_64-linux.fleet-alert.drvPath` before and after, against 536,870,912 B (evaluation).
  Done 2026-11-14: `fleet-alert` 471,236,480 B and 1.39 s at `main@origin` `22f59a5a`, 473,320,816 B and 1.36 s with this change; `otel-collector-config`, whose input the receiver joins, 552,545,200 B before and 552,429,488 B after, already over the budget at `main@origin` and not raised by this change (`logs/streamA-evalstats-*.json`).
- [ ] 2.2 Run `nix fmt`, open the pull request in plain words, and merge it through the queue; the merge does not wait for the gate of 3.1, because nothing changes on a host until magnetite deploys (command).

## 3. magnetite's deploy (gated)

- [ ] 3.1 Gate (D5): on or after 2026-11-24 19:02Z, on magnetite, `sudo -n -u omnigent psql omnigent -XAtc "SELECT count(*) FROM device_grants WHERE client_id = 'omnigent-cli' AND status = 4 AND approved_at <= extract(epoch FROM now())::bigint - 30 * 86400"` prints `0`. The server purges a grant past 30 days on the next refresh, at most every 300 s, and the workers refresh hourly, so a non-zero count an hour after the last superseded grant turned 30 days old means a worker is down, which is investigated before the deploy (command).
- [ ] 3.2 Deploy magnetite from the merged commit, before 2026-12-14, only with 3.1 passed in the same session. — verify: on magnetite `systemctl show -p Environment omnigent` includes `OMNIGENT_GRANT_MAX_LIFETIME_DAYS=90`, `omnigent-pg-grants` is `active (exited)`, and the server's journal shows no warning about the variable (command).

## 4. Acceptance

- [ ] 4.1 Read `omnigent_login_grant_expiry_timestamp_seconds` from the `fleet` database. — verify: one series per owner alias with `host_name="magnetite"`, each equal to that owner's earliest redeemed CLI grant's `approved_at` plus 7,776,000 s, and no `RuleSignalMissing` naming `OmnigentLoginGrantExpiring` within 30 min of the deploy (command).
