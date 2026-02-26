# beads-ui service

Clan service module for the beads issue tracker UI.
Deploys a systemd service running beads-ui, a Node.js Express + WebSocket server that provides a real-time web interface for managing beads issues across registered workspaces.

## Roles

The `default` role runs the beads-ui server on the assigned machine.

## Settings

- `port`: HTTP listen port (default: `3009`)
- `serviceUser`: Unix user to run the server as (default: `cameron`)

## Workspace discovery

The server reads `~/.beads/registry.json` from the service user's home directory to discover registered workspaces.
This file is managed declaratively by the `beads-registry` home-manager module.

## Hardening

The systemd service runs as an unprivileged user with `NoNewPrivileges`, `PrivateDevices`, `PrivateTmp`, and kernel isolation directives.
Filesystem sandboxing (`ProtectSystem=strict`) is intentionally omitted because the service needs read/write access to the home directory for workspace `.beads/` directories and the global registry.
