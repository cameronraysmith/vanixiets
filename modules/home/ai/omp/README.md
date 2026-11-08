# omp

`default.nix` configures omp (oh-my-pi); its header comment explains which files it owns and why.

## Browser relay extension

omp's browser relay lets the Eval `browser` API drive the user's own browser, with its profiles and extensions, through a Chrome extension.
`pkgs/by-name/omp-browser-relay-extension` builds that extension by running `omp browser-relay install` with the omp that `programs.omp.package` installs.
The build fails unless the extension's version stamp equals that omp's version.
On darwin, `programs.omp.browserRelay.extension` copies the extension to `~/.omp/browser-relay/extension` on every activation.
That is the directory omp's relay updates by default.
Activation makes the directory mirror the package: it deletes extra files, makes the files writable, and leaves identical files untouched.

The directory is a real directory, not a symlink into the nix store.
Helium records the resolved path of an unpacked extension and derives the extension ID from it.
A store symlink would give the extension a new ID on every omp bump, and the browser would treat it as a different extension.
Activation fails if the directory is a symlink.

Each Helium profile needs one manual step: open `chrome://extensions`, turn on Developer mode, choose Load unpacked, and select `~/.omp/browser-relay/extension`.
The extension's badge shows `on` while a relay is running.
If omp's default directory moves (for example when `$XDG_DATA_HOME/omp` exists, or under an omp profile), the loaded path and omp's updater no longer agree.

The relay is enabled per call with `app.relay: true`.
`browser.relay` is not set in `config.yml`, because it would make every session in every project drive the real browser.

After an omp bump, activation writes the new extension files first.
Going by omp's relay source, the new relay's own update then finds identical files, writes nothing, and asks the extension to reload, so the browser picks up the new version without another manual step.
This has not yet been observed on a real bump.

Bitwarden is installed by hand in each Helium profile.
Force-installing it would need a macOS configuration profile that has to be approved manually.
Helium also ignores extension update URLs that do not go through its proxy on Macs not enrolled in MDM.

## ovnfs checkouts

`programs.omp.ovnfs.enable` (off by default) sets omp's `ovnfs.path` to the binary from `programs.omp.ovnfs.package`, which defaults to `pkgs/by-name/ovnfs`.
It does not add ovnfs to `home.packages`, so a shell has no `ovnfs` on PATH and only omp knows where the binary is.
With the switch off, `config.yml` carries no `ovnfs` key and omp behaves as before, as long as nothing else puts `ovnfs` on PATH.

From omp 18.17.0 the setting alone turns omp's ovnfs integration on (`ovnfsCommand` in `src/task/settings.ts`), with these effects:

- The system prompt gains a "Separate checkouts" section: an agent that wants a second copy of a folder MUST run `ovnfs new` instead of `git worktree add`, `git clone` or `cp -r`, unless the user asks for those (`src/prompts/system/system-prompt.md`).
- `grep` and `glob` inside an ovnfs checkout search through the ovnfs daemon, found with `ovnfs --json status`.
- The bash git guard names `ovnfs new` in its refusal hints when `bash.gitGuard` is on.
- Isolated subagents run in ovnfs checkouts only when `task.isolation.enabled` (off by default) is set and `isolation.backend` is `auto`; this module sets neither, so subagents are unaffected.

omp 18.17.0 and later require ovnfs admin protocol 5; ovnfs v0.3.0 serves protocol 5 (`protocolVersion` in `ops.go`).
`omp worktree clear` removes ovnfs checkouts that omp lost track of, from omp 18.18.1.

Enabling the switch conflicts with the fleet's worktree rule (`plugins/agent-context-vcs-jj/.apm/instructions/040-worktree-interop-and-external-frameworks.instructions.md`).
That rule keeps work in the jj development join and makes creating a separate tree an ask that is answered yes only when a separate tree is the point; in a flake repository that tree must be a colocated jj workspace or a git worktree.
omp's prompt section instead tells agents they MUST use an ovnfs checkout whenever they want a separate copy, and no ask gate covers `ovnfs new`.
Neither text yields to the other, so with the switch on an agent receives two contradictory instructions about separate trees, and which one it follows is not settled by configuration.
Whether jj and flake evaluation work inside an ovnfs checkout has not been tested here.
