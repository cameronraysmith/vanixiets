## 1. Auto-hide slice

- [x] 1.1 Establish missing-autoHide RED on generation 13's frozen source — verify: assertion rejected, exit 1, `logs/pyrite-autohide-red-20260915T043311Z.log`.
- [x] 1.2 Add the default-bar setting and desktop assertion; verify GREEN and unchanged other bar settings — verify: full settings comparison and all system assertions passed, exit 0, `logs/pyrite-autohide-green-20260915T043311Z.log`.
- [x] 1.3 Freeze and verify the first local delivery commit — verify: path-scoped local delivery, nixfmt and strict OpenSpec validation passed; immutable ref and final evaluation recorded in the ignored preparation report.

## 2. Zen slice

- [ ] 2.1 Pin the approved input following root nixpkgs, preserving existing lock nodes.
- [ ] 2.2 Install the wrapped package through a pyrite-only cameron aggregate import and add focused desktop checks.
- [ ] 2.3 Verify package scope, unchanged browser defaults, system assertions and hardware artifact identities.
- [ ] 2.4 Build the exact frozen candidate natively and inspect the desktop entry and wrapper.

## Integration Verification

- [ ] 3.1 Parent independently reviews both immutable commits and build evidence.
- [ ] 3.2 Operator accepts physical bar hiding and hover reveal after separately authorized activation.
- [ ] 3.3 Operator accepts browser launch after separately authorized activation.

No preparation task authorizes activation or closes TODO-98b80efc.
