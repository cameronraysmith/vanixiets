# Declarative single-source cognee endpoint (comprehensive) Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** Make cognee the universal knowledge base accessed via the cognee-cli and the `cognee-memory` plugin (not the MCP), all pointed at one central magnetite cognee through a single declarative nix source of truth, plus a public kanidm-gated browser UI at `kb.scientistexperience.net`. This is one comprehensive change: source of truth + drop the MCP (client and server) + bind REST ZeroTier-only + plugin/CLI pointed at central + a same-origin frontend rebuild + a public kanidm-gated UI fronted by a dedicated containerized oauth2-proxy that leaves buildbot untouched. There is no buildbot prerequisite; only cognee app-level auth, the mesh `X-Api-Key` credential, multi-user public access, and a public machine path remain as deferred future work.

**Architecture:** A two-layer `flake.lib` value (a per-host ZeroTier-address registry plus a derived `flake.lib.cognee` record carrying `meshApiUrl`/`apiPort`/`publicFqdn` and NO MCP URL), each consolidated into its own single file per the `lazyAttrsOf raw` constraint, is read by the cognee server bind, the plugin env, the cognee-cli wrapper, and the public-UI FQDN. The cognee MCP is removed on both sides (client entry plus `~/.mcp/cognee.json`, and `services.cognee.mcp.enable = false` plus the 9271 firewall opening). The cognee REST API (9270, loopback-only today) is bound ZeroTier-only to the magnetite ZeroTier address (single `types.str` listen address, fail-closed) and opened on `zt+`. The frontend is rebuilt in the cognee-nix fork with `NEXT_PUBLIC_LOCAL_API_URL=""` for same-origin `/api/` and bound to loopback `127.0.0.1:3000`. The plugin becomes always-on global via `home.sessionVariables` (managed mode, no key in v1), a global cognee-cli wrapper bakes `--api-url ${meshApiUrl}`, and a dedicated containerized kanidm oauth2-proxy (jfly pattern) plus a bespoke host nginx vhost plus a terranix DNS record provide the public browser UI gated on `cognee_access` group membership, behind a no-public-bind invariant, with buildbot's oauth2-proxy singleton left untouched.

**Tech Stack:** nix flake-parts `flake.lib`, the cognee-nix fork (frontend rebuild), NixOS modules (`modules/nixos/cognee.nix`, a new cognee oauth2-proxy/client/group module using the jfly containerized pattern, nginx, ACME), home-manager (`mcp-servers.nix` edit, a new plugin-env module using `home.sessionVariables`, a new cognee-cli wrapper module over the cognee-nix overlay's `pkgs.cognee`), clan-vars/sops secrets (one generator, two bare-value files), terranix Cloudflare DNS (applied via `just terraform*`).

---

## Task 1: Source-of-truth nix values (deliverable A)

- [ ] **Step 1:** Create a single new file declaring `flake.lib.hosts.<host>.zt` with `magnetite.zt = "fddb:4344:343b:14b9:399:930f:39db:40d2"`, as a single-file consolidation.
- [ ] **Step 2:** Add the derived `flake.lib.cognee` record in its own single file: `meshApiUrl = "http://[${magnetite.zt}]:9270"`, `apiPort = 9270`, `publicFqdn = "kb.scientistexperience.net"`; NO MCP URL of any kind.
- [ ] **Step 3:** Confirm both additions evaluate cleanly under `flake.lib` (`lazyAttrsOf raw`).

## Task 2: Frontend rebuild for same-origin (deliverable A-frontend)

- [ ] **Step 1:** Rebuild the cognee frontend in the cognee-nix fork with `NEXT_PUBLIC_LOCAL_API_URL=""` so the browser calls same-origin `/api/`.
- [ ] **Step 2:** Drop the module's inert `NEXT_PUBLIC_BACKEND_API_URL` injection (upstream reads `NEXT_PUBLIC_LOCAL_API_URL`).

## Task 3: Server — bind REST ZeroTier-only + loopback frontend + disable server MCP + drop 9271 firewall (deliverables C, B-server)

- [ ] **Step 1:** In `modules/nixos/cognee.nix`, set the single `types.str` REST listen address to `flake.lib.hosts.magnetite.zt` instead of `127.0.0.1` (fail-closed) and open port 9270 on the `zt+` interface only.
- [ ] **Step 2:** Enable the rebuilt frontend bound to loopback `127.0.0.1:3000`; confirm postgres stays loopback `127.0.0.1:5432`.
- [ ] **Step 3:** Set `services.cognee.mcp.enable = false`.
- [ ] **Step 4:** Remove the 9271 `zt+` firewall opening; leave `services.cognee.nginx` unused (the bespoke host vhost fronts the UI).

## Task 4: Client — drop MCP client config + point the plugin at central magnetite (deliverables B-client, D)

- [ ] **Step 1:** Remove the cognee entry from `modules/home/ai/claude-code/mcp-servers.nix` so `~/.mcp/cognee.json` is no longer generated; confirm the hardcoded MCP IPv6 literal is gone.
- [ ] **Step 2:** Add a home-manager module exporting `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` via `home.sessionVariables` (always-on global); do NOT set `COGNEE_API_KEY` in v1.
- [ ] **Step 3:** Confirm the URL is NOT written into `~/.cognee-plugin/config.json` (stripped by `save_config`); note the degrade-when-unreachable behavior.

## Task 5: cognee-cli wrapper module (deliverable E)

- [ ] **Step 1:** Add a home-manager module installing a global cognee-cli wrapper as a `writeShellApplication` over `pkgs.cognee` (cognee-nix overlay) that bakes `--api-url ${flake.lib.cognee.meshApiUrl}`.
- [ ] **Step 2:** Confirm the wrapper is decoupled from the plugin's venv and accept the ~1.5 GiB closure footprint; use `--api-key`/`X-Api-Key` (never `--api-token`) if a key is ever added — none in v1.

## Task 6: clan-vars secret generator (deliverable F-secrets)

- [ ] **Step 1:** Add the single clan-vars generator `kanidm-oauth2-cognee` emitting `files.secret` (bare, owner kanidm) and `files.cookie` (bare), with `restartUnits` on `kanidm.service` and the oauth2-proxy unit; no KEY=VALUE env-file shaping.

## Task 7: Public browser UI — kanidm client + group + containerized oauth2-proxy + bespoke nginx vhost (deliverable F)

- [ ] **Step 1:** Register a new kanidm OAuth2 client via `services.kanidm.provision.systems.oauth2.cognee` with `basicSecretFile` reading `files.secret`, mirroring synapse, with `scopeMaps.cognee_access = ["openid" "email" "groups"]` and `claimMaps.groups`.
- [ ] **Step 2:** Define the kanidm stub group `provision.groups.cognee_access = { members = []; overwriteMembers = false; }` with `provision.autoRemove = false`; add cameron operationally.
- [ ] **Step 3:** Add a dedicated containerized kanidm oauth2-proxy (jfly pattern, unix socket, `provider = "oidc"`, PKCE) with `clientSecretFile` reading `files.secret` and `cookie.secretFile` reading `files.cookie`; do NOT reuse the nixpkgs host singleton.
- [ ] **Step 4:** Add a bespoke host nginx 443 vhost (`forceSSL` + ACME) for `kb.scientistexperience.net` routing `location /` to the loopback frontend `127.0.0.1:3000` and `location /api/` to the ZeroTier REST `[${magnetite.zt}]:9270`, gated by `auth_request` against the containerized oauth2-proxy with `allowed_groups=cognee_access`.
- [ ] **Step 5:** Keep the cognee client, group, and generator in the cognee module; `kanidm.nix` stays a pure IdP scaffold. Confirm buildbot is untouched.

## Task 8: terranix kb DNS record (deliverable F-DNS)

- [ ] **Step 1:** Add the `kb` Cloudflare DNS record in `modules/terranix/cloudflare.nix` reading `flake.lib.cognee.publicFqdn` where the terranix eval can reach `flake.lib` (CNAME `kb` -> `magnetite.scientistexperience.net`, `ttl = 1`, `proxied = false`), cloned from the niks3/buildbot/git records; restate the literal ONLY if the `flake.lib` read is verified impossible; apply via `just terraform*` (never `nix run .#terraform` directly).

## Task 9: magnetite wiring, deploy, and verification

- [ ] **Step 1:** Import any new `flake.modules.nixos.<svc>` on magnetite (`modules/machines/nixos/magnetite/default.nix`).
- [ ] **Step 2:** Evaluate the magnetite NixOS configuration and the relevant home-manager activation; grep the repointed consumers to confirm the IPv6 literal and the cognee MCP literal are gone.
- [ ] **Step 3:** Deploy and confirm a laptop session reaches central magnetite over the mesh (plugin and cognee-cli wrapper), the same-origin browser UI does kanidm `cognee_access` SSO with a valid cert, the no-public-bind invariant holds (REST ZeroTier-only, frontend and postgres loopback, nginx 443 the sole public surface), and buildbot's oauth2-proxy singleton and auth are unchanged.
