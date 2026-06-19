## 1. Reusable gateway module skeleton (D6)

- [ ] 1.1 Create the `flake.modules.nixos.sso-gateway` module exposing `sso.authDomain` (default `auth.scientistexperience.net`), `sso.cookieDomain` (default `.scientistexperience.net`), and `sso.services = attrsOf (submodule { domain; allowedGroups = listOf str; upstream = attrsOf str; })` (the `upstream` map keys are nginx `location` paths, values are `proxyPass` targets)
- [ ] 1.2 Confirm the module evaluates with an empty `sso.services` (the gateway stands up its central auth surface even before any consumer registers a service)

## 2. Bespoke oauth2-proxy-kanidm unit (D1, D3, D4)

- [ ] 2.1 Define `systemd.services.oauth2-proxy-kanidm` running `${pkgs.oauth2-proxy}/bin/oauth2-proxy` directly (NOT `services.oauth2-proxy`, which buildbot owns; NOT a NixOS container), with `DynamicUser = true`, a `RuntimeDirectory`, and `Restart = "always"`, listening on `--http-address=127.0.0.1:4181`
- [ ] 2.2 Configure the OIDC flags: `--provider=oidc`, `--oidc-issuer-url=https://accounts.scientistexperience.net/oauth2/openid/sso-gateway` (auto-discovery), `--client-id=sso-gateway`, `--client-secret-file`/`--cookie-secret-file` from `LoadCredential`, `--email-domain=*`, `--reverse-proxy=true`, `--trusted-proxy-ip=127.0.0.1`, `--set-xauthrequest=true`, `--code-challenge-method=S256`, `--redirect-url=https://auth.scientistexperience.net/oauth2/callback`
- [ ] 2.3 Set cross-subdomain SSO flags: `--cookie-domain=.scientistexperience.net` (from `sso.cookieDomain`) and `--whitelist-domain=.scientistexperience.net` (passed as a CLI flag because the nixpkgs `services.oauth2-proxy` module does not expose it; here the unit is hand-rolled so the flag is passed directly) [D3]
- [ ] 2.4 Set a DISTINCT `--cookie-name=_sso_gateway` (NEVER the default `_oauth2_proxy`); a domain-wide cookie under buildbot's default name would shadow buildbot's host-only cookie and break buildbot auth (verified against buildbot-nix `master.nix`: no `cookie-name`/`cookie-domain` set → defaults) [D4 hard constraint]

## 3. Central auth subdomain vhost (D2)

- [ ] 3.1 Define the central auth nginx vhost (`forceSSL = true`, `enableACME = true`) at `sso.authDomain` (`auth.scientistexperience.net`) owning the single `/oauth2/` surface (the `/oauth2/` and `/oauth2/callback` locations proxying to the bespoke unit on `127.0.0.1:4181`), so the single kanidm redirect URI `https://auth.scientistexperience.net/oauth2/callback` is the only callback surface
- [ ] 3.2 Confirm no per-service vhost owns its own `/oauth2/` callback (the central auth vhost is the sole `/oauth2/` flow; per-service vhosts only run `auth_request` against it)

## 4. Per-service vhost emission + auth_request wiring (D6c, D7)

- [ ] 4.1 For each registered `sso.services.<name>`, emit a `forceSSL = true`, `enableACME = true` nginx vhost at `<service>.domain` with the `upstream` map rendered as `location` blocks (each key a `location`, each value a `proxyPass`)
- [ ] 4.2 Wire `auth_request /oauth2/auth?allowed_groups=<group>` on each emitted vhost, passing the service's group as a QUERY PARAM (nginx cannot otherwise pass args to `auth_request`); browser vhosts redirect a 401 to the sign-in flow, API paths use `error_page 401 =401` to fail fast [D7]
- [ ] 4.3 Confirm a single shared `oauth2-proxy-kanidm` instance enforces a different group per vhost via the query-param `allowed_groups` (no per-service oauth2-proxy instance is created)

## 5. Auto-derived kanidm client + provision additions (D5, D6d)

The group stub for each derived group MUST be declared before any scopeMap references it, satisfying the `kanidm.nix:876` referential-integrity assertion.

- [ ] 5.1 Compute the union of all registered services' `allowedGroups`; for each distinct group, auto-derive a `provision.groups.<group> = { members = []; overwriteMembers = false; }` stub (cameron/members added operationally, not declaratively), with `provision.autoRemove = false`
- [ ] 5.2 Auto-derive the one shared `provision.systems.oauth2.sso-gateway` client with, per derived group, `scopeMaps.<group> = ["openid" "email" "profile"]` and `claimMaps.groups = { joinType = "array"; valuesByGroup.<group> = ["<group>"]; }` so the token's `groups` claim carries clean literal group names that oauth2-proxy `--allowed-group`/`?allowed_groups=` match exactly [D5: `claimMaps.groups` is a NEW requirement — synapse uses no `claimMaps`]
- [ ] 5.3 Confirm each derived group stub is emitted before its scopeMap reference (the auto-derivation emits stubs and scopeMaps together so the referential-integrity ordering holds)
- [ ] 5.4 Record the explicit tradeoff in the module/design: one shared client weakens per-service OAuth isolation versus per-service clients, accepted as the cost of shared-gateway SSO and simplicity

## 6. Gateway secrets via clan-vars generators (D8)

- [ ] 6.1 Add the `kanidm-oauth2-sso` clan-vars generator emitting the OAuth2 client secret (owner `kanidm`, `mode = "0400"`, `secret = true`, `restartUnits = [ "kanidm.service" "oauth2-proxy-kanidm.service" ]`), consumed by host-side kanidm-provision (`basicSecretFile`) and by the gateway unit
- [ ] 6.2 Add the `sso-cookie-secret` clan-vars generator emitting a 32-byte cookie secret in an acceptable encoding (oauth2-proxy requires 16/24/32 bytes; mirror `openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32`), `mode = "0400"`, `secret = true`, `restartUnits = [ "oauth2-proxy-kanidm.service" ]`
- [ ] 6.3 Deliver both secrets to the bespoke unit via systemd `LoadCredential`; document the snapshot-staleness caveat (LoadCredential snapshots at unit start, so a rotated secret stays stale until the named units restart — this is why `restartUnits` is mandatory)

## 7. Central auth DNS + ACME (terranix) — USER-RUN apply

DNS + ACME must land before §3.1's nginx `forceSSL` can obtain a cert.

- [ ] 7.1 Add the central `auth` Cloudflare DNS record in `modules/terranix/cloudflare.nix` (CNAME `auth` -> `magnetite.scientistexperience.net`, `ttl = 1`, `proxied = false` so ACME works), cloned from the existing niks3/buildbot/git records
- [ ] 7.2 USER-RUN: apply via `just terraform*` (never `nix run .#terraform` directly) and verify ACME issuance for `auth.scientistexperience.net`

## 8. magnetite import wiring

- [ ] 8.1 Import `flake.modules.nixos.sso-gateway` on magnetite (`modules/machines/nixos/magnetite/default.nix`)
- [ ] 8.2 Evaluate the magnetite NixOS configuration to confirm the bespoke `oauth2-proxy-kanidm` unit and the central auth vhost resolve and the configuration builds (with an empty or first-consumer `sso.services`)

## 9. clan vars generate/check (D8) — USER-RUN

- [ ] 9.1 USER-RUN: run `clan vars generate` so the `kanidm-oauth2-sso` and `sso-cookie-secret` generators emit their files, and confirm the client-secret owner (`kanidm`) matches the consuming unit's `User=`; the user runs the command and hands the orchestrator the generated commits to route
- [ ] 9.2 USER-RUN: run `clan vars check` to confirm both generators are satisfied

## 10. Deploy from the single chain tip — USER-RUN deploy

- [ ] 10.1 Re-map the diamond before the deploy phase (N can increase between phases) and pin the build+deploy to the single chain tip, NEVER the multi-parent `@` `[wip]` (the diamond-wip-deploy-pulls-all-chains hazard: a `[wip]` deploy builds the integrated tree of all active chains)
- [ ] 10.2 USER-RUN: build and deploy magnetite from the pinned chain tip

## 11. Gateway-level verification (end-to-end auth deferred to the first consumer)

- [ ] 11.1 Confirm the bespoke `oauth2-proxy-kanidm` unit evaluates and starts (it is a distinct host unit from buildbot's `services.oauth2-proxy`, listens on `127.0.0.1:4181`, and runs `provider = oidc` against kanidm with `--cookie-name=_sso_gateway` and `--cookie-domain=.scientistexperience.net`)
- [ ] 11.2 Confirm the central auth vhost is present at `auth.scientistexperience.net` with a valid ACME cert and owns the single `/oauth2/callback` redirect URI
- [ ] 11.3 Confirm buildbot's `services.oauth2-proxy` singleton is unchanged: different provider (GitHub vs OIDC/kanidm), different instance, distinct cookie name (`_oauth2_proxy` vs `_sso_gateway`); no buildbot file edited
- [ ] 11.4 Confirm synapse's kanidm client is unaffected: synapse is a direct kanidm OIDC client (`modules/nixos/matrix.nix:300-320`), never behind oauth2-proxy, and the new client/groups/claimMaps are additive under per-client-isolated `autoRemove = false`
- [ ] 11.5 Note that end-to-end browser auth (a real gated vhost admitting only its `allowedGroups`) is verified by the first consumer's change, which registers `sso.services.<name>`; this change verifies the gateway scaffold only
