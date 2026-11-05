# Fleet dashboard behind Kanidm (CAM-73) implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a standalone Perses 0.55.1 on magnetite, packaged from the upstream release, serves `fleet-hosts` and `devloop` at `https://obs.scientistexperience.net/` to members of the Kanidm group `perses_users` through its own Kanidm client, reads the telemetry store only through two global datasources with anchored read-only endpoints, a fixed header allow-list and the `perses:ro` account, and holds no resource that is not committed; landed as three pull requests and one magnetite deploy, accepted by `cameron`'s refusal before he joins the group and his admission after (Linear CAM-73; ADR-002 reversed; ADR-002 Q9 dissolved, Q10 answered).

**Architecture:** `pkgs/by-name/perses-bin` installs the release's `perses`, `percli` and pinned plugin archives from the version, hashes and pins in its `sources.json`; `modules/nixos/perses.nix` configures nixpkgs' `services.perses` with that package on `127.0.0.1:8095`, an nginx vhost that strips `x-greptime-auth` and hides `/metrics`, the unit's credentials, envelope and failure wiring, provisioning from `modules/nixos/perses/resources/` with the database and plugin directories removed before each start, and an assertion over `flake.lib.persesServingFailures`.
`modules/nixos/kanidm.nix` adds the client `perses`, its generator and the group stub; magnetite adds `perses-encryption-key`, the restart on `perses-password` and the holder and kill-order changes.
`checks.x86_64-linux.perses-lint` lints the resources with the shipped plugins; `checks.x86_64-linux.perses-config` judges the predicate against mutants; `vmTests.x86_64-linux.perses-greptimedb` exercises the read path on demand.

**Tech Stack:** nix flakes with flake-parts and import-tree; nixpkgs' `services.perses`; Perses 0.55.1 (`perses`, `percli`) and its plugin archives; Kanidm 1.11.2 OAuth2 provisioning; clan vars generators; nginx with ACME; nspawn container tests; terranix with Cloudflare.

**Spec:** `openspec/changes/serve-the-fleet-dashboard/` — `design.md` (D1–D12, Q1–Q4 answered), `brainstorm.md` (O1–O11, the rejected embedded option), `specs/`, `tasks.md`, `proposal.md`; the plan review and the operator's decisions in `logs/cam73-evidence/1.1-plan-review-20261104T235200Z.md` (F1–F23, all applied); ADR-002 and `components/perses.md` under `docs/notes/development/observability/`.

## Global Constraints

- Repository: `$REPO` is the repository root, jj-colocated; never relocate `@`; commit each plan task as changes off `main@origin` per the repository's jj workflow; Task 2 forms pull request 1, Tasks 3 to 5 pull request 2 and Task 7 pull request 3, each landing through the merge queue before the next is enqueued.
- After creating or renaming any file, run `jj st --no-pager >/dev/null` before any `nix` command reads the tree.
- Commit messages, pull-request titles, bodies and comments carry no decision, finding, requirement or task code and no pull-request ordinal; ADR numbers, file paths, `CAM-73` and GitHub pull-request numbers are allowed.
- Before every commit run `nix fmt` and keep its log; a tree failing `nix fmt -- --fail-on-change` is not pushed.
- Evidence: `<command> 2>&1 | tee logs/cam73-evidence/<item>-<slug>-$(/bin/date -u +%Y%m%dT%H%M%SZ).log`, filters after the `tee`; `logs/` is git-ignored.
- Secrets: no agent reads, prints, logs or commits the value of `perses-password`, the Kanidm client secret or the encryption key; the operator alone runs `clan vars generate` for the two new generators; logs name files, never values.
- Remote commands run as `ssh magnetite.zt 'bash -c '"'"'…'"'"''` or with a quoted heredoc to `bash -s`, because login shells are zsh; journals are read with `sudo journalctl`.
- Nix-managed outputs are verified by `nix eval`, `nix build`, or the delivered path after activation, never by reading source; each step says which.
- Evaluation cost: every new or changed check records `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/<check>-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath` and `jq '.gc.totalBytes, .cpuTime'` against 536,870,912 B before and after; a figure over that stops the task.
- Every check leg relates two independently defined values; a relation within magnetite is an assertion, shown failing by an `extendModules` override.
- Every regulator (leg, mutant, assertion) is written before the code it judges and seen failing; every runtime clause has a negative control seen failing.
- import-tree loads every `.nix` file under `modules/` as a flake-parts module; resources, rules and mutants use `.json` and `.yaml`.
- Vendored consumer: Perses is run exactly as nixpkgs' module runs it, `perses -config=/run/perses/config.yaml -web.listen-address=127.0.0.1:8095` (NP `nixos/modules/services/monitoring/perses.nix:81-88`); `percli` is run exactly as `perses-lint` runs it, `percli lint -f <file> --plugin.path <dir> --custom-rule.path <rules>`; any probe uses those argument lists.
- Deploys: from the deploy worktree `$DEPLOY` = `$REPO/../vanixiets-worktrees/deploy`, refreshed with `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main` (created once with `git -C $REPO worktree add --detach $DEPLOY origin/main` if absent); only after `nixbot-logs queue` prints `Queue is empty`; exactly `clan machines update magnetite 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log`, run in `$DEPLOY`, with no wrapper script.
- Kanidm: no agent changes membership or logs in as a person; the operator runs `kanidm group add-members perses_users cameron` only in Task 6 Step 4, after the refusal is recorded.
- `sso-gateway` stays disabled; `openspec/changes/sso-gateway/` is not touched.
- Linear: CAM-73's transitions are the orchestrator's, per `openspec-linear-sync`; no task here touches Linear.
- Prose files keep one sentence per line.

## Interface contract

Every task uses exactly these names.

| Kind | Name | Defined in |
|---|---|---|
| Package | `pkgs.perses-bin`, version `0.55.1`, read from `pkgs/by-name/perses-bin/sources.json` (`version`, `hashes.<system>`, `plugins`); `$out/bin/{perses,percli}`; `$out/share/perses/plugins-archive/<Name>-<version>.tar.gz`; `passthru.plugins` (attrset name → version); `passthru.pluginsArchive = "${finalAttrs.finalPackage}/share/perses/plugins-archive"`; `passthru.updateScript = ./update.sh`; `meta.mainProgram = "perses"`; `null` on systems other than `x86_64-linux` and `aarch64-darwin` | Task 2 |
| App | `apps.update-perses-bin`, running `pkgs/by-name/perses-bin/update.sh` on every system | Task 2 |
| Lib | `flake.lib.persesCuratedPlugins = [ "Prometheus" "GreptimeDB" "TimeSeriesChart" "StatChart" "GaugeChart" "Table" "Markdown" ]` | Task 2 |
| Lib | `flake.lib.persesCuratedArchives pkgs perses-bin` → `linkFarm` of the curated `<Name>-<version>.tar.gz` archives, used by the lint check and by the module's `plugin.archive_paths` | Task 2 |
| Lib | `flake.lib.persesServingFailures { settings; listenAddress; port; unit; vhost; client; resources; }` → list of strings | Task 3 |
| Constants | `credsDir = "/run/credentials/perses.service"`; credential ids `kanidm-client-secret`, `encryption-key`, `perses-password`; port `8095`; domain `obs.scientistexperience.net`; project `fleet`; secret `greptimedb-perses`; datasources `greptimedb-promql`, `greptimedb-sql`; dashboards `fleet-hosts`, `devloop`; OIDC `slug_id = "kanidm"` | Tasks 3–4 |
| Module | `flake.modules.nixos.perses`, imported by magnetite | Task 4 |
| Generators | `kanidm-oauth2-perses` (file `secret`, owner `kanidm`, `0400`, `restartUnits = [ "kanidm.service" "perses.service" ]`); `perses-encryption-key` (file `key`, `0400`, `restartUnits = [ "perses.service" ]`, 32 bytes) | Task 4 |
| Checks | `checks.x86_64-linux.perses-lint` (legs `valid`, `mutants` with an expected message each, `bareLintTautological`); `checks.x86_64-linux.perses-config` (`valid`, at least one mutant per clause) | Tasks 2–3 |
| Test | `vmTests.x86_64-linux.perses-greptimedb`, with its provisioning folder `modules/vm-tests/perses-greptimedb/` (one `User`, the datasource `greptimedb-sql-open`) | Task 5 |
| Evidence | `logs/cam73-evidence/` | all |

## Task map

| Plan task | `tasks.md` items | Pull request | Deploy |
|---|---|---|---|
| Task 1: Plan review and baselines | 1.1–1.2 | planning pull request | none |
| Task 2: The package and the lint check | 2.1–2.5 | 1 | none |
| Task 3: The serving predicate and its check | 3.1–3.2 | 2 | — |
| Task 4: Resources, module, identity and DNS | 3.3–3.6 | 2 | — |
| Task 5: Container test, vars and pull request 2 | 3.7–3.9 | 2 | vars committed in it |
| Task 6: Deploy and acceptance | 4.1–4.5 | none | DNS, then magnetite |
| Task 7: Documentation and decision records | 5.1–5.3 | 3 | none |
| Task 8: Close-out and integration verification | 6.1–6.3, 7.1 | close-out pull request | none |

Rollback: a pull request removes the import of `flake.modules.nixos.perses` from magnetite, and magnetite is deployed from it; the client and group stay in Kanidm, because provisioning does not remove (`modules/nixos/kanidm.nix:201`), and the operator removes them by hand if the rollback is final; the record and vars stay committed and unused.

---

## Task files

Each task lives in its own file so that one implementer reads only its task.

- [Task 1: Plan review and baselines](plan/task-1.md)
- [Task 2: The package and the lint check](plan/task-2.md)
- [Task 3: The serving predicate and its check](plan/task-3.md)
- [Task 4: Resources, module, identity and DNS](plan/task-4.md)
- [Task 5: Container test, vars and pull request 2](plan/task-5.md)
- [Task 6: Deploy and acceptance](plan/task-6.md)
- [Task 7: Documentation and decision records](plan/task-7.md)
- [Task 8: Close-out and integration verification](plan/task-8.md)
