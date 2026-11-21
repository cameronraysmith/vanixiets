# claude-sandbox

The home-manager configuration `claude-sandbox@x86_64-linux` gives a Claude Code cloud session (claude.ai/code, on an Anthropic-hosted environment) the operator's user context, skill corpus and command-line tools, the context of each attached repository, and the Linear credentials.
It runs as `root` with home `/root`, and imports the shared `sandbox` aggregate (`modules/home/sandbox/`) that the `ubuntu` profile also uses.
The design and its measurements are in the OpenSpec change `bootstrap-claude-sandbox` (CAM-118).

## Why a cloud session is set up differently

Elsewhere a profile is activated from the flake: `nix run github:cameronraysmith/vanixiets#home -- <username>`, or, in a hosted sandbox with its key in `SOPS_AGE_KEY`, `nix run github:cameronraysmith/vanixiets#home-bootstrap`.
Both evaluate this flake, and a cloud session cannot: its GitHub gate refuses the archive downloads every `github:` flake input needs.
So the cloud environment consumes a closure instead.
CI builds the activation package as `checks.x86_64-linux.home-manager-claude-sandbox`, and nixbot publishes it to `cache.scientistexperience.net`.
The environment's setup script names that package by store path, fetches it from the caches, and activates it, evaluating nothing.

## The setup script

`nix run .#claude-sandbox-setup-script` prints the setup script for the current commit (pass a flake reference to print it for another).
It prints about 17 lines:

- a comment naming the vanixiets revision and its date, the script's only provenance (`<rev>-dirty` for a checkout with changes);
- `P=`, the activation package's store path;
- `nix-store -r "$P"` from `cache.scientistexperience.net` and `cache.nixos.org` with their public keys (from `lib/caches.nix`);
- `"$P/activate"` as `USER=root HOME=/root` under `timeout 240`, skipped if the realise failed or `P` is already the current generation;
- one marker line appended to `/var/log/claude-sandbox-bootstrap/setup.log`;
- `exit 0`, because a setup script that exits non-zero stops the session from ever starting.

The `claude-sandbox-setup-script` check holds it to the platform's limits (100 lines of 200 bytes) and to that final `exit 0`.
The script holds a store path, two cache addresses and their public keys, and no secret.

## Renewing every 30 days

niks3 drops a closure from `cache.scientistexperience.net` 30 days after its last reference.
Regenerate the setup script and swap it into the environment at least every 30 days, even when nothing else changed; an unrenewed environment eventually fails to fetch its closure and starts sessions without the profile.
A new setup script also rebuilds the environment's snapshot, so sessions pick up the new profile only through a swap.

## Trying a change: the controller loop

1. Push the commit and wait for nixbot to build `home-manager-claude-sandbox`.
2. Start one cloud session on the environment as the controller, with a prompt (see `logs/claude-sandbox/` for past ones) that swaps in the script `nix run .#claude-sandbox-setup-script` printed, creates child sessions with `create_session`, and reads the reports they push to new `claude/sandbox-reports-*` branches.
3. Accept one approval card for each setup script change the controller makes.

That is the whole cost: one prompt per round and one approval card per setup change.
The first child after a swap runs the setup step (about 30 s for the 5.2 GB closure on 2026-11-21); later children start from the snapshot and run only the session hooks.

## Operator steps for a new environment

1. In claude.ai's environment settings, create or pick the environment and paste the printed setup script.
2. Allow `*.nixos.org`, `*.scientistexperience.net` and `*.linear.app` among its allowed hosts; the first two serve the closure, the last serves the Linear skills' API.
3. Set the variable `SOPS_AGE_KEY` to the private age key of `claude-sandbox-user`, from the Bitwarden SSH key `sops-claude-sandbox`, directly in the settings, never through chat or the clipboard.
   The key is readable by the model and every process in the session, and opens only the Linear keys in `secrets/home-manager/users/claude-sandbox/secrets.yaml`.

## What a session sees

After a successful setup, `/var/log/claude-sandbox-bootstrap/` holds `setup.log` (one marker line per run), `run.log` (the fetch and activation output, then one line per session hook) and `report.json` (the generation, closure size, skill count and tools).
A successful run's marker reads like `2026-11-21T22:09:03Z rev=8c41bceb… realise=0/29s activate=0/2s nix=2.34.6 P=/nix/store/…-home-manager-generation`.
At each session start, two hooks run by store path: `claude-sandbox-session-secrets` renders `~/.config/linear/credentials.toml` into `/dev/shm`, and `claude-sandbox-repo-context` compiles each attached repository's `AGENTS.md`; each appends a line to `run.log` (`session-secrets status=ok`, `repo-context repo=… rc=0 tier=default`).

## What a failed setup looks like

The session still starts, but without the profile: no `/root/.claude/CLAUDE.md`, only the platform's own two skills, and none of the profile's tools.
The marker records why: `realise=1/…s activate=skipped/0s` when the closure could not be fetched (a store path the caches lack, or a closure dropped after 30 days), or a non-zero activate code when activation failed, with the details in `run.log`.
A `setup.log` whose lines all predate the container's boot (`uptime -s`) is not a failure: the session started from the snapshot and ran no setup of its own.
No `setup.log` at all means this script never ran in the container.

## Revoking the Linear credentials

The cloud environment decrypts `secrets/home-manager/users/claude-sandbox/secrets.yaml` with the age key in its `SOPS_AGE_KEY` variable, the recipient `claude-sandbox-user` in `.sops.yaml`.
To revoke that access, on stibnite with the admin key:

1. Remove the recipient: delete `*claude-sandbox-user` from the `secrets/home-manager/users/claude-sandbox/.*\.yaml$` rule in `.sops.yaml`.
2. Re-encrypt that one file: `sops updatekeys secrets/home-manager/users/claude-sandbox/secrets.yaml`.
3. Rotate both Linear keys in Linear, `linear-api-key-personal` and `linear-api-key-work`, which are the ubuntu profile's agent Linear keys, shared with claude-sandbox; the old file in git history still opens with the removed key.
4. Clear the `SOPS_AGE_KEY` variable in the claude.ai cloud environment's settings.
