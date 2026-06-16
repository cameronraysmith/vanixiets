## Context

Cognee is being made the universal knowledge base for the fleet, accessed via the cognee-cli and the `cognee-memory` plugin (not the MCP), all pointed at one central magnetite cognee through a single declarative nix source of truth, plus a public kanidm-gated browser UI.

Confirmed magnetite facts (these are verified, load-bearing, and not open questions):

- The cognee REST API listens on port 9270, currently bound `127.0.0.1` (loopback ONLY) with the firewall closed (`modules/nixos/cognee.nix:116-117`, `openFirewall = false` at `:109`).
- The cognee MCP listens on port 9271, bound to magnetite's ZeroTier IPv6, the ONLY mesh-facing surface today; it proxies to the loopback REST API. The `zt+` firewall opens 9271 only (`:200`).
- REST auth is DISABLED in this deploy: `auth.multiTenant = false` produces `ENABLE_BACKEND_ACCESS_CONTROL = false`, and `REQUIRE_AUTHENTICATION` is unset, so the API auth dependency is optional. The ZeroTier mesh is the security boundary in v1.
- No client-presented credential exists or is needed in v1. Existing clan-vars generators are `cognee-jwt-secret`, `cognee-db-password`, `cognee-default-user-password`, and `cognee-openai-api-key` (manual); none is a remote-client API key.
- No nginx fronts cognee today; `frontend.enable = false`. `JWT_LIFETIME_SECONDS` is roughly ten years. `auth.defaultUserEmail = cameron@scientistexperience.net`.

Wiring facts (verified):

- The plugin's router is the URL alone: a non-local `COGNEE_SERVICE_URL` puts the plugin in managed mode (connect to the remote, never boot a local server; degrade gracefully if unreachable). `COGNEE_API_KEY` is OPTIONAL auth (sent as `X-Api-Key`) with a default-user fallback, so with auth disabled no key is needed in v1.
- The plugin's endpoint resolution precedence is `COGNEE_LOCAL_API_URL` > `COGNEE_SERVICE_URL` > default `http://localhost:8011`. The plugin always sends `X-Api-Key`, never `Bearer`.
- The CLI requires `--api-url` to enter HTTP-delegate mode and has NO env fallback for it (so the wrapper must pass it explicitly). `--api-key` maps to `X-Api-Key` (preferred), `--api-token` maps to `Authorization: Bearer` (only if no api-key). For consistency with the plugin, use `--api-key` / `X-Api-Key`, never `--api-token`.

kanidm is live at `https://accounts.scientistexperience.net` (`modules/nixos/kanidm.nix`, imported on magnetite, already gating matrix-synapse OIDC in `modules/nixos/matrix.nix`); the reusable registration pattern is `services.kanidm.provision.systems.oauth2.<name>` with a `basicSecretFile` from a clan-vars generator (synapse uses generator `kanidm-oauth2-synapse`).

## Goals / Non-Goals

**Goals:**

Establish one canonical, typed nix source of truth for the cognee endpoint (`flake.lib.hosts.<host>.zt` plus a derived `flake.lib.cognee` record), consumed by the cognee server bind, the plugin env, the cognee-cli wrapper, and the public-UI FQDN, with no MCP URL in the record.
Abandon the cognee MCP entirely on both sides: remove the client entry and `~/.mcp/cognee.json` generation, disable the server MCP, and drop the 9271 `zt+` firewall opening.
Expose the cognee REST API (9270) over the ZeroTier mesh so the always-on plugin and the cognee-cli wrapper reach the central graph.
Make the plugin always-on global pointed at central magnetite via `home.sessionVariables`, and install a global cognee-cli wrapper baking the mesh API URL.
Add a public, kanidm-gated browser UI at `kb.scientistexperience.net` (frontend plus nginx plus oauth2-proxy plus kanidm client plus clan-vars secrets plus a terranix DNS record), restricted to cameron.
Record and assert the no-public-bind security invariant that makes app-auth-off safe.

**Non-Goals (deferred future work):**

Do not enable cognee app-level auth (`REQUIRE_AUTHENTICATION`) or provision the mesh clients' `X-Api-Key` credential; that is a separate future multi-user/hardening change.
Do not build multi-user public access or cognee native OIDC; the oauth2-proxy is a perimeter gate and cognee runs its single default user behind it.
Do not build a public machine path (public CLI access with a bearer); it is moot for now since machines use the mesh.
Do not write the endpoint into the plugin's `~/.cognee-plugin/config.json` (the plugin strips those keys); the URL is delivered via `home.sessionVariables`.

## Decisions

### D1: a typed two-layer nix source of truth, each layer in a single file, with no MCP URL

Choice: introduce two nix values, each consolidated into a single file because `flake.lib` is `lazyAttrsOf raw` (it forbids nested option declarations and multi-file writes at the same nested path).
`flake.lib.hosts.<host>.zt` is a per-host ZeroTier-address registry; `magnetite.zt = "fddb:4344:343b:14b9:399:930f:39db:40d2"`.
`flake.lib.cognee` is a derived record: `{ meshApiUrl = "http://[${magnetite.zt}]:9270"; apiPort = 9270; publicFqdn = "kb.scientistexperience.net"; ... }`.
No `mcpUrl`, `meshMcpUrl`, or `publicMcpUrl` is included, because the MCP is dropped.

Rationale: a single typed value read by the cognee server bind, the plugin env, the CLI wrapper, and the public-UI FQDN is the de-hardcoding mechanism, and the `lazyAttrsOf raw` constraint mandates single-file consolidation.
Alternatives considered: writing the registry across multiple files at the same nested path (rejected — breaks eval under `lazyAttrsOf raw`); a flat string constant per consumer (rejected — does not eliminate the recurrence); keeping an MCP URL in the record (rejected — the MCP is abandoned).

### D2: drop the cognee MCP entirely (client and server)

Choice: abandon the cognee MCP on both sides.
Client: remove the cognee entry from `modules/home/ai/claude-code/mcp-servers.nix` and stop generating `~/.mcp/cognee.json`.
Server: set `services.cognee.mcp.enable = false` in `modules/nixos/cognee.nix` and remove the 9271 `zt+` firewall opening.

Rationale: the MCP was only ever a detour proxying to the loopback REST API; the plugin and CLI talk REST directly, and codex/opencode declare no cognee MCP, so nothing consumes the server-side MCP once the client is dropped.
Alternatives considered: de-hardcoding the MCP URL and keeping the MCP active per-session (rejected — the decided architecture abandons the MCP, not de-hardcodes it); keeping the server MCP enabled for safety (rejected — it is the auth-less mesh transport with no remaining consumer).

### D3: expose the cognee REST API over ZeroTier (required)

Choice: in `modules/nixos/cognee.nix`, bind the REST API listen address to `flake.lib.hosts.magnetite.zt` (instead of `127.0.0.1`) and open port 9270 on the `zt+` interface.

Rationale: the REST API is loopback-only today, so this is what makes the plugin and the cognee-cli wrapper able to reach magnetite over the mesh.
This does not widen the attack surface: the now-removed MCP already proxied full REST capability unauthenticated over the same mesh, so this is the same capability by a more direct path.
Alternatives considered: keeping REST loopback-only and reintroducing an MCP-style proxy (rejected — that is the detour being removed); exposing REST publicly (rejected — the public path is the kanidm-gated UI, not raw REST).

### D4: plugin always-on global pointed at central magnetite

Choice: set `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` via home-manager `home.sessionVariables` (global), so every session's `cognee-memory` plugin connects to magnetite in managed mode (no local fallback).
No `COGNEE_API_KEY` is set in v1 because cognee app-level auth is disabled; the plugin's optional `X-Api-Key` auth degrades to the default user.
The plugin remains the passive-memory engine (auto-capture of tool traces, auto-recall on prompt, end-of-session graph bridge).

Rationale: a non-local `COGNEE_SERVICE_URL` is exactly the plugin's managed-mode router, so the global env is what makes the central default hold; the URL must come via the environment because the plugin's `save_config` strips it from `~/.cognee-plugin/config.json`.
Behavior note (accepted trade-off): when magnetite is unreachable (laptop off the mesh or offline), the plugin degrades — for a remote URL it connects-only and does not boot a local fallback server, so cognee is simply unavailable that session.
Alternatives considered: writing the URL into `~/.cognee-plugin/config.json` (rejected — stripped by `save_config`); setting a `COGNEE_API_KEY` in v1 (rejected — auth is disabled, no key exists or is needed).

### D5: global cognee-cli wrapper baking the mesh API URL

Choice: a global cognee-cli wrapper as a first-class nix package — a `writeShellApplication` over `pkgs.cognee` (provided by the already-wired cognee-nix overlay; vanixiets `flake.nix` has cognee-nix as an input and `modules/nixpkgs/overlays/cognee.nix` wires it) — that bakes `--api-url ${flake.lib.cognee.meshApiUrl}` into every invocation, installed globally via a home-manager module.

Rationale: the CLI requires `--api-url` to enter HTTP-delegate mode and has no env fallback for it, so the wrapper must pass it explicitly; this is the manual/explicit and debugging-dropback path, independent of the plugin's bundled venv.
The footprint is ~1.5 GiB closure per host (the CLI entry point lives in the heavy cognee package); accepted.
For consistency with the plugin, when a client credential is eventually introduced the wrapper uses `--api-key` (`X-Api-Key`), never `--api-token` (Bearer); in v1 no key is passed.
Alternatives considered: relying on an env var for `--api-url` (rejected — the CLI has no env fallback for it); reusing the plugin's bundled venv CLI (rejected — the global wrapper is decoupled from the plugin and is the explicit/debugging path).

### D6: public kanidm-gated browser UI fronting cognee on loopback

Choice: enable the cognee frontend and front it with nginx (`forceSSL` plus ACME) delegating to a kanidm-OIDC-backed oauth2-proxy that proxies to cognee on loopback.
Register a new kanidm OAuth2 client via `services.kanidm.provision.systems.oauth2.<name>` plus a clan-vars `basicSecretFile`, mirroring the synapse pattern, and add a clan-vars oauth2-proxy cookie secret.
Restrict the oauth2-proxy allowlist to cameron's identity (email or kanidm group); behind the proxy cognee runs its single default user (`cameron@scientistexperience.net`) with app-auth off.

Rationale: cognee is not OIDC-native, so a perimeter proxy is the minimal way to gate the public browser surface on the live kanidm SSO; the single-default-user model is acceptable for one operator.
Alternatives considered: cognee gaining native OIDC for true per-user SSO (out of scope); a GitHub-backed oauth2-proxy like buildbot's (rejected — kanidm is the live SSO provider for this fleet); fronting raw REST publicly without the proxy (rejected — app-auth is off, the proxy is the public gate).

### D7: public vhost and DNS, mirroring the existing public-service pattern

Choice: an nginx vhost (`forceSSL` plus ACME) for `kb.scientistexperience.net`, mirroring the buildbot/gitea/niks3 public-vhost pattern; `cognee.nix` already has `services.cognee.nginx.enable` plus `nginx.domain` scaffolding.
Cloudflare DNS via terranix: add a `kb` record in `modules/terranix/cloudflare.nix` (CNAME `kb` -> `magnetite.scientistexperience.net`, `ttl = 1`, `proxied = false` so ACME works), cloned from the existing niks3/buildbot/git records, applied via `just terraform*` (never `nix run .#terraform` directly).

Rationale: reusing the established public-vhost pattern minimizes risk, and the existing scaffolding in `cognee.nix` is the intended insertion point.
Alternatives considered: `proxied = true` (rejected — fails ACME silently the way the other public records are configured).

### D8: auth posture and the no-public-bind security invariant

Choice: in v1 cognee app-level auth is OFF everywhere. The gates are ZeroTier membership (mesh/machine clients) and the oauth2-proxy/kanidm perimeter (public/browser).
INVARIANT (asserted as a requirement): cognee's REST API and frontend are bound ONLY to loopback (for the proxy) and to the ZeroTier address (for machine clients), NEVER to a public interface; the public reaches cognee ONLY through nginx then oauth2-proxy. This is what makes app-auth-off safe on the public path.
DECOUPLING: turning on cognee app-level auth (`REQUIRE_AUTHENTICATION`) is NOT coupled to the kanidm UI; it is a separate future switch driven by multi-user identity or defense-in-depth. The real hard coupling to record as future work: enabling app-auth REQUIRES simultaneously provisioning and wiring the mesh clients' `X-Api-Key` credential (clan-vars to `home.sessionVariables` plus the CLI wrapper), or the always-on plugin breaks fleet-wide.

Rationale: with app-auth off, the only safe public surface is one fully behind a perimeter gate, and the bind invariant is the property that guarantees no path bypasses the gate; recording the app-auth-to-credential coupling prevents a future change from enabling auth without breaking every laptop's always-on plugin.

## Risks / Trade-offs

[Risk] Exposing REST over the mesh could appear to widen the attack surface. → Mitigation/clarification: it does not — the now-removed MCP already proxied full REST capability unauthenticated over the same mesh, so this is the same capability by a more direct path (D3).

[Risk] `flake.lib` is `lazyAttrsOf raw`, so a multi-file write at the same nested path breaks eval. → Mitigation: the host registry and the cognee record are each single-file consolidations (D1), enforced as an early task before any consumer is repointed.

[Risk] With app-auth off, any public listener on cognee would be open. → Mitigation: the no-public-bind invariant (D8) binds cognee only to loopback and ZeroTier; the public path is exclusively nginx then oauth2-proxy, asserted as a requirement.

[Risk] A future change enabling cognee app-auth without the mesh `X-Api-Key` credential would break the always-on plugin fleet-wide. → Mitigation: the app-auth-to-credential coupling is recorded as future work (D8); enabling auth must co-provision and wire the credential.

[Risk] ACME for `kb` fails silently if `proxied = true`. → Mitigation: set `proxied = false` (DNS-only) on the `kb` record, matching the existing public records (D7).

[Trade-off] terranix is a separate eval from the NixOS and home-manager modules, so the FQDN may be restated in `cloudflare.nix` rather than read from `flake.lib.cognee.publicFqdn`. → Accepted: a minor, acknowledged drift; the canonical value remains `flake.lib.cognee.publicFqdn` for the in-eval consumers.

[Trade-off] the cognee-cli wrapper carries a ~1.5 GiB closure per host (the CLI entry point lives in the heavy cognee package). → Accepted for the manual/explicit and debugging-dropback path (D5).

[Trade-off] cognee runs a single default user behind the perimeter gate rather than true per-user SSO. → Accepted for a single-operator knowledge base; native OIDC is out-of-scope future work (D6).

## Migration Plan

Deploy order: (1) land the single-file `flake.lib.hosts.<host>.zt` registry and the `flake.lib.cognee` record; (2) on the server, expose REST over ZeroTier (bind to `flake.lib.hosts.magnetite.zt`, open 9270 on `zt+`), set `mcp.enable = false`, and remove the 9271 opening; (3) on the client, remove the cognee MCP entry from `mcp-servers.nix` and add the plugin-env `home.sessionVariables` module; (4) add the cognee-cli wrapper module; (5) add the clan-vars generators (kanidm oauth2 client secret, oauth2-proxy cookie secret) before the consumers that read them; (6) enable the frontend and add the nginx vhost plus the kanidm-OIDC oauth2-proxy plus the kanidm OAuth2 client, restricted to cameron; (7) add the `kb` Cloudflare DNS record via `just terraform*` and verify ACME issuance; (8) import any new `flake.modules.nixos.<svc>` on magnetite and deploy.

Rollback: the `flake.lib` additions and new modules are removed and the cognee MCP re-enabled if needed; the `kb` DNS record is removed via `just terraform*`; the kanidm OAuth2 client registration is removed.
Acceptance: a laptop session's always-on plugin (via `home.sessionVariables`) reaches central magnetite over the mesh; the cognee-cli wrapper reaches magnetite without an explicit `--api-url`; the cognee MCP literal and the `~/.mcp/cognee.json` no longer exist; `kb.scientistexperience.net` serves the cognee browser UI behind the kanidm gate with a valid cert; and cognee is bound only to loopback and ZeroTier, never to a public interface (the no-public-bind invariant).

## Open Questions

The exact module file names for the host registry plus cognee record, the plugin-env module, the cognee-cli wrapper module, and the kanidm oauth2-proxy section (new module versus a section in an existing module) are confirmed at implementation; the single-file consolidation for the `flake.lib` additions is non-negotiable.

The clan-vars generator names for the kanidm oauth2 client secret and the oauth2-proxy cookie secret are pinned at implementation, mirroring the synapse generator naming (`kanidm-oauth2-synapse`).
