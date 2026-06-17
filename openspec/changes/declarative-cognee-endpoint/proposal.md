---
linear_story_id: 46d87b5c-3408-4534-9230-d85a58a7f112
linear_story_identifier: CAM-18
linear_story_title: "Utilize cognee server on magnetite host exclusively as backend for other agents"
linear_story_url: "https://linear.app/cameronraysmith/issue/CAM-18/utilize-cognee-server-on-magnetite-host-exclusively-as-backend-for"
linear_story_state: Todo
linear_team: CAM
linear_project: cognee-memory-layer
last_synced_state: Todo
last_synced_at: "2026-06-17T19:51:45Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-06-17T19:51:45Z", transition: "Backlog->Todo", outcome: "posted", note: "bind CAM-18; seed issue description from proposal; set Todo" }
---

## Why

Cognee should be the universal knowledge base for the fleet, accessed through the cognee-cli and the `cognee-memory` plugin, all pointed at one central magnetite cognee via a single declarative nix source of truth, plus a public kanidm-gated browser UI.
Today this is blocked by an MCP detour: the cognee MCP (port 9271, bound to magnetite's ZeroTier IPv6) is the only mesh-facing surface and it proxies, unauthenticated, to a loopback-only REST API (port 9270, `127.0.0.1`, firewall closed).
The Claude Code MCP client hardcodes that ZeroTier IPv6 MCP literal, while the cognee plugin cannot reach magnetite at all and falls back to a local per-laptop cognee.
The decided path is to abandon the cognee MCP entirely (client and server), expose the REST API directly over the mesh bound ZeroTier-only, point the plugin and a global cognee-cli at it through one nix source of truth, and add a kanidm-gated browser UI fronted by a dedicated containerized oauth2-proxy that leaves buildbot's existing oauth2-proxy singleton fully untouched.

## What Changes

This is one comprehensive change that makes cognee the universal knowledge base via the CLI and the plugin (not the MCP), with a public browser UI.
It establishes a single typed nix source of truth, drops the cognee MCP on both sides, exposes the REST API bound ZeroTier-only, points the always-on plugin and a new global cognee-cli wrapper at central magnetite, and adds a kanidm-gated public UI at `kb.scientistexperience.net`.
There is no Phase-1/Phase-2 split and no buildbot prerequisite change; only cognee app-level auth, the mesh `X-Api-Key` credential, multi-user public access, and a public machine path remain as deferred future work.

**Cognee endpoint source of truth**
- From: a hardcoded ZeroTier IPv6 MCP literal `http://[fddb:4344:343b:14b9:399:930f:39db:40d2]:9271/mcp` in `mcp-servers.nix` and a separately restated address in the cognee server and firewall, with no shared nix value.
- To: a typed two-layer nix value (`flake.lib.hosts.<host>.zt` host registry plus a derived `flake.lib.cognee` record carrying `meshApiUrl`, `apiPort`, `publicFqdn`; no MCP URL) consumed by the cognee server bind, the plugin env, the CLI wrapper, and the public-UI FQDN.
- Reason: one canonical endpoint feeding every consumer, with the recurring literal eliminated.
- Impact: additive nix values, each consolidated into a single file because `flake.lib` is `lazyAttrsOf raw`; consumers read the new value.

**Drop the cognee MCP entirely (client and server)**
- From: an MCP client entry in `mcp-servers.nix` that generates `~/.mcp/cognee.json`, and a server-side MCP (`services.cognee.mcp`) bound to ZeroTier with port 9271 opened on `zt+`.
- To: remove the cognee entry from `mcp-servers.nix` (no `~/.mcp/cognee.json`), set `services.cognee.mcp.enable = false`, and remove the 9271 `zt+` firewall opening.
- Reason: the MCP detour is abandoned; the plugin and CLI talk REST directly, and codex/opencode declare no cognee MCP, so nothing consumes the server MCP after the client is dropped.
- Impact: removes the auth-less mesh MCP transport; its REST capability is preserved by exposing REST directly over the mesh.

**Expose the cognee REST API bound ZeroTier-only**
- From: the REST API binds `127.0.0.1` (loopback-only) with the firewall closed, unreachable over the mesh.
- To: bind the single `types.str` REST listen address to `flake.lib.hosts.magnetite.zt` (fail-closed, no dual-bind patch) and open port 9270 on the `zt+` interface only.
- Reason: this is what lets the plugin and CLI reach magnetite over the mesh; it does not widen the attack surface, since the now-removed MCP already proxied full REST capability unauthenticated over the same mesh.
- Impact: REST is reachable from mesh members; never from the public internet.

**Plugin and CLI pointed at central magnetite**
- From: the plugin bootstraps a local per-laptop cognee; there is no global cognee-cli pointed at magnetite.
- To: set `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` via `home.sessionVariables` (always-on global, managed mode, no local fallback, no `COGNEE_API_KEY` in v1 since auth is disabled), and install a global cognee-cli `writeShellApplication` wrapper over `pkgs.cognee` that bakes `--api-url ${flake.lib.cognee.meshApiUrl}` into every invocation (the CLI has no env fallback for `--api-url`).
- Reason: every session defaults to the central graph through the plugin, with the CLI as the manual/explicit and debugging path.
- Impact: additive home-manager modules; the plugin degrades gracefully when magnetite is unreachable.

**Public kanidm-gated browser UI**
- To: rebuild the cognee frontend in the cognee-nix fork with `NEXT_PUBLIC_LOCAL_API_URL=""` so it calls same-origin `/api/`, run it on loopback `127.0.0.1:3000`, and serve it through a bespoke host nginx 443 vhost at `kb.scientistexperience.net` that routes `location /` to the loopback frontend and `location /api/` to the ZeroTier REST API, gated by `auth_request` against a dedicated containerized kanidm oauth2-proxy.
- Reason: cognee has no native OIDC and its SPA fails open with app-auth off, so a kanidm perimeter is the sole access-control layer; buildbot already owns the host oauth2-proxy singleton, so the cognee proxy must be containerized and independent.
- Impact: a new dedicated containerized oauth2-proxy, a new kanidm OAuth2 client plus `cognee_access` group, one clan-vars generator emitting two secret files, one new DNS record, and a host nginx vhost; buildbot is left entirely untouched.

## Capabilities

### New Capabilities
- `cognee-knowledge-base`: a single canonical nix source of truth for the cognee endpoint consumed by the cognee server bind, the always-on plugin env, a global cognee-cli wrapper, and the public-UI FQDN; the cognee MCP dropped on both sides; the REST API bound ZeroTier-only; the plugin and CLI pointed at central magnetite; a kanidm-gated public browser UI served by a bespoke nginx vhost over a dedicated containerized oauth2-proxy; and the no-public-bind security invariant with app-auth off and buildbot left untouched.

### Modified Capabilities
<!-- None. This change introduces a new capability; no existing capability's requirements change. -->

## Impact

Consumers and files updated: a single new file for the `flake.lib.hosts.<host>.zt` registry and a single new file for the derived `flake.lib.cognee` record (each one file per the `lazyAttrsOf raw` constraint), `modules/home/ai/claude-code/mcp-servers.nix` (remove the cognee entry, stop generating `~/.mcp/cognee.json`), a new home-manager module exporting `COGNEE_SERVICE_URL` via `home.sessionVariables`, a new home-manager module installing the cognee-cli wrapper, the cognee-nix fork (rebuild the frontend with `NEXT_PUBLIC_LOCAL_API_URL=""`), `modules/nixos/cognee.nix` (bind REST to ZeroTier and open 9270 on `zt+`, set `mcp.enable = false`, remove the 9271 opening, enable the frontend on loopback, drop the inert `NEXT_PUBLIC_BACKEND_API_URL` injection, leave the module's built-in `services.cognee.nginx` unused), a new cognee module owning its dedicated containerized kanidm oauth2-proxy plus the `provision.systems.oauth2.cognee` client and the `cognee_access` group, the bespoke host nginx vhost for `kb.scientistexperience.net`, `modules/terranix/cloudflare.nix` (the `kb` DNS record reading `flake.lib.cognee.publicFqdn` where reachable), `modules/machines/nixos/magnetite/default.nix` (import any new `flake.modules.nixos.<svc>`), and a single clan-vars generator `kanidm-oauth2-cognee` emitting `files.secret` and `files.cookie`.
Buildbot's `accessMode.fullyPrivate` GitHub-backed oauth2-proxy singleton and its auth configuration are left entirely untouched; no buildbot change and no buildbot prerequisite exist.
Out of scope (deferred future work): cognee app-level auth plus the mesh `X-Api-Key` credential; multi-user public access or cognee native OIDC; a public machine path (public CLI access with a bearer), moot for now since machines use the mesh.
