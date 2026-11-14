Group 1 is the implementation, done in the working copy on 2026-11-14; group 2 is the purge of D2; group 3 is the pull request and magnetite's deploy, which both wait on it.
Nix-managed outputs are verified by evaluating (`nix eval`) or building (`nix build`, x86_64-linux on magnetite with `--eval-store auto --store ssh-ng://magnetite.zt`), or on magnetite after activation; each item names which.
Every query of `device_grants` in these tasks is read-only and prints no token hash, code or grant id.

## 1. Implementation

- [x] 1.1 Set `OMNIGENT_GRANT_MAX_LIFETIME_DAYS` to `"90"` in `systemd.services.omnigent.environment` in `modules/nixos/omnigent.nix` (D1). — verify: `nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.omnigent.environment.OMNIGENT_GRANT_MAX_LIFETIME_DAYS` prints `90` (evaluation).
- [x] 1.2 Update `modules/clan/services/omnigent/README.md`'s lifetime and renewal lines to name `OMNIGENT_GRANT_MAX_LIFETIME_DAYS`, 90 days once deployed, and renewal ahead of the date or on the unit's failure notice.
- [x] 1.3 Build magnetite and the fleet-alert check. — verify: `nix build` of `checks.x86_64-linux.nixos-magnetite` and `checks.x86_64-linux.fleet-alert` passes (build).

## 2. Gate (D2)

- [x] 2.1 Deploy magnetite with `OMNIGENT_GRANT_MAX_LIFETIME_DAYS = "7"` from an uncommitted edit in the deploy tree, POST one `grant_type=refresh_token` request with a placeholder token to `/oauth/token`, and run `sudo -n -u omnigent psql omnigent -XAtc "SELECT count(*) FROM device_grants WHERE client_id = 'omnigent-cli' AND status = 4 AND approved_at <= extract(epoch FROM now())::bigint - 7 * 86400"`. — verify: the server's environment shows `OMNIGENT_GRANT_MAX_LIFETIME_DAYS=7`, the query prints `0`, and the 2026-11-14 grants remain (command).
  Done 2026-11-14: magnetite deployed with the 7-day lifetime (omnigent started 21:35:46Z, 0 failed units); the first request reached nginx before omnigent listened and got 502, the retry got `400 invalid_grant`, and the server's purge deleted the grants of 2026-10-17 and 2026-10-25; the query printed `0`, the five grants of 2026-11-14 remain, and both worker hosts on magnetite stayed active.

## 3. Merge and deploy (gated on 2.1)

- [x] 3.1 Enqueue pull request #3873 only after 2.1 passes, and the same day: under 7 days the 2026-11-14 grants expire on 2026-11-21 (command).
  Enqueued after nixbot passed and merged at 2026-11-14 22:12:11Z.
- [x] 3.2 Deploy magnetite from the merged commit, discarding the deploy tree's edit. — verify: on magnetite `systemctl show -p Environment omnigent` includes `OMNIGENT_GRANT_MAX_LIFETIME_DAYS=90`, and the server's journal since the start shows no warning about the variable (command).
  Deployed from `main` at 2026-11-14 22:13:39Z after discarding the edit: the environment shows `OMNIGENT_GRANT_MAX_LIFETIME_DAYS=90`, the journal since the start has no line about it, 0 failed units, and both worker hosts are active.
