## ADDED Requirements

### Requirement: Single canonical nix source of truth for the cognee endpoint

The configuration SHALL expose a single typed nix source of truth for the cognee endpoint as two layers, each consolidated into a single file because `flake.lib` is `lazyAttrsOf raw`: a per-host ZeroTier-address registry `flake.lib.hosts.<host>.zt` (with `magnetite.zt` set to the magnetite ZeroTier IPv6 address `fddb:4344:343b:14b9:399:930f:39db:40d2`) and a derived `flake.lib.cognee` record carrying at least `meshApiUrl`, `apiPort`, `publicFqdn`, and `userEmail`.
The record SHALL NOT carry any MCP URL (no `mcpUrl`, `meshMcpUrl`, or `publicMcpUrl`), because the cognee MCP is removed entirely by this change.
Every cognee consumer SHALL read the endpoint from this source of truth rather than from a hardcoded literal: the cognee server bind, the plugin env, the cognee-cli wrapper, the public-UI FQDN, and the terranix DNS record.

#### Scenario: the mesh API URL is derived from the host registry

- **WHEN** `flake.lib.cognee.meshApiUrl` is evaluated
- **THEN** it is derived from `flake.lib.hosts.magnetite.zt` and `flake.lib.cognee.apiPort` (resolving to `http://[fddb:4344:343b:14b9:399:930f:39db:40d2]:9270`) rather than restating the ZeroTier address literal

#### Scenario: the record carries the owner email and no MCP URL

- **WHEN** `flake.lib.cognee` is evaluated
- **THEN** it exposes `userEmail = "cameron@scientistexperience.net"` and no `mcpUrl`, `meshMcpUrl`, or `publicMcpUrl` attribute, because the plugin and CLI authenticate against the cognee default/owner account and the cognee MCP is dropped

#### Scenario: flake.lib additions are single-file consolidations

- **WHEN** the host registry and the cognee record are added to `flake.lib`
- **THEN** each is consolidated into its own single file, satisfying the `lazyAttrsOf raw` constraint that forbids multi-file writes at the same nested path

### Requirement: Drop the cognee MCP entirely (client and server)

The cognee MCP SHALL be abandoned entirely on both sides.
On the client side, `modules/home/ai/claude-code/mcp-servers.nix` SHALL NOT contain a cognee entry and SHALL NOT generate `~/.mcp/cognee.json`.
On the server side, `modules/nixos/cognee.nix` SHALL set `services.cognee.mcp.enable = false` and SHALL NOT open the MCP port (9271) on the ZeroTier (`zt+`) firewall interface.
Disabling `mcp.enable` orphans the vanixiets `systemd.services.cognee-mcp.*` stanzas (`MCP_DISABLE_DNS_REBINDING_PROTECTION` and the per-service `serviceConfig` capability tightening); those stanzas SHALL be removed.
The `ip_nonlocal_bind=1` sysctl SHALL be retained, because it is reassigned from the MCP to the REST ZeroTier bind, and its comment SHALL be rewritten to describe the REST bind rather than the MCP.
The hardcoded ZeroTier IPv6 MCP literal `http://[fddb:4344:343b:14b9:399:930f:39db:40d2]:9271/mcp` SHALL NOT appear in any repointed consumer.

#### Scenario: the MCP client config is removed

- **WHEN** `modules/home/ai/claude-code/mcp-servers.nix` is evaluated
- **THEN** it contains no cognee entry, generates no `~/.mcp/cognee.json`, and contains no hardcoded cognee MCP IPv6 literal

#### Scenario: the server MCP, its firewall opening, and its orphaned stanzas are removed

- **WHEN** `modules/nixos/cognee.nix` is evaluated for magnetite
- **THEN** `services.cognee.mcp.enable` is `false`, port 9271 is not opened on the `zt+` interface, and the `cognee-mcp` `serviceConfig` capability tightening and the `MCP_DISABLE_DNS_REBINDING_PROTECTION` env stanza are absent

#### Scenario: the ip_nonlocal_bind sysctl is retained for the REST bind

- **WHEN** the magnetite cognee configuration is evaluated after the MCP stanzas are removed
- **THEN** `net.ipv4.ip_nonlocal_bind = 1` is still set, its comment describes the REST ZeroTier bind (binding to the ZeroTier address before the interface is fully up) rather than the MCP, and it is not deleted along with the MCP stanzas

#### Scenario: no remaining consumer references the cognee MCP

- **WHEN** the codex and opencode agent configurations are inspected
- **THEN** none declares a cognee MCP server, so nothing consumes the server-side MCP after the client is dropped

### Requirement: Bind the cognee REST API ZeroTier-only with the surface widening acknowledged

The cognee REST API (port 9270, bound `127.0.0.1` loopback-only today with the firewall closed) SHALL be made reachable over the ZeroTier mesh and ONLY over the ZeroTier mesh so the always-on plugin's REST client and the cognee-cli wrapper can reach the central graph: `modules/nixos/cognee.nix` SHALL set the single `types.str` REST listen address to `flake.lib.hosts.magnetite.zt` (fail-closed, no dual-bind patch) and the firewall SHALL admit port 9270 only on the ZeroTier (`zt+`) interface.
Binding the full REST surface to the mesh DOES widen the attack surface relative to the now-dropped 12-tool MCP, which only ever proxied its own limited tool set; this widening SHALL be acknowledged rather than denied, and SHALL be mitigated by per-agent authentication (`REQUIRE_AUTHENTICATION=true`, see the per-agent authentication requirement), so an unauthenticated mesh member cannot reach any REST group.
An optional ZeroTier-bound nginx path-allowlist reverse proxy (exposing only `remember`/`recall`/`search`/`cognify`/`add` and denying `users`/`permissions`/`settings`/`delete`/`sync`) MAY be added as defense-in-depth, but it is NOT required for v1 given per-caller authentication.

#### Scenario: REST is mesh-reachable but not public

- **WHEN** an authenticated mesh member queries the cognee REST API at `flake.lib.cognee.meshApiUrl` with a valid `X-Api-Key`
- **THEN** the request reaches the central cognee, while port 9270 is not reachable from the public internet

#### Scenario: the surface widening is mitigated by authentication

- **WHEN** an unauthenticated mesh member queries any REST group on `flake.lib.hosts.magnetite.zt:9270`
- **THEN** cognee returns HTTP 401 because `REQUIRE_AUTHENTICATION` is on, so the widened REST surface is reachable only by holders of a valid per-host `X-Api-Key`

### Requirement: Per-agent authentication on, multi-tenancy off, via the two-knob model

The configuration SHALL set `REQUIRE_AUTHENTICATION = "true"` through the cognee-nix module's freeform `services.cognee.settings` attrset (rendered last into the unit environment, overriding the base env, with zero fork change), while keeping `auth.multiTenant = false` so that `ENABLE_BACKEND_ACCESS_CONTROL` stays `false`.
These are two orthogonal cognee env knobs: `REQUIRE_AUTHENTICATION` demands a logged-in user on every request (else HTTP 401, with no default-user fallback) without partitioning storage, so all data remains in one global graph and vector store; `ENABLE_BACKEND_ACCESS_CONTROL` additionally turns on multi-tenant per-dataset physical database partitioning (databases named `{dataset_id}`) and ACL recall isolation.
Turning on `REQUIRE_AUTHENTICATION` SHALL be treated as a smooth, reversible upgrade: nothing is stranded and the knob can be flipped back.
Turning on `ENABLE_BACKEND_ACCESS_CONTROL` SHALL be deferred to a future change because it is a one-way door: there is no lazy migration from the global store into per-dataset databases, so flipping it strands pre-existing knowledge until a full re-cognify.
The forward-compatibility note SHALL be recorded: magnetite's providers (vector `pgvector`, graph `ladybug`) are on cognee's multi-user-supported provider lists, so a future flip of `ENABLE_BACKEND_ACCESS_CONTROL` stays provider-feasible; that is not v1 work.

#### Scenario: authentication is required but storage is not partitioned

- **WHEN** the magnetite cognee configuration is evaluated
- **THEN** `services.cognee.settings.REQUIRE_AUTHENTICATION` is `"true"`, `auth.multiTenant` is `false` (so `ENABLE_BACKEND_ACCESS_CONTROL` resolves `false`), and all cognee data lives in one global graph and vector store with no per-dataset physical partitioning

#### Scenario: the multi-tenant flip is deferred as a one-way door

- **WHEN** the design records the multi-tenant posture
- **THEN** `ENABLE_BACKEND_ACCESS_CONTROL` is explicitly deferred to a future change as a one-way door (no lazy migration, pre-existing knowledge stranded until a full re-cognify), with the `pgvector`/`ladybug` provider-compatibility forward note recorded as forward-compatibility rather than v1 work

### Requirement: Scoped per-host X-Api-Key credential with secure client distribution

Because `REQUIRE_AUTHENTICATION` is on, every mesh REST caller SHALL present a valid key, so the change SHALL provision a scoped per-agent/per-host `X-Api-Key`, NOT the owner credential broadcast to laptops.
Each key SHALL be minted by a one-time owner-authenticated bootstrap: logging in as the cognee default/owner user `cameron@scientistexperience.net` using the existing clan-vars `cognee-default-user-password`, then calling `POST /api/v1/auth/api-keys` once per fleet client.
This mint SHALL be treated as a documented manual/clan-vars bootstrap step, not an automatic generator output, because the mint requires a live server and an authenticated session.
Each minted key SHALL be stored per host in clan-vars and delivered to the laptop over a secure client secret channel — a sops-nix home-manager secret — and SHALL NOT ride plaintext `home.sessionVariables`, which is world-readable.
The key SHALL be consumed by BOTH the plugin (as `COGNEE_API_KEY`) and the cognee-cli wrapper (as `--api-key`, sent as `X-Api-Key`, never `--api-token`/Bearer).
The non-secret env SHALL ride `home.sessionVariables`: `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl`, `COGNEE_PLUGIN_DATASET`, `COGNEE_AGENT_NAME`, and `COGNEE_USER_EMAIL = cameron@scientistexperience.net` (the plugin's built-in default `default_user@example.com` would not match the server).

#### Scenario: the key is minted by a documented owner-authenticated bootstrap

- **WHEN** the per-host key is provisioned
- **THEN** it is minted once per fleet client via a manual/clan-vars bootstrap that logs in as `cameron@scientistexperience.net` with `cognee-default-user-password` and calls `POST /api/v1/auth/api-keys`, with the minted scoped value then stored per host in clan-vars rather than emitted by an automatic generator

#### Scenario: the secret key rides a sops-nix secret, not world-readable session variables

- **WHEN** the per-host key is delivered to a laptop
- **THEN** it is delivered via a sops-nix home-manager secret consumed by both the plugin (`COGNEE_API_KEY`) and the cognee-cli wrapper (`--api-key`), and it is NOT written into plaintext `home.sessionVariables`

#### Scenario: non-secret env rides home.sessionVariables with the correct owner email

- **WHEN** the plugin env is delivered declaratively
- **THEN** `COGNEE_SERVICE_URL`, `COGNEE_PLUGIN_DATASET`, `COGNEE_AGENT_NAME`, and `COGNEE_USER_EMAIL = cameron@scientistexperience.net` ride `home.sessionVariables`, so the plugin authenticates against the real cognee default/owner account rather than the nonexistent `default_user@example.com`

### Requirement: The cognee plugin is an always-on global pointed at central magnetite with per-host namespacing

The cognee plugin (the `cognee-memory` hooks plus skills) SHALL be made always-on global by setting `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` via home-manager `home.sessionVariables`, so every session's plugin connects to the central magnetite cognee in HTTP mode (connect to the remote, never boot a local server).
Because the service URL is non-local, the plugin runs in HTTP mode, which is what makes per-host agent identity real (the local-SDK path pins a fixed identity regardless of env).
`COGNEE_PLUGIN_DATASET` and `COGNEE_AGENT_NAME` SHALL be set per host via `home.sessionVariables`, overriding the plugin's hardcoded `claude_sessions` dataset default and node_set defaults; the change SHALL NOT claim "no hardcoded dataset names", because `claude_sessions` and the node_sets are hardcoded plugin defaults that the per-host env overrides.
The plugin's automatic hook recall passes no dataset, so it spans all datasets the authenticated principal is read-authorized for; for one human (`cameron@scientistexperience.net`) authenticated from every laptop, the fleet's memory unions automatically with no explicit sharing step.
Selective per-dataset sharing to another principal SHALL remain available later as a first-class grant (`POST /api/v1/permissions/datasets/{principal_id}`); cross-human grants require a shared tenant, which arrives with the deferred `ENABLE_BACKEND_ACCESS_CONTROL`.

#### Scenario: a non-local service URL puts the plugin in HTTP mode with a real agent identity

- **WHEN** any session starts and the cognee plugin runs with `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` inherited from `home.sessionVariables`
- **THEN** the plugin connects to the remote magnetite cognee in HTTP mode, never boots a local server, and presents its per-host `COGNEE_AGENT_NAME` identity rather than the fixed local-SDK identity

#### Scenario: a laptop session connects as its agent rather than failing default-user login

- **WHEN** a laptop session starts with the per-host `X-Api-Key` (`COGNEE_API_KEY`) and `COGNEE_USER_EMAIL = cameron@scientistexperience.net` present
- **THEN** the plugin's `session-start.py` authenticates as the real cognee default/owner account and connects as its per-host agent, rather than its default-user login raising and being caught non-fatally with memory silently degrading

#### Scenario: recall unions across the single human's datasets automatically

- **WHEN** the plugin's automatic hook recall fires on any laptop with no explicit dataset
- **THEN** it spans every dataset the authenticated `cameron@scientistexperience.net` principal is read-authorized for, so the fleet's per-host memory unions automatically with no sharing step, while selective per-dataset sharing to another principal remains available later via `POST /api/v1/permissions/datasets/{principal_id}`

#### Scenario: the always-on plugin degrades when magnetite is unreachable

- **WHEN** a laptop is off the ZeroTier mesh or magnetite is offline so `flake.lib.cognee.meshApiUrl` cannot be reached
- **THEN** the always-on plugin degrades gracefully (it connects-only and does not boot a local fallback server), so cognee is simply unavailable that session; an offline-session smoke check confirms the session completes without a local-server boot

### Requirement: Global cognee-cli wrapper named cognee-cli baking the mesh API URL and the per-host key

A global cognee-cli wrapper SHALL be provided as a first-class nix package, a `writeShellApplication` whose binary is named exactly `cognee-cli` and which execs `${pkgs.cognee}/bin/cognee-cli` directly (because `pkgs.cognee` has no `meta.mainProgram`, so `lib.getExe` fails on it).
The wrapper SHALL bake `--api-url ${flake.lib.cognee.meshApiUrl}` into every invocation, because the CLI requires `--api-url` to enter HTTP-delegate mode and has no environment fallback for it.
The wrapper SHALL pass `--api-key` (sent as `X-Api-Key`) from the secure sops-nix secret, never `--api-token` (Bearer), and SHALL forward `"$@"` to the underlying binary.
The wrapper SHALL be installed globally via a home-manager module and SHALL be independent of the plugin's bundled venv; the plugin skills and agent reference the `cognee-cli` name on `PATH`.
Building `pkgs.cognee` and confirming `bin/cognee-cli --help` lists `--api-url` and `--api-key` SHALL be a precondition checked before the wrapper is authored.

#### Scenario: the wrapper is named cognee-cli and execs the package binary directly

- **WHEN** the cognee-cli wrapper is built
- **THEN** its binary is named exactly `cognee-cli` and it execs `${pkgs.cognee}/bin/cognee-cli` directly (not via `lib.getExe`, which fails because `pkgs.cognee` has no `meta.mainProgram`), so the name the plugin skills hardcode on `PATH` resolves

#### Scenario: the wrapper bakes the api-url and the per-host api-key

- **WHEN** the cognee-cli wrapper is invoked
- **THEN** it passes `--api-url ${flake.lib.cognee.meshApiUrl}` (entering HTTP-delegate mode against central magnetite without any environment fallback) and `--api-key` read from the secure sops-nix secret (never `--api-token`), then forwards `"$@"`

#### Scenario: the cli binary exists and exposes the required flags before the wrapper is authored

- **WHEN** `pkgs.cognee` is built as a precondition
- **THEN** `bin/cognee-cli --help` lists `--api-url` and `--api-key`, confirming the wrapper's baked flags are valid before the wrapper module is written

### Requirement: The cognee frontend is rebuilt cross-repo for same-origin by patching the backend-URL fallback per file class

The cognee frontend SHALL be rebuilt in the cognee-nix fork so the browser calls same-origin `/api/` rather than a literal `localhost` backend URL, and this rebuild SHALL be sequenced as an explicit cross-repo prerequisite, not in-repo config.
The fork's `packages/cognee-frontend/default.nix` `configurePhase` SHALL `substituteInPlace` the backend-URL fallback expression `|| "http://localhost:8000"` per file class, the FOD hashes SHALL be recomputed, the `cognee-v112` branch SHALL be pushed, and the cognee-nix input SHALL be bumped in vanixiets `flake.nix`/`flake.lock`.
Setting `NEXT_PUBLIC_LOCAL_API_URL=""` at build time SHALL NOT be relied upon, because the code reads `process.env.NEXT_PUBLIC_LOCAL_API_URL || "http://localhost:8000"` and an empty string is falsy, so the `localhost` fallback wins (verified: the empty-env bundle contained `http://localhost:8000` five times); the fallback literal itself SHALL be patched instead.
The per-file-class substitution SHALL set the fallback to `""` in the 6 client/shared files (so the browser issues same-origin `/api/v1/...`), to an absolute loopback URL in the 2 server-side Node route handlers (`src/app/api/local-signout/route.ts`, `src/app/api/visualize/route.ts`, which need absolute URLs for Node `fetch`), and to the public FQDN `https://kb.scientistexperience.net` in the 2 copyable-URL display components (`ApiKeysPage`, `ConnectionModal`).
The module's injected `NEXT_PUBLIC_BACKEND_API_URL` SHALL be dropped because the code never reads it and `NEXT_PUBLIC_*` bakes at build time, making the injection inert; any genuinely build-time value SHALL instead be supplied to the variable the code reads (`NEXT_PUBLIC_LOCAL_API_URL`).
The rebuilt frontend SHALL be enabled and bound to loopback `127.0.0.1:3000`, never to a public interface.

#### Scenario: the cross-repo fork edit and flake bump precede the frontend deliverable

- **WHEN** the same-origin frontend is delivered
- **THEN** the cognee-nix fork's `packages/cognee-frontend/default.nix` `configurePhase` substitutes the `|| "http://localhost:8000"` fallback per file class, the FOD hashes are recomputed, the `cognee-v112` branch is pushed, and the cognee-nix input is bumped in `flake.nix`/`flake.lock` before the in-repo frontend-enable config references the rebuilt bundle

#### Scenario: the empty-env mechanism is rejected because an empty string is falsy

- **WHEN** the same-origin mechanism is chosen
- **THEN** setting `NEXT_PUBLIC_LOCAL_API_URL=""` is rejected because `process.env.NEXT_PUBLIC_LOCAL_API_URL || "http://localhost:8000"` treats the empty string as falsy and the `localhost` fallback wins (the empty-env bundle contained `http://localhost:8000` five times), so the fallback literal itself is patched per file class instead

#### Scenario: the built bundle contains no literal localhost backend URL

- **WHEN** the rebuilt frontend bundle's live `.next/static` chunks are inspected
- **THEN** they contain no literal `localhost` backend URL (because the client/shared fallback is patched to `""`, the browser calls same-origin `/api/`), and the inert `NEXT_PUBLIC_BACKEND_API_URL` injection is absent

#### Scenario: the frontend binds loopback only

- **WHEN** the magnetite cognee configuration is evaluated
- **THEN** the frontend listens only on `127.0.0.1:3000` and is reachable publicly only through the gateway-emitted `kb` nginx vhost

### Requirement: kanidm-gated public browser UI by registering cognee as the shared sso-gateway's consumer #1

The public browser UI SHALL be served at `kb.scientistexperience.net` by the shared `sso-gateway` (delivered by the `sso-gateway` change, on which this change depends), with cognee registering as consumer #1 via `sso.services.cognee = { domain = "kb.scientistexperience.net"; allowedGroups = [ "cognee_access" ]; upstream = { "/" = "http://127.0.0.1:3000"; "/api/" = "http://[fddb:4344:343b:14b9:399:930f:39db:40d2]:9270"; }; }`, supplying the loopback frontend as the `/` upstream and the ZeroTier REST API as the `/api/` upstream.
cognee SHALL NOT define its own oauth2-proxy (container or otherwise), its own bespoke nginx vhost, its own kanidm OAuth2 client, its own `cognee_access` group stub, or its own client-secret/cookie-secret generator; the shared gateway owns the `oauth2-proxy-kanidm` unit, the shared `sso-gateway` kanidm client, the `auth.scientistexperience.net` subdomain, the perimeter secret generators, and the auto-derivation of `cognee_access` and the client's `scopeMaps`/`claimMaps.groups` from cognee's registration.
The gateway-emitted `kb` vhost (`forceSSL` plus ACME) SHALL run `auth_request` against the shared `oauth2-proxy-kanidm`, authorize on `cognee_access` via the query-param `allowed_groups`, and apply the browser-vs-API 401 split: `location /` (the browser UI) redirects a 401 to the sign-in flow, while `location /api/` (API clients) uses `error_page 401 =401` to fail fast.
Buildbot's existing `accessMode.fullyPrivate` GitHub-backed oauth2-proxy singleton and its auth configuration SHALL be left entirely untouched, with no buildbot change and no buildbot prerequisite (the shared gateway is a distinct second instance with a distinct cookie name).
Behind the gate cognee SHALL run as its single default/owner user (`cameron@scientistexperience.net`) with `REQUIRE_AUTHENTICATION` additionally enforced, so the perimeter gate and app-auth are defense-in-depth.
The `kb` Cloudflare DNS record SHALL be provisioned via terranix reading `config.flake.lib.cognee.publicFqdn` as the source of truth (threaded into the terranix module), as a CNAME to `magnetite.scientistexperience.net` with `ttl = 1` and `proxied = false` so ACME succeeds, cloned from the existing niks3/buildbot/git records and applied via `just terraform*` (never `nix run .#terraform`); the central `auth.scientistexperience.net` record belongs to the `sso-gateway` change, NOT this one.

#### Scenario: cognee registers as the gateway's consumer #1 and owns no perimeter internals

- **WHEN** the cognee public UI is delivered
- **THEN** cognee sets `sso.services.cognee` (`domain = "kb.scientistexperience.net"`, `allowedGroups = [ "cognee_access" ]`, `upstream` mapping `/` to the loopback frontend and `/api/` to the ZeroTier REST), and declares no oauth2-proxy, no bespoke nginx vhost, no kanidm client, no `cognee_access` group stub, and no perimeter secret generator — all of which the shared gateway owns

#### Scenario: only members of cognee_access reach the UI

- **WHEN** a request hits `kb.scientistexperience.net`
- **THEN** the gateway-emitted vhost runs `auth_request /oauth2/auth?allowed_groups=cognee_access` against the shared `oauth2-proxy-kanidm`, which admits only kanidm `cognee_access` group members before nginx routes `/` to the loopback frontend and `/api/` to the ZeroTier REST API

#### Scenario: browser and API paths handle 401 differently

- **WHEN** an unauthenticated request hits the `kb` vhost
- **THEN** `location /` (the browser UI) redirects the 401 to the sign-in flow while `location /api/` (API clients) uses `error_page 401 =401` to return a clean fast 401 rather than an HTML redirect

#### Scenario: buildbot's oauth2-proxy singleton is untouched

- **WHEN** cognee is gated through the shared `oauth2-proxy-kanidm` instance
- **THEN** buildbot's `accessMode.fullyPrivate` GitHub-backed host `services.oauth2-proxy` singleton and its auth configuration are unchanged, with no shared blast radius (a different provider, a different instance, and a distinct cookie name)

#### Scenario: the perimeter and app-auth are defense-in-depth

- **WHEN** a `cognee_access` member is admitted through the gateway and the rebuilt same-origin frontend loads
- **THEN** cognee behind the gate enforces `REQUIRE_AUTHENTICATION` as the default/owner user (`cameron@scientistexperience.net`), so the perimeter gates public browser access on `cognee_access` membership and the app additionally requires a logged-in user, with no per-user SSO into cognee in this phase

#### Scenario: ACME issuance succeeds for the kb record reading the threaded FQDN

- **WHEN** the `kb` Cloudflare DNS record is created via terranix and applied with `just terraform*`
- **THEN** it reads `config.flake.lib.cognee.publicFqdn` threaded into the terranix module via the `config.nix` `let`-binding, is a CNAME to `magnetite.scientistexperience.net` with `ttl = 1` and `proxied = false`, allowing ACME to issue TLS for the gateway-emitted `forceSSL` `kb` vhost, while the central `auth` record is provisioned by the `sso-gateway` change

### Requirement: cognee's kanidm and perimeter plumbing is owned by the shared sso-gateway

cognee SHALL NOT declare any kanidm OAuth2 client (`provision.systems.oauth2.cognee`), any `cognee_access` group stub, or any client-secret/cookie-secret generator of its own.
All of that plumbing is owned by the shared `sso-gateway` change: cognee contributes `cognee_access` to the gateway's derivation purely by setting `sso.services.cognee.allowedGroups = [ "cognee_access" ]`, and the gateway auto-derives the `cognee_access` group stub (`{ members = []; overwriteMembers = false; }`, declared in `entitiesByName` before its `scopeMap` so the `kanidm.nix:876` referential-integrity assertion holds), the shared `sso-gateway` client's per-group `scopeMaps`, and `claimMaps.groups.valuesByGroup.cognee_access` from the union of registered services' `allowedGroups`.
`claimMaps.groups` (a new requirement relative to synapse, which uses no `claimMaps`) is set on the shared client by the gateway so oauth2-proxy's `allowed_groups` reads literal group names from the token; cognee never declares it.
cameron SHALL be added to `cognee_access` operationally rather than declaratively.

#### Scenario: cognee declares no kanidm client, group, or generator

- **WHEN** the cognee-side modules are evaluated
- **THEN** they declare no `provision.systems.oauth2.cognee` client, no `provision.groups.cognee_access` stub, and no `kanidm-oauth2-cognee` (or any other perimeter-secret) generator; the shared gateway owns and derives all of it

#### Scenario: the gateway auto-derives cognee_access from the registration

- **WHEN** cognee sets `sso.services.cognee.allowedGroups = [ "cognee_access" ]`
- **THEN** the shared gateway emits the `cognee_access` group stub (`members = []`, `overwriteMembers = false`) before its `scopeMap` (satisfying the `kanidm.nix:876` assertion), and adds `scopeMaps.cognee_access` and `claimMaps.groups.valuesByGroup.cognee_access = ["cognee_access"]` to the shared `sso-gateway` client, all without cognee declaring any of it

#### Scenario: cognee carries no perimeter secret topology

- **WHEN** the cognee public UI's secret needs are evaluated
- **THEN** cognee carries no client-secret or cookie-secret generator, no dual-context two-file split, and no container-uid mapping; the gateway's `DynamicUser` `oauth2-proxy-kanidm` unit consumes the gateway-owned secrets via `LoadCredential`, so the dual-context uid problem does not arise for cognee

### Requirement: A mechanical no-public-bind assertion

The cognee module SHALL promote the no-public-bind invariant from prose and manual checklist to a NixOS `assertion` that fails the build if `cfg.listenAddress`, the frontend `listenAddress`, or the postgres listen address resolves to anything other than loopback (`127.0.0.1`/`::1`) or the ZeroTier prefix (`fddb:4344:343b:14b9::/64`, the prefix of the `flake.lib.hosts.magnetite.zt` value).
A mechanical assertion is required because the retained `ip_nonlocal_bind=1` sysctl makes a wrong bind silent — the daemon binds an address it does not yet own without erroring — so a misconfigured public bind would not fail at runtime; a manual checklist does not catch it.
The invariant SHALL hold: the REST API binds ZeroTier-only `[fddb:4344:343b:14b9:399:930f:39db:40d2]:9270`, the frontend loopback `127.0.0.1:3000`, postgres loopback `127.0.0.1:5432`, and nginx 443 is the only public surface, reaching cognee only through the oauth2-proxy.

#### Scenario: a wrong public bind fails the build

- **WHEN** `cfg.listenAddress`, the frontend `listenAddress`, or the postgres listen address resolves to anything other than loopback or the ZeroTier prefix
- **THEN** the NixOS assertion fails the build before deploy, rather than the daemon binding a public interface silently under `ip_nonlocal_bind=1`

#### Scenario: every cognee listener binds only to loopback or ZeroTier

- **WHEN** the magnetite cognee configuration is evaluated and the assertion passes
- **THEN** the REST API listens only on `flake.lib.hosts.magnetite.zt:9270`, the frontend only on `127.0.0.1:3000`, and postgres only on `127.0.0.1:5432`, with nginx 443 the sole public surface reaching cognee only through the oauth2-proxy

### Requirement: Deploy from the single chain tip, not the multi-parent development join

The deploy phase SHALL build and deploy from the single `declarative-cognee-endpoint` chain tip, NOT from the multi-parent `@` `[wip]` of a diamond development join.
The diamond SHALL be re-mapped before the deploy phase and the deploy pinned to the recomputed chain tip, because the join's parent set can change (N can increase) between phases.
A clan deploy from a multi-parent `[wip]` builds the integrated tree of all active chains, so sibling-chain work would reach production as a side effect (the diamond-wip-deploy-pulls-all-chains hazard); deploying from the single chain tip isolates this change.

#### Scenario: the deploy is isolated to this change's chain tip

- **WHEN** the change is deployed to magnetite
- **THEN** the build and deploy are pinned to the single `declarative-cognee-endpoint` chain tip after re-mapping the diamond, never the multi-parent `[wip]`, so no sibling-chain work reaches production as a side effect

### Requirement: Rollback completeness

Rollback SHALL cover, in coherent order, every piece of state the naive "remove the modules" rollback leaves behind.
It SHALL remove the in-repo modules and the `flake.lib` additions, remove the `kb` Cloudflare DNS record via `just terraform*` (the central `auth` record is the `sso-gateway` change's), remove the `sso.services.cognee` registration so the shared gateway stops emitting the `kb` vhost and drops `cognee_access` from its derived kanidm union, and revert the cognee-nix input bump in `flake.nix`/`flake.lock`.
The shared gateway's own residual state — its perimeter secret files and its orphaned `sso-gateway` kanidm client (which `provision.autoRemove = false` preserves) — is owned and rolled back by the `sso-gateway` change, NOT this one; cognee declares none of it.
It SHALL restore mesh-client reachability coherently by re-adding the MCP client and removing `COGNEE_SERVICE_URL` in the same step, because the two are coupled: removing the service URL without re-adding the MCP client leaves the plugin with no path to cognee.

#### Scenario: rollback removes all residual state

- **WHEN** the change is rolled back
- **THEN** the in-repo modules and `flake.lib` additions are removed, the `kb` DNS record is removed via `just terraform*`, the `sso.services.cognee` registration is removed (so the gateway stops emitting the `kb` vhost and drops `cognee_access` from its derived union), and the cognee-nix input bump is reverted, while the gateway's own secret files and orphaned `sso-gateway` client are the `sso-gateway` change's rollback concern

#### Scenario: the coupled MCP-client-re-add and service-URL-removal restore reachability

- **WHEN** rollback restores mesh-client reachability
- **THEN** the MCP client is re-added and `COGNEE_SERVICE_URL` is removed in the same step, because removing the service URL without re-adding the MCP client would leave the plugin with no path to cognee
