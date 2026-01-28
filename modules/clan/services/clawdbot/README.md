# clawdbot service

clan service module for the clawdbot matrix gateway.
Deploys a systemd service that connects to a matrix homeserver via the clawdbot plugin-based gateway architecture.

## Roles

The `default` role runs the clawdbot gateway on the assigned machine.

## Settings

- `homeserver`: matrix homeserver URL (e.g., `https://matrix.zt`)
- `botUserId`: matrix bot user ID (e.g., `@clawd:matrix.zt`)
- `port`: gateway listen port (default: `18789`)
- `bindMode`: network bind mode, one of `loopback`, `lan`, or `auto` (default: `loopback`)

## Secrets

The matrix bot password is read at runtime from the clan vars file for `matrix-password-clawd`.
A gateway auth token is generated via the `clawdbot-gateway-token` vars generator.
