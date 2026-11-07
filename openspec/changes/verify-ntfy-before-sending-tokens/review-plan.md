# Plan review

This review answers task 1.1's four questions over `brainstorm.md`, `design.md`, `tasks.md`, `plan.md`, `plan/` and `specs/`, against the repository on disk and read-only evaluations of it.
It also lists every regulator of groups 2 to 5 with its two value sources, and judges the import of task 2.4 and the security trade-off of keeping caddy's root key as clan vars.
Evidence logs are under `logs/cam87-evidence/1.1-*.log`.

## Severity summary

| Severity | Count | Findings |
|---|---|---|
| High | 3 | F1, F2, F3 |
| Medium | 4 | F4, F5, F6, F7 |
| Low | 5 | F8, F9, F10, F11, F12 |
| Info | 2 | F13, F14 |

The three high findings each falsify a stated guarantee or a planned green step: F1 the claim that the key is never written to a local file, F2 the claim that a rotation loses no post, and F3 the green expectation of the client scan.

## Findings

| Code | Severity | Question | Finding | Evidence | Recommendation |
|---|---|---|---|---|---|
| F1 | High | Critical oversight | The import writes caddy's root key in plaintext to a local file on stibnite. `clan vars set` reaches `encrypt_file`, which writes the value to a `NamedTemporaryFile` in `/dev/shm` and, when that is missing, in the default temporary directory, then runs `sops encrypt --in-place` on it and unlinks it afterwards. stibnite has no `/dev/shm`, and its `TMPDIR` is under `/var/folders`, on disk. This contradicts design D10 and D12 ("nothing writes the key to a local file"), plan Global Constraints, and the FAI scenario `The vars are imported` ("no key is printed or written to a local file"). | `clan-core@dbae2101:pkgs/clan-cli/clan_cli/secrets/sops.py:527-555`, `:283`; `ls -ld /dev/shm` on stibnite: no such file; `TMPDIR=/var/folders/…/T/`; `tmutil listlocalsnapshots /` listed none. | Either run the two `clan vars set` commands with `TMPDIR` on a RAM disk created for the step and detached after it, or restate the guarantee as a transient `0600` file in the operator's temporary directory that clan unlinks; the operator decides, and D12, plan Task 2 Step 4 and the FAI scenario follow the decision. |
| F2 | High | Critical oversight | Rotation step 3 to step 5 (design D7) can refuse every post. caddy's leaf for `ntfy.zt` lives 12 hours and is stored with the intermediate that signed it, so after step 3 caddy keeps serving a chain to the old root until the leaf renews. Step 4's `caddy-root-check` verifies against the two-root bundle, so it passes whether or not the switch happened. A step 5 that removes the old root before the leaf renews makes every client refuse `ntfy.zt`. | `caddyserver/caddy@v2.11.7:modules/caddytls/internalissuer.go:200` (`defaultInternalCertLifetime = 12 * time.Hour`); `modules/caddypki/ca.go:345-375` (stored intermediate loaded without checking its signer). That certmagic serves the stored leaf until its renewal window is an inference from its storage model, not read from source. | Step 3 also moves caddy's stored leaf certificates for the `tls internal` names out of storage, or step 4 verifies the served chain with `-CAfile` naming the new root alone, and step 5 starts only after that verifies. Add the condition to the FA scenario `The old root is removed too early`. |
| F3 | High | Critical oversight | The scan's clause C fails at the green of 4.5 and 4.7, because three files name `ntfy.zt`, match the `invokes` pattern and are in no list. `modules/vm-tests/caddy-root-from-vars.nix`, added in pull request 1, names `ntfy.zt` and runs curl. `modules/lib/observability-notify-run.nix` gains both words from 4.6's new sentence. `modules/home/tools/hooks/default.nix` names `ntfy.zt` and lists `curl` in two `runtimeInputs` today, so the red expectation of 4.4, which names only the two hook scripts, is incomplete. | `rg` over `modules/` and `pkgs/` for files naming `ntfy.zt` that also match `invokes`: the three hook files, `zt-dns.nix`, `fleet-alert.nix` and the three `ntfy-send` files; `modules/home/tools/hooks/default.nix:18`, `:82`, `:171`; plan Task 2 Step 1 (VM test text); plan Task 4 Step 6 (new sentence). | Declare the VM test a non-client (its curl verifies with `--cacert` against a test root inside a VM), and declare `observability-notify-run.nix` a non-client or word 4.6's sentence without `ntfy.zt`. Add `default.nix` to 4.4's expected clause C lines. |
| F4 | Medium | Check that cannot fail as written | The mutant `verificationSkipped` does not skip verification. Its `sed` sets `verified=0`, the value the line already has, and removing `-verify_return_error` leaves the `grep` for `Verify return code: 0 (ok)` in place. The mutant still fails `servedDrifted` with `does not verify`, so the leg passes and the check prints `FAIL: mutant verificationSkipped passed`, and 5.2's green expectation fails. | plan Task 5 Step 1 (`sed -e 's/ -verify_return_error//' -e 's/^verified=.*/verified=0/'`); Step 2 (`verified=0`, then `grep -q … && verified=1`). | Make the mutant accept, for example `s/^verified=0/verified=1/`, and keep it run only on `servedDrifted`. |
| F5 | Medium | Property nothing covers | The gate's search in plan Task 1 Step 2 is `A7[89] |A8[0-2] ` and its fallback says "no A78-A82", while `tasks.md` 1.2 searches `A8[0-3]` and the change adds A83. As written in the plan, a corpus already holding A83 passes the gate. | `plan/task-1.md` Step 2; `tasks.md` 1.2; `specs/world-assumptions/spec.md:298`. | Use `A8[0-3]` and "no A78-A83" in the plan. |
| F6 | Medium | Clause that over-claims | FA `The service authority's expiry reaches a person 180 days ahead` says a failure notice "naming its expiry" reaches a person. The notifier posts `FAILED <unit> on <host>`, which names the unit, not the expiry; the expiry is only in cinnabar's journal. Nothing discharges "naming its expiry". | `modules/lib/observability-notify-run.nix:59`; `specs/fleet-alerting/spec.md:24-38`. | Reword the requirement to a notice naming `caddy-root-check`, with the expiry in the unit's journal, or extend the notifier, which this change does not otherwise touch. |
| F7 | Medium | Property nothing covers; check that cannot fail | FAI `ntfy-send verifies ntfy.zt against caddy's root and fails closed` requires a non-zero exit before curl runs when `NTFY_CACERT` is unset or empty. `caUnset` tests only unset, and under `set -u` the expansion `"$NTFY_CACERT"` already fails an unset variable, so the case passes with the `:?` guard removed. The empty case, which only the guard handles, has no test, and "before curl runs" is not observed, because the case runs the real curl and only checks that nothing was received. | plan Task 4 Step 1 (`caUnset`); Step 3 (`set -euo pipefail`, `: "${NTFY_CACERT:?…}"`); `pkgs/by-name/ntfy-send/test-token-transport.nix:59-62`, whose stub already detects "curl ran". | Add `caUnset` and `caEmpty` cases to `token-transport`, asserting a non-zero exit and no recorded argv, and add a mutant without the guard that runs only `caEmpty`. |
| F8 | Low | Clause restating the line it judges | The clause `configured root` compares caddy's adapted root paths with `cfg.certFile` and `cfg.keyFile`, the same options the module renders the `pki` block from. The FAI scenario says the adapter names "the generator's `root.crt` and `root.key` paths", but nothing compares the options with the generator's paths. A cinnabar edit pointing `certFile` at another file whose first certificate has the recorded fingerprint passes both clauses. caddy's adapter is an independent reader, and `pkiDropped` shows the clause can fail, so the gap is narrow. | plan Task 2 Step 2 (check text); design D11 table; `specs/fleet-alerting-interface/spec.md` scenario `caddy's adapter reads the configured root`. | Either give the check its expected paths from cinnabar's generator, or reword the scenario to "the configured `certFile` and `keyFile`". |
| F9 | Low | Oversight in plan text | `services.caddy.configFile` on cinnabar evaluates to the file `…-Caddyfile-formatted/Caddyfile`, so the plan's `${caddy.configFile}/Caddyfile` names a path that does not exist. cinnabar's `services.caddy.globalConfig` evaluates to `log { level ERROR }`, so plan Task 2 Step 5's statement that the global block "holds only the pki option" is false, and `pkiDropped = mkForce ""` drops the log setting as well. | `logs/cam87-evidence/1.1-caddy-configfile-*.log`; `nix eval --json .#nixosConfigurations.cinnabar.config.services.caddy.globalConfig` printed `"\n\n\n\nlog {\n  level ERROR\n\n}\n"`. | Read `${caddy.configFile}` directly, and make `pkiDropped` remove only the `pki` block. |
| F10 | Low | Check that cannot fail | In 7.1, "`cam87 foreign` is absent from `fleet-acceptance` 60 s later" cannot fail: the post goes to magnetite's ingress, which never forwards to ntfy, with or without `-k`. The observation that discriminates is `rc=60`, peer verification failure. The FAI scenario's "the ingress receives no request" is read by no step. | plan Task 7 Step 1; `specs/fleet-alerting-interface/spec.md` scenario `A deployed host is pointed at another server`. | Keep `rc=60` as the clause, and either drop the absence claim and the "receives no request" wording or read the ingress's log for the attempt. |
| F11 | Low | Import procedure | The import's expected readers are "cinnabar and the sops users", without saying which users. clan's `encrypt_secret` adds the machine, the machine's default groups and the running admin's user entry. `sops/users/` holds five users, and `cameron` and `crs58` share one age key. | `clan-core@dbae2101:pkgs/clan-cli/clan_cli/secrets/secrets.py:170-235`; `clan_lib/vars/secret_modules/sops.py:183-214`; `ls sops/users`: `cameron`, `christophersmith`, `crs58`, `janettesmith`, `raquel`; both `cameron` and `crs58` hold `age1vn8fpkmkzkjttcuc…`; `otel-cert/key.pem` readers: `machines/cinnabar`, `users/cameron`. | State the expected readers exactly: `machines/cinnabar` and one of `users/cameron` or `users/crs58`, the same age key. Any other entry stops the step. Record the same in A81. |
| F12 | Low | Consistency | (a) `tasks.md` 1.1 lists regulators of groups 2 and 3, while plan Task 1 Step 1 lists those of Tasks 2, 4 and 5. (b) `tasks.md` 9.3 places applied review findings in "a group §9", which collides with group 9, while plan Task 9 Step 3 says §11. (c) plan Task 4 Step 7 is headed "Pull request 1 (4.7)" but opens pull request 2. (d) `tasks.md` 4.2 sets `NTFY_CACERT` to "a path in its work directory", while plan Task 4 Step 2 sets `/ca`. (e) `tasks.md` 1.4 expects "HTTP 200", but the rehearsal command prints only curl's exit code. (f) plan Task 2 Step 2's VM build passes `--option builders` twice. | The cited lines. | Align each pair on one text: groups 2 to 5 for the inventory, §11, pull request 2, one `NTFY_CACERT` value, `-w '%{http_code}'` or "exit 0", and one `--option builders`. |
| F13 | Info | Cost against the invariant | Clause C matches `curl` anywhere in a file, comments included, so a prose mention beside `ntfy.zt` needs a non-client declaration (F3 shows three). Each declaration is cheap, and the false positive errs towards review. | plan Task 4 Step 4 (`invokes`, clause C). | Accept, or skip comment lines in clause C. Either way, record the choice in the check's header. |
| F14 | Info | Property nothing covers at runtime | On cinnabar, the stored root and the var are the same root and key, so 3.1's served-chain reads cannot show that caddy loads its root from the vars. Only the build-time check and the VM test do. | design D8 step 1; `tasks.md` 3.1; cinnabar's rendered Caddyfile (`/nix/store/fbja0vq70acmidihn4r6yqvrz3p63z9g-Caddyfile-formatted/Caddyfile`) has no `admin off`, and `services.caddy.enableReload` is `true`. | Add to 3.1 a read-only read of caddy's loaded configuration on cinnabar, for example `curl -s localhost:2019/config/apps/pki`, showing the vars' paths; caddy's default admin endpoint, `localhost:2019`, is not disabled there. |

## Checked and cleared

On stibnite, `openssl verify -CAfile` does not fall back to the system bundle, which nix-darwin builds with CR in it: verifying the served intermediate against `vars/shared/otel-ca/ca.crt/value` fails with error 20, with and without `-no-CApath -no-CAstore`, and against CR it prints `OK` (`logs/cam87-evidence/1.1-verify-default-paths-*.log`).
So 3.1's verification against RV from stibnite can fail.
cinnabar's caddy is 2.11.7 and both systems' `pkgs.curl` is 8.22.0, as the grounding states.
`ntfy-send.sh` keeps `-m 5` as the only `-m <digits>`, which R9.5 reads (`modules/nixos/fleet-alert.nix:625-634`).
The token test's argv mutant `-H @- "$@"` still applies to the new script.
caddy's configured root is loaded with `ca.Root.Load()` and its first certificate used, and the stored intermediate is loaded without checking its signer (`ca.go:150-175`, `:345-375`), as A79 states.
The A-numbers A78 to A83 collide with no other open change, which use A61 to A77.

## Regulators and their value sources

Each row names a regulator from groups 2 to 5 and the two values it relates, and says whether they are defined independently.

| Item | Regulator | Value 1 | Value 2 | Independent |
|---|---|---|---|---|
| 2.1 | VM `restored`: curl gets 200 | the root the test makes with `openssl` | the chain caddy serves | yes |
| 2.1 | VM `restored`: served chain verifies (`s_client -verify_return_error`) | the test root | the served intermediate | yes |
| 2.1 | VM `restored`: no `root.crt` in storage | the node's filesystem | A79's claim that a configured root is never written | yes |
| 2.1 | VM `minting` (negative control): curl exits 60 | the test root | the root caddy mints | yes |
| 2.1 | Red: VM test does not evaluate | the module attribute | its absence | evaluation only; the behavioural red is `minting` |
| 2.2 | `caddy-root-from-vars` clause `configured root` | caddy's adapter over the rendered Caddyfile | `cfg.certFile` and `cfg.keyFile` | partly: the options also feed the render (F8) |
| 2.2 | `caddy-root-from-vars` clause `recorded root` | the var's first certificate | the fingerprint read on cinnabar on 2026-11-06 | yes |
| 2.3 | `nix eval` of the generator's files | the declaration | the evaluated attributes | no: it restates the declaration, but the path check reads clan's computed path |
| 2.3 | `clan vars check` reports both files missing | the declaration | the vars tree | yes |
| 2.4 | Var fingerprint equals recorded and live | RV | the option value and the live `root.crt` | yes |
| 2.4 | Public-key hashes equal | the decrypted `root.key` | RV's public key | yes |
| 2.4 | Readers listed | `root.key/machines`, `users` | the expected readers | yes once F11 states them |
| 2.4 | No `PRIVATE KEY` in the log | the log | the key's PEM header | yes |
| 2.4 | `clan vars check` passes | the vars tree | the generator (A83) | yes |
| 2.5 | `pkiDropped` fails `configured root` | the override | the clause message | yes (F9 on its breadth) |
| 2.5 | `fingerprintOther` fails `recorded root` | `otel-ca`'s fingerprint | the var's | yes |
| 2.6 | `rg` finds no reader of CR | the tree | the old path | yes |
| 2.6 | Keychain certificate `cmp` RV | the first `-value` store path in stibnite's activation text | RV | yes; it takes the first `-value` path, not necessarily the keychain step's |
| 3.1 | Served intermediate verifies against RV, before and after | the live chain from cinnabar | RV | yes ("Checked and cleared") |
| 3.1 | `caddy` active; `root.key` `caddy 400` | the host | the declaration | yes |
| 3.1 | `/v1/health` with `--cacert` RV | the live server | RV | yes |
| 3.1 | Deploy records before and after; posts with causes | the host's record | the deploy made | yes |
| 4.1 | `foreignRefusedSource`, `foreignRefusedBuilt` | the CA file given to curl (RV) | the sandbox CA that signed the leaf | yes |
| 4.1 | `ownAccepted`, `bundleAccepted` | `other`, or RV followed by `other` | the sandbox CA | yes |
| 4.1 | `caUnset` | unset `NTFY_CACERT` | the exit status | no: `set -u` alone also fails it (F7) |
| 4.1 | `--help` assertions | the help text | the required strings | yes |
| 4.1 | Mutant `insecure`, only on `foreignRefusedSource` | `-k` | the sandbox CA | yes |
| 4.2 | Token test argv lists | the stub's recorded argv | the expected list | yes |
| 4.4 | Clause A, mutants `insecureShort`, `insecureCluster`, `insecureLong`, `insecureContinued` | the file's text | curl's option grammar | yes |
| 4.4 | Clause B, mutants `clientMissing`, `cacertDropped` | the declared list | the file | yes |
| 4.4 | Clause C, mutant `undeclaredClient` | the lists | the tree | yes (F3, F13) |
| 4.5 | Hook scripts show only the `ntfy-send` call | the built scripts | the pattern `curl\|ntfy-send` | yes |
| 5.1 | `servedHeld`, `servedInOverlap`, `servedDrifted` | the chain `s_server` presents | the bundle | yes |
| 5.1 | `rootExpiring` | the bundle's first root's `notAfter` | the build's clock | yes |
| 5.1 | Mutant `verificationSkipped`, only on `servedDrifted` | the edited script | `servedDrifted` | no as written (F4) |
| 5.1 | Mutant `expirySkipped`, only on `rootExpiring` | the edited script | `rootExpiring` | yes |
| 5.3 | `onFailure`, timer, `notifiedUnits`, magnetite's exclusion | the evaluated units | the host table | yes |
| 5.3 | Zone override fails | `OnCalendar` without a zone | `observability-notify.nix`'s assertion | yes |

## The import and the security trade-off

The import of task 2.4 keeps the key off argument lists and out of logs, compares fingerprints and public keys, and stops on a difference, which is sound apart from F1 and F11.
F1 means the key does touch a local file on stibnite, in clan's temporary file; F11 means the expected readers need stating so that a difference can be detected.
The trade-off in design "Risks / Trade-offs" is stated correctly for the recipients clan adds: cinnabar's age key and the running admin's key, which `cameron` and `crs58` share.
The other three sops users are not added by `clan vars set`, so the trade-off does not extend to them unless someone adds them later; A81 is the place to say so.

## F1: keeping the key off disk-backed paths

Option (a) runs task 2.4's two `clan vars set` commands with `TMPDIR` on a RAM disk created before them and destroyed after them.
Option (b) keeps the import as planned and restates the guarantee as a transient `0600` file in the operator's temporary directory, which clan unlinks.

Option (a) is sound, because the two writes that receive the key both follow `TMPDIR`:

- `encrypt_file` falls back to `NamedTemporaryFile(delete=False)` without a directory when `/dev/shm` is missing (`clan-core@dbae2101:pkgs/clan-cli/clan_cli/secrets/sops.py:527-530`), and Python's `tempfile` takes `TMPDIR` first.
- clan's interpreter, `python3.14` from the `clan` wrapper, honours it: with `TMPDIR` set to a fresh directory, `tempfile.gettempdir()` and a `NamedTemporaryFile` landed in that directory. The `clan` wrapper does not set `TMPDIR`, and `clan_lib` never overrides it for this path.
- sops 3.13.3 writes `encrypt --in-place` with `os.Create(fileName)` on the same path (`getsops/sops@v3.13.3:cmd/sops/main.go:894-895`), so the ciphertext overwrites the plaintext on the RAM disk. clan then copies the ciphertext into the vars tree and unlinks the RAM-disk file (`sops.py:549-555`).
- The only other temporary file, `sops_run`'s `--config` manifest, holds public keys only (`sops.py:250-268`). `clan vars get` decrypts to stdout, so the comparison step writes no file.
- clan's evaluation cache also moves under `TMPDIR` (`clan_lib/dirs/__init__.py:132`), which costs a cold evaluation and holds nothing secret.
- The key still exists in the memory of `ssh`, the pipe and clan, as it does under either option; macOS encrypts swap, so paging does not write it in clear.
  The guarantee concerns files, which (a) keeps.
- No local snapshot of `/` existed when checked, and a RAM disk is outside any snapshot.

Three details make (a) hold on macOS, and none of them has been exercised on stibnite:

- `diskutil erasevolume APFS cam87ram /dev/diskN`, after `hdiutil attach -nomount ram://<sectors>`, formats and mounts the device in one step; `newfs_apfs` alone leaves it unmounted.
- Volumes mounted under `/Volumes` ignore ownership by default, so `diskutil enableOwnership` precedes a `0700` directory that becomes `TMPDIR`.
- Spotlight can read a new volume's files into its index on the system disk, so `.metadata_never_index` is created at the volume's root before the import.

The check, logged with the import: `df "$TMPDIR"` names the RAM device; the `clan` interpreter's `tempfile.gettempdir()` prints the RAM-disk directory; the directory is empty after both commands; and `hdiutil detach` of the device succeeds at the end.
This shows where clan's temporary files went, which the code path above makes the only place the key was written; no check can show a deleted file was never written elsewhere.
Recommendation: (a). It keeps the guarantee as specified, costs four commands around the import, and (b) would weaken a stated property to save them.
Applied, design D12, plan Task 2 Step 4 and task 2.4 gain the RAM disk and the check, and the guarantee's wording is unchanged.

## Dispositions

The operator decided Q1 to Q5 and replaced Q6 on 2026-11-07 (`brainstorm.md` "Second round"), and on the same day accepted every finding as recommended, F1 as option (a).
Rows recommended `accept` apply the finding's own recommendation; the others say what changes.
The last column names where each row is applied; requirement names are those of `specs/`, and plan locations are the files under `plan/`.

| Row | Subject | Recommended | Reason | Operator's decision | Applied in |
|---|---|---|---|---|---|
| Q1 | Route the permission hooks through `ntfy-send` (D3) | accept | decided as recommended | accept (2026-11-07) | before this review: design D3; `tasks.md` 4.5; `task-4.md` Step 5 |
| Q2 | Weekly `caddy-root-check` on cinnabar (D6) | accept | decided as recommended, read with the served-chain check | accept (2026-11-07) | before this review: design D6; `tasks.md` 5.1 to 5.3; `task-5.md` |
| Q3 | Charter v30 and A78 to A83 for this change; CAM-81 moves to v31 | accept | decided as recommended | accept (2026-11-07) | before this review: design D9; `tasks.md` 1.2, 8.1; WA A78 to A83 |
| Q4 | Six hosts outside the window | accept | decided as recommended | accept (2026-11-07) | before this review: design D8; `tasks.md` 7.5; `task-7.md` Step 5 |
| Q5 | The scan covers `modules/` and `pkgs/`; the runbook is corrected by hand | accept | decided as recommended | accept (2026-11-07) | before this review: design D5, D9; `tasks.md` 4.4, 8.2 |
| Q6 | Defer caddy's root as clan vars | reject | superseded by O8 to O12 | reject (2026-11-07) | before this review: design D10 to D13 |
| F1 | Plaintext key in clan's temporary file on stibnite | accept-modified: option (a), with `diskutil erasevolume`, `enableOwnership`, `.metadata_never_index` and the logged check above | keeps the stated guarantee for four commands | accept (2026-11-07) | design D10 (guarantee and residual) and D12 (RAM disk commands, logged check, rejected option (b)); `plan.md` Global Constraints, clan vars; `task-2.md` Step 4 (commands, expected, residual, stop rule); `tasks.md` 2.4; FAI `The vars are imported`; the emptiness check reads the directory's top level, where `NamedTemporaryFile` writes, because clan's evaluation cache also lands under `TMPDIR` |
| F2 | Rotation can remove the old root while the old chain is served | accept-modified: gate step 5 on the served chain verifying with `-CAfile` naming the new root alone; do not move stored leaves | the gate observes the condition directly and does not rest on the inferred leaf behaviour | accept (2026-11-07) | design D7 steps 4 and 5; FA `The old root is removed too early` |
| F3 | Clause C fails on three undeclared files | accept-modified: declare the VM test and `observability-notify-run.nix` as non-clients with reasons, keep 4.6's wording, add `default.nix` to 4.4's expected red | a declaration states why the file is not a client; rewording would hide the mention | accept (2026-11-07) | design D5 non-client table; `task-4.md` Step 4 (`nonclients`, expected red, the mutant preview's tree); `tasks.md` 4.4 |
| F4 | `verificationSkipped` does not skip | accept | the mutant must accept for the leg to reject it | accept (2026-11-07) | `task-5.md` Step 1 (`sed 's/^verified=0$/verified=1/'`) and Step 2 (the edited line); design D6 mutants; `tasks.md` 5.1 |
| F5 | The gate's search omits A83 | accept | the plan must search what the change adds | accept (2026-11-07) | `task-1.md` Step 2 (`A8[0-3]`, "no A78-A83") |
| F6 | The expiry notice does not name the expiry | accept-modified: reword the FA requirement to a notice naming `caddy-root-check`, its journal naming the expiry; leave the notifier unchanged | changing the notifier's message touches every notified unit, beyond this change | accept (2026-11-07) | FA `The service authority's expiry reaches a person 180 days ahead` and its scenario `The root enters its last 180 days` |
| F7 | Empty `NTFY_CACERT` untested; `caUnset` cannot fail | accept | the spec requires the empty case, and the token test's stub can observe "before curl" | accept (2026-11-07) | `caUnset` moves from the TLS test to the token test beside `caEmpty`, with mutant `cacertGuardDropped` run only on `caEmpty`: design D4; `plan.md` Interface contract; `task-4.md` Steps 1, 2 and 3; `tasks.md` 4.1 to 4.3; FAI `ntfy-send verifies ntfy.zt against caddy's root and fails closed` (discharge, scenario `No CA file is given`) |
| F8 | `configured root` compares with its own input | accept-modified: reword the FAI scenario to "the configured `certFile` and `keyFile`"; no check change | comparing with the generator's paths on cinnabar would restate the line that sets them | accept (2026-11-07) | FAI `caddy's adapter reads the configured root` |
| F9 | `configFile` path; `pkiDropped` breadth | accept | the path is evaluated; a mutant should remove only the judged block | accept (2026-11-07) | `task-2.md` Step 2 (`--config ${caddy.configFile}` and the sentence after the module) and Step 5 (`pkiDropped` override and the sentence after the block); `tasks.md` 2.5 |
| F10 | 7.1's absence check cannot fail | accept-modified: keep `rc=60` as the clause, drop the absence check and the scenario's "the ingress receives no request" | `rc=60` is the discriminating observation; reading the ingress's log adds a source for nothing more | accept (2026-11-07) | `task-7.md` Step 1; `tasks.md` 7.1; FAI `A deployed host is pointed at another server`; design "Migration Plan" acceptance |
| F11 | Readers not pinned | accept | an unstated expectation cannot stop the step | accept (2026-11-07) | design layout table, D10, D12 and the security trade-off; `task-2.md` Steps 4 and 7; `task-8.md` Step 2; `tasks.md` 2.4; FAI `The vars are imported`; WA A81 (statement, evidence, scenario) |
| F12 | Six text inconsistencies | accept | each pair needs one text; groups 2 to 5 for the inventory, §11 for applied findings | accept (2026-11-07) | (a) `tasks.md` 1.1 and `task-1.md` Step 1, groups and Tasks 2 to 5; (b) `tasks.md` 9.3, §11; (c) `task-4.md` Step 7 heading, pull request 2, and in the same pass `task-8.md` Step 3 heading, pull request 4; (d) `tasks.md` 4.2 and design D4, `NTFY_CACERT=/ca`; (e) `tasks.md` 1.4, exit 0, because `-w '%{http_code}'` would change the argument list the rehearsal copies; (f) `task-2.md` Step 2, one `--option builders` |
| F13 | Clause C matches comments | accept-modified: keep the clause as written and add one header sentence saying comments count | the false positive costs one declaration and errs towards review | accept (2026-11-07) | `task-4.md` Step 4, the check's header; design D5; `tasks.md` 4.4 |
| F14 | Runtime cannot show the configured root | accept-modified: in 3.1, on cinnabar, read `curl -s localhost:2019/config/apps/pki` before and after, as read-only evidence | the rendered Caddyfile has no `admin off` and `services.caddy.enableReload` is `true`, so the admin endpoint is on | accept (2026-11-07) | `tasks.md` 3.1; `task-3.md` Steps 1 and 2; design D8 step 1 and "Migration Plan" acceptance |
