## ADDED Requirements

### Requirement: A105 — omnigent refuses a login grant's refresh once its age reaches a lifetime fixed at server start, and later purges it

It is true of omnigent 0.22.0, independent of what this fleet builds, that the server refuses to refresh a login grant once the time since its approval reaches the grant lifetime it read at start, and that a later refresh deletes every redeemed or revoked grant of that age.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation condition below is observed.

**Evidence**: `omnigent/server/routes/device_auth.py:522-525` returns `expired_token` once `now - approved_at` reaches the lifetime; `:123-156` make the lifetime `OMNIGENT_GRANT_MAX_LIFETIME_DAYS` whole days when that is a positive integer and 30 days otherwise; `:408` reads it once when the token router is mounted; `:288` and `omnigent/server/device_grant_store.py:586-640` purge aged grants at most every 300 s on a refresh; `device_auth.py:529-545` keeps a login grant's refresh token for its whole life; `:118` makes access tokens last 3,600 s, so workers refresh hourly.

#### Scenario: An upgrade changes the lifetime's rule

- **WHEN** an omnigent upgrade changes how the lifetime is computed, read or enforced, or stops purging aged grants
- **THEN** this assumption is void, and the 90-day lifetime and the purge-first deploy of this change must be re-derived from the new source

#### Scenario: The server is restarted with a longer lifetime

- **WHEN** the server starts with a lifetime longer than the age of a grant it has not yet purged
- **THEN** that grant becomes refreshable again, which is why every superseded grant is purged before the lifetime is raised

### Requirement: A106 — A login grant is revocable only by presenting its own token

It is true of omnigent 0.22.0, independent of what this fleet builds, that a login grant can be revoked only by presenting its refresh token or an access token naming it, so a grant whose tokens no holder keeps ends only at its lifetime.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation condition below is observed.

**Evidence**: `omnigent/server/routes/device_auth.py:582-610` is the only revocation route; the server has no administrative revocation, and the 0.22.0 CLI never calls `/oauth/revoke`, read on magnetite on 2026-11-14.

#### Scenario: omnigent gains administrative revocation

- **WHEN** an omnigent release lets an administrator revoke a grant by owner or by identifier
- **THEN** this assumption is void, and superseded grants can be revoked rather than purged before the lifetime is raised
