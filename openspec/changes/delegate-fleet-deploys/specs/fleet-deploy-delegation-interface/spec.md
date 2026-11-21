## ADDED Requirements

### Requirement: This capability states its own trust boundary

The properties in this capability SHALL be read as guarantees only about what the repository declares, what evaluation of the flake and these checks accept, and what `fleet-deploy-request` does when run on cinnabar as `fleet-deployer`. The checks are the machine checks, `checks.x86_64-linux.fleet-deployer-obligations`, `checks.x86_64-linux.fleet-deploy-request`, `checks.x86_64-linux.sops-correspondence` and the on-demand `vmTests.x86_64-linux.fleet-deployer`. None of these properties is an end-to-end guarantee.

**Outside the boundary**:
- root on cinnabar, which can read the deployer's keys;
- a merge gate that admits a harmful commit, which the deployer then deploys;
- what a target does after activation, beyond the deploy record, the unit or launchd state and the SSH answer the health check reads;
- whether the session id a request names is true;
- the forge, the binary cache, clan and ntfy, which the VM test replaces with local stand-ins.

#### Scenario: a harmful commit is merged
- **WHEN** a commit that breaks a host lands on `main` through the merge queue and is deployed on request
- **THEN** this capability is not violated, because the merge gate is outside its boundary; the deploy is recorded and announced, and the host rolls back only if it stops answering

### Requirement: Deploy targets are derived from the enabled machines

`flake.lib.fleetDeployer.targets` SHALL be the sorted names of every `clan.inventory.machines` entry whose `machineClass` is `nixos` or `darwin`, that is enabled, and that is not `stibnite` or `blackphos`. A machine is enabled when its entry in `flake.lib.cloudMachines.hetzner` or `flake.lib.cloudMachines.gcp` has `enabled = true`, or when it has no such entry. `flake.lib.fleetDeployer.problems`, asserted by `modules/checks/machines.nix`, SHALL be empty, and SHALL be non-empty for any target that is disabled, excluded or of another class.

#### Scenario: the targets are evaluated
- **WHEN** `nix eval .#lib.fleetDeployer.targets` is run while electrum, galena and scheelite are disabled
- **THEN** it prints `argentum`, `cinnabar`, `magnetite`, `pyrite`, `rosegold`

#### Scenario: a disabled machine is put in reach
- **WHEN** `checks.x86_64-linux.fleet-deployer-obligations` judges a target list containing a disabled machine, an excluded machine or a phone
- **THEN** each mutant yields exactly one problem naming that machine

### Requirement: Reach is the role policy over each machine's primary user

`flake.lib.hosts.<name>.primaryUser` SHALL be null or a name in `flake.users`. A requester SHALL reach a target exactly when the target's primary user is null and the requester is in `flake.lib.fleetDeployer.operators` (`cameron`, `janettesmith`), or when the requester is the target's primary user or `flake.lib.fleetDeployer.admin` (`cameron`). `fleet-deploy-request <requester>` SHALL refuse with status 3 any machine outside that requester's reach.

#### Scenario: the reach is evaluated
- **WHEN** `nix eval .#lib.fleetDeployer.requesters` is run
- **THEN** cameron's machines are `argentum`, `cinnabar`, `magnetite`, `pyrite`, `rosegold` and janettesmith's are `cinnabar`, `magnetite`, `rosegold`

#### Scenario: reach outside the policy
- **WHEN** the policy judge is given janettesmith reaching pyrite, or an operator who is not the admin reaching a personal machine
- **THEN** it yields exactly one problem naming the requester and the machine

### Requirement: The deployer answers only its forced command

Every key in `fleet-deployer`'s `authorized_keys` on cinnabar SHALL equal `flake.lib.fleetDeployer.requestKeyLine <requester> <key>`, which is `restrict,from="<tincr /64>,<ZeroTier /64>,<ZeroTier IPv4 /24>",command="/run/current-system/sw/bin/fleet-deploy-request <requester>" <key>`. `fleet-deploy-request` SHALL accept only `deploy <machine> [<commit>] [--session <id>]`, at most 200 printable ASCII characters separated by single spaces, where:
- `<machine>` is a target;
- `<commit>` is 7-40 lowercase hexadecimal digits;
- `<id>` is 1-64 characters from `[A-Za-z0-9._-]`.

Anything else SHALL be refused with exit status 3.

#### Scenario: the parser is run over fixtures
- **WHEN** `checks.x86_64-linux.fleet-deploy-request` is built
- **THEN** the four accepted forms exit 0. Each mutant exits 3: an empty or bare command, a shell metacharacter, a substitution, a flake reference, a ref name, an extra argument, a double space, an unknown machine, `stibnite`, a machine outside the requester's reach, an unknown requester, an uppercase commit, an over-long or missing session id, and `shell`.

#### Scenario: a key without the forced command is declared
- **WHEN** cinnabar's configuration declares a `fleet-deployer` authorized key other than the requesters' lines
- **THEN** the `nixos-cinnabar` check fails with a fleet-obligation message naming cinnabar

### Requirement: Only merged commits are deployed, and a NixOS host only from a built closure

Before contacting a target, `fleet-deploy-request` SHALL:
- fetch `refs/heads/main` from the configured forge into the deployer's bare mirror;
- refuse with status 3 a commit that does not resolve there, or for which `git merge-base --is-ancestor <commit> <main>` fails;
- deploy from a detached worktree of that commit only.

For a target of class `nixos`, it SHALL refuse with status 3 when `nix path-info --store <cacheStore>` fails for the evaluated toplevel.

#### Scenario: an unmerged commit is requested in the VM test
- **WHEN** `vmTests.x86_64-linux.fleet-deployer` requests a commit on a branch other than `main`
- **THEN** the request exits 3 and the target's sshd journal shows no new accepted connection

#### Scenario: an uncached closure in the VM test
- **WHEN** the VM test requests a merged commit whose closure is absent from the test cache
- **THEN** the request exits 3 and its record's reason names the cache

### Requirement: The deployer checks every machine's secrets before it deploys

`fleet-deploy-request` SHALL run `clan vars check` for every inventory machine in the deploy worktree, and SHALL refuse with status 3, before contacting the target, when any check fails. `clan machines update` therefore never generates or re-encrypts a var on cinnabar.

#### Scenario: a vars check fails in the VM test
- **WHEN** the VM test requests a merged commit for which the stand-in vars check fails
- **THEN** the request exits 3 and its record's reason names the vars check

### Requirement: The deployer deploys with clan to the commit's own target

`fleet-deploy-request` SHALL take the target from the deployed commit: `clan.inventory.machines.<m>.deploy.targetHost` for a NixOS machine, `darwinConfigurations.<m>.config.clan.core.networking.targetHost` for a darwin machine. It SHALL then run `clan machines update --flake <worktree> <m> --target-host <target>` with:
- `SOPS_AGE_KEY_FILE` set to `/var/lib/fleet-deployer/keys/age.key`;
- `CLAN_NO_COMMIT=1`;
- no `SSH_AUTH_SOCK` or `SSH_AGENT_PID` in its environment;
- an SSH configuration naming only `/var/lib/fleet-deployer/keys/id_ed25519`.

#### Scenario: a darwin target is deployed
- **WHEN** rosegold is deployed through the deployer
- **THEN** the command's target is the commit's declared `cameron@…`, never `root@`, and clan's network selection is not consulted

### Requirement: Only deploy targets accept the deployer's key

When `flake.lib.fleetDeployer.keys` is set, every target SHALL carry `flake.lib.fleetDeployer.targetKeyLine (name == deployerHost) keys.ssh` exactly once, on its deploy account and on no other account. That line is `from="<cinnabar's tincr, ZeroTier IPv6 and IPv4 addresses>",restrict <key>`. On the deployer host itself, the `from=` list also admits loopback (`127.0.0.1,::1`), because the host resolves its own name to a loopback address (F82). The deploy account is root on NixOS and `flake.lib.hosts.<name>.deployUser` on darwin. No other machine SHALL carry the key on any account.

#### Scenario: an excluded host gains the key
- **WHEN** the host judge is given stibnite, which is not a target, with the deployer's key on any account
- **THEN** it yields exactly one problem, and so would stibnite's machine check

#### Scenario: an unrestricted line on a target
- **WHEN** the host judge is given a target whose deploy account carries the key without `from=` and `restrict`
- **THEN** it yields exactly one problem naming the account and the expected line

### Requirement: Deploys hold a per-host lock and one of two slots

`fleet-deploy-request` SHALL probe the target at `flake.lib.hosts.<name>.targetHost` before it evaluates the commit, ending the request with status 5 if it does not answer (F83). It SHALL then hold one of two slot locks under `/run/fleet-deployer/slot/` while it evaluates, release it, and probe the target again at the address resolved from the commit. It SHALL then hold `/run/fleet-deployer/lock/<machine>` (waiting at most 600 s) until the health check ends, and hold a slot again while the deploy command runs. A lock not obtained in time SHALL end the request with status 4.

#### Scenario: concurrent requests in the VM test
- **WHEN** the VM test sends two requests for the same target one second apart
- **THEN** both exit 0, and the second deploy starts after the first deploy's end, as the stand-in deploy command's log shows

#### Scenario: a held host lock in the VM test
- **WHEN** the VM test holds the target's lock for longer than the configured wait and sends a request
- **THEN** the request exits 4

### Requirement: Each request ends in one exit status

`fleet-deploy-request` SHALL probe the target with `ssh -o ConnectTimeout=<probeTimeout>` before taking the host's lock. It SHALL end every request with exactly one of: 0 deployed, 3 refused, 4 busy, 5 unreachable, 6 failed, 7 unhealthy, 8 rolled back, 9 unconfirmed. The health check SHALL run `settle` seconds after the deploy command returns and requires:
- SSH answers;
- the target's newest `/var/log/deploy-record.jsonl` line has `closure` equal to the deployed toplevel;
- on NixOS, `systemctl --failed` lists no unit;
- on darwin, every `org.nixos.*` job in `launchctl list` has last exit status 0 or none.

#### Scenario: an unreachable target in the VM test
- **WHEN** the VM test stops the target's sshd and sends a request
- **THEN** the request exits 5 within 15 s and `/run/fleet-deployer/lock/target` was not created

#### Scenario: a failed unit in the VM test
- **WHEN** the VM test deploys a closure with a failing unit
- **THEN** the request exits 7 naming the unit, and the target keeps that closure after the confirm window

### Requirement: The target arms its own rollback before the deploy

Before the deploy command runs, `fleet-deploy-request` SHALL read the target's `/run/current-system` as the previous closure and arm the watcher. On NixOS it stops stale watchers and starts `fleet-deploy-watch <id> <activationWait> <confirmWindow>` through `systemd-run --unit fleet-deploy-watch-<id>`. On darwin it runs `sudo fleet-deploy-watch --arm <id> <activationWait> <confirmWindow>`, which bootstraps the job declared by the target's configuration into launchd's system domain, so the watcher runs as root, and fails while that job is already loaded. The watcher SHALL:
- record `/run/current-system`;
- wait up to `activationWait` seconds for it to change, and then up to `confirmWindow` seconds for `/run/fleet-deploy/<id>.confirmed` (`/var/run/fleet-deploy/` on darwin);
- end without rolling back as soon as that file exists, during either wait, so a deploy of the running closure ends it at its confirmation;
- when that file is absent, set a new system profile generation to the recorded system and activate it;
- unload its own launchd job on every path.

Every darwin target's configuration SHALL declare that job in launchd's `system` domain, with no user other than root, not kept alive, running `fleet-deploy-watch --run`.

`fleet-deploy-request` SHALL create the file as soon as SSH answers after the settle period, and SHALL stop the watcher when the deploy command fails. When the file cannot be created, it SHALL read the target's `/run/current-system` until `confirmWindow + rollbackGrace` seconds have passed. It SHALL end with status 8 only once the target runs the previous closure, and with status 9 otherwise.

#### Scenario: the confirm never arrives in the VM test
- **WHEN** the VM test deploys a closure whose firewall drops the deployer's SSH
- **THEN** the request exits 8. The target's current system is the previous closure again within 60 s after it, and its newest deploy record names the previous closure with the dropped closure as `previous_closure`.

#### Scenario: the confirm fails while the target keeps the deployed closure
- **WHEN** `checks.x86_64-linux.fleet-deploy-request` deploys to a fixture darwin target whose confirmation fails and whose running system stays the deployed closure
- **THEN** the request exits 9, `unconfirmed`, and is not reported rolled back; the same target read back on its previous closure exits 8

#### Scenario: a darwin watcher outside the system domain
- **WHEN** a darwin target's watcher job is declared in another domain, for another user, kept alive or running another program
- **THEN** its `darwin-<host>` machine check fails evaluation naming the problem

### Requirement: Every request is written to the request log and posted to ntfy

`fleet-deploy-request` SHALL append one JSON line to `/var/lib/fleet-deployer/requests.jsonl` (mode `0600`) for every request, refusals included. The line holds `ts`, `id`, `requester`, `command`, `session`, `machine`, `target`, `commit`, `closure`, `previous`, `outcome`, `reason` and `finished`. `target` is the requested target as received, every word between `deploy` and the commit or `--session`, and is null when the command was refused before it. `previous` is the target's running system read before the deploy. `fleet-deploy-notify`, a root oneshot started by a path unit on that file, SHALL post each new line once through `ntfy-send` to the topic `fleet-deploy`, with `Priority: high` for `refused`, `unhealthy`, `rolled-back` and `unconfirmed`, reading the token from the alerter token file.

#### Scenario: notices in the VM test
- **WHEN** the VM test has sent all its requests
- **THEN** the recording `ntfy-send` holds one post per request line on topic `fleet-deploy`, each starting with its outcome, high priority exactly for the four outcomes, and the request log has mode `0600`

### Requirement: The deployer's keys are readable by its account only

On the deployer host:
- `fleet-deployer-keys` SHALL run with `UMask=0277`;
- `systemd.tmpfiles` SHALL declare `/var/lib/fleet-deployer/keys` mode `0700` owned by `fleet-deployer`;
- `fleet-deployer-keycheck.service` SHALL fail when `keys/`, `keys/age.key` or `keys/id_ed25519` have another mode or owner, or when their public halves differ from `flake.lib.fleetDeployer.keys`.

No other machine SHALL declare the `fleet-deployer` account or its key service.

#### Scenario: a key file is widened in the VM test
- **WHEN** the VM test makes `age.key` mode `0440`
- **THEN** `fleet-deployer-keycheck.service` fails, and passes again once the mode is restored

#### Scenario: the declared modes are widened
- **WHEN** the host judge is given a deployer host whose key directory is declared `0755` or whose key service runs with `UMask=0077`
- **THEN** it yields exactly one problem for each
