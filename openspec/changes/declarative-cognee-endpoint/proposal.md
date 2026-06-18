---
linear_story_id: 46d87b5c-3408-4534-9230-d85a58a7f112
linear_story_identifier: CAM-18
linear_story_title: "Utilize cognee server on magnetite host exclusively as backend for other agents"
linear_story_url: "https://linear.app/cameronraysmith/issue/CAM-18/utilize-cognee-server-on-magnetite-host-exclusively-as-backend-for"
linear_story_state: In Progress
linear_team: CAM
linear_project: cognee-memory-layer
last_synced_state: In Progress
last_synced_at: "2026-06-18T05:17:26Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-06-17T19:51:45Z", transition: "Backlog->Todo", outcome: "posted", note: "bind CAM-18; seed issue description from proposal; set Todo" }
  - { at: "2026-06-18T05:17:26Z", transition: "Todo->In Progress", outcome: "posted", note: "apply gate: first tasks.md checkbox (section 1 source of truth)" }
---

## Why

Cognee should be the universal knowledge base for the fleet, accessed through the cognee-cli and the `cognee-memory` plugin, all pointed at one central magnetite cognee via a single declarative nix source of truth, plus a public kanidm-gated browser UI.
Today this is blocked by an MCP detour: the cognee MCP (port 9271, bound to magnetite's ZeroTier IPv6) is the only mesh-facing surface and it proxies to a loopback-only REST API (port 9270, `127.0.0.1`, firewall closed).
The Claude Code MCP client hardcodes that ZeroTier IPv6 MCP literal, while the cognee plugin cannot reach magnetite at all and falls back to a local per-laptop cognee.
The decided path is to abandon the cognee MCP entirely (client and server), expose the REST API directly over the mesh bound ZeroTier-only, point the plugin and a global cognee-cli at it through one nix source of truth, and add a kanidm-gated browser UI fronted by a dedicated containerized oauth2-proxy that leaves buildbot's existing oauth2-proxy singleton fully untouched.
Because binding the full REST surface to the mesh genuinely widens the attack surface beyond the dropped 12-tool MCP, this change turns on per-agent authentication (`REQUIRE_AUTHENTICATION=true`) and provisions a scoped per-host `X-Api-Key`, so every mesh caller authenticates; that same credential also lets the always-on plugin bootstrap (without it the plugin's login raises and memory silently degrades).
Multi-tenant per-dataset isolation (`ENABLE_BACKEND_ACCESS_CONTROL`) stays off because flipping it is a one-way door that strands the existing global knowledge.

## What Changes

This is one comprehensive change that makes cognee the universal knowledge base via the CLI and the plugin (not the MCP), with a public browser UI.
It establishes a single typed nix source of truth, drops the cognee MCP on both sides, exposes the REST API bound ZeroTier-only behind per-agent authentication, points the always-on plugin and a new global cognee-cli wrapper at central magnetite with per-host namespacing, and adds a kanidm-gated public UI at `kb.scientistexperience.net`.
There is no Phase-1/Phase-2 split and no buildbot prerequisite change.
The one cross-repo prerequisite is rebuilding the cognee frontend in the cognee-nix fork (a `buildPhase` edit plus a flake-input bump); multi-tenant per-dataset isolation, multi-user public access, cognee native OIDC, and a public machine path remain deferred future work.

**Cognee endpoint source of truth**
- From: a hardcoded ZeroTier IPv6 MCP literal `http://[fddb:4344:343b:14b9:399:930f:39db:40d2]:9271/mcp` in `mcp-servers.nix` and a separately restated address in the cognee server and firewall, with no shared nix value.
- To: a typed two-layer nix value (`flake.lib.hosts.<host>.zt` host registry plus a derived `flake.lib.cognee` record carrying `meshApiUrl`, `apiPort`, `publicFqdn`, `userEmail`; no MCP URL) consumed by the cognee server bind, the plugin env, the CLI wrapper, the public-UI FQDN, and the terranix DNS record.
- Reason: one canonical endpoint feeding every consumer, with the recurring literal eliminated.
- Impact: additive nix values, each consolidated into a single file because `flake.lib` is `lazyAttrsOf raw`; consumers read the new value.

**Drop the cognee MCP entirely (client and server), removing its orphaned systemd stanzas**
- From: an MCP client entry in `mcp-servers.nix` that generates `~/.mcp/cognee.json`, a server-side MCP (`services.cognee.mcp`) bound to ZeroTier with port 9271 opened on `zt+`, and the vanixiets `systemd.services.cognee-mcp.*` stanzas (`MCP_DISABLE_DNS_REBINDING_PROTECTION`, capability tightening).
- To: remove the cognee entry from `mcp-servers.nix` (no `~/.mcp/cognee.json`), set `services.cognee.mcp.enable = false`, remove the 9271 `zt+` firewall opening, and remove the orphaned `cognee-mcp` systemd stanzas, while retaining the `ip_nonlocal_bind` sysctl (now load-bearing for the REST ZeroTier bind) with a rewritten comment.
- Reason: the MCP detour is abandoned; the plugin and CLI talk REST directly, and codex/opencode declare no cognee MCP, so nothing consumes the server MCP after the client is dropped.
- Impact: removes the auth-less mesh MCP transport and its now-dead stanzas; the REST capability is preserved by exposing REST directly over the mesh, and the retained sysctl supports the REST bind.

**Expose the cognee REST API bound ZeroTier-only behind per-agent authentication**
- From: the REST API binds `127.0.0.1` (loopback-only) with the firewall closed and no per-caller authentication.
- To: bind the single `types.str` REST listen address to `flake.lib.hosts.magnetite.zt` (fail-closed, no dual-bind patch), open port 9270 on the `zt+` interface only, set `services.cognee.settings.REQUIRE_AUTHENTICATION = "true"` (multiTenant stays false), and add a build-time no-public-bind assertion.
- Reason: this lets the plugin and CLI reach magnetite over the mesh; binding the full REST surface to the mesh does widen the surface beyond the dropped MCP, so per-agent authentication mitigates the widening and the assertion makes a wrong bind fail the build rather than bind silently under `ip_nonlocal_bind=1`.
- Impact: REST is reachable from authenticated mesh members only; never from the public internet.

**Per-agent X-Api-Key credential, plugin and CLI pointed at central magnetite with per-host namespacing**
- From: the plugin bootstraps a local per-laptop cognee with no credential; there is no global cognee-cli pointed at magnetite.
- To: mint one scoped per-host `X-Api-Key` via a one-time owner-authenticated bootstrap (login as `cameron@scientistexperience.net` with the existing `cognee-default-user-password`, then `POST /api/v1/auth/api-keys`), store each key per host in clan-vars, and deliver it to laptops over a sops-nix home-manager secret consumed by both the plugin (`COGNEE_API_KEY`) and the cognee-cli wrapper (`--api-key`); ride the non-secret env (`COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl`, `COGNEE_PLUGIN_DATASET`, `COGNEE_AGENT_NAME`, `COGNEE_USER_EMAIL = cameron@scientistexperience.net`) on `home.sessionVariables`; install a global cognee-cli `writeShellApplication` named `cognee-cli` over `${pkgs.cognee}/bin/cognee-cli` that bakes `--api-url ${flake.lib.cognee.meshApiUrl}` and `--api-key`.
- Reason: with authentication on, every mesh caller needs a key; a scoped per-host key keeps the owner credential off the laptops, the sops-nix secret keeps it off world-readable `home.sessionVariables`, and the per-host dataset/agent env makes per-host identity real (HTTP mode) while recall unions across the single human's datasets automatically.
- Impact: additive home-manager modules plus one sops-nix secret per host; the plugin connects as its per-host agent rather than failing the default-user login.

**Public kanidm-gated browser UI**
- To: rebuild the cognee frontend in the cognee-nix fork with `NEXT_PUBLIC_LOCAL_API_URL=""` so it calls same-origin `/api/`, run it on loopback `127.0.0.1:3000`, and serve it through a bespoke host nginx 443 vhost at `kb.scientistexperience.net` that routes `location /` to the loopback frontend and `location /api/` to the ZeroTier REST API, gated by `auth_request` against a dedicated containerized kanidm oauth2-proxy; the kanidm OAuth2 client, the `cognee_access` group stub, and the secret generator live in `modules/nixos/kanidm.nix` alongside synapse (the live precedent), and `claimMaps.groups` is added so oauth2-proxy's `allowed_groups` can read the group.
- Reason: cognee has no native OIDC, so a kanidm perimeter gates the browser path; buildbot already owns the host oauth2-proxy singleton, so the cognee proxy must be containerized and independent; with `REQUIRE_AUTHENTICATION` on, the perimeter and app-auth are defense-in-depth.
- Impact: a new dedicated containerized oauth2-proxy, a new kanidm OAuth2 client plus `cognee_access` group in `kanidm.nix`, one clan-vars generator emitting the ownership-correct client-secret files plus a length-correct cookie secret, one new DNS record, and a host nginx vhost; buildbot is left entirely untouched.

## Capabilities

### New Capabilities
- `cognee-knowledge-base`: a single canonical nix source of truth for the cognee endpoint consumed by the cognee server bind, the always-on plugin env, a global cognee-cli wrapper, the public-UI FQDN, and the terranix DNS record; the cognee MCP dropped on both sides with its orphaned systemd stanzas removed; the REST API bound ZeroTier-only behind `REQUIRE_AUTHENTICATION` with a build-time no-public-bind assertion; a scoped per-host `X-Api-Key` consumed by the plugin and the CLI; the plugin always-on with per-host dataset/agent namespacing and auto-union recall; a kanidm-gated public browser UI served by a bespoke nginx vhost over a dedicated containerized oauth2-proxy with the kanidm plumbing in `kanidm.nix`; multi-tenant per-dataset isolation deferred as a one-way door; and buildbot left untouched.

### Modified Capabilities
<!-- None. This change introduces a new capability; no existing capability's requirements change. -->

## Impact

Consumers and files updated: a single new file for the `flake.lib.hosts.<host>.zt` registry and a single new file for the derived `flake.lib.cognee` record (each one file per the `lazyAttrsOf raw` constraint), `modules/home/ai/claude-code/mcp-servers.nix` (remove the cognee entry, stop generating `~/.mcp/cognee.json`), a new home-manager module exporting the non-secret plugin env via `home.sessionVariables` and delivering the per-host `X-Api-Key` via a sops-nix home-manager secret, a new home-manager module installing the cognee-cli wrapper (named `cognee-cli`, exec `${pkgs.cognee}/bin/cognee-cli`), the cognee-nix fork (`packages/cognee-frontend/default.nix` `buildPhase` exporting `NEXT_PUBLIC_LOCAL_API_URL=""`, FOD-hash recompute, branch push) with the cognee-nix input bumped in `flake.nix`/`flake.lock`, `modules/nixos/cognee.nix` (bind REST to ZeroTier and open 9270 on `zt+`, set `REQUIRE_AUTHENTICATION` via `services.cognee.settings` with multiTenant false, add the no-public-bind assertion, set `mcp.enable = false`, remove the 9271 opening, remove the orphaned `cognee-mcp` systemd stanzas, retain the `ip_nonlocal_bind` sysctl with a rewritten comment, enable the frontend on loopback, drop the inert `NEXT_PUBLIC_BACKEND_API_URL` injection, leave the module's built-in `services.cognee.nginx` unused), `modules/nixos/kanidm.nix` (add the `provision.systems.oauth2.cognee` client with `claimMaps.groups`, the `cognee_access` group stub declared before its scopeMap, and the `kanidm-oauth2-cognee` generator), a new cognee module owning the dedicated containerized oauth2-proxy and the bespoke host nginx vhost for `kb.scientistexperience.net`, `modules/terranix/cloudflare.nix` with `config.flake.lib.cognee.publicFqdn` threaded in via `config.nix` (the `kb` DNS record), and `modules/machines/nixos/magnetite/default.nix` (import any new `flake.modules.nixos.<svc>`).
The deploy builds from the single `declarative-cognee-endpoint` chain tip after re-mapping the diamond, never from the multi-parent `[wip]`.
Buildbot's `accessMode.fullyPrivate` GitHub-backed oauth2-proxy singleton and its auth configuration are left entirely untouched; no buildbot change and no buildbot prerequisite exist.
Out of scope (deferred future work): multi-tenant per-dataset isolation (`ENABLE_BACKEND_ACCESS_CONTROL`, a one-way door); multi-user public access or cognee native OIDC; a public machine path (public CLI access with a bearer), moot for now since machines use the mesh.
