## Context

omp is installed for each account in the `homeManager.ai` aggregate by `modules/home/ai/omp/default.nix`, from `inputs.llm-agents.packages.${system}.omp` (18.16.0 when this change opened); its user configuration is written by `managedConfigs` rather than as store symlinks, because omp persists to the same files at runtime.
omp's Eval `browser` API drives the person's own Chromium browser only through its relay: omp listens locally, and the relay extension, loaded unpacked in the browser, connects to it and drives tabs through the Chrome debugger API.
A call opts in with `app.relay: true`; the `browser.relay` setting would opt in every session.

The browser is Helium (cask `helium-browser`, `modules/darwin/homebrew.nix:33`) on all four darwin hosts; stibnite runs six Helium profiles, each with Bitwarden enabled.
No NixOS host has a Chromium browser; pyrite runs only Zen.

Upstream installs the extension with `omp browser-relay install [--dir]`, by default into `dirs.rootSubdir("browser-relay", "data")`, which on stibnite is `~/.omp/browser-relay/extension` because `$XDG_DATA_HOME/omp` does not exist and `~/.omp` is a real directory.
The relay keeps a loaded extension current itself (`packages/coding-agent/src/tools/browser/relay/server.ts:49-62`, `bridge.ts:786-823`): it rewrites the directory only when the unpacked-extension ID derived from the directory's resolved path equals the connected extension's ID and the extension reports an older omp release; `writeRelayExtension` skips identical files (`extension-files.ts:50-53`); the bridge then sends a reload (`bridge.ts:816`), which the extension obeys (`background.ts:283-285`).
No setting disables that self-update.

Three spikes were run before this change opened: a sandboxed build of the install (Q1 in `brainstorm.md`), Helium's record of a symlinked unpacked extension (Q3), and Helium's handling of user-domain and profile policies (Q7).

## Goals / Non-Goals

**Goals:**
- Build the relay extension from the omp the fleet deploys, with no second version or hash to maintain.
- Place it on darwin hosts where the browser can load it once per profile and keep the same extension identity across omp upgrades.
- Leave omp's own updater able to refresh and reload the loaded extension.
- Document the residual manual step and its hazards beside the module.

**Non-Goals:**
- Loading the extension into Helium profiles automatically.
- Installing or forcing Bitwarden or any other browser extension.
- Enabling the relay for every session (`browser.relay`).
- Any NixOS host, or any browser other than Helium.
- Pinning the extension ID with a manifest `key`.

## Decisions

### D1: Build the extension with the deployed omp — vendored-versus-first-party boundary

- **Choice**: `pkgs/by-name/omp-browser-relay-extension/package.nix` is a `runCommand "omp-browser-relay-extension-${omp.version}"` with `nativeBuildInputs = [ omp ]` whose script runs `export HOME=$TMPDIR; omp browser-relay install --dir $out`, then fails the build unless the first line of `$out/background.js` stamps `OMP_INSTALL_VERSION` equal to `omp.version`. The omp it uses is an overridable argument (`ompPackage`) so the Home Manager option can pass `programs.omp.package`; the package is exposed as `packages.<system>.omp-browser-relay-extension` with the check `checks.<system>.package-omp-browser-relay-extension`.
- **Rationale**: the extension content is vendored (upstream's bundled assets inside the omp package); the package is a first-party wrapper that only invokes upstream's installer. Spike: the build succeeds under an enforced sandbox, writes nothing outside `$out`, is reproducible under `nix build --rebuild`, and is byte-identical by `diff -r` to the v18.16.0 release asset `omp-browser-relay-extension.zip` (sha256 `383c47f7…af48f`). The stamp check turns a silent mismatch between the omp used to build and the omp deployed into a build failure.
- **Alternatives considered**: fetching the release zip with `fetchzip` — rejected, it adds a hash to bump on every omp update and can drift from the llm-agents omp; adding a manifest `key` to pin the ID — rejected by the user to avoid proliferating hashes, and unnecessary given D2.

### D2: Deliver by activation copy into a fixed real directory — source-versus-delivered boundary

- **Choice**: a Home Manager option set `programs.omp.browserRelay.extension.{enable, package, directory}` in `modules/home/ai/omp/default.nix`, `enable` defaulting to `pkgs.stdenv.hostPlatform.isDarwin`, `package` defaulting to the D1 package built from `programs.omp.package`, `directory` defaulting to `~/.omp/browser-relay/extension`. When enabled, the activation step `home.activation.ompBrowserRelayExtension` creates `directory` as a real directory if absent, refuses with a clear message and changes nothing if it is a symbolic link (a link there means someone deliberately pointed it elsewhere, and replacing it would silently change the extension's identity), copies the package's files into it, leaves them writable by the account (`u+w`), and removes files the package does not contain.
- **Rationale**: the delivered artifact must be a mutable path, not the store source. Spike: Helium 0.20.3.1 records the resolved path of an unpacked extension, and its ID is a hash of that path; a real directory at a fixed home path gives one ID per home that survives every omp upgrade. Because the directory is omp's own default, omp's updater recognises it (its resolved path hashes to the connected ID) and can write into it.
- **Alternatives considered**: `home.file` or `xdg.dataFile` symlink to the store path — rejected by the spike: Helium would record the store path, so the ID would change on every omp bump, each of the six profiles would see a new extension, lose its permissions and options, and need loading again; and omp's updater could not write a read-only store path. Leaving it to `omp browser-relay install` run by hand — rejected as the imperative step this change removes.

### D3: Rely on omp's self-update for the reload, not on activation

- **Choice**: activation only writes files; it never tries to reload the extension in the browser. After an omp upgrade, the next relay connection finds the extension reporting the older release, rewrites the directory (every file already identical, so nothing changes) and sends the reload.
- **Rationale**: upstream behaviour quoted in Context; activation cannot reach a running browser, and the relay already can. This is [INFERENCE] until observed after a real omp bump, so it remains an open verification task.
- **Alternatives considered**: a launchd agent or activation hook that reloads the extension — rejected, no API reaches an unpacked extension from outside the browser, and it would duplicate upstream.

### D4: No `browser.relay` in managed settings

- **Choice**: `programs.omp.settings` stays free of `browser.relay`; a call requests the relay with `app.relay: true`.
- **Rationale**: setting it would make every session in every project drive the person's signed-in browser (relay README line 12).
- **Alternatives considered**: enabling it fleet-wide — rejected for that reason.

### D5: darwin only by default; Bitwarden stays manual

- **Choice**: `enable` defaults true only on darwin. Bitwarden and the relay extension are loaded by the person; the fleet sets no Helium policy.
- **Rationale**: Helium is installed on every darwin host and no NixOS host. Spike: user-domain `defaults` for Helium are recommended-level policy, which Chromium ignores for `ExtensionInstallForcelist`; mandatory policy on macOS needs a configuration profile the person approves manually in System Settings, and on a Mac not enrolled in device management Helium also filters non-proxied update URLs. Bitwarden is already enabled in all six stibnite profiles.
- **Alternatives considered**: a macOS configuration profile forcing Bitwarden (and the relay extension) — rejected, it trades one manual approval for another and adds a management surface for an extension already present; `ExtensionSettings` with `runtime_blocked_hosts` or `DisableScreenshots` as hardening — rejected, either makes Chromium refuse the relay's debugger attach ("Host access is restricted by policy", Chromium `debugger_api.cc`).

### D6: Document the manual step at the module

- **Choice**: a new `modules/home/ai/omp/README.md` records, once per Helium profile, chrome://extensions → Developer mode → Load unpacked → `~/.omp/browser-relay/extension`, that the extension badge reads "on" while a relay runs, that requests opt in with `app.relay: true`, and the hazard that creating `$XDG_DATA_HOME/omp` or using an omp profile moves omp's default directory away from the loaded one.
- **Rationale**: the nearest README carries a directory's contract and hazards in this repository.
- **Alternatives considered**: documenting in `modules/home/ai/README.md` — rejected, it indexes children rather than carrying harness detail.

## Risks / Trade-offs

- [Risk] omp's default relay directory moves (`$XDG_DATA_HOME/omp` created, or an omp profile used) → the loaded directory and omp's updater diverge silently, and the extension stops following upgrades. Mitigation: world assumption A69 with its violation condition, and the README hazard; the `directory` option can be pointed at the new location.
- [Risk] Helium stops identifying unpacked extensions by resolved path → the extension ID changes or the updater stops recognising the directory. Mitigation: world assumption A67; the per-profile load would need repeating once.
- [Risk] omp's relay stops refreshing or reloading the loaded extension (A68) → after an upgrade the browser runs the old extension until the person reloads it in each profile. Mitigation: activation still writes the new files, so a manual reload suffices; task 5.4 records the first observed upgrade.
- [Trade-off] Activation and omp's updater both write the same directory; between activations it holds whatever omp last wrote. Accepted: both write upstream's files for an omp release, and the updater never writes an older release over a newer one.
- [Trade-off] One manual load per Helium profile remains. Accepted per D5.
- [Risk] Once loaded, any omp session that requests the relay drives the person's signed-in browser, including sites Bitwarden has filled. Accepted: the opt-in is per request (D4); the change confers no isolation beyond that.

## Migration Plan

1. Land the package, option and README; build the package and the darwin checks on aarch64-darwin.
2. Deploy stibnite; inspect `~/.omp/browser-relay/extension` (a real directory, the package's files, writable).
3. In each Helium profile, the person loads the directory unpacked; confirm the badge and a relay tab.
4. Other darwin hosts pick the folder up at their next activation; each person loads it once per profile there.
Rollback: disable `programs.omp.browserRelay.extension.enable` or revert; the folder is left in place and harmless, and the person may remove the extension from each profile.

## Open Questions

- Does the automatic reload after an omp upgrade (D3) happen as inferred? Resolved only at the first omp bump after deployment (task 5.4).
- Two other active changes (`stand-up-gitea-mq-on-magnetite`, `stand-up-nixbot-on-magnetite`) also modify the `world-assumptions` designation table; whichever archives later must merge its rows into the table the earlier one folded in.
