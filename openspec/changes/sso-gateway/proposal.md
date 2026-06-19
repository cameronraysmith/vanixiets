## Why

Multiple internal magnetite web UIs need kanidm-OIDC authentication gating — cognee now, dagster and signoz next — and each one would otherwise re-invent the same perimeter.
buildbot already owns the host's single nixpkgs `services.oauth2-proxy` instance, pinned to the GitHub provider (buildbot-nix `master.nix:1145-1187`; vanixiets `buildbot.nix:118-125`).
oauth2-proxy cannot run multiple providers in one process (upstream issue #926), and the nixpkgs module is a hard singleton: one systemd unit, one provider, one client.
A kanidm-gated service therefore needs a SECOND oauth2-proxy instance.
Standing up one oauth2-proxy per service would duplicate the perimeter, fragment cookies, and give no single sign-on.
This change instead delivers ONE shared, reusable kanidm-OIDC SSO gateway NixOS module that gates many vhosts behind a single central auth surface, giving cross-subdomain single-login SSO with a per-service footprint of three declarative lines.
This is the reusable gateway only; the existing `declarative-cognee-endpoint` change is revised separately to consume it as the first consumer, and dagster/signoz follow with their own consumer registrations.

## What Changes

This is one change that introduces a reusable shared SSO gateway capability and nothing service-specific.
It defines a bespoke `oauth2-proxy-kanidm` systemd unit (not `services.oauth2-proxy`, which buildbot owns; not a NixOS container, which is overkill for a single shared unit), a central auth subdomain with a single redirect URI and a single kanidm OAuth2 client, cross-subdomain SSO via a domain-wide cookie under a deliberately distinct cookie name, and a `flake.modules.nixos.sso-gateway` module whose `sso.services.<name>` registration auto-derives every per-service kanidm provisioning addition (group stubs, scopeMaps, claimMaps) from the union of registered services' allowed groups.
Buildbot is untouched (different provider, different instance, distinct cookie name) and synapse is untouched (a direct kanidm OIDC client, never behind oauth2-proxy).
The per-service consumer registrations themselves, migrating buildbot off its GitHub singleton, and cognee's same-origin frontend remain out of scope and live in their own changes.

**Shared kanidm-OIDC SSO gateway unit**
- From: no host-side kanidm-gated perimeter exists; buildbot's `services.oauth2-proxy` is a GitHub-pinned singleton that cannot host a second provider (upstream #926) or a second client.
- To: a bespoke `systemd.services.oauth2-proxy-kanidm` running `${pkgs.oauth2-proxy}/bin/oauth2-proxy` directly with `DynamicUser=true`, a `RuntimeDirectory`, and `Restart=always`, listening on `127.0.0.1:4181`, configured `--provider=oidc` against kanidm with PKCE (`--code-challenge-method=S256`).
- Reason: a single shared unit gates many vhosts with one login session, and a bespoke unit avoids both the buildbot-owned `services.oauth2-proxy` singleton and the heavier NixOS-container approach.
- Impact: one new always-on host unit; buildbot's `services.oauth2-proxy` instance is left entirely unchanged.

**Central auth subdomain with a single redirect and a static client**
- From: no central auth surface; each gated service would otherwise need its own `/oauth2/` callback and its own kanidm redirect URI.
- To: a central `auth.scientistexperience.net` subdomain owning the single `/oauth2/` surface and the single kanidm redirect URI `https://auth.scientistexperience.net/oauth2/callback`, with one shared kanidm OAuth2 client `sso-gateway`, so adding a consumer never changes the kanidm client.
- Reason: a single redirect URI and a single client keep the kanidm registration static as consumers are added; new consumers only add nginx vhosts and group authorization.
- Impact: a new central auth vhost (`forceSSL` plus ACME) and one shared kanidm client; the client is never edited per consumer.

**Cross-subdomain SSO cookie with a distinct cookie name**
- From: no SSO cookie exists; buildbot's oauth2-proxy uses the default cookie name `_oauth2_proxy` as a host-only cookie.
- To: the gateway sets `--cookie-domain=.scientistexperience.net` and `--whitelist-domain=.scientistexperience.net` so a single login is valid across every gated subdomain, with a deliberately DISTINCT `--cookie-name=_sso_gateway` (never the default `_oauth2_proxy`).
- Reason: the domain-wide cookie is what makes single-login SSO span subdomains; the distinct cookie name is a hard constraint because a domain-wide cookie sharing buildbot's default name would shadow buildbot's host-only cookie and break buildbot auth.
- Impact: cross-subdomain SSO for every gated service, with buildbot's cookie left intact because the names differ.

**Shared kanidm OAuth2 client with per-access-group scope and claim maps**
- From: synapse's kanidm client uses `scopeMaps` but no `claimMaps.groups`, so group membership is not projected into the token.
- To: one shared kanidm OAuth2 client `sso-gateway` with per-access-group `scopeMaps.<group> = ["openid" "email" "profile"]` plus `claimMaps.groups = { joinType = "array"; valuesByGroup.<group> = ["<group>"]; }`, so the token's `groups` claim carries clean literal group names that oauth2-proxy's `--allowed-group`/`?allowed_groups=` match exactly.
- Reason: oauth2-proxy authorizes on group membership, which requires the groups claim present with literal group names; `claimMaps.groups` is a new requirement synapse never needed.
- Impact: one shared client weakens per-service OAuth isolation relative to per-service clients — accepted as the cost of shared-gateway SSO and simplicity.

**Per-vhost group authorization wired by the module**
- From: no per-vhost authorization mechanism exists for kanidm-gated services.
- To: each registered service's nginx vhost runs `auth_request /oauth2/auth?allowed_groups=<group>` (the query param, because nginx cannot otherwise pass args to `auth_request`); browser vhosts redirect a 401 to the sign-in flow, while API paths use `error_page 401 =401` to fail fast.
- Reason: query-param `allowed_groups` is how a single shared oauth2-proxy enforces a different group per vhost; browser vs API error handling matches the two consumer shapes.
- Impact: per-service authorization with no extra oauth2-proxy instances.

**Reusable per-service registration auto-deriving kanidm config**
- From: each gated service would otherwise hand-write its own oauth2-proxy, its nginx auth wiring, and its kanidm group/scopeMap/claimMap plumbing.
- To: a `flake.modules.nixos.sso-gateway` module exposing `sso.authDomain`, `sso.cookieDomain`, and `sso.services = attrsOf (submodule { domain; allowedGroups; upstream; })`; the module defines the bespoke unit and the central auth vhost, emits a `forceSSL`+ACME vhost with upstream locations and `auth_request` wiring per registered service, and AUTO-DERIVES the kanidm `services.kanidm.provision` additions (group stubs, the shared client's per-group scopeMaps, and `claimMaps.groups.valuesByGroup`) from the union of all registered services' `allowedGroups`.
- Reason: auto-derivation reduces a consumer's footprint to three lines of `sso.services.<name>` and keeps the kanidm provisioning a single computed function of the registered services.
- Impact: consumers register declaratively; the kanidm client, groups, scopeMaps, and claimMaps are computed, not hand-written per service.

**Gateway secrets via clan-vars with restart-on-rotation**
- From: no gateway client secret or cookie secret exists.
- To: two clan-vars generators — `kanidm-oauth2-sso` (the OAuth2 client secret, owner `kanidm`, `mode 0400`, `restartUnits = [ "kanidm.service" "oauth2-proxy-kanidm.service" ]`) and `sso-cookie-secret` (a 32-byte cookie secret, `restartUnits = [ "oauth2-proxy-kanidm.service" ]`) — delivered to the unit via systemd `LoadCredential`.
- Reason: kanidm-provision and the gateway unit both consume the client secret, the gateway unit consumes the cookie secret, and `LoadCredential` snapshots the value at unit start, so a rotated secret stays stale until the named units restart (the snapshot-staleness caveat makes `restartUnits` mandatory).
- Impact: two generators; rotation correctly restarts the consuming units.

## Capabilities

### New Capabilities
- `sso-gateway`: a reusable shared kanidm-OIDC SSO gateway as a `flake.modules.nixos.sso-gateway` module — one bespoke `oauth2-proxy-kanidm` host unit (not buildbot's `services.oauth2-proxy` singleton, not a container), a central `auth.scientistexperience.net` subdomain with a single `/oauth2/` redirect and one shared kanidm OAuth2 client `sso-gateway`, cross-subdomain SSO via a `.scientistexperience.net` cookie under a distinct `_sso_gateway` name (so buildbot's default-named cookie is never shadowed), per-vhost `allowed_groups` authorization, and a `sso.services.<name>` registration that auto-derives the kanidm group stubs, per-group scopeMaps, and `claimMaps.groups` from the union of registered services; secrets delivered via two clan-vars generators with `restartUnits` on rotation; buildbot and synapse left untouched.

### Modified Capabilities
<!-- None. This change introduces a new capability; no existing capability's requirements change. -->

## Impact

Files added or updated: a new `flake.modules.nixos.sso-gateway` module defining the bespoke `oauth2-proxy-kanidm` unit, the central auth vhost, the per-service vhost emission, and the auto-derived `services.kanidm.provision` additions; `modules/nixos/kanidm.nix` (or the module's own provision contributions) gaining the `kanidm-oauth2-sso` generator and the shared `sso-gateway` client/groups/claimMaps source; a `sso-cookie-secret` clan-vars generator; the central `auth` Cloudflare DNS record via terranix (`modules/terranix/cloudflare.nix`, applied with `just terraform*`) and its ACME cert; and `modules/machines/nixos/magnetite/default.nix` importing `flake.modules.nixos.sso-gateway`.
buildbot's `services.oauth2-proxy` singleton (GitHub provider, default `_oauth2_proxy` cookie) is verified untouched.
synapse's kanidm client is verified untouched: synapse is a DIRECT kanidm OIDC client (`modules/nixos/matrix.nix:300-320`), never behind oauth2-proxy, and kanidm provisioning is per-client isolated under `autoRemove = false`, so the new client/groups/claimMaps cannot affect the synapse client.
Out of scope: the per-service consumer registrations themselves (each consumer change registers its own `sso.services.<name>`), migrating buildbot off its GitHub singleton, and cognee's same-origin frontend (its own change).
End-to-end auth verification is deferred to the first consumer's change; this change verifies the gateway itself (the unit evaluates, the central auth vhost is present, and buildbot's `services.oauth2-proxy` is unchanged).
