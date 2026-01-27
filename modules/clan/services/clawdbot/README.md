# Clawdbot service

Clan service module for the clawdbot Matrix gateway.
Deploys a systemd service that connects to a Matrix homeserver via the clawdbot plugin-based gateway architecture.

## Roles

The `default` role runs the clawdbot gateway on the assigned machine.

## Settings

- `homeserver`: Matrix homeserver URL (e.g., `https://matrix.zt`)
- `botUserId`: Matrix bot user ID (e.g., `@clawd:matrix.zt`)
- `port`: Gateway listen port (default: `18789`)
- `bindMode`: Network bind mode, one of `loopback`, `lan`, or `auto` (default: `loopback`)

## Secrets

The Matrix bot password is read at runtime from the clan vars file for `matrix-password-clawd`.
A gateway auth token is generated via the `clawdbot-gateway-token` vars generator.
