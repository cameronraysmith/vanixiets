## 1. Auto-hide slice

- [x] 1.1 Establish missing-autoHide RED on generation 13's frozen source — verify: assertion rejected, exit 1, `logs/pyrite-autohide-red-20260915T043311Z.log`.
- [x] 1.2 Add the default-bar setting and desktop assertion; verify GREEN and unchanged other bar settings — verify: full settings comparison and all system assertions passed, exit 0, `logs/pyrite-autohide-green-20260915T043311Z.log`.
- [x] 1.3 Freeze and verify the first local delivery commit — verify: path-scoped local delivery, nixfmt and strict OpenSpec validation passed; immutable ref and final evaluation recorded in the ignored preparation report.

## 2. Zen slice

- [x] 2.1 Pin the approved input following root nixpkgs, preserving existing lock nodes — verify: deleting only the new root edge and Zen node yields the unchanged base lock, SHA-256 `7f468c5f5ff66e608075491501bb378d582f0847ce3ba65c82a5276bbc41f4c9`.
- [x] 2.2 Install the wrapped package through a pyrite-only cameron aggregate import and add focused desktop checks — verify: baseline package-count RED exited 1; candidate package-count and full system assertions passed.
- [x] 2.3 Verify package scope, unchanged browser defaults, system assertions and hardware artifact identities — verify: six NixOS hosts, four Darwin hosts and thirteen standalone native/target-system homes compared; seven preservation predicates passed in `logs/pyrite-desktop-preservation-20260915T043311Z.json`.
- [ ] 2.4 Build the exact frozen candidate natively and inspect the desktop entry and wrapper.

## Integration Verification

- [ ] 3.1 Parent independently reviews both immutable commits and build evidence.
- [ ] 3.2 Operator accepts physical bar hiding and hover reveal after separately authorized activation.
- [ ] 3.3 Operator accepts browser launch after separately authorized activation.

Final native-build evidence is recorded against the frozen delivery ref in the ignored preparation report, without rewriting that ref merely to update a task checkbox.
No preparation task authorizes activation or closes TODO-98b80efc.
