# claude-sandbox

The home-manager configuration `claude-sandbox@x86_64-linux` gives a Claude Code cloud session (claude.ai/code, on an Anthropic-hosted environment) the operator's user context, skill corpus and command-line tools, the context of each attached repository, and the Linear credentials.
It runs as `root` with home `/root`, and imports the shared `sandbox` aggregate (`modules/home/sandbox/`) that the `ubuntu` profile also uses.
The design and its measurements are in the OpenSpec changes `bootstrap-claude-sandbox` (CAM-118) and `track-main-in-claude-sandbox` (CAM-119).

## Why a cloud session is set up differently

Elsewhere a profile is activated from the flake: `nix run github:cameronraysmith/vanixiets#home -- <username>`, or, in a hosted sandbox with its key in `SOPS_AGE_KEY`, `nix run github:cameronraysmith/vanixiets#home-bootstrap`.
A cloud session cannot use `github:` flake references: its GitHub gate refuses the archive downloads they need.
It can evaluate `git+https://github.com/cameronraysmith/vanixiets` over anonymous git, with every input source substituted from the caches, but it must not build the profile: CI builds the activation package as `checks.x86_64-linux.home-manager-claude-sandbox`, and nixbot publishes it to `cache.scientistexperience.net`.
So the setup step evaluates only the activation package's store path, fetches that closure from the caches, and activates it.

## The setup step

The environment's setup box holds a fixed bootstrap, the same for every commit, that runs the flake app `claude-sandbox-setup` from `main`:

```bash
#!/bin/bash
nix run \
  --option substituters 'https://cache.nixos.org https://cache.scientistexperience.net?priority=45' \
  --option trusted-public-keys 'cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= cache.scientistexperience.net-1:N9ZeWasooJLXEwaN+rd4MMyBuGpAtcUAXrEUPBT5cXI=' \
  --option accept-flake-config false \
  'git+https://github.com/cameronraysmith/vanixiets?ref=main&shallow=1#claude-sandbox-setup'
exit 0
```

Its one `nix run` command is split with `\` continuations because the platform refuses a setup-script line wider than 200 columns, a tab counting 8.

Only bash and the image's preinstalled Nix are trusted: every command the app calls, Nix included, comes from its `runtimeInputs`.
Its only local build is its own wrapper, a printf and a shellcheck whose inputs come from `cache.nixos.org`.
The app (`modules/apps/claude-sandbox-setup.{nix,sh}`) follows `main`:

- it lists `main`'s 5 newest first-parent commits with a treeless shallow clone;
- from the tip, it evaluates each commit's activation package path through `git+https://…?rev=<sha>&shallow=1`, with `cache.scientistexperience.net` and `cache.nixos.org` and their keys (from `lib/caches.nix`) as substituters, and accepts the first whose narinfo `cache.scientistexperience.net` serves, within about 300 s; a failed evaluation is a miss;
- it realises that path with `--max-jobs 0 --option builders ''`, so the profile's closure is never built;
- it runs `"$P/activate"` as `USER=root HOME=/root` under `timeout 240`, unless the realise failed or the path is already the current generation;
- it appends one marker line to `/var/log/claude-sandbox-bootstrap/setup.log`, and exits 0.

To pin one closure, end the command's last line, the flake reference, with `-- /nix/store/…-home-manager-generation`.
A pin is an argument because the setup step cannot read the environment's variables.

The bootstrap's `exit 0` holds even when `nix run` fails: a setup step that exits non-zero stops the session from ever starting.
The `claude-sandbox-setup-script` check holds this bootstrap, here and in the app module's comment, to the lines it generates from `lib/caches.nix`, and the app to the same caches and keys and to its substitute-only realise.
Where `github:` flake references work, `nix run github:cameronraysmith/vanixiets#claude-sandbox-setup` runs the same app.

A change to the app reaches an environment the next time its snapshot is rebuilt, like a change to the profile; a revert on `main` is the normal rollback.

## Renewing while pinned

niks3 drops a closure from `cache.scientistexperience.net` 30 days after its last reference.
An environment that follows `main` needs no renewal.
A pinned environment does: replace its pin at least every 30 days, even when nothing else changed, or it eventually fails to fetch its closure and starts sessions without the profile.

## Trying a change: the controller loop

1. Push the commit and wait for nixbot to build `home-manager-claude-sandbox`.
2. Start one cloud session on the environment as the controller, with a prompt (see `logs/claude-sandbox/` for past ones) that creates child sessions with `create_session` and reads the reports they push to new `claude/sandbox-reports-*` branches.
3. A child picks up the new commit once the environment's snapshot is rebuilt; an edit to the setup box, such as adding a dated comment, forces that, at one approval card.

The first child after a rebuild runs the setup step (about 80 s on 2026-11-22: 46–48 s evaluating, 21–29 s fetching, 3 s activating); later children start from the snapshot and run only the session hooks.

## Operator steps for a new environment

1. In claude.ai's environment settings, create or pick the environment and paste the bootstrap above into its setup box.
2. Allow `*.nixos.org`, `*.scientistexperience.net` and `*.linear.app` among its allowed hosts; the first two serve the input sources, the app's wrapper inputs and the closure, the last the Linear skills' API.
3. Set the variable `SOPS_AGE_KEY` to the private age key of `claude-sandbox-user`, from the Bitwarden SSH key `sops-claude-sandbox`, directly in the settings, never through chat or the clipboard.
   The key is readable by the model and every process in the session, and opens only the Linear keys in `secrets/home-manager/users/claude-sandbox/secrets.yaml`.

## What a session sees

After a successful setup, `/var/log/claude-sandbox-bootstrap/` holds `setup.log` (one marker line per run), `run.log` (the walk, fetch and activation output, then one line per session hook) and `report.json` (the generation, closure size, skill count and tools).
A successful run's marker reads like `2026-11-22T03:24:26Z mode=tracked tip=e43cce1d… rev=0cda729d… dist=1 skip=e43cce1d2cd4:narinfo select=44s realise=0/12s activate=0/3s nix=2.35.6 P=/nix/store/…-home-manager-generation`; `mode` is `tracked`, `pinned` or `none`, `dist` is the accepted commit's distance from `main`'s tip, and `skip` lists each newer commit with its reason (`eval/<code>`, `narinfo` or `budget`).
At each session start, three hooks run by store path: `claude-sandbox-session-secrets` renders `~/.config/linear/credentials.toml` into `/dev/shm`, `claude-sandbox-repo-context` compiles each attached repository's `AGENTS.md`, and `claude-sandbox-staleness` compares the marker's tip with `main`'s; each appends a line to `run.log` (`session-secrets status=ok`, `repo-context repo=… rc=0 tier=default`, `staleness rev=… dist=main~0 main=… moved=no`).

## What a failed setup looks like

The session still starts, but without the profile: no `/root/.claude/CLAUDE.md`, only the platform's own two skills, and none of the profile's tools.
The marker records why: `rev=none` with five entries in `skip` when none of the 5 newest commits was published, `realise=1/…s activate=skipped/0s` when the closure could not be fetched, or a non-zero activate code when activation failed, with the details in `run.log`.
A `setup.log` whose lines all predate the container's boot (`uptime -s`) is not a failure: the session started from the snapshot and ran no setup of its own.
No `setup.log` at all means the app never ran in the container: the bootstrap's `nix run` failed to fetch, evaluate or build it, and the setup step's own output says why.

## Revoking the Linear credentials

The cloud environment decrypts `secrets/home-manager/users/claude-sandbox/secrets.yaml` with the age key in its `SOPS_AGE_KEY` variable, the recipient `claude-sandbox-user` in `.sops.yaml`.
To revoke that access, on stibnite with the admin key:

1. Remove the recipient: delete `*claude-sandbox-user` from the `secrets/home-manager/users/claude-sandbox/.*\.yaml$` rule in `.sops.yaml`.
2. Re-encrypt that one file: `sops updatekeys secrets/home-manager/users/claude-sandbox/secrets.yaml`.
3. Rotate both Linear keys in Linear, `linear-api-key-personal` and `linear-api-key-work`, which are the ubuntu profile's agent Linear keys, shared with claude-sandbox; the old file in git history still opens with the removed key.
4. Clear the `SOPS_AGE_KEY` variable in the claude.ai cloud environment's settings.
