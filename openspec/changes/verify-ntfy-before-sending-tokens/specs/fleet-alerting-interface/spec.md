## ADDED Requirements

### Requirement: ntfy-send verifies ntfy.zt against caddy's root and fails closed

`ntfy-send` SHALL pass curl `--cacert` with the file in `NTFY_CACERT`, which its built wrapper sets to the store copy of `vars/per-machine/cinnabar/caddy-root-ca/root.crt/value`, SHALL never pass `-k` or `--insecure`, and SHALL exit non-zero before curl runs when `NTFY_CACERT` is unset or empty.
It SHALL run its own `runtimeInputs` curl on every platform, and every script that posts to `ntfy.zt` SHALL post through it.

**Discharged by**: `checks.<system>.package-ntfy-send-test-tls-verification` with its `insecure` mutant and `checks.<system>.package-ntfy-send-test-token-transport`, resting on world assumptions `A80 — curl given a CA file trusts only that file's certificates, any of them, and -k disables verification` and, on stibnite, `A82 — A store-built curl on stibnite reaches ntfy.zt over ZeroTier from a launchd job's account`; the rehearsal posts before the deploy window, the posts read after it, and the acceptance control against the ingress's address.

#### Scenario: A server for ntfy.zt presents a certificate from another CA

- **WHEN** `package-ntfy-send-test-tls-verification` runs the source script with `NTFY_CACERT` naming caddy's root, and the built wrapper as delivered, against a loopback server for `ntfy.zt` whose certificate a CA made in the sandbox signed
- **THEN** both exit 60 and the server records no request body

#### Scenario: The server's own CA is trusted

- **WHEN** the same test runs the source script with `NTFY_CACERT` naming the sandbox CA, and then naming a file holding caddy's root followed by the sandbox CA
- **THEN** both exit 0 and the server records the message each time

#### Scenario: No CA file is given

- **WHEN** the source script runs with `NTFY_CACERT` unset
- **THEN** it exits non-zero before curl runs, and no request reaches the server

#### Scenario: Verification is switched off

- **WHEN** the test runs a mutant of the script in which `--cacert` is replaced by `-k` against the server signed by the sandbox CA with `NTFY_CACERT` naming caddy's root
- **THEN** the mutant exits 0 and the server records the message, so the test reports the mutant rejected

#### Scenario: The help text is read

- **WHEN** `ntfy-send --help` is run
- **THEN** it documents `NTFY_CACERT` and says nothing about endpoint security blocking store binaries

#### Scenario: A deployed host posts

- **WHEN** after a host's deploy its delivered `ntfy-send` posts to `fleet-acceptance` with the `alerter` token
- **THEN** ntfy accepts the post and it is read back over a verified connection, and the wrapper's `NTFY_CACERT` names a store path whose content equals `vars/per-machine/cinnabar/caddy-root-ca/root.crt/value`, which the operator records for magnetite, cinnabar, pyrite and stibnite

#### Scenario: A deployed host is pointed at another server

- **WHEN** at acceptance magnetite's delivered `ntfy-send` runs with `--connect-to ntfy.zt:443:<magnetite's ingress address>:4318`, whose certificate the collection CA signed
- **THEN** it exits 60 and the ingress receives no request, which the operator records

### Requirement: No ntfy.zt client in the repository skips verification

`checks.x86_64-linux.ntfy-tls-verification`, a literal attribute evaluated within 536,870,912 B, SHALL fail when a curl or wget command line in a scanned file naming `ntfy.zt` carries `-k`, `--insecure` or a short-option cluster containing `k`, when a declared client is missing or lacks `--cacert`, or when a scanned file naming `ntfy.zt` and invoking curl or wget is declared neither a client nor a non-client.

**Discharged by**: the check over the repository's tree with its mutants `insecureShort`, `insecureCluster`, `insecureLong`, `insecureContinued`, `clientMissing`, `cacertDropped` and `undeclaredClient`, each run only against the clause it must fail; its evaluation cost recorded before and after.

#### Scenario: The scanned files are listed

- **WHEN** the check builds its tree
- **THEN** it holds every `.sh`, `.bash`, `.nix`, `.py`, `.ts` and `.js` file under `modules/` and `pkgs/`, joins backslash continuations before judging a command line, and exempts from the flag clause only its own files and `ntfy-send`'s test files, which hold the deliberate mutants

#### Scenario: The repository's tree is scanned

- **WHEN** the check runs over the tree at a commit of this change
- **THEN** it passes, having found `pkgs/by-name/ntfy-send/ntfy-send.sh` with `--cacert` and every other file that names `ntfy.zt` and invokes curl in its non-client list

#### Scenario: A client skips verification

- **WHEN** a mutant tree adds `-k`, `--insecure` or `k` in a short-option cluster to a curl command line in a file naming `ntfy.zt`, on one line or across a continuation
- **THEN** the check fails naming the file and line, and each of the four mutants is rejected

#### Scenario: The declared client stops verifying or disappears

- **WHEN** a mutant tree removes `--cacert` from `ntfy-send.sh` or removes the file
- **THEN** the check fails naming the declared client

#### Scenario: A new client appears

- **WHEN** a mutant tree adds a file that names `ntfy.zt` and invokes curl with `--cacert`
- **THEN** the check fails until the file is declared a client or a non-client with a reason

### Requirement: cinnabar checks the root caddy serves weekly

On cinnabar, `caddy-root-check.service` SHALL run weekly from `caddy-root-check.timer` at `Mon *-*-* 14:00:00 UTC` and SHALL fail when the chain served for `ntfy.zt` does not verify against `vars/per-machine/cinnabar/caddy-root-ca/root.crt/value`, or when that value's first certificate expires within 15,552,000 seconds; cinnabar's notified units SHALL include it.

**Discharged by**: the legs `servedHeld`, `servedInOverlap`, `servedDrifted` and `rootExpiring` of `checks.x86_64-linux.ntfy-tls-verification` against `openssl s_server` on loopback with chains made in the sandbox, with the mutants `verificationSkipped` and `expirySkipped`; `observability-notify.nix`'s assertions on notified units and their timers' zones; at acceptance, the unit's first run on cinnabar and the operator's hand-runs of its script against `otel-ca`'s certificate and with a 10-year threshold, resting on world assumptions `A78 — cinnabar's caddy signs ntfy.zt's certificate under the root kept as cinnabar's caddy-root-ca vars` and `A79 — caddy loads a configured root from its files, never mints or renews it, and derives intermediates from it`.

#### Scenario: caddy serves under the var's root, far from expiry

- **WHEN** the check runs on cinnabar after its deploy
- **THEN** it exits 0, and its journal names the root's fingerprint and expiry

#### Scenario: caddy serves a chain the var does not anchor

- **WHEN** the leg `servedDrifted` serves a chain under a root absent from the bundle, or the operator runs the deployed script by hand with `otel-ca`'s certificate as the bundle
- **THEN** it fails with `does not verify`, and the mutant `verificationSkipped` passes that leg and is rejected

#### Scenario: The root nears expiry

- **WHEN** the leg `rootExpiring` uses a root valid for 100 days, or the operator runs the deployed script by hand with a 10-year threshold
- **THEN** it fails with `expires`, and the mutant `expirySkipped` passes that leg and is rejected

#### Scenario: The var holds two roots during a rotation

- **WHEN** the leg `servedInOverlap` uses a two-root bundle and serves under the second root
- **THEN** it exits 0

### Requirement: caddy on cinnabar loads its root from the caddy-root-ca vars

cinnabar SHALL declare a generator `caddy-root-ca`, with a secret `root.key` owned by `caddy` with mode `0400`, a public `root.crt` and a script that only fails.
`flake.modules.nixos.caddy-local-root` SHALL render caddy's `pki` root from those two files, and the first certificate of `root.crt` SHALL have the fingerprint `vanixiets.caddyLocalRoot.fingerprint`, on cinnabar `7E:78:F6:7C:83:BD:DC:81:51:FF:EB:8F:82:1A:68:5D:02:89:9F:93:27:33:7F:9B:F2:41:9B:F9:3B:AA:2E:82`.

**Discharged by**: cinnabar's build-time check `caddy-root-from-vars`, built by `checks.x86_64-linux.nixos-cinnabar`, with the `extendModules` overrides `pkiDropped` and `fingerprintOther`; `vmTests.x86_64-linux.caddy-root-from-vars` with its `minting` control; the operator's import record; resting on world assumptions `A79 — caddy loads a configured root from its files, never mints or renews it, and derives intermediates from it` and `A83 — clan neither regenerates an imported generator nor stores a value other than what clan vars set received`.

#### Scenario: caddy's adapter reads the configured root

- **WHEN** cinnabar's toplevel builds
- **THEN** `caddy adapt` of the rendered Caddyfile names the generator's `root.crt` and `root.key` paths as `apps.pki.certificate_authorities.local.root`, and an override dropping the `pki` block fails the build

#### Scenario: The var holds another certificate

- **WHEN** an override sets `vanixiets.caddyLocalRoot.fingerprint` to a fingerprint other than that of the var's first certificate
- **THEN** cinnabar's build fails naming both fingerprints

#### Scenario: The vars are imported

- **WHEN** the operator imports the root and key from caddy's storage with `CLAN_NO_COMMIT=1 clan vars set`
- **THEN** the var's fingerprint equals the recorded one and the live stored root's, the decrypted key's public key equals the certificate's, `root.key`'s readers are cinnabar and the sops users, no key is printed or written to a local file, and the operator records all of it

#### Scenario: A regeneration is attempted

- **WHEN** `clan vars generate cinnabar --generator caddy-root-ca` runs with a file missing
- **THEN** the script fails with its message naming the import, and no root is minted

## MODIFIED Requirements

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that an alert reaches a person.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that the evaluator queries each rule's database as `regulator` on the path its language names, that the rules render from one source to the evaluator and to `promtool`, that instance state, freezes, presence watching, titles, priorities, heartbeats, the dead-man and its ping behave as the fixture check, its mutants, its property test and the recorded acceptance observations show, and that ntfy is configured with the stated access entries, provisioning and proxy settings, and that `ntfy-send`, the one client of `ntfy.zt` in the repository, verifies the server against caddy's root, as its `tls-verification` test, the client scan and cinnabar's root check show, and that caddy on cinnabar is configured with the root its vars hold, as cinnabar's build-time check shows

#### Scenario: A guarantee about ntfy's enforcement is sought

- **WHEN** someone asks whether these properties guarantee that ntfy refuses an anonymous `fleet-*` publish, rate-limits each client separately, or delivers a message to a subscribed device
- **THEN** the answer is no: ntfy enforces the access entries and rate limits and delivers to subscribed devices, and this machine only configures it, which R9.4's probe and the acceptance observations monitor

#### Scenario: A guarantee about the token's secrecy is sought

- **WHEN** someone asks whether only the evaluator, the dead-man, the notifier and stibnite's notifier wrapper can read the `alerter` token
- **THEN** the answer is no: any root process on a host holding a copy, magnetite, cinnabar, pyrite, electrum, galena, scheelite or stibnite, can read it, and on stibnite so can any process running as `_otelcol`, which also runs the agent collector

#### Scenario: A guarantee that the token and messages reach only cinnabar is sought

- **WHEN** someone asks whether the `alerter` token and a message posted to `ntfy.zt` reach only cinnabar's ntfy
- **THEN** the answer is that they reach only a server presenting a chain to a root in `vars/per-machine/cinnabar/caddy-root-ca/root.crt/value`, which only a holder of that root's key can present; anyone with root on cinnabar or the `caddy` account can read the key, and so can any holder of cinnabar's age key or a sops user's key, because the repository carries the key sops-encrypted to them, a copy of the key defeats verification everywhere until the root is replaced, and a client outside `modules/` and `pkgs/`, or one that builds the name without writing `ntfy.zt`, is beyond the client scan

#### Scenario: A guarantee of delivery against an impostor is sought

- **WHEN** someone asks whether verification guarantees that a post reaches ntfy while another mesh member answers for cinnabar's address
- **THEN** the answer is no: the impostor cannot read the token or the message, but it can refuse or drop the connection, and the post fails; a failed heartbeat or alert post fails the evaluator's run, and the dead-man and the external watch report the heartbeats' absence

#### Scenario: A guarantee that every host verifies is sought

- **WHEN** someone asks whether every host in the fleet verifies `ntfy.zt`
- **THEN** the answer is that a host verifies once its running configuration contains this `ntfy-send`; a host not activated since, such as a laptop its user has not activated, still posts with `-k` and verifies nothing

#### Scenario: A guarantee that a compromised laptop posts only its own notices is sought

- **WHEN** someone asks whether a compromised stibnite can post only its own failure notices
- **THEN** the answer is no: whoever reads stibnite's copy of the token can post to any `fleet-*` topic, alerts and heartbeats included, as whoever reads pyrite's copy can today, because ntfy grants the one `alerter` token every `fleet-*` topic and cannot tell which host posted; stibnite's copy also travels on a laptop that leaves the operator's premises, and it stays valid until the shared token is replaced

#### Scenario: A guarantee about an ntfy outage is sought

- **WHEN** someone asks whether an outage of cinnabar or its ntfy is reported
- **THEN** the answer is that the dead-man stops pinging healthchecks.io, which emails the operator once the check's period and grace pass; healthchecks.io evaluates the period and grace and sends the email, the operator's mail provider delivers it, and this machine only pings, so nothing reports the outage if healthchecks.io fails at the same time

#### Scenario: A guarantee about the watch's configuration is sought

- **WHEN** someone asks whether the check's period, grace and email integration are as the runbook states
- **THEN** the answer is no: they are set in healthchecks.io's web interface, not by this machine, and only the acceptance stops and later outages observe them

#### Scenario: A guarantee about the ping URL's secrecy is sought

- **WHEN** someone asks whether only the dead-man can send a ping that keeps the check up
- **THEN** the answer is no: the URL is a bearer credential, any root process on cinnabar can read it, and anyone holding it can keep the check up while the alert path is down

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that an alert reaches a person
- **THEN** the answer is no: each stage's configuration, the fixture check and the recorded acceptance observations behave as stated, and nothing here observes an alert or an email reaching a person's device
