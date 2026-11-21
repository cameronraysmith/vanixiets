# Brainstorm: bootstrap Claude Code cloud sessions from vanixiets

Decision log captured from three sources rather than a live brainstorming conversation:
the record of session 99972732 (a cloud session teleported to the operator's laptop on 2026-11-21, items V1–V35, C1–C18, G1–G16, R1–R9, O1–O15),
two probe rounds run on 2026-11-21 in the `nix-sandbox-test` cloud environment (session 1 at 19:12, session 2 from 19:22 to 19:36),
and a read-only map of the repository's agent-context, skills, devshell, sandbox-profile and secrets machinery.
The probe flake is `bootstrap/claude-sandbox` on branch `claude-sandbox-dev` at `7fffbd2c2464f7663348fde7882541b430507714`; the setup scripts and prompts are under `logs/claude-sandbox/`.

## Background

A Claude Code cloud session (claude.ai/code, Anthropic-hosted) starts in an Ubuntu 24.04 Firecracker VM as root, with Nix 2.34.6 preinstalled single-user and no daemon (V7, V8, V13, V26).
It starts with none of the operator's context: no `~/.claude/CLAUDE.md`, none of the composed skills, none of the CLIs those skills call (V6).
The operator asked for a setup step that is "a single line shim" naming one vanixiets target, so that the environment is "effectively declarative" (U8), reusing what the repository already builds (U3, U9).
The operator also asked for a closed development loop: start fresh cloud sessions against a candidate environment and read back what happened (U10, U11).

Constraints the earlier session established:
- GitHub archive, codeload and API requests for repositories not attached to the session return 403; anonymous git smart-HTTP reads are served (C1, C2, V11, V12, V24).
  Every `github:` flake input therefore fails; vanixiets has 94 unique `github:` inputs (V18, R6).
- Allowlisted hosts include `*.nixos.org`, `*.cachix.org`, `*.scientistexperience.net`, `*.numtide.com` and `*.clan.lol` (V31).
- The setup script runs as root before Claude starts, cannot read the environment's variables or secrets, must not contain secrets, and is limited to 100 lines of 200 bytes (C7, C8, C9).
- The documentation says setup is snapshotted when it finishes within roughly five minutes, re-runs when the script or allowed hosts change or after about seven days, and does not run on idle restore (C12, C14).
- SessionStart hooks run on every session start and resume, uncached (C13).
- `update_environment` replaces the setup script of the environment the session runs in, behind an approval card each time (C5, C7, V5).

## Q1: setup script or SessionStart hook?

Options: do all bootstrap work in a SessionStart hook (the pattern in mizchi/vibe-lang and the kumewata write-up), or do it in the setup script, or split.
A hook re-runs on every session and resume, so any realisation it does is paid every time (C13); kumewata measured 68 s per start.
The setup script's writes are snapshotted and later sessions skip it (C12).
Evidence settled the cached path: child A2 and B2 sessions ran no setup and were working about 10 s after `create_session`, with the earlier run's files in place (session 2, A2 and B2).
Evidence also settled that setup-written context is honoured: `/root/.claude/CLAUDE.md` and `/root/.claude/skills/<n>/SKILL.md` written by setup were loaded in the first context (session 1 P3; session 2 A, A2, B, B2).
Outcome: the user tier (context, skills, CLIs) is installed by the setup script.
Hooks remain the only place for anything per-session: the attached repositories' context (they differ per session) and secrets (setup cannot read them).
Whether a hook declared in a setup-written `~/.claude/settings.json` runs at all, and what PATH it and the Bash tool see, is still open (probe P4).

## Q2: pin a revision or follow a branch?

Options: the shim names a branch ref (push to update), an environment variable names the revision, or the shim names a full revision.
A ref never invalidates the snapshot, because the cache only rebuilds when the script or allowed hosts change (C12), so pushes would not reach sessions until expiry.
An environment-variable switch has the same problem, and setup cannot read variables anyway (C7).
A revision in the script makes every update a script change, which is exactly the cache invalidator, and a script change costs one approval card.
Evidence: a remote `nix run git+https://github.com/cameronraysmith/vanixiets?rev=<sha>&shallow=1&dir=bootstrap/claude-sandbox` worked from setup (session 2 A), resolving O5.
Outcome: one pinned line naming one vanixiets revision.

## Q3: evaluate the flake in the sandbox, or substitute a prebuilt closure?

Option A: prefetch the 94 `github:` inputs over `git+https`, then evaluate the main flake in the sandbox.
The earlier session measured 75 s to prefetch (91 matched by narHash, 3 mismatched) and 37 s to list home configurations with extra substituters (V18–V20); building the composed skills also needs github at build time unless cached (machinery map §2).
Option B: a small bootstrap sub-flake whose only input is a channels.nixos.org tarball, which carries a pointer to a closure CI already built and pushed to the fleet cache; setup substitutes and activates it with no evaluation of the main flake.
The probe flake is a working instance of B's outer half: 23 s, 50 paths, 30.6 MiB from cache.nixos.org (session 2 A).
Trade-off: B depends on CI having built and cached the exact closure; A depends on GitHub's git service and on every input matching its narHash.
Leaning: B, recorded as open decision D2.

## Q4: a new profile or extend `ubuntu`?

`ubuntu@x86_64-linux` is the existing sandbox profile (built for Devin): it already handles no systemd, the C.UTF-8 locale and sops on tmpfs, but it imports neither agents-md nor agent-context nor ai-capabilities, its home is `/home/ubuntu`, and it declares sops secrets that need a key at activation (machinery map §4).
The `ai` aggregate assumes macOS paths and sops secrets for MCP servers and wrappers and does not evaluate without them (machinery map §4).
Options: add the agent modules to `ubuntu`; or a new `claude-sandbox` profile (root, `/root`) importing the sops-free subset, with the sandbox-handling parts of `ubuntu` factored into a shared aggregate both import.
Extending `ubuntu` would change Devin's profile and still leave the root home and secret declarations wrong for this sandbox.
Leaning: the new profile with a shared aggregate, recorded as open decision D1.

## Q5: Linear credentials

The Linear skills require `~/.config/linear/credentials.toml` with a default workspace and refuse to run when `LINEAR_API_KEY` or `LINEAR_WORKSPACE` is set (machinery map §6).
Options: none in v1; platform network secrets (header injection by the proxy); a sops file decrypted at session start from a key held in an environment variable, reusing `ubuntu`'s tmpfs mechanism.
Network secrets would leave no local credentials file, so the skills refuse to run; they are rejected for Linear.
The sops route puts a decryption key in an environment variable that the model and every process in the session can read.
This is security-sensitive and needs the operator's explicit decision; recorded as open decision D5, with "no secrets in v1" as the alternative.

## Q6: what happens when setup fails or runs long?

Evidence: a setup exiting 3 left the session pending forever with `last_init_error` "Setup script failed", `recoverable=false`; Claude never started (session 2 D), resolving O8.
`CCR_SETUP_SCRIPT_FAILURE_CONTINUES` appears in setup's environment (session 1 P6) and did not change that outcome.
Evidence: a 360 s setup was not cut off and was still snapshotted (session 2 B and B2), contradicting the documented five-minute bound and resolving O7 for 360 s; the real ceiling is unknown.
Outcome: the shim always exits 0 and degrades, and writes its own report, since the platform shows no setup output for a successful run (C15).

## Q7: the repository tier

The devshell already chooses the repository context tier by whether `~/.claude/CLAUDE.md` exists, so once the user tier is installed the repository file carries only the repository's own tier (machinery map §3).
The devshell cannot be entered in the sandbox without evaluating the main flake (Q3).
Option: a SessionStart hook runs `apm-context-compile --auto` from the activated closure in each attached repository that has `apm.yml`.
Recorded as open decision D3, gated on probe P4.
The Claude Code hooks module calls bare command names; recorded as open decision D4 (absolute store paths).

## Q8: the development loop

Evidence: a controller cloud session created child sessions with `create_session`, swapped the setup script with `update_environment` (one approval card each), and read the reports the children pushed to new branches (session 2), resolving O2 and O10 for new branch names.
Outcome: one operator action (start the controller with a prompt) plus one approval card per script swap.

## Settled by evidence versus still open

Settled: setup-written context and skills load; pinned `git+https` with `?dir=` works from setup; snapshots are reused; 360 s is accepted; non-zero exit is fatal; setup runs twice on first use; the Bash tool sees no profile or bashrc exports; about 64 GB of disk is free; the dev loop works.
Open at capture time: D1–D5, probe P4, the setup time ceiling, and the closure size the profile will have.

## Outcome

The operator authorized D1–D5 as recommended on 2026-11-21.
For D5 the operator chose a dedicated recipient `claude-sandbox-user` derived from a new Bitwarden SSH key `sops-claude-sandbox`, its private key placed directly in the environment's `SOPS_AGE_KEY` variable, and a scoped sops file holding only the Linear workspace keys.
The operator created the key, supplied the public recipient `age1sfddwr9waenu8du9mpxj7l4cfz7w3pkng4tc6xk4k4z09wj9tu8smr9xcf` and set `SOPS_AGE_KEY` in `nix-sandbox-test` the same day.
Still open: probe P4, the setup time ceiling, and the closure size.
