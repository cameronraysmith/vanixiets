## Context

Every client of `https://ntfy.zt` runs curl with `-k`, so it hands the shared `alerter` token and its message to whoever completes a TLS handshake for that name (Linear CAM-87).
A mesh member that redirects another host's traffic for cinnabar's address (CAM-86) would collect the token and could then post or suppress fleet alerts.
`brainstorm.md` (BS) records the grounding, the contradictions C1 to C5, the operator's decisions O1 to O12 of 2026-11-06 and 2026-11-07 and the orchestrator's D1 to D13 with the questions Q1 to Q7; this document develops them.

Citation keys are BS's: A9 is ADR-009, CH the charter, FC the `fleet-alert` component, RA the reference architecture and RB the operator runbook; NS, NP and TT are `ntfy-send.sh`, `package.nix` and `test-token-transport.nix` under `pkgs/by-name/ntfy-send/`; HK is `modules/home/tools/hooks/`, FA is `modules/nixos/fleet-alert.nix`, ZT is `modules/darwin/zt-services-trust.nix` and CR is `modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt`, the repository's copy of caddy's root before this change.
RV is `vars/per-machine/cinnabar/caddy-root-ca/root.crt/value`, the public value of the generator this change adds, which replaces CR.
caddy is cited at `caddyserver/caddy@v2.11.7`, curl at 8.22.0 and clan-core at the root pin `dbae2101`.

The current state, at `main@origin` `f70d1a0aca0c`:

- Three scripts post to `ntfy.zt`, `ntfy-send` (NS:44, :47) and the hooks `notify-permission-prompt` and `notify-permission-wait` (`HK/notify-permission-prompt.sh:45`, `HK/notify-permission-wait.sh:17`), all with `-sfk -m 5`.
- `ntfy-send` posts for magnetite's evaluator, heartbeat and notifier, cinnabar's dead-man and notifier, pyrite's notifier, stibnite's envelope wrapper and `gate-dangerous-commands`, and is the home `tools` command on every host (BS "The clients"; C1).
- darwin's `ntfy-send` runs `/usr/bin/curl` (NP:33-35) on the strength of a note that endpoint security blocks store binaries from ZeroTier, which C3 refutes.
- caddy on cinnabar generated its root on 2026-01-27 into `/var/lib/caddy/.local/share/caddy/pki/authorities/local/`, and its key exists nowhere else; CR equals that root by sha256 fingerprint, read on 2026-11-06 (BS "caddy's root").
- caddy's Caddyfile on cinnabar has no `pki` global option, so caddy loads its root from storage, and would generate a new one with a new key if storage were lost (A79).
- R9.5 reads `ntfy-send`'s post timeout from NS at evaluation (FA:625-634; C5).
- Every one of the ten host configurations contains `ntfy-send`'s derivation (BS "Closures").

Constraints carried from the archived slices and the schema:

- Each check states the 536,870,912 B evaluation budget, measured with `NIX_SHOW_STATS=1 nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath`; attribute names come from static data only; relations within one host are module assertions or build-time checks of that host.
- Each new clause names its two independently defined value sources before its mutant is written, and each mutant runs only the case it must fail.
- Every regulator is seen failing before the code it judges exists, and every runtime clause has a negative control.
- A deploy's verification reads every post since the deploy started and records each with its cause.
- Every clan vars command carries `CLAN_NO_COMMIT=1`, and no command regenerates a var without the operator.

Stakeholders are the operator, who receives every alert and permission notice and whose phone trusts caddy's root by hand, the users of argentum, blackphos and rosegold, whose hooks post to their own topics, and CAM-81, which plans next against the same decision records.

## Goals / Non-Goals

**Goals:**

- caddy's existing root and key become the clan vars `caddy-root-ca` on cinnabar, imported unchanged, and caddy loads its root from them, so a reinstall of cinnabar restores the same root that every client, the operator's phone included, already trusts.
- The generator's public value is the one source of caddy's root for every reader.
- Every post to `ntfy.zt` from the fleet's code verifies the server against that root, on Linux and darwin, and posts nothing when it cannot.
- A test shows a server with a certificate from another CA refused and a server under a trusted root accepted, with a mutant restoring `-k` rejected.
- A flake check fails if any client under `modules/` or `pkgs/` passes `-k` or `--insecure`, or if a new client appears undeclared; cinnabar's build fails if caddy's configured root is not the var or the var is not the recorded root.
- The operator is warned 180 days before caddy's root expires, and the runbook states how to rotate it without a gap.
- magnetite, cinnabar, pyrite and stibnite run the verifying client after one window, with every post in it explained.

**Non-Goals:**

- Minting a new root; the root, its key and its expiry stay as they are.
- Changing ntfy, the access entries, the `alerter` token or its readers, or caddy's sites.
- Protecting delivery: a member answering for cinnabar can still drop posts, which the dead-man and the external watch already report.
- Verifying other `.zt` services or the runbook's `-k` probe of the ingress, which is not an `ntfy.zt` client.
- Activating argentum, blackphos or rosegold, or provisioning electrum, galena or scheelite (Q4).

## Decisions

### Layout

| File | Change |
|---|---|
| `modules/nixos/caddy-local-root.nix` | new: `flake.modules.nixos.caddy-local-root`, options `vanixiets.caddyLocalRoot.{certFile,keyFile,fingerprint}`, caddy's `pki` global option from them and the build-time check `caddy-root-from-vars` (D11) |
| `modules/machines/nixos/cinnabar/caddy-root-ca.nix` | new: the generator `caddy-root-ca`, the import of `caddy-local-root` with the vars' paths and the recorded fingerprint (D10, D11) |
| `modules/vm-tests/caddy-root-from-vars.nix` | new: the reinstall test of D11 |
| `vars/per-machine/cinnabar/caddy-root-ca/` | new: `root.key` (secret, reader cinnabar and the sops users), `root.crt/value` (public), imported (D12) |
| `modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt` | removed; RV replaces it |
| `modules/darwin/zt-services-trust.nix` | reads RV |
| `pkgs/by-name/ntfy-send/ntfy-send.sh` | a check `: "${NTFY_CACERT:?…}"` after `--help`, then `-sf --cacert "$NTFY_CACERT" -m 5`; `--help` documents `NTFY_CACERT` and drops the endpoint-security paragraph |
| `pkgs/by-name/ntfy-send/package.nix` | `caddyRootCa` argument defaulting to RV; `runtimeInputs = [ curl ]` on every platform; preamble exports `NTFY_CURL_BIN=curl` and `NTFY_CACERT`; `passthru.tests.tls-verification`; corrected comment and description |
| `pkgs/by-name/ntfy-send/test-token-transport.nix` | expected argv `-sf --cacert <ca> -m 5`; runs with `NTFY_CACERT` set |
| `pkgs/by-name/ntfy-send/test-tls-verification.nix` | new: the loopback TLS cases of D4 |
| `modules/checks/package-tests.nix` | `ntfy-send = [ "tls-verification" "token-transport" ]` |
| `modules/home/tools/hooks/notify-permission-{prompt,wait}.sh` and `default.nix` | post through `ntfy-send`; `runtimeInputs` swap `curl` for `pkgs.ntfy-send`; `gate-dangerous-commands` gains `pkgs.ntfy-send` |
| `modules/checks/ntfy-tls-verification.nix` with `modules/checks/ntfy-tls-verification/` | new: the scan of D5 and the root-check legs of D6 |
| `modules/lib/caddy-root-check.nix` | new: `flake.lib.caddyRootCheck` |
| `modules/machines/nixos/cinnabar/caddy-root-check.nix` | new: the weekly oneshot and timer |
| `modules/lib/observability-hosts.nix` | cinnabar's `notifiedUnits` gains `caddy-root-check` |
| `modules/lib/observability-notify-run.nix`, `modules/clan/services/otel-collector/README.md` | notes on darwin's curl corrected |

### D10: caddy's root becomes the clan vars caddy-root-ca, imported unchanged (O8, O9)

cinnabar declares a per-machine generator `caddy-root-ca` with two files:

- `root.key`: `secret = true`, `owner = "caddy"`, `group = "caddy"`, `mode = "0400"`, `neededFor = "services"`, `restartUnits = [ "caddy.service" ]`, deployed to `/run/secrets/vars/per-machine/cinnabar/caddy-root-ca/root.key`; its sops readers are cinnabar's age key and the repository's sops users, today `cameron`, as for `otel-cert/key.pem`.
- `root.crt`: `secret = false`, its value committed at RV and its `path` a store path.

The generator has no prompts and no `validation`, and its `script` only fails, printing `caddy-root-ca is imported from cinnabar's caddy storage with clan vars set, never generated; see the runbook`.
So `clan vars generate` and `clan machines update` cannot mint a root: with the files present the generator counts as current, because a generator whose `validation` is unset and that has no stored hash is valid (`clan-core@dbae2101:pkgs/clan-cli/clan_lib/vars/_types.py:400-409`, `generator.py:443-459`), and with a file missing the script fails and the deploy stops.
Boundary: vendored versus first-party; the fail-only script is first-party, and the behaviour it relies on is clan-core's, recorded as A83.

Alternatives: prompts of type `multiline-hidden` for the key and certificate, rejected because the key would pass through a terminal and the operator's clipboard; `clan vars import` of an exported tree, rejected because it needs the key written to a local directory first; a generator that mints a root, rejected by O8, because the operator's Android phone trusts the existing root by hand.

### D11: caddy loads its root from the vars, and cinnabar's build proves it (O10)

`services.caddy.globalConfig` on cinnabar gains:

```
pki {
	ca local {
		root {
			cert <files."root.crt".path>
			key <files."root.key".path>
		}
	}
}
```

This is caddy 2.11.7's syntax (`caddyconfig/httpcaddyfile/pkiapp.go:32-55`, `:126-153`), adapting to `apps.pki.certificate_authorities.local.root.certificate` and `.private_key` with the default format `pem_file` (`modules/caddypki/crypto.go:73-85`).
With a configured root, caddy reads both files at provisioning, refuses to start the authority when the key does not match the first certificate (`crypto.go:91-118`, `:127`), never generates or renews a root and never consults the root in its storage (`ca.go:150-158`, `maintain.go:68-76`), derives intermediates from the configured root, reading the files again at each renewal (`ca.go:175`, `maintain.go:78-100`, `ca.go:277-284`), and loads a stored intermediate when one exists without checking that the configured root signed it (`ca.go:345-375`).
The stored intermediate today was signed by the same key, so it stays valid; after a reinstall caddy finds none and issues one from the configured root.
caddy's old `root.crt` and `root.key` stay in its storage, unused (Q7, decided by the operator on 2026-11-07): the stored key is the same key, readable only by `caddy` and root, who can already read the deployed var, and removing it would let a dropped `pki` block mint a new root.
What guards the `pki` block itself is `caddy-root-from-vars`: cinnabar's build fails when caddy's adapted configuration does not name the vars as its root.

`vanixiets.caddyLocalRoot.fingerprint`, an option of the module `flake.modules.nixos.caddy-local-root`, which also renders the `pki` block from `certFile` and `keyFile`, and which cinnabar sets to the vars' paths and to the fingerprint recorded on cinnabar on 2026-11-06, `7E:78:F6:7C:83:BD:DC:81:51:FF:EB:8F:82:1A:68:5D:02:89:9F:93:27:33:7F:9B:F2:41:9B:F9:3B:AA:2E:82`, records the live root.
The module adds to `system.checks` `caddy-root-from-vars`, a derivation built with the host's toplevel, on cinnabar and so by `checks.x86_64-linux.nixos-cinnabar`, with two clauses:

| Clause | Fails when | Value sources | Mutant, by `extendModules` |
|---|---|---|---|
| configured root | `caddy adapt --adapter caddyfile` of `services.caddy.configFile`, read with `jq`, names a root certificate or key other than `certFile` and `keyFile`, which cinnabar sets to the generator's `root.crt` and `root.key` paths, or none | caddy's own adapter over the rendered Caddyfile; the options' values, clan's evaluated file paths on cinnabar | `pkiDropped`: `services.caddy.globalConfig` without the `pki` block |
| recorded root | the sha256 fingerprint of the first certificate in `certFile` differs from `vanixiets.caddyLocalRoot.fingerprint` | the committed var; the fingerprint read from cinnabar's storage | `fingerprintOther`: the option set to another fingerprint |

A reinstall is exercised by `vmTests.x86_64-linux.caddy-root-from-vars`, a NixOS test in the non-gating `vmTests` lane, built on magnetite like every `x86_64-linux` build of this change: node `restored` imports `caddy-local-root` with a root and key made in the test and runs caddy with empty storage, and a `tls internal` site for `ntfy.zt`; a client node's curl with `--cacert` on that root gets 200, the served intermediate verifies against it, and `root.crt` never appears in `restored`'s storage.
Its negative control is node `minting`, the same caddy without the module, against which the same curl exits 60, because caddy minted a root of its own; it runs only that case.
The two values related are the root the test made and the chain caddy serves.

The first clause catches a `pki` block that caddy ignores or adapts elsewhere, which an evaluation-time string match would not; the second fails a var holding any certificate but the one cinnabar served on 2026-11-06, so an import of the wrong file, or a later regeneration, fails cinnabar's build before it deploys.
A rotation changes the option with the var (D7).

### D12: The one-time import (O9; operator-gated)

The import runs on stibnite in the primary checkout, in the commit that declares the generator, before caddy's `pki` option exists, with the operator present; nothing writes the key to a local file:

```bash
ssh cinnabar.zt 'sudo cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.key' \
  | CLAN_NO_COMMIT=1 clan vars set cinnabar caddy-root-ca/root.key
ssh cinnabar.zt 'sudo cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt' \
  | CLAN_NO_COMMIT=1 clan vars set cinnabar caddy-root-ca/root.crt
```

`clan vars set` reads a non-terminal stdin to the end and stores it through the file's store, encrypting a secret with sops (`clan-core@dbae2101:pkgs/clan-cli/clan_lib/vars/set.py:38-72`); `CLAN_NO_COMMIT=1` leaves the files to the change's own commit.
The path is caddy's `dataDir` (`/var/lib/caddy`, `services.caddy.dataDir`) plus caddy's storage prefix, confirmed read-only on 2026-11-06.
The step then verifies, printing no key:

- RV's sha256 fingerprint equals the recorded one and the live `root.crt`'s;
- `clan vars get cinnabar caddy-root-ca/root.key | openssl pkey -pubout | sha256sum` equals `openssl x509 -in RV -pubkey -noout | sha256sum`;
- `vars/per-machine/cinnabar/caddy-root-ca/root.key/machines/` lists `cinnabar`, and `users/` the sops users.

No `clan vars generate --regenerate` runs on this generator in this change; a regeneration would only reach the failing script.

### D1: One root file, carried as a store path

RV is the one source of caddy's root.
`ntfy-send`'s package takes `caddyRootCa ? ../../../vars/per-machine/cinnabar/caddy-root-ca/root.crt/value`, and its wrapper's preamble exports `NTFY_CACERT=${caddyRootCa}`, as it exports `NTFY_CURL_BIN` today, so the root is a store path in every closure that holds `ntfy-send` and needs no distribution step (C2).
The script checks `: "${NTFY_CACERT:?ntfy-send: NTFY_CACERT names no CA file}"` after `--help` and passes `--cacert "$NTFY_CACERT"`, so a run without it fails before curl rather than posting unverified; the preamble's export cannot be overridden from the caller's environment.
ZT reads RV for darwin's keychain, caddy reads the same var through its store path (D11), and `caddy-root-check` (D6) judges caddy's served chain against it, so a rotation edits one var and every reader follows.
RV may hold more than one PEM certificate; curl accepts a chain to any of them (A80), and caddy uses only the first, whose key `root.key` must match (`crypto.go:113`), which is what a rotation's overlap needs (D7).
CR is removed in pull request 1, together with ZT's switch to RV, so no second copy of the root stays in the tree.

Boundary: source versus delivered.
The judged artifact is the built wrapper, whose `NTFY_CACERT` names a store copy of RV; D4 runs both the source script, to inject a test CA, and the built wrapper, to show the delivered root refusing a foreign server.

Alternatives: a `flake.lib` attribute naming the path, rejected because a `pkgs/by-name` package cannot read `flake.lib`; cinnabar's evaluated `files."root.crt".value`, rejected because reading it from every host's evaluation evaluates cinnabar; the system bundle or keychain, rejected by O1 and by C4, which shows a launchd job's store curl not consulting what ZT installs.

### D2: The store curl on darwin

`runtimeInputs = [ curl ]` on every platform and `NTFY_CURL_BIN=curl`, removing the darwin branch, its comment and the "(Apple-signed curl on Darwin)" description (O2).
A82 grounds it: the store curl reached `ntfy.zt` from stibnite as `_otelcol` with verification on.
`NTFY_CURL_BIN` stays an environment hook only for the source-script tests.

### D3: The permission hooks post through ntfy-send (Q1)

`notify-permission-prompt` becomes `ntfy-send "$MESSAGE" "$NTFY_TOPIC" -H "Title: …" -H "Priority: default" -H "Tags: lock,${REPO_NAME}" 2>/dev/null || true`, and `notify-permission-wait` the same with `&>/dev/null || true`, keeping each hook's topic, headers, output handling and best-effort exit.
`ntfy-send`'s 5 s timeout equals the hooks' `-m 5`.
Their `runtimeInputs` replace `curl` with `pkgs.ntfy-send`, and `gate-dangerous-commands`, which already calls `ntfy-send` from `PATH` (`HK/gate-dangerous-commands.sh:183`), gains `pkgs.ntfy-send` among its `runtimeInputs`, so every caller is hermetic.
After this, `ntfy-send.sh` is the only script under `modules/` or `pkgs/` that reaches `ntfy.zt`.

Alternative: `--cacert` in each hook's own curl, rejected because it keeps three copies of the flags and the root's path, and D4 would cover only one of them.

### D4: The loopback TLS test

`passthru.tests.tls-verification` (`test-tls-verification.nix`), a `runCommand` with `__darwinAllowLocalNetworking = true`, run on every system `package-tests` exposes.
In the sandbox it makes a P-256 CA `other` and a leaf for `DNS:ntfy.zt` signed by it, starts a Python `http.server` over `ssl` on `127.0.0.1` with an OS-chosen port that records each POST body to a file, and runs every case with `--connect-to ntfy.zt:443:127.0.0.1:<port>` as `ntfy-send`'s extra arguments, so the real curl, the real script and the real root meet a server for `ntfy.zt`.

| Case | Script | `NTFY_CACERT` | Expected |
|---|---|---|---|
| `foreignRefusedSource` | source NS, root pin's curl | RV | exit 60, nothing recorded |
| `foreignRefusedBuilt` | the built wrapper | its own (RV) | exit 60, nothing recorded |
| `ownAccepted` | source NS | `other` | exit 0, body recorded |
| `bundleAccepted` | source NS | RV followed by `other` | exit 0, body recorded |
| `caUnset` | source NS | unset | non-zero exit before curl runs |

The two values each case relates are the CA file given to curl and the CA that signed the server's leaf, made independently in the sandbox.
Mutant `insecure`: NS with `--cacert "$NTFY_CACERT"` replaced by `-k`, run only on `foreignRefusedSource`, which then exits 0 with a recorded body, so the test reports the mutant rejected.
The test also asserts that `--help` documents `NTFY_CACERT` and no longer contains "endpoint security".
RV's acceptance by caddy's real server cannot be shown in a sandbox, because the key is not in it; the rehearsal before the window and every post after it show it.

The wrapper reaches its own test through a `let` binding, `pkg = writeShellApplication { …; passthru.tests.tls-verification = callPackage ./test-tls-verification.nix { ntfySend = pkg; }; }`, which Nix evaluates lazily.
TT keeps its stub curl and changes only its expected argument lists to `-sf --cacert <ca> -m 5 [-H @-]` and sets `NTFY_CACERT`.

### D5: The client scan

`checks.x86_64-linux.ntfy-tls-verification` judges a source tree built from `lib.fileset.toSource` over the `.sh`, `.bash`, `.nix`, `.py`, `.ts` and `.js` files under `modules/` and `pkgs/`; if its evaluation exceeds the budget, the tree is `self`'s source instead, which costs nothing to evaluate and rebuilds on every commit.
The attribute name is a literal.
The check holds three declared lists: clients, `[ "pkgs/by-name/ntfy-send/ntfy-send.sh" ]`; non-clients, each with its reason; and exempt files, the last two rows below, which hold deliberate mutants and which clause A skips.

| Non-client or exempt file | Reason |
|---|---|
| `modules/machines/nixos/cinnabar/zt-dns.nix` | serves the name; its curl reaches the ZeroTier controller on localhost |
| `modules/nixos/fleet-alert.nix` | the dead-man's curl reaches ntfy's own listener over HTTP; its posts go through `ntfy-send` |
| `pkgs/by-name/ntfy-send/package.nix` | builds the client and names curl's path |
| `pkgs/by-name/ntfy-send/test-token-transport.nix`, `test-tls-verification.nix` | exempt: tests holding a curl stub and the `insecure` mutant |
| `modules/checks/ntfy-tls-verification.nix` and its directory | exempt: this check, its scanner and mutant fixtures |

| Clause | Fails when | Value sources | Mutant, run alone |
|---|---|---|---|
| A, no insecure flag | in a file naming `ntfy.zt`, outside the test and check files above, a command line invoking `curl`, `wget` or `CURL_BIN`, with backslash continuations joined, carries `-k`, `--insecure` or a short-option cluster containing `k` | the file's text; curl's option grammar (`curl/curl@curl-8_22_0:docs/cmdline-opts/insecure.md`) | `insecureShort` (`--cacert …` replaced by `-k` in NS), `insecureCluster` (`-sf` replaced by `-sfk`), `insecureLong` (`--insecure` added), `insecureContinued` (a hook-shaped file with `curl \`, then `  -k \`, then the URL) |
| B, declared clients verify | a declared client is missing from the tree or carries no `--cacert` | the declared list; the file's text | `clientMissing` (NS removed), `cacertDropped` (`--cacert …` removed, nothing added) |
| C, no undeclared client | a file naming `ntfy.zt` and invoking `curl` or `wget` is in neither list | the two lists; the tree | `undeclaredClient` (a new `modules/x/post.sh` with a verifying curl to `https://ntfy.zt/x`) |

The unmutated tree passes all three clauses, and each mutant fails with its clause's message, so the scanner cannot pass by finding nothing (B) or by judging only what it found (C).

### D6: cinnabar checks the root caddy serves, weekly (Q2)

`flake.lib.caddyRootCheck pkgs { bundle; connect; servername; minRemainingSec ? 15552000; }` returns a `writeShellApplication` over `openssl`, `coreutils` and `gawk` with two clauses:

- served root: `openssl s_client -connect <connect> -servername <servername> -CAfile <bundle> -verify_return_error` must complete with `Verify return code: 0`, so the chain caddy actually serves, intermediate included, ends at a root in `bundle`; otherwise it fails with `caddy-root-check: the chain served for <servername> does not verify against <bundle>`.
- expiry: `openssl x509 -checkend <minRemainingSec>` on the first certificate of `bundle`, the root caddy is configured with; otherwise it fails with `caddy-root-check: caddy's root expires <notAfter>, within <days> days`.

On success it prints the served root's fingerprint and expiry.
It judges what clients meet, not a file: after D11 caddy's stored root is unused, and a stored intermediate that the configured root did not sign, the one failure D11's build check cannot see, makes the served chain fail to verify.
On cinnabar, `systemd.services.caddy-root-check` runs it as a oneshot with `DynamicUser = true`, `bundle` the store path of RV, `connect` `ntfy.zt:443` and `servername` `ntfy.zt`, after `caddy.service`, and `caddy-root-check.timer` fires `Mon *-*-* 14:00:00 UTC` with `Persistent = true`, which `observability-notify.nix`'s zone assertion requires of a notified unit's timer.
cinnabar's `notifiedUnits` gains `caddy-root-check`, so a failure posts one `FAILED caddy-root-check.service on cinnabar` per episode and the unit is excluded from `SystemdUnitFailed` on magnetite.
180 days (`15552000` s) puts the first warning at 2035-06-09, while the root still serves and the notice can still be delivered; with a configured root caddy logs no expiry warning of its own (A79).
When the served chain stops verifying, every client refuses `ntfy.zt` too, so this unit's notice is not delivered; its value then is the named cause in cinnabar's journal, while the external watch's email reports the outage (`fleet-alerting` `An outage of the alert path reaches the operator by email from outside the fleet`).

Legs in `ntfy-tls-verification`, each serving a leaf through an intermediate with `openssl s_server` on loopback, over roots made in the sandbox with validities relative to the build's clock:

| Leg | `bundle` | served chain under | Expected |
|---|---|---|---|
| `servedHeld` | R1, 400 days | R1 | exit 0 |
| `servedInOverlap` | R1 then R2 | R2 | exit 0 |
| `servedDrifted` | R1 | R2 | fails, "does not verify" |
| `rootExpiring` | R3, 100 days | R3 | fails, "expires" |

The values related are the chain the server presents against the bundle, and the configured root's `notAfter` against the clock.
Mutants `verificationSkipped` (the `-verify_return_error` and return-code test removed) runs only `servedDrifted`, and `expirySkipped` (the `-checkend` test removed) runs only `rootExpiring`.

Alternatives: comparing caddy's stored `root.crt` with the bundle, the first plan, dropped because after D11 the stored root is unused and the comparison would judge a file nothing serves; a Linear issue due in 2035, rejected as a reminder nothing checks; a clause in `fleet-deadman`, rejected because failing the dead-man for a warning would stop its pings and report an outage that is not one.

### D7: Rotating caddy's root

Rotation is a runbook procedure, written in RB by this change and run before 2035-06-09 or whenever `caddy-root-check` reports expiry; every step is the operator's:

1. On cinnabar, in a directory only root reads, generate a P-256 key and a self-signed root matching RV's extensions, `basicConstraints=critical,CA:TRUE,pathlen:1` and `keyUsage=critical,keyCertSign,cRLSign`, valid 3600 days, named `Caddy Local Authority - <year> ECC Root`, as caddy's own template does (`modules/caddypki/certificates.go:26-31`).
2. Set RV to the old root followed by the new one with `CLAN_NO_COMMIT=1 clan vars set cinnabar caddy-root-ca/root.crt`; caddy keeps using the first certificate and the unchanged key; merge and deploy every running host, reading every post; install the new root on the phone by hand.
3. Set `root.key` to the new key and RV to the new root followed by the old one, set cinnabar's `vanixiets.caddyLocalRoot.fingerprint` to the new root's, merge, and, before deploying cinnabar, move `intermediate.crt` and `intermediate.key` out of caddy's storage, so caddy issues an intermediate under the new root instead of loading the old one (`ca.go:345-375`); deploy cinnabar.
4. Run `caddy-root-check` by hand and post one message from each host.
5. Set RV to the new root alone; merge; deploy every running host again.

caddy refuses to load a key that does not match RV's first certificate, so a step 3 with the two files out of order fails caddy's reload and leaves the old root serving.
ZT imports the root into the System keychain by its common name; whether `security add-trusted-cert` imports both PEMs of an overlap is checked at the first rotation, since it affects only browsers on darwin, not any `ntfy.zt` client.

### D8: The deployment order

caddy's switch to the vars deploys on its own, before any client changes, so a failure there is caddy's alone and no client's acceptance depends on it:

1. After pull request 1 merges, cinnabar deploys from the deploy worktree. Before and after, the served chain for `ntfy.zt` is read from stibnite with `openssl s_client -showcerts`, and its intermediate is verified against RV with `openssl verify`; the stored root's fingerprint and the configured root's are read on cinnabar, and caddy's journal is read for the PKI app's provisioning. The intermediate may be the same or reissued; both are correct.
2. After pull requests 2 and 3 merge, the window deploys magnetite, then cinnabar, then pyrite over its LAN address with the operator present, then stibnite by the operator's `just activate` after the deploy-record check.

magnetite goes first in the window because its evaluator reads cinnabar's new `notifiedUnits` from the host table, and its heartbeat each minute is the first live sign that the new client is accepted.
Before the window, a probe runs the merged `ntfy-send`, built for each host's system, on each of the four hosts with the `alerter` token to `fleet-acceptance`; a refusal there stops the window before anything deploys.
Between hosts, a mixed fleet is safe: the server is unchanged, an old client still posts with `-k`, and a new client verifies.
electrum, galena and scheelite are not provisioned and take the change at their next install; argentum, blackphos and rosegold take it at their users' next activation (Q4).

### D9: Decision records amended under charter v30

- A9 item 10, Delivery evidence (A9:53) and Consequences (A9:204-205): delivery verifies `ntfy.zt` against caddy's root from RV, carried as a store path, and fails closed; the token reaches only a holder of the root's key; caddy's root is the clan vars `caddy-root-ca`, whose key the sops users can decrypt; the sentence on distributing the root to magnetite is removed.
- FC:52 and RA:139: the `-k` convention is replaced by verification.
- CH: the v30 entry lists these amendments and A78 to A83.
- RB: `curl -sk` on `ntfy.zt` (RB:190) becomes `curl -s --cacert vars/per-machine/cinnabar/caddy-root-ca/root.crt/value`; RB:555's note records the fix; a section gains caddy's root as vars, D12's import as a record, D7's rotation, recovery after a reinstall, and the meaning of a `caddy-root-check` failure.
- `modules/README.md` lists `checks.x86_64-linux.ntfy-tls-verification` among the gating checks and `caddy-root-from-vars` among cinnabar's build-time checks.

### Spec deltas

- `fleet-alerting` gains `A host posts to the notification service only over a verified connection`, `The service authority's expiry reaches a person 180 days ahead`, `Replacing the service authority loses no post` and `A reinstall of cinnabar keeps the service authority`.
- `fleet-alerting-interface` gains `caddy on cinnabar loads its root from the caddy-root-ca vars`, `ntfy-send verifies ntfy.zt against caddy's root and fails closed`, `No ntfy.zt client in the repository skips verification` and `cinnabar checks the root caddy serves weekly`, and its trust boundary gains verification's scope and the key's readers; the modified text starts from `stand-up-darwin-collection`'s version, which is the corpus's once that change archives (O7).
- `world-assumptions` gains A78 to A83 and two designation rows; its table starts from `stand-up-darwin-collection`'s version for the same reason.

## Risks / Trade-offs

- [Risk] The import stores the wrong certificate or a key that does not match → Mitigation: D12's fingerprint and public-key comparisons before commit; D11's `recorded root` clause fails cinnabar's build; caddy refuses a mismatched key at reload and keeps serving the old configuration, so `clan machines update` reports the failed reload.
- [Risk] caddy loads a stale intermediate the configured root did not sign → Mitigation: today's stored intermediate was signed by the same key; the rotation procedure removes it; the weekly check verifies the served chain.
- [Trade-off, security] The root's key moves from one file on cinnabar's disk into the repository, sops-encrypted to cinnabar's age key and the sops users, today `cameron`; anyone holding one of those private keys, or root on cinnabar, can sign a certificate every client trusts, and an encrypted copy now lives in every clone and in the forge → accepted by O11, because a reinstall without it would mint a root no client trusts, the operator's phone included; the sops users are the same people who already hold root on cinnabar.
- [Risk] A typo in the root's path or the flags makes every post fail after deploy → Mitigation: D4 builds the wrapper and shows it refusing a foreign server and its source accepting a trusted one; the probe posts with the merged package on each host before anything deploys; magnetite deploys first and its heartbeat shows acceptance within a minute.
- [Risk] R9.5's evaluation-time reading of `-m` changes → Mitigation: `-m 5` stays literal, and magnetite's evaluation passes in task 4.3 (C5).
- [Risk] The hooks change behaviour when routed through `ntfy-send` → Mitigation: same topic, headers, timeout and exit handling; an acceptance task posts once through each hook on stibnite and reads the message back.
- [Risk] The scan misses a client that builds the URL from a variable without naming `ntfy.zt` → Mitigation: clause C forces every file naming `ntfy.zt` with curl into a list; a client naming neither is out of the scan's reach, which the trust boundary states.
- [Risk] The scan's fileset evaluation exceeds the budget → Mitigation: measured when the check is written; `self`'s source is the fallback.
- [Trade-off] A failed `caddy-root-check` stays failed until rotation, up to 180 days, with one notice per episode → accepted; the warning's purpose is to start the rotation.
- [Trade-off] Hosts outside the window keep `-k` until their next activation → accepted (Q4): none holds a running copy of the `alerter` token.

## Migration Plan

1. Task 1.1 reviews the plan; task 1.2 waits for `stand-up-darwin-collection` to archive on `main@origin`.
2. Pull request 1: D10 to D12, with the generator declared, the import made by the operator and committed, the build check seen failing first, then caddy's `pki` option; CR removed and ZT switched to RV.
3. cinnabar deploys alone, with the served chain read before and after (D8 step 1).
4. Pull request 2: D1 to D5, with the regulators seen failing first.
5. Pull request 3: D6 and cinnabar's `notifiedUnits`.
6. The window of D8 step 2, after both merge and the probe passes; every post since the window's start is read and recorded with its cause.
7. Pull request 4: D9's documentation.
8. Acceptance, close-out and archive.

Rollback: before the window, reverting pull request 1 and deploying cinnabar returns caddy to its storage root, which is the same root, so nothing a client sees changes; after the window, revert pull request 3 and then pull request 2, and deploy magnetite, cinnabar, pyrite and stibnite in the same order; the reverted client posts with `-k` again and accepts any server.
If magnetite's heartbeats stop after its deploy, the window stops, and the revert deploys magnetite alone.
The imported vars stay committed through any rollback; they are the root caddy already holds.

Acceptance: the chain cinnabar serves verifies against RV before and after caddy's switch; `vmTests.x86_64-linux.caddy-root-from-vars` shows a caddy with empty storage serving under the configured root; each host's deployed `ntfy-send` posts to `fleet-acceptance` with the token and is read back; on magnetite, the deployed `ntfy-send` pointed at the ingress's address with `--connect-to` exits 60 and nothing arrives; each hook on stibnite posts once to `stibnite`; `caddy-root-check` passes on cinnabar and fails when run by hand against `otel-ca`'s certificate and with a 10-year threshold; 24 hours pass with every post explained and no email from the watch service.

## Open Questions

- Q1 to Q5 were decided on 2026-11-07 as recommended, and Q6 was replaced by O8 to O11 (BS "Second round").
- Q7, decided by the operator on 2026-11-07: caddy's stored `root.key` is kept; it is the same key, readable only by `caddy` and root, who can already read the deployed var, and removing it would let a dropped `pki` block mint a new root; `caddy-root-from-vars` guards the `pki` block (D11).
