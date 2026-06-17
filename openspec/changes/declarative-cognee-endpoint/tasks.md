## 1. Source-of-truth nix values (deliverable A)

- [ ] 1.1 Create a single new file declaring `flake.lib.hosts.<host>.zt` with `magnetite.zt = "fddb:4344:343b:14b9:399:930f:39db:40d2"`, as a single-file consolidation per the `lazyAttrsOf raw` constraint
- [ ] 1.2 Add the derived `flake.lib.cognee` record in its own single file: `meshApiUrl = "http://[${magnetite.zt}]:9270"`, `apiPort = 9270`, `publicFqdn = "kb.scientistexperience.net"` — with NO `mcpUrl`/`meshMcpUrl`/`publicMcpUrl` (the MCP is dropped)
- [ ] 1.3 Confirm both additions evaluate without breaking `flake.lib` (`lazyAttrsOf raw`)

## 2. Frontend rebuild (deliverable A-frontend)

- [ ] 2.1 Rebuild the cognee frontend in the cognee-nix fork with `NEXT_PUBLIC_LOCAL_API_URL=""` (build-time inlined) so the browser calls same-origin `/api/` rather than `localhost:8000`
- [ ] 2.2 Drop the module's injected `NEXT_PUBLIC_BACKEND_API_URL` (upstream reads `NEXT_PUBLIC_LOCAL_API_URL`, so the injection is inert)

## 3. Server: bind REST ZeroTier-only, enable loopback frontend, disable server MCP, drop 9271 firewall (deliverables C and B-server)

- [ ] 3.1 In `modules/nixos/cognee.nix`, set the single `types.str` REST listen address to `flake.lib.hosts.magnetite.zt` (instead of `127.0.0.1`, fail-closed, no dual-bind patch) and open port 9270 on the `zt+` interface only (this is the same capability the now-removed MCP proxied unauthenticated over the mesh, by a more direct path)
- [ ] 3.2 Enable the rebuilt frontend bound to loopback `127.0.0.1:3000`, and confirm postgres stays loopback `127.0.0.1:5432`
- [ ] 3.3 Set `services.cognee.mcp.enable = false` in `modules/nixos/cognee.nix`
- [ ] 3.4 Remove the 9271 `zt+` firewall opening (no remaining consumer; codex/opencode declare no cognee MCP)
- [ ] 3.5 Leave the module's built-in `services.cognee.nginx` unused (the bespoke host vhost in §6 fronts the UI)

## 4. Client: drop MCP client config, point the plugin at central magnetite (deliverables B-client and D)

- [ ] 4.1 Remove the cognee entry from `modules/home/ai/claude-code/mcp-servers.nix` so `~/.mcp/cognee.json` is no longer generated, and confirm the hardcoded ZeroTier IPv6 MCP literal no longer appears
- [ ] 4.2 Add a home-manager module exporting `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` via `home.sessionVariables` (always-on global, managed mode, no local fallback); do NOT set `COGNEE_API_KEY` in v1 (cognee app-auth is disabled)
- [ ] 4.3 Confirm the URL is NOT written into `~/.cognee-plugin/config.json` (the plugin's `save_config` strips it); `home.sessionVariables` is the authoritative lever, and the plugin degrades (connects-only, no local fallback) when magnetite is unreachable

## 5. cognee-cli wrapper module (deliverable E)

- [ ] 5.1 Add a home-manager module installing a global cognee-cli wrapper as a `writeShellApplication` over `pkgs.cognee` (the cognee-nix overlay package wired in `modules/nixpkgs/overlays/cognee.nix`) that bakes `--api-url ${flake.lib.cognee.meshApiUrl}` into every invocation (the CLI has no env fallback for `--api-url`)
- [ ] 5.2 Confirm the wrapper is decoupled from the plugin's bundled venv and accept the ~1.5 GiB per-host closure footprint; when a credential is eventually introduced use `--api-key` / `X-Api-Key`, never `--api-token` (Bearer) — in v1 pass no key

## 6. Public UI: secret generator, kanidm client + group, containerized oauth2-proxy, bespoke nginx vhost (deliverable F)

- [ ] 6.1 Add the single clan-vars generator `kanidm-oauth2-cognee` emitting two bare-value files: `files.secret` (owner kanidm) and `files.cookie`, with `restartUnits` on `kanidm.service` and the oauth2-proxy unit; no KEY=VALUE env-file shaping
- [ ] 6.2 Register a new kanidm OAuth2 client via `services.kanidm.provision.systems.oauth2.cognee` with `basicSecretFile` reading `files.secret`, mirroring the synapse client, with `scopeMaps.cognee_access = ["openid" "email" "groups"]` and `claimMaps.groups`
- [ ] 6.3 Define the kanidm stub group `provision.groups.cognee_access = { members = []; overwriteMembers = false; }` with `provision.autoRemove = false`; cameron is added operationally, not declaratively
- [ ] 6.4 Add a dedicated containerized kanidm oauth2-proxy (jfly `oauth2-proxies-nginx` pattern): a NixOS container running its own `services.oauth2-proxy` (`provider = "oidc"`, PKCE) listening on a unix socket, with `clientSecretFile` reading `files.secret` and `cookie.secretFile` reading `files.cookie`; do NOT reuse the nixpkgs host `services.oauth2-proxy` singleton
- [ ] 6.5 Add a bespoke host nginx 443 vhost (`forceSSL` + ACME) for `kb.scientistexperience.net` (NOT `services.cognee.nginx`) routing `location /` to the loopback frontend `127.0.0.1:3000` and `location /api/` to the ZeroTier REST `[${magnetite.zt}]:9270`, gated by `auth_request` against the containerized oauth2-proxy with `allowed_groups=cognee_access`
- [ ] 6.6 Keep the cognee client, group, and generator in the cognee module; `modules/nixos/kanidm.nix` stays a pure IdP scaffold (no edits)
- [ ] 6.7 Confirm buildbot is left entirely untouched: its `accessMode.fullyPrivate` GitHub-backed oauth2-proxy singleton and auth configuration are unchanged

## 7. terranix kb DNS record (deliverable F-DNS)

- [ ] 7.1 Add the `kb` Cloudflare DNS record in `modules/terranix/cloudflare.nix` reading `flake.lib.cognee.publicFqdn` as the source of truth where the terranix eval can reach `flake.lib` (CNAME `kb` -> `magnetite.scientistexperience.net`, `ttl = 1`, `proxied = false`), cloned from the niks3/buildbot/git records; restate the literal ONLY if the `flake.lib` read is verified impossible; apply via `just terraform*` (never `nix run .#terraform` directly)

## 8. magnetite import wiring

- [ ] 8.1 Import any new `flake.modules.nixos.<svc>` on magnetite (`modules/machines/nixos/magnetite/default.nix`)
- [ ] 8.2 Evaluate the magnetite NixOS configuration and the relevant home-manager activation to confirm all consumers resolve the canonical values and the configuration builds
- [ ] 8.3 Grep the repointed consumers to confirm the hardcoded IPv6 literal and the cognee MCP literal no longer appear

## 9. Deploy and verify

- [ ] 9.1 Deploy and confirm a laptop session's always-on plugin (via `home.sessionVariables`) reaches central magnetite over the mesh, and the cognee-cli wrapper reaches magnetite without an explicit `--api-url`, with the local per-laptop fallback eliminated (acceptance criterion: universal KB reachability)
- [ ] 9.2 Confirm `kb.scientistexperience.net` serves the FUNCTIONAL same-origin browser UI behind the kanidm `cognee_access` gate (interactive OIDC SSO) with a valid ACME cert, and that buildbot's oauth2-proxy singleton and auth are left fully untouched (acceptance criterion: public UI gated + buildbot untouched)
- [ ] 9.3 ACCEPTANCE INVARIANT (listener inventory): confirm cognee's REST API binds ZeroTier-only `[${magnetite.zt}]:9270`, the frontend loopback `127.0.0.1:3000`, postgres loopback `127.0.0.1:5432`, and nginx 443 is the only public surface; the public reaches cognee only through nginx then the containerized oauth2-proxy (acceptance criterion: non-public bind verified)
- [ ] 9.4 Confirm the cognee MCP is gone on both sides (no `~/.mcp/cognee.json`, `services.cognee.mcp.enable = false`, no 9271 `zt+` opening), so the central REST API is the only programmatic surface (acceptance criterion: MCP decommissioned)
- [ ] 9.5 Confirm the `kanidm-oauth2-cognee` generator emitted `files.secret`/`files.cookie` with `restartUnits`, and the containerized oauth2-proxy gates via `auth_request` (exit condition: secret and proxy provisioned)
