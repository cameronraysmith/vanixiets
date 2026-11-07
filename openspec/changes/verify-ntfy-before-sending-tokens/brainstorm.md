# Brainstorm: verify ntfy.zt's certificate before sending a token to it (CAM-87)

## Background

Every client of `ntfy.zt` posts with curl's `-k`, so it sends whatever it carries, the shared `alerter` token included, to whoever completes a TLS handshake for that name.
The reader of this file is the implementer and reviewer of CAM-87, who knows the fleet's alert path from ADR-009 but has not read the grounding below.
Classification under `skill://brainstorming`: a security fix with a fleet-wide deployment, because the one changed package sits in every host's closure and the fix fails closed: a client that cannot verify posts nothing.

Abbreviations used below: A9 is `docs/notes/development/observability/decisions/ADR-009-alerting.md`, CH is `docs/notes/development/observability/charter.md`, FC is `docs/notes/development/observability/components/fleet-alert.md` and RA is `docs/notes/development/observability/architecture/reference-architecture.md`.
NS is `pkgs/by-name/ntfy-send/ntfy-send.sh`, NP is `pkgs/by-name/ntfy-send/package.nix`, TT is `pkgs/by-name/ntfy-send/test-token-transport.nix`, HK is `modules/home/tools/hooks/`, FA is `modules/nixos/fleet-alert.nix`, ZT is `modules/darwin/zt-services-trust.nix` and CR is `modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt`.
RB is the operator runbook `packages/docs/src/content/docs/development/operations/fleet-observability.md`.
Upstream sources are cited at this repository's pins: caddy `v2.11.7` (cinnabar's `services.caddy.package`) and curl `8.22.0` (`pkgs.curl` of both cinnabar and stibnite).

Inputs gathered on 2026-11-06:

- `linear issue view CAM-87` and its comment of 2026-11-06 fixing the order: after CAM-72 archives and before CAM-81.
- The repository at `main@origin` `f70d1a0aca0c`: every file under `modules/` and `pkgs/` that names `ntfy.zt`, the checks that read `ntfy-send`, and the evaluated configurations of all ten hosts.
- caddy's PKI code at `v2.11.7` and the root it stores on cinnabar, read without change.
- `logs/s5-evidence/7.3-ntfy-curl-proof-20261106T220636Z.log`, recorded on stibnite for CAM-72.

## Status of the decisions

The operator made O1 to O7 on 2026-11-06, in assigning this plan and in CAM-87's comment, and O8 to O12 on 2026-11-07 ("Second round" below).
Decisions that follow from them or from the evidence are the orchestrator's, marked D1 to D9; each question Q1 to Q6 carries a recommendation for the operator at task 1.1.

- Decision (O1, operator, 2026-11-06): every `ntfy.zt` client drops `-k` and `--insecure` and passes caddy's root explicitly with `--cacert`, on Linux and darwin alike, so no client depends on a system or keychain trust store.
- Decision (O2, operator, 2026-11-06): darwin's `ntfy-send` uses the store curl instead of `/usr/bin/curl`.
- Decision (O3, operator, 2026-11-06): `ntfy-send`'s `--help` stops claiming that endpoint security blocks store binaries from ZeroTier.
- Decision (O4, operator, 2026-11-06): a flake check fails if any `ntfy.zt` client passes `-k` or `--insecure`, within the 536,870,912 B evaluation budget and with a static attribute name, and a test shows a server presenting a certificate from another CA refused while caddy's root is accepted.
- Decision (O5, operator, 2026-11-06): the plan covers caddy's root rotating before 2035-12-06, with one source the clients read and an expiry warning if it is cheap.
- Decision (O6, operator, 2026-11-06): one coordinated deploy window covers every host whose closure changes and that runs, with every post read afterwards and the deploy-record checks of CAM-72; magnetite and cinnabar deploy from the deploy worktree, pyrite over its LAN address with the operator present, and stibnite by the operator's `just activate`.
- Decision (O7, operator, 2026-11-06): implementation starts only after `stand-up-darwin-collection` archives, and lands before CAM-81.

## Found while preparing

### The clients

Three scripts post to `ntfy.zt`, all with `-k`, and nothing else under `modules/` or `pkgs/` does.

| Client | Where it posts from | Token | Lines |
|---|---|---|---|
| `ntfy-send` | magnetite's evaluator and notifier, cinnabar's dead-man and notifier, pyrite's notifier, stibnite's envelope wrapper, `gate-dangerous-commands`, and the home `tools` command on every host | `alerter` through `NTFY_TOKEN_FILE` for `fleet-*`, otherwise anonymous | NS:44, NS:47 |
| `notify-permission-prompt` | the Claude Code permission hook on every host with the home `tools` module | none; the host's own topic | `HK/notify-permission-prompt.sh:45` |
| `notify-permission-wait` | the gate hooks before they ask, on the same hosts | none; the host's own topic | `HK/notify-permission-wait.sh:17` |

The two hooks carry no token, but their messages carry the command or file path an agent is waiting to use, which an impostor answering for `ntfy.zt` would read.
`gate-dangerous-commands` already posts through `ntfy-send` from `PATH` (`HK/gate-dangerous-commands.sh:183`), without `ntfy-send` among its `runtimeInputs` (`HK/default.nix:158-166`).

Other files name `ntfy.zt` and call curl without being clients: cinnabar's dnsmasq record and its ZeroTier controller calls (`modules/machines/nixos/cinnabar/zt-dns.nix:35-36`, `:76`, `:101`), the dead-man's probe and poll on ntfy's own listener over HTTP (FA:509-517), and the HTTP gate's list of auto-approved hosts (`HK/default.nix:17-19`).

### Contradictions with the issue and the decision records

- C1: CAM-87 says cinnabar's `fleet-deadman` is not affected because it uses ntfy's local listener without TLS.
  Its probe and poll do (FA:509-517), but it posts `AlertEvaluatorSilent` through `ntfy-send` to `https://ntfy.zt` (FA:555), as cinnabar's notifier does, so cinnabar is a client and is in the window.
  cinnabar resolves `ntfy.zt` through its own dnsmasq to its own ZeroTier address, so its posts are unlikely to cross another member, but it runs the same `ntfy-send` and verifies like every other host.
- C2: A9:205 says trusting caddy's root would need the certificate distributed to magnetite, which no caller does.
  The root is not secret and is already in the repository (CR), so a store path in `ntfy-send`'s closure distributes it with every deploy; no distribution step is needed.
- C3: NS:23-25 and NP:5-15 say darwin's endpoint security blocks store binaries from TCP over ZeroTier.
  World assumption A65 records the store-built collector reaching the ingress from stibnite, and on 2026-11-06 the store curl reached `https://ntfy.zt/v1/health` as `_otelcol` with HTTP 200 and verification result 0 (`logs/s5-evidence/7.3-ntfy-curl-proof-20261106T220636Z.log`).
- C4: CAM-87 says `zt-services-trust.nix` already installs the root on darwin (ZT:7-13).
  It does, into the System keychain and nix-darwin's bundle, but the same log shows the store curl as `_otelcol` refusing `ntfy.zt` with exit 60 when no `--cacert` is given, so that installation does not reach the store curl in a launchd job; an explicit `--cacert` is what makes the client verify, as O1 requires.
- C5: regulator R9.5 reads `ntfy-send`'s post timeout at evaluation from NS with the pattern `-m ([0-9]+)` (FA:625-634).
  The edit keeps `-m 5` literal and adds no other `-m <digits>`, or magnetite's evaluation would compute a different timeout.

### caddy's root

- cinnabar's caddy stores its root at `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`, written 2026-01-27T14:29:17Z, owner `caddy`, mode `0600`, on cinnabar's ZFS root dataset; its sha256 fingerprint `7E:78:F6:7C:83:BD:DC:81:51:FF:EB:8F:82:1A:68:5D:02:89:9F:93:27:33:7F:9B:F2:41:9B:F9:3B:AA:2E:82` equals CR's, read on 2026-11-06.
- CR is `CN=Caddy Local Authority - 2026 ECC Root`, valid from 2026-01-27T14:29:17Z to 2035-12-06T14:29:17Z, 3600 days, which is caddy's default root lifetime (`caddyserver/caddy@v2.11.7:modules/caddypki/ca.go:475`).
- caddy never renews its root: within the last 20% of the root's lifetime it logs `root certificate expiring soon (FIXME: ROOT RENEWAL NOT YET IMPLEMENTED)` every 10 minutes and does nothing else (`modules/caddypki/maintain.go:68-76`, `ca.go:477-478`), which for this root starts at 2033-12-16T14:29:17Z.
- caddy generates a new root, with a new key and the common name `Caddy Local Authority - <year> ECC Root`, only when `root.crt` is missing from its storage (`ca.go:277-293`, `:472`); otherwise it loads the stored one, so losing cinnabar's `/var/lib/caddy` changes the root.
- caddy refuses to start its CA once the root's remaining lifetime is shorter than the 7-day intermediate lifetime (`ca.go:170-173`, `:476`), so from 2035-11-29 `ntfy.zt` stops serving a certificate at all.
- The root's key exists only in that storage; the repository holds the certificate alone.

### Closures

Every evaluated host configuration contains `ntfy-send`'s derivation, so every host's closure changes; this was read from `nix-store -qR` of each `system.build.toplevel.drvPath` at a tree equal to `main@origin` `f70d1a0aca0c` outside `openspec/` and `logs/`.

| Host | Holds the `alerter` token | What posts from it | Running |
|---|---|---|---|
| magnetite | yes | evaluator, heartbeat, notifier, hooks | yes |
| cinnabar | yes | dead-man, notifier, hooks | yes |
| pyrite | yes | notifier, hooks | yes |
| stibnite | yes, owned by `_otelcol` | envelope wrapper, hooks | yes, the operator's laptop |
| electrum, galena, scheelite | yes | notifier, hooks | no: `enabled = false` in `modules/terranix/hetzner.nix:18` and `modules/terranix/gcp.nix:32`, `:40` |
| argentum, blackphos, rosegold | no | hooks and the `tools` command, anonymously | yes, other users' laptops, outside the operator's activations (ADR-003 Q3) |

### What a verified post rests on

With `--cacert` naming one file, curl accepts a server only if its chain ends at a certificate in that file, and ignores the system bundle and the keychain; the log above shows exit 60 both without `--cacert` and with `otel-ca`'s certificate as the CA.
A file holding two roots accepts a chain to either, which is what lets a rotation overlap old and new.
`ntfy-send` passes extra arguments to curl before the URL (NS:44, :47), so a test can point `ntfy.zt` at a loopback server with `--connect-to` and exercise the real curl, the real script and the real root without binding port 443.

## Decision chain

- D1 (orchestrator): CR stays where it is and is the one source of caddy's root; `ntfy-send`'s package reads it by path and exports it as `NTFY_CACERT` in the wrapper's preamble, as it exports `NTFY_CURL_BIN` today, and the script requires it and passes `--cacert "$NTFY_CACERT"`, so a script run without it fails before curl rather than posting unverified.
  ZT already reads the same file, so a rotation edits one file and every reader follows.
  Alternative: a `flake.lib` attribute naming the path; rejected, because a `pkgs/by-name` package cannot read `flake.lib`, and a name for a path adds nothing a path does not give.
- D2 (orchestrator, O2): `ntfy-send` takes curl from `runtimeInputs` on every platform, and `NTFY_CURL_BIN` is `curl` everywhere; the darwin branch and its comment go.
- D3 (orchestrator, Q1): the two permission hooks post through `ntfy-send` with the same topic, headers, timeout and best-effort exit, and their `runtimeInputs` swap `curl` for `pkgs.ntfy-send`; `gate-dangerous-commands` gains `pkgs.ntfy-send` too.
  Then exactly one script reaches `ntfy.zt`, and the verifying test covers every client.
  Alternative: add `--cacert` to each hook's own curl; rejected, because it keeps three copies of the flags and of the root's path.
- D4 (orchestrator, O4): a new `passthru.tests.tls-verification` runs the real curl and the script against a loopback TLS server for `ntfy.zt` whose certificate comes from a CA made in the sandbox: refused with exit 60 under CR, by the source script and by the built wrapper, with nothing received; accepted under that CA, and under a bundle of CR and that CA; and refused before curl with `NTFY_CACERT` unset.
  A mutant replacing `--cacert` with `-k` runs only the refusal case and must be accepted, so the test rejects it.
  CR's own acceptance cannot be shown in a sandbox, since caddy's key is on cinnabar; the rehearsal before the window and every deployed post show it.
- D5 (orchestrator, O4): `checks.x86_64-linux.ntfy-tls-verification`, a static name, scans every `.sh`, `.bash`, `.nix`, `.py`, `.ts` and `.js` file under `modules/` and `pkgs/`: in a file naming `ntfy.zt`, no curl or wget command line, continuation lines joined, carries `-k`, `--insecure` or a short-option cluster containing `k`; every declared client exists and passes `--cacert`; and every file naming `ntfy.zt` and calling curl or wget is a declared client or a declared non-client with its reason.
  Each clause has a mutant tree that runs only that clause.
- D6 (orchestrator, Q2, O5): cinnabar runs `caddy-root-check` weekly, a oneshot that fails, and so posts a failure notice through the existing notifier, when the root caddy has stored is not among CR's certificates or expires within 180 days.
  The second condition warns from 2035-06-09, while the root still works and the notice can still be delivered.
- D7 (orchestrator, O5): rotation is a procedure in RB, not code in this change: generate the new root, add it to CR beside the old one, deploy every client, switch caddy's storage to the new root, then remove the old one and deploy again.
- D8 (orchestrator, O6): the window deploys magnetite, then cinnabar, then pyrite, then stibnite, after pull requests 1 and 2 merge; electrum, galena and scheelite take the change at their next install, and argentum, blackphos and rosegold at their users' next activation.
  magnetite goes first because cinnabar's `notifiedUnits` gains `caddy-root-check`, whose exclusion from `SystemdUnitFailed` magnetite's evaluator reads from the host table, and because its minutely heartbeat is the fastest live evidence that the new client is accepted.
- D9 (orchestrator): the decision records are amended in place under charter v30, which this change takes because it lands before CAM-81 (Q3).

## Questions for the operator

- Q1: Route the two permission hooks through `ntfy-send` (D3)? Recommended: yes; one client, one test, and the hooks' behaviour is otherwise unchanged.
- Q2: Add the weekly `caddy-root-check` on cinnabar, failing at 180 days before expiry or when caddy's stored root is not in CR (D6)? Recommended: yes; it costs one oneshot, one timer and one row in cinnabar's `notifiedUnits`, and it names the cause on cinnabar when a lost `/var/lib/caddy` changes the root, a failure whose notice cannot itself be delivered but whose outage the watch service's email reports.
  Alternative: a Linear issue due 2035-05; rejected as a reminder nine years out that nothing checks.
- Q3: This change takes charter v30 and world assumptions A78 to A82; CAM-81's planned v30 becomes v31, and its copy of the designation table is rebased onto this change's two rows before it archives? Recommended: yes, since this change lands first.
- Q4: electrum, galena and scheelite, which are not provisioned, and argentum, blackphos and rosegold, which their users activate, stay outside the window? Recommended: yes; none of the six holds a running copy of the `alerter` token, and each picks up the change at its next install or activation.
- Q5: The scan covers `modules/` and `pkgs/` only, and the runbook's `curl -sk` commands (RB:190) are corrected by hand in the documentation pull request? Recommended: yes; documentation and archived plans hold historical commands that are not clients.
- Q6 (superseded on 2026-11-07 by O8 to O12): caddy's root key lives only on cinnabar's disk, so a reinstall of cinnabar changes the root and every post fails until CR is updated and every host deploys, which the watch service reports within 15 to 20 minutes; accept that for this change and open a follow-up to declare the root and key as a clan var that caddy loads? Recommended: yes; the follow-up changes cinnabar's caddy configuration and secrets, which this change does not otherwise touch.

## Second round (2026-11-07)

The operator decided Q1 to Q5 as recommended and replaced Q6 on 2026-11-07, relayed by the orchestrator; Q6's deferral is withdrawn, and caddy's root becomes clan vars in this change.

- Decision (O8, operator, 2026-11-07): caddy's local root becomes clan vars on cinnabar, importing the existing root and key rather than minting new ones, because every client trusts the existing root, the operator's Android phone included, where it was installed by hand.
- Decision (O9, operator, 2026-11-07): a per-machine generator `caddy-root-ca` holds `root.key`, secret, read on cinnabar only, and `root.crt`, a public value; a one-time import from caddy's data directory, made with `CLAN_NO_COMMIT=1` and gated on the operator, fills them, and no `--regenerate` runs without the operator.
- Decision (O10, operator, 2026-11-07): caddy loads its root from the vars' paths, so a reinstall restores the same root; a check asserts that caddy's configured root is the var and that the var's fingerprint equals the live root's recorded fingerprint.
- Decision (O11, operator, 2026-11-07): the var's public value replaces `modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt` as the one source every reader uses, and the security trade-off of moving the key into the encrypted repository is stated.
- Decision (O12, operator, 2026-11-07): the import precedes the caddy change, the restart is verified by fingerprint before and after, and a reissued intermediate is acceptable.

### Found in the second round

- caddy 2.11.7's Caddyfile takes `pki { ca [<id>] { root { cert <path> key <path> format <format> } } }`, with `local` as the default id and `pem_file` as the default format (`caddyconfig/httpcaddyfile/pkiapp.go:32-55`, `:126-153`; `modules/caddypki/crypto.go:73-85`).
- With `root` configured, caddy loads it with `KeyPair.Load`, which refuses a key that does not match the first certificate (`crypto.go:91-118`), and never calls `loadOrGenRoot`'s generation branch or the root-expiry warning, both of which run only when `ca.Root == nil` (`ca.go:150-162`, `maintain.go:68-76`).
- Intermediates come from the configured root: at provisioning `loadOrGenIntermediate` loads a stored intermediate or issues one from the configured root (`ca.go:175`, `:345-375`), and maintenance renews it every 10 minutes' check through `loadOrGenRoot`, which re-reads the configured files when `ca.Root != nil` (`maintain.go:78-100`, `ca.go:277-284`).
  A stored intermediate is loaded without checking which root signed it, so a rotation must remove it; today's was signed by the key being imported, so it stays valid.
- clan-core at `dbae2101`: `clan vars set <machine> <generator>/<file>` reads a non-terminal stdin to its end and stores the value through the file's secret or public store (`pkgs/clan-cli/clan_lib/vars/set.py:38-72`), honouring `CLAN_NO_COMMIT`; a generator with no `validation` and no stored hash counts as current when its files exist (`_types.py:400-409`, `generator.py:443-459`), so an imported generator is not regenerated by `clan vars generate` or `clan machines update`.
- cinnabar's per-machine secrets are encrypted to cinnabar and the sops user `cameron` (`vars/per-machine/cinnabar/otel-cert/key.pem/machines/`, `users/`), and deploy under `/run/secrets/vars/per-machine/cinnabar/<generator>/<file>`; a public file's `path` is a store path (evaluated for `otel-cert` on 2026-11-07).
- With caddy's root configured, the stored `root.crt` is unused, so the first plan's weekly comparison of it with the repository would judge a file nothing serves; the check now verifies the chain caddy serves.

### Decision chain, second round

- D10 (orchestrator, O8, O9): the generator `caddy-root-ca` declares both files and a script that only fails, so no command can mint a root; the import uses `clan vars set` reading `ssh cinnabar.zt 'sudo cat …'` on stdin, so the key never lands in a local file.
- D11 (orchestrator, O10): caddy's `pki` block names the vars' paths; cinnabar's `system.checks` gains `caddy-root-from-vars`, which adapts the rendered Caddyfile with caddy itself and compares the root paths with the vars', and compares RV's fingerprint with the recorded one, held in an option so an `extendModules` override shows each clause failing; a NixOS VM test shows a caddy with empty storage serving under a configured root.
- D12 (orchestrator, O9, O12): the import is an operator-gated step in pull request 1, before caddy's `pki` block is added; cinnabar then deploys alone, with the served chain verified against RV before and after.
- D13 (orchestrator, O11): RV replaces CR for `ntfy-send`, ZT and the weekly check; CR is removed in pull request 1; the weekly check verifies the served chain against RV instead of comparing stored files (D6 revised); rotation becomes a sequence of `clan vars set` steps (D7 revised).
- Q7 (new; decided by the operator on 2026-11-07 as recommended, keep the stored key): whether to remove the unused `root.key` from caddy's storage after a week; recommended no, because without the `pki` option caddy would mint a root if none were stored.
- Q2 and Q3 as decided read with this round's changes: the weekly check verifies the served chain against the var rather than comparing caddy's stored root with CR, and the change takes world assumptions A78 to A83.
