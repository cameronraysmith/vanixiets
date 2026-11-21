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
  - F84 (2026-11-19): on darwin the watcher ran as the deploy user in `gui/502`. It was armed with `sudo sh -c 'launchctl submit …'`, and `submit` acts on the caller's bootstrap namespace, which sudo keeps. As that user it could not create `/var/run/fleet-deploy`, the confirm failed, and it could not roll back. The deployer reported `rolled-back` (8) without reading the host (`logs/cam115-e2e3-20261119T1852Z-6.3-rolledback-diag.log`). Fix (design D10):
    - The darwin target declares the job as data (`vanixiets.fleetDeployWatch`, `/etc/fleet-deploy-watch`), and `sudo fleet-deploy-watch --arm` bootstraps it into `system`.
    - The deployer arms only a target that has that job.
    - It reports `rolled-back` only after reading the target back on its previous closure, and `unconfirmed` (9) otherwise.
    - Regulators: the darwin judge in `flake.lib.fleetDeployer.failures` with five mutants in `checks.x86_64-linux.fleet-deployer-obligations`, and the deploy runs of `checks.x86_64-linux.fleet-deploy-request`. That check exited 8 for a target left on the deployed closure before the fix (`logs/cam115-f84-deploy-request-red-20261119.log`).
    - `vmTests.x86_64-linux.fleet-deployer` on pyrite. Its first run exited 9 for the SSH-cut case: the `isolated` drop rule sat in `INPUT`, which the rollback's firewall reload does not flush, so the deployer still could not reach the target. The old exit 8 had been reported without reading the target. With the rule in `nixos-fw`, the case exits 8 with `returned to <broken>` (`logs/cam115-f84-vmtest-fleet-deployer-before-fixture-20261119.log`, `logs/cam115-f84-vmtest-fleet-deployer-20261119.log`).
    - Live (2026-11-19): cinnabar took the F84 deployer code by its own request at f2f5382b (`fleet-deploy cinnabar`, exit 0, `8ppikbpb…`). Its request command changed from `w0m80zgf…` to `s9vqzv62…`, which carries `await_rollback` (`logs/cam115-f84-20261119T1926Z-1-cinnabar.log`). The Mac path is in 5.4.
  - F82 (2026-11-19, #4060): the deployer could not reach its own host. On cinnabar `cinnabar.zt` resolves to 127.0.0.2, and the deployer key's `from=` list admitted only mesh addresses (6.2's 08:20Z attempt).
    - `targetKeyLine` now also admits `127.0.0.1,::1` on the deployer host only. `hostProblems` requires exactly that, with fixtures `deployerLineWithoutLoopback` and `targetLineWithLoopback`. The `no-loopback` mutant was seen failing (`logs/cam115-f82-red-20261119T0824Z.log`, `logs/cam115-f82-green-20261119T0828Z.log`).
    - A request survives its own host's switch. It runs in its sshd session's scope, and sshd is `KillMode=process` with `X-StopIfChanged=false`.
    - `vmTests.x86_64-linux.fleet-deployer` adds "a request that switches the deployer's own system survives the switch": sshd restarts and the request command is replaced mid-request. At 71ec4d13 on pyrite, all 13 subtests passed (`logs/fleet-deployer-vmtest-20261119T1839Z-f82-main.log`). Live proof: 6.2.
  - F86 (2026-11-19, main f2f5382b): every darwin activation recorded `previous_closure` equal to `closure`: clan's update, a manual `activate` and the watcher's rollback (argentum at 19:32:12Z, 19:34:28Z and 19:35:09Z; `logs/cam115-f84-20261119T1931Z-2.1-manual-update.log`, `logs/cam115-f84-20261119T1934Z-2.3-rollback.log`).
    - The order of the rendered activate script was unchanged from 71ec4d13: the record still ran before the final relink. The same jcnmk… script recorded correctly at 18:45 and wrongly at 19:34.
    - The cause is nix-darwin's `activate-system` daemon (`modules/services/activate-system` at ff0e21a). It runs at load and links `/run/current-system` to `cat /nix/var/nix/profiles/system/systemConfig`. Its script embeds the `/etc` activation, so its plist changes whenever the set of `/etc` files changes, which F84's `/etc/fleet-deploy-watch` did in both directions. The activation's launchd step then reloads it, after `nix-env --set` and before `postActivation`, so the link already names the new system when the record reads it.
    - Fix: the darwin `preActivation` reads `/run/current-system` first, and the record takes that read as a second argument.
    - Regulators: `flake.lib.deployRecordObligations` now judges the rendered activation's order on every machine check. Before the fix it failed all four Macs, and it fails argentum with the read removed or moved into `postActivation`. `checks.x86_64-linux.deploy-record-order` covers the judge's fixtures and mutants and the record script's two-argument form.
    - Fixed by #4067. Live proof: argentum's deploy record at 19:54:41Z, from 5.4 step 4, names closure `ydnfm1yn…` with previous `cbrb4rak…` (`logs/cam115-f84-20261119T1951Z-2.4-request.log`).
  - F90 (2026-11-21): a deploy of the running closure left the watcher loaded for `activationWait` (2 h). The confirmation was read only after `/run/current-system` changed, and a same-closure deploy never changes it.
    - On rosegold, request `8da9881f6a10` (main 6ffb8fac) was confirmed and reported deployed, and its job stayed in `system`. Every `--arm` then refused the Mac until it was disarmed by hand (`logs/cam115-6.3-rosegold-20261121T1527Z-2-request.log`).
    - On magnetite, the NixOS unit lingered the same way: `9bc06211b083` (6.1, 2026-11-19 04:36–06:36Z) and `4787da1fe27e` (2026-11-20 21:32–23:32Z) each ended "did not change within 7200s", with no rollback. The next request's `systemctl stop 'fleet-deploy-watch-*'` would have cleared them, so they never blocked a deploy.
    - Fix: the watcher reads the confirmation on every poll of the activation wait and ends (unloading its darwin job) once it is there. The timeout and rollback rules are unchanged.
    - The deployer does not also `--disarm` after `deployed`. A watcher whose window ran out just before a late confirmation can be in the middle of its rollback's activation while the health check still reads the new closure, and a disarm there (`bootout` or `systemctl stop`) would kill the rollback half done.
    - Regulators: `checks.x86_64-linux.fleet-deploy-watch` runs the watcher as built against a fixture root, as on NixOS and as the darwin job. Before the fix it failed "same closure, confirmed" on both platforms ("still running after 7 s"), and the other three cases passed. `vmTests.x86_64-linux.fleet-deployer` adds a same-closure deploy whose transient unit must be gone within 10 s.
- [x] 5.4 HOST STEP: in a window with argentum awake and both its users logged in (F72), with christophersmith told in advance. — verify, each step recorded with every alert since the window opened and its cause:
  1. From stibnite, `clan machines update argentum` at a commit carrying F84's fix. The deployer refuses to arm a Mac that lacks `/etc/fleet-deploy-watch/job.plist`, so this first deploy is by hand. Then `cat /etc/fleet-deploy-watch/domain` prints `system`, and `sudo launchctl print system/org.vanixiets.fleet-deploy-watch` reports the job is not loaded.
  2. `sudo fleet-deploy-watch --arm manual-1 30 30` on the unchanged system. `sudo launchctl print system/org.vanixiets.fleet-deploy-watch` shows it running, and `/var/log/fleet-deploy-watch.log` says `watching … as root`. A second `--arm` fails with `already loaded`. Within 60 s the log says the system did not change, and the job is unloaded (A159 for darwin).
  3. `sudo fleet-deploy-watch --arm manual-2 600 30`, then switch to the previous system generation by hand (`sudo nix-env -p /nix/var/nix/profiles/system --set <previous>` and its `activate`) without confirming. Within 60 s the watcher returns argentum to the system it recorded, and the newest deploy record names it.
  4. A deploy through the deployer at a merged commit that changes argentum's closure exits 0. While it is armed, `/var/run/fleet-deploy/request` names the request and the job is loaded in `system/org.vanixiets.fleet-deploy-watch` (only `--arm` creates either), `/var/run/fleet-deploy` is owned by root, and the job is unloaded after the confirm.
  - Clause reworded on 2026-11-19, after the first live run: step 4 asked for "its log shows `--arm`", but nothing logs the arm command line. It now names the request file and the loaded system-domain job, which only `--arm` creates.
  - Evidence (2026-11-19, argentum on AC power with christophersmith and cameron at the console, held awake with `caffeinate`):
    1. 19:31Z: `CLAN_NO_COMMIT=1 clan machines update argentum` from a throwaway `git clone --shared` of f2f5382b in /tmp. Exit 0, generation 32 `cbrb4rak…`, `domain` = `system`, job not loaded, tincr and otelcol up (`logs/cam115-f84-20261119T1931Z-2.1-manual-update.log`).
    2. 19:32Z: `--arm manual-1 30 30` ran as root in `system` (pid 75859), with `/var/run/fleet-deploy` root:wheel. The second arm exited 1 with `already loaded`. After 30 s: "did not change"; the job was unloaded and the directory emptied. `--disarm` of a 600 s arm also unloaded it (`logs/cam115-f84-20261119T1932Z-2.2-arm.log`).
    3. 19:34Z: `--arm manual-2 600 30`, then a switch by hand to `jcnmknlh…` (generation 33). The watcher returned argentum to `cbrb4rak…` 33 s later (generation 34), the job unloaded itself, and the newest record names `cbrb4rak…` (`logs/cam115-f84-20261119T1934Z-2.3-rollback.log`).
    4. 19:51Z, main 3e913270: `fleet-deploy argentum` exited 0 with `ydnfm1yn…` (generation 35), request `6c95d788794b`.
       - While armed, `/var/run/fleet-deploy/request` read "6c95d788794b 7200 300", and the job was running in `system` as root.
       - The watcher logged "confirmed", then the job unloaded and the directory emptied.
       - Services were up, both console sessions remained, and the record has `previous` `cbrb4rak…` (`logs/cam115-f84-20261119T1951Z-2.4-request.log`).
  - Alerts in the window (19:25Z on): two p3 `deployed` posts (cinnabar at 19:29:50Z and argentum at 19:55:51Z), and RESOLVED `otel-envelope.service` on magnetite at 19:51:04Z, which is unrelated (`logs/cam115-f84-20261119T1956Z-5.4-window-alerts.log`).

## 6. Integration Verification

- [x] 6.1 From an `omnigent-cameron` session on magnetite, while stibnite is asleep, run `fleet-deploy magnetite`. — verify:
  - exit 0, and the log shows fetch, cache hit, update and health;
  - one `requests.jsonl` line, one `fleet-deploy` post, and magnetite's deploy record names the closure;
  - every alert since the request started is recorded with its cause.
  - F80 (2026-11-19, fixed by #4053): the first attempt at c3672d28 was refused at the cache check. The deployer resolved through a `path:` reference, which copies `.git`, so the closure it resolved never matched CI's. It now uses `git+file://<worktree>?rev=<commit>` for every step, and `checks.x86_64-linux.fleet-deploy-resolve` and its `path:` mutant regulate it (`logs/cam115-e2e-20261119T0339Z-f78-diag.log`).
  - First run (2026-11-19, main 1c544d53): exit 0 with `sanh2m2m…`, request `9bc06211b083`. It did not count, because stibnite was awake and ran it (`logs/cam115-e2e2-20261119T0435Z-6.1.log`, `logs/cam115-e2e2-20261119T0640Z-6.1-verify.log`).
  - Evidence (2026-11-20, main aa88addf): the request was scheduled in advance as a one-shot `systemd-run` timer on magnetite (unit `cam115-e2e-6-1`, User/Group `omnigent-cameron`, 21:30:00Z) running `fleet-deploy magnetite --session cam115-e2e-6.1` (`logs/cam115-6.1-schedule-20261120-161840.log`).
    - stibnite was asleep: from 21:21 to 21:39Z pmset shows only DarkWake maintenance entries (Deep Idle, no user session), and its next FullWake was at 22:07Z (HID). cinnabar's sshd accepted the request from magnetite's address, not stibnite's.
    - Request `4787da1fe27e`, 21:30:01–21:34:03Z: deployed, exit 0, commit aa88addf, closure `byvvvi6q…`, with `previous`, `target` and `session` recorded. `previous` equals the closure because magnetite had been on main since 19:24Z, so this was a same-closure deploy.
    - Fetch: the deployer's nix-daemon connections on cinnabar start at 21:30:03Z.
    - Cache hit: no explicit line. It is implied by the absence of a cache refusal, and `byvvvi6q…`'s narinfo was 200 when checked independently.
    - Update: magnetite's activation ran 21:32:59–21:33:02Z.
    - Health: "activated; settling 60 s", then "deployed: magnetite runs byvvvi6q…" at 21:34:03Z. Afterwards magnetite was running with no failed units.
    - One p3 `fleet-deploy` post at 21:34:03Z. magnetite's deploy record at 21:32:58Z names `byvvvi6q…`. No fleet-alerts from 21:30Z to 21:40Z (`logs/cam115-6.1-evidence-20261120-170833.log`, `logs/cam115-6.1-post-alerts-20261120T2209Z.log`).
- [x] 6.2 From an `omnigent-janettesmith` session, deploy a real configuration change to cinnabar (D13), then ask for pyrite. — verify: cinnabar exits 0 across its own activation; pyrite exits 3 (outside her reach) with a high-priority post; every alert since each request started is recorded with its cause
  - pyrite (2026-11-19, main 1c544d53, from magnetite): refused with exit 3, `janettesmith may not deploy pyrite`, a p4 post and no deployer login on pyrite. No fleet-alerts in the window (`logs/cam115-e2e2-20261119T0438Z-6.2.log`).
  - Earlier cinnabar attempts:
    - 04:39Z: refused at the cache check because nixbot did not upload `skipped_local` outputs (F81).
    - 07:53Z: F81's first patch (#4054) did not upload either, because it fired only on main events.
    - 08:12Z: the every-build patch uploaded the closure.
    - 08:20Z: exit 5, because the deployer's key was refused from loopback on its own host (F82, 5.3).
    - Logs: `logs/cam115-e2e2-20261119T0439Z-6.2-cache.log`, `-0752Z-6.2b-resolve.log`, `-0816Z-6.2c-resolve.log`, `-0819Z-6.2c.log`, `-0822Z-6.2c-unreachable-diag.log`.
  - cinnabar (18:55Z, main 53f6ea2d, from magnetite): resolved `h05hmlbp…` (narinfo 200, a change from `chibpsnq…`), activated, settled 60 s, deployed, exit 0.
    - Request `60d3aff58def`, one p3 post; cinnabar's deploy record at 18:58:03Z (previous `chibpsnq…`).
    - The request survived its own host's switch: `fleet-deploy-request` changed from `mzxbbv69…` to `w0m80zgf…` while it ran.
    - After a further 75 s: no failed units.
    - The record and notice were written by the code that started the request (pre-#4061).
    - The one fleet-alert in the window, FAILED `otel-envelope.service` on magnetite, is unrelated (`logs/cam115-e2e3-20261119T1854Z-6.2-pre2.log`, `logs/cam115-e2e3-20261119T1855Z-6.2.log`).
- [ ] 6.3 Ask for `rosegold` while it is asleep, then while it is awake at a commit that changes its closure. — verify:
  - the first exits 5 within one minute, with no change on rosegold;
  - the second exits 0, the log shows target `cameron@…`, and the darwin machine-key guard passes;
  - every alert since each request started is recorded with its cause.
  - rosegold: not reached. It needs a window with janettesmith logged in at the console; physical presence is not needed (F72, design Risks).
  - argentum (2026-11-19, `omnigent-cameron` on magnetite), in place of rosegold, so this does not meet the clause:
    - Asleep (18:36Z, 71ec4d13): exit 5, `cameron@argentum.zt did not answer within 10 s`, no change on argentum, request `40e4fcaf7806`. It took 133 s, not ≤ 60 s, because the resolve runs before the reachability probe (F83, design Risks; `logs/cam115-e2e3-20261119T1836Z-6.3.log`).
    - Awake (18:43Z): argentum reached `jcnmknlh…`, but the request reported `rolled-back` (8). That was F84 (5.3) and nothing was rolled back (`logs/cam115-e2e3-20261119T1843Z-6.3-awake.log`).
    - Awake, after F84's fix: 5.4 step 4 (19:51Z, 3e913270) deployed with exit 0 and target `cameron@argentum.zt`. The machine-key guard was not checked separately.
- [x] 6.4 Exercise refusals live: an unmerged commit, `deploy stibnite`, `deploy electrum` and a malformed command. — verify: each exits 3 with no SSH connection from cinnabar, with a `requests.jsonl` line and a high post
  - Evidence (2026-11-19, `omnigent-cameron` on pyrite): the requests were `071b5aa7…` (an unmerged renovate head), `stibnite`, `electrum`, and two malformed targets, `magnetite;touch /tmp/cam115-canary-…` and `magnetite$(touch …)`. Each exited 3 with its own `requests.jsonl` line and a p4 post. No root login from cinnabar reached magnetite or pyrite, and no canary file exists on the worker, cinnabar or magnetite. The fleet-alerts in the window, FilesystemFillingWarn on rosegold and AlertBudgetExceeded, are unrelated (`logs/cam115-e2e2-20261119T0422Z-6.4.log`, `logs/cam115-e2e2-20261119T0427Z-6.4-probe.log`, `logs/cam115-e2e2-20261119T0427Z-6.4-malformed.log`).
  - Incident, 04:22Z: a quoting error in the test harness (a `;` inside a remote shell string) made pyrite's root shell run a real `fleet-deploy magnetite` as `omnigent-cameron` with no session. It then ran `reboot --session …` as root on pyrite, which failed only because `--session` is not a `reboot` option. The deploy was correct: request `5b74e975f92b` at 1c544d53, `bny34077…` → `sanh2m2m…`, deployed with a p3 post. It restarted magnetite's `omnigent-host-*` and home-manager units, and its window was reported so the overlapping evaluator replay pair could be redone. The harness now passes each argument through `printf %q` to `ssh … -- sudo -u …` without `-i`, and was proven with an `echo` probe first (`logs/cam115-e2e2-20261119T0426Z-incident.log`).
- [x] 6.5 In a window the operator picks, on pyrite, request a deploy and block cinnabar's mesh route to pyrite with `nft` after activation. — verify:
  - pyrite returns to the previous system within 360 s, and the request exits 8 with a high post;
  - once the route is restored, pyrite's deploy record has both lines;
  - every alert since the request started is recorded with its cause.
  - Evidence (2026-11-19, main 53f6ea2d, `omnigent-cameron` on magnetite): `fleet-deploy pyrite` resolved `i1drmgsx…` and activated it (deploy record at 19:04:31Z, previous `smwfj9zc…`).
    - During the settle, an `inet cam115block` table on pyrite dropped tcp/22 from cinnabar's tincr, ZeroTier IPv6 and IPv4 addresses.
    - The watcher returned pyrite to `smwfj9zc…`, with its record at 19:09:36Z, 305 s after activation.
    - The request exited 8 (`rolled-back`, request `8dad01a5d276`) with a p4 post.
    - Once the table was deleted, the deployer reached pyrite again, and the record has both lines.
    - No failed units and no fleet-alerts. This was the first request on #4061's code: its record keeps closure and commit (`logs/cam115-e2e3-20261119T1900Z-6.5.log`).
  - Earlier, at 04:29Z, a rollback by request and a roll forward both exited 0 (`logs/cam115-e2e2-20261119T0429Z-6.5.log`).
- [ ] 6.6 Write the operator runbook page (`packages/docs/src/content/docs/development/operations/`). It covers what a session runs, the exit statuses, adding a requester or target, revoking, and moving the deployer. — verify: the docs package builds

## 7. Close-out

- [ ] 7.1 List the provisioning conditionals and remove those that no longer apply once the host steps are done:
  - `keys == null` branches in `modules/lib/fleet-deployer.nix`, `modules/system/fleet-deploy-target.nix`, `modules/nixos/fleet-deployer.nix` and `modules/checks/sops-correspondence.nix`;
  - `deployRequestEnrolled`;
  - the `pathExists` on request public keys.

  — verify: `rg -n "keys == null|keys != null|deployRequestEnrolled|pathExists \(requestKeyFile" modules` finds only what still applies, and every machine check evaluates
