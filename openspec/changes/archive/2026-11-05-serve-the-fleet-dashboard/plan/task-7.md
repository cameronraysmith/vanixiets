### Task 7: Documentation and decision records

Implements `tasks.md` 5.1–5.3 (design "Implementation surface: artifacts amended"; O11).
Pull request 3.

**Files:**
- Modify: `packages/docs/src/content/docs/development/operations/fleet-observability.md`
- Modify: `docs/notes/development/observability/{charter.md,README.md}`, `decisions/ADR-002-dashboard-layer.md`, `decisions/ADR-007-packaging-placement-and-clan-service.md`, `decisions/ADR-008-access-control-and-tenancy.md`, `architecture/reference-architecture.md`
- Rewrite: `docs/notes/development/observability/components/perses.md`

**Interfaces:**
- Consumes: Task 6's recorded observations, for the runbook's expected outputs.
- Produces: the corpus consistent with the deployed state.

**Grounding:**
- Each amended line is located by the quoted phrase design "Implementation surface" gives for it, at `origin/main` `674cdf4a7`; if a phrase moved, locate it by `rg -n` and record the new line.
- The charter is at v27 (`charter.md:9`); a revision is a version bump with a dated entry, and earlier text is never edited in place (`charter.md:10`).

- [ ] **Step 1: The runbook (tasks.md 5.1)**

Replace "Reaching the dashboard" (`:40-62`) with: the URL; admission (`nix develop -c kanidm group add-members perses_users <account>`) and removal, and the 1 h lag (a 45 min refresh token and a 15 min access token); the tunnel `ssh -L 4000:127.0.0.1:4000 magnetite.zt` to the embedded dashboard as the operator's fallback, typing the `perses` password only there.
Update `:346` (fetching the `perses` password now matters only for the tunnel), `:583-584` (`devloop` is read in the `devloop` view, or through the tunnel), `:873` (dashboards over `devloop` delivered by S6) and `:876` (S6 done).
Add "Upgrading Perses": run `nix run .#update-perses-bin`, which rewrites `pkgs/by-name/perses-bin/sources.json`, then `checks.x86_64-linux.perses-lint`, `checks.x86_64-linux.perses-config` and `vmTests.x86_64-linux.perses-greptimedb` before merging.

Run: `rg -n 'obs\.scientistexperience\.net|perses_users|update\.sh' packages/docs/src/content/docs/development/operations/fleet-observability.md | tee logs/cam73-evidence/5.1-runbook-<ts>.log`

Expected: the new section's lines.

- [ ] **Step 2: Decision records and corpus (tasks.md 5.2)**

- `charter.md`: status, date and version lines to v28; a v28 entry recording O1 to O11 and the operator's answers to Q1 to Q4: ADR-002 reversed to a standalone Perses 0.55.1 packaged as `perses-bin`, with its own Kanidm client and group `perses_users` at `obs.scientistexperience.net`; the embedded dashboard kept on loopback as the operator's fallback; ADR-002 Q9 dissolved and Q10 answered; ADR-007 and ADR-008 follow; S6 precedes S5; the pull-request numbers of Tasks 2 and 5.
- ADR-002: every item design "Implementation surface" lists, including its citations of MG:133 for `sso.enable` at `:50` and `:167`, which become MG:162.
- ADR-007 `:76-78`, `:181`; ADR-008 `:89-91`, `:130-131`.
- `components/perses.md`: rewritten in its existing section order (Purpose, Decisions realized, Placement, Interfaces, Configuration surface, Operating envelope and regulator, Failure prevented, Deployment acceptance items, Deferred) from design D1 to D12 and its envelope table.
- `reference-architecture.md`: `:42`, `:85`, `:113`, `:124-127`, `:194`, `:216-222`, `:270-272`, `:280`.
- `README.md`: a v28 line in the charter summary; `:37` unchanged.

Run:

```bash
rg -n 'perses\.scientistexperience|127\.0\.0\.1:4006|perses-dashboards\.service|sso-gateway' docs/notes/development/observability \
  | rg -v '/charter\.md:|/research/' | tee logs/cam73-evidence/5.2-corpus-<ts>.log
```

Expected: only lines that record the 2026-10-15 gate or the rejected embedded option.

- [ ] **Step 3: Pull request 3 (tasks.md 5.3)**

`nix fmt`, `nix fmt -- --fail-on-change`, commit, open the pull request titled "Record the standalone Perses dashboard in the observability decision records".

Expected: nixbot green.
