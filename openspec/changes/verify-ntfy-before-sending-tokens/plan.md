# Verify ntfy.zt before sending tokens (CAM-87) implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** caddy's existing root and key become cinnabar's clan vars `caddy-root-ca`, which caddy loads, so a reinstall keeps the root every client trusts; every post to `ntfy.zt` from the fleet's code verifies the server against that root and posts nothing when it cannot; a test, a client scan, a build-time check on cinnabar, a VM test and a weekly served-root check regulate it; magnetite, cinnabar, pyrite and stibnite run it after one window (Linear CAM-87).

**Architecture:** the generator `caddy-root-ca` holds the imported `root.key` and the public `root.crt` (RV); `flake.modules.nixos.caddy-local-root` renders caddy's `pki` root from them and checks, at cinnabar's build, that caddy adapts it to those paths and that RV is the recorded root.
`ntfy-send` becomes the one client: its wrapper exports `NTFY_CACERT`, the store copy of the repository's root, and its script requires it and passes `--cacert "$NTFY_CACERT"` instead of `-k`, with the store curl on every platform; the two permission hooks post through it.
`passthru.tests.tls-verification` runs the real curl against a loopback TLS server for `ntfy.zt`, and `checks.x86_64-linux.ntfy-tls-verification` scans `modules/` and `pkgs/` for any client that skips verification and judges `flake.lib.caddyRootCheck`, which cinnabar runs weekly against the chain caddy serves.

**Tech Stack:** nix flakes with flake-parts and import-tree; clan-core `dbae2101` vars with sops; `writeShellApplication`; curl 8.22.0 and OpenSSL from the root pin; Python's `http.server` and `ssl` in the build sandbox; caddy 2.11.7's local authority on cinnabar and its `pki` global option; NixOS VM tests built on magnetite; systemd timers under `observability-notify`'s zone assertion.

**Spec:** `openspec/changes/verify-ntfy-before-sending-tokens/` — `design.md` (D1–D13, "Migration Plan"), `specs/`, `tasks.md`, `brainstorm.md` (O1–O12, C1–C5, Q1–Q7), `proposal.md`; ADR-009 under `docs/notes/development/observability/decisions/`.

## Global Constraints

- Repository: `$REPO` is the repository root, jj-colocated; never relocate `@`; commit each plan task as changes off `main@origin` per the repository's jj workflow; Task 2 is pull request 1, Task 4 pull request 2, Task 5 pull request 3 and Task 8 pull request 4, each landing through the merge queue before the next is enqueued.
- Gate: nothing in Tasks 2 to 9 starts before Task 1 Step 2 records `stand-up-darwin-collection` archived on `main@origin` (O7).
- After creating or renaming any file, run `jj st --no-pager >/dev/null` before any `nix` command reads the tree.
- Concurrent implementation subagents each get their own `git worktree add` copy, or run in sequence; no `jj workspace add` is used.
- Clan vars: every command carries `CLAN_NO_COMMIT=1`; `caddy-root-ca` is filled only by Task 2 Step 4's `clan vars set`, with the operator present; no command runs `clan vars generate` with `--regenerate` on it; its key is never printed, written to a local file or placed on an argument list, and no log holds `PRIVATE KEY`; Task 2 Step 4 runs `clan vars set` with `TMPDIR` on a RAM disk made for the step and detached after it, so clan's temporary file holding the key is on no disk, and the key exists in clear only in the memory of `ssh`, the pipe and clan.
- Commit messages, pull-request titles, bodies and comments carry no decision, question, requirement or task code and no pull-request ordinal; ADR numbers, file paths, `CAM-87` and GitHub pull-request numbers are allowed.
- Before every commit run `nix fmt` and keep its log; a tree failing `nix fmt -- --fail-on-change` is not pushed.
- Evidence: `<command> 2>&1 | tee logs/cam87-evidence/<item>-<slug>-$(/bin/date -u +%Y%m%dT%H%M%SZ).log`, filters after the `tee`; no token value in any repository file or log; a token is read only by `$(< file)` inside the command that uses it.
- Commands on magnetite, cinnabar and pyrite run as `ssh <host>.zt 'bash -c '"'"'…'"'"''` or with a quoted heredoc to `bash -s`, because their login shell is zsh; local commands on stibnite run under `/bin/bash`, with `/bin/date`, `/bin/launchctl` and `/usr/bin/sudo`; zsh scripts use `rc`, never `status`; every jq filter tolerates a missing field.
- Nix-managed outputs are verified by `nix eval`, `nix build`, or the delivered path after activation, never by reading source; each step says which.
- Builders: every `x86_64-linux` build, VM tests included, runs on magnetite with `--option builders "$(grep 930f /etc/nix/machines | head -1)"` added to the `nix build`; never on pyrite; `aarch64-darwin` builds run on stibnite.
- Evaluation cost: every new or changed check records `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/<check>-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath` and `jq '.gc.totalBytes, .cpuTime'` of the stats file against 536,870,912 B before and after its task; a figure over that stops the task.
- Every check clause relates two independently defined values, named in the step before its mutant is written; a relation within one host is a module assertion shown failing by an `extendModules` override; each mutant runs only the case it must fail.
- Every regulator (test case, check clause, leg, assertion) is written before the code it judges and seen failing; every runtime clause has a negative control seen failing.
- `ntfy-send.sh` keeps `-m 5` literal and gains no other `-m <digits>`, because `modules/nixos/fleet-alert.nix:625-634` reads the post timeout from it at evaluation (C5).
- import-tree loads every `.nix` file under `modules/` as a flake-parts module; the scanner and fixtures under `modules/checks/ntfy-tls-verification/` use other extensions, or are strings inside the check.
- Deploys: from `$DEPLOY` = `$REPO/../vanixiets-worktrees/deploy`, created once with `git -C $REPO worktree add --detach $DEPLOY origin/main` and refreshed before the window with `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main`; magnetite and cinnabar only after `nixbot-logs queue` prints `Queue is empty`, by exactly `clan machines update <machine> 2>&1 | tee logs/<machine>-$(date +%Y%m%d-%H%M%S).log`; pyrite by exactly `clan machines update pyrite --target-host root@<pyrite LAN address> 2>&1 | tee logs/pyrite-$(date +%Y%m%d-%H%M%S).log` from stibnite with the operator present; stibnite by exactly `just activate 2>&1 | tee logs/stibnite-$(date +%Y%m%d-%H%M%S).log` with the operator present, in `$DEPLOY`, or in `$REPO` when `jj diff --from main@origin --to @ --name-only` lists nothing outside `openspec/` and `logs/`, and only after `logs/cam87-evidence/recent-activation.sh` finds no other activation of stibnite since the step's previous read or within the last hour.
- Every deploy or activation step ends by recording every post since its start, as `tasks.md`'s preamble lists the sources, each with its cause.
- Reading a topic over a verified connection: `curl -s --cacert $REPO/vars/per-machine/cinnabar/caddy-root-ca/root.crt/value "https://ntfy.zt/<topic>/json?poll=1&since=<since>" | jq -c 'select(.event == "message") | {time, title, message}'`.
- Linear: the orchestrator binds CAM-87 and posts its transitions per `openspec-linear-sync`; no plan step mutates Linear.
- Prose files keep one sentence per line.

## Grounding

The consumer here is curl, run by `ntfy-send`; the argument lists below are read from the script as Task 2 leaves it, and Task 1 Step 4 and Task 4 Step 2 probe with exactly these lists before any deploy.

- With a token: stdin `Authorization: Bearer <token>\n`; argv `curl -sf --cacert <NTFY_CACERT> -m 5 -H @- <caller args…> -d <message> https://ntfy.zt/<topic>`.
- Without a token: argv `curl -sf --cacert <NTFY_CACERT> -m 5 <caller args…> -d <message> https://ntfy.zt/<topic>`.
- `NTFY_CACERT` in the built wrapper: the store copy of `vars/per-machine/cinnabar/caddy-root-ca/root.crt/value`; `NTFY_CURL_BIN`: `curl`, resolved through the wrapper's `PATH` to the root pin's curl 8.22.0 on both `x86_64-linux` and `aarch64-darwin`.
- curl's `--cacert` and `-k` semantics: `curl/curl@curl-8_22_0:docs/cmdline-opts/cacert.md`, `insecure.md`; observed on stibnite in `logs/s5-evidence/7.3-ntfy-curl-proof-20261106T220636Z.log` (A80, A82).
- caddy's storage path on cinnabar: `/var/lib/caddy/.local/share/caddy/pki/authorities/local/{root,intermediate}.{crt,key}`, `services.caddy.dataDir` being `/var/lib/caddy`; the consumer of the vars is caddy, whose argument list is the adapted `pki` block `apps.pki.certificate_authorities.local.root.{certificate,private_key}` read with `pem_file` (`caddyserver/caddy@v2.11.7:caddyconfig/httpcaddyfile/pkiapp.go:32-55`, `:126-153`; `modules/caddypki/crypto.go:73-118`); its root handling: `ca.go:150-175`, `:277-315`, `:345-375`, `:472-478`, `maintain.go:68-100`, `certificates.go:26-31` (A79).
- The import's consumer is `clan vars set <machine> <generator>/<file>`, reading stdin to its end (`clan-core@dbae2101:pkgs/clan-cli/clan_lib/vars/set.py:59-72`); Task 1 Step 4 rehearses the comparisons of Task 2 Step 4, and the import itself is the operator's step.

## Interface contract

Every task uses exactly these names.

| Kind | Name | Defined in |
|---|---|---|
| Generator | cinnabar `clan.core.vars.generators.caddy-root-ca`: `files."root.key"` (secret, `owner`/`group` `caddy`, `mode = "0400"`, `restartUnits = [ "caddy.service" ]`, path `/run/secrets/vars/per-machine/cinnabar/caddy-root-ca/root.key`), `files."root.crt"` (`secret = false`, RV), `script` only fails | Task 2 |
| Module | `flake.modules.nixos.caddy-local-root` (`modules/nixos/caddy-local-root.nix`): options `vanixiets.caddyLocalRoot.certFile`, `keyFile`, `fingerprint`; the `pki { ca local { root { cert key } } }` global option; `system.checks` `caddy-root-from-vars` with clauses `configured root` and `recorded root`; overrides `pkiDropped`, `fingerprintOther` | Task 2 |
| VM test | `vmTests.x86_64-linux.caddy-root-from-vars` (`modules/vm-tests/caddy-root-from-vars.nix`): nodes `restored`, `minting`, `client` | Task 2 |
| Package | `ntfy-send` (`pkgs/by-name/ntfy-send/package.nix`) takes `caddyRootCa ? ../../../vars/per-machine/cinnabar/caddy-root-ca/root.crt/value`; `runtimeInputs = [ curl ]`; preamble `export NTFY_CURL_BIN=curl` and `export NTFY_CACERT=${caddyRootCa}`; `passthru.tests = { token-transport; tls-verification; }` | Task 4 |
| Script | `ntfy-send.sh`: `: "${NTFY_CACERT:?ntfy-send: NTFY_CACERT names no CA file}"` after `--help`, then `"${NTFY_CURL_BIN:-curl}" -sf --cacert "$NTFY_CACERT" -m 5 …`; `--help` documents `NTFY_CACERT` | Task 4 |
| Test | `passthru.tests.tls-verification` (`test-tls-verification.nix`, argument `ntfySend`): cases `foreignRefusedSource`, `foreignRefusedBuilt`, `ownAccepted`, `bundleAccepted`; mutant `insecure`; prints `ok: <case>` and `mutant insecure rejected`; `passthru.tests.token-transport` (`test-token-transport.nix`) gains cases `caUnset` and `caEmpty` and mutant `cacertGuardDropped`, run only on `caEmpty` | Task 4 |
| Check | `checks.<system>.package-ntfy-send-test-tls-verification`, declared in `modules/checks/package-tests.nix` | Task 4 |
| Hooks | `notify-permission-prompt` and `notify-permission-wait` call `ntfy-send "$MESSAGE" "$NTFY_TOPIC" -H "Title: Permission: ${TOOL_NAME}" -H "Priority: default" -H "Tags: lock,${REPO_NAME}"`; `runtimeInputs` hold `pkgs.ntfy-send`, not `curl`; `gate-dangerous-commands` adds `pkgs.ntfy-send` | Task 4 |
| Check | `checks.x86_64-linux.ntfy-tls-verification` at `modules/checks/ntfy-tls-verification.nix`, scanner `modules/checks/ntfy-tls-verification/scan.bash`; clauses `A`, `B`, `C`; mutants `insecureShort`, `insecureCluster`, `insecureLong`, `insecureContinued`, `clientMissing`, `cacertDropped`, `undeclaredClient` (Task 4); legs `servedHeld`, `servedInOverlap`, `servedDrifted`, `rootExpiring`, mutants `verificationSkipped`, `expirySkipped` (Task 5) | Tasks 4, 5 |
| Lib | `flake.lib.caddyRootCheck pkgs { bundle; connect; servername; minRemainingSec ? 15552000; }` → `writeShellApplication` `caddy-root-check` over `openssl`, `coreutils`, `gawk`; messages `caddy-root-check: the chain served for <servername> does not verify against <bundle>`, `caddy-root-check: caddy's root expires <notAfter>, within <days> days`, and on success `caddy-root-check: served chain verifies against root <fp>, expires <notAfter>` | Task 5 |
| Units | cinnabar: `caddy-root-check.service` (oneshot, `DynamicUser`, after `caddy.service`, `bundle` RV's store path, `connect` `ntfy.zt:443`), `caddy-root-check.timer` (`Mon *-*-* 14:00:00 UTC`, `Persistent = true`); `flake.lib.observabilityHosts.cinnabar.notifiedUnits` gains `"caddy-root-check"` | Task 5 |
| Evidence | `logs/cam87-evidence/`; `window.env` holds `CINNABAR_SWITCH_EPOCH`, `WINDOW_START_EPOCH` and each host's `<HOST>_DEPLOY_EPOCH` from `/bin/date -u +%s`; `recent-activation.sh` guards stibnite's activation; `read-posts.sh <since-epoch>` prints every post from the sources of `tasks.md`'s preamble | Tasks 1, 3, 6 |

## Task map

| Plan task | `tasks.md` items | Pull request | Deploy |
|---|---|---|---|
| Task 1: Plan review, gate, baselines and rehearsal | 1.1–1.4 | planning pull request | none |
| Task 2: caddy's root as clan vars | 2.1–2.7, 2.4 **[operator]** | 1 | vars committed in it |
| Task 3: cinnabar's switch to the vars | 3.1 | — | cinnabar alone |
| Task 4: The verifying client | 4.1–4.7 | 2 | — |
| Task 5: cinnabar's served-root check | 5.1–5.4 | 3 | — |
| Task 6: The deploy window | 6.1–6.7 | — | magnetite, cinnabar, then pyrite **[operator]**, then stibnite **[operator]** |
| Task 7: Acceptance | 7.1–7.5 | none | none |
| Task 8: Documentation | 8.1–8.3 | 4 | none |
| Task 9: Close-out and integration verification | 9.1–9.6, 10.1, and §11 for applied review findings | close-out pull request | none |

Steps marked **[operator]**: 2.4, 6.1, 6.5, 6.6, 7.2.

Rollback: before the window, reverting pull request 1 and deploying cinnabar returns caddy to the same root in its storage; after it, revert pull request 3 and then pull request 2, and deploy magnetite, cinnabar, pyrite and stibnite in the window's order; the reverted client posts with `-k` again.
If magnetite's heartbeats stop after its deploy, the window stops at once and the revert deploys magnetite alone.
The imported vars stay committed through any rollback.

---

## Task files

Each task lives in its own file so that one implementer reads only its task.

- [Task 1: Plan review, gate, baselines and rehearsal](plan/task-1.md)
- [Task 2: caddy's root as clan vars](plan/task-2.md)
- [Task 3: cinnabar's switch to the vars](plan/task-3.md)
- [Task 4: The verifying client](plan/task-4.md)
- [Task 5: cinnabar's served-root check](plan/task-5.md)
- [Task 6: The deploy window](plan/task-6.md)
- [Task 7: Acceptance](plan/task-7.md)
- [Task 8: Documentation](plan/task-8.md)
- [Task 9: Close-out and integration verification](plan/task-9.md)
