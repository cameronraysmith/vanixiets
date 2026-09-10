# Tasks

## 1. Local preparation

- [x] 1.1 Scaffold the change with the installed schema and record approved scope — verify: openspec status --change pyrite-dms-session --json and planning artifacts.
- [x] 1.2 Pin the upstream DMS module without moving existing lock nodes — verify: semantic flake.lock comparison against the immutable niri base passed; logs/pyrite-dms-static-20260910.log.

## 2. Shell integration

- [x] 2.1 Compose native DMS into pyrite cameron with niri-only service ownership and required controls — verify: all nine desktop assertions true; logs/pyrite-dms-evaluate-5-20260910.log.
- [x] 2.2 Add native password lock, idle policy and typed bindings while preserving GNOME/GDM — verify: assertions, generated KDL evaluation, and baseline comparison of all 15 prior binds and preservation settings passed; logs/pyrite-dms-preservation-5-20260910.log.

## 3. Local verification

- [x] 3.1 Evaluate package identities, ownership, controls, lock and preservation assertions against an immutable candidate — verify: candidate 40bce3be9c086eddd6a30c605c7a348244fa5597 passes all desktop and NixOS assertions; three in-memory mutations rejected; verify.md records commands.
- [x] 3.2 Validate generated KDL with installed native niri — verify: exact reviewed b23e8a077956a75f3d25ec99558339a169384e6e built on pyrite; native validator reported config is valid, exit 0; logs/pyrite-dms-build-b23e8a077956-20260910/niri.stderr.log and niri.exit.
- [x] 3.3 Realize native DMS — verify: local cache substitution passed; authorized pyrite realization also exited 0, with DMS substituted rather than compiled or launched; logs/pyrite-dms-build-b23e8a077956-20260910/dms.result.json and dms.exit.
- [x] 3.4 Check Nix formatting and local OpenSpec structure — verify: nixfmt --check, openspec validate pyrite-dms-session --strict, and openspec validate --all --json exited 0.
- [x] 3.5 Prepare one signed local delivery commit and honest evidence — verify: scoped diff, valid SSH signature, Change-Id and pyrite-dms-prepared bookmark; final immutable ref returned to parent.

## Integration Verification

- [x] 4.1 Independent review before slice C or any deployment decision — verify: parent-owned review of immutable b23e8a077956a75f3d25ec99558339a169384e6e found no evidence-backed findings; logs/pyrite-dms-independent-review.md.
- [ ] 4.2 Inspect existing DMS session/settings state before separately authorized activation — verify: no legacy timeout migration overrides declared policy; do not silently overwrite user state.
- [ ] 4.3 Physical shell, login/logout, GNOME fallback, input and performance acceptance — verify: separately authorized panel observations; no equivalent local evaluation test.
- [ ] 4.4 Physical password lock/unlock and logind-lock acceptance — verify: separately authorized panel observations without suspend experiments.
- [ ] 4.5 Runtime notification/polkit/clipboard ownership and portal transactions — verify: separately authorized complete session snapshot, FileChooser and ScreenCast exercise.

Tasks 4.2–4.5 remain pending, not passed or authorized by the successful build.
The pyrite system toplevel build exited 0 without activation; exact source, outputs, complete logs and unchanged runtime identities are recorded in verify.md section 9.
CAM-59 remains untouched; CAM-66 requires niri.service inactive before any later authorized display-manager restart.
Linear binding and archive remain deferred.
