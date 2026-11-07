---
linear_story_id: CAM-87
linear_story_identifier: CAM-87
linear_story_title: "Verify ntfy.zt's certificate before sending a token to it"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-87/verify-ntfyzts-certificate-before-sending-a-token-to-it
linear_story_state: Todo
linear_team: CAM
linear_project: fleet-observability
last_synced_state: null
last_synced_at: null
review_round: 0
max_review_rounds: 3
attempt_log: []
---

## Why

Every post to `ntfy.zt` skips certificate verification, so a mesh member that answers for cinnabar's address collects the shared `alerter` token and every message, and can then post or suppress fleet alerts.
caddy's root, which every client and the operator's phone trust, lives only on cinnabar's disk, so a reinstall would mint a root nobody trusts.
This change keeps that root as clan vars caddy loads, makes every client verify against it and fail closed, and warns before it expires on 2035-12-06.

## What Changes

Decisions tagged `O<n>` were made by the operator on 2026-11-06 and 2026-11-07; `D<n>` and the questions `Q<n>` are recorded in `brainstorm.md` and developed in `design.md`.

**caddy's root as clan vars**
- A per-machine generator `caddy-root-ca` on cinnabar holds `root.key`, secret, and `root.crt`, public; its script only fails, so no command mints a root (O8, O9; D10).
- The operator imports the existing root and key from caddy's storage with `CLAN_NO_COMMIT=1 clan vars set`, reading them over ssh on stdin, and the import is checked by fingerprint and public key (O9; D12).
- caddy's `pki` option names the vars' paths, so a reinstall serves the same root; cinnabar's build adapts the Caddyfile with caddy and fails unless the configured root is the var and the var is the recorded root `7E:78…2E:82`, and a VM test shows caddy with empty storage serving under a configured root (O10; D11).
- cinnabar deploys this alone, before any client changes, with the served chain verified before and after (O12; D8).

**One verifying client**
- `ntfy-send` posts with `-sf --cacert <caddy's root> -m 5` instead of `-sfk -m 5`, reading the root from the var's public value, and refuses to run without it (O1, O11; D1).
- darwin's `ntfy-send` uses the store curl, and its `--help` no longer claims that endpoint security blocks store binaries from ZeroTier (O2, O3; D2).
- The permission hooks `notify-permission-prompt` and `notify-permission-wait` post through `ntfy-send`, so one script reaches `ntfy.zt` (D3; Q1).

**Regulators**
- `ntfy-send` gains a test running the real curl against a loopback TLS server for `ntfy.zt`: a certificate from another CA is refused under caddy's root by the source script and the built wrapper, the same server is accepted under its own CA and under a two-root bundle, and a mutant with `-k` is rejected (O4; D4).
- `checks.x86_64-linux.ntfy-tls-verification` fails when any file under `modules/` or `pkgs/` that names `ntfy.zt` passes curl `-k` or `--insecure`, when a declared client lacks `--cacert`, or when an undeclared file names `ntfy.zt` and calls curl (O4; D5).
- cinnabar runs `caddy-root-check` weekly, which fails, and so posts a failure notice, when the chain caddy serves for `ntfy.zt` does not verify against the var or its root expires within 180 days (O5; D6; Q2).

**Rotation and deployment**
- The var's public value is the one source every reader uses, replacing `modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt`, and may hold two roots while a rotation overlaps them; the runbook gains the rotation procedure (O5, O11; D7, D13).
- One window deploys magnetite, cinnabar, pyrite over its LAN address and stibnite by the operator's activation, reading every post afterwards; implementation starts after `stand-up-darwin-collection` archives (O6, O7; D8).

**Decision records amended under charter v30**
- From: ADR-009 item 10 and its Delivery evidence and Consequences say delivery inherits `ntfy-send`'s `-k`, so the token's confidentiality rests on ZeroTier's encryption and cinnabar's dnsmasq, and that trusting caddy's root would need it distributed to magnetite.
- To: every client verifies `ntfy.zt` against caddy's root, the public value of the clan vars `caddy-root-ca`, carried in each closure as a store path; the token reaches only a holder of the root's key.
- Reason: a mesh member answering for cinnabar's address could otherwise collect the token (CAM-86).
- Impact: non-breaking; the root is unchanged; its key moves into the sops-encrypted repository, readable by cinnabar and the sops users.

## Capabilities

### New Capabilities

None.
The change tightens the existing alerting capabilities; no new area of behaviour is added.

### Modified Capabilities

- `fleet-alerting` (stratum: `behavioral`): adds `A host posts to the notification service only over a verified connection`, `The service authority's expiry reaches a person 180 days ahead`, `Replacing the service authority loses no post` and `A reinstall of cinnabar keeps the service authority`.
- `fleet-alerting-interface` (stratum: `interface`): adds `caddy on cinnabar loads its root from the caddy-root-ca vars`, `ntfy-send verifies ntfy.zt against caddy's root and fails closed`, `No ntfy.zt client in the repository skips verification` and `cinnabar checks the root caddy serves weekly`; `This capability states its own trust boundary` gains what verification guarantees and who can read the root's key.
  Trust boundary: verification guarantees that the token and a message reach only a server holding the key of a root in the var; it does not guarantee delivery, since a member answering for cinnabar can still drop posts, and it guarantees nothing once that key is read by anyone outside cinnabar's root account, caddy and the sops users.
- `world-assumptions` (stratum: `world`): A78 to A83 record that caddy signs `ntfy.zt`'s certificate under the imported root (A78), how caddy 2.11.7 loads, keeps and derives intermediates from a configured root (A79), that curl with `--cacert` trusts that file alone and `-k` disables it (A80), who can read the root's key (A81), that the store curl on stibnite reaches `ntfy.zt` from a launchd job's account (A82), and that clan neither regenerates an imported generator nor writes a value `clan vars set` did not receive (A83); `Grounded vocabulary for behavioral requirements` gains the rows `service authority` and `verified connection`.

## Impact

- New: `modules/machines/nixos/cinnabar/caddy-root-ca.nix`, `vars/per-machine/cinnabar/caddy-root-ca/`, `modules/vm-tests/caddy-root-from-vars.nix`, `modules/checks/ntfy-tls-verification.nix`, `modules/lib/caddy-root-check.nix`, `modules/machines/nixos/cinnabar/caddy-root-check.nix` and `pkgs/by-name/ntfy-send/test-tls-verification.nix`.
- Changed: `pkgs/by-name/ntfy-send/` (`ntfy-send.sh`, `package.nix`, `test-token-transport.nix`), `modules/checks/package-tests.nix`, `modules/home/tools/hooks/` (the two hooks and `default.nix`), `modules/darwin/zt-services-trust.nix`, `modules/lib/observability-hosts.nix` (cinnabar's `notifiedUnits`), `modules/lib/observability-notify-run.nix` and the collector README's notes on darwin's curl.
- Removed: `modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt`.
- New secrets: cinnabar's `caddy-root-ca/root.key`, the existing key imported, encrypted to cinnabar and the sops users.
- Unchanged: the root, its key and its expiry; caddy's sites; ntfy's configuration; the `alerter` token and its readers.
- Documentation: the charter v30 entry, ADR-009, the `fleet-alert` component, the reference architecture and the runbook's verification commands, the root's import record, recovery and rotation.
- Deployment: cinnabar deploys alone after pull request 1; every host's closure changes after pull request 2, and magnetite, cinnabar, pyrite and stibnite deploy in one window; electrum, galena and scheelite are not provisioned, and argentum, blackphos and rosegold activate at their users' convenience (Q4).
- Security trade-off: the root's key, until now one file on cinnabar's disk, is also in every clone and the forge, sops-encrypted; holders of cinnabar's age key or a sops user's key can sign certificates every client trusts (O11).
- Out of scope: the ingress's own `-k` probe in the runbook, which is not an `ntfy.zt` client; removing caddy's stored copy of the key, which the operator decided to keep (Q7); any change to who may publish.
