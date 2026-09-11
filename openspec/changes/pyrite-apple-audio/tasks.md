## 1. Local implementation

- [x] 1.1 Observe an independent replacement-selection predicate fail on exact corrected B.
- [x] 1.2 Package the pinned upstream against matching kernel source/config/headers, with zero-fuzz patches and post-strip symbol checks.
- [x] 1.3 Add the pyrite-only extra module and focused full-tree check without changing other machine policy.
- [x] 1.4 Record upstream limitations and the separate no-startup-sound/software-volume rollout gate.

## 2. Exact artifact verification

- [x] 2.1 Compile the product recipe against exact Linux 6.18.42 and inspect actual closure references and source identity.
- [x] 2.2 Build the full candidate module tree and focused check; verify name/alias selection and native dependencies, with negative controls.
- [ ] 2.3 Freeze new B/C refs, build both exact toplevels and inspect the actual initrd.
- [ ] 2.4 Verify parent scope, unchanged old refs and preserved live state; retain exact outputs and logs outside the frozen source.

Tasks 2.3–2.4 are executed after source freeze; their final status belongs to the external verification record rather than a self-referential source amendment.

## 3. Separate acceptance

- [ ] 3.1 Parent arranges independent source review and operator-controlled rollout/recovery and sound-suppression preparation.
- [ ] 3.2 Operator verifies binding and conservative acoustic acceptance after separately authorized deployment/reboot.
- [ ] 3.3 Bind a Linear story before publication or archival; local binding remains explicitly deferred.
