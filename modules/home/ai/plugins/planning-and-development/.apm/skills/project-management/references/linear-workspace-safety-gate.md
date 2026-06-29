# Linear workspace safety gate

This is the hardest constraint in the entire project-management hub.
Read it before proposing any Linear mutation, in this hub or in the openspec-linear-sync overlay.

## The gate

Never propose a Linear mutation until the correct personal-versus-work workspace is confirmed via `linear auth whoami`.
Confirm explicitly which workspace `whoami` reports before any create, update, transition, comment, or document write.
Optionally scope the check to a candidate workspace with `linear auth whoami --workspace <slug>`.

Every linear-cli invocation, reads as well as mutations, passes an explicit `--workspace <slug>`.
A command that omits `--workspace`, including a read such as `team list`, `project list`, `label list`, `issue query`, `issue view`, or `document list`, silently resolves to the credentials default, which is the personal workspace in this deployment.
Do not let any command run against whatever workspace happens to be ambient; name the workspace on every command.

Never run mutating `linear auth` commands (`linear auth login`, `linear auth logout`, or any auth subcommand that writes credentials).
Credentials are nix-managed and immutable here, rendered from sops into a read-only (0400) inline `credentials.toml` (flat `<workspace> = "<api-key>"` keys plus a top-level `default = "<workspace>"`), so a mutating `linear auth` would fail against the read-only file and is in any case ineffective and dangerous.
linear-cli also supports an OS-keyring credential mode (macOS Keychain via `/usr/bin/security`; Linux secret-tool/libsecret; Windows CredentialManager), but that is not the mode in use; this operator's credentials live in the inline file.
The auth surface is read-only here: `linear auth whoami` confirms identity, nothing more.
The `whoami`, `migrate`, and `--plaintext` verbs and the keyring-versus-plaintext credential modes are documented in `~/.claude/skills/linear-cli/references/auth.md`, which is also the authoritative home for the `credentials.toml` flat-key-plus-`default` format; the separate `.linear.toml` project config is covered in `~/.claude/skills/linear-cli/references/config.md`.

## Why the gate keys on confirmed credentials, not LINEAR_WORKSPACE

Do not key the gate on `LINEAR_WORKSPACE`.
It is the wrong lever because it is env-overridable and silently outranked by `--workspace` and the API-key tiers, not because of where it sits relative to the credentials default.

The credential precedence and the conflict-throw below are derived from linear-cli upstream source, not from the bundled skill, which does not document them: the resolution chain and the throw live in `src/utils/graphql.ts` (plus the config resolution in `src/config.ts`) at `~/projects/planning-workspace/linear-cli` (schpet/linear-cli).
These were verified against v2.0.0; re-check them against the pinned version on any linear-cli bump, since a reordering of the tiers would silently change which workspace a mutation hits.

The credential precedence has five tiers, highest first:

1. `LINEAR_API_KEY` env, or an `api_key` resolved from the highest-priority config.
2. A project-config `api_key` (in `.linear.toml`).
3. The `--workspace <slug>` flag, which selects which stored credential set to use via a keyring lookup.
4. `getOption("workspace")`, which reads the `LINEAR_WORKSPACE` env var first, then a project-config workspace, then resolves the result through `getCredentialApiKey()`, which abstracts over either the OS keyring or the inline `credentials.toml` file (the latter being this deployment's mode).
5. The `credentials.toml` `default` key.

`LINEAR_WORKSPACE` resolves at tier 4 — above the `credentials.toml` default but below `--workspace` and below the API-key tiers.
Because tier 4 sits under tier 3 and tiers 1-2, a `--workspace` flag or an `api_key` silently outranks whatever `LINEAR_WORKSPACE` names, and because it is an environment variable it can be set out from under you.
A gate keyed on `LINEAR_WORKSPACE` therefore gives a false sense of which workspace a mutation will actually hit.

The safe gate keys on `linear auth whoami` plus an explicit `--workspace`.
`whoami` reports the workspace that the resolved credentials actually authenticate against, after the full five-tier resolution, so confirming it closes the personal-versus-work ambiguity that `LINEAR_WORKSPACE` cannot.

## Pre-gate environment assertion

Before running the `linear auth whoami` gate, assert that both `LINEAR_API_KEY` and `LINEAR_WORKSPACE` are unset.
`LINEAR_API_KEY` is tier 1 and silently outranks the gate: if it is set, the resolved workspace is whatever that key authenticates against regardless of what `whoami` is scoped to, so refuse to proceed while it is present.
Furthermore, linear-cli throws when both `LINEAR_API_KEY` and a `--workspace` flag are set (verified in upstream `src/utils/graphql.ts` at `~/projects/planning-workspace/linear-cli`, v2.0.0; re-verify on a version bump), so an ambient `LINEAR_API_KEY` would also break the mandatory `--workspace` on every command.
`LINEAR_WORKSPACE` is tier 4 and env-overridable, so it too must be unset to keep the resolution path deterministic and keyed on the confirmed credentials default.
The shell-env assertion is necessary but not sufficient: linear-cli's own loadEnvFiles reads a `./.env` or git-root `.env` and injects `LINEAR_*` keys into its process (resolving at tiers 1 and 4), invisible to a shell check, so the assertion below also rejects such a `.env`.

```bash
[ -z "${LINEAR_API_KEY:-}" ] || { echo "refuse: LINEAR_API_KEY is set and outranks the gate; unset it first" >&2; exit 1; }
[ -z "${LINEAR_WORKSPACE:-}" ] || { echo "refuse: LINEAR_WORKSPACE is set; unset it before the gate" >&2; exit 1; }
git_root=$(git rev-parse --show-toplevel 2>/dev/null || echo .)
for envfile in ./.env "$git_root/.env"; do [ -f "$envfile" ] && grep -Eq '^[[:space:]]*(LINEAR_API_KEY|LINEAR_WORKSPACE)=' "$envfile" && { echo "refuse: $envfile defines LINEAR_API_KEY/LINEAR_WORKSPACE; linear-cli reads it into its own process" >&2; exit 1; }; done
```

## Checklist before any mutation

Assert `LINEAR_API_KEY` and `LINEAR_WORKSPACE` are unset (the pre-gate assertion above); refuse to proceed if `LINEAR_API_KEY` is present.
Run `linear auth whoami --workspace <slug>` and confirm the reported workspace is the intended personal-versus-work workspace.
Pass `--workspace <slug>` on every command, reads as well as mutations.
Never reach for `LINEAR_WORKSPACE` and never run a mutating `linear auth` subcommand.
