### Task 8: Documentation

Implements `tasks.md` 8.1–8.3 (design D7, D9; FA `Replacing the service authority loses no post`; FAI `This capability states its own trust boundary`).
It starts after Task 6 Step 7, so the documents record the import and the window's outcome, and lands as pull request 4.

**Files:**
- Modify: `docs/notes/development/observability/charter.md`, `docs/notes/development/observability/decisions/ADR-009-alerting.md`, `docs/notes/development/observability/components/fleet-alert.md`, `docs/notes/development/observability/architecture/reference-architecture.md`, `packages/docs/src/content/docs/development/operations/fleet-observability.md`, `modules/README.md`.

- [ ] **Step 1: Decision records (8.1)**

Add the charter's v30 entry after v29, in the form of the v27 to v29 entries: its status, date and version lines; "the decisions of CAM-87 (`openspec/changes/verify-ntfy-before-sending-tokens/`), the operator's O1 to O7 of 2026-11-06"; and one bullet per amendment below with its file and lines.
Amend ADR-009 in place under charter v30, adding the status line "Amended in place under charter v30 (<date>): delivery verifies `ntfy.zt` against caddy's root (CAM-87)":
- Item 10 (A9:85-86): "so delivery inherits the helper's `-k` convention for caddy's internal TLS" becomes "and `ntfy-send` verifies `ntfy.zt` against caddy's root, the public value of cinnabar's clan vars `caddy-root-ca`, carried in its closure as a store path, posting nothing to a server that cannot present a chain to it".
- Delivery evidence (A9:53): the `curl -sfk -m 5` sentence states `curl -sf --cacert <caddy's root> -m 5` and cites `pkgs/by-name/ntfy-send/ntfy-send.sh` and `package.nix` at the merge commit.
- Consequences (A9:204-205): the sentences on `-k`, on the token's confidentiality resting on ZeroTier and dnsmasq, and on distributing the root to magnetite are replaced by: the token and every message reach only a holder of caddy's root key, which cinnabar, caddy and the sops users can read (A81); caddy loads that root from the vars, so a reinstall serves the same root; a served chain that stops verifying stops every post, which the external watch reports; delivery still depends on cinnabar's `.zt` resolver.
In `components/fleet-alert.md:52`, "inheriting the helper's `curl -sfk -m 5` convention for caddy's internal TLS" becomes "verifying `ntfy.zt` against caddy's root with `curl -sf --cacert <root> -m 5`"; in `architecture/reference-architecture.md:139`, the sentence becomes "Delivery to `ntfy.zt` verifies caddy's certificate against the root in the repository, so the `alerter` token reaches only a holder of that root's key (ADR-009 Consequences)."
Then:

```bash
rg -n '^- v30 ' docs/notes/development/observability/charter.md
rg -n -- '-sfk|-k. convention|inherits the helper' docs/notes/development/observability/
```

Expected: the v30 entry; the second search prints only historical charter entries (v12 to v29), which are not edited.

- [ ] **Step 2: The runbook (8.2)**

In `packages/docs/src/content/docs/development/operations/fleet-observability.md`:
- Line 190's `curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=1h'` becomes `curl -s --cacert vars/per-machine/cinnabar/caddy-root-ca/root.crt/value 'https://ntfy.zt/fleet-alerts/json?poll=1&since=1h'`, run from the repository root, and every other `curl -sk` against `ntfy.zt` in the file the same.
- Line 555's note records that `ntfy-send` verifies `ntfy.zt` against caddy's root on both platforms with the store curl since CAM-87, and that the hooks post through it.
- A new section "caddy's root" states: that caddy's root and key are cinnabar's clan vars `caddy-root-ca`, imported on <date of tasks.md 2.4> with fingerprint `7E:78…2E:82` and readers cinnabar and the sops users, and that `clan vars generate` cannot mint them; the security trade-off of design "Risks / Trade-offs"; that a reinstall restores the root by deploying cinnabar; that caddy stops issuing from 2035-11-29 (A79); what a `FAILED caddy-root-check.service on cinnabar` means for each of its two messages; and design D7's five rotation steps, with the commands of each.

```bash
f=packages/docs/src/content/docs/development/operations/fleet-observability.md
rg -n 'caddy-root-check|caddy-root-ca|--cacert|rotation|reinstall' "$f"
rg -n "curl -sk .https://ntfy" "$f" || echo "no unverified ntfy curl"
```

Expected: each term found; `no unverified ntfy curl`.

- [ ] **Step 3: The modules README and pull request 3 (8.3)**

In `modules/README.md`, after the fleet-alerting checks paragraph (around line 55), add two sentences: `checks.x86_64-linux.ntfy-tls-verification` scans `modules/` and `pkgs/` for an `ntfy.zt` client passing `-k` or `--insecure` or undeclared, and runs `flake.lib.caddyRootCheck` over roots made in the sandbox; it does not observe the chain caddy serves, which cinnabar's weekly `caddy-root-check` verifies; `caddy-root-from-vars`, built with cinnabar's toplevel, adapts caddy's configuration and compares the configured root with the vars and the recorded fingerprint; `vmTests.x86_64-linux.caddy-root-from-vars` shows a caddy with empty storage serving under a configured root.
Run `nix fmt`, keep its log, run `nix fmt -- --fail-on-change`, and open pull request 4, titled "Document ntfy.zt certificate verification and caddy's root as clan vars".
Expected: nixbot green; the pull request merges through the queue.
