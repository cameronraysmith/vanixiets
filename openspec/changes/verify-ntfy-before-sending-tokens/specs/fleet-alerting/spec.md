## ADDED Requirements

### Requirement: A host posts to the notification service only over a verified connection

Every host SHALL post to the fleet's notification service only over a verified connection, and SHALL present no credential and post nothing when the connection cannot be verified.

**Discharged by**: `fleet-alerting-interface` requirements `ntfy-send verifies ntfy.zt against caddy's root and fails closed` and `No ntfy.zt client in the repository skips verification`, resting on world assumptions `A78 — cinnabar's caddy signs ntfy.zt's certificate under the root kept as cinnabar's caddy-root-ca vars`, `A80 — curl given a CA file trusts only that file's certificates, any of them, and -k disables verification` and `A81 — caddy's root key is readable only by cinnabar's root and caddy accounts and by the sops recipients of its var`, and for stibnite `A82 — A store-built curl on stibnite reaches ntfy.zt over ZeroTier from a launchd job's account`; the posts read after the deploy window and the acceptance control against a server of another authority discharge it on the hosts deployed.

#### Scenario: Another member answers for the notification service

- **WHEN** a host connects to the notification service's name and the server answering presents a certificate that does not chain to the service authority
- **THEN** the host refuses the connection, sends no credential and no message, and the post fails, which the operator records at acceptance by pointing a deployed host at a server of another authority

#### Scenario: The notification service answers

- **WHEN** a host posts an alert, a heartbeat, a failure notice or a host's own message and the notification service answers with its certificate under the service authority
- **THEN** the post is accepted as before, which the posts read after each host's deploy in the window record

#### Scenario: cinnabar serves under a root the fleet does not hold

- **WHEN** cinnabar's caddy serves `ntfy.zt` under a root that is not in cinnabar's `caddy-root-ca` vars
- **THEN** every host's post is refused, no alert or failure notice reaches a person, and the operator learns of it from the external watch's email under `An outage of the alert path reaches the operator by email from outside the fleet`, not from a notice

### Requirement: The service authority's expiry reaches a person 180 days ahead

When the service authority's root has 180 days or fewer of validity left, a failure notice naming `caddy-root-check` SHALL reach a person within 7 days, while posts are still verified, and that unit's journal on cinnabar SHALL name the root's expiry.

**Discharged by**: `fleet-alerting-interface` requirement `cinnabar checks the root caddy serves weekly`, resting on world assumption `A79 — caddy loads a configured root from its files, never mints or renews it, and derives intermediates from it`; the check's `rootExpiring` leg with its mutant and the operator's hand-run of the deployed check with a 10-year threshold discharge it.

#### Scenario: The root enters its last 180 days

- **WHEN** the weekly check runs on or after 180 days before the root's expiry
- **THEN** it fails with its journal naming the root's expiry, and one failure notice naming `caddy-root-check` reaches a person while the root still verifies, at the latest 7 days after the threshold

#### Scenario: The threshold is exercised before it is reached

- **WHEN** at acceptance the operator runs the deployed check by hand with a threshold of 10 years
- **THEN** it exits non-zero naming the root's expiry, without posting, and the operator records the output

### Requirement: Replacing the service authority loses no post

When the operator replaces the service authority's root, every running host SHALL keep posting over a verified connection before, during and after the switch.

**Discharged by**: the `caddy-root-ca` public value holding both roots during the overlap, caddy using only the first, the `tls-verification` test's two-root case and the runbook's rotation procedure, resting on world assumptions `A79 — caddy loads a configured root from its files, never mints or renews it, and derives intermediates from it` and `A80 — curl given a CA file trusts only that file's certificates, any of them, and -k disables verification`; the first rotation's posts read from each host discharge it at runtime.

#### Scenario: Both roots are trusted during the overlap

- **WHEN** the `caddy-root-ca` public value holds the old and the new root and every running host has deployed it
- **THEN** a host posts over a verified connection whether cinnabar serves under the old root or the new one, which the two-root test case shows on every build

#### Scenario: The old root is removed too early

- **WHEN** the old root is removed from the `caddy-root-ca` public value before cinnabar serves under the new one
- **THEN** every host that deploys the file is refused, and the procedure's order, new root added and deployed, switch, old root removed and deployed only after the chain served for `ntfy.zt` verifies against the new root alone, is what prevents it

### Requirement: A reinstall of cinnabar keeps the service authority

When cinnabar is reinstalled or caddy's storage is lost, caddy SHALL serve the fleet's mesh-only names under the same service authority as before, so that every host and every device that trusts it, the operator's phone included, keeps verifying without any change on its side.

**Discharged by**: `fleet-alerting-interface` requirement `caddy on cinnabar loads its root from the caddy-root-ca vars`, resting on world assumptions `A79 — caddy loads a configured root from its files, never mints or renews it, and derives intermediates from it` and `A83 — clan neither regenerates an imported generator nor stores a value other than what clan vars set received`; `vmTests.x86_64-linux.caddy-root-from-vars` with its `minting` control, cinnabar's build-time check `caddy-root-from-vars` with its overrides, and the served chain read before and after cinnabar's deploy discharge it.

#### Scenario: caddy starts with empty storage

- **WHEN** caddy starts with the vars deployed and no root or intermediate in its storage
- **THEN** it serves `ntfy.zt` under the vars' root with a freshly issued intermediate, and writes no root of its own, as the VM test's `restored` node shows

#### Scenario: caddy is configured without the vars

- **WHEN** caddy starts with empty storage and no configured root
- **THEN** it mints a root no host trusts and every verified post is refused, as the VM test's `minting` node shows, which is why cinnabar's build fails when the configured root is not the var

#### Scenario: caddy switches to the vars

- **WHEN** cinnabar first deploys caddy with the configured root
- **THEN** the chain served for `ntfy.zt` verifies against the vars' root before and after, and the operator records both reads
