## Context

Cognee is being made the universal knowledge base for the fleet, accessed via the cognee-cli and the `cognee-memory` plugin (not the MCP), all pointed at one central magnetite cognee through a single declarative nix source of truth, plus a public kanidm-gated browser UI.

Confirmed magnetite facts (these are verified, load-bearing, and not open questions):

- The cognee REST API listens on port 9270, currently bound `127.0.0.1` (loopback ONLY) with the firewall closed; its listen address is a single `types.str` option with no dual-bind support.
- The cognee MCP listens on port 9271, bound to magnetite's ZeroTier IPv6, the ONLY mesh-facing surface today; it proxies to the loopback REST API. The `zt+` firewall opens 9271 only.
- REST auth is DISABLED in this deploy: `auth.multiTenant = false` produces `ENABLE_BACKEND_ACCESS_CONTROL = false`, and `REQUIRE_AUTHENTICATION` is unset, so the API auth dependency is optional. The ZeroTier mesh is the security boundary in v1.
- No client-presented credential exists or is needed in v1. Existing clan-vars generators are `cognee-jwt-secret`, `cognee-db-password`, `cognee-default-user-password`, and `cognee-openai-api-key` (manual); none is a remote-client API key.
- No nginx fronts cognee today; `frontend.enable = false`. `JWT_LIFETIME_SECONDS` is roughly ten years. `auth.defaultUserEmail = cameron@scientistexperience.net`.

Frontend and SPA facts (verified):

- cognee is a Next.js single-page app whose `LocalProvider` only redirects to `/local-login` on an HTTP 401 or 403 from `/api/v1/users/me`. With app-auth off, that endpoint returns 200 as the default user, so the SPA FAILS OPEN and renders without ever prompting for credentials. cognee therefore enforces no access control of its own, and a perimeter gate is genuinely required.
- The frontend reads its backend URL from `NEXT_PUBLIC_LOCAL_API_URL`, inlined at build time. The cognee.nix module injects `NEXT_PUBLIC_BACKEND_API_URL`, but upstream reads the `LOCAL` variable, so that injection is inert. Without a rebuild the browser calls `localhost:8000` and the UI is broken; the frontend must be rebuilt in the cognee-nix fork with `NEXT_PUBLIC_LOCAL_API_URL=""` so it calls same-origin `/api/`.

Wiring facts (verified):

- The plugin's router is the URL alone: a non-local `COGNEE_SERVICE_URL` puts the plugin in managed mode (connect to the remote, never boot a local server; degrade gracefully if unreachable). `COGNEE_API_KEY` is OPTIONAL auth (sent as `X-Api-Key`) with a default-user fallback, so with auth disabled no key is needed in v1.
- The plugin's endpoint resolution precedence is `COGNEE_LOCAL_API_URL` > `COGNEE_SERVICE_URL` > default `http://localhost:8011`. The plugin always sends `X-Api-Key`, never `Bearer`.
- The CLI requires `--api-url` to enter HTTP-delegate mode and has NO env fallback for it (so the wrapper must pass it explicitly). `--api-key` maps to `X-Api-Key` (preferred), `--api-token` maps to `Authorization: Bearer` (only if no api-key). For consistency with the plugin, use `--api-key` / `X-Api-Key`, never `--api-token`.

kanidm is live at `https://accounts.scientistexperience.net` (`modules/nixos/kanidm.nix`, imported on magnetite, already gating matrix-synapse OIDC in `modules/nixos/matrix.nix`); the reusable registration pattern is `services.kanidm.provision.systems.oauth2.<name>` with a `basicSecretFile` from a clan-vars generator (synapse uses generator `kanidm-oauth2-synapse`), a `scopeMaps` mapping a kanidm group to OIDC scopes, and `claimMaps.groups` projecting group membership into the token.
buildbot already runs `accessMode.fullyPrivate`, which owns the host's single `services.oauth2-proxy` instance (GitHub-backed); the nixpkgs `services.oauth2-proxy` is one-per-host, so a second cognee proxy cannot reuse it.
The jfly `oauth2-proxies-nginx` pattern (`~/projects/nix-workspace/jfly-clan-snow/nixos-modules/oauth2-proxies-nginx.nix`) runs each protected vhost's oauth2-proxy in its own NixOS container, listening on a unix socket under `/run/oauth2-proxies/`, with host nginx doing `auth_request` and `allowed_groups`.

## Goals / Non-Goals

**Goals:**

Establish one canonical, typed nix source of truth for the cognee endpoint (`flake.lib.hosts.<host>.zt` plus a derived `flake.lib.cognee` record), consumed by the cognee server bind, the plugin env, the cognee-cli wrapper, and the public-UI FQDN, with no MCP URL in the record.
Abandon the cognee MCP entirely on both sides: remove the client entry and `~/.mcp/cognee.json` generation, disable the server MCP, and drop the 9271 `zt+` firewall opening.
Bind the cognee REST API (9270) ZeroTier-only so the always-on plugin and the cognee-cli wrapper reach the central graph, fail-closed, with no public listener.
Make the plugin always-on global pointed at central magnetite via `home.sessionVariables`, and install a global cognee-cli wrapper baking the mesh API URL.
Add a public, kanidm-gated browser UI at `kb.scientistexperience.net` served by a bespoke host nginx 443 vhost over a dedicated containerized oauth2-proxy, with the frontend rebuilt for same-origin `/api/`, gated by `cognee_access` kanidm group membership, and buildbot's oauth2-proxy singleton left untouched.
Record and assert the no-public-bind security invariant that makes app-auth-off safe.

**Non-Goals (deferred future work):**

Do not change buildbot at all: its `accessMode.fullyPrivate` GitHub-backed oauth2-proxy singleton and auth configuration are out of scope and untouched, and there is no buildbot prerequisite for this change.
Do not enable cognee app-level auth (`REQUIRE_AUTHENTICATION`) or provision the mesh clients' `X-Api-Key` credential; that is a separate future multi-user/hardening change.
Do not build multi-user public access or cognee native OIDC; the oauth2-proxy is a perimeter gate and cognee runs its single default user behind it.
Do not build a public machine path (public CLI access with a bearer); it is moot for now since machines use the mesh.
Do not write the endpoint into the plugin's `~/.cognee-plugin/config.json` (the plugin strips those keys); the URL is delivered via `home.sessionVariables`.

## Decisions

### D1: a typed two-layer nix source of truth, each layer in a single file, with no MCP URL

Choice: introduce two nix values, each consolidated into a single file because `flake.lib` is `lazyAttrsOf raw` (it forbids nested option declarations and multi-file writes at the same nested path).
`flake.lib.hosts.<host>.zt` is a per-host ZeroTier-address registry; `magnetite.zt = "fddb:4344:343b:14b9:399:930f:39db:40d2"`.
`flake.lib.cognee` is a derived record: `{ meshApiUrl = "http://[${magnetite.zt}]:9270"; apiPort = 9270; publicFqdn = "kb.scientistexperience.net"; }`.
No `mcpUrl`, `meshMcpUrl`, or `publicMcpUrl` is included, because the MCP is dropped.

Rationale: a single typed value read by the cognee server bind, the plugin env, the CLI wrapper, and the public-UI FQDN is the de-hardcoding mechanism, and the `lazyAttrsOf raw` constraint mandates single-file consolidation.
Alternatives considered: writing the registry across multiple files at the same nested path (rejected — breaks eval under `lazyAttrsOf raw`); a flat string constant per consumer (rejected — does not eliminate the recurrence); keeping an MCP URL in the record (rejected — the MCP is abandoned).

### D2: drop the cognee MCP entirely (client and server)

Choice: abandon the cognee MCP on both sides.
Client: remove the cognee entry from `modules/home/ai/claude-code/mcp-servers.nix` and stop generating `~/.mcp/cognee.json`.
Server: set `services.cognee.mcp.enable = false` in `modules/nixos/cognee.nix` and remove the 9271 `zt+` firewall opening.

Rationale: the MCP was only ever a detour proxying to the loopback REST API; the plugin and CLI talk REST directly, and codex/opencode declare no cognee MCP, so nothing consumes the server-side MCP once the client is dropped.
Alternatives considered: de-hardcoding the MCP URL and keeping the MCP active per-session (rejected — the decided architecture abandons the MCP, not de-hardcodes it); keeping the server MCP enabled for safety (rejected — it is the auth-less mesh transport with no remaining consumer).

### D3: bind the cognee REST API ZeroTier-only (required)

Choice: in `modules/nixos/cognee.nix`, set the single `types.str` REST listen address to `flake.lib.hosts.magnetite.zt` (instead of `127.0.0.1`) and open port 9270 on the `zt+` interface only.

Rationale: the REST API is loopback-only today, so this is what makes the plugin and the cognee-cli wrapper able to reach magnetite over the mesh.
Because the listen address is a single string with no dual-bind option, binding it to the ZeroTier address is fail-closed: it is reachable only over the mesh, never on the public interface, and the public path reaches REST exclusively through the nginx `/api/` location behind the gate.
This does not widen the attack surface: the now-removed MCP already proxied full REST capability unauthenticated over the same mesh, so this is the same capability by a more direct path.
Alternatives considered: keeping REST loopback-only and reintroducing an MCP-style proxy (rejected — that is the detour being removed); patching the module for a dual loopback-plus-ZT bind (rejected — unnecessary and not fail-closed); exposing REST publicly (rejected — the public path is the kanidm-gated UI, not raw REST).

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

### D6: a dedicated containerized kanidm oauth2-proxy as the sole access-control layer

Choice: gate the public UI with a dedicated containerized kanidm oauth2-proxy following the jfly `oauth2-proxies-nginx` pattern: a NixOS container running its own `services.oauth2-proxy` (`provider = "oidc"`, PKCE via `code-challenge-method = "S256"`) against kanidm, listening on a unix socket under `/run/oauth2-proxies/`, with host nginx doing `auth_request` on the kb vhost.
The allowlist is kanidm GROUP membership `cognee_access`, passed as `allowed_groups` to the proxy's `/oauth2/auth` location.
Register the oauth2 client via `services.kanidm.provision.systems.oauth2.cognee`, mirroring the synapse client, with `scopeMaps.cognee_access = ["openid" "email" "groups"]` and `claimMaps.groups` so the group projects into the token.
Define the access group as a kanidm stub group `provision.groups.cognee_access = { members = []; overwriteMembers = false; }`, with `provision.autoRemove = false`, and add cameron operationally rather than declaratively.
cognee app-auth stays OFF (`auth.multiTenant = false`), so this proxy plus group is the SOLE access-control layer; behind it cognee runs its single default user (`cameron@scientistexperience.net`).

Rationale: cognee has no native OIDC (v1.1.2 is FastAPI-Users only) and its SPA fails open with app-auth off, so a perimeter gate is genuinely required and is the only gate.
buildbot's `accessMode.fullyPrivate` already owns the host's one nixpkgs `services.oauth2-proxy` singleton, which is one-per-host, so the cognee proxy must be a dedicated containerized instance; this also keeps buildbot's GitHub-backed auth and its blast radius entirely untouched.
Group membership (rather than an email-claim allowlist) is the durable allowlist mechanism and follows the established kanidm group-gating precedent (synapse OIDC).
Alternatives considered: reusing the nixpkgs host `services.oauth2-proxy` (rejected — it is one-per-host and owned by buildbot); changing buildbot to share a proxy (rejected — out of scope, expands blast radius, and is unnecessary); an email-claim allowlist (rejected — group membership is the durable, precedent-following mechanism); cognee gaining native OIDC for true per-user SSO (out of scope).

### D7: a bespoke host nginx vhost, frontend rebuilt for same-origin, terranix DNS reading the source of truth

Choice: serve the public UI from a bespoke host nginx 443 vhost (`forceSSL` plus ACME) for `kb.scientistexperience.net`, NOT the module's built-in `services.cognee.nginx` (too rigid to interpose `auth_request`).
The vhost routes `location /` to the loopback frontend `127.0.0.1:3000` and `location /api/` to the ZeroTier REST API `[${magnetite.zt}]:9270`, with `auth_request` against the containerized oauth2-proxy.
The frontend is rebuilt in the cognee-nix fork with `NEXT_PUBLIC_LOCAL_API_URL=""` (build-time inlined to same-origin `/api/`), and the module's inert `NEXT_PUBLIC_BACKEND_API_URL` injection is dropped.
Cloudflare DNS via terranix: add a `kb` record in `modules/terranix/cloudflare.nix` reading `flake.lib.cognee.publicFqdn` as the single source of truth where the terranix eval can reach `flake.lib` (CNAME to `magnetite.scientistexperience.net`, `ttl = 1`, `proxied = false` so ACME works), cloned from the existing niks3/buildbot/git records, applied via `just terraform*` (never `nix run .#terraform` directly).

Rationale: cognee's built-in nginx is too rigid to interpose the oauth2-proxy `auth_request`, so a bespoke vhost is required; the frontend must be rebuilt because upstream reads `NEXT_PUBLIC_LOCAL_API_URL` (not the module's injected `NEXT_PUBLIC_BACKEND_API_URL`), and without the same-origin rebuild the browser calls `localhost:8000` and the UI is broken.
Reading `publicFqdn` from `flake.lib.cognee` keeps the FQDN single-sourced; restating the literal in `cloudflare.nix` is a fallback ONLY if the terranix eval genuinely cannot reach `flake.lib`, to be checked at implementation time, not accepted up front.
Alternatives considered: using `services.cognee.nginx` (rejected — cannot interpose `auth_request`); leaving the inert `NEXT_PUBLIC_BACKEND_API_URL` injection (rejected — upstream ignores it, the UI stays broken); `proxied = true` on the DNS record (rejected — fails ACME silently the way the other public records are configured); restating the FQDN literal unconditionally (rejected — `flake.lib.cognee.publicFqdn` is the source of truth).

### D8: secret topology — one generator, two bare-value files, dual consumers

Choice: a single clan-vars generator `kanidm-oauth2-cognee` emits TWO bare-value files: `files.secret` (owner kanidm) and `files.cookie`.
`files.secret` feeds BOTH the kanidm-provision `basicSecretFile` for the `cognee` oauth2 client AND the oauth2-proxy `clientSecretFile`.
`files.cookie` feeds the oauth2-proxy `cookie.secretFile`.
The generator sets `restartUnits` on `kanidm.service` and the oauth2-proxy unit, because both consume these via `LoadCredential`-style snapshots taken at unit start.
No KEY=VALUE env-file shaping: the files are bare values, consumed directly.

Rationale: one generator with bare-value files is the minimal secret topology that satisfies the kanidm-provision/oauth2-proxy dual-consumer relationship with correct owners; `restartUnits` is required because the snapshot of a credential is taken at unit start, so a regenerated secret is stale until the unit restarts.
Alternatives considered: two separate generators (rejected — supersedes earlier wording; one generator with two files is the minimal correct topology); KEY=VALUE env-file shaping (rejected — the consumers read bare values, env shaping adds an unnecessary layer); omitting `restartUnits` (rejected — leaves a stale-snapshot footgun).

### D9: each gated service owns its identity plumbing; kanidm.nix stays a pure IdP scaffold

Choice: this cognee module owns its own kanidm oauth2 client (`provision.systems.oauth2.cognee`), its own `cognee_access` group, and its own `kanidm-oauth2-cognee` secret generator, all in the cognee module rather than in `kanidm.nix`.
`modules/nixos/kanidm.nix` stays a pure IdP scaffold and is not edited by this change.

Rationale: keeping each gated service's client, group, and secret generator in its own module mirrors the synapse precedent and prevents `kanidm.nix` from accreting per-service coupling.
Alternatives considered: centralizing the cognee client/group/generator in `kanidm.nix` (rejected — accretes per-service coupling into the IdP scaffold and breaks the established per-service-ownership pattern).

### D10: auth posture and the no-public-bind security invariant

Choice: in v1 cognee app-level auth is OFF everywhere. The gates are ZeroTier membership (mesh/machine clients) and the containerized oauth2-proxy/kanidm perimeter (public/browser).
INVARIANT (asserted as a requirement): every cognee listener binds ONLY to loopback or to the ZeroTier address, NEVER to a public interface — REST is ZeroTier-only `[${magnetite.zt}]:9270`, the frontend is loopback `127.0.0.1:3000`, and postgres is loopback `127.0.0.1:5432`; nginx 443 is the only public surface, and the public reaches cognee ONLY through nginx then the oauth2-proxy. This is what makes app-auth-off safe on the public path.
DECOUPLING: turning on cognee app-level auth (`REQUIRE_AUTHENTICATION`) is NOT coupled to the kanidm UI; it is a separate future switch driven by multi-user identity or defense-in-depth. The real hard coupling to record as future work: enabling app-auth REQUIRES simultaneously provisioning and wiring the mesh clients' `X-Api-Key` credential (clan-vars to `home.sessionVariables` plus the CLI wrapper), or the always-on plugin breaks fleet-wide.

Rationale: with app-auth off and the SPA failing open, the only safe public surface is one fully behind a perimeter gate, and the bind invariant is the property that guarantees no path bypasses the gate; recording the app-auth-to-credential coupling prevents a future change from enabling auth without breaking every laptop's always-on plugin.

## Risks / Trade-offs

[Risk] Binding REST to the mesh could appear to widen the attack surface. → Mitigation/clarification: it does not — the now-removed MCP already proxied full REST capability unauthenticated over the same mesh, so this is the same capability by a more direct path, and the single-string ZeroTier-only bind is fail-closed (D3).

[Risk] cognee's SPA fails open (renders without auth when app-auth is off), so any direct public listener would be unguarded. → Mitigation: the no-public-bind invariant (D10) binds every cognee listener to loopback or ZeroTier; the only public surface is nginx 443, which gates every request through the containerized oauth2-proxy before anything reaches cognee.

[Risk] buildbot already owns the host's one nixpkgs `services.oauth2-proxy` singleton. → Mitigation: the cognee proxy is a dedicated containerized instance (D6), so buildbot's GitHub-backed singleton and auth are left entirely untouched with no shared blast radius.

[Risk] Without the same-origin frontend rebuild the browser calls `localhost:8000` and the UI is broken. → Mitigation: the frontend is rebuilt in the cognee-nix fork with `NEXT_PUBLIC_LOCAL_API_URL=""`, and the inert `NEXT_PUBLIC_BACKEND_API_URL` injection is dropped (D7).

[Risk] `flake.lib` is `lazyAttrsOf raw`, so a multi-file write at the same nested path breaks eval. → Mitigation: the host registry and the cognee record are each single-file consolidations (D1), enforced as an early task before any consumer is repointed.

[Risk] A future change enabling cognee app-auth without the mesh `X-Api-Key` credential would break the always-on plugin fleet-wide. → Mitigation: the app-auth-to-credential coupling is recorded as future work (D10); enabling auth must co-provision and wire the credential.

[Risk] A regenerated `kanidm-oauth2-cognee` secret is stale until the consuming units restart (LoadCredential snapshots at unit start). → Mitigation: the generator sets `restartUnits` on `kanidm.service` and the oauth2-proxy unit (D8).

[Risk] ACME for `kb` fails silently if `proxied = true`. → Mitigation: set `proxied = false` (DNS-only) on the `kb` record, matching the existing public records (D7).

[Trade-off] terranix is a separate eval from the NixOS and home-manager modules. → The `kb` record reads `flake.lib.cognee.publicFqdn` as the source of truth where the eval can reach `flake.lib`; restating the literal is a fallback only if verified necessary at implementation time, not an accepted carve-out (D7).

[Trade-off] the cognee-cli wrapper carries a ~1.5 GiB closure per host (the CLI entry point lives in the heavy cognee package). → Accepted for the manual/explicit and debugging-dropback path (D5).

[Trade-off] cognee runs a single default user behind the perimeter gate rather than true per-user SSO. → Accepted for a single-operator knowledge base; native OIDC is out-of-scope future work (D6).

## Migration Plan

Deploy order: (1) land the single-file `flake.lib.hosts.<host>.zt` registry and the single-file `flake.lib.cognee` record; (2) rebuild the cognee-nix frontend with `NEXT_PUBLIC_LOCAL_API_URL=""`; (3) on the server, bind REST ZeroTier-only (to `flake.lib.hosts.magnetite.zt`, open 9270 on `zt+`), set `mcp.enable = false`, remove the 9271 opening, enable the frontend on loopback `127.0.0.1:3000`, and drop the inert `NEXT_PUBLIC_BACKEND_API_URL` injection; (4) on the client, remove the cognee MCP entry from `mcp-servers.nix` and add the plugin-env `home.sessionVariables` module; (5) add the cognee-cli wrapper module; (6) add the single clan-vars generator `kanidm-oauth2-cognee` (`files.secret`, `files.cookie`, with `restartUnits`) before the consumers that read them; (7) add the cognee module owning the `provision.systems.oauth2.cognee` client, the `cognee_access` stub group, and the dedicated containerized oauth2-proxy; (8) add the bespoke host nginx 443 vhost routing `/` to the loopback frontend and `/api/` to the ZeroTier REST, gated by `auth_request`; (9) add the `kb` Cloudflare DNS record via `just terraform*` (reading `flake.lib.cognee.publicFqdn`) and verify ACME issuance; (10) import any new `flake.modules.nixos.<svc>` on magnetite and deploy.

Rollback: the `flake.lib` additions and new modules are removed and the cognee MCP re-enabled if needed; the `kb` DNS record is removed via `just terraform*`; the kanidm OAuth2 client registration and the `cognee_access` group are removed; buildbot is never affected.
Acceptance: a laptop session's always-on plugin (via `home.sessionVariables`) reaches central magnetite over the mesh; the cognee-cli wrapper reaches magnetite without an explicit `--api-url`; the cognee MCP literal and the `~/.mcp/cognee.json` no longer exist; `kb.scientistexperience.net` serves the functional cognee browser UI behind the kanidm `cognee_access` gate with a valid cert; cognee is bound only to loopback and ZeroTier, never to a public interface (the no-public-bind invariant); and buildbot's oauth2-proxy singleton and auth are unchanged.

## Open Questions

The exact module file names for the host registry plus cognee record, the plugin-env module, the cognee-cli wrapper module, and the cognee oauth2-proxy/client/group module are confirmed at implementation; the single-file consolidation for each `flake.lib` addition is non-negotiable.

Whether the terranix eval can reach `flake.lib.cognee.publicFqdn` for the `kb` record is an implementation-time check; restating the literal is permitted only if that read is verified impossible.
