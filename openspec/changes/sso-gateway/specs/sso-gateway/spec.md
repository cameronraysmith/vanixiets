## ADDED Requirements

### Requirement: A shared bespoke kanidm-OIDC SSO gateway unit

The configuration SHALL define a single shared kanidm-OIDC SSO gateway as a bespoke `systemd.services.oauth2-proxy-kanidm` unit running `${pkgs.oauth2-proxy}/bin/oauth2-proxy` directly, with `DynamicUser = true`, a `RuntimeDirectory`, and `Restart = "always"`, listening on `127.0.0.1:4181`.
It SHALL NOT use the nixpkgs `services.oauth2-proxy` module (which buildbot owns as a host singleton) and SHALL NOT run as a NixOS container.
The gateway SHALL be configured `--provider=oidc` against kanidm with `--oidc-issuer-url=https://accounts.scientistexperience.net/oauth2/openid/sso-gateway` (auto-discovery), `--client-id=sso-gateway`, `--client-secret-file` and `--cookie-secret-file` from systemd `LoadCredential`, `--email-domain=*`, `--reverse-proxy=true`, `--trusted-proxy-ip=127.0.0.1`, `--set-xauthrequest=true`, and `--code-challenge-method=S256`.
A single shared unit SHALL gate many vhosts, because oauth2-proxy cannot run multiple providers in one process (upstream issue #926) and the nixpkgs module is a hard singleton already owned by buildbot.

#### Scenario: the gateway is a bespoke unit, not services.oauth2-proxy and not a container

- **WHEN** the magnetite NixOS configuration is evaluated
- **THEN** `systemd.services.oauth2-proxy-kanidm` runs `${pkgs.oauth2-proxy}/bin/oauth2-proxy` directly with `DynamicUser = true` and `Restart = "always"` on `127.0.0.1:4181`, and the nixpkgs `services.oauth2-proxy` module is not used for it and it is not a NixOS container

#### Scenario: the gateway runs the oidc provider with PKCE against kanidm

- **WHEN** the gateway unit's command line is evaluated
- **THEN** it sets `--provider=oidc`, `--oidc-issuer-url=https://accounts.scientistexperience.net/oauth2/openid/sso-gateway`, `--client-id=sso-gateway`, `--code-challenge-method=S256`, `--set-xauthrequest=true`, `--reverse-proxy=true`, and `--trusted-proxy-ip=127.0.0.1`, reading its client and cookie secrets from `LoadCredential`

### Requirement: A central auth domain owning a single redirect and a static client

The gateway SHALL own a central auth subdomain `sso.authDomain` (default `auth.scientistexperience.net`) that holds the single `/oauth2/` surface and the single kanidm redirect URI `https://auth.scientistexperience.net/oauth2/callback`, backed by one shared kanidm OAuth2 client `sso-gateway`.
The central auth subdomain SHALL be served by a dedicated nginx vhost with `forceSSL = true` and `enableACME = true`.
The gateway SHALL set `--redirect-url=https://auth.scientistexperience.net/oauth2/callback`.
Adding a consumer SHALL NOT change the kanidm client or the redirect URI: a new consumer adds an nginx vhost and a group authorization, never a kanidm client edit or a new redirect URI, so the kanidm client stays static as consumers are added.

#### Scenario: the central auth vhost owns the only oauth2 callback

- **WHEN** the gateway is evaluated
- **THEN** the `auth.scientistexperience.net` vhost (`forceSSL`, `enableACME`) owns the single `/oauth2/` surface and the single redirect URI `https://auth.scientistexperience.net/oauth2/callback`, and no per-service vhost owns its own `/oauth2/` callback

#### Scenario: adding a consumer leaves the kanidm client static

- **WHEN** a new service is registered via `sso.services.<name>`
- **THEN** the shared kanidm OAuth2 client `sso-gateway` and the single redirect URI are unchanged, and only an nginx vhost and a group authorization are added

### Requirement: Cross-subdomain SSO via a domain-wide cookie

The gateway SHALL provide cross-subdomain single-login SSO by setting `--cookie-domain=.scientistexperience.net` (from `sso.cookieDomain`, default `.scientistexperience.net`) and `--whitelist-domain=.scientistexperience.net`, so a single login is valid across every gated subdomain.
`--whitelist-domain` SHALL be passed as a CLI flag, because the nixpkgs `services.oauth2-proxy` module does not expose it and the gateway unit is hand-rolled.

#### Scenario: one login spans every gated subdomain

- **WHEN** a user authenticates once at any gated subdomain under `.scientistexperience.net`
- **THEN** the gateway's `--cookie-domain=.scientistexperience.net` cookie makes that session valid across every other gated subdomain without a second login, and `--whitelist-domain=.scientistexperience.net` permits the cross-subdomain redirects back

### Requirement: A distinct cookie name so buildbot's cookie is never shadowed

The gateway SHALL set a distinct `--cookie-name=_sso_gateway`, and SHALL NOT use the default cookie name `_oauth2_proxy`.
This is a hard constraint because buildbot's oauth2-proxy uses the default cookie name `_oauth2_proxy` as a host-only cookie (verified against buildbot-nix `master.nix`: no `cookie-name`/`cookie-domain` set, so defaults apply), and a domain-wide cookie (the cross-subdomain SSO cookie) sharing buildbot's default name would shadow buildbot's host-only cookie on shared subdomains and break buildbot auth.

#### Scenario: the gateway cookie does not collide with buildbot's cookie

- **WHEN** the gateway sets a domain-wide cookie on `.scientistexperience.net`
- **THEN** it uses the distinct name `_sso_gateway`, never the default `_oauth2_proxy`, so buildbot's host-only `_oauth2_proxy` cookie is not shadowed and buildbot auth is unaffected

### Requirement: Per-vhost group authorization via query-param allowed_groups

Each registered service's nginx vhost SHALL run `auth_request /oauth2/auth?allowed_groups=<group>`, passing the service's authorized group as a query parameter, because nginx cannot otherwise pass arguments to `auth_request`.
Browser vhosts SHALL redirect a 401 to the sign-in flow, and API paths SHALL use `error_page 401 =401` to fail fast.
A single shared `oauth2-proxy-kanidm` instance SHALL enforce a different group per vhost via the query-param `allowed_groups`, with no per-service oauth2-proxy instance created.

#### Scenario: each vhost enforces its own group through one shared proxy

- **WHEN** a request reaches a registered service's vhost
- **THEN** nginx runs `auth_request /oauth2/auth?allowed_groups=<group>` against the single shared `oauth2-proxy-kanidm`, which admits only members of that service's group, so different vhosts enforce different groups without any additional oauth2-proxy instance

#### Scenario: browser and API 401s are handled differently

- **WHEN** an unauthenticated request hits a gated vhost
- **THEN** a browser vhost redirects the 401 to the sign-in flow while an API path uses `error_page 401 =401` to return a clean fast 401 rather than an HTML redirect

### Requirement: Reusable per-service registration auto-deriving the kanidm client config

The configuration SHALL provide a reusable `flake.modules.nixos.sso-gateway` module exposing `sso.authDomain` (default `auth.scientistexperience.net`), `sso.cookieDomain` (default `.scientistexperience.net`), and `sso.services = attrsOf (submodule { domain; allowedGroups = listOf str; upstream = attrsOf str; })` where `upstream` maps nginx `location` paths to `proxyPass` targets.
The module SHALL (a) define the bespoke `oauth2-proxy-kanidm` unit, (b) define the central auth vhost (`forceSSL` + `enableACME`), (c) for each registered service emit a `forceSSL`+`enableACME` nginx vhost with the `upstream` locations plus the `auth_request` wiring, and (d) AUTO-DERIVE the `services.kanidm.provision` additions from the union of all registered services' `allowedGroups`: the group stubs (`{ members = []; overwriteMembers = false; }`), the shared `sso-gateway` client's `scopeMaps` per group, and `claimMaps.groups.valuesByGroup` per group.
Each derived group stub SHALL be declared in `entitiesByName` before any `scopeMap` references it, satisfying the `kanidm.nix:876` referential-integrity assertion.
For each derived group the client SHALL set `scopeMaps.<group> = ["openid" "email" "profile"]` and `claimMaps.groups = { joinType = "array"; valuesByGroup.<group> = ["<group>"]; }`, so the token's `groups` claim carries clean literal group names that oauth2-proxy's `--allowed-group`/`?allowed_groups=` match exactly; `claimMaps.groups` is a new requirement because synapse uses `scopeMaps` but no `claimMaps`.
A consumer's footprint SHALL be just three declarative lines of `sso.services.<name>` (`domain`, `allowedGroups`, `upstream`).
One shared client weakens per-service OAuth isolation versus per-service clients; this tradeoff SHALL be recorded, accepted as the cost of shared-gateway SSO and simplicity.

#### Scenario: a consumer registers in three declarative lines

- **WHEN** a consumer sets `sso.services.<name>` with `domain`, `allowedGroups`, and `upstream`
- **THEN** the module emits the service's `forceSSL`+`enableACME` vhost with the `upstream` locations and the `auth_request` wiring, and the consumer hand-writes no oauth2-proxy, no nginx auth block, and no kanidm group/scopeMap/claimMap

#### Scenario: the kanidm provisioning is auto-derived from the union of allowed groups

- **WHEN** the registered services' `allowedGroups` are unioned
- **THEN** each distinct group becomes a `provision.groups.<group> = { members = []; overwriteMembers = false; }` stub declared before its scopeMap, and the one shared `provision.systems.oauth2.sso-gateway` client gains `scopeMaps.<group> = ["openid" "email" "profile"]` and `claimMaps.groups.valuesByGroup.<group> = ["<group>"]`

#### Scenario: claimMaps.groups carries clean literal group names

- **WHEN** a token is issued by the shared `sso-gateway` client
- **THEN** its `groups` claim carries each group's clean literal name (via `claimMaps.groups.valuesByGroup`), so oauth2-proxy's `--allowed-group`/`?allowed_groups=` match exactly, and this `claimMaps.groups` is a deliberate new requirement because synapse uses no `claimMaps`

### Requirement: Gateway secrets via clan-vars with restart-on-rotation

The gateway SHALL deliver its OAuth2 client secret and its cookie secret via two clan-vars generators, both consumed through systemd `LoadCredential`.
The `kanidm-oauth2-sso` generator SHALL emit the OAuth2 client secret with owner `kanidm`, `mode = "0400"`, `secret = true`, and `restartUnits = [ "kanidm.service" "oauth2-proxy-kanidm.service" ]`, consumed by host-side kanidm-provision (`basicSecretFile`) and by the gateway unit.
The `sso-cookie-secret` generator SHALL emit a 32-byte cookie secret in an acceptable encoding (oauth2-proxy requires a 16/24/32-byte cookie secret), `mode = "0400"`, `secret = true`, and `restartUnits = [ "oauth2-proxy-kanidm.service" ]`.
Because `LoadCredential` snapshots a credential at unit start, a rotated secret stays stale until the consuming units restart; therefore `restartUnits` SHALL name the real units (`kanidm.service` for provision, `oauth2-proxy-kanidm.service` for the gateway).

#### Scenario: two generators feed the gateway via LoadCredential

- **WHEN** the gateway secrets are evaluated
- **THEN** `kanidm-oauth2-sso` emits the client secret (owner `kanidm`, `0400`, `secret = true`) consumed by kanidm-provision and the gateway, and `sso-cookie-secret` emits a 32-byte cookie secret (`0400`, `secret = true`) consumed by the gateway, both delivered via systemd `LoadCredential`

#### Scenario: a rotated secret restarts the named consuming units

- **WHEN** the client secret or the cookie secret is rotated
- **THEN** `restartUnits` restarts the named units (`kanidm.service` and `oauth2-proxy-kanidm.service` for the client secret, `oauth2-proxy-kanidm.service` for the cookie secret), so the new value is not left stale behind a unit-start `LoadCredential` snapshot

### Requirement: Buildbot and synapse non-interference

The gateway SHALL leave buildbot's `services.oauth2-proxy` instance entirely untouched and SHALL leave synapse's kanidm client unaffected, with no buildbot or synapse file edited and no buildbot or synapse prerequisite.
buildbot non-interference SHALL rest on three deliberate separations: a different provider (the gateway is OIDC/kanidm, buildbot is GitHub), a different instance (the bespoke `oauth2-proxy-kanidm` unit versus buildbot's `services.oauth2-proxy` singleton), and a distinct cookie name (`_sso_gateway` versus the default `_oauth2_proxy`).
synapse non-interference SHALL rest on synapse being a DIRECT kanidm OIDC client (`modules/nixos/matrix.nix:300-320`), never behind oauth2-proxy, and on kanidm provisioning being per-client isolated under `provision.autoRemove = false`, so the new shared `sso-gateway` client, the new group stubs, and the new `claimMaps.groups` are purely additive and cannot affect the synapse client.

#### Scenario: buildbot's oauth2-proxy singleton is unchanged

- **WHEN** the gateway is provisioned as a bespoke second oauth2-proxy instance
- **THEN** buildbot's `services.oauth2-proxy` instance is unchanged — a different provider (GitHub vs OIDC/kanidm), a different instance, and a distinct cookie name (`_oauth2_proxy` vs `_sso_gateway`) — with no buildbot file edited

#### Scenario: synapse's kanidm client is unaffected by the gateway's additions

- **WHEN** the gateway's shared `sso-gateway` client, group stubs, and `claimMaps.groups` are added to the kanidm provision tree
- **THEN** synapse's kanidm client is unaffected, because synapse is a direct kanidm OIDC client never behind oauth2-proxy and kanidm provisioning is per-client isolated under `autoRemove = false`, so the gateway's additions are purely additive
