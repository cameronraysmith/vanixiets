## 1. Regulators (red first)

- [x] 1.1 Add `flake.lib.fleetDeployer` (`modules/lib/fleet-deployer.nix`) and assert it in `modules/checks/machines.nix`.
  - Contents: targets derived from enabled machines (Q30); the role policy (Q31); `keys` (null until provisioned); the target and request key lines; the policy judge `problems`; the host judge `failures`.
  - Machine checks: `failures` on every `nixos-<host>`/`darwin-<host>` check, `problems == [ ]` once.
  - Lift the terranix machine sets to `flake.lib.cloudMachines` (`modules/lib/cloud-machines.nix`).
  - Add the typed `primaryUser` to `flake.lib.hosts`.

  — verify: `nix eval .#lib.fleetDeployer` shows targets `argentum cinnabar magnetite pyrite rosegold` and disabled `electrum galena scheelite`; `nixos-cinnabar` fails before the deployer module exists (red); terraform JSON identical before and after the lift
  - Evidence (2026-11-18): targets and reach as stated; `problems = [ ]`. The red message was `Fleet obligations unmet on cinnabar: … fleetDeployer [cinnabar is the deployer host but does not run the deployer]`. `config.tf.json` was the same store path before and after the lift (sha256 `3cea80f0ab7acc241a6dcc03c12318f465bb68980ccdee407139b80d3f2c98ec`). Every machine-check drvPath evaluates: cinnabar, electrum, galena, magnetite, pyrite, stibnite, rosegold, argentum, blackphos.
- [x] 1.2 Add `checks.x86_64-linux.fleet-deploy-request`: the parser and authorization over 20 fixtures (4 accepted, 16 mutants refused with 3). — verify: built on magnetite
  - Evidence: built on magnetite (`/nix/store/fayachfj…-fleet-deploy-request`).
- [x] 1.3 Extend `checks.x86_64-linux.sops-correspondence` with the deployer's reach (secret-custody-interface), and add the mutants `deployer-reaches-stibnite`, `deployer-reads-shared` and `deployer-user-early`. The mutants `deployer-key-changed` and `deployer-group-missing` run once `keys` is set. — verify: built on magnetite; each mutant fails naming its file
  - Evidence: built on magnetite; `0 failures` on the tree, and the three mutants failed as expected (for example `FAIL: sops/secrets/stibnite-age.key/groups/fleet-deployers gives the fleet deployer a secret outside its targets' machine keys and vars`). The two provisioned mutants have not run yet; they run at task 2.2.
- [x] 1.4 Add `checks.x86_64-linux.fleet-deployer-obligations`: `targetsFrom`, `policyProblems` and `hostProblems` over fixtures. Cases: 6 policy (disabled, excluded and phone targets; an operator on a personal machine; a primary user on a shared server) and 13 host (missing primary-user account, key on a non-target, second account, unrestricted line, missing line, extra deployer key, widened key dir, widened UMask, deployer service outside its host). — verify: built on magnetite; real-data mutants evaluated
  - Evidence: built on magnetite. `nix eval` of real-data mutants: `electrum is disabled but is a deploy target`; `stibnite is not a deploy target but root accept the deployer's key`; `janettesmith reaches pyrite outside the role policy`; `h: root does not carry exactly the deployer's key line from="fd09:…:9f7e,fddb:…:343b,10.147.17.1",restrict …`.

## 2. The deployer's keys and read scope (D2, D3)

- [x] 2.1 Add `modules/nixos/fleet-deployer.nix`, imported by cinnabar. It declares:
  - the `fleet-deployer` account and tmpfiles (`0700`);
  - `fleet-deployer-keys` (`UMask=0277`);
  - `fleet-deployer-keycheck` and its daily timer;
  - the SSH client config naming only the deployer's key;
  - `fleet-deploy-notify`, a path unit plus a root oneshot.

  — verify: `nixos-cinnabar` evaluates green; the VM test covers runtime (4.3)
  - Evidence: `nixos-cinnabar` drvPath evaluates with the obligation met; `users.users.fleet-deployer.openssh.authorizedKeys.keys` is `[ ]` until request keys exist.
- [x] 2.2 HOST STEP:
  - Deploy cinnabar from stibnite so `fleet-deployer-keys` generates the keys.
  - Read their public halves on cinnabar and commit them to `flake.lib.fleetDeployer.keys` and `sops/users/fleet-deployer/key.json`.
  - Create the group `fleet-deployers` with only that user, and add it to the targets' machine keys and activation vars (D3). Use a throwaway clone with `CLAN_NO_COMMIT=1` and copy back only the resulting files.

  — verify:
  - only `sops/users/fleet-deployer`, `sops/groups/fleet-deployers`, the five targets' machine keys and the three activation vars changed;
  - nothing else gained or lost a recipient, and no secret value changed;
  - `sops-correspondence` passes with its provisioned mutants;
  - every machine check is green with `keys` set, and an added activation var without the group fails.
  - Evidence (2026-11-18): #4029 deployed cinnabar, and `fleet-deployer-keys` generated the keys (age `age107c7…mpaw`, SSH `…FbyeGR fleet-deployer@cinnabar`; `logs/cam115-step1-cinnabar-*.log`). In a clone of `main@origin` `057a8c5f`, with `CLAN_NO_COMMIT=1`, I ran:
    - `clan secrets users add fleet-deployer --age-key …`;
    - `clan secrets groups add-user fleet-deployers fleet-deployer`;
    - `clan secrets groups add-secret fleet-deployers <m>-age.key` for argentum, cinnabar, magnetite, pyrite and rosegold;
    - group links plus `clan vars fix <m> -g initrd-ssh` for cinnabar, magnetite and pyrite.
  - Of the 190 secret files under `sops/secrets` and `vars`, exactly those 8 gained the one recipient `age107c7…mpaw`, and the other 182 have the same recipients as before. stibnite, blackphos, electrum, galena and scheelite are untouched. The sha256 of each of the 8 decrypted values is unchanged.
  - `sops-correspondence` built with `deployer-key-changed` and `deployer-group-missing` failing as expected. The nine machine-check drvPaths evaluate. On cinnabar, an `extendModules` activation var gives `cinnabar: vars/per-machine/cinnabar/fd-mutant/key is decrypted by the deployer but fleet-deployers is not a reader`; the fixture mutants `activationVarWithoutGroup` and `machineKeyWithoutGroup` each yield one problem.
  - The decrypt-on-cinnabar test (the deployer reads rosegold's machine key but not stibnite's) moves to task 4.2, the first step run as the deployer.
- [x] 2.3 HOST STEP: on cinnabar, make `keys/age.key` mode `0440` and start `fleet-deployer-keycheck`; it fails. Restore the mode; it passes. Record whether `SystemdUnitFailed cinnabar` is posted (open question 3). — verify: unit results and the ntfy post
  - Evidence (2026-11-18, `logs/cam115-steps0-3-*.log`): with mode 0440 the key check failed, and it passed again at 0400. No `SystemdUnitFailed` alert was posted, which answers open question 3: no. #4042 adds `fleet-deployer-keycheck` to cinnabar's `notifiedUnits`, with its timer at `*-*-* 04:00:00 UTC` as observability-notify requires. Since cinnabar was redeployed, the key check passes against the committed keys.
- [x] 2.4 The obligation's key-mode clause judges the declared tmpfiles mode and `UMask`. — verify: mutants `deployerWideKeyDir` and `deployerWideUMask` in 1.4
  - Evidence: covered by 1.4's build.

## 3. Requesters and their credentials (D4, D5)

- [x] 3.1 Render `fleet-deployer`'s `authorized_keys` from `requesterLines`: `restrict,from="<three ranges>",command="/run/current-system/sw/bin/fleet-deploy-request <name>" <key>`, for each requester whose generated public key exists. — verify: the obligation's deployer clause; the VM test's forced-command requests
  - Evidence: green on `nixos-cinnabar`; the lines are empty until 3.3.
- [x] 3.2 Add the credential kind `deployRequestKey`:
  - the generator `<worker>-deploy-request` (shared, ssh-keygen, private `key` `0400`, public `key.pub`);
  - the worker SSH alias `fleet-deployer` and the `fleet-deploy` command;
  - the generator-name assertion and obligation;
  - the flag `deployRequestEnrolled = false` in `modules/clan/inventory/services/omnigent.nix`.

  — verify: the five omnigent checks build; with the flag forced on, only the two missing-ciphertext assertions fail
  - Evidence: `omnigent-worker-capabilities`, `omnigent-credential-policy`, `omnigent-credentials-unit` (33 tests), `omnigent-worker-inventory` and `omnigent-worker-linux` built. With the flag forced on through `extendModules` (magnetite, pyrite, stibnite), the generators are shared, prompt-free, `key` secret and `key.pub` public, and the alias and command are present. The only failed assertions are "credentials require private shared services files…" and "only the declared Clan vars ciphertext…".
- [ ] 3.3 HOST STEP (returns to the orchestrator first):
  - Run `clan vars generate` for `omnigent-cameron-deploy-request` and `omnigent-janettesmith-deploy-request`, and flip `deployRequestEnrolled = true` in the same commit.
  - Deploy cinnabar (new authorized keys), then magnetite and pyrite from stibnite, then stibnite by `just activate`.

  — verify:
  - each delivered key file is `0400` and owned by its worker, and its parent directories are root-owned `751`, as sops-nix creates them (traversable, not listable);
  - `fleet-deploy shell` from each worker exits 3 with a refusal;
  - every alert since each deploy started is recorded with its cause.
  - Repository half, done (2026-11-19, in a clone of `main@origin` `4de4d1cb` with `CLAN_NO_COMMIT=1`):
    - `clan vars generate magnetite pyrite stibnite -g omnigent-cameron-deploy-request` and `clan vars generate magnetite pyrite -g omnigent-janettesmith-deploy-request`;
    - only the two new `vars/shared/omnigent-<user>-deploy-request/` trees were added, and no other file changed;
    - cameron's `key/secret` is readable by the operator key (`age1vn8f…tmv8`), magnetite, pyrite and stibnite;
    - janettesmith's is readable by the operator key, magnetite and pyrite;
    - `fleet-deployers` (`age107c7…mpaw`) reads neither;
    - cinnabar's evaluated `fleet-deployer` authorized keys now hold the two forced-command lines.
  - Host half (2026-11-19, `logs/pr-cam-115-request-keys-merge-20261118-213423.log`): #4043 merged on the operator's approval (Q65).
    - cinnabar and pyrite were deployed with rc=0, and stibnite was activated with rc=0; cinnabar's `fleet-deployer` holds the two request lines, and no unit failed.
    - Refusals: `cameron` asking for `stibnite` got "refused: 'stibnite' is not a deploy target", exit 3; `janettesmith` asking for `pyrite` got "refused: janettesmith may not deploy pyrite", exit 3.
  - Delivered keys (2026-11-19, read-only `stat -c '%U %a %n'`, over SSH on magnetite, pyrite and cinnabar, locally on stibnite):
    - On magnetite and pyrite, `/run/secrets/vars/shared/omnigent-cameron-deploy-request/key` is owned by `omnigent-cameron` with mode 400, and `/run/secrets/vars/shared/omnigent-janettesmith-deploy-request/key` by `omnigent-janettesmith` with mode 400.
    - On stibnite, cameron's key is owned by `omnigent-cameron` with mode 400; janettesmith's is absent there, as her recipients are magnetite and pyrite only. cinnabar holds neither.
    - Every parent directory, from the key's own up to the sops-nix generation directory (`/run/secrets.d/<n>`, which the `/run/secrets` symlink points to), is owned by `root` with mode 751 on magnetite, pyrite and stibnite.
  - Operator decision (2026-11-19): the clause names root-owned `751` parents, not a `0700` directory, because a root-owned `0700` directory would stop the worker from reaching its own key.
  - Still open: `fleet-deploy shell` from each worker, and the alerts since each deploy.

## 4. The request path (D6, D7, D9, D11, D12)

- [x] 4.1 Write `fleet-deploy-request` (`pkgs/by-name/fleet-deploy-request`, Python) to D1-D12. Its order:
  - parse and authorize;
  - fetch `main` and run the ancestor check;
  - create a worktree;
  - with a slot: resolve the commit's closure and target, check the cache (NixOS), run `clan vars check` for every machine;
  - probe the target;
  - take the host lock, then a slot;
  - arm the watcher and deploy;
  - settle, confirm, run the health check;
  - record the request.

  — verify: the package builds (flake8 in `writePython3Bin`); checks 1.2 and 4.3
  - Evidence: built on magnetite.
  - Q66 (2026-11-19): #4046 makes the health check compare the target's running system with the deployed closure (design, Risks, F72). cinnabar was redeployed at 03:07Z with rc=0, and its `fleet-deploy-request` contains the running-system check (`logs/deploy-round-q66-collation-20261118-220709.log`).
- [x] 4.2 HOST STEP: on cinnabar, as `fleet-deployer`, in a worktree of `main`, run `clan vars check` for every machine, then `clan machines update magnetite --target-host root@192.0.2.1` (unreachable, so it stops at the connection). — verify: every `vars check` exits 0 without decrypting out-of-scope files, and the update fails at the connection, not at decryption; if not, stop and revise D7
  - Evidence (2026-11-18, `logs/cam115-steps0-3-*.log`):
    - as `fleet-deployer`, rosegold's machine key and pyrite's `initrd-ssh/id_ed25519` decrypt; stibnite's machine key and `ntfy-alerter` exit 128, with no value printed;
    - `clan vars check` passes ("All vars are present and valid") for all ten machines.
  - Run through `runuser` from root, `clan vars check` first crashed with `PermissionError: /run/user/0/clan-cache` (root's `XDG_RUNTIME_DIR`, inherited). #4042 makes `fleet-deploy-request` replace its environment (`HOME`, `XDG_RUNTIME_DIR`, `XDG_CACHE_HOME` and `TMPDIR` under `/var/lib/fleet-deployer`, 0700). The VM test's hostile-environment case fails without that and passes with it.
- [x] 4.3 Run `vmTests.x86_64-linux.fleet-deployer` on pyrite (KVM). The stand-ins are the forge, the cache check (`cacheCheckCommand`), the vars check and clan. Its cases:
  - a merged commit (0);
  - an unmerged commit, an unreachable-by-policy host, `stibnite` and `shell` (3, no target connection);
  - an uncached closure and a failed vars check (3);
  - a held lock (4);
  - concurrent requests serialised;
  - a stopped sshd (5 within 15 s, no host lock);
  - a failed unit (7, kept);
  - SSH cut by activation (8, rolled back);
  - notices;
  - the key check on a widened mode.

  — verify: `nix build .#vmTests.x86_64-linux.fleet-deployer` on pyrite after its GC hold test ends
  - Evidence (2026-11-18T23:39Z, `logs/fleet-deployer-vmtest-20261118T2339Zh.log`): all nine subtests passed and the test script finished in 201 s. Outcomes:
    - `deployed` with the record naming the closure;
    - `refused` for the unmerged commit, `other`, `stibnite` and `shell`, with no new accepted SSH connection on the target;
    - `refused` for the uncached closure and for the failed vars check;
    - `busy` after 20 s;
    - the second concurrent deploy started after the first ended;
    - `unreachable` in 0.57 s with no host lock;
    - `unhealthy: failed unit broken.service`, kept after the window;
    - `rolled-back`, with the target back on `broken` and the record's `previous_closure` = `isolated`;
    - 13 posts, high priority exactly for refused, unhealthy and rolled-back;
    - `requests.jsonl` mode 600;
    - the key check failing at 0440 and passing at 0400.
  - Earlier runs on the same day found two defects, both fixed in `srnuwxtx`: `ssh-keygen` forces 0600 on the private key past `UMask=0277`, so `fleet-deployer-keys` now runs `chmod 0400` afterwards; and `fleet-deploy-notify` hit systemd's start limit during a burst of refusals, so it now sets `startLimitIntervalSec = 0`.
- [x] 4.4 `fleet-deploy-notify` posts each request line to `fleet-deploy` with the alerter token, high priority for refused, unhealthy and rolled-back. ntfy's existing `alerter:fleet-*:rw` admits the topic (Q32). — verify: the VM test's notices case
  - Evidence: no ACL edit is needed (`modules/machines/nixos/cinnabar/ntfy.nix:61-64`); runtime proof is in 4.3.

## 5. Targets and rollback (D8, D10, D13)

- [x] 5.1 Add `modules/system/fleet-deploy-target.nix` (NixOS and darwin, imported by every base). On targets it installs `fleet-deploy-watch` and, once `keys` is set, adds the restricted key line to the deploy account. The group's read access is per file (D3), not through `defaultGroups`. — verify: every machine check is green; the host-judge mutants in 1.4
  - Evidence: all nine machine-check drvPaths evaluate; `fleet-deploy-watch` is in magnetite's `systemPackages`.
- [ ] 5.2 HOST STEP: after 2.2, deploy each target from stibnite one at a time: cinnabar, magnetite, pyrite, then rosegold and argentum when awake. — verify: on each, `ssh -i <deployer key> <deployUser>@<host> true` succeeds from cinnabar as `fleet-deployer`, and the same key is refused from any other address; every alert since each deploy started is recorded with its cause
  - Evidence (2026-11-18/19): trust deploys of cinnabar, pyrite, rosegold and argentum are done, and `fleet-deployer` reaches `root@pyrite` and `cameron@{rosegold,argentum}`, with sudo on the Macs. rosegold and argentum were deployed without `--target-host`, and clan used `cameron@<host>.vanixiets.internal` (the F36 fix; CAM-109 task 9.11). The argentum deploy hit F72 (design, Risks). magnetite's trust comes with its pending deploy.
- [x] 5.3 Write `fleet-deploy-watch` (`pkgs/by-name/fleet-deploy-watch`). It watches `/run/current-system`, has a confirm window, rolls back by profile generation plus activation, and removes its own launchd job. — verify: the VM test's rollback case (4.3)
  - Evidence: the rollback case in 4.3 (NixOS). The darwin path is task 5.4.
- [ ] 5.4 HOST STEP: on rosegold or argentum, with its user told in advance, deploy through the deployer at the deployed commit (no closure change). Then run a watcher by hand with a 60 s window on an unchanged system. — verify: the deploy exits 0 and no `org.vanixiets.fleet-deploy-watch.*` job remains; the hand-run watcher ends without switching (A159 for darwin); every alert since the test started is recorded with its cause

## 6. Integration Verification

- [ ] 6.1 From an `omnigent-cameron` session on magnetite, while stibnite is asleep, run `fleet-deploy magnetite`. — verify:
  - exit 0, and the log shows fetch, cache hit, update and health;
  - one `requests.jsonl` line, one `fleet-deploy` post, and magnetite's deploy record names the closure;
  - every alert since the request started is recorded with its cause.
  - F80 (2026-11-19, fixed by #4053): the first attempt at c3672d28 was refused at the cache check. The deployer resolved through a `path:` reference, which copies `.git`, so the closure it resolved never matched CI's. It now uses `git+file://<worktree>?rev=<commit>` for every step, and `checks.x86_64-linux.fleet-deploy-resolve` and its `path:` mutant regulate it (`logs/cam115-e2e-20261119T0339Z-f78-diag.log`).
  - Evidence (2026-11-19, main 1c544d53, `omnigent-cameron` on magnetite): exit 0 with closure `sanh2m2m…` (nixbot #2722), activated, settled 60 s, deployed. Request `9bc06211b083` wrote one `requests.jsonl` line and one p3 post, and magnetite's deploy record names the closure. No fleet-alerts in the window (`logs/cam115-e2e2-20261119T0435Z-6.1.log`, `logs/cam115-e2e2-20261119T0640Z-6.1-verify.log`).
  - Rerun with stibnite asleep: stibnite was awake, because it ran the test. The requester's log has no explicit fetch or cache-hit line, so the rerun's evidence must show the cache hit through the deployer's record or journal, or state that it is implied by the absence of a cache refusal.
- [ ] 6.2 From an `omnigent-janettesmith` session, deploy a real configuration change to cinnabar (D13), then ask for pyrite. — verify: cinnabar exits 0 across its own activation; pyrite exits 3 (outside her reach) with a high-priority post; every alert since each request started is recorded with its cause
  - Evidence (2026-11-19, main 1c544d53, from magnetite): pyrite was refused with exit 3, `janettesmith may not deploy pyrite`, a p4 post and no deployer login on pyrite. cinnabar resolved to `kmh8nxa6…`, which is nixbot #2722's `nixos-cinnabar`, and was refused with exit 3 at the cache check. The refusal was correct, because nixbot never uploaded `skipped_local` outputs (F81). No fleet-alerts in the window (`logs/cam115-e2e2-20261119T0438Z-6.2.log`, `logs/cam115-e2e2-20261119T0439Z-6.2-cache.log`).
  - F81, first fix (#4054) did not take effect: in #2726 (bc9b2178), all five `nixos-*` outputs, cinnabar's `75gqnpym…` included, were `skipped_local` and still 404 on the cache at 07:53Z. The patch fired only on main events, and the main push reused the PR build by tree hash. No request was sent (`logs/cam115-e2e2-20261119T0752Z-6.2b-resolve.log`).
  - F81, every-build patch (305a112b) worked: in #2727 and #2728 (0cb13291), `nixos-cinnabar` was still `skipped_local`. niks3 registered `75gqnpym….narinfo` at 08:12:16Z, and the narinfo is 200. The deployer's resolve at 0cb13291 gives the same `75gqnpym…` (`logs/cam115-e2e2-20261119T0816Z-6.2c-resolve.log`).
  - Rerun (08:19Z, 0cb13291) ended unreachable: exit 5 after the cache check passed, `root@cinnabar.zt did not answer within 10 s`. Request `b7309b8d9d9d` got a p3 post, and cinnabar stayed on `kmh8nxa6…` with no failed units and no fleet-alerts. Cause: on cinnabar, `/etc/hosts` maps `cinnabar.zt` to 127.0.0.2. The deployer's key line in root's `authorized_keys` allows only `from=` cinnabar's mesh addresses, so sshd refused the key from 127.0.0.1 ("correct key but not from a permitted host"). The deployer cannot yet deploy its own host (`logs/cam115-e2e2-20261119T0819Z-6.2c.log`, `logs/cam115-e2e2-20261119T0822Z-6.2c-unreachable-diag.log`).
  - The cinnabar request is to rerun once the deployer can reach its own host.
- [ ] 6.3 Ask for `rosegold` while it is asleep, then while it is awake at a commit that changes its closure. — verify:
  - the first exits 5 within one minute, with no change on rosegold;
  - the second exits 0, the log shows target `cameron@…`, and the darwin machine-key guard passes;
  - every alert since each request started is recorded with its cause.
  - Not reached (2026-11-19): no request was sent to rosegold or argentum. It needs a window in which the machine's user (janettesmith on rosegold) is logged in at the console. Physical presence is not needed (F72 as narrowed in design, Risks).
- [x] 6.4 Exercise refusals live: an unmerged commit, `deploy stibnite`, `deploy electrum` and a malformed command. — verify: each exits 3 with no SSH connection from cinnabar, with a `requests.jsonl` line and a high post
  - Evidence (2026-11-19, `omnigent-cameron` on pyrite): the requests were `071b5aa7…` (an unmerged renovate head), `stibnite`, `electrum`, and two malformed targets, `magnetite;touch /tmp/cam115-canary-…` and `magnetite$(touch …)`. Each exited 3 with its own `requests.jsonl` line and a p4 post. No root login from cinnabar reached magnetite or pyrite, and no canary file exists on the worker, cinnabar or magnetite. The fleet-alerts in the window, FilesystemFillingWarn on rosegold and AlertBudgetExceeded, are unrelated (`logs/cam115-e2e2-20261119T0422Z-6.4.log`, `logs/cam115-e2e2-20261119T0427Z-6.4-probe.log`, `logs/cam115-e2e2-20261119T0427Z-6.4-malformed.log`).
  - Incident, 04:22Z: a quoting error in the test harness (a `;` inside a remote shell string) made pyrite's root shell run a real `fleet-deploy magnetite` as `omnigent-cameron` with no session. It then ran `reboot --session …` as root on pyrite, which failed only because `--session` is not a `reboot` option. The deploy was correct: request `5b74e975f92b` at 1c544d53, `bny34077…` → `sanh2m2m…`, deployed with a p3 post. It restarted magnetite's `omnigent-host-*` and home-manager units, and its window was reported so the overlapping evaluator replay pair could be redone. The harness now passes each argument through `printf %q` to `ssh … -- sudo -u …` without `-i`, and was proven with an `echo` probe first (`logs/cam115-e2e2-20261119T0426Z-incident.log`).
- [ ] 6.5 In a window the operator picks, on pyrite, request a deploy and block cinnabar's mesh route to pyrite with `nft` after activation. — verify:
  - pyrite returns to the previous system within 360 s, and the request exits 8 with a high post;
  - once the route is restored, pyrite's deploy record has both lines;
  - every alert since the request started is recorded with its cause.
  - Evidence (2026-11-19, `omnigent-cameron` on magnetite): a rollback by request, not the route block. `fleet-deploy pyrite c6376ab4…` deployed `vfrsl7xf…` (nixbot #2710) with exit 0, then `fleet-deploy pyrite` deployed `smwfj9zc…` (main 1c544d53, #2722) with exit 0. After each, `/run/current-system` and the deploy record named the new and previous closures, with no failed units, p3 posts and no fleet-alerts (`logs/cam115-e2e2-20261119T0429Z-6.5.log`).
  - Still to run: the route block and the exit 8 rollback.
- [ ] 6.6 Write the operator runbook page (`packages/docs/src/content/docs/development/operations/`). It covers what a session runs, the exit statuses, adding a requester or target, revoking, and moving the deployer. — verify: the docs package builds

## 7. Close-out

- [ ] 7.1 List the provisioning conditionals and remove those that no longer apply once the host steps are done:
  - `keys == null` branches in `modules/lib/fleet-deployer.nix`, `modules/system/fleet-deploy-target.nix`, `modules/nixos/fleet-deployer.nix` and `modules/checks/sops-correspondence.nix`;
  - `deployRequestEnrolled`;
  - the `pathExists` on request public keys.

  — verify: `rg -n "keys == null|keys != null|deployRequestEnrolled|pathExists \(requestKeyFile" modules` finds only what still applies, and every machine check evaluates
