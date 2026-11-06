<!--
Raw capture of the brainstorming step for this change.

Procedural note, recorded rather than elided: the interactive `superpowers:brainstorming`
dialogue was not run. This change was authored by a delegated session whose brief
pre-settled the packaging, delivery, settings and scope decisions on the strength of three
spikes run before the change was opened (sandboxed install, Helium's record of an unpacked
extension's path, and Helium's policy handling). The schema-sanctioned manual-write path was
taken. What follows is the decision log the interactive skill would have produced.
Questions answered by the brief are marked `[given]`; questions answered from repository,
upstream or spike evidence are marked `[decided]` with the evidence inline; questions the
user answered are marked `[user]`; questions still open are marked `[open]`.
-->

# Background

omp (oh-my-pi) is the coding agent this fleet installs from `inputs.llm-agents.packages.${system}.omp`, at 18.16.0 when this change was opened, configured by `modules/home/ai/omp/default.nix` as a member of the `homeManager.ai` aggregate.
Its Eval tool exposes a `browser` API.
By default that API drives a browser omp launches itself; with `app.relay: true` on a call it instead drives tabs of the person's own Chromium browser through a relay: omp listens locally, and a browser extension the person has loaded connects to it and executes the commands through the Chrome debugger API.
Driving the person's own browser matters because that is where the person is signed in and where the Bitwarden password manager extension lives.

Upstream ships the relay extension two ways: as a release asset `omp-browser-relay-extension.zip`, and through `omp browser-relay install`, which writes the extension files into a directory, `dirs.rootSubdir("browser-relay", "data")` by default.
On stibnite that resolves to `~/.omp/browser-relay/extension`, because `$XDG_DATA_HOME/omp` does not exist and `~/.omp` is a real directory.
The person then loads that directory in the browser with chrome://extensions → Developer mode → Load unpacked.
Today nothing in the fleet runs the install; it would be an imperative step per laptop, repeated on every omp bump.

The person's browser is Helium (cask `helium-browser`, `modules/darwin/homebrew.nix:33`), installed on all four darwin hosts.
On stibnite it runs six profiles, each with Bitwarden already enabled.
pyrite, the NixOS laptop, has only the Firefox-based Zen browser, so the Chromium relay extension has no consumer there.

Upstream relay behaviour, read at `/private/var/lib/ghq/github.com/can1357/oh-my-pi`:
- `packages/coding-agent/src/tools/browser/relay/server.ts:49-62`: the relay updates the extension directory only when the unpacked extension ID derived from `realpath(dir)` equals the connected extension's ID, and only when the extension's reported omp version is not newer than the running omp.
- `bridge.ts:786-823`: after such an update the bridge sends the extension a reload (`bridge.ts:816`); the extension reloads itself on that message (`background.ts:283-285`).
- `extension-files.ts:50-53`: `writeRelayExtension` skips files whose content is already identical.
- No setting disables this self-update.
- The relay README (line 12) warns that setting `browser.relay` makes every session in every project drive the real browser.

# Decision chain

## Q1 [given]: build the extension, or fetch the release asset?

Build it with the deployed omp: a `runCommand` named `omp-browser-relay-extension-${omp.version}` with `nativeBuildInputs = [ omp ]` running `export HOME=$TMPDIR; omp browser-relay install --dir $out`.

Spike evidence [decided]: the build succeeds under an enforced sandbox, writes nothing outside `$out`, is deterministic under `nix build --rebuild`, and its output is byte-identical (`diff -r`) to upstream's v18.16.0 release asset (sha256 `383c47f7…af48f`).
The output holds `background.js` (first line `const OMP_INSTALL_VERSION = "18.16.0";`), `manifest.json` (`version` 0.1.0, `version_name` 18.16.0), `LICENSE`, `options.html` and `options.js`.

Building from the omp the fleet already deploys means the extension can never be a different release from the relay it talks to, and no second hash has to be bumped alongside omp.
Fetching the zip would add a hash per omp bump and could drift from the llm-agents omp.

## Q2 [user]: pin the extension's ID with a manifest `key`?

No. The store path is the single content identity; adding a `key` would proliferate hashes the operator maintains (user decision).
Stability of the ID comes from the delivered path instead (Q3).

## Q3 [decided]: deliver as a symlink into the store, or as a real directory?

A real directory at `~/.omp/browser-relay/extension`, refreshed by a Home Manager activation step that copies the package's files in, leaves them writable by the person (`u+w`), and removes files the package no longer has.

Rejected: `home.file` symlink to the store path.
Spike evidence: Helium 0.20.3.1 records the resolved path of an unpacked extension, so a symlinked directory is recorded as its store path and the extension ID is the hash of that store path.
Every omp bump changes the store path and therefore the ID; each profile would then hold a new, unknown extension and lose its site permissions and options, and the person would have to load it again in every profile.
With a fixed real directory the ID is the hash of `realpath(~/.omp/browser-relay/extension)`, stable for a given home.
A store path is also read-only, so omp's own updater (Background) could never write into it.

## Q4 [decided]: does activation fight omp's own self-update?

No, by the upstream behaviour in Background.
The directory activation writes is omp's own default directory, so its realpath hashes to the loaded extension's ID and omp's relay considers it its own.
After an omp bump, activation writes the new release's stamped files; the new relay finds the connected extension reporting an older version, rewrites the directory (a no-op, every file already identical) and sends the reload, so the browser runs the new extension without the person reloading it.
This is [INFERENCE] until observed live after a real omp bump; it stays an open verification task.

## Q5 [given]: set `browser.relay: true` in omp's managed settings?

No. The relay is requested per call with `app.relay: true`.
Setting `browser.relay` would make every session in every project drive the person's real browser (relay README line 12), which is the person's signed-in browser with the password manager.

## Q6 [decided]: which hosts?

darwin only by default, keyed on the Home Manager platform, because Helium is installed on all four darwin hosts and on no NixOS host.
pyrite runs only Zen, a Firefox derivative, which cannot load a Chromium extension.

## Q7 [decided]: force-install Bitwarden (and the relay extension) by browser policy?

No; Bitwarden stays a manual, already-done step and the relay extension is loaded by hand once per profile.

Rejected: a Chromium `ExtensionInstallForcelist` policy.
Spike evidence: user-domain defaults (`defaults write net.imput.helium ...`) are only "recommended" policy, and Chromium ignores `ExtensionInstallForcelist` at that level; mandatory policy on macOS requires a configuration profile the person approves manually in System Settings, and on a Mac not enrolled in device management Helium additionally filters non-proxied update URLs.
Delivering a configuration profile is a manual approval step no less manual than the one it would replace, and adds a management surface for one extension already present in all six profiles.

Also avoided: `ExtensionSettings` `runtime_blocked_hosts` and `DisableScreenshots`; either makes Chromium refuse the relay's debugger attach ("Host access is restricted by policy", Chromium `debugger_api.cc`).

## Q8 [open]: what if omp's default directory moves?

If `$XDG_DATA_HOME/omp` is ever created, or an omp profile is used, omp's default relay directory moves away from `~/.omp/browser-relay/extension`; the loaded directory and the directory omp's updater writes then diverge silently.
Recorded as a world assumption with a violation condition and as a documented hazard; not automated.

# Agreed approach

A package `omp-browser-relay-extension` built from the deployed omp with a build-time check that the stamped version equals `omp.version`; a darwin-default Home Manager option under `programs.omp` that copies it into `~/.omp/browser-relay/extension` on activation; no `browser.relay` setting; and documentation of the residual per-profile "Load unpacked" step.
