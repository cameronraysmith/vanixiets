## Why

Pyrite's native CS8409 codec driver does not initialize the Apple subsystem `106b3300` speaker path.
The selected upstream Apple implementation has compiled against pyrite's exact Linux 6.18.42, including internal-header/layout and unloaded selection checks, but is not in the system configuration.
This change integrates that implementation without claiming working or acoustically safe speakers.

## What changes

Package `davidjo/snd_hda_macbookpro` revision `89b22ff90b86468b186706861dd18663562defa7` against the selected kernel source and prepared headers.
Add it only to pyrite's extra module packages, with its same-name module under `updates/codecs/cirrus` rather than overwriting the native path.
Check the full candidate module tree and preserve the existing kernel, other extra modules, native HDA dependencies, desktop and power policy.
Record a separate operator-controlled rollout and acoustic acceptance gate.

## Capabilities

### New capabilities

- `pyrite-apple-audio` (interface): the built candidate exposes the pinned Apple CS8409 implementation through the module loader's name and codec-alias interfaces.
  The trust boundary ends at build artifacts and unloaded selection; actual hardware initialization and acoustic safety require physical acceptance.

### Modified capabilities

None.

## Impact

Only the kernel-scoped package, pyrite's extra-module contribution, focused check and this local OpenSpec change are in scope.
The delivery starts at corrected DMS source `71e2355e69a832ed4b67e6763ea13014a8a5c9f4` and is separately composed with corrected DankGreeter `ab809bc2a501a86540a4685df77aa35a5085b4ae`.
Existing private refs remain unchanged.
Linear story binding is provisionally deferred by explicit authorization; no tracker publication or archival is part of this delivery.
The parent explicitly approved direct implementation after A14; this local change uses the proportional spec-driven schema, without another workflow or discovery round.
