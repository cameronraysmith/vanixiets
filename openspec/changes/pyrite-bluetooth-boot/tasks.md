## 1. Source preparation

- [x] 1.1 Add the tracked historical patch and selected-kernel module-only recipe — verify: zero-fuzz dry-run on the reviewed source and byte comparison of the behavior patch; selected recipe evaluates for Linux 6.18.42.
- [x] 1.2 Add only the Pyrite extra-module contribution — verify: exact delivery diff against B contains one machine-file line and no foreign desktop changes.
- [x] 1.3 Add the focused aggregate-selection check — verify: frozen B fails its missing-candidate assertion; candidate check evaluates successfully.
- [x] 1.4 Record the configured OpenSpec artifacts and acceptance boundary — verify: scoped OpenSpec structural validation, not hardware validation.

## 2. Native store verification

- [ ] 2.1 Dry-run and build the exact candidate module on Pyrite with cached selected-kernel inputs — verify: managed daemon job, builders empty, max-jobs 1, cores 2, explicit exit and no full-kernel/compiler compilation.
- [ ] 2.2 Verify final module identity, metadata, aliases, undefined symbols, relevant BTF layouts and runtime closure against reviewed scratch/native — verify: post-fixup SHA256/build ID, metadata and ABI comparison logs, no development/source references.
- [ ] 2.3 Build the actual full aggregate tree and run focused Bluetooth and existing audio checks — verify: both name and BCM2E7C alias select the candidate, native dependency and ZFS/CS8409 preservation, cheap native-selection negative probe rejected.
- [ ] 2.4 Dry-run and build exact initrd/toplevel without activation — verify: unchanged kernel derivation/output, actual initrd selection/preload and normalized non-Bluetooth/crypto preservation, explicit successful build exits.

## 3. Integration Verification

- [ ] 3.1 Obtain parent independent source/build review of the immutable own delivery and artifacts — verify: reviewer findings resolved in the same delivery commit.
- [ ] 3.2 Coordinate separately authorized source-based deployment and attended fresh boot with recovery Generations 10 and 11 retained — verify: boot/system and loaded-module identity attested before manual intervention.
- [ ] 3.3 Assess initialization/RX and Adapter1, then separately authorized intended-headset pairing and GNOME/niri acoustic acceptance — verify: direct observations, not store-build inference; unresolved niri silence tracked separately.

Native verification is currently blocked before authentication completes: SSH reaches Pyrite and the server accepts the key, but agent signing does not finish within the bounded probe.
No native build, deployment, service change, radio action or audio action has occurred in this preparation.
Linear binding remains explicitly deferred; no external issue was created.
