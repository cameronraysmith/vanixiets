## Context

Cognee is being made the universal knowledge base for the fleet, accessed via the cognee-cli and the `cognee-memory` plugin (not the MCP), all pointed at one central magnetite cognee through a single declarative nix source of truth, plus a public kanidm-gated browser UI.

This design supersedes a prior revision that left cognee app-level auth off everywhere and provisioned no client credential.
A 39-agent adversarial pre-implementation review found that posture unsafe (the full REST surface bound to the mesh with no per-caller authentication) and unworkable (the plugin cannot bootstrap with no credential once authentication is demanded).
The user has locked a revised posture: keep app-level multi-tenancy off, but turn per-agent authentication on, and provision a scoped per-agent `X-Api-Key`.
The two changes are orthogonal cognee env knobs and the credential closes both the security gap and the bootstrap gap with one mechanism.

Confirmed magnetite facts (verified, load-bearing, not open questions):

- The cognee REST API listens on port 9270, currently bound `127.0.0.1` (loopback only) with the firewall closed; its listen address is a single `types.str` option with no dual-bind support.
- The cognee MCP listens on port 9271, bound to magnetite's ZeroTier IPv6, the only mesh-facing surface today; it proxies to the loopback REST API. The `zt+` firewall opens 9271 only.
- Existing clan-vars generators are `cognee-jwt-secret`, `cognee-db-password`, `cognee-default-user-password` (the cognee default/owner user password), and `cognee-openai-api-key` (manual); none is a remote-client API key.
- No nginx fronts cognee today; `frontend.enable = false`. `JWT_LIFETIME_SECONDS` is roughly ten years. The cognee default/owner user is `cameron@scientistexperience.net`.

Auth-knob facts (verified in cognee v1.1.2 `get_authenticated_user.py` `_resolve_auth_posture`):

- `REQUIRE_AUTHENTICATION` and `ENABLE_BACKEND_ACCESS_CONTROL` are two orthogonal env knobs.
- `REQUIRE_AUTHENTICATION=true` demands a logged-in user on every request (else HTTP 401, with no default-user fallback); it does not partition storage. All data still lives in one global graph and vector store.
- `ENABLE_BACKEND_ACCESS_CONTROL=true` additionally turns on multi-tenant access control: per-dataset physical database partitioning (databases named `{dataset_id}`) and ACL recall isolation. There is no lazy migration from the global store into per-dataset databases, so flipping it strands pre-existing knowledge until a full re-cognify.
- The cognee-nix module (pinned rev `cognee-v112`) exposes `REQUIRE_AUTHENTICATION` independently through its freeform `services.cognee.settings` attrset, which is rendered last into the unit environment and overrides the base env, with zero fork change. `auth.multiTenant` stays `false`, which keeps `ENABLE_BACKEND_ACCESS_CONTROL=false`.
- magnetite's providers (vector `pgvector`, graph `ladybug`) are on cognee's multi-user-supported provider lists, so a future flip of `ENABLE_BACKEND_ACCESS_CONTROL` stays provider-feasible; that is forward-compatibility, not v1 work.

Frontend and SPA facts (verified):

- cognee is a Next.js single-page app whose `LocalProvider` redirects to `/local-login` on an HTTP 401 or 403 from `/api/v1/users/me`. With `REQUIRE_AUTHENTICATION=true` an unauthenticated `/api/v1/users/me` returns 401, so the SPA no longer fails open; the public path is still gated by the oauth2-proxy perimeter, and the perimeter plus app-auth are now defense-in-depth rather than the perimeter being the sole gate.
- The frontend reads its backend URL from `NEXT_PUBLIC_LOCAL_API_URL`, inlined at build time. `packages/cognee-frontend/default.nix` in the cognee-nix fork currently exports no `NEXT_PUBLIC_LOCAL_API_URL` in its `buildPhase` (the cognee.nix module injects `NEXT_PUBLIC_BACKEND_API_URL`, but upstream reads the `LOCAL` variable, so that injection is inert). Without a rebuild the browser calls `localhost:8000` and the UI is broken; the fork must export `NEXT_PUBLIC_LOCAL_API_URL=""` in its `buildPhase` so the bundle calls same-origin `/api/`.

Wiring facts (verified):

- The plugin's router is the URL alone: a non-local `COGNEE_SERVICE_URL` puts the plugin in HTTP mode (connect to the remote, never boot a local server; degrade gracefully if unreachable), which is what makes per-host agent identity real (the local-SDK path pins a fixed identity regardless of env).
- The plugin always sends `X-Api-Key` (from `COGNEE_API_KEY`), never `Bearer`. Its `session-start.py` logs in the configured user before use; with `REQUIRE_AUTHENTICATION=true` and no credential, that login raises and is caught non-fatally, so memory silently degrades. The plugin's built-in default user is `default_user@example.com`, which does not exist on this server; `COGNEE_USER_EMAIL` must be set to `cameron@scientistexperience.net` (the cognee default/owner user) so the plugin authenticates against a real account.
- The plugin's automatic hook recall passes no dataset, so it spans all datasets the authenticated principal is read-authorized for. For one human across the fleet this means the laptops' memory unions automatically with no sharing step. `claude_sessions` and the node_sets are hardcoded plugin defaults; per-host env (`COGNEE_PLUGIN_DATASET`, `COGNEE_AGENT_NAME`) overrides them, so the change does not claim "no hardcoded dataset names".
- The CLI binary is `cognee-cli`; `pkgs.cognee` has no `meta.mainProgram`, so `lib.getExe` fails and the wrapper must reference `${pkgs.cognee}/bin/cognee-cli` directly. The CLI requires `--api-url` to enter HTTP-delegate mode and has no env fallback for it. `--api-key` maps to `X-Api-Key` (preferred), `--api-token` maps to `Authorization: Bearer`; use `--api-key`, never `--api-token`.
- cognee exposes a key-mint endpoint `POST /api/v1/auth/api-keys` (owner-authenticated) and a per-dataset grant endpoint `POST /api/v1/permissions/datasets/{principal_id}`.

kanidm is live at `https://accounts.scientistexperience.net` (`modules/nixos/kanidm.nix`, imported on magnetite).
The live precedent is synapse: `modules/nixos/kanidm.nix` itself declares the `services.kanidm.provision.systems.oauth2.synapse` client, the synapse access group, and the synapse secret generator; the consuming module (`modules/nixos/matrix.nix`) only reads the secret.
kanidm-provision asserts referential integrity: a group referenced by a `scopeMap` must be declared in `entitiesByName` before the reference (the `kanidm.nix:876` assertion), so any `cognee_access` group stub must be declared before the scopeMap that references it.
synapse uses `scopeMaps` but no `claimMaps.groups`; projecting group membership into the token via `claimMaps.groups` is a new requirement here, because oauth2-proxy's `allowed_groups` needs the groups claim present.
buildbot runs `accessMode.fullyPrivate`, which owns the host's single nixpkgs `services.oauth2-proxy` instance (GitHub-backed, one-per-host), so a second cognee proxy cannot reuse it.
The jfly `oauth2-proxies-nginx` pattern (`~/projects/nix-workspace/jfly-clan-snow/nixos-modules/oauth2-proxies-nginx.nix`) runs each protected vhost's oauth2-proxy in its own NixOS container listening on a unix socket under `/run/oauth2-proxies/`, with host nginx doing `auth_request` and `allowed_groups`.

The terranix cloudflare module is a separate eval that does not receive `flake.lib` in scope by default.

## Goals / Non-Goals

**Goals:**

Establish one canonical, typed nix source of truth for the cognee endpoint (`flake.lib.hosts.<host>.zt` plus a derived `flake.lib.cognee` record), consumed by the cognee server bind, the plugin env, the cognee-cli wrapper, and the public-UI FQDN, with no MCP URL in the record.
Abandon the cognee MCP entirely on both sides: remove the client entry and `~/.mcp/cognee.json` generation, disable the server MCP, remove the orphaned MCP-specific systemd stanzas, and drop the 9271 `zt+` firewall opening while retaining the `ip_nonlocal_bind` sysctl for the REST ZeroTier bind.
Turn on per-agent authentication (`REQUIRE_AUTHENTICATION=true` via `services.cognee.settings`) while keeping multi-tenancy off, and provision a scoped per-agent/per-host `X-Api-Key` consumed by both the plugin and the cognee-cli wrapper.
Bind the cognee REST API (9270) ZeroTier-only so the always-on plugin and the cognee-cli wrapper reach the central graph over the mesh, fail-closed, with no public listener, asserted by a mechanical no-public-bind gate.
Make the plugin an always-on global pointed at central magnetite, with per-host dataset and agent namespacing, so the fleet's memory unions automatically.
Add a public, kanidm-gated browser UI at `kb.scientistexperience.net` served by a bespoke host nginx 443 vhost over a dedicated containerized oauth2-proxy, with the frontend rebuilt for same-origin `/api/`, gated by `cognee_access` kanidm group membership, leaving buildbot's oauth2-proxy singleton untouched.

**Non-Goals (deferred future work):**

Do not enable `ENABLE_BACKEND_ACCESS_CONTROL` (multi-tenant per-dataset physical partitioning); that is a one-way door (no lazy migration from the global store; pre-existing knowledge stranded until a full re-cognify) and is deferred to a future change.
Do not build multi-user public access or cognee native OIDC; the oauth2-proxy is a perimeter gate and cognee runs its single default/owner user behind it.
Do not build a public machine path (public CLI access with a bearer); it is moot for now since machines use the mesh.
Do not change buildbot: its `accessMode.fullyPrivate` GitHub-backed oauth2-proxy singleton and auth configuration are out of scope and untouched, and there is no buildbot prerequisite for this change.
Do not write the endpoint or the credential into the plugin's `~/.cognee-plugin/config.json` (the plugin strips those keys); the URL and non-secret env ride `home.sessionVariables` and the key rides a sops-nix home-manager secret.

## Decisions

### D1: a typed two-layer nix source of truth, each layer in a single file, with no MCP URL

Introduce two nix values, each consolidated into a single file because `flake.lib` is `lazyAttrsOf raw` (it forbids nested option declarations and multi-file writes at the same nested path).
`flake.lib.hosts.<host>.zt` is a per-host ZeroTier-address registry; `magnetite.zt = "fddb:4344:343b:14b9:399:930f:39db:40d2"`.
`flake.lib.cognee` is a derived record: `{ meshApiUrl = "http://[${magnetite.zt}]:9270"; apiPort = 9270; publicFqdn = "kb.scientistexperience.net"; userEmail = "cameron@scientistexperience.net"; }`.
No `mcpUrl`, `meshMcpUrl`, or `publicMcpUrl` is included, because the MCP is dropped.

Rationale: a single typed value read by the cognee server bind, the plugin env, the CLI wrapper, the public-UI FQDN, and the terranix DNS record is the de-hardcoding mechanism, and the `lazyAttrsOf raw` constraint mandates single-file consolidation.
Alternatives considered: writing the registry across multiple files at the same nested path (rejected — breaks eval under `lazyAttrsOf raw`); a flat string constant per consumer (rejected — does not eliminate the recurrence); keeping an MCP URL in the record (rejected — the MCP is abandoned).

### D2: drop the cognee MCP entirely (client and server), removing its orphaned systemd stanzas, retaining ip_nonlocal_bind

Abandon the cognee MCP on both sides.
Client: remove the cognee entry from `modules/home/ai/claude-code/mcp-servers.nix` and stop generating `~/.mcp/cognee.json`.
Server: set `services.cognee.mcp.enable = false` in `modules/nixos/cognee.nix` and remove the 9271 `zt+` firewall opening.

Disabling `mcp.enable` orphans the vanixiets `systemd.services.cognee-mcp.*` stanzas in `modules/nixos/cognee.nix` (`MCP_DISABLE_DNS_REBINDING_PROTECTION` and the per-service `serviceConfig` capability tightening); these are removed.
The `ip_nonlocal_bind=1` sysctl is retained but its comment is rewritten: it is no longer for the MCP, it is now load-bearing for the REST ZeroTier bind (binding to the ZeroTier address before the interface is fully up requires non-local bind).
This distinction is called out explicitly so the implementer removes the MCP `serviceConfig` and DNS-rebinding stanzas without deleting the now-load-bearing sysctl.

Rationale: the MCP was only ever a detour proxying to the loopback REST API; the plugin and CLI talk REST directly, and codex/opencode declare no cognee MCP, so nothing consumes the server-side MCP once the client is dropped.
Alternatives considered: de-hardcoding the MCP URL and keeping the MCP active (rejected — the decided architecture abandons the MCP); keeping the server MCP enabled for safety (rejected — it is the auth-less mesh transport with no remaining consumer); deleting the `ip_nonlocal_bind` sysctl along with the MCP stanzas (rejected — it is reassigned to the REST bind, and `ip_nonlocal_bind=1` makes a wrong bind silent, so it must be paired with the D4 assertion).

### D3: bind the cognee REST API ZeroTier-only (required), acknowledging the surface widening

In `modules/nixos/cognee.nix`, set the single `types.str` REST listen address to `flake.lib.hosts.magnetite.zt` (instead of `127.0.0.1`) and open port 9270 on the `zt+` interface only.

Rationale: the REST API is loopback-only today, so this is what makes the plugin and the cognee-cli wrapper able to reach magnetite over the mesh.
Because the listen address is a single string with no dual-bind option, binding it to the ZeroTier address is fail-closed: reachable only over the mesh, never on the public interface; the public path reaches REST exclusively through the nginx `/api/` location behind the gate.
Surface-widening correction: the prior revision claimed this does not widen the attack surface. That is false. The dropped MCP exposed only its 12-tool proxy; binding the full ~25-group REST to the mesh genuinely widens the surface. The widening is acknowledged and mitigated by D5: with `REQUIRE_AUTHENTICATION=true`, every mesh caller must present a valid `X-Api-Key`, so an unauthenticated mesh member cannot reach any REST group.
An optional ZeroTier-bound nginx path-allowlist reverse proxy (expose only `remember`/`recall`/`search`/`cognify`/`add`; deny `users`/`permissions`/`settings`/`delete`/`sync`) is available as defense-in-depth, but it is not required for v1 given per-caller authentication; it is recorded as an optional hardening alternative, not a deliverable.
Alternatives considered: keeping REST loopback-only and reintroducing an MCP-style proxy (rejected — the detour being removed); patching the module for a dual loopback-plus-ZT bind (rejected — unnecessary and not fail-closed); exposing REST publicly (rejected — the public path is the kanidm-gated UI, not raw REST).

### D4: a mechanical no-public-bind assertion, not a prose checklist

Promote the no-public-bind invariant from prose and manual checklist to a NixOS `assertion` in the cognee module that fails the build if `cfg.listenAddress`, the frontend `listenAddress`, or the postgres listen address resolves to anything other than loopback (`127.0.0.1`/`::1`) or the ZeroTier prefix (`fddb:4344:343b:14b9::/64`, i.e. the `flake.lib.hosts.magnetite.zt` value's prefix).

Rationale: `ip_nonlocal_bind=1` (retained in D2) makes a wrong bind silent — the daemon binds an address it does not yet own without erroring — so a misconfigured public bind would not fail at runtime. A build-time assertion is the only mechanical gate that catches it; a manual checklist does not.
The invariant remains: REST is ZeroTier-only `[${magnetite.zt}]:9270`, the frontend is loopback `127.0.0.1:3000`, postgres is loopback `127.0.0.1:5432`, and nginx 443 is the only public surface, reaching cognee only through the oauth2-proxy.
Alternatives considered: documenting the invariant in prose and a deploy checklist (rejected — silent under `ip_nonlocal_bind=1`); a runtime smoke test of bound ports (rejected — catches the fault after deploy, not before; the assertion is severe and pre-deploy).

### D5: per-agent authentication on, multi-tenancy off, via the two-knob model

Set `REQUIRE_AUTHENTICATION=true` via `services.cognee.settings.REQUIRE_AUTHENTICATION = "true"` (the freeform attrset rendered last into the unit env, overriding the base env, with zero fork change), while keeping `auth.multiTenant = false` (so `ENABLE_BACKEND_ACCESS_CONTROL` stays `false`).

This is the central correction.
The two knobs are orthogonal: `REQUIRE_AUTHENTICATION` demands a logged-in user on every request (else 401, no default-user fallback) without partitioning storage; `ENABLE_BACKEND_ACCESS_CONTROL` additionally turns on multi-tenant per-dataset physical database partitioning and ACL recall isolation.
Turning on `REQUIRE_AUTHENTICATION` now is a smooth, reversible upgrade: all data stays in one global graph and vector store, nothing is stranded, and the knob can be flipped back.
Turning on `ENABLE_BACKEND_ACCESS_CONTROL` is a one-way door: per-dataset databases named `{dataset_id}` with no lazy migration from the global store, so pre-existing knowledge is stranded until a full re-cognify; it is deferred to a future change (Non-Goals).
magnetite's providers (`pgvector`, `ladybug`) are on cognee's multi-user-supported lists, so the future flip stays provider-feasible; that is forward-compatibility, not v1 work.

Rationale: per-agent authentication closes the surface-widening exposure of D3 (every mesh caller needs a key) and is the precondition for a real per-host agent identity; keeping multi-tenancy off avoids the irreversible stranding of the existing global knowledge.
Alternatives considered: leaving both knobs off (rejected by the review — the full REST surface on the mesh is unauthenticated); turning both on together (rejected — `ENABLE_BACKEND_ACCESS_CONTROL` is a one-way door that strands the existing global store); editing the cognee-nix fork to expose the knob (rejected — the freeform `services.cognee.settings` attrset already exposes it with zero fork change).

### D6: scoped per-agent X-Api-Key credential, secure client distribution, dual consumption

With `REQUIRE_AUTHENTICATION=true`, every mesh REST caller needs a key.
Provision a scoped per-agent/per-host `X-Api-Key`, not the owner credential broadcast to laptops:

- Mint: a one-time owner-authenticated bootstrap logs in as the cognee default/owner user `cameron@scientistexperience.net` using the existing clan-vars `cognee-default-user-password`, then `POST /api/v1/auth/api-keys` once per fleet client to mint one scoped key per host. This is a documented manual/clan-vars bootstrap step, not an automatic generator output (the mint requires a live server and an authenticated session).
- Store: each minted key is stored per host in clan-vars.
- Deliver: each host's key is delivered to the laptop over a secure client secret channel — a sops-nix home-manager secret — never plaintext `home.sessionVariables` (which is world-readable).
- Consume: the key is consumed by both the plugin (`COGNEE_API_KEY`) and the cognee-cli wrapper (`--api-key`), reading the sops-nix secret path.

Non-secret env rides `home.sessionVariables`: `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` (puts the plugin in HTTP mode so per-host identity is real), `COGNEE_PLUGIN_DATASET` and `COGNEE_AGENT_NAME` (per host, see D8), and `COGNEE_USER_EMAIL = cameron@scientistexperience.net` (the plugin's built-in default `default_user@example.com` would not match the server, so the email must be set explicitly).

Rationale: this single credential mechanism closes both the security blocker (unauthenticated full-REST-over-mesh) and the plugin-bootstrap blocker (the plugin's default-user login raises and is caught non-fatally, silently degrading memory). A scoped per-host key is the least-privilege client credential and keeps the owner credential off the laptops; the secret must ride a sops-nix secret, not `home.sessionVariables`, because the latter is world-readable.
Alternatives considered: broadcasting the owner credential to laptops (rejected — over-privileged and a single revocation kills the whole fleet); putting the key in plaintext `home.sessionVariables` (rejected — world-readable); a single shared fleet key (rejected — defeats per-host scoping and per-host revocation); minting the key in a clan-vars generator (rejected — the mint needs a live authenticated server session, so it is a documented bootstrap, with the minted value stored in clan-vars after).

### D7: a bespoke host nginx vhost, terranix DNS threading flake.lib

Serve the public UI from a bespoke host nginx 443 vhost (`forceSSL` plus ACME) for `kb.scientistexperience.net`, not the module's built-in `services.cognee.nginx` (too rigid to interpose `auth_request`).
The vhost routes `location /` to the loopback frontend `127.0.0.1:3000` and `location /api/` to the ZeroTier REST API `[${magnetite.zt}]:9270`, with `auth_request` against the containerized oauth2-proxy.
The frontend rebuild (D11) supplies the same-origin bundle.

Cloudflare DNS via terranix: add a `kb` record in `modules/terranix/cloudflare.nix` reading `config.flake.lib.cognee.publicFqdn` as the single source of truth.
The terranix cloudflare module does not receive `flake.lib` in scope by default; thread it in.
Decision (resolving the prior conditional hedge): thread `config.flake.lib.cognee.publicFqdn` into the terranix module via the module's existing `config.nix` `let`-binding (the same eval already constructs the terranix config from flake-level values), so the record reads the source of truth rather than restating the literal.
The record is a CNAME to `magnetite.scientistexperience.net`, `ttl = 1`, `proxied = false` (so ACME works), cloned from the existing niks3/buildbot/git records, applied via `just terraform*` (never `nix run .#terraform` directly).

Rationale: cognee's built-in nginx cannot interpose the oauth2-proxy `auth_request`, so a bespoke vhost is required; threading `flake.lib` keeps the FQDN single-sourced and removes the prior up-front "restate the literal as a fallback" hedge — the threading is the chosen mechanism and the scenario asserts it.
Alternatives considered: using `services.cognee.nginx` (rejected — cannot interpose `auth_request`); `proxied = true` on the DNS record (rejected — fails ACME the way the other public records show); restating the FQDN literal unconditionally (rejected — `flake.lib` threads cleanly via `config.nix`, so the literal is unnecessary); leaving the threading conditional (rejected — the review flagged the conditional hedge as an undecided question).

### D8: per-host dataset and agent namespacing with auto-union recall and selective sharing later

Set `COGNEE_PLUGIN_DATASET` and `COGNEE_AGENT_NAME` per host via `home.sessionVariables`, overriding the plugin's hardcoded `claude_sessions` dataset default and node_set defaults.
`COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` keeps the plugin in HTTP mode so the per-host agent identity is real (the local-SDK path pins a fixed identity regardless of env).

The plugin's automatic hook recall passes no dataset, so it spans all datasets the authenticated principal is read-authorized for.
For one human (`cameron@scientistexperience.net`) authenticated from every laptop, the fleet's memory unions automatically with no explicit sharing step.
Selective per-dataset sharing to another principal remains available later as a first-class grant (`POST /api/v1/permissions/datasets/{principal_id}`); cross-human grants need a shared tenant (which arrives with `ENABLE_BACKEND_ACCESS_CONTROL`, deferred).

Rationale: per-host dataset and agent env make each host's writes attributable while recall still unions across the single human's datasets; HTTP mode is the precondition for real per-host identity.
The change does not claim "no hardcoded dataset names" — `claude_sessions` and the node_sets are hardcoded plugin defaults that the per-host env overrides.
Alternatives considered: leaving the plugin on its hardcoded `claude_sessions` default for every host (rejected — collapses per-host attribution); relying on the local-SDK path for identity (rejected — it pins a fixed identity regardless of env, so HTTP mode is required).

### D9: cognee's kanidm plumbing lives in kanidm.nix alongside synapse (matching the live precedent)

Place cognee's kanidm OAuth2 client (`provision.systems.oauth2.cognee`), the `cognee_access` group stub, and the `kanidm-oauth2-cognee` secret generator inside `modules/nixos/kanidm.nix`, alongside the existing synapse client/group/generator.
The consuming cognee module only reads the resulting secret.

This reverses the prior revision's D9, which asserted the inverse — that each gated service owns its kanidm plumbing and `kanidm.nix` stays a pure IdP scaffold "mirroring the synapse precedent."
That framing was false: the live synapse precedent puts the OAuth2 client, group, and generator inside `modules/nixos/kanidm.nix`, and `modules/nixos/matrix.nix` only reads the secret.
Matching the live precedent means cognee's plumbing lives in `kanidm.nix` too.

Referential-integrity carry-forward: the `cognee_access` group stub must be declared in `entitiesByName` before any `scopeMap` references it, satisfying the `kanidm.nix:876` assertion.
Define it as `provision.groups.cognee_access = { members = []; overwriteMembers = false; }` with `provision.autoRemove = false`, with cameron added operationally rather than declaratively.

claimMaps correction: the prior revision attributed `claimMaps.groups` to the synapse precedent. synapse uses no `claimMaps`. Frame `claimMaps.groups` as a new requirement: oauth2-proxy's `allowed_groups` needs group membership projected into the token, which synapse never needed, so this is a deliberate addition, not a mirror of synapse.

Rationale: placing the plumbing where the live precedent places it keeps the codebase internally consistent and avoids inventing a per-service-ownership pattern that the repository does not actually follow; the referential-integrity ordering and the new `claimMaps.groups` requirement are the two correctness details the review surfaced.
Alternatives considered: distributing the cognee client/group/generator into the cognee module (rejected — contradicts the live synapse precedent, which is the binding pattern in this repo; would be a deliberate departure with no justifying benefit); attributing `claimMaps.groups` to synapse (rejected — synapse uses no claimMaps, so the attribution is false).

### D10: a dedicated containerized kanidm oauth2-proxy as the public access-control layer

Gate the public UI with a dedicated containerized kanidm oauth2-proxy following the jfly `oauth2-proxies-nginx` pattern: a NixOS container running its own `services.oauth2-proxy` (`provider = "oidc"`, PKCE via `code-challenge-method = "S256"`) against kanidm, listening on a unix socket under `/run/oauth2-proxies/`, with host nginx doing `auth_request` on the kb vhost.
The allowlist is kanidm group membership `cognee_access`, passed as `allowed_groups`.
With app-auth now on (D5), the perimeter and app-auth are defense-in-depth: the perimeter gates public browser access on `cognee_access` membership, and cognee additionally enforces `REQUIRE_AUTHENTICATION` behind it.

Rationale: cognee has no native OIDC (v1.1.2 is FastAPI-Users only), so a perimeter gate is required for the browser path; buildbot's `accessMode.fullyPrivate` owns the host's one nixpkgs `services.oauth2-proxy` singleton (one-per-host), so the cognee proxy must be a dedicated containerized instance, keeping buildbot's GitHub-backed auth and blast radius untouched.
Group membership (rather than an email-claim allowlist) is the durable allowlist and follows the established kanidm group-gating precedent.
Alternatives considered: reusing the nixpkgs host `services.oauth2-proxy` (rejected — one-per-host, owned by buildbot); changing buildbot to share a proxy (rejected — out of scope, expands blast radius); an email-claim allowlist (rejected — group membership is durable and precedent-following); cognee native OIDC (out of scope).

### D11: cross-repo cognee-nix fork rebuild as a sequenced prerequisite

The same-origin frontend is a cross-repo deliverable, not in-repo config.
It requires editing the cognee-nix fork: `packages/cognee-frontend/default.nix` `buildPhase` must export `NEXT_PUBLIC_LOCAL_API_URL=""` (it currently exports none), recomputing the FOD hashes, pushing the `cognee-v112` branch, and bumping the cognee-nix input in vanixiets `flake.nix`/`flake.lock`.
The module's inert `NEXT_PUBLIC_BACKEND_API_URL` injection is dropped (upstream reads `NEXT_PUBLIC_LOCAL_API_URL`).
The rebuilt frontend is enabled and bound to loopback `127.0.0.1:3000`.

Rationale: without the same-origin rebuild the browser calls `localhost:8000` and the UI is broken; this is a sequenced prerequisite because it touches a separate repository and a flake-input bump, which must land before the in-repo vhost and frontend-enable config can reference the rebuilt bundle.
Verification is falsifiable: the built frontend bundle contains no literal `localhost` backend URL.
Alternatives considered: leaving the inert `NEXT_PUBLIC_BACKEND_API_URL` injection (rejected — upstream ignores it, the UI stays broken); rebuilding in-repo without the fork edit (rejected — the `buildPhase` export lives in the fork, not in vanixiets); treating the fork edit as ordinary in-repo config (rejected — it is cross-repo and gates the flake bump).

### D12: secret topology — dual-context consumers, mode 0400, named container unit in restartUnits

The `kanidm-oauth2-cognee` generator (in `kanidm.nix`, D9) emits the OAuth2 client secret and the oauth2-proxy cookie secret.
The client secret is consumed by host-side kanidm-provision (owner `kanidm`) and, in a different security context, by the containerized oauth2-proxy via bind-mount (the container runs the proxy under its own uid).
Resolve the uid mapping by emitting the secret as two files from the one generator: `files.secret` with owner `kanidm` (for kanidm-provision's `basicSecretFile`) and `files.secret-proxy` owned by the oauth2-proxy container's runtime uid (bind-mounted into the container as `clientSecretFile`).
Document the exact bind-mount path and the container uid mapping in the implementation.
Set every emitted file `mode = "0400"` and `secret = true`.

The cookie secret generator emits exactly 16, 24, or 32 bytes in an acceptable encoding, mirroring the buildbot cookie-secret generator's `openssl` recipe (`openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32`), because oauth2-proxy rejects a cookie secret that is not one of those lengths.

`restartUnits` names the real units: `kanidm.service` (kanidm-provision) and the actual containerized oauth2-proxy host unit — `container@oauth2-proxy-cognee.service` (the NixOS-container host unit), not a generic "the oauth2-proxy unit" — because both consume the secret via a `LoadCredential`-style snapshot taken at unit start, so a regenerated secret is stale until the named units restart.

Rationale: the dual security context (host kanidm uid vs container proxy uid) is the detail the review flagged; emitting two ownership-correct files from one generator resolves the uid mismatch without weakening the mode; the cookie-length constraint and the named restart target are the two remaining correctness details.
Alternatives considered: a single file shared across both contexts (rejected — the two consumers run under different uids, so one ownership cannot satisfy both at `0400`); two separate generators (rejected — one generator with multiple files is the minimal correct topology); naming "the oauth2-proxy unit" generically (rejected — the consuming unit is the named container host unit, and `restartUnits` must name it exactly); an arbitrary-length cookie secret (rejected — oauth2-proxy rejects non-16/24/32-byte secrets).

### D13: deploy from the single chain tip, not the multi-parent development join

Mandate that the deploy phase build and deploy from the single `declarative-cognee-endpoint` chain tip, not the multi-parent `@` `[wip]` of a diamond development join.
Re-map the diamond before the deploy phase and pin the deploy to the chain tip.

Rationale: a clan deploy from a multi-parent `[wip]` builds the integrated tree of all active chains, so sibling-chain work would reach production as a side effect (the diamond-wip-deploy-pulls-all-chains hazard); deploying from the single chain tip isolates this change. The diamond can grow under the work (N can increase between phases), so a re-map before deploy is required, not optional.
Alternatives considered: deploying from `@` for convenience (rejected — pulls every active chain's work into the magnetite deploy); skipping the re-map (rejected — the join's parent set can change between phases, so the tip must be recomputed at deploy time).

### D14: rollback completeness

Rollback covers, in coherent order:

- Remove the in-repo modules and the `flake.lib` additions; re-enable the cognee MCP if mesh reachability via the prior path is needed.
- Remove the `kb` Cloudflare DNS record via `just terraform*`.
- Remove the `kanidm-oauth2-cognee` clan-vars generator and its emitted secret files (the generator removal does not delete already-emitted files; delete them explicitly).
- Revert the cognee-nix input bump in `flake.nix`/`flake.lock` (D11).
- Delete the orphaned kanidm OAuth2 client left in kanidm's database: `provision.autoRemove = false` does not delete it, so removing the declaration leaves the client registered; it must be removed from kanidm explicitly (or `autoRemove` temporarily flipped).
- Restore mesh-client reachability coherently by re-adding the MCP client and removing `COGNEE_SERVICE_URL` in the same step, because the two are coupled: removing the service URL without re-adding the MCP client leaves the plugin with no path to cognee.

Rationale: each item is a piece of state the naive "remove the modules" rollback leaves behind — emitted secret files, the flake-input bump, the orphaned kanidm client (which `autoRemove = false` preserves), and the coupled MCP-client-re-add to `COGNEE_SERVICE_URL`-removal ordering. Buildbot is never affected.

## Risks / Trade-offs

[Risk] Binding the full REST surface to the mesh widens the attack surface relative to the 12-tool MCP. → Mitigation: `REQUIRE_AUTHENTICATION=true` (D5) means every mesh caller must present a valid per-host `X-Api-Key` (D6); the optional ZeroTier-bound nginx path-allowlist proxy (D3) is available as defense-in-depth but not required given per-caller auth.

[Risk] The plugin cannot bootstrap with no credential once authentication is demanded — `session-start.py`'s login raises and is caught non-fatally, silently degrading memory. → Mitigation: the per-host `X-Api-Key` plus `COGNEE_USER_EMAIL = cameron@scientistexperience.net` (D6) make the plugin authenticate as a real account; the verification is that a laptop session connects as its agent rather than failing the default-user login.

[Risk] `ip_nonlocal_bind=1` (retained for the REST ZeroTier bind, D2) makes a wrong public bind silent. → Mitigation: the build-time no-public-bind assertion (D4) is the mechanical gate that catches it pre-deploy.

[Risk] Flipping `ENABLE_BACKEND_ACCESS_CONTROL` is a one-way door that strands the existing global knowledge. → Mitigation: it stays off in v1 (D5, Non-Goals); only `REQUIRE_AUTHENTICATION` (smooth and reversible) is turned on, and the provider-compatibility forward note records that a future flip stays feasible.

[Risk] The kanidm client secret is consumed in two security contexts (host kanidm uid and container proxy uid). → Mitigation: the one generator emits two ownership-correct `0400` files (D12), and the container bind-mount/uid mapping is documented.

[Risk] Disabling `mcp.enable` orphans the `cognee-mcp` systemd stanzas. → Mitigation: those stanzas are removed (D2), while the `ip_nonlocal_bind` sysctl is retained and its comment rewritten for the REST bind.

[Risk] The same-origin frontend requires a cross-repo fork edit and a flake bump. → Mitigation: D11 sequences the fork edit, FOD-hash recompute, branch push, and input bump as an explicit prerequisite, with a falsifiable check that the bundle has no literal localhost backend URL.

[Risk] A clan deploy from the multi-parent `[wip]` would pull every active chain's work into magnetite. → Mitigation: deploy from the single chain tip after re-mapping the diamond (D13).

[Risk] `provision.autoRemove = false` leaves the orphaned kanidm OAuth2 client registered after rollback. → Mitigation: rollback removes the client from kanidm explicitly (D14).

[Risk] ACME for `kb` fails silently if `proxied = true`. → Mitigation: `proxied = false` (DNS-only) on the `kb` record, matching the existing public records (D7).

[Trade-off] terranix is a separate eval from the NixOS and home-manager modules. → `config.flake.lib.cognee.publicFqdn` is threaded into the terranix module via `config.nix` (D7), so the FQDN is single-sourced rather than restated.

[Trade-off] the cognee-cli wrapper carries a ~1.5 GiB closure per host (the CLI entry point lives in the heavy cognee package). → Accepted for the manual/explicit and debugging-dropback path.

[Trade-off] cognee runs a single default/owner user behind the perimeter gate rather than true per-user SSO. → Accepted for a single-operator knowledge base; native OIDC and multi-tenant per-dataset isolation are out-of-scope future work (D5, D10).

## Migration Plan

Deploy order:

1. Land the single-file `flake.lib.hosts.<host>.zt` registry and the single-file `flake.lib.cognee` record (with `userEmail`).
2. Cross-repo prerequisite (D11): edit the cognee-nix fork `packages/cognee-frontend/default.nix` `buildPhase` to export `NEXT_PUBLIC_LOCAL_API_URL=""`, recompute FOD hashes, push the `cognee-v112` branch, and bump the cognee-nix input in `flake.nix`/`flake.lock`.
3. Confirm `pkgs.cognee` builds and `bin/cognee-cli --help` lists `--api-url`/`--api-key` (D-pre, before the wrapper is authored).
4. On the server: set `services.cognee.settings.REQUIRE_AUTHENTICATION = "true"` (multiTenant stays false), bind REST to `flake.lib.hosts.magnetite.zt` and open 9270 on `zt+`, set `mcp.enable = false`, remove the 9271 opening, remove the orphaned `cognee-mcp` systemd stanzas, retain `ip_nonlocal_bind` with a rewritten comment, add the no-public-bind assertion, enable the rebuilt frontend on `127.0.0.1:3000`, and drop the inert `NEXT_PUBLIC_BACKEND_API_URL` injection.
5. One-time credential bootstrap (D6): log in as `cameron@scientistexperience.net` with `cognee-default-user-password`, `POST /api/v1/auth/api-keys` once per fleet client, store each scoped key per host in clan-vars.
6. On the client: remove the cognee MCP entry from `mcp-servers.nix`, add the non-secret plugin env via `home.sessionVariables` (`COGNEE_SERVICE_URL`, `COGNEE_PLUGIN_DATASET`, `COGNEE_AGENT_NAME`, `COGNEE_USER_EMAIL`), and deliver the per-host key via a sops-nix home-manager secret consumed as `COGNEE_API_KEY`.
7. Add the cognee-cli wrapper module (named `cognee-cli`, exec `${pkgs.cognee}/bin/cognee-cli`, baking `--api-url ${meshApiUrl}` and `--api-key` from the sops-nix secret, forwarding `"$@"`).
8. Add the `kanidm-oauth2-cognee` generator in `kanidm.nix` (client secret as two ownership-correct `0400` files, cookie secret 16/24/32 bytes, `restartUnits` on `kanidm.service` and `container@oauth2-proxy-cognee.service`) plus the `cognee_access` group stub (declared before its scopeMap) and the `provision.systems.oauth2.cognee` client with `scopeMaps` and the new `claimMaps.groups`.
9. Add the cognee module's dedicated containerized oauth2-proxy and the bespoke host nginx 443 vhost (`/` to the loopback frontend, `/api/` to the ZeroTier REST, `auth_request` against the proxy).
10. Add the `kb` Cloudflare DNS record via `just terraform*` (reading the threaded `config.flake.lib.cognee.publicFqdn`) and verify ACME issuance.
11. Re-map the diamond (D13), import any new `flake.modules.nixos.<svc>` on magnetite, and deploy from the single chain tip.

Rollback: per D14.

Acceptance: a laptop session's always-on plugin connects to central magnetite as its per-host agent (not failing the default-user login) and unions recall across the single human's datasets; the cognee-cli wrapper reaches magnetite with the baked `--api-url` and the per-host `--api-key`; the cognee MCP literal and `~/.mcp/cognee.json` no longer exist; `kb.scientistexperience.net` serves the functional cognee browser UI behind the kanidm `cognee_access` gate with a valid cert and `REQUIRE_AUTHENTICATION` enforced behind it; the build asserts every cognee listener binds only to loopback or ZeroTier; and buildbot's oauth2-proxy singleton and auth are unchanged.

## Open Questions

The exact module file names for the host registry plus cognee record, the plugin-env and key-delivery module, the cognee-cli wrapper module, and the cognee oauth2-proxy/vhost module are confirmed at implementation; the single-file consolidation for each `flake.lib` addition is non-negotiable.

The exact container uid the bind-mounted `files.secret-proxy` must be owned by (D12) is confirmed against the NixOS-container's runtime user at implementation time.
