# Design

## Context and goals

The reviewed scratch build produced a compatible-looking Linux 6.18.42 module in eleven seconds using cached native inputs.
Its source omission and static ABI evidence are reusable; its ignored derivation and diagnostic output are not product inputs.
Produce a reproducible experimental boot candidate without rebuilding the kernel or changing running hardware state.

## Decisions

### D1: Tracked source, selected kernel inputs

At the first-party/upstream boundary, keep a tracked context patch recording the historical upstream commits.
Require Linux 6.18.42 and verify the reviewed `hci_bcm.c`, prepared configuration, Module.symvers and autoconf hashes.
Use `kernel.src`, `kernel.dev`, `kernel.stdenv` and native module make flags rather than permanent literal store paths or scratch imports.
Keep the native Makefile and assert all seven UART constituent objects.
Build only `hci_uart.ko`; do not build Linux, Bluetooth core or another driver.

### D2: Exact wake omission

Remove only `set_device_wakeup(dev, powered)` and its failure-specific shutdown reversal from `bcm_gpio_set_power`.
Apply at zero fuzz and verify that the complete changed file equals exactly those removals and other Bluetooth sources remain identical.
BTPU/BTPD, other clock/regulator/error cleanup and delays remain.
Only startup/shutdown BTLP calls disappear; suspend/resume still invoke the callback.
No model quirks, reset-first logic, baud, firmware or flow-control changes are introduced.

### D3: Machine-scoped selection

At the source/delivered boundary, add only Pyrite's `boot.extraModulePackages` contribution.
Install the stripped module under `updates/bluetooth` and let the actual aggregate module tree establish precedence.
Check both `hci_uart` and `acpi:BCM2E7C:APPLE-UART-BLTH:`; verify native dependency paths and existing ZFS/CS8409 selection.
Do not delete native files, blacklist modules or introduce an initrd preload.
The runtime package contains one module, not the scratch evidence or kernel development closure.

### D4: Build evidence is not boot acceptance

Build from the frozen own delivery rather than the integrated working copy or remote dirty checkout.
Dry-run each native build group, use the daemon with builders empty, max-jobs 1 and cores 2, and stop for full-kernel/compiler or exceptional expensive prerequisites.
Cached-input restoration and private closure transfers are permitted.
Compare the actual kernel derivation/output, module ABI and normalized non-Bluetooth initrd contents against the exact baseline.

## Risks and trade-offs

The historical workaround is not an established upstream solution and affects BCM power transitions throughout the module, not a DMI-specific quirk.
Omitting explicit BT_WAKE transitions depends on hardware/firmware state left by other power methods or earlier operations.
Unchanged suspend/resume callbacks can subsequently change that state.
Module metadata, symbols and relevant BTF layouts support compatibility but cannot substitute for the kernel loader or physical initialization.
A successful first boot does not certify idle power, reconnect, later reboot, suspend/resume or wake reliability.
An out-of-tree module may taint the kernel; rollback does not promise to clear taint without reboot.

## Migration and acceptance

No deployment is authorized during preparation.
After independent review and operator coordination, use normal source-based deployment, retaining recovery Generations 10 and 11.
Attest the fresh candidate boot and loaded module build ID/srcversion before any manual reload or other intervention.
Only then assess initialization/RX and Adapter1, followed by separately authorized intended-headset pairing and acoustic checks in GNOME and niri.
A missing attestation or partial observation is a pending gate, not success and not permission to reload or change audio policy.

## Open questions

Physical efficacy and power-management reliability remain unproven.
Niri headset silence is a separate unresolved issue.
Linear binding remains explicitly deferred to the parent/operator.
