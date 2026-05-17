# hermes-agent (clan service)

Clan-service wrapper around the upstream
[NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)
NixOS module.
This wrapper imports `inputs.hermes-agent.nixosModules.default` and adapts
clan-vars secrets to the upstream `services.hermes-agent.environmentFiles`
option.

## Scope and roadmap

This module landed via beads epic `nix-gyy` (Hermes Agent on cinnabar).
Issue `nix-gyy.2` produced this scaffold.
The full wrapper body is filled in by subsequent issues:

- `nix-gyy.3` — clan-vars-to-environmentFiles adapter (OPENROUTER_API_KEY, MATRIX_PASSWORD)
- `nix-gyy.4` — clan-vars generators (hermes-openrouter-api-key, matrix-password-hermes)
- `nix-gyy.5` — systemd hardening tuning (mkForce overrides where upstream defaults clash with createUser=false)
- `nix-gyy.6` — sibling hermes-agent-dashboard systemd unit (loopback listener; reverse-proxied via nginx)
- `nix-gyy.7` — matrix channel wiring and deep settings merge (allowlist, devices, history)

## Settings (current scaffold)

| Option | Default | Purpose |
|---|---|---|
| `serviceUser` | `cameron` | Unix user (createUser=false; user is provisioned by the machine config) |
| `stateDir` | `/home/cameron/.hermes` | HERMES_HOME |
| `openrouterApiKeyGenerator` | `hermes-openrouter-api-key` | Name of clan-vars generator for the LLM API key |
| `matrixBotPasswordGenerator` | `matrix-password-hermes` | Name of clan-vars generator for the bot's Matrix password |
| `matrixServerName` | `matrix.zt` | Homeserver hostname |
| `matrixUserName` | `hermes` | Bot localpart |
| `port` | `18791` | Gateway port (loopback) |
| `dashboardPort` | `18790` | Dashboard port (loopback) |
| `channelsAllowlist` | `[ ]` | Matrix MXIDs allowed to DM the bot |
| `configOverrides` | `{ }` | Deep-merged into upstream's `services.hermes-agent.settings` |

## Reference

- Upstream NixOS module: `~/projects/planning-workspace/hermes-agent/nix/nixosModules.nix`
- Sibling analog: `modules/clan/services/openclaw/flake-module.nix`
