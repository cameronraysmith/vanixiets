## 1. Source-of-truth nix values (deliverable A)

- [x] 1.1 Create a single new file declaring `flake.lib.hosts.<host>.zt` with `magnetite.zt = "fddb:4344:343b:14b9:399:930f:39db:40d2"`, as a single-file consolidation per the `lazyAttrsOf raw` constraint
- [x] 1.2 Add the derived `flake.lib.cognee` record in its own single file: `meshApiUrl = "http://[${magnetite.zt}]:9270"`, `apiPort = 9270`, `publicFqdn = "kb.scientistexperience.net"`, `userEmail = "cameron@scientistexperience.net"` — with NO `mcpUrl`/`meshMcpUrl`/`publicMcpUrl` (the MCP is dropped)
- [x] 1.3 Confirm both additions evaluate without breaking `flake.lib` (`lazyAttrsOf raw`)

## 2. Cross-repo cognee-nix fork prerequisite (deliverable A-frontend, D11)

This whole section is a sequenced PREREQUISITE that touches a separate repository and a flake-input bump; it MUST land before the in-repo frontend-enable config (§4.2) can reference the rebuilt bundle.

- [ ] 2.1 In the cognee-nix fork, edit `packages/cognee-frontend/default.nix` `buildPhase` to export `NEXT_PUBLIC_LOCAL_API_URL=""` (it currently exports none), so the bundle calls same-origin `/api/` rather than a literal `localhost` backend URL
- [ ] 2.2 Recompute the FOD hashes for the rebuilt frontend derivation
- [ ] 2.3 Push the `cognee-v112` branch with the `buildPhase` edit
- [ ] 2.4 Bump the cognee-nix input in vanixiets `flake.nix`/`flake.lock` to the pushed `cognee-v112` revision
- [ ] 2.5 Confirm the built frontend bundle contains no literal `localhost` backend URL (falsifiable check)

## 3. cli existence precondition (deliverable E precondition, PL8)

- [ ] 3.1 Build `pkgs.cognee` (the cognee-nix overlay package) and confirm `bin/cognee-cli --help` lists `--api-url` and `--api-key` BEFORE the wrapper module (§7) is authored
  - Source-verified (build deferred to remote builder): `pkgs.cognee` is the cognee-nix overlay package (`inputs.cognee-nix.overlays.default` registered via `nixpkgsOverlays`, exposing `python-final.cognee` as top-level `cognee`); the v1.1.2 CLI entrypoint `cognee/cli/_cognee.py` declares `--api-url` and `--api-key` (the latter "sent as X-Api-Key ... Falls back to $COGNEE_API_KEY") on the top-level argparse parser, before its subparsers; `cognee/cli/api_dispatch.py` confirms the `X-Api-Key` header. A built `cognee-1.1.2` store path exposes the binary named exactly `cognee-cli` with no `meta.mainProgram`. Checkbox left unticked because its literal text requires a `--help` build confirmation, which the orchestrator/remote builder owns.

## 4. Server: REQUIRE_AUTHENTICATION, REST ZeroTier bind, no-public-bind assertion, MCP teardown, loopback frontend (deliverables C, B-server; POSTURE-A, PL2, PL4, PL6, PL7)

- [x] 4.1 In `modules/nixos/cognee.nix`, set `services.cognee.settings.REQUIRE_AUTHENTICATION = "true"` (rendered last into the unit env, overriding base env, zero fork change), keeping `auth.multiTenant = false` so `ENABLE_BACKEND_ACCESS_CONTROL` resolves `false` [POSTURE-A]
  - Added `settings.REQUIRE_AUTHENTICATION = "true"` to the existing `services.cognee.settings` attrset; `auth.multiTenant = false` retained unchanged.
- [x] 4.2 Set the single `types.str` REST listen address to `flake.lib.hosts.magnetite.zt` (fail-closed, no dual-bind patch) and open port 9270 on the `zt+` interface only; the full REST surface on the mesh DOES widen the surface vs the 12-tool MCP, mitigated by REQUIRE_AUTHENTICATION (every caller needs a key) [PL2]
  - `listenAddress = magnetite.zt` (bound at outer scope via `inherit (config.flake.lib.hosts) magnetite;`, no literal restated); `networking.firewall.interfaces."zt+".allowedTCPPorts = [ 9270 ]`.
- [x] 4.3 Add a NixOS `assertion` failing the build if `cfg.listenAddress`, the frontend `listenAddress`, or the postgres listen address resolves to anything other than loopback (`127.0.0.1`/`::1`) or the ZeroTier prefix (`fddb:4344:343b:14b9::/64`); required because the retained `ip_nonlocal_bind=1` makes a wrong bind silent [PL4]
  - `assertions` entry over `isLoopbackOrMesh` of `services.cognee.listenAddress`, `services.cognee.frontend.listenAddress`, and `services.postgresql.settings.listen_addresses`; predicate admits `127.0.0.1`/`::1`/`hasPrefix "fddb:4344:343b:14b9:"`. Build-verification (assertion passes for the ZT/loopback config) deferred to §10.2 (orchestrator/remote builder).
- [ ] 4.4 Enable the rebuilt frontend bound to loopback `127.0.0.1:3000`, drop the inert `NEXT_PUBLIC_BACKEND_API_URL` injection (upstream reads `NEXT_PUBLIC_LOCAL_API_URL`), and confirm postgres stays loopback `127.0.0.1:5432` [PL7 in-repo half] (deferred → §8/§2: frontend.package unbuildable at current pin)
  - `frontend.enable = true` (upstream `frontend.listenAddress`/`port` defaults are already `127.0.0.1`/`3000`). The `NEXT_PUBLIC_BACKEND_API_URL` injection is a PHANTOM in-repo: the vanixiets module never set `frontend.backendApiUrl`, so there was nothing to delete (`rg -i 'NEXT_PUBLIC_BACKEND_API_URL|backendApiUrl' .` hits only the openspec change docs). Postgres stays loopback (`settings.listen_addresses = lib.mkForce "127.0.0.1"`, unchanged).
- [x] 4.5 Set `services.cognee.mcp.enable = false`
- [x] 4.6 Remove the 9271 `zt+` firewall opening (no remaining consumer; codex/opencode declare no cognee MCP)
  - The `allowedTCPPorts` list now holds `[ 9270 ]` only; the `[ 9271 ]` opening is gone.
- [x] 4.7 Remove the orphaned `cognee-mcp` systemd stanzas (`MCP_DISABLE_DNS_REBINDING_PROTECTION` and the per-service `serviceConfig` capability tightening), but RETAIN the `ip_nonlocal_bind` sysctl and rewrite its comment to describe the REST ZeroTier bind (now load-bearing for the REST bind, not the MCP) — do NOT delete this sysctl [PL6]
  - Removed `systemd.services.cognee-mcp.environment.MCP_DISABLE_DNS_REBINDING_PROTECTION` and `systemd.services.cognee-mcp.serviceConfig`; also dropped the now-orphaned `mcp.transport`/`mcp.port`/`mcp.listenAddress`. Retained both `net.ipv{4,6}.ip_nonlocal_bind = 1` with the comment rewritten to describe the REST ZeroTier bind. `rg 'cognee-mcp|9271|MCP_DISABLE_DNS_REBINDING_PROTECTION'` over the module returns nothing.
- [x] 4.8 Leave the module's built-in `services.cognee.nginx` unused (the bespoke host vhost in §8 fronts the UI)
  - `services.cognee.nginx` is not enabled or referenced anywhere in the module.

## 5. Client: drop MCP client, non-secret plugin env + per-host namespacing, secure key delivery (deliverables B-client, D; POSTURE-B, PL1, PL9)

- [x] 5.1 Remove the cognee entry from `modules/home/ai/claude-code/mcp-servers.nix` so `~/.mcp/cognee.json` is no longer generated, and confirm the hardcoded ZeroTier IPv6 MCP literal no longer appears
- [x] 5.2 Add a home-manager module exporting the non-secret plugin env via `home.sessionVariables`: `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` (HTTP mode so per-host identity is real), per-host `COGNEE_PLUGIN_DATASET` and `COGNEE_AGENT_NAME` (overriding the hardcoded `claude_sessions`/node_set defaults — do NOT claim "no hardcoded dataset names"), and `COGNEE_USER_EMAIL = cameron@scientistexperience.net` (the plugin default `default_user@example.com` would not match the server) [PL9]
- [x] 5.3 Deliver the per-host `X-Api-Key` via a sops-nix home-manager secret consumed as `COGNEE_API_KEY` (NOT plaintext `home.sessionVariables`, which is world-readable); the same secret is consumed by the cognee-cli wrapper (§7) [POSTURE-B, PL1]
- [x] 5.4 Confirm the URL and key are NOT written into `~/.cognee-plugin/config.json` (the plugin strips those keys); `home.sessionVariables` plus the sops-nix secret are the authoritative levers, and the plugin degrades (connects-only, no local fallback) when magnetite is unreachable

## 6. One-time per-host X-Api-Key mint bootstrap (POSTURE-B, PL1) — USER-RUN

- [ ] 6.1 USER-RUN: once the server (§4) is deployed and reachable, log in as the cognee default/owner user `cameron@scientistexperience.net` with the existing clan-vars `cognee-default-user-password`, then `POST /api/v1/auth/api-keys` once per fleet client to mint one scoped per-host key (documented manual/clan-vars bootstrap; the mint requires a live authenticated server session, so it is not an automatic generator output)
- [ ] 6.2 USER-RUN: store each minted scoped key per host in clan-vars (`clan vars` set), so §5.3's sops-nix delivery has a value to deliver

## 7. cognee-cli wrapper module (deliverable E, PL3) — after §3 precondition

- [x] 7.1 Add a home-manager module installing a global cognee-cli wrapper as a `writeShellApplication` whose binary is named exactly `cognee-cli` and which execs `${pkgs.cognee}/bin/cognee-cli` directly (NOT `lib.getExe`, which fails because `pkgs.cognee` has no `meta.mainProgram`), baking `--api-url ${flake.lib.cognee.meshApiUrl}` (the CLI has no env fallback for `--api-url`) and passing `--api-key` (sent as `X-Api-Key`, NEVER `--api-token`/Bearer) from the secure sops-nix secret, then forwarding `"$@"` [PL3]
  - Implemented in `modules/home/ai/cognee/cognee-cli-wrapper.nix` (`flake.modules.homeManager.ai`, sibling to `default.nix`); `pkgs.writeShellApplication` named `cognee-cli`, execs `${pkgs.cognee}/bin/cognee-cli` directly, bakes `--api-url "${flake.lib.cognee.meshApiUrl}"` and reads `--api-key` at runtime from `config.sops.secrets."cognee-api-key".path` (no plaintext in the store), baked optionals precede `"$@"` so they sit ahead of the subcommand token. Embedded script shellcheck-clean.
- [x] 7.2 Confirm the wrapper is decoupled from the plugin's bundled venv and accept the ~1.5 GiB per-host closure footprint; the plugin skills/agent hardcode the `cognee-cli` name on `PATH`, which this wrapper satisfies
  - The wrapper is a standalone `home.packages` entry referencing `pkgs.cognee` (the overlay package), independent of any plugin venv; its binary name is exactly `cognee-cli`, satisfying the name the plugin skills/agent hardcode on `PATH`. The ~1.5 GiB closure is accepted per design.md [Trade-off].

## 8. Public UI: kanidm plumbing in kanidm.nix, dual-context secret, containerized oauth2-proxy, bespoke nginx vhost (deliverable F; D9, D12, PL5, PL11, PL12, PL15)

The kanidm group stub MUST be declared before its scopeMap; DNS+ACME (§9) must land before nginx `forceSSL` resolves.

- [ ] 8.1 In `modules/nixos/kanidm.nix` (alongside the live synapse precedent), declare the `provision.groups.cognee_access = { members = []; overwriteMembers = false; }` stub with `provision.autoRemove = false` BEFORE any scopeMap references it (satisfying the `kanidm.nix:876` referential-integrity assertion); cameron is added operationally, not declaratively [PL11]
- [ ] 8.2 In `modules/nixos/kanidm.nix`, register `provision.systems.oauth2.cognee` with `basicSecretFile` reading `files.secret`, `scopeMaps.cognee_access = ["openid" "email" "groups"]`, and `claimMaps.groups` (a NEW requirement — synapse uses no `claimMaps` — needed so oauth2-proxy's `allowed_groups` can read group membership from the token) [PL11]
- [ ] 8.3 In `modules/nixos/kanidm.nix`, add the single `kanidm-oauth2-cognee` clan-vars generator emitting two ownership-correct client-secret files — `files.secret` (owner `kanidm`, for kanidm-provision's `basicSecretFile`) and `files.secret-proxy` (owner the oauth2-proxy container's runtime uid, bind-mounted as `clientSecretFile`) — plus a cookie secret of exactly 16/24/32 bytes (mirror `openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32`); every emitted file `mode = "0400"` and `secret = true`; `restartUnits = [ "kanidm.service" "container@oauth2-proxy-cognee.service" ]` [PL5, PL12, PL15]
- [ ] 8.4 Document the exact bind-mount path and the container uid mapping for `files.secret-proxy` against the NixOS-container's runtime user, confirmed at implementation time [PL5]
- [ ] 8.5 Add a dedicated containerized kanidm oauth2-proxy (jfly `oauth2-proxies-nginx` pattern): a NixOS container running its own `services.oauth2-proxy` (`provider = "oidc"`, PKCE via `code-challenge-method = "S256"`) listening on a unix socket under `/run/oauth2-proxies/`, with `clientSecretFile` reading the bind-mounted `files.secret-proxy` and `cookie.secretFile` reading the cookie secret, `allowed_groups = cognee_access`; do NOT reuse the nixpkgs host `services.oauth2-proxy` singleton (buildbot owns it)
- [ ] 8.6 Add a bespoke host nginx 443 vhost (`forceSSL` + ACME) for `kb.scientistexperience.net` (NOT `services.cognee.nginx`) routing `location /` to the loopback frontend `127.0.0.1:3000` and `location /api/` to the ZeroTier REST `[${magnetite.zt}]:9270`, gated by `auth_request` against the containerized oauth2-proxy; behind the gate cognee enforces `REQUIRE_AUTHENTICATION` as the default/owner user, so perimeter + app-auth are defense-in-depth
- [ ] 8.7 Confirm buildbot is left entirely untouched: its `accessMode.fullyPrivate` GitHub-backed oauth2-proxy singleton and auth configuration are unchanged
- [ ] 8.8 (Optional, NOT required) record the ZeroTier-bound nginx path-allowlist reverse proxy (expose only `remember`/`recall`/`search`/`cognify`/`add`; deny `users`/`permissions`/`settings`/`delete`/`sync`) as defense-in-depth, not a v1 deliverable [PL2]

## 9. terranix kb DNS record + ACME (deliverable F-DNS, PL13) — USER-RUN apply

DNS + ACME must land before §8.6's nginx `forceSSL` can obtain a cert.

- [ ] 9.1 Thread `config.flake.lib.cognee.publicFqdn` into the terranix cloudflare module via the module's existing `config.nix` `let`-binding (the eval that constructs the terranix config from flake-level values), so the `kb` record reads the source of truth rather than restating the literal [PL13]
- [ ] 9.2 Add the `kb` Cloudflare DNS record in `modules/terranix/cloudflare.nix` (CNAME `kb` -> `magnetite.scientistexperience.net`, `ttl = 1`, `proxied = false` so ACME works), cloned from the niks3/buildbot/git records
- [ ] 9.3 USER-RUN: apply via `just terraform*` (never `nix run .#terraform` directly) and verify ACME issuance for `kb.scientistexperience.net`

## 10. magnetite import wiring

- [ ] 10.1 Import any new `flake.modules.nixos.<svc>` on magnetite (`modules/machines/nixos/magnetite/default.nix`)
- [ ] 10.2 Evaluate the magnetite NixOS configuration and the relevant home-manager activation to confirm all consumers resolve the canonical values and the configuration builds (including the no-public-bind assertion passing)
- [ ] 10.3 Grep the repointed consumers to confirm the hardcoded IPv6 literal and the cognee MCP literal no longer appear

## 11. clan vars generate/check (POSTURE-B, PL5) — USER-RUN

- [ ] 11.1 USER-RUN: run `clan vars generate` so the `kanidm-oauth2-cognee` generator emits `files.secret`/`files.secret-proxy`/the cookie secret, and confirm the secret owner (`kanidm` for `files.secret`) matches the consuming unit's `User=`; the user runs the command and hands the orchestrator the generated commits to route
- [ ] 11.2 USER-RUN: run `clan vars check` to confirm all generators (including the per-host key from §6) are satisfied

## 12. Deploy from the single chain tip (D13, PL10) — USER-RUN deploy

- [ ] 12.1 Re-map the diamond before the deploy phase (N can increase between phases) and pin the build+deploy to the single `declarative-cognee-endpoint` chain tip, NEVER the multi-parent `@` `[wip]` (cite the diamond-wip-deploy-pulls-all-chains hazard: a `[wip]` deploy builds the integrated tree of all active chains) [PL10]
- [ ] 12.2 USER-RUN: build and deploy magnetite from the pinned chain tip

## 13. Verify

- [ ] 13.1 Confirm a laptop session's always-on plugin connects to central magnetite over the mesh as its per-host agent (presenting `COGNEE_AGENT_NAME`, authenticated with the per-host `X-Api-Key` and `COGNEE_USER_EMAIL`) rather than failing the default-user login, and unions recall across the single human's datasets [PL1]
- [ ] 13.2 Run an offline-session smoke check confirming the always-on plugin degrades gracefully (connects-only, no local-server boot) when magnetite is unreachable [PL16]
- [ ] 13.3 Confirm the cognee-cli wrapper (named `cognee-cli`) reaches magnetite with the baked `--api-url` and the per-host `--api-key`
- [ ] 13.4 Confirm `kb.scientistexperience.net` serves the FUNCTIONAL same-origin browser UI behind the kanidm `cognee_access` gate with a valid ACME cert and `REQUIRE_AUTHENTICATION` enforced behind it, and that buildbot's oauth2-proxy singleton and auth are left fully untouched
- [ ] 13.5 ACCEPTANCE INVARIANT (listener inventory): confirm the build asserts cognee's REST API binds ZeroTier-only `[${magnetite.zt}]:9270`, the frontend loopback `127.0.0.1:3000`, postgres loopback `127.0.0.1:5432`, and nginx 443 is the only public surface, reaching cognee only through nginx then the containerized oauth2-proxy [PL4]
- [ ] 13.6 Confirm the cognee MCP is gone on both sides (no `~/.mcp/cognee.json`, `services.cognee.mcp.enable = false`, no 9271 `zt+` opening, no orphaned `cognee-mcp` stanzas) while the `ip_nonlocal_bind` sysctl is retained for the REST bind [PL6]
