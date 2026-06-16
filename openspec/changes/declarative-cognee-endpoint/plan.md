# Declarative single-source cognee endpoint (comprehensive) Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development
> to implement this plan task-by-task.

**Goal:** Make cognee the universal knowledge base accessed via the cognee-cli and the `cognee-memory` plugin (not the MCP), all pointed at one central magnetite cognee through a single declarative nix source of truth, plus a public kanidm-gated browser UI at `kb.scientistexperience.net`. This is one comprehensive change: source of truth + drop the MCP (client and server) + expose REST over ZeroTier + plugin/CLI pointed at central + public kanidm-gated UI. Only cognee app-level auth, the mesh `X-Api-Key` credential, multi-user public access, and a public machine path remain as deferred future work.

**Architecture:** A two-layer `flake.lib` value (a per-host ZeroTier-address registry plus a derived `flake.lib.cognee` record carrying `meshApiUrl`/`apiPort`/`publicFqdn` and NO MCP URL), each consolidated into a single file per the `lazyAttrsOf raw` constraint, is read by the cognee server bind, the plugin env, the cognee-cli wrapper, and the public-UI FQDN. The cognee MCP is removed on both sides (client entry plus `~/.mcp/cognee.json`, and `services.cognee.mcp.enable = false` plus the 9271 firewall opening). The cognee REST API (9270, loopback-only today) is bound to the ZeroTier address and opened on `zt+`. The plugin becomes always-on global via `home.sessionVariables` (managed mode, no key in v1), a global cognee-cli wrapper bakes `--api-url ${meshApiUrl}`, and a kanidm-OIDC-backed oauth2-proxy plus nginx vhost plus terranix DNS record provide the public browser UI behind a no-public-bind invariant.

**Tech Stack:** nix flake-parts `flake.lib`, NixOS modules (`modules/nixos/cognee.nix`, kanidm, oauth2-proxy, nginx, ACME), home-manager (`mcp-servers.nix` edit, a new plugin-env module using `home.sessionVariables`, a new cognee-cli wrapper module over the cognee-nix overlay's `pkgs.cognee`), clan-vars/sops secrets, terranix Cloudflare DNS (applied via `just terraform*`).

---

## Task 1: Source-of-truth nix values (deliverable A)

- [ ] **Step 1:** Create a single new file declaring `flake.lib.hosts.<host>.zt` with `magnetite.zt = "fddb:4344:343b:14b9:399:930f:39db:40d2"`, as a single-file consolidation.
- [ ] **Step 2:** Add the derived `flake.lib.cognee` record (co-located in one file): `meshApiUrl = "http://[${magnetite.zt}]:9270"`, `apiPort = 9270`, `publicFqdn = "kb.scientistexperience.net"`; NO MCP URL of any kind.
- [ ] **Step 3:** Confirm both additions evaluate cleanly under `flake.lib` (`lazyAttrsOf raw`).

## Task 2: Server — expose REST over ZeroTier + disable server MCP + drop 9271 firewall (deliverables C, B-server)

- [ ] **Step 1:** In `modules/nixos/cognee.nix`, bind the REST API (9270) listen address to `flake.lib.hosts.magnetite.zt` instead of `127.0.0.1` and open port 9270 on the `zt+` interface.
- [ ] **Step 2:** Set `services.cognee.mcp.enable = false`.
- [ ] **Step 3:** Remove the 9271 `zt+` firewall opening.

## Task 3: Client — drop MCP client config + point the plugin at central magnetite (deliverables B-client, D)

- [ ] **Step 1:** Remove the cognee entry from `modules/home/ai/claude-code/mcp-servers.nix` so `~/.mcp/cognee.json` is no longer generated; confirm the hardcoded MCP IPv6 literal is gone.
- [ ] **Step 2:** Add a home-manager module exporting `COGNEE_SERVICE_URL = flake.lib.cognee.meshApiUrl` via `home.sessionVariables` (always-on global); do NOT set `COGNEE_API_KEY` in v1.
- [ ] **Step 3:** Confirm the URL is NOT written into `~/.cognee-plugin/config.json` (stripped by `save_config`); note the degrade-when-unreachable behavior.

## Task 4: cognee-cli wrapper module (deliverable E)

- [ ] **Step 1:** Add a home-manager module installing a global cognee-cli wrapper as a `writeShellApplication` over `pkgs.cognee` (cognee-nix overlay) that bakes `--api-url ${flake.lib.cognee.meshApiUrl}`.
- [ ] **Step 2:** Confirm the wrapper is decoupled from the plugin's venv and accept the ~1.5 GiB closure footprint; use `--api-key`/`X-Api-Key` (never `--api-token`) if a key is ever added — none in v1.

## Task 5: clan-vars generators (deliverable F-secrets)

- [ ] **Step 1:** Add a clan-vars generator for the kanidm oauth2 client secret, mirroring the synapse generator naming.
- [ ] **Step 2:** Add a clan-vars generator for the oauth2-proxy cookie secret.

## Task 6: Public browser UI — frontend + nginx + oauth2-proxy + kanidm client (deliverable F)

- [ ] **Step 1:** Register a new kanidm OAuth2 client via `services.kanidm.provision.systems.oauth2.<name>` with a `basicSecretFile` from the Task 5 generator, mirroring synapse.
- [ ] **Step 2:** Enable the cognee frontend (`frontend.enable = true`) and add a kanidm-OIDC-backed oauth2-proxy proxying to cognee on loopback, allowlist restricted to cameron's identity.
- [ ] **Step 3:** Add an nginx vhost (`forceSSL` + ACME) for `kb.scientistexperience.net` delegating to the oauth2-proxy, using the existing `services.cognee.nginx.enable` + `nginx.domain` scaffolding, mirroring the buildbot/gitea/niks3 public-vhost pattern.

## Task 7: terranix kb DNS record (deliverable F-DNS)

- [ ] **Step 1:** Add the `kb` Cloudflare DNS record in `modules/terranix/cloudflare.nix` (CNAME `kb` -> `magnetite.scientistexperience.net`, `ttl = 1`, `proxied = false`), cloned from the niks3/buildbot/git records; apply via `just terraform*` (never `nix run .#terraform` directly).

## Task 8: magnetite wiring, deploy, and verification

- [ ] **Step 1:** Import any new `flake.modules.nixos.<svc>` on magnetite (`modules/machines/nixos/magnetite/default.nix`).
- [ ] **Step 2:** Evaluate the magnetite NixOS configuration and the relevant home-manager activation; grep the repointed consumers to confirm the IPv6 literal and the cognee MCP literal are gone.
- [ ] **Step 3:** Deploy and confirm a laptop session reaches central magnetite over the mesh (plugin and cognee-cli wrapper), the browser UI does kanidm SSO with a valid cert, and the no-public-bind invariant holds (cognee bound only to loopback and ZeroTier).
