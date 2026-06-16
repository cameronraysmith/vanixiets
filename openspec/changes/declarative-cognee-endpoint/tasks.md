## 1. Source-of-truth nix values (deliverable A)

- [ ] 1.1 Create a single new file declaring `flake.lib.hosts.<host>.zt` with `magnetite.zt = "fddb:4344:343b:14b9:399:930f:39db:40d2"`, as a single-file consolidation per the `lazyAttrsOf raw` constraint
- [ ] 1.2 Add the derived `flake.lib.cognee` record (co-located in one file): `meshApiUrl = "http://[${magnetite.zt}]:9270"`, `apiPort = 9270`, `publicFqdn = "kb.scientistexperience.net"`, and any other derived fields — with NO `mcpUrl`/`meshMcpUrl`/`publicMcpUrl` (the MCP is dropped)
- [ ] 1.3 Confirm both additions evaluate without breaking `flake.lib` (`lazyAttrsOf raw`)

## 2. Server: expose REST over ZeroTier, disable server MCP, drop 9271 firewall (deliverables C and B-server)

- [ ] 2.1 In `modules/nixos/cognee.nix`, bind the REST API listen address to `flake.lib.hosts.magnetite.zt` (instead of `127.0.0.1`) and open port 9270 on the `zt+` interface (this is the same capability the now-removed MCP proxied unauthenticated over the mesh, by a more direct path)
- [ ] 2.2 Set `services.cognee.mcp.enable = false` in `modules/nixos/cognee.nix`
- [ ] 2.3 Remove the 9271 `zt+` firewall opening (no remaining consumer; codex/opencode declare no cognee MCP)

## 3. Client: drop MCP client config, point the plugin at central magnetite (deliverables B-client and D)

- [ ] 3.1 Remove the cognee entry from `modules/home/ai/claude-code/mcp-servers.nix` so `~/.mcp/cognee.json` is no longer generated, and confirm the hardcoded ZeroTier IPv6 MCP literal no longer appears
- [ ] 3.2 Add a home-manager module exporting `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` via `home.sessionVariables` (always-on global, managed mode, no local fallback); do NOT set `COGNEE_API_KEY` in v1 (cognee app-auth is disabled)
- [ ] 3.3 Confirm the URL is NOT written into `~/.cognee-plugin/config.json` (the plugin's `save_config` strips it); `home.sessionVariables` is the authoritative lever, and the plugin degrades (connects-only, no local fallback) when magnetite is unreachable

## 4. cognee-cli wrapper module (deliverable E)

- [ ] 4.1 Add a home-manager module installing a global cognee-cli wrapper as a `writeShellApplication` over `pkgs.cognee` (the cognee-nix overlay package wired in `modules/nixpkgs/overlays/cognee.nix`) that bakes `--api-url ${flake.lib.cognee.meshApiUrl}` into every invocation (the CLI has no env fallback for `--api-url`)
- [ ] 4.2 Confirm the wrapper is decoupled from the plugin's bundled venv and accept the ~1.5 GiB per-host closure footprint; when a credential is eventually introduced use `--api-key` / `X-Api-Key`, never `--api-token` (Bearer) — in v1 pass no key

## 5. Public UI: frontend, nginx, oauth2-proxy, kanidm client, clan-vars secrets (deliverable F)

- [ ] 5.1 Add a clan-vars generator for the kanidm oauth2 client secret, mirroring the synapse generator naming (`kanidm-oauth2-synapse`)
- [ ] 5.2 Add a clan-vars generator for the oauth2-proxy cookie secret
- [ ] 5.3 Register a new kanidm OAuth2 client via `services.kanidm.provision.systems.oauth2.<name>` with a `basicSecretFile` from §5.1, mirroring synapse
- [ ] 5.4 Enable the cognee frontend (`frontend.enable = true`) and add a kanidm-OIDC-backed oauth2-proxy that proxies to cognee on loopback, with the allowlist restricted to cameron's identity (email or kanidm group)
- [ ] 5.5 Add an nginx vhost (`forceSSL` + ACME) for `kb.scientistexperience.net` delegating to the oauth2-proxy, using the existing `services.cognee.nginx.enable` + `nginx.domain` scaffolding, mirroring the buildbot/gitea/niks3 public-vhost pattern

## 6. terranix kb DNS record (deliverable F-DNS)

- [ ] 6.1 Add the `kb` Cloudflare DNS record in `modules/terranix/cloudflare.nix` (CNAME `kb` -> `magnetite.scientistexperience.net`, `ttl = 1`, `proxied = false`), cloned from the niks3/buildbot/git records; apply via `just terraform*` (never `nix run .#terraform` directly)

## 7. magnetite import wiring

- [ ] 7.1 Import any new `flake.modules.nixos.<svc>` on magnetite (`modules/machines/nixos/magnetite/default.nix`)
- [ ] 7.2 Evaluate the magnetite NixOS configuration and the relevant home-manager activation to confirm all consumers resolve the canonical values and the configuration builds
- [ ] 7.3 Grep the repointed consumers to confirm the hardcoded IPv6 literal and the cognee MCP literal no longer appear

## 8. Deploy and verify

- [ ] 8.1 Deploy and confirm a laptop session's always-on plugin (via `home.sessionVariables`) reaches central magnetite over the mesh, and the cognee-cli wrapper reaches magnetite without an explicit `--api-url`
- [ ] 8.2 Confirm `kb.scientistexperience.net` serves the cognee browser UI behind the kanidm gate (browser SSO) with a valid ACME cert
- [ ] 8.3 ACCEPTANCE INVARIANT: confirm cognee's REST API and frontend are bound ONLY to loopback (for the proxy) and to `flake.lib.hosts.magnetite.zt` (for machine clients), and never to a public interface; the public reaches cognee only through nginx then oauth2-proxy
- [ ] 8.4 Confirm the cognee MCP is gone on both sides (no `~/.mcp/cognee.json`, `services.cognee.mcp.enable = false`, no 9271 `zt+` opening)
