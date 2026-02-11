# kanban service

Clan service module for the beads kanban board UI.
Deploys a systemd service running beads-kanban-ui, a Rust/Axum server that serves an embedded Next.js frontend for managing beads issues as kanban boards.

## Roles

The `default` role runs the beads-kanban-ui server on the assigned machine.

## Settings

- `port`: HTTP listen port (default: `3008`)
- `serviceUser`: Unix user to run the server as (default: `cameron`)

## Database

The service uses an embedded SQLite database for persistence.
The database is auto-created at `~/.local/share/beads/kanban-ui/settings.db` via XDG ProjectDirs conventions under the service user's home directory.

No external database setup is required.

## Project data

The kanban board reads beads issues from `.beads/issues.jsonl` files within registered project paths.
Project registration (seeding) is performed manually through the web UI after the service is running.

## Hardening

The systemd service runs with `ProtectSystem=strict` and grants write access only to the SQLite data directory (`~/.local/share/beads`).
The service does not require secrets, external databases, or network access beyond its listen port.
