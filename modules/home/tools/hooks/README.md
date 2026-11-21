---
title: Claude Code hook scripts
created: 2026-08-26
---

## Claude Code hook scripts

A hook takes effect through two files.
`default.nix` in this directory packages each script as a `pkgs.writeShellApplication` derivation, gives it a `name` and declares its `runtimeInputs`, all inside the function `flake.lib.claudeCodeHooks`, which takes `pkgs` and returns the derivations keyed by name.
`../../ai/claude-code/hooks.nix` defines `flake.modules.homeManager.claude-code-hooks`, imported by the `ai` aggregate and the `claude-sandbox` profile, which sets `programs.claude-code.settings.hooks.<Event>` to a list of `{ matcher; hooks = [ { type = "command"; command = <store path>; } ]; }` entries, each command being `lib.getExe` of the derivation of that name.
A hook therefore runs whether or not it is on PATH, as in a cloud session's profile, and naming a hook that `flake.lib.claudeCodeHooks` does not package fails evaluation.
The same module asserts that every command under `programs.claude-code.settings.hooks`, whichever module set it, starts with the store directory, so a bare command name added anywhere fails evaluation of every configuration that imports it.
`flake.modules.homeManager.tools` also appends the same derivations to `home.packages`, so after activation a hook can be exercised by hand without triggering its event, by piping the same JSON shape the harness would send: `echo '{}' | redirect-rm-to-rip`.
A derivation added to `default.nix` without a corresponding `command` entry in `hooks.nix` sits on PATH and never fires.
Not every derivation in `default.nix` is wired to an event this way: `notify-permission-wait` appears in `hooks.nix` nowhere, because `gate-mutating-http` and `gate-dangerous-commands` consume it only as a `runtimeInputs` entry, calling it internally rather than being invoked directly by an event.

The event names currently wired in `hooks.nix`, i.e. the top-level keys under `programs.claude-code.settings.hooks`, are `PreToolUse`, `WorktreeCreate`, `WorktreeRemove`, `PostToolUse`, `SessionStart`, `UserPromptSubmit`, and `Notification`.

A script's own file-mode executable bit is irrelevant.
Each `.sh` file here is never invoked directly; `default.nix` pulls its contents in with `builtins.readFile ./foo.sh` and hands that text to `writeShellApplication`, which builds a wrapped executable at `<derivation>/bin/<name>` with its own shebang and permissions.
The build does run `shellcheck` against that text, so a script with an unaddressed finding fails the build regardless of whether it is ever wired to an event.

A script's runtime dependencies are declared explicitly through `runtimeInputs`, either as `pkgs.*` packages or, for a hook that calls another hook script internally (as `gate-mutating-http` and `gate-dangerous-commands` call `notify-permission-wait`), as a reference to that other derivation's `let`-bound name.
`writeShellApplication` constrains the built executable's `PATH` to exactly its `runtimeInputs`.
Omitting a dependency is not a build-time error: `shellcheck` lints syntax, not command availability, so a missing dependency surfaces only as a "command not found" failure the first time the hook actually runs.

Several scripts (`enforce-branch-before-edit.sh`, `gate-worktree-surfaces.sh`, `gate-git-worktree.sh`, `verify-diamond-before-edit.sh`) share repository-context helpers from `lib-repo-context.sh`.
Because shell has no `import`, `default.nix` composes this in textually, prepending `repoContextLib` (the file's contents, read once) to the consuming script's `text`.
Each consumer only calls a subset of the shared helpers, so `default.nix` also sets `excludeShellChecks = repoContextShellChecks` (`[ "SC2329" ]`) on those derivations; omitting that exclusion fails the build on the helpers a given script does not happen to call.

Finally, flake sources in this repository are git-tracked only.
A new `.sh` file, or a `default.nix` edit that reads one, is invisible to a flake build until the file is tracked by git (`jj file track` in this jj-colocated repository), regardless of whether it exists on disk.
