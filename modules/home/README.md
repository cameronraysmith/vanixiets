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
`home.packages = [ pkgs.x ]` records only that `x` is installed; `programs.x` records its configuration surface, shell integration, and environment, at the same line count.
A raw package is acceptable only when no `programs.*` or `services.*` module exists for it; it then lives in the aggregate that consumes it, in a file named for the package.

Configure at the consumer.
Fonts belong beside the terminal emulators that render them, and a wrapper's flags belong in the wrapper's module.
Nothing goes into a shared package list on the grounds that several aggregates might want it.

Per-user exceptions are overrides, not omissions.
A user who cannot run one module of an aggregate imports the aggregate and disables that module with `lib.mkForce` in `users/<name>/default.nix`, keeping the rest of the capability.
`users/ubuntu` does this for `programs.bash.enable` and `services.ssh-agent.enable`.

Reusable options and shared data are named deferred modules or `flake.lib` values, never `_name.nix` files pulled in through `imports`; `core/catppuccin.nix` shows the pattern.
Den and `flake-file` are not adopted here.

## Hazards

Adding a file activates it on the next evaluation; there is no registration step.
An untracked file is invisible to `nix flake check`, so run `git add` before evaluating.

A user's evaluated package set is a contract for that user.
Moving a declaration between files must not change `home.packages` for any user unless the change is the point; the structure checks under `modules/checks/` catch accidental drift.

`users/ubuntu` is the profile activated inside a Devin sandbox VM, which has no systemd user manager and no AI secrets.
Modules that start user services or read sops secrets fail there and must be overridable as described above.

## Verification

```bash
direnv exec . nix flake check --accept-flake-config
nix eval --accept-flake-config --json '.#homeConfigurations."crs58@x86_64-linux".config.home.packages' --apply 'ps: builtins.sort builtins.lessThan (map (p: p.name) ps)'
nix build --accept-flake-config '.#homeConfigurations."ubuntu@x86_64-linux".activationPackage'
```

The first is the closure operator every change must pass.
The second is the per-user package contract; compare it against the base branch for any change that claims to be a relocation.
The third builds the sandbox profile that the Devin snapshot activates.

## Children

- `ai/` — agent tooling that needs sops secrets (cognee, opencode, moshi, devin); indexed by its own README.
- `base/` — sops-nix wiring, including activation without systemd.
- `core/` — fontconfig, XDG, Catppuccin, session variables, SSH, Bitwarden; imported by every user.
- `development/` — editors (LazyVim neovim, helix), version control (git, jujutsu, radicle), terminal emulators (ghostty), and their configuration.
- `herdr/` — the herdr terminal multiplexer, secret-free.
- `modules/` — option-declaring home-manager modules consumed by aggregates (`agents-md`).
- `packages/` — raw package lists not yet attached to the aggregate that consumes them.
- `shell/` — bash, fish, atuin, tmux, zellij, yazi, session path.
- `terminal/` — terminal utilities with `programs.*` modules (bat, btop, fzf, zoxide, and others) and the browser terminal wrapper for the sandbox.
- `tools/` — operator tooling (nix helpers, gpg, awscli, k9s, texlive, typst, repository sync).
- `users/` — identity, aggregate lists, and per-user overrides; `lib.nix` declares `flake.users`.

Top-level files: `app.nix` (the `home-bootstrap` app), `configurations.nix`, `mk-home.nix`.

## References

`github:mightyiam/dendritic` states the pattern.
`github:drupol/infra` shows feature ownership carried through: fifteen `programs.*` and thirteen `services.*` declarations against nine raw packages, each raw package inside the feature that uses it.
`github:GaetanLePage/nix-config` injects `core` into every home host and keeps each secret inside the feature that reads it.
To read them locally, acquire each with `ghq` as the `dependency-source-acquisition` skill describes.
