---
title: Home-manager aspects
created: 2026-09-04
---

## Home-manager aspects

Every `.nix` file under this directory is a flake-parts module that contributes `deferredModule` values to `flake.modules.homeManager.<aggregate>`.
A directory is an aggregate: one user-facing capability, named for what a user gets (`shell`, `development`, `herdr`), never for how it is declared.
A user is composed by listing aggregates in `flake.users.<name>.aggregates` (`users/<name>/meta.nix`); `configurations.nix` and `mk-home.nix` turn that list into one `homeConfigurations` output per declared system.
This is the dendritic pattern from `github:mightyiam/dendritic`: a file is one feature across every configuration that wants it, the path names the feature, and merging by aggregate name replaces import lists.

## Contract

One aggregate, one capability, one secret posture.
If part of an aggregate needs a sops secret and part does not, split it, so that a user who lacks the secret can still import the secret-free part.
`ai` needs secrets and `herdr` does not, so `herdr` is its own aggregate although the tool is used alongside AI agents.

Prefer the home-manager module to the raw package.
`home.packages = [ pkgs.x ]` records only that `x` is installed; `programs.x` records its configuration surface, shell integration, and environment.
A raw package is acceptable only when no `programs.*` or `services.*` module exists for it; it then lives in the aggregate that consumes it, in a file named for the package or for the small group that shares a purpose, such as one language's toolchain.

Configure at the consumer.
Fonts belong beside the terminal emulators that render them, and a wrapper's flags belong in the wrapper's module.
Nothing goes into a shared package list on the grounds that several aggregates might want it.

Per-user exceptions are overrides, not omissions.
A user who cannot run one module of an aggregate imports the aggregate and disables that module with `lib.mkForce` in `users/<name>/default.nix`, keeping the rest of the capability.
`users/ubuntu` does this for `programs.bash.enable` and `services.ssh-agent.enable`.

Reusable options and shared data are named deferred modules or `flake.lib` values, never `_name.nix` files pulled in through `imports`; `core/catppuccin.nix` shows the pattern.
Neither Den (drupol's aspect framework over dendritic flake-parts) nor `flake-file` (generating `flake.nix` from modules) is adopted here; both are evaluated in `github:drupol/infra`.

## Selectable development capabilities

`flake.modules.homeManager.repository-acquisition` supplies `ghq`, `ghq-sync`, `dependency-sources` and direct `zoxide` lookup without enabling interactive shell hooks.
It uses `programs.zoxide.package` directly when the program module is disabled; when that module is enabled, it owns both installation and shell integration.
This deliberate raw-package exception allows noninteractive lookup without changing the terminal aggregate's behavior.
The `ghq`, `ghq-sync` and `dependency-sources` constituent exports preserve the existing split: `development` selects only `ghq`, while `tools` selects the two wrappers.

`engineering-tools` groups recipe execution, edit checking and structured-output inspection through `just`, `shellcheck`, `uncomment` (from `uncomment-bin`), `ratchet`, `jc`, `jaq` and `yq`.
`nix-development` exposes the existing group in `development/nix-tools.nix` intact.
`development` imports both groups without moving its other domain, diagram or clipboard tools into them.
These Home Manager exports use consumer packages and stable module identities, so importing a named capability alongside its aggregate does not duplicate its contribution.
They require neither personal secrets nor `osConfig`, and selecting them confers no credentials or host authority.

## Hazards

Adding a file activates it on the next evaluation; there is no registration step.
An untracked file is invisible to `nix flake check`, so run `git add` before evaluating.

A user's evaluated package set is a contract for that user.
Moving a declaration between files must not change `home.packages` for any user unless the change is the point.
No check pins these sets, because a committed manifest would need regenerating on every package change and its aarch64 entries can only be produced on a host that can evaluate those configurations.
Instead, `just home-package-names` prints the sorted package names of every configuration for one system, the current one by default; run it on the base and on the change and diff the two outputs to review a relocation.
A configuration that imports from a derivation can only be evaluated by a host that can realise it; today this is `crs58` and `cameron` on aarch64-darwin and aarch64-linux, through `apm-skills-compose` in the `ai` aggregate.

The `<aggregate>/tools.nix` files hold raw packages that no home-manager module owns yet; they are split into per-program files as modules are adopted.

`users/ubuntu` is the profile activated inside a Devin sandbox VM, which has no AI secrets, and whose exec shells reach no systemd user manager while its snapshot builds do.
Modules that start user services or read sops secrets fail there and must be overridable as described above; an activation must also succeed under a user manager with no key present, which is what `base/sops-install-without-systemd.nix` provides.

## Verification

```bash
direnv exec . nix flake check --accept-flake-config
direnv exec . just home-package-names
direnv exec . nix eval --accept-flake-config --json .#lib.homePackageNames --apply 'f: (f "aarch64-darwin")."tara@aarch64-darwin"'
direnv exec . nix eval --accept-flake-config --json '.#homeConfigurations."crs58@x86_64-linux".config.home.packages' --apply 'ps: builtins.sort builtins.lessThan (map (p: p.name) ps)'
direnv exec . nix build --accept-flake-config '.#homeConfigurations."ubuntu@x86_64-linux".activationPackage'
```

The first is the closure operator every change must pass.
The second prints the per-user package names on this host; the diff of its output between base and change is the delta a reviewer reads.
The third produces one user's entry for another system from a host that can evaluate that configuration.
The fourth shows one user's versioned package names, for the case where a relocation could change a version rather than a name.
The fifth builds the sandbox profile that the Devin snapshot activates.

## Children

- `agents/` — agent CLIs (apm, cursor-agent, droid, gemini-cli, claudebox, claude-monitor, golem, hindsight, ouroboros); secret-free like `herdr/`, because the harness supplies credentials at run time, whereas `ai/` reads sops secrets.
  Distinct from the `agents-md` module under `modules/`, which generates the per-harness context files (`AGENTS.md`, `CLAUDE.md`, and others).
- `ai/` — agent tooling that needs sops secrets (cognee, opencode, moshi, devin); indexed by its own README.
- `base/` — sops-nix wiring, including activation without systemd.
- `bioinformatics/` — sequence alignment and SRA retrieval (minimap2, STAR, xsra).
- `compute/` — cloud, container, and Kubernetes command-line tools (gcloud, kubectl, helm, argo, crane, lima, and others).
- `core/` — fontconfig, XDG, Catppuccin, session variables, SSH, Bitwarden; imported by every user.
- `database/` — database engines and clients (PostgreSQL, SQLite, DuckDB, DataFusion, Turso, Supabase).
- `development/` — editors (LazyVim neovim, helix), version control (git, jujutsu, radicle), terminal emulators (ghostty) and the fonts they render, general and Nix development tools, and their configuration; agent CLIs live in `agents/`.
- `herdr/` — the herdr terminal multiplexer and `browser-terminal`, its ttyd front end for the sandbox; secret-free.
- `languages/` — one file per language toolchain (Rust, TypeScript, Go, Scala, Python, Haskell, OCaml, Elixir, proof assistants) at the latest stable version nixpkgs ships.
  For quick experiments with other versions, use proto as a dynamic version manager or a reproducible language-specific flake instead of editing these files.
- `modules/` — option-declaring home-manager modules consumed by aggregates (`agents-md`).
- `publishing/` — document and media production (Quarto, ImageMagick, PDF tools, SVG tools, mermaid, asciinema).
- `security/` — secrets and key handling (age, sops, ssh-to-age, Bitwarden CLI, YubiKey, gitleaks, aws-vault).
- `shell/` — bash, fish, atuin, tmux, zellij, yazi, session path, shell aliases.
- `terminal/` — terminal utilities with `programs.*` modules (bat, btop, fzf, zoxide, and others) and the raw Unix, I/O, and compression tools.
- `tools/` — operator tooling (nix helpers, gpg, awscli, k9s, texlive, typst, repository sync).
- `users/` — identity, aggregate lists, and per-user overrides; `lib.nix` declares `flake.users`.

Top-level files: `app.nix` (the `home` app, an `nh`-based `home-switch`), `configurations.nix`, `mk-home.nix`; `home-bootstrap` lives in `modules/apps/bootstrap/`.

## References

`github:mightyiam/dendritic` states the pattern.
`github:drupol/infra` shows feature ownership carried through: nearly every tool is enabled through its `programs.*` or `services.*` module, and each of the few raw packages sits inside the feature that uses it.
`github:GaetanLePage/nix-config` injects `core` into every home host and keeps each secret inside the feature that reads it.
To read them locally, acquire each with `ghq` as the `dependency-source-acquisition` skill describes.
