# Verification boundary

The independent selection predicate in `logs/pyrite-apple-audio-20260911-selection.sh` ran against corrected B's actual module tree `/nix/store/l4mcqy5c6i8b6r8v2w3nai49zcplwqmx-linux-6.18.42-modules`.
It resolved the native `kernel/sound/hda/codecs/cirrus/snd-hda-codec-cs8409.ko.xz` and failed with `Apple replacement is not selected`, exit 1.
The baseline evaluator's first invocation used the wrong function application form; its error log is retained separately and is not RED evidence.

A14's exact-kernel compile and normalized native BTF/diagnostic DWARF layout comparison are supporting evidence, not a substitute for the product build.
The product retains a source-hash manifest and rechecks critical internal headers, release and symbols after stripping.
Final binary hashes are expected to differ from A14 because diagnostic debug information is removed.

The product build and full-tree check passed on 2026-09-11 in transient user job `pyrite-apple-audio-20260911-artifacts2`, exit 0.
The final module package is `/nix/store/6z46ys343p34va6xkd1yf048gy1g166p-snd-hda-macbookpro-0-unstable-2026-09-06-6.18.42`, with no registered runtime references.
Its source manifest matches a reconstruction of A14's exact kernel-source and upstream patch recipe.
The full module tree retains ZFS and all checked native HDA/Cirrus/HDMI paths; both name and codec alias select the replacement.
The kernel-version negative control rejects 6.18.43 with the explicit revalidation message, exit 1.

An initial product build revealed that disabling patchelf fixup alone does not disable nixpkgs' RPATH audit, which also calls patchelf on relocatable ELF.
The package now disables that inapplicable audit and checks the stripped module directly for build-directory references; required-symbol and kernel.dev-reference checks remain in place.
The second build has no patchelf error.
The built initrd contains 110 modules and no audio module; final exact-toplevel inspection remains part of the post-freeze record.
The initrd builder emitted unresolved `libcrypto.so.4` warnings for several systemd tools; the complete log retains these rather than presenting the build as warning-free.

The exact final commit identities, derivations, builds, full-tree/initrd selection, negative controls, actual closure references and before/after preservation evidence are recorded after source freeze in ignored `logs/pyrite-apple-audio-20260911-*` artifacts.
This avoids changing the tested source merely to embed its own commit ID.
Unchecked tasks remain unchecked until their evidence exists; source review and physical acceptance are parent/operator-owned.

OpenSpec validation checks document structure only.
This local interface-focused change does not introduce a world-designation table or claim a requirement-to-world entailment proof.
No build result establishes runtime initialization, acoustic safety, microphone support or suspend correctness.
