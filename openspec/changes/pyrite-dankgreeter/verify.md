# Verification report

Change: `pyrite-dankgreeter`.
Verifier: direct implementation worker, GPT-6 Astra, 2026-09-10.
Status: review repairs locally evaluated; independent re-review, exact-final Linux builds and physical acceptance remain pending.

## 1. Structural validation

`openspec validate pyrite-dankgreeter --strict` exited 0 after planning and initial implementation.
This checks document structure, not authentication safety or physical behavior.

## 2. Task completion

Initial preparation and authorized Linux builds completed for the historical source recorded below.
Independent review required F1–F3 repairs; their local evidence is in section 9.
The user-approved shared-login empty-password policy remains in force.
Independent re-review, exact-final builds, mutable-state inspection and physical acceptance remain pending.

## 3. Delta spec sync state

Four added interface requirements under `machine-interface` remain local to this change.
No corpus sync, binding, publication or archive occurred.

## 4. Design and specification coherence

Native greeter/PAM selection, typed configuration and explicit supporting services implement design D1–D3; D5 records the bounded no-sync repair.
D4's initial private transfer and build completed without activation; historical before/after runtime snapshots match.
Those receipts do not cover the repaired source or later metadata revisions.

## 5. Implementation and evidence

Base: `a8f9f6b6fd40754be016bab1dc874f7adf42ba52` (`pyrite-dms-prepared`).
Delivery change: `noylyowusxqorvmknxkkpnkxqpxpnqpv` / `pyrite-dankgreeter-prepared`.
Initial evaluated C source: `afa374c3af0869947aa9e056d16ef287662c641a`.
Historical built C source: `468fc7b1ff4f87be0ab5b54cc78423369118b861`.
Private build ref: `refs/heads/pyrite-dankgreeter-build-468fc7b1ff4f` on `pyrite.zt:projects/vanixiets`.
Pre-review metadata revision: `26c8ad0db83359176077916932c6b1f7b447acde`; it was not remotely built and evaluates to a different toplevel despite identical Nix blobs.

All Nix commands used `--store daemon --builders '' --max-jobs 1 --cores 2 --option accept-flake-config false --no-write-lock-file --no-update-lock-file`.
Immutable sources used `git+file:///Users/crs58/projects/vanixiets?rev=<sha>`.

| Check | Observed result | Evidence |
|---|---|---|
| B RED | Exit 1: asserted native greeter enabled/GDM disabled is false | `logs/pyrite-dankgreeter-red-20260910.log` |
| Initial merged eval | Exit 1: greeter isolation and native PAM assertions fail when forcing toplevel | `logs/pyrite-dankgreeter-evaluate-1-20260910.log` |
| Diagnostic eval without toplevel | Exit 0, nine assertions true, isolation/PAM false; actual custom KDL, greetd settings and PAM text captured | `logs/pyrite-dankgreeter-diagnose-20260910.log` |
| B login PAM | Eval exit 0: `allowNullPassword=true`, Unix auth true, rootOK/fingerprint false | `logs/pyrite-dankgreeter-baseline-login-pam-20260910.log` |

The diagnostic command is `nix eval --json --file logs/pyrite-dankgreeter-evaluate.nix --apply 'f: builtins.removeAttrs (f { candidate = "<sha>"; }) [ "toplevel" ]'` with the flags above.
The initial isolation predicate expected an unquoted environment key; actual typed output is `environment { "DMS_RUN_GREETER" "1"; }`.
That predicate was corrected without changing generated configuration.
The launcher check's `-C` expectation was also corrected after evaluating pinned `lib.escapeShellArgs [ "sh" "-C" "/nix/store/config" ]`, which returns `sh -C /nix/store/config`.

### Approved authentication-policy amendment

Pinned nixpkgs `nixos/modules/programs/shadow.nix:250–258` sets native login PAM `allowNullPassword=true`.
B already has this effective value.
Native greetd delegates auth/password to login, so the initial C login auth included `pam_unix.so ... nullok`.
The no-empty-password assertion rejected this, as intended.
No evidence says any account currently has an empty password; the issue is the declared authentication boundary.

The user selected “Disable empty passwords (Recommended)” after the console-login impact was explained.
`security.pam.services.login.allowNullPassword = lib.mkForce false` implements that approved exception to console-authentication preservation.
Native `shadow.nix:253–258` assigns true at normal priority, so a plain false would conflict.
Normal native password authentication remains enabled; no authentication wrapper is added.
The continuation reproduced assertion RED at `1ae00cf6c2f2b683dbcc9d8ddb39eb7589e59d99`: exit 1 in `logs/pyrite-dankgreeter-pam-red-20260910.log` with its `.exit` receipt.
The corrected candidate passes all 11 desktop assertions and all system assertions, including Unix auth enabled and no `nullok` on authentication rules.
Native password-management rules retain their existing `nullok` parameter; the approval changes authentication, not password-management policy.
An initially overbroad text assertion also rejected that unchanged password-management rule; it was narrowed to authentication lines, with no further PAM configuration changes.

### Continuation verification

All final evaluation results below identify built source `468fc7b1ff4f87be0ab5b54cc78423369118b861`.
The ignored evaluator files and complete logs remain available locally.

| Gate | Result | Evidence |
|---|---|---|
| Merged assertions and toplevel derivation | Exit 0; all 11 desktop assertions and all system assertions true | `logs/pyrite-dankgreeter-green-3-20260910.log` and `.exit`; command in `logs/pyrite-dankgreeter-local-verify-20260910.sh` |
| B preservation | Exit 0; all 18 interface groups equivalent, with only auth-line `nullok` normalized for the approved exception | `logs/pyrite-dankgreeter-preservation-final-20260910.log` and `.exit`; evaluator `logs/pyrite-dankgreeter-preservation.nix` |
| Negative controls | Exit 0; nine incorrect variants rejected | `logs/pyrite-dankgreeter-mutations-3-20260910.log` and `.exit`; evaluator `logs/pyrite-dankgreeter-mutations.nix` |
| Static candidate checks | Strict OpenSpec, nixfmt, whitespace, signature and scoped gitleaks checks passed | `logs/pyrite-dankgreeter-static-2-20260910.log` |
| Private transfer | Fresh non-force ref resolves to the exact built SHA and B parent; remote HEAD/dirty paths unchanged | `logs/pyrite-dankgreeter-private-transfer-20260910.log` |
| Linux builds and runtime comparison | All three Nix exits, build sequence, log tee, snapshot and state comparison exits 0 | `logs/pyrite-dankgreeter-build-468fc7b1ff4f-20260910/` |

The negative controls cover empty-password auth, disabled Unix auth, wrong PAM service, initial session, non-native greeter package, power-key handling, missing support service, idle suspend and globally scoped DMS ownership.
Preservation covers boot/kernel/initrd/LUKS, filesystems/swap, SSH/network, hardware/fan settings, suspend guards, logind/sleep/dconf, rendered user niri, DMS settings/unit, lock PAM, normalized login PAM, portals and support-service enablement.
The initial preservation harness forced removed or unset NixOS aliases; those harness failures and the malformed-SHA invocation remain in earlier numbered logs rather than being counted as product failures.

### Native Linux build outputs

The dedicated transient user unit was `pyrite-dankgreeter-build-468fc7b1ff4f.service`, invocation `61360a0dfd294c68a374a51ee75313e2`.
Its script, exact commands, complete build output, per-target JSON/exit receipts and before/after snapshots were copied to `logs/pyrite-dankgreeter-build-468fc7b1ff4f-20260910/`.
It used one local job/two cores, no offloading, no-link and the flags above, with an immutable `git+file` URL containing both ref and revision.

| Target | Output | Execution evidence |
|---|---|---|
| `checks.x86_64-linux.pyrite-dankgreeter-config` | `/nix/store/74bp0x9j2zmz0yzaahvckphb6adi2i7h-pyrite-dankgreeter-config` | Fresh build; native niri reports “config is valid”; launcher/native-package path and asset checks pass |
| `nixosConfigurations.pyrite.config.home-manager.users.cameron.xdg.configFile.niri-config.source` | `/nix/store/9vaxxjhbbirw7rkn28lf4x7q039iknyp-config.kdl` | Already cached; no fresh validator execution claimed for this target |
| `nixosConfigurations.pyrite.config.system.build.toplevel` | `/nix/store/bxya2rgbrh32n5qciqh3v8kbkldvm9qj-nixos-system-pyrite-26.11.20260804.85f6261` | Fresh system build completed at `2026-09-10T23:13:40+00:00`; dependencies mixed cached/fresh |

### Runtime and checkout preservation

Preflight found load `0.00`, 11 GiB available memory and 390 GiB available store disk; no push-deployment hook was present.
The exact before/after snapshot comparison exited 0.
Current and booted system remain `/nix/store/pgww7gi7jxb3ibdbfa2mphb2azid0znx-nixos-system-pyrite-26.11.20260804.85f6261`, boot ID `cd0fe5e2-132c-49af-8ea0-d338f1eff9fb`.
GDM remained active with PID 1560/invocation `07e8c9b7a4084e6c9d4393b175c754c2`; SSH remained active with PID 1174/invocation `db0b844181144d7e82af688f050057fc`.
Greeter session `c1`, leader 1567, and the captured gdm-greeter process identities remained unchanged; greetd, niri and DMS remained inactive.
Remote HEAD remained detached at `5c48c2d7eca397484ba2f0f640a333cc12e4e0d1` with the same seven dirty `.atomic` paths.
Git's native `hash-object --stdin` recorded identical unstaged binary-diff hash `4f9305ef4c57cf09eb1e5b7ee9eb567b156f22c8` and staged-diff hash `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391`; no `sha256sum` wrapper was used.
The B built closure remains present; no logs/cache were removed.

## 6. Artifact routing

Only the two authorized Nix files and this directory are in C.
Shared wip `osurqvnxwxruvlyzuvrqoknknunrzvxp` and join `ulrosuppkwlrmpszvkzpknnvmxmrtwxo` remain the same changes with preserved descriptions.
B remains unchanged.
No workflow, nested agent, worktree or controller repair was used.
The historical metadata-only revision was compared to the built source outside this OpenSpec directory in `logs/pyrite-dankgreeter-final-gates-20260910.log`.
That Nix-blob comparison did not establish an identical toplevel; neither it nor the historical build discharges the final repaired-source build obligation.

## 7. Deferred acceptance

Only authorized private Git transfer, build/cache writes and read-only inspection occurred remotely.
No activation, switch, bootloader installation, service/session restart, login/logout, reboot or suspend occurred.
Build generation of activation scripts did not execute them.
Physical login/logout, greeter return, rendering/input, password/lid locking, keyring unlock, live ownership, polkit and portal transactions remain unobserved.

## 8. Designation and discharge assessment

The delta requirements concern machine-side configuration interfaces, not hidden world state.
This non-blocking agent assessment is not performed by OpenSpec validation.
The existing world-assumptions corpus is not amended.
Historical assertions and Linux build receipts did not detect F1–F3; local repair assertions and negative controls now cover those configuration defects, while physical intent remains unverified.

## 9. Independent review repair

The ignored local review `logs/pyrite-dankgreeter-independent-review.md` required changes against `26c8ad0db83359176077916932c6b1f7b447acde`.
The repair worker verified the pinned sources and merged configuration before editing; no remote operation or PAM session experiment was performed.
Source excerpts are retained in `logs/pyrite-dankgreeter-repair-sources-20260910.log`, `logs/pyrite-dankgreeter-repair-greetd-source-20260910.log` and `logs/pyrite-dankgreeter-repair-loginuid-source-20260910.log`.
All Git source inspection used `GIT_NO_LAZY_FETCH=1`; no upstream ref was changed.

F1: native greeter PAM had `startSession=false`, its systemd session rule was disabled, and seatd was disabled.
Setting `startSession=true` enables native `pam_systemd.so` with `optional` control and, through the native `setLoginUid` default at pinned `pam.nix:902`, native `pam_loginuid.so`.
The updated guard requires the enabled native systemd module/control; actual seat acquisition remains unobserved.

F2: null `configHome` and empty `configFiles` did not suppress the native root synchronization hook.
Design D5 disables only that hook for this intentionally unsynchronized setup, preserving native user/home/tmpfiles creation and greetd privilege separation.
Merged `preStart` is empty and `serviceConfig` has no `ExecStartPre`; the comparison preserves all other greetd service configuration.
This does not make native synchronization safe to enable later; detailed security findings remain in ignored local logs.

F3: substituting `pam_permit.so` for the login deny rule passed the old named guard and all system assertions.
The guard now checks the exact native `pam_deny.so` path and rejects that mutation.
The repair leaves authenticated-user login/greetd PAM text unchanged, including approved empty-password rejection and legitimate password-management `nullok`.

The immutable repaired Nix source evaluated here is `f4e8346e3c3290975d4baef8e4da36a4fa0aee8d`.
The final handoff supplies the later revision carrying this evidence and its fresh local evaluation receipts; no build of either repair revision is claimed.

| Gate | Observed result | Evidence |
|---|---|---|
| F1/F2/F3 RED | Each assertion exits 1 against pre-review C | `logs/pyrite-dankgreeter-repair-red-{F1,F2,F3}-20260910.log` and `.exit`; runner `logs/pyrite-dankgreeter-repair-red.sh` |
| Merged diagnostic | Exit 0; all three missing-guard predicates false, permit mutant accepted | `logs/pyrite-dankgreeter-repair-inspect-2-20260910.log` |
| Repaired assertions | Exit 0; all 11 desktop and all system assertions true; toplevel derivation evaluated, not built | `logs/pyrite-dankgreeter-repair-source-3-green-20260910.log` and `.exit` |
| Preservation | Exit 0; all 18 B groups and five C comparisons true | `logs/pyrite-dankgreeter-repair-source-3-preservation-20260910.log` and `.exit` |
| Negative controls | Exit 0; all original nine plus three new variants rejected | `logs/pyrite-dankgreeter-repair-source-3-mutations-20260910.log` and `.exit` |
| Repaired boundary probe | Exit 0; F1/F2/F3 true, native session modules rendered, hook absent, permit mutant fails all-system guard | `logs/pyrite-dankgreeter-repair-source-3-probes-20260910.log` and `.exit` |
| Source static gates | Exit 0; nixfmt, strict OpenSpec, whitespace, signature and scoped gitleaks | `logs/pyrite-dankgreeter-repair-source-static-20260910.log` |

The successful runner command was `bash logs/pyrite-dankgreeter-repair-verify.sh f4e8346e3c3290975d4baef8e4da36a4fa0aee8d source-3`.
It runs `nix eval --json --file <evaluator> --apply <candidate-and-assertions>` with the restricted daemon/no-builders/one-job/two-core/no-lock-write flags above and captures complete output through `tee` with `pipefail` and per-command exit receipts.
The preservation evaluator is `logs/pyrite-dankgreeter-repair-preservation.nix`; it reuses `logs/pyrite-dankgreeter-preservation.nix` for B and compares enabled PAM rules, other greetd service fields, native greeter setup and authenticated-user PAM against pre-review C.
The mutation evaluator remains `logs/pyrite-dankgreeter-mutations.nix`; restoring the old native hook occurs only in local module evaluation, never by executing it.

Failed diagnostic attempts remain recorded: the first inspection queried an invalid nested options path; the first preservation comparison forced disabled PAM rules referencing the removed `kanidm` alias; the second omitted native `pam_loginuid` from its expected session additions.
The corrected comparison includes precisely the two native session rules and the removed sync hook; it does not claim greeter PAM or preStart is unchanged.
Nix emitted detached-HEAD fallback and existing stdenv deprecation warnings; these runs were not warning-free.

Independent re-review and the parent's exact-final B/C build lane are pending.
Final build receipts belong in ignored external evidence after source freeze; do not create another documentation-only revision after those builds.

## Overall decision

Return repaired C for independent re-review and exact-final builds; keep mutable-state inspection and physical acceptance pending.
Do not activate or archive this candidate.
