---
title: "ADR-0011: SOPS secrets management"
---

## Status

Accepted

## Context

Managing secrets in infrastructure-as-code requires:
- Encryption at rest in version control
- Decryption by authorized developers and CI
- Key rotation capabilities
- Audit trail of secret access

Common approaches:
- **SOPS** - file-based encryption with multiple backend support (age, GPG, cloud KMS)
- **git-crypt** - transparent git integration, GPG-based
- **Sealed Secrets** - Kubernetes-native, cluster-scoped
- **Vault** - centralized secret management, requires server
- **Age** - modern encryption tool, simpler than GPG
- **1Password/Bitwarden CLI** - cloud-based secret management

## Decision

Use **SOPS (Secrets OPerationS) with age encryption** for managing secrets.

## Architecture

**Key components:**
- Developer keys for local decryption
- CI key stored in GitHub Secrets
- Encrypted `secrets/shared.yaml` committed to repository
- `.sops.yaml` contains public keys only (private keys never committed)

## Key Design Decisions

### Why store CI_AGE_KEY in secrets/shared.yaml?

**Context:** The CI age key could be stored only in Bitwarden or only in GitHub Secrets.

**Decision:** Store encrypted CI_AGE_KEY in secrets/shared.yaml as well.

**Rationale:**
- Allows rotating `SOPS_AGE_KEY` GitHub Secret from dev workstation
- Still requires dev key to decrypt (security maintained)
- Bitwarden serves as offline backup
- Single source of truth for all secrets

### Why separate sops-upload-github-key from ghsecrets?

**Context:** Could use SOPS-encrypted secrets file to manage GitHub Secrets including SOPS_AGE_KEY.

**Decision:** Keep `sops-upload-github-key` as separate workflow from general `ghsecrets` management.

**Rationale:**
- **Avoids chicken-and-egg problem:** can't use SOPS to get key needed to use SOPS
- **During rotation:** new key may not be in secrets/shared.yaml yet
- **Bootstrap support:** allows pasting from Bitwarden during initial setup
- **Explicit operation:** rotating SOPS key is critical, deserves dedicated workflow

## Rationale for SOPS + age

**SOPS benefits:**
- File-based encryption (works with any text format: YAML, JSON, ENV, etc.)
- Encrypted files commit to git (full audit trail)
- Multiple key support (multiple developers, CI)
- Partial encryption (can leave some keys unencrypted)
- Active development and Nix integration

**age over GPG:**
- Simpler key format (single line)
- Modern cryptography
- No complex trust model
- Easier key rotation
- Better performance

## Trade-offs

**Positive:**
- Secrets in version control (audit trail)
- No external secret server required
- Easy to audit access (check who has keys)
- Works offline
- Nix integration for declarative secret management

**Negative:**
- Key distribution requires secure channel (initially)
- Compromised developer key compromises all secrets (until rotation)
- No automatic key expiration
- Manual key rotation process

**Neutral:**
- Need to remember to encrypt secrets before committing
- `.sops.yaml` configuration required
- Binary age keys less convenient than cloud-based secret managers

## Consequences

See [Secrets management guide](/guides/secrets-management) for workflows and setup.

**For developers:**
- Need age key generated and added to `.sops.yaml`
- Use `sops` command to edit secrets
- Can't read secrets without key

**For CI:**
- `SOPS_AGE_KEY` must be in GitHub Secrets
- Workflows use `sops` to decrypt at runtime
- Secrets never exposed in logs

**For operations:**
- Key rotation requires updating all encrypted files
- New team members need key added to `.sops.yaml`
- Bitwarden backup provides disaster recovery
