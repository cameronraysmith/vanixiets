# Bind mesh writes to their host (CAM-81) implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a mesh write reaches the telemetry store only when the certificate that carried it names, in its URI SAN `spiffe://vanixiets/host/<host>`, a collecting host, arrives from that host's ZeroTier address, and claims no other host in its resources, deploy records or points; magnetite pins each collecting host's neighbour entry so no member can claim another's address; and magnetite's `otel-envelope` fails on any refusal, drop or wrong entry; landed as three pull requests and two deploy rounds (Linear CAM-81).

**Architecture:** `otel-cert` gains the URI SAN on every agent host; `flake.lib.hosts` becomes the one source of every collecting host's ZeroTier address, checked against the clan vars and the controller's `allowedIps`.
On magnetite, caddy owns `[${flake.lib.hosts.magnetite.zt}]:4318`, verifies the client certificate against `otel-ca`, maps its SAN to a host and address, answers 403 on a mismatch, and forwards to the collector's `otlp/mesh` on a Unix socket only caddy and the collector can open, setting `X-Vanixiets-Host`.
`otlp/mesh` feeds only `metrics/mesh` and `logs/mesh`, whose binding filters drop a resource, deploy record or point that names another host before `forward`; networkd pins each collecting host's neighbour entry with the MAC `flake.lib.zerotierMac` computes; C6 in the ingress host's `otel-envelope` reads the filters' counters, caddy's 403 count and the live neighbour table.

**Tech Stack:** nix flakes with flake-parts and import-tree; clan-core `dbae2101` vars; nixpkgs `3a32588c` `services.caddy` (caddy 2.11.7) and systemd-networkd `[Neighbor]`; `otelcol-contrib` 0.155.0; ZeroTierOne 1.16.0; Linux 6.18.58; `writeShellApplication` over `curl`, `jq`, `awk`, `iproute2` and coreutils.

**Spec:** `openspec/changes/bind-mesh-writes-to-their-host/` — `design.md` (D1–D11, "Migration Plan", O1–O11), `specs/`, `tasks.md`, `brainstorm.md`, `proposal.md`; ADR-003 under `docs/notes/development/observability/decisions/`, the reference architecture and the `otel-collector` component.

## Global Constraints

- Repository: `$REPO` is the repository root, jj-colocated; never relocate `@`; commit each plan task as changes off `main@origin` per the repository's jj workflow; Task 2 is pull request 1, Task 4 pull request 2 and Task 7 pull request 3, each landing through the merge queue before the next is enqueued.
- No implementation commit is made before Task 1 Step 3, the gate on `stand-up-darwin-collection`'s archive, has passed (O6).
- After creating or renaming any file, run `jj st --no-pager >/dev/null` before any `nix` command reads the tree.
- Concurrent implementation subagents each get their own `git worktree add` copy, or run in sequence; no `jj workspace add` is used.
- Commit messages, pull-request titles, bodies and comments carry no decision, finding, requirement or task code and no pull-request ordinal; ADR numbers, file paths, `CAM-81` and GitHub pull-request numbers are allowed.
- Before every commit run `nix fmt` and keep its log; a tree failing `nix fmt -- --fail-on-change` is not pushed.
- Evidence: `<command> 2>&1 | tee logs/cam81-evidence/<item>-<slug>-$(date -u +%Y%m%dT%H%M%SZ).log`, filters after the `tee`; `logs/` is git-ignored; no credential value in any repository file or log.
- Commands on magnetite run as `ssh magnetite.zt 'bash -c '"'"'…'"'"''` or with a quoted heredoc to `bash -s`, because its login shell is zsh; the public path is `ssh root@magnetite.scientistexperience.net` (49.12.12.74, port 22), used only for the rollback, the restart of Task 6 Step 1 and the session Task 5 Step 3 opens; every jq filter tolerates a missing field (`// empty`, `// 0`).
- Nix-managed outputs are verified by `nix eval`, `nix build`, or the delivered path after activation, never by reading source; each step says which.
- Evaluation cost: every new or changed check records `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/<check>-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath` and `jq '.gc.totalBytes, .cpuTime'` of the stats file against 536,870,912 B before and after its task; a figure over that stops the task.
- Every check clause relates two independently defined values, named in the step before its mutant is written; a relation within magnetite is an assertion in the ingress role, shown failing by an `extendModules` override, never a check clause; each mutant runs only the case it must fail.
- Every regulator (check clause, assertion, container case) is written before the code it judges and seen failing; every runtime clause has a negative control seen failing.
- Vars: every clan vars command carries `CLAN_NO_COMMIT=1`; `clan vars generate` runs only on `otel-cert`; after every vars step the sha256 of `vars/shared/otel-ca/ca.crt/value` and of the decrypted `ntfy-alerter` token (`CLAN_NO_COMMIT=1 clan vars get magnetite ntfy-alerter/token | sha256sum`, never printed) equal the previous step's, and the step stops otherwise.
- Pins: `otelcol-contrib` 0.155.0 and caddy 2.11.7, read at `nix eval --raw .#nixosConfigurations.magnetite.pkgs.path`; vendor behaviour is read there before depending on it and cited `path:line`.
- Vendored-tool probes run the consumer's exact argument list (schema `plan` instruction): the collector unit runs `otelcol-contrib --config=file:<store path>`, read from `nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.opentelemetry-collector.serviceConfig.ExecStart`; caddy's unit runs `caddy run --config <file> --adapter caddyfile`, read the same way from `systemd.services.caddy.serviceConfig.ExecStart`; Task 1 Step 5 records each list as run.
- Store: HTTP `http://127.0.0.1:4000` on magnetite; PromQL `GET /v1/prometheus/api/v1/query` with `x-greptime-db-name`; `regulator` (`ro`) for every read, its password from a file, never on an argument list.
- Addresses: the network is `db4344343b14b903`; the ingress is `[fddb:4344:343b:14b9:399:930f:39db:40d2]:4318` = `flake.lib.hosts.magnetite.zt` = `vars/shared/zerotier-ip-magnetite-zerotier/ip/value`; magnetite's ZeroTier link was `zt554fbdjy` on 2026-11-06 and is read, not assumed.
- Deploys: from `$DEPLOY` = `$REPO/../vanixiets-worktrees/deploy`, created once with `git -C $REPO worktree add --detach $DEPLOY origin/main` and refreshed before each deploy with `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main`; magnetite, cinnabar and pyrite only after `nixbot-logs queue` prints `Queue is empty`, by exactly `clan machines update <machine> 2>&1 | tee logs/<machine>-$(date +%Y%m%d-%H%M%S).log`; stibnite by exactly `just activate 2>&1 | tee logs/stibnite-$(date +%Y%m%d-%H%M%S).log` in `$DEPLOY`, with the operator present, after `recent-activation.sh` finds no other activation within the hour.
- Every deploy or activation step ends by recording every post since its start with `logs/cam81-evidence/posts.sh <epoch>` (Task 3 Step 1), each with its cause.
- Neighbour entries: nothing outside steps marked **[operator]** changes, deletes or provokes a neighbour entry on any host, or restarts zerotierone; the pull request that installs the entries deploys only after Task 5 Step 2's MAC gate (O4).
- Linear: the orchestrator binds CAM-81 and posts its transitions per `openspec-linear-sync`; no plan step mutates Linear.
- Prose files keep one sentence per line.

## Interface contract

Every task uses exactly these names.

| Kind | Name | Defined in |
|---|---|---|
| Lib | `flake.lib.hosts.<host>.zt` for magnetite, cinnabar, pyrite, electrum, galena, scheelite and stibnite, compressed form, eight groups | Task 2 |
| Lib | `flake.lib.zerotierMac { network; address; }` → `"xx:xx:xx:xx:xx:xx"`, lower-case, in `modules/lib/zerotier-mac.nix`; `network` a 16-digit hex string, `address` an eight-group rfc4193 address | Task 2 |
| Generator | `otel-cert`'s `subjectAltName=URI:spiffe://vanixiets/host/<machine>[,IP:<zt>,DNS:magnetite.zt]`, the whole string in `validation.subjectAltNames` | Task 2 |
| Check clauses | `otel-collector-config`: `address` (mutants `addressDigitChanged`, `externalAddressDiffers`), `mac` over `modules/checks/otel-collector-config/zerotier-macs.json` (mutant `macBytesReversed`), R3.1 endpoint revised (mutants `meshTcpEndpoint`, `caddyWildcard`) | Tasks 2, 4 |
| Option | `vanixiets.otelCollector.meshIdentities : attrsOf str` (host → overlay address), default the collecting rows of `flake.lib.observabilityHosts` minus the ingress host joined with `flake.lib.hosts` | Task 4 |
| Service | `services.caddy` on the ingress host: site `https://[<zt>]:4318`, `admin 127.0.0.1:2019`, `metrics`, `MemoryMax = 128M`, `OOMScoreAdjust = 700`, `LoadCredential` `otel-cert`, `otel-key`, `restartUnits` on both | Task 4 |
| Header | `X-Vanixiets-Host`, read in OTTL as `otelcol.client.metadata["x-vanixiets-host"][0]` | Task 4 |
| Socket | `/run/otelcol-mesh/otlp.sock`, directory mode 2770, group `otelcol-mesh` (members: the collector's and caddy's accounts), collector `UMask = 0007` | Task 4 |
| Pipelines | `metrics/mesh` (`otlp/mesh` → `memory_limiter`, `filter/mesh-host-metrics` → `forward`), `logs/mesh` (`otlp/mesh` → `memory_limiter`, `filter/mesh-host-logs` → `forward`); `metrics/ingress` and `logs/ingress` receive only `forward` | Task 4 |
| Assertions | on the ingress host: `meshPipelineCoverage` (overrides `meshInIngress`, `logsMeshUnfiltered`, `tracesMeshUnfiltered`), `meshTableAgreement` (`mapLineSwapped`, `neighbourDropped`), `meshSocketGroup` (`extraSocketMember`); magnetite's kill order adds caddy (`caddyBelowPerses`) | Task 4 |
| Lib | `flake.lib.otelEnvelope` gains `binding ? null` (`{ caddyMetricsUrl; filters = [ "filter/mesh-host-metrics" "filter/mesh-host-logs" ]; neighbours = { <address> = <mac>; }; ip; }`); clause `C6 binding` | Task 4 |
| Check | `checks.x86_64-linux.otel-envelope` gains the C6 cases and mutants `c6IgnoresFilter`, `c6IgnoresRefusal`, `c6IgnoresNeighbour` | Task 4 |
| Test PKI | `flake.lib.otelTestPki` gains `id-<name>.{crt,key}` for `electrum`, `budgethost`, `cinnabar`, `v6host`, plus `nosan.{crt,key}` and `outsider.{crt,key}` | Task 4 |
| Container cases | `fleet-ingress`: `bindingMatch`, `bindingWrongAddress`, `bindingNoSan`, `bindingOutsider`, `bindingUnlisted`, `bindingHeaderForged`, `bindingHostMismatch`, `bindingRecordMismatch`, `bindingPointAttribute`, `bindingBackPressure`, `socketAccess`, `neighbourPinned` (mutant `noPinnedEntries`) | Task 4 |
| Networkd | `systemd.network.networks."09-zerotier".neighbors = [ { Address; LinkLayerAddress; } ]` on the ingress host, one per `meshIdentities` entry | Task 4 |
| Evidence | `logs/cam81-evidence/`; `window.env`, `mark.sh`, `posts.sh`, `recent-activation.sh`, `mac-gate.sh`, `survey.sh` | Tasks 1, 3, 5 |

## Task map

| Plan task | `tasks.md` items | Pull request | Deploy |
|---|---|---|---|
| Task 1: Plan review, baselines, the archive gate, rehearsal and the filter probe | 1.1–1.5 | planning pull request | none |
| Task 2: Identity and addresses | 2.1–2.5 | 1 | vars committed in it |
| Task 3: Deploying pull request 1 | 3.1–3.4 | — | magnetite, cinnabar, pyrite, then stibnite **[operator]** |
| Task 4: The binding | 4.1–4.6 | 2 | — |
| Task 5: Deploying pull request 2 | 5.1–5.5 | — | magnetite **[operator]**, after the MAC gate |
| Task 6: Acceptance | 6.1–6.5 | none | none |
| Task 7: Documentation | 7.1–7.3 | 3 | none |
| Task 8: Close-out and integration verification | 8.1–8.6, 9.1 | close-out pull request | none |

Steps marked **[operator]**: 3.3, 5.2, 5.3, 6.1, 6.2, 6.3, 6.4.
Gates: 1.3 (archive), 1.5 (vendored filter probe), 3.4 (reissued certificates in use), 5.1 (honest-attribute survey), 5.2 (MAC gate).

Rollback: a wrong pinned entry is deleted over the public path at once; reverting pull request 2 and deploying magnetite, with `--target-host root@magnetite.scientistexperience.net` if ZeroTier between stibnite and magnetite is impaired, restores `otlp/mesh` on the ZeroTier address and removes caddy and the entries; pull request 1 needs no rollback, because a SAN nothing reads is harmless.

---

## Task files

Each task lives in its own file so that one implementer reads only its task.

- [Task 1: Plan review, baselines, the archive gate, rehearsal and the filter probe](plan/task-1.md)
- [Task 2: Identity and addresses](plan/task-2.md)
- [Task 3: Deploying pull request 1](plan/task-3.md)
- [Task 4: The binding](plan/task-4.md)
- [Task 5: Deploying pull request 2](plan/task-5.md)
- [Task 6: Acceptance](plan/task-6.md)
- [Task 7: Documentation](plan/task-7.md)
- [Task 8: Close-out and integration verification](plan/task-8.md)
