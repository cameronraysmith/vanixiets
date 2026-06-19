## Context

Several internal magnetite web UIs need kanidm-OIDC authentication gating.
cognee is the first; dagster and signoz are anticipated next.
Rather than each service standing up its own perimeter, this change delivers one reusable shared SSO gateway that gates many vhosts behind a single central auth surface, giving cross-subdomain single-login SSO.

Confirmed magnetite facts (verified, load-bearing, not open questions):

- buildbot already owns the host's single nixpkgs `services.oauth2-proxy` instance, pinned to the GitHub provider (buildbot-nix `master.nix:1145-1187`; vanixiets `buildbot.nix:118-125`).
- oauth2-proxy cannot run multiple providers in one process (upstream issue #926). The nixpkgs `services.oauth2-proxy` module is a hard singleton: one systemd unit, one provider, one client. A kanidm-gated service therefore needs a SECOND oauth2-proxy instance.
- buildbot's oauth2-proxy sets no `cookie-name` and no `cookie-domain`, so it uses the default cookie name `_oauth2_proxy` as a host-only cookie. This was verified against buildbot-nix `master.nix` (no `cookie-name`/`cookie-domain` set → defaults).
- kanidm is live at `https://accounts.scientistexperience.net` (`modules/nixos/kanidm.nix`, imported on magnetite). The live precedent is synapse: `modules/nixos/kanidm.nix` declares the `services.kanidm.provision.systems.oauth2.synapse` client, the synapse access group, and the synapse secret generator, while the consuming module reads the secret.
- synapse uses `scopeMaps` but no `claimMaps.groups`. synapse is a DIRECT kanidm OIDC client (`modules/nixos/matrix.nix:300-320`), never behind oauth2-proxy. kanidm provisioning is per-client isolated under `provision.autoRemove = false`.
- kanidm-provision asserts referential integrity: a group referenced by a `scopeMap` must be declared in `entitiesByName` before the reference (the `kanidm.nix:876` assertion), so any group stub must be declared before the scopeMap that references it.

This design is the reusable gateway only.
The existing `declarative-cognee-endpoint` change is revised separately to consume this gateway as consumer #1; dagster and signoz follow with their own consumer registrations.
Nothing service-specific is in scope here.

## Goals / Non-Goals

**Goals:**

Deliver one reusable shared kanidm-OIDC SSO gateway as a `flake.modules.nixos.sso-gateway` module that gates many vhosts behind a single central auth surface with cross-subdomain single-login SSO.
Define a bespoke `oauth2-proxy-kanidm` systemd unit running `${pkgs.oauth2-proxy}/bin/oauth2-proxy` directly, not buildbot's `services.oauth2-proxy` singleton and not a NixOS container.
Own a central `auth.scientistexperience.net` subdomain with a single `/oauth2/` surface and a single kanidm redirect URI, backed by one shared kanidm OAuth2 client `sso-gateway`, so the kanidm client stays static as consumers are added.
Provide cross-subdomain SSO via a `.scientistexperience.net` cookie under a deliberately distinct cookie name `_sso_gateway`, so buildbot's default-named host-only cookie is never shadowed.
Authorize per-vhost on kanidm group membership via query-param `allowed_groups`.
Make a consumer's footprint three declarative lines of `sso.services.<name>` by auto-deriving every kanidm provisioning addition from the union of registered services' allowed groups.
Deliver the gateway's client secret and cookie secret via clan-vars generators with `restartUnits` on rotation, consumed via systemd `LoadCredential`.

**Non-Goals (out of scope):**

Do not register any per-service consumer here; each consumer change registers its own `sso.services.<name>` (cognee is consumer #1 in its own change).
Do not migrate buildbot off its GitHub-provider `services.oauth2-proxy` singleton; it stays untouched.
Do not deliver cognee's same-origin frontend or any other consumer-specific deliverable; those live in the consumer changes.
Do not perform end-to-end browser-auth verification here; that is deferred to the first consumer's change, which supplies a real gated vhost. This change verifies the gateway itself (the unit evaluates, the central auth vhost is present, buildbot's `services.oauth2-proxy` is unchanged).

## Decisions

### D1: a bespoke oauth2-proxy-kanidm systemd unit, not services.oauth2-proxy and not a container

Define `systemd.services.oauth2-proxy-kanidm` running `${pkgs.oauth2-proxy}/bin/oauth2-proxy` directly, with `DynamicUser = true`, a `RuntimeDirectory`, and `Restart = "always"`.
It listens on `127.0.0.1:4181`.

Rationale: buildbot owns the host's single nixpkgs `services.oauth2-proxy` instance, which is a hard singleton (one unit, one provider, one client) and cannot host a second provider (upstream #926), so the kanidm gateway must be a second, independent instance.
A bespoke `systemd.services` unit is the minimal correct mechanism: a single shared unit gates many vhosts with one login session, and a hand-rolled unit lets us pass flags the nixpkgs module does not expose (notably `--whitelist-domain`).
A NixOS container is overkill for a single shared host unit.
Alternatives considered: reusing buildbot's `services.oauth2-proxy` (rejected — one-per-host, owned by buildbot, GitHub provider); a second `services.oauth2-proxy` (rejected — the module is a singleton; a second declaration is not supported); a NixOS container per the jfly `oauth2-proxies-nginx` pattern (rejected — overkill for one shared unit; the container indirection buys nothing when a host unit already isolates via `DynamicUser`).

### D2: a central auth subdomain with a single redirect URI and a static shared client

Own a central `auth.scientistexperience.net` subdomain that holds the single `/oauth2/` surface and the single kanidm redirect URI `https://auth.scientistexperience.net/oauth2/callback`, backed by one shared kanidm OAuth2 client `sso-gateway`.
The gateway flags set `--redirect-url=https://auth.scientistexperience.net/oauth2/callback`.

Rationale: a single redirect URI and a single client keep the kanidm registration static as consumers are added — a new consumer adds an nginx vhost and a group authorization, never a kanidm client edit or a new redirect URI.
The central auth vhost is the one place the `/oauth2/` flow lives; per-service vhosts only run `auth_request` against it.
Alternatives considered: a per-service redirect URI and per-service client (rejected — the kanidm registration would change on every consumer, defeating the static-client goal and fragmenting login); hosting `/oauth2/` on every service vhost (rejected — multiplies the callback surface and the redirect URIs).

### D3: cross-subdomain SSO via a domain-wide cookie

Set `--cookie-domain=.scientistexperience.net` plus `--whitelist-domain=.scientistexperience.net` on the gateway, so a single login is valid across every gated subdomain.
`--whitelist-domain` is passed as a CLI flag because the nixpkgs `services.oauth2-proxy` module does not expose it; here the unit is hand-rolled (D1), so the flag is passed directly.

Rationale: the domain-wide cookie is what makes single-login SSO span subdomains; without it each subdomain would require its own login.
`--whitelist-domain` is required so oauth2-proxy permits redirects back to the registered subdomains after auth.
Alternatives considered: a host-only cookie per subdomain (rejected — no SSO; the user logs in once per service); omitting `--whitelist-domain` (rejected — cross-subdomain redirects are rejected without it).

### D4: a distinct cookie name so buildbot's cookie is never shadowed (hard constraint)

Set a DISTINCT `--cookie-name=_sso_gateway`, never the default `_oauth2_proxy`.

This is a hard constraint, not a preference.
buildbot's oauth2-proxy uses the default cookie name `_oauth2_proxy` as a host-only cookie (verified against buildbot-nix `master.nix`: no `cookie-name`/`cookie-domain` set → defaults).
A domain-wide cookie (D3) sharing buildbot's default name would shadow buildbot's host-only cookie on shared subdomains and break buildbot auth.
Using a distinct name `_sso_gateway` keeps the two cookies disjoint, so buildbot's auth is untouched while the gateway's cookie is domain-wide.

Rationale: the collision is silent and breaks buildbot, so the distinct name is the mechanical guard.
Alternatives considered: leaving the default cookie name (rejected — a domain-wide `_oauth2_proxy` shadows buildbot's host-only `_oauth2_proxy`); scoping the gateway cookie host-only to avoid the collision (rejected — that defeats cross-subdomain SSO, the whole point of D3).

### D5: one shared kanidm client with per-access-group scopeMaps and claimMaps.groups

Provision one shared kanidm OAuth2 client `sso-gateway` (not a client per service).
For each access group registered across all consumers, set `scopeMaps.<group> = ["openid" "email" "profile"]` and `claimMaps.groups = { joinType = "array"; valuesByGroup.<group> = ["<group>"]; }`, so the token's `groups` claim carries clean literal group names.

oauth2-proxy authorizes on group membership via `--allowed-group`/`?allowed_groups=`, which match the literal group names in the token's `groups` claim exactly, so `claimMaps.groups` must project each group as its own literal name.
`claimMaps.groups` is a new requirement here: synapse uses `scopeMaps` but no `claimMaps`, so this is a deliberate addition, not a mirror of synapse.
The referential-integrity ordering (`kanidm.nix:876`) requires each group stub declared in `entitiesByName` before its `scopeMap`; the auto-derivation (D6) emits stubs and scopeMaps together so the ordering holds.

Tradeoff (explicit): a shared client weakens per-service OAuth isolation relative to per-service clients — a single client secret and a single token audience span every gated service.
This is accepted as the cost of shared-gateway SSO and simplicity; per-service clients would restore isolation but reintroduce per-consumer kanidm edits and fragment login.

Rationale: a single client is what makes one login session valid across services, and per-group scopeMaps/claimMaps give oauth2-proxy the literal group names it authorizes on.
Alternatives considered: a client per service (rejected — fragments login and reintroduces per-consumer kanidm edits, contradicting D2); omitting `claimMaps.groups` (rejected — oauth2-proxy's `allowed_groups` then has no groups claim to match); projecting raw kanidm group SPNs instead of literal names (rejected — `allowed_groups` matches the literal name, so the claim must carry clean literals).

### D6: a reusable module with sso.services registration auto-deriving the kanidm config

Define `flake.modules.nixos.sso-gateway` exposing:

- `sso.authDomain` (default `auth.scientistexperience.net`),
- `sso.cookieDomain` (default `.scientistexperience.net`),
- `sso.services = attrsOf (submodule { domain; allowedGroups (listOf str); upstream (attrsOf str, location -> proxyPass); })`.

The module:

- (a) defines the bespoke `oauth2-proxy-kanidm` unit (D1, D3, D4),
- (b) defines the central auth vhost (`forceSSL` + `enableACME`) at `sso.authDomain` (D2),
- (c) for each registered service emits a `forceSSL`+`enableACME` nginx vhost with the `upstream` locations plus the `auth_request` wiring (D7), and
- (d) AUTO-DERIVES the `services.kanidm.provision` additions from the union of all registered services' `allowedGroups`: the group stubs (`{ members = []; overwriteMembers = false; }`), the shared `sso-gateway` client's `scopeMaps` per group, and `claimMaps.groups.valuesByGroup` per group (D5).

This makes a consumer's footprint just three lines of `sso.services.<name>` (`domain`, `allowedGroups`, `upstream`).

Rationale: auto-derivation keeps the kanidm provisioning a single computed function of the registered services, so a consumer never hand-writes a group, a scopeMap, a claimMap, an oauth2-proxy instance, or auth wiring.
The union over `allowedGroups` is the natural derivation: each distinct group used by any service becomes a stub plus a scopeMap entry plus a claimMap entry on the one shared client.
Alternatives considered: requiring each consumer to declare its own kanidm group/scopeMap/claimMap (rejected — that is the duplication the shared gateway exists to remove); a fixed group list in the module (rejected — not reusable; new consumers would need module edits); per-service oauth2-proxy instances behind a thin module (rejected — fragments cookies and login, contradicting D1–D5).

### D7: per-vhost group authorization via query-param allowed_groups, with browser vs API error handling

Each registered service's nginx vhost runs `auth_request /oauth2/auth?allowed_groups=<group>`.
The `allowed_groups` is passed as a query parameter, because nginx cannot otherwise pass arguments to `auth_request`.
Browser vhosts redirect a 401 to the sign-in flow (so an unauthenticated browser is sent to log in); API paths use `error_page 401 =401` to fail fast (so an unauthenticated API call gets a clean 401 rather than an HTML redirect).

Rationale: a single shared oauth2-proxy enforces a different group per vhost only if the group travels with the auth subrequest, and the query param is the only nginx mechanism for that.
The browser-vs-API split matches the two consumer shapes: a browser UI wants a redirect to sign in, an API wants a fast 401.
Alternatives considered: a separate oauth2-proxy per group (rejected — defeats the shared gateway); a static `allowed_groups` baked into the proxy (rejected — then every vhost shares one group, with no per-service authorization); redirecting API 401s to the sign-in page (rejected — API clients cannot follow an interactive redirect).

### D8: gateway secrets via clan-vars generators with restart-on-rotation, delivered by LoadCredential

Two clan-vars generators:

- `kanidm-oauth2-sso` emits the OAuth2 client secret, owner `kanidm`, `mode = "0400"`, `secret = true`, `restartUnits = [ "kanidm.service" "oauth2-proxy-kanidm.service" ]`. It is consumed by host-side kanidm-provision (`basicSecretFile`) and by the gateway unit.
- `sso-cookie-secret` emits a 32-byte cookie secret, `restartUnits = [ "oauth2-proxy-kanidm.service" ]`. oauth2-proxy requires a 16/24/32-byte cookie secret; 32 is chosen.

The gateway unit receives both secrets via systemd `LoadCredential`.

Rationale: kanidm-provision and the gateway both consume the client secret; the gateway consumes the cookie secret.
`LoadCredential` snapshots the credential at unit start (the snapshot-staleness caveat), so a rotated secret stays stale until the consuming units restart; therefore `restartUnits` is mandatory and must name the real units (`kanidm.service` for provision, `oauth2-proxy-kanidm.service` for the gateway).
Alternatives considered: a single generator for both secrets (rejected — they have different consumers and the client secret needs `kanidm` ownership for `basicSecretFile`); delivering secrets by environment file rather than `LoadCredential` (rejected — `LoadCredential` is the established snapshot mechanism and keeps the secret out of the unit's environment); omitting `restartUnits` (rejected — a rotated secret would be silently stale behind the unit-start snapshot).

### D9: buildbot non-interference, verified

buildbot's `services.oauth2-proxy` instance is left entirely untouched: a different provider (GitHub vs OIDC/kanidm), a different instance (the bespoke `oauth2-proxy-kanidm` unit, D1), and a distinct cookie name (`_sso_gateway` vs the default `_oauth2_proxy`, D4).
No buildbot file is edited and no buildbot prerequisite exists.

Rationale: the three separations (provider, instance, cookie name) are exactly the axes on which a second oauth2-proxy could collide with buildbot, and each is deliberately kept disjoint, so buildbot's auth and blast radius are unchanged.
Alternatives considered: migrating buildbot onto the shared gateway (rejected — out of scope and expands blast radius; buildbot's GitHub provider serves a different audience).

### D10: synapse non-interference, verified

synapse is unaffected.
synapse is a DIRECT kanidm OIDC client (`modules/nixos/matrix.nix:300-320`), never behind oauth2-proxy, so it does not touch the gateway at all.
kanidm provisioning is per-client isolated under `provision.autoRemove = false`, so the new shared `sso-gateway` client, the new group stubs, and the new `claimMaps.groups` cannot affect the synapse client's registration.

Rationale: the only place the gateway and synapse could interact is the shared kanidm provision tree, and per-client isolation plus the new client being a distinct entity means the additions are purely additive to the synapse client.
This is recorded as a risk-assessment note because the shared provision tree is the one surface a reviewer would worry about.
Alternatives considered: none — synapse is a direct client and the gateway introduces only additive, isolated kanidm entities.

## Risks / Trade-offs

[Risk] A domain-wide gateway cookie under buildbot's default name would shadow buildbot's host-only cookie and break buildbot auth. → Mitigation: a distinct `--cookie-name=_sso_gateway` (D4), kept disjoint from buildbot's default `_oauth2_proxy`.

[Risk] oauth2-proxy cannot run multiple providers in one process (upstream #926) and the nixpkgs module is a singleton owned by buildbot. → Mitigation: a bespoke second instance `oauth2-proxy-kanidm` running the binary directly (D1), leaving buildbot's instance untouched.

[Risk] A rotated client or cookie secret is silently stale because `LoadCredential` snapshots at unit start. → Mitigation: both generators name the real consuming units in `restartUnits` (D8).

[Risk] The shared kanidm provision tree is the one surface the gateway shares with synapse. → Mitigation: synapse is a direct client never behind oauth2-proxy and kanidm provisioning is per-client isolated under `autoRemove = false`, so the gateway's additions are purely additive (D10).

[Risk] The group referential-integrity assertion (`kanidm.nix:876`) fails if a scopeMap references a group declared after it. → Mitigation: the auto-derivation emits each group stub before its scopeMap from the same union over `allowedGroups` (D6).

[Trade-off] One shared kanidm client weakens per-service OAuth isolation relative to per-service clients. → Accepted as the cost of shared-gateway SSO and simplicity; per-service clients would restore isolation but reintroduce per-consumer kanidm edits and fragment login (D5).

[Trade-off] `--whitelist-domain` is not exposed by the nixpkgs `services.oauth2-proxy` module. → The gateway unit is hand-rolled (D1), so the flag is passed directly on the command line (D3).

[Trade-off] Browser and API consumers want different 401 handling. → The per-vhost wiring redirects browser 401s to sign-in and fails API 401s fast via `error_page 401 =401` (D7).

## Migration Plan

Deploy order:

1. Author `flake.modules.nixos.sso-gateway`: the bespoke `oauth2-proxy-kanidm` unit (D1, D3, D4), the central auth vhost (D2), the per-service vhost emission and `auth_request` wiring (D7), and the auto-derived `services.kanidm.provision` additions (D5, D6).
2. Wire the shared `sso-gateway` kanidm client plus the `kanidm-oauth2-sso` and `sso-cookie-secret` generators (D8), with the auto-derived group stubs declared before their scopeMaps (D6).
3. Add the central `auth.scientistexperience.net` Cloudflare DNS record via terranix and obtain its ACME cert (USER-RUN apply via `just terraform*`).
4. Import `flake.modules.nixos.sso-gateway` on magnetite.
5. Run `clan vars generate`/`clan vars check` so the two generators emit their files (USER-RUN).
6. Deploy magnetite (USER-RUN), pinned to a single chain tip, never a multi-parent development-join `[wip]` (the diamond-wip-deploy-pulls-all-chains hazard).
7. Gateway-level verification: the bespoke unit evaluates; the central auth vhost is present; buildbot's `services.oauth2-proxy` instance is unchanged. End-to-end browser auth is deferred to the first consumer's change, which registers a real `sso.services.<name>`.

Rollback: remove the module import on magnetite and the `flake.modules.nixos.sso-gateway` module; remove the `auth` Cloudflare DNS record via `just terraform*`; remove the `kanidm-oauth2-sso` and `sso-cookie-secret` generators and explicitly delete their already-emitted secret files (generator removal does not delete emitted files); explicitly delete the orphaned shared `sso-gateway` kanidm client left in kanidm's database (`autoRemove = false` does not delete it). buildbot and synapse are never affected.

## Open Questions

The exact module file name(s) for the gateway and whether the `kanidm-oauth2-sso` generator and the shared client live in `modules/nixos/kanidm.nix` (alongside synapse, the live precedent) or are contributed by the gateway module itself are confirmed at implementation; both are consistent with the design and the auto-derivation in D6.

The precise `auth_request` location block (the exact internal `/oauth2/auth` and `/oauth2/start` plumbing and the `X-Auth-Request-*` header pass-through) is confirmed against the running oauth2-proxy at implementation time.
