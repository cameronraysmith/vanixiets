---
title: Clawdbot deployment on cinnabar via ZeroTier
---

# Clawdbot deployment on cinnabar via ZeroTier

## Architecture overview

Cinnabar hosts all three services on a single NixOS machine, accessible only over ZeroTier.
Synapse provides the Matrix homeserver, Clawdbot connects as a Matrix bot gateway to Claude, and Caddy terminates TLS for both services.
Clients on the ZeroTier network (stibnite, Android devices) reach the services through ZeroTier DNS names resolved via `/etc/hosts` entries.

```
┌─────────────────────────────────────────────────┐
│                   cinnabar                       │
│                (ZeroTier only)                   │
│                                                  │
│  ┌───────────┐  ┌───────────┐  ┌─────────────┐  │
│  │  Synapse   │  │ Clawdbot  │  │    Caddy     │  │
│  │  (Matrix)  │  │ (gateway) │  │  (reverse    │  │
│  │  :8008     │  │  :3000    │  │   proxy)     │  │
│  └─────┬─────┘  └─────┬─────┘  └──────┬──────┘  │
│        │               │               │          │
│        └───────────────┴───────┬───────┘          │
│                                │                  │
│                         ZeroTier iface            │
│                          :443 (TLS)               │
└────────────────────────────────┼─────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    │    ZeroTier network      │
                    │                          │
                    │  stibnite   Android      │
                    └─────────────────────────┘
```

## Design decisions

The initial plan considered wrapping Matrix Synapse behind a clan-core service module, but clan-core's existing service patterns are tightly coupled to nginx and ACME for TLS.
Writing a new clan service for Synapse would require reimplementing certificate management and reverse proxy configuration that NixOS modules already handle well.
A direct NixOS module configuration for Synapse avoids that duplication.

Caddy was chosen over nginx because it provides automatic internal TLS certificate generation without external ACME infrastructure.
On a ZeroTier-only network with no public DNS, Caddy's `tls internal` directive generates self-signed CA certificates that clients can trust by installing the Caddy root CA.
This avoids the complexity of running a private ACME server or configuring manual certificate paths in nginx.

Clawdbot is deployed as a clan service because it is a custom application with no upstream NixOS module.
The clan service pattern provides a consistent interface for secrets management, configuration, and systemd unit generation.

## Components

### Matrix Synapse

Synapse runs as the Matrix homeserver with `server_name` set to `matrix.zt`.
Federation is disabled since this is a private ZeroTier-only deployment.
PostgreSQL provides the database backend.

Two user accounts are provisioned:
- `@cameron:matrix.zt` as the admin account for human interaction
- `@clawd:matrix.zt` as the bot account used by clawdbot

### Caddy

Caddy listens on the ZeroTier interface and serves two virtual hosts.
Both use `tls internal` to generate certificates from Caddy's built-in CA.

`matrix.zt` proxies to Synapse on port 8008.
`clawdbot.zt` proxies to the clawdbot gateway on port 3000.

### Clawdbot

Clawdbot is deployed as a clan service with the Matrix plugin bundled via the `CLAWDBOT_BUNDLED_PLUGINS_DIR` environment variable.
Authentication to Claude uses Claude Max via the `setup-token` OAuth flow, which requires a one-time interactive browser session.

## Files created

| File path | Purpose |
|---|---|
| `machines/cinnabar/modules/matrix.nix` | Synapse NixOS module configuration |
| `machines/cinnabar/modules/caddy.nix` | Caddy reverse proxy with internal TLS |
| `clanModules/clawdbot/` | Clan service module for clawdbot gateway |
| `machines/cinnabar/configuration.nix` | Machine config importing matrix, caddy, clawdbot |

## Non-declarative post-deploy steps

### Claude setup-token

The `claude setup-token` command must be run once interactively on cinnabar to complete the Claude Max OAuth flow.
This stores the token in the clawdbot service's state directory.
Subsequent service restarts reuse the stored token without re-authentication.

### Caddy CA cert install on Android

The Caddy root CA certificate must be manually installed on Android devices to trust the internal TLS certificates.
Export the CA from Caddy's data directory on cinnabar, transfer it to the device, and install it through the Android security settings.

### Caddy CA cert install on stibnite

The same Caddy root CA must be installed on stibnite for CLI and browser access to the services.
This step is manual initially but could be automated later through NixOS configuration that adds the CA to the system trust store.

## DNS

Service names resolve via `/etc/hosts` entries pointing to cinnabar's ZeroTier IP address.

On NixOS machines, entries are configured through `networking.extraHosts`.
On darwin machines (stibnite), entries are configured through `clan.core.networking.extraHosts`.

Stibnite is configured first as the initial testing client before rolling out to other machines.
