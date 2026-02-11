# openclaw service

Clan service module for the openclaw matrix gateway.
Deploys a systemd service that connects to a matrix homeserver via the openclaw plugin-based gateway architecture.

## Roles

The `default` role runs the openclaw gateway on the assigned machine.

## Settings

- `homeserver`: matrix homeserver URL (e.g., `https://matrix.zt`)
- `botUserId`: matrix bot user ID (e.g., `@clawd:matrix.zt`)
- `port`: gateway listen port (default: `18789`)
- `bindMode`: network bind mode, one of `loopback`, `lan`, or `auto` (default: `loopback`)

## Secrets

The matrix bot password is read at runtime from the clan vars file for `matrix-password-clawd`.
A gateway auth token is generated via the `clawdbot-gateway-token` vars generator.

The Z.AI Coding Plan API key is provisioned through the `clawdbot-zai-coding-api` clan vars generator.
To obtain an API key, follow the Z.AI Coding Plan documentation at https://docs.z.ai/devpack/tool/others for registration and key generation.
Store the key in the vars file before deploying the service.

## Model configuration

The service uses `zai-coding-plan/glm-5` as the primary model for processing requests.
When the primary model is unavailable or encounters errors, the service falls back to `anthropic/claude-opus-4-5` to maintain availability.
This fallback behavior ensures continuous operation even during Z.AI service disruptions while providing access to a capable alternative model.
