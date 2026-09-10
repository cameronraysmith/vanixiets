## 1. Preparation

- [x] 1.1 Record the authorized C plan and B boundary — verify: local OpenSpec artifacts and exact B ref inspection.
- [x] 1.2 Establish missing-greeter RED on B — verify: direct evaluation fails the enabled-native-greeter/disabled-GDM assertion.

## 2. Implementation

- [x] 2.1 Configure native greeter, explicit PAM selection and typed niri configuration — verify: merged native provenance, isolation and PAM assertions.
- [x] 2.2 Preserve supporting services and B desktop policy — verify: merged assertions and baseline interface comparison.
- [x] 2.3 Add native generated greeter validation check — verify: real Linux niri validation plus launcher and asset checks.
- [x] 2.4 Apply the approved rejection of empty passwords in shared login PAM, including console login — verify: PAM RED/GREEN and rendered Unix auth rules without `nullok`, with normal password authentication preserved.

## 3. Candidate verification

- [x] 3.1 Evaluate all assertions and reject representative invalid configurations — verify: immutable-source eval and mutation receipts.
- [x] 3.2 Check formatting, secrets, source scope and OpenSpec structure — verify: nixfmt, gitleaks, Git diff and openspec validate.
- [x] 3.3 Privately transfer and build initial immutable C `468fc7b1ff4f87be0ab5b54cc78423369118b861` without activation — verify: historical native greeter check, user niri config and full toplevel receipts with before/after runtime snapshots; not final repaired-source build evidence.
- [x] 3.4 Repair review findings F1–F3 — verify: local RED, native session registration, absent sync hook and exact deny-module guard with three new rejected mutations.
- [x] 3.5 Re-evaluate repair preservation — verify: 18 B interface groups plus five C comparisons that account for native systemd/loginuid session rules and removal of the unused sync hook.

## Integration Verification

- [ ] 4.1 Obtain independent source review — verify: parent review of returned immutable source.
- [ ] 4.2 Inspect existing mutable DMS state and optional greeter override paths before activation — verify: separately authorized read-only inspection, without resetting state.
- [ ] 4.3 Accept physical authenticated login/logout, greeter return, rendering, input and responsiveness — verify: operator-observed session cycle after separately authorized activation.
- [ ] 4.4 Accept password lock/unlock, lid lock and keyring unlock — verify: operator-observed authentication and locking; no suspend experiment.
- [ ] 4.5 Accept live shell/notification/polkit ownership and portal transactions — verify: active-session ownership snapshot and actual FileChooser/ScreenCast/polkit transactions.
- [ ] 4.6 Build exact final reviewed B/C revisions — verify: parent-owned external build receipts; no later metadata-only revision substituted for a built toplevel.
