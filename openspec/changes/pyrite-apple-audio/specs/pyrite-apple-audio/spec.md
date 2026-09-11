## ADDED Requirements

### Requirement: Exact-kernel Apple module compatibility

The candidate SHALL build the pinned Apple CS8409 implementation against pyrite's selected Linux 6.18.42 source, internal headers and configuration, retaining module-required symbols after debug stripping.
It SHALL reject an unchecked kernel version, mismatched internal headers, incompatible patch layout, unsupported HDA configuration or unresolved kernel symbols.

#### Scenario: Checked kernel and source

- **WHEN** the candidate is built with the selected kernel and upstream revision
- **THEN** its stripped module has matching release metadata and no undefined symbols absent from that kernel's symbol table
- **AND** its runtime closure excludes diagnostic kernel.dev references

#### Scenario: Unchecked kernel

- **WHEN** the selected kernel version differs from 6.18.42
- **THEN** package evaluation fails with the explicit revalidation requirement

### Requirement: Deterministic unloaded replacement selection

The full candidate module tree SHALL select the Apple CS8409 module by both module name and codec alias while retaining native HDA dependencies, other Cirrus codecs, Intel HDMI and configured extra modules.
It SHALL NOT blacklist the shared CS8409 name, overwrite its native path or change the kernel to achieve selection.

#### Scenario: Root-stage module lookup

- **WHEN** an unloaded lookup uses `snd_hda_codec_cs8409` or `hdaudio:v10138409r00100100a01` in the candidate tree
- **THEN** both resolve to the pinned replacement in `updates/codecs/cirrus`
- **AND** the dependency index has exactly one selected CS8409 entry

#### Scenario: Initrd inspection

- **WHEN** the actual candidate initrd is inspected
- **THEN** it either omits audio modules or contains the replacement without a native CS8409 preload path
- **AND** no audio module is made initrd-required solely for this check

### Requirement: Build-only delivery boundary

The delivery SHALL preserve unrelated configuration and running state and SHALL distinguish artifact compatibility from physical acceptance.

#### Scenario: Successful artifact checks

- **WHEN** module, tree, check and system builds succeed
- **THEN** actual speaker operation and acoustic safety remain explicitly unverified
- **AND** activation, loading and playback remain gated on a separate operator-controlled rollout and software-volume/amplitude preparation
