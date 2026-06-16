## Why

Cognee should be the universal knowledge base for the fleet, accessed through the cognee-cli and the `cognee-memory` plugin, all pointed at one central magnetite cognee via a single declarative nix source of truth, plus a public kanidm-gated browser UI.
Today this is blocked by an MCP detour: the cognee MCP (port 9271, bound to magnetite's ZeroTier IPv6) is the only mesh-facing surface and it proxies, unauthenticated, to a loopback-only REST API (port 9270, `127.0.0.1`, firewall closed).
The Claude Code MCP client hardcodes that ZeroTier IPv6 MCP literal, while the cognee plugin cannot reach magnetite at all and falls back to a local per-laptop cognee.
The decided path is to abandon the cognee MCP entirely (client and server), expose the REST API directly over the mesh, point the plugin and a global cognee-cli at it through one nix source of truth, and add a kanidm-gated browser UI.

## What Changes

This is one comprehensive change that makes cognee the universal knowledge base via the CLI and the plugin (not the MCP), with a public browser UI.
It establishes a single typed nix source of truth, drops the cognee MCP on both sides, exposes the REST API over ZeroTier, points the always-on plugin and a new global cognee-cli wrapper at central magnetite, and adds a kanidm-gated public UI at `kb.scientistexperience.net`.
There is no Phase-1/Phase-2 split; only cognee app-level auth, the mesh `X-Api-Key` credential, multi-user public access, and a public machine path remain as deferred future work.

**Cognee endpoint source of truth**
- From: a hardcoded ZeroTier IPv6 MCP literal `http://[fddb:4344:343b:14b9:399:930f:39db:40d2]:9271/mcp` in `mcp-servers.nix` and a separately restated address in the cognee server and firewall, with no shared nix value.
- To: a typed two-layer nix value (`flake.lib.hosts.<host>.zt` host registry plus a derived `flake.lib.cognee` record carrying `meshApiUrl`, `apiPort`, `publicFqdn`; no MCP URL) consumed by the cognee server bind, the plugin env, the CLI wrapper, and the public-UI FQDN.
- Reason: one canonical endpoint feeding every consumer, with the recurring literal eliminated.
- Impact: additive nix values; consumers read the new value.

**Drop the cognee MCP entirely (client and server)**
- From: an MCP client entry in `mcp-servers.nix` that generates `~/.mcp/cognee.json`, and a server-side MCP (`services.cognee.mcp`) bound to ZeroTier with port 9271 opened on `zt+`.
- To: remove the cognee entry from `mcp-servers.nix` (no `~/.mcp/cognee.json`), set `services.cognee.mcp.enable = false`, and remove the 9271 `zt+` firewall opening.
- Reason: the MCP detour is abandoned; the plugin and CLI talk REST directly, and codex/opencode declare no cognee MCP, so nothing consumes the server MCP after the client is dropped.
- Impact: removes the auth-less mesh MCP transport; its REST capability is preserved by exposing REST directly over the mesh.

**Expose the cognee REST API over ZeroTier**
- From: the REST API binds `127.0.0.1` (loopback-only) with the firewall closed, unreachable over the mesh.
- To: bind the REST API listen address to `flake.lib.hosts.magnetite.zt` and open port 9270 on the `zt+` interface.
- Reason: this is what lets the plugin and CLI reach magnetite over the mesh; it does not widen the attack surface, since the now-removed MCP already proxied full REST capability unauthenticated over the same mesh.
- Impact: REST is reachable from mesh members; never from the public internet.

**Plugin and CLI pointed at central magnetite**
- From: the plugin bootstraps a local per-laptop cognee; there is no global cognee-cli pointed at magnetite.
- To: set `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` via `home.sessionVariables` (always-on global, managed mode, no local fallback, no `COGNEE_API_KEY` in v1 since auth is disabled), and install a global cognee-cli `writeShellApplication` wrapper over `pkgs.cognee` that bakes `--api-url ${flake.lib.cognee.meshApiUrl}` into every invocation (the CLI has no env fallback for `--api-url`).
- Reason: every session defaults to the central graph through the plugin, with the CLI as the manual/explicit and debugging path.
- Impact: additive home-manager modules; the plugin degrades gracefully when magnetite is unreachable.

**Public kanidm-gated browser UI**
- To: enable the cognee frontend, front it with nginx (`forceSSL` plus ACME) delegating to a kanidm-OIDC-backed oauth2-proxy to cognee on loopback at `kb.scientistexperience.net`, restrict the oauth2-proxy allowlist to cameron, register a new kanidm OAuth2 client plus an oauth2-proxy cookie secret as clan-vars, and add a `kb` Cloudflare DNS record via terranix.
- Reason: an authenticated browser UI for the universal knowledge base without exposing any auth-less transport.
- Impact: a new perimeter gate, a new kanidm OAuth2 client, two clan-vars secrets, and one new DNS record.

## Capabilities

### New Capabilities
- `cognee-knowledge-base`: a single canonical nix source of truth for the cognee endpoint consumed by the cognee server bind, the always-on plugin env, a global cognee-cli wrapper, and the public-UI FQDN; the cognee MCP dropped on both sides; the REST API exposed over ZeroTier; the plugin and CLI pointed at central magnetite; a kanidm-gated public browser UI; and the no-public-bind security invariant with app-auth off.

### Modified Capabilities
<!-- None. This change introduces a new capability; no existing capability's requirements change. -->

## Impact

Consumers and files updated: a new single file for the `flake.lib.hosts.<host>.zt` registry and the co-located `flake.lib.cognee` record (per the `lazyAttrsOf raw` single-file constraint), `modules/home/ai/claude-code/mcp-servers.nix` (remove the cognee entry, stop generating `~/.mcp/cognee.json`), a new home-manager module exporting `COGNEE_SERVICE_URL` via `home.sessionVariables`, a new home-manager module installing the cognee-cli wrapper, `modules/nixos/cognee.nix` (bind REST to ZeroTier and open 9270 on `zt+`, set `mcp.enable = false`, remove the 9271 opening, enable the frontend, add the nginx vhost), a new kanidm oauth2-proxy plus OAuth2 client for cognee, `modules/terranix/cloudflare.nix` (the `kb` DNS record), `modules/machines/nixos/magnetite/default.nix` (import any new `flake.modules.nixos.<svc>`), and clan-vars generators for the kanidm oauth2 client secret and the oauth2-proxy cookie secret.
Out of scope (deferred future work): cognee app-level auth plus the mesh `X-Api-Key` credential; multi-user public access or cognee native OIDC; a public machine path (public CLI access with a bearer), moot for now since machines use the mesh.
This change is Linear-skipped: it authors no `linear_*` frontmatter and does not touch `openspec/linear.yaml`.
