# Verification report

Change: `pyrite-dms-session`.
Verifier: directly supervised implementation worker, GPT-6 Astra, 2026-09-10.
This report records local preparation and the separately authorized pyrite build; physical acceptance remains pending.

## 1. Structural validation

`openspec validate pyrite-dms-session --strict` passed.
`openspec validate --all --json` exited 0; complete output is retained in `logs/pyrite-dms-openspec-all-20260910.log`.
These commands check document structure and delta form, not the satisfaction argument.

## 2. Task completion

Ten of fourteen tasks are complete.
Task 3.2 passed on pyrite: the native niri validator executed while building the generated configuration.
Task 4.1 passed independent source review of `b23e8a077956a75f3d25ec99558339a169384e6e`; the review found no evidence-backed findings (`logs/pyrite-dms-independent-review.md`).
Tasks 4.2–4.5 remain pending state inspection and physical acceptance, with no deployment authorization implied.
Archive is not authorized.

## 3. Delta spec sync state

`machine-interface` has four added requirements in this change; they are not synced to the living corpus.
No corpus or archive files were edited.
Linear binding remains explicitly deferred.

## 4. Design and specification coherence

Design D1 maps to native-package/input assertions and the small upstream HM adapter.
Design D2 maps to the niri-only unit relationships, absence of separate services/startup commands, and native portal/polkit assertions.
Design D3 maps to widget/binding, native PAM and idle-policy assertions.
Design D4 maps to immutable-revision evaluation and the attempted native validator build.
No greeter module, lifecycle daemon, theme, plugin or extra integration was added.
The pre-existing cursor-theme and X11-satellite limitations remain; runtime portal transactions remain unobserved.

## 5. Implementation and executable evidence

Tested code revision: `40bce3be9c086eddd6a30c605c7a348244fa5597`, one delivery commit after base `1c31c2ab6e827758303b58875daddd8d10a704f7`.
Delivery change: `ykwqwuvuqolqsopsspypmuxspsxvmxmo`; bookmark: `pyrite-dms-prepared`.
Subsequent edits to this ledger/tasks do not alter the six Nix paths; the final handoff checks that equality and supplies the final immutable ref.
The shared working-copy change and its full description are preserved; unrelated pending edits remain outside this delivery.
The original local checks below preceded the private transfer documented in section 9; nothing was published to GitHub.

For the commands below, `candidate` is the tested Git SHA above and `flake` is `git+file:///Users/crs58/projects/vanixiets?rev=$candidate`.
Every eval/build used these flags:

```sh
--store daemon --builders '' --max-jobs 1 --cores 2 \
  --option accept-flake-config false --no-write-lock-file --no-update-lock-file
```

| Check | Command or precise assertion | Result | Full log under repository root |
|---|---|---|---|
| Baseline RED | `nix eval "$base#nixosConfigurations.pyrite.config" --apply 'c: assert (c.home-manager.users.cameron.programs.dank-material-shell.enable or false); true' --json` | Exit 1, expected missing-DMS assertion | `logs/pyrite-dms-red-20260910.log` |
| Input lock | `nix flake lock --update-input dms-src` with the same builder/store limits, allowing this one lock write | Exit 0; one HTTP-429 retry, only new DMS node/root edge added | `logs/pyrite-dms-lock-20260910.log` |
| Lock preservation | Semantic comparison of all existing nodes/root input edges against the base | Passed; niri pin unchanged | `logs/pyrite-dms-static-20260910.log` |
| Desktop and system assertions | `nix eval --json --file logs/pyrite-dms-evaluate.nix --apply 'f: f { candidate = "40bce3be9c086eddd6a30c605c7a348244fa5597"; }'` | Exit 0; nine desktop assertions and all NixOS assertions true | `logs/pyrite-dms-evaluate-5-20260910.log` |
| Baseline preservation | Same invocation using `logs/pyrite-dms-preservation.nix` | Exit 0; all 15 original binds and selected policy unchanged | `logs/pyrite-dms-preservation-5-20260910.log` |
| Mutation checks | Same invocation using `logs/pyrite-dms-mutations.nix` | Exit 0; wrong validator, global service target and AC suspend 900 each rejected by the intended assertion | `logs/pyrite-dms-mutations-20260910.log` |
| Generated artifacts | Same invocation using `logs/pyrite-dms-artifacts.nix` | Exit 0; generated KDL, PAM, settings, package paths; no HM autostart entries | `logs/pyrite-dms-artifacts-20260910.log` |
| Native niri validation | `nix build --no-link "$flake#nixosConfigurations.pyrite.config.home-manager.users.cameron.xdg.configFile.niri-config.source"` | Exit 1, platform mismatch; validator NOT-RUN | `logs/pyrite-dms-build-niri-20260910.log` |
| Native DMS realization | `nix build --no-link "$flake#nixosConfigurations.pyrite.config.home-manager.users.cameron.programs.dank-material-shell.package"` | Exit 0, cache substitution rather than local compilation | `logs/pyrite-dms-build-dms-20260910.log` |
| Format | `nixfmt --check` on the five owned `.nix` files | Exit 0 | `logs/pyrite-dms-static-20260910.log` |
| Secrets and whitespace | `gitleaks git --redact --log-opts="$base..$candidate" .`; `git diff --check "$base" "$candidate"` | Both exit 0; one commit scanned, no leaks | `logs/pyrite-dms-integrity-20260910.log` |
| Signature and local capability | `git verify-commit "$candidate"`; limited `nix config show --json` | Both exit 0; valid SSH signature; builders empty, local platform aarch64-darwin | `logs/pyrite-dms-capability-20260910.log` |

The preserved policy comparison includes logind, sleep settings, both d3cold guards and their unit relationships/executables, lid-wake unit, kernel parameters, SSH settings, GNOME dconf, niri power-key handling, default session and autologin.
It does not claim remote runtime state.

The installed, native and validator niri paths are identical: `/nix/store/y32xfvyx99qp91s2g3d2dr8wsx7k3gb0-niri-26.04`.
The actual config derivation is `/nix/store/6f3srzvnm8nsqyy5gfiwkbl2ii9rlpd1-config.kdl.drv` and contains `niri validate -c $configPath` with that niri as its build input.
`file` identifies the binary as x86-64 Linux; derivation inspection does not count as executing it (`logs/pyrite-dms-validator-derivation-20260910.log`).
DMS resolves to `/nix/store/4pywbp96xnfzykjhghwwb92n75wkb2m4-dms-shell-1.5.3`, and native Quickshell to `/nix/store/w3s69yqqgy1c4s82czlv3ygrc2j1jwwh-quickshell-0.3.0`.

Initial probe errors are retained in `logs/pyrite-dms-eval-{1,2,3,4}-20260910.log` and `logs/pyrite-dms-diagnose-20260910.log`.
Filtering every assertion's message forced an unrelated lazy nixpkgs filesystem error message; the corrected probe evaluates assertions and reads only this module's literal messages.
A file-function invocation initially lacked explicit application.
Two initial test expectations used pre-coercion representations: HM coerces ExecStart to a list and dconf serializes its values.
The assertions were corrected against the observed merged representations; no service or GNOME policy was changed to make them pass.

## 6. Artifact routing

All artifacts created by this change are in the CLI-created `openspec/changes/pyrite-dms-session/` directory.
No design output was created under `docs/superpowers/`.
The operator's directly supervised worker/shared jj join instructions explicitly replace the schema's nested-executor/worktree ceremony for this task.

## 7. Deferred physical coverage

| Pending task | Evaluation coverage | Missing observation |
|---|---|---|
| 4.1 Independent review (complete) | Source review of `b23e8a077956a75f3d25ec99558339a169384e6e`, no findings | Physical acceptance is separate |
| 4.2 Existing DMS state | Declared settings only | Legacy session migration and current settings inspection before activation |
| 4.3 Shell/login/input/performance | Widgets, binds and session registration | Actual rendering, input, login/logout, fallback and responsiveness |
| 4.4 Lock/unlock | Native password PAM, logind wiring and timers | Successful physical authentication and locking |
| 4.5 Runtime ownership/portals | Unit graph, package paths and portal routing | Complete active-session ownership snapshot and real FileChooser/ScreenCast transactions |

These are real gaps, not equivalent automated coverage.
No suspend experiment is authorized; CAM-59 is unchanged.
CAM-66 remains the explicit unrepaired exception: any later authorized display-manager restart requires the affected user's niri.service inactive first.

## 8. Designation and discharge assessment

This agent-executed assessment is non-blocking and is not performed by OpenSpec validation.
All four delta requirements are explicitly interface-stratum: they concern configuration, package paths, unit relationships, IPC arguments, PAM and observed session-selection interfaces.
No new world vocabulary or world-assumption table amendment is claimed.
The existing user-visible motivation is not discharged by declaring these interfaces alone.

| Requirement | Configuration evidence | Remaining assumption or gap |
|---|---|---|
| Native packages and one niri-scoped service | Identity, ownership, portal and support assertions pass; native validator executed successfully on pyrite | Live bus/process ownership remains unverified |
| Required controls and shortcuts | Widget and typed-bind assertions pass; original binds unchanged | Physical rendering/input and upstream IPC behavior pending |
| Lock without idle suspend | Password PAM and timeouts pass; baseline power policy unchanged | Upstream behavior, existing mutable state and physical authentication pending |
| Preserve GNOME/GDM | Session/idle assertions and baseline comparison pass | No new physical session-cycle observation; CAM-66 exception retained |

## 9. Authorized pyrite build and cache warming

On 2026-09-10 the user authorized private transfer and builds on pyrite, not activation.
The exact independently reviewed Git revision `b23e8a077956a75f3d25ec99558339a169384e6e` was pushed without force to `pyrite.zt:projects/vanixiets`, under `refs/heads/pyrite-dms-build-b23e8a077956`.
The receiver had no active receive hooks in the inspected hook directory; its detached HEAD and working files were not checked out or moved.
Remote ref/object identity was verified before building (`logs/pyrite-dms-private-transfer-20260910.log`).

For all three sequential commands, `flake` was `git+file:///home/cameron/projects/vanixiets?ref=refs/heads/pyrite-dms-build-b23e8a077956&rev=b23e8a077956a75f3d25ec99558339a169384e6e`.
Nix 2.34.8 ran on pyrite with these flags, without remote builders or lock writes:

```sh
nix build --store daemon --builders '' --max-jobs 1 --cores 2 \
  --no-write-lock-file --no-update-lock-file --option accept-flake-config false \
  --no-link --print-build-logs --json "$flake#$attribute"
```

| Attribute after `nixosConfigurations.pyrite.config.` | Result | Output |
|---|---|---|
| `home-manager.users.cameron.xdg.configFile.niri-config.source` | Exit 0; locally built, native validator reported `config is valid` at 22:27:59 UTC | `/nix/store/9vaxxjhbbirw7rkn28lf4x7q039iknyp-config.kdl` |
| `home-manager.users.cameron.programs.dank-material-shell.package` | Exit 0; substituted during the niri dependency realization, not compiled or launched | `/nix/store/4pywbp96xnfzykjhghwwb92n75wkb2m4-dms-shell-1.5.3` |
| `system.build.toplevel` | Exit 0; built with cached dependencies, not activated | `/nix/store/dfydvmxbybr6kian1hclygfwysdivwgv-nixos-system-pyrite-26.11.20260804.85f6261` |

The corresponding derivations are `/nix/store/6f3srzvnm8nsqyy5gfiwkbl2ii9rlpd1-config.kdl.drv`, `/nix/store/lnz2jiykv9824b39lj7ilcvgx8w9bimg-dms-shell-1.5.3.drv` and `/nix/store/3rw2w0zg2s4ikyrlin075pidi67bby5z-nixos-system-pyrite-26.11.20260804.85f6261.drv`.
Derivation inspection confirms `niri validate -c $configPath` with the candidate's native `/nix/store/y32xfvyx99qp91s2g3d2dr8wsx7k3gb0-niri-26.04` build input.
The daemon's validator execution log is retained in `logs/pyrite-dms-remote-validator-20260910.log`; the JSON derivation and checked summary are in `logs/pyrite-dms-remote-validator-{derivation,summary}-20260910.{json,log}` respectively.

The SSH-disconnect-safe transient user unit was `pyrite-dms-build-b23e8a077956-20260910.service`, launch PID `12264`, invocation `d29084d2a3cf46b3b6629e3b2b70e9a6`.
It ran from 22:27:02 to 22:29:22 UTC and finished with `ExecMainStatus=0`, `Result=success`, no running main process.
Each Nix command and its stdout tee exited 0; the sequence and full-log tee also exited 0.
Complete logs, exact script, per-target JSON/exit receipts and before/after snapshots remain in `/home/cameron/projects/vanixiets/logs/pyrite-dms-build-b23e8a077956-20260910/` on pyrite, copied locally to `logs/pyrite-dms-build-b23e8a077956-20260910/`.
The unit journal is retained locally in `logs/pyrite-dms-remote-unit-journal-20260910.log`.
Observed available memory remained at least 9.4 GiB in bounded samples, with no swap used; the cooperative core setting is not a hard CPU limit.

Before/after snapshots compare equal (`state_comparison_exit=0`): `/run/current-system` and `/run/booted-system` both remain `/nix/store/pgww7gi7jxb3ibdbfa2mphb2azid0znx-nixos-system-pyrite-26.11.20260804.85f6261`, and boot ID remains `cd0fe5e2-132c-49af-8ea0-d338f1eff9fb`.
Display-manager PID `1560`/invocation `07e8c9b7a4084e6c9d4393b175c754c2`, sshd PID `1174`/invocation `db0b844181144d7e82af688f050057fc`, and GDM greeter session `c1`/leader `1567` are unchanged.
The niri and DMS services and graphical-session target remain inactive.
The remote detached HEAD remains `5c48c2d7eca397484ba2f0f640a333cc12e4e0d1`, with the same seven dirty `.atomic` paths.
Optional dirty-diff hash probes failed because the remote `sha256sum` wrapper requires a filename; the journal records this, and the snapshots do not establish bytewise equality of those dirty files.
No activation, boot installation, reboot, suspend, logout, existing-service restart or DMS/GNOME process control was performed.

Only this verification ledger and tasks are updated after the build.
The final handoff verifies all six Nix/lock blobs against the remotely built revision; it does not claim that the resulting metadata-only Git revision was built.

## Overall decision

Native validation, system preparation and independent source review have passed.
Activation and archive remain on hold for tasks 4.2–4.5; no physical acceptance is claimed.
