# Declarative single-source cognee endpoint (comprehensive) implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** Make cognee the universal knowledge base accessed via the cognee-cli and the `cognee-memory` plugin (not the MCP), all pointed at one central magnetite cognee through a single declarative nix source of truth, plus a public kanidm-gated browser UI at `kb.scientistexperience.net`.
This is one comprehensive change: a typed source of truth, dropping the cognee MCP on both sides, binding the REST API ZeroTier-only behind per-agent authentication, pointing the always-on plugin and a new global cognee-cli wrapper at central magnetite with per-host namespacing, a same-origin frontend rebuild, and a public kanidm-gated UI fronted by a dedicated containerized oauth2-proxy that leaves buildbot untouched.
There is no Phase-1/Phase-2 split and no buildbot prerequisite.
Multi-tenant per-dataset isolation (`ENABLE_BACKEND_ACCESS_CONTROL`), multi-user public access, cognee native OIDC, and a public machine path remain deferred future work.

**Architecture:** A two-layer `flake.lib` value (a per-host ZeroTier-address registry plus a derived `flake.lib.cognee` record carrying `meshApiUrl`/`apiPort`/`publicFqdn`/`userEmail` and NO MCP URL), each consolidated into its own single file per the `lazyAttrsOf raw` constraint, is read by the cognee server bind, the plugin env, the cognee-cli wrapper, the public-UI FQDN, and the terranix DNS record.
The cognee MCP is removed on both sides (client entry plus `~/.mcp/cognee.json`, and `services.cognee.mcp.enable = false` plus the 9271 firewall opening and the orphaned `cognee-mcp` systemd stanzas), while the `ip_nonlocal_bind` sysctl is retained and its comment rewritten for the REST ZeroTier bind.
The cognee REST API (9270, loopback-only today) is bound ZeroTier-only to the magnetite ZeroTier address (single `types.str` listen address, fail-closed) and opened on `zt+`.
Per-agent authentication is turned on via `services.cognee.settings.REQUIRE_AUTHENTICATION = "true"` (two-knob model: `auth.multiTenant` stays `false`, so `ENABLE_BACKEND_ACCESS_CONTROL` resolves `false` and nothing is stranded), and a scoped per-host `X-Api-Key` — minted once per fleet client by an owner-authenticated bootstrap and delivered via a sops-nix home-manager secret — is dual-consumed by the plugin (`COGNEE_API_KEY`) and the cognee-cli wrapper (`--api-key`).
A build-time no-public-bind assertion is the mechanical gate (the retained `ip_nonlocal_bind=1` makes a wrong bind silent).
The frontend is rebuilt in the cognee-nix fork with `NEXT_PUBLIC_LOCAL_API_URL=""` for same-origin `/api/` and bound to loopback `127.0.0.1:3000`.
A dedicated containerized kanidm oauth2-proxy (jfly pattern) plus a bespoke host nginx vhost plus a terranix DNS record provide the public browser UI gated on `cognee_access` group membership, with cognee's kanidm client/group/generator living in `modules/nixos/kanidm.nix` alongside synapse (the live precedent), and buildbot's oauth2-proxy singleton left untouched.

**Tech Stack:** nix flake-parts `flake.lib`, the cognee-nix fork (frontend rebuild, cross-repo prerequisite), NixOS modules (`modules/nixos/cognee.nix`; the cognee oauth2-proxy/vhost module using the jfly containerized pattern; `modules/nixos/kanidm.nix` for the client/group/generator; nginx, ACME), home-manager (`mcp-servers.nix` edit; a plugin-env module using `home.sessionVariables` plus a sops-nix secret for the key; a cognee-cli wrapper module named `cognee-cli` over the cognee-nix overlay's `pkgs.cognee`), clan-vars/sops secrets (one `kanidm-oauth2-cognee` generator emitting two ownership-correct client-secret files plus a length-correct cookie secret), terranix Cloudflare DNS (applied via `just terraform*`).

---

## Phase 1: Source of truth (deliverable A)

- [ ] **Step 1:** Create a single new file declaring `flake.lib.hosts.<host>.zt` with `magnetite.zt = "fddb:4344:343b:14b9:399:930f:39db:40d2"`, as a single-file consolidation.
- [ ] **Step 2:** Add the derived `flake.lib.cognee` record in its own single file: `meshApiUrl = "http://[${magnetite.zt}]:9270"`, `apiPort = 9270`, `publicFqdn = "kb.scientistexperience.net"`, `userEmail = "cameron@scientistexperience.net"`; NO MCP URL of any kind.
- [ ] **Step 3:** Confirm both additions evaluate cleanly under `flake.lib` (`lazyAttrsOf raw`).

## Phase 2: Cross-repo cognee-nix fork prerequisite (deliverable A-frontend)

This phase touches a separate repository and a flake-input bump, and must land before the in-repo frontend-enable config (Phase 4) can reference the rebuilt bundle.

- [ ] **Step 1:** In the cognee-nix fork, edit `packages/cognee-frontend/default.nix` `buildPhase` to export `NEXT_PUBLIC_LOCAL_API_URL=""` (it currently exports none) for same-origin `/api/`.
- [ ] **Step 2:** Recompute the FOD hashes, push the `cognee-v112` branch, and bump the cognee-nix input in vanixiets `flake.nix`/`flake.lock`.
- [ ] **Step 3:** Confirm the built bundle contains no literal `localhost` backend URL (falsifiable check).

## Phase 3: cli existence precondition (deliverable E precondition)

- [ ] **Step 1:** Build `pkgs.cognee` and confirm `bin/cognee-cli --help` lists `--api-url` and `--api-key` before the wrapper (Phase 7) is authored.

## Phase 4: Server — REQUIRE_AUTHENTICATION, REST ZeroTier bind, no-public-bind assertion, MCP teardown, loopback frontend (deliverables C, B-server)

- [ ] **Step 1:** Set `services.cognee.settings.REQUIRE_AUTHENTICATION = "true"` (rendered last, overriding base env, zero fork change), keeping `auth.multiTenant = false` so `ENABLE_BACKEND_ACCESS_CONTROL` resolves `false`.
- [ ] **Step 2:** Set the single `types.str` REST listen address to `flake.lib.hosts.magnetite.zt` (fail-closed) and open 9270 on `zt+` only; the full REST surface on the mesh does widen the surface vs the 12-tool MCP, mitigated by `REQUIRE_AUTHENTICATION`.
- [ ] **Step 3:** Add a NixOS `assertion` failing the build if the REST/frontend/postgres listen addresses resolve outside loopback or the ZeroTier prefix (required because the retained `ip_nonlocal_bind=1` makes a wrong bind silent).
- [ ] **Step 4:** Enable the rebuilt frontend bound to loopback `127.0.0.1:3000`, drop the inert `NEXT_PUBLIC_BACKEND_API_URL` injection, and confirm postgres stays loopback `127.0.0.1:5432`.
- [ ] **Step 5:** Set `services.cognee.mcp.enable = false`, remove the 9271 `zt+` opening, and remove the orphaned `cognee-mcp` systemd stanzas (`MCP_DISABLE_DNS_REBINDING_PROTECTION`, the per-service `serviceConfig`), while RETAINING the `ip_nonlocal_bind` sysctl and rewriting its comment for the REST bind; leave `services.cognee.nginx` unused.

## Phase 5: Client — drop MCP client, non-secret plugin env + per-host namespacing, secure key delivery (deliverables B-client, D)

- [ ] **Step 1:** Remove the cognee entry from `modules/home/ai/claude-code/mcp-servers.nix` so `~/.mcp/cognee.json` is no longer generated; confirm the hardcoded MCP IPv6 literal is gone.
- [ ] **Step 2:** Add a home-manager module exporting the non-secret plugin env via `home.sessionVariables`: `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` (HTTP mode), per-host `COGNEE_PLUGIN_DATASET` and `COGNEE_AGENT_NAME`, and `COGNEE_USER_EMAIL = cameron@scientistexperience.net`.
- [ ] **Step 3:** Deliver the per-host `X-Api-Key` via a sops-nix home-manager secret consumed as `COGNEE_API_KEY` (never plaintext `home.sessionVariables`); confirm the plugin strips URL/key from `~/.cognee-plugin/config.json` and degrades gracefully (connects-only) when magnetite is unreachable.

## Phase 6: One-time per-host X-Api-Key mint bootstrap (user-run)

- [ ] **Step 1:** USER-RUN: once Phase 4 is deployed and reachable, log in as `cameron@scientistexperience.net` with the existing `cognee-default-user-password`, `POST /api/v1/auth/api-keys` once per fleet client, and store each scoped key per host in clan-vars (a documented manual/clan-vars bootstrap; the mint needs a live authenticated server session).

## Phase 7: cognee-cli wrapper module (deliverable E)

- [ ] **Step 1:** Add a home-manager module installing a global cognee-cli wrapper as a `writeShellApplication` named exactly `cognee-cli` that execs `${pkgs.cognee}/bin/cognee-cli` directly (not `lib.getExe`, which fails on no `meta.mainProgram`), bakes `--api-url ${flake.lib.cognee.meshApiUrl}` and `--api-key` (from the sops-nix secret, never `--api-token`), and forwards `"$@"`.
- [ ] **Step 2:** Confirm the wrapper is decoupled from the plugin's venv and accept the ~1.5 GiB per-host closure footprint; the plugin skills hardcode the `cognee-cli` name on `PATH`.

## Phase 8: Public browser UI — kanidm plumbing in kanidm.nix, dual-context secret, containerized oauth2-proxy, bespoke nginx vhost (deliverable F)

- [ ] **Step 1:** In `modules/nixos/kanidm.nix` (alongside synapse), declare the `provision.groups.cognee_access` stub (`members = []`, `overwriteMembers = false`, `provision.autoRemove = false`) BEFORE any scopeMap references it (the `kanidm.nix:876` referential check); cameron is added operationally.
- [ ] **Step 2:** Register `provision.systems.oauth2.cognee` with `basicSecretFile` reading `files.secret`, `scopeMaps.cognee_access = ["openid" "email" "groups"]`, and `claimMaps.groups` (a new requirement — synapse uses no `claimMaps` — needed for oauth2-proxy `allowed_groups`).
- [ ] **Step 3:** Add the single `kanidm-oauth2-cognee` generator emitting two ownership-correct client-secret files (`files.secret` owner `kanidm`; `files.secret-proxy` owner the container's runtime uid, bind-mounted) plus a 16/24/32-byte cookie secret (mirror `openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32`), every file `mode = "0400"` `secret = true`, `restartUnits = [ "kanidm.service" "container@oauth2-proxy-cognee.service" ]`; document the bind-mount path and uid mapping.
- [ ] **Step 4:** Add a dedicated containerized kanidm oauth2-proxy (jfly pattern, unix socket under `/run/oauth2-proxies/`, `provider = "oidc"`, PKCE `S256`) with `clientSecretFile` reading the bind-mounted `files.secret-proxy`, `cookie.secretFile` reading the cookie secret, `allowed_groups = cognee_access`; do NOT reuse the nixpkgs host singleton.
- [ ] **Step 5:** Add a bespoke host nginx 443 vhost (`forceSSL` + ACME) for `kb.scientistexperience.net` routing `location /` to the loopback frontend `127.0.0.1:3000` and `location /api/` to the ZeroTier REST `[${magnetite.zt}]:9270`, gated by `auth_request`; behind the gate cognee enforces `REQUIRE_AUTHENTICATION` (perimeter + app-auth are defense-in-depth). Confirm buildbot is untouched.

## Phase 9: terranix kb DNS record + ACME (deliverable F-DNS)

- [ ] **Step 1:** Thread `config.flake.lib.cognee.publicFqdn` into the terranix cloudflare module via the existing `config.nix` `let`-binding, and add the `kb` record in `modules/terranix/cloudflare.nix` (CNAME `kb` -> `magnetite.scientistexperience.net`, `ttl = 1`, `proxied = false`), cloned from the niks3/buildbot/git records.
- [ ] **Step 2:** USER-RUN: apply via `just terraform*` (never `nix run .#terraform` directly) and verify ACME issuance, which must land before Phase 8's nginx `forceSSL` can obtain a cert.

## Phase 10: magnetite wiring, clan vars, deploy from the single chain tip, verification

- [ ] **Step 1:** Import any new `flake.modules.nixos.<svc>` on magnetite (`modules/machines/nixos/magnetite/default.nix`); evaluate the NixOS configuration and home-manager activation (the no-public-bind assertion passing); grep the repointed consumers to confirm the IPv6 literal and the cognee MCP literal are gone.
- [ ] **Step 2:** USER-RUN: run `clan vars generate`/`clan vars check` so the `kanidm-oauth2-cognee` generator emits its files (confirm the secret owner matches the consuming unit's `User=`) and the per-host keys are satisfied; the user runs the commands and hands the orchestrator the generated commits to route.
- [ ] **Step 3:** Re-map the diamond before deploy (N can increase between phases) and pin the build+deploy to the single `declarative-cognee-endpoint` chain tip, never the multi-parent `[wip]` (the diamond-wip-deploy-pulls-all-chains hazard: a `[wip]` deploy builds the integrated tree of all active chains).
- [ ] **Step 4:** USER-RUN: deploy magnetite from the pinned chain tip and confirm acceptance: a laptop session reaches central magnetite as its per-host agent (not failing default-user login) and offline-degrades gracefully; the cognee-cli wrapper reaches magnetite with the baked `--api-url`/`--api-key`; `kb.scientistexperience.net` serves the same-origin UI behind the kanidm `cognee_access` gate with a valid cert and `REQUIRE_AUTHENTICATION` enforced; the no-public-bind invariant holds; the cognee MCP is gone on both sides while `ip_nonlocal_bind` is retained; and buildbot is unchanged.

## Rollback

Rollback removes the in-repo modules and `flake.lib` additions; removes the `kb` Cloudflare DNS record via `just terraform*`; removes the `kanidm-oauth2-cognee` generator and explicitly deletes its already-emitted secret files; reverts the cognee-nix input bump in `flake.nix`/`flake.lock`; explicitly deletes the orphaned kanidm OAuth2 client (which `provision.autoRemove = false` preserves); and restores mesh-client reachability coherently by re-adding the MCP client and removing `COGNEE_SERVICE_URL` in the same step (the two are coupled). Buildbot is never affected.
