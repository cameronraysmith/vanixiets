## ADDED Requirements

### Requirement: Single canonical nix source of truth for the cognee endpoint

The configuration SHALL expose a single typed nix source of truth for the cognee endpoint as two layers, each consolidated into a single file because `flake.lib` is `lazyAttrsOf raw`: a per-host ZeroTier-address registry `flake.lib.hosts.<host>.zt` (with `magnetite.zt` set to the magnetite ZeroTier IPv6 address `fddb:4344:343b:14b9:399:930f:39db:40d2`) and a derived `flake.lib.cognee` record carrying at least `meshApiUrl`, `apiPort`, and `publicFqdn`.
The record SHALL NOT carry any MCP URL (no `mcpUrl`, `meshMcpUrl`, or `publicMcpUrl`), because the cognee MCP is removed entirely by this change.
Every cognee consumer SHALL read the endpoint from this source of truth rather than from a hardcoded literal: the cognee server bind, the plugin env, the CLI wrapper, and the public-UI FQDN.

#### Scenario: the mesh API URL is derived from the host registry

- **WHEN** `flake.lib.cognee.meshApiUrl` is evaluated
- **THEN** it is derived from `flake.lib.hosts.magnetite.zt` and `flake.lib.cognee.apiPort` (resolving to `http://[fddb:4344:343b:14b9:399:930f:39db:40d2]:9270`) rather than restating the ZeroTier address literal

#### Scenario: the record carries no MCP URL

- **WHEN** `flake.lib.cognee` is evaluated
- **THEN** it exposes no `mcpUrl`, `meshMcpUrl`, or `publicMcpUrl` attribute, because the cognee MCP is dropped

#### Scenario: flake.lib additions are single-file consolidations

- **WHEN** the host registry and the cognee record are added to `flake.lib`
- **THEN** each is consolidated into its own single file, satisfying the `lazyAttrsOf raw` constraint that forbids multi-file writes at the same nested path

### Requirement: Drop the cognee MCP entirely (client and server)

The cognee MCP SHALL be abandoned entirely on both sides.
On the client side, `modules/home/ai/claude-code/mcp-servers.nix` SHALL NOT contain a cognee entry and SHALL NOT generate `~/.mcp/cognee.json`.
On the server side, `modules/nixos/cognee.nix` SHALL set `services.cognee.mcp.enable = false` and SHALL NOT open the MCP port (9271) on the ZeroTier (`zt+`) firewall interface.
The hardcoded ZeroTier IPv6 MCP literal `http://[fddb:4344:343b:14b9:399:930f:39db:40d2]:9271/mcp` SHALL NOT appear in any repointed consumer.

#### Scenario: the MCP client config is removed

- **WHEN** `modules/home/ai/claude-code/mcp-servers.nix` is evaluated
- **THEN** it contains no cognee entry, generates no `~/.mcp/cognee.json`, and contains no hardcoded cognee MCP IPv6 literal

#### Scenario: the server MCP and its firewall opening are removed

- **WHEN** `modules/nixos/cognee.nix` is evaluated for magnetite
- **THEN** `services.cognee.mcp.enable` is `false` and port 9271 is not opened on the `zt+` interface

#### Scenario: no remaining consumer references the cognee MCP

- **WHEN** the codex and opencode agent configurations are inspected
- **THEN** none declares a cognee MCP server, so nothing consumes the server-side MCP after the client is dropped

### Requirement: Bind the cognee REST API ZeroTier-only

The cognee REST API (port 9270, bound `127.0.0.1` loopback-only today with the firewall closed) SHALL be made reachable over the ZeroTier mesh and ONLY over the ZeroTier mesh so the always-on plugin's REST client and the cognee-cli wrapper can reach the central graph: `modules/nixos/cognee.nix` SHALL set the single `types.str` REST listen address to `flake.lib.hosts.magnetite.zt` (fail-closed, no dual-bind patch) and the firewall SHALL admit port 9270 only on the ZeroTier (`zt+`) interface.
This SHALL NOT widen the attack surface relative to the prior deployment, because the now-removed MCP already proxied full REST capability unauthenticated over the same mesh; this is the same capability reached by a more direct path.

#### Scenario: REST is mesh-reachable but not public

- **WHEN** a mesh member queries the cognee REST API at `flake.lib.cognee.meshApiUrl`
- **THEN** the request reaches the central cognee, while port 9270 is not reachable from the public internet

#### Scenario: REST replaces the dropped MCP as the mesh surface

- **WHEN** the server configuration is evaluated after the MCP is disabled
- **THEN** the REST API on `flake.lib.hosts.magnetite.zt:9270` is the mesh-facing surface and the prior 9271 MCP opening is gone

### Requirement: The cognee plugin is an always-on global pointed at central magnetite

The cognee plugin (the `cognee-memory` hooks plus skills) SHALL be made always-on global by setting `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` via home-manager `home.sessionVariables`, so every session's plugin connects to the central magnetite cognee in managed mode (connect to the remote, never boot a local server).
Because cognee app-level auth is disabled in this deployment, no `COGNEE_API_KEY` SHALL be set in v1; the plugin's optional `X-Api-Key` auth degrades to the cognee default user.
The plugin SHALL remain the passive-memory engine (auto-capture of tool traces, auto-recall on prompt, and the end-of-session graph bridge).

#### Scenario: a non-local service URL puts the plugin in managed mode

- **WHEN** any session starts and the cognee plugin runs with `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` inherited from `home.sessionVariables`
- **THEN** the plugin connects to the remote magnetite cognee in managed mode and never boots a local server

#### Scenario: no client API key is required in v1

- **WHEN** the plugin env is delivered declaratively
- **THEN** `COGNEE_API_KEY` is unset because cognee app-level auth is disabled, and the plugin reaches cognee as the default user

#### Scenario: the always-on plugin degrades when magnetite is unreachable

- **WHEN** a laptop is off the ZeroTier mesh or magnetite is offline so `flake.lib.cognee.meshApiUrl` cannot be reached
- **THEN** the always-on plugin degrades gracefully (it connects-only and does not boot a local fallback server), so cognee is simply unavailable that session

### Requirement: Global cognee-cli wrapper baking the mesh API URL

A global cognee-cli wrapper SHALL be provided as a first-class nix package (a `writeShellApplication` over `pkgs.cognee`, supplied by the already-wired cognee-nix overlay) that bakes `--api-url ${flake.lib.cognee.meshApiUrl}` into every invocation, because the CLI requires `--api-url` to enter HTTP-delegate mode and has no environment fallback for it.
The wrapper SHALL be installed globally via a home-manager module and SHALL be independent of the plugin's bundled venv.
For consistency with the plugin, when a client credential is eventually introduced the wrapper SHALL use `--api-key` (sent as `X-Api-Key`), never `--api-token` (Bearer); in v1 no key is passed because cognee auth is disabled.

#### Scenario: the wrapper bakes the required api-url

- **WHEN** the cognee-cli wrapper is invoked
- **THEN** it passes `--api-url ${flake.lib.cognee.meshApiUrl}` so the CLI enters HTTP-delegate mode against central magnetite without relying on any environment fallback

#### Scenario: the wrapper is a first-class package decoupled from the plugin venv

- **WHEN** the home-manager module installs the wrapper
- **THEN** it is a standalone `writeShellApplication` over `pkgs.cognee` (the cognee-nix overlay package), accepting the per-host closure footprint (~1.5 GiB), independent of the plugin's bundled venv

### Requirement: The cognee frontend is rebuilt for same-origin and bound to loopback

The cognee frontend SHALL be rebuilt in the cognee-nix fork with `NEXT_PUBLIC_LOCAL_API_URL=""` (build-time inlined) so the browser calls same-origin `/api/` rather than `localhost:8000`, and the module's injected `NEXT_PUBLIC_BACKEND_API_URL` SHALL be dropped because upstream reads `NEXT_PUBLIC_LOCAL_API_URL` and that injection is inert.
The rebuilt frontend SHALL be enabled and bound to loopback `127.0.0.1:3000`, never to a public interface.

#### Scenario: the frontend calls same-origin /api

- **WHEN** the rebuilt frontend is served and the browser issues backend requests
- **THEN** it calls same-origin `/api/` (because `NEXT_PUBLIC_LOCAL_API_URL` is `""` at build time) rather than `localhost:8000`, and the inert `NEXT_PUBLIC_BACKEND_API_URL` injection is absent

#### Scenario: the frontend binds loopback only

- **WHEN** the magnetite cognee configuration is evaluated
- **THEN** the frontend listens only on `127.0.0.1:3000` and is reachable publicly only through the nginx vhost

### Requirement: kanidm-gated public browser UI at kb.scientistexperience.net via a dedicated containerized oauth2-proxy

The public browser UI SHALL be served at `kb.scientistexperience.net` by a bespoke host nginx 443 vhost (`forceSSL` plus ACME), NOT the module's built-in `services.cognee.nginx`, routing `location /` to the loopback frontend `127.0.0.1:3000` and `location /api/` to the ZeroTier REST API `[fddb:4344:343b:14b9:399:930f:39db:40d2]:9270`, with `auth_request` against a dedicated containerized kanidm oauth2-proxy.
The oauth2-proxy SHALL be a dedicated NixOS container running its own `services.oauth2-proxy` (`provider = "oidc"`, PKCE) against kanidm, listening on a unix socket (the jfly `oauth2-proxies-nginx` pattern), and SHALL NOT reuse the nixpkgs host `services.oauth2-proxy` singleton.
Buildbot's existing `accessMode.fullyPrivate` GitHub-backed oauth2-proxy singleton and its auth configuration SHALL be left entirely untouched, with no buildbot change and no buildbot prerequisite.
A new kanidm OAuth2 client SHALL be registered via `services.kanidm.provision.systems.oauth2.cognee`, mirroring the synapse client, with `scopeMaps.cognee_access = ["openid" "email" "groups"]` and `claimMaps.groups`.
The allowlist SHALL be kanidm group membership `cognee_access`, defined as a stub group `provision.groups.cognee_access = { members = []; overwriteMembers = false; }` with `provision.autoRemove = false`, with cameron added operationally; behind the proxy cognee SHALL run as its single default user (`cameron@scientistexperience.net`) with app-level auth off.
The `kb` Cloudflare DNS record SHALL be provisioned via terranix reading `flake.lib.cognee.publicFqdn` as the source of truth where the terranix eval can reach `flake.lib`, as a CNAME to `magnetite.scientistexperience.net` with `ttl = 1` and `proxied = false` so ACME succeeds, cloned from the existing niks3/buildbot/git records and applied via `just terraform*` (never `nix run .#terraform`).

#### Scenario: only members of cognee_access reach the UI

- **WHEN** a request hits `kb.scientistexperience.net`
- **THEN** the host nginx vhost runs `auth_request` against the dedicated containerized kanidm oauth2-proxy, which admits only kanidm `cognee_access` group members before nginx routes `/` to the loopback frontend and `/api/` to the ZeroTier REST API

#### Scenario: buildbot's oauth2-proxy singleton is untouched

- **WHEN** the cognee oauth2-proxy is provisioned as a dedicated NixOS container
- **THEN** buildbot's `accessMode.fullyPrivate` GitHub-backed host `services.oauth2-proxy` singleton and its auth configuration are unchanged, with no shared blast radius

#### Scenario: the functional UI renders under the single default user

- **WHEN** a `cognee_access` member is admitted through the proxy and the rebuilt same-origin frontend loads
- **THEN** cognee behind the gate renders functionally as its single default user (`cameron@scientistexperience.net`) with app-level auth off, with no per-user SSO into cognee in this phase

#### Scenario: ACME issuance succeeds for the kb record

- **WHEN** the `kb` Cloudflare DNS record is created via terranix and applied with `just terraform*`
- **THEN** it reads `flake.lib.cognee.publicFqdn` as the source of truth (where the eval can reach `flake.lib`), is a CNAME to `magnetite.scientistexperience.net` with `ttl = 1` and `proxied = false`, allowing ACME to issue TLS for the `forceSSL` nginx vhost

### Requirement: Single clan-vars generator with dual-consumer bare-value files

A single clan-vars generator `kanidm-oauth2-cognee` SHALL emit two bare-value files: `files.secret` (owner kanidm) and `files.cookie`.
`files.secret` SHALL feed both the kanidm-provision `basicSecretFile` for the `cognee` oauth2 client AND the oauth2-proxy `clientSecretFile`.
`files.cookie` SHALL feed the oauth2-proxy `cookie.secretFile`.
The generator SHALL set `restartUnits` on `kanidm.service` and the oauth2-proxy unit, because both consume the secret via a credential snapshot taken at unit start.
The files SHALL be bare values with no KEY=VALUE env-file shaping.

#### Scenario: one generator satisfies both consumers

- **WHEN** the `kanidm-oauth2-cognee` generator is evaluated
- **THEN** `files.secret` (owner kanidm) feeds both the kanidm-provision `basicSecretFile` and the oauth2-proxy `clientSecretFile`, and `files.cookie` feeds the oauth2-proxy `cookie.secretFile`, all as bare values

#### Scenario: regenerated secrets restart their consumers

- **WHEN** the `kanidm-oauth2-cognee` secret is regenerated
- **THEN** the generator's `restartUnits` restarts `kanidm.service` and the oauth2-proxy unit so the new value is not left stale behind a unit-start credential snapshot

### Requirement: Each gated service owns its identity plumbing and kanidm.nix stays a pure IdP scaffold

The cognee module SHALL own its own kanidm oauth2 client (`provision.systems.oauth2.cognee`), its own `cognee_access` group, and its own `kanidm-oauth2-cognee` secret generator.
`modules/nixos/kanidm.nix` SHALL remain a pure IdP scaffold and SHALL NOT be edited to add per-service cognee client, group, or generator definitions.

#### Scenario: the cognee client, group, and generator live in the cognee module

- **WHEN** the cognee module is evaluated
- **THEN** it declares the `provision.systems.oauth2.cognee` client, the `cognee_access` group, and the `kanidm-oauth2-cognee` generator, while `modules/nixos/kanidm.nix` remains a pure IdP scaffold with no cognee-specific additions

### Requirement: No-public-bind security invariant with app-auth off

In v1 cognee app-level auth SHALL be off everywhere (`auth.multiTenant = false`, `REQUIRE_AUTHENTICATION` unset), and the only gates SHALL be ZeroTier membership (for mesh/machine clients) and the containerized oauth2-proxy/kanidm perimeter (for the public browser).
Because cognee's SPA fails open with app-auth off (its `LocalProvider` only redirects on HTTP 401/403, and `/api/v1/users/me` returns 200 as the default user), the perimeter gate is the SOLE access-control layer for the public path.
As the load-bearing invariant, every cognee listener SHALL bind ONLY to loopback or to the ZeroTier address, NEVER to a public interface: the REST API ZeroTier-only `[fddb:4344:343b:14b9:399:930f:39db:40d2]:9270`, the frontend loopback `127.0.0.1:3000`, and postgres loopback `127.0.0.1:5432`; nginx 443 SHALL be the only public surface, and the public internet SHALL reach cognee ONLY through nginx then the oauth2-proxy.
Enabling cognee app-level auth (`REQUIRE_AUTHENTICATION`) SHALL be a separate future change and SHALL NOT be coupled to the kanidm UI; its true hard coupling SHALL be recorded: enabling app-auth requires simultaneously provisioning and wiring the mesh clients' `X-Api-Key` credential (clan-vars to `home.sessionVariables` plus the CLI wrapper), or the always-on plugin breaks fleet-wide.

#### Scenario: every cognee listener binds only to loopback or ZeroTier

- **WHEN** the magnetite cognee configuration is evaluated
- **THEN** the REST API listens only on `flake.lib.hosts.magnetite.zt:9270`, the frontend only on `127.0.0.1:3000`, and postgres only on `127.0.0.1:5432`, with no listener bound to a public interface and nginx 443 the sole public surface

#### Scenario: app-auth-off is safe because the perimeter is the sole gate

- **WHEN** an unauthenticated request arrives from the public internet
- **THEN** it can only traverse nginx then the containerized oauth2-proxy, which gates it on kanidm `cognee_access` membership before any traffic reaches the app-auth-off, fail-open cognee

#### Scenario: enabling app-auth is decoupled from the UI but coupled to the mesh credential

- **WHEN** a future change enables `REQUIRE_AUTHENTICATION`
- **THEN** it is independent of the kanidm UI but must simultaneously provision and wire the mesh clients' `X-Api-Key` credential into `home.sessionVariables` and the CLI wrapper, or the always-on plugin breaks fleet-wide
