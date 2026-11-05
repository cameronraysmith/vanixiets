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
