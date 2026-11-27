## ADDED Requirements

### Requirement: A320 — clan reads a public var's value as the committed file, untrimmed, at a path fixed by machine, generator and file

It is true of clan-core at the locked revision 78d5de23, independent of what this fleet builds, that an `in_repo` public vars file's value is the untrimmed contents of `<directory>/vars/per-machine/<machine>/<generator>/<file>/value`, or of `<directory>/vars/shared/<generator>/<file>/value` for a shared generator.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: clan-core 78d5de23, `nixosModules/clanCore/vars/public/in_repo.nix:14-21` (`flakePath = settings.directory + "/vars/${rel_dir}/${name}/value"`; `value = readFile flakePath` when the file exists). The value of each NixOS host's `openssh` public key, forced on 2026-11-26, ends in `" \n"` (`logs/cross-host-eval-cost-c-20261126-174313.log`), and each committed `vars/per-machine/<h>/openssh/ssh.id_ed25519.pub/value` ends in a newline.

#### Scenario: Read at the source and forced on 2026-11-26

- **WHEN** the file above was read and the six NixOS hosts' `openssh` public values were forced on 2026-11-26
- **THEN** the path form and the untrimmed read were as stated, and each value equalled its committed file byte for byte

#### Scenario: Secret files and recipients share the layout

- **WHEN** the committed tree of a secret vars file is read at that revision
- **THEN** its encrypted contents sit at the same location with `secret` in place of `value`, and its recipients at `machines/<m>`, `users/<u>` and `groups/<g>` beside it

#### Scenario: clan changes the public store

- **WHEN** a clan-core update moves the public value file, renames `rel_dir`'s form, trims the value, or makes `in_repo` no longer the public store; the own-host host-key obligation failing on every NixOS host at once is how this shows
- **THEN** this assumption is void; the `host-configuration-independence` requirement `Each host takes other hosts' host keys from the keys the fleet pins` and the `host-configuration-independence-interface` requirements on `flake.lib.vars` and `flake.lib.hostKeys` lose their discharge until the accessor is restated against the new layout

### Requirement: A321 — The sshd service's host key generator is per machine and its public half is public

It is true of clan-core's sshd service at the locked revision, independent of what this fleet builds, that it declares a vars generator `openssh` with a secret file `ssh.id_ed25519` and a public file `ssh.id_ed25519.pub`, without `share`, produced by `ssh-keygen -t ed25519 -N "" -C ""`, and that the host's sshd presents that key.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: clan-core 78d5de23, `clanServices/sshd/default.nix:29-31` (the host key path) and `:41-51` (the generator).

#### Scenario: Read at the source on 2026-11-26

- **WHEN** the sshd service was read on 2026-11-26
- **THEN** the generator's name, files, absence of `share` and key type were as stated

#### Scenario: The sshd service changes its generator

- **WHEN** a clan-core update renames the generator or its files, shares it across machines, or makes sshd present a different key
- **THEN** this assumption is void; `flake.lib.hostKeys` may read a file sshd no longer presents, and the `host-configuration-independence` requirement `A host whose configuration presents a host key other than its pinned one fails before deploy` loses its discharge until the obligation is restated against the new generator

### Requirement: A322 — A committed file reads the same through a repository path and through the flake source string

It is true of Nix as this fleet evaluates it that `readFile`, `pathExists` and `hashFile` on a file of this repository give the same result whether it is named by a path relative to a module file or by the string `"${self}/<relative path>"`, and that interpolating such a path into a string copies only that file into the store.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: observed 2026-11-27. The flake source is a store path without references, so neither form carries a string context; `just drv-diff 390f72f0c809 bbb7c5ccc978` (`logs/drv-diff-390f72f0c809-bbb7c5ccc978-20261127T033555Z`, re-judged `report.20261127T035524Z`, exit 0) found every system, home and vm-test drvPath unchanged across six readers that moved from the string form to the path form.

#### Scenario: The drvPath diff is taken

- **WHEN** the before/after drvPath diff of every system, home and check output is taken across a change that switches readers between the two forms
- **THEN** an empty diff confirms this assumption for the forms that change used

#### Scenario: The two forms diverge

- **WHEN** a drvPath moves at a site whose only change was the form of the name, or a Nix update gives `readFile` of a source-tree string a store context
- **THEN** this assumption is void; the `host-configuration-independence-interface` requirement `Every reader of the committed vars tree uses one accessor and keeps its read` loses its discharge for that site until the site is restored to its previous form

### Requirement: A323 — The evaluation cost of other hosts' configurations on stibnite, measured 2026-11-26

It is true of the fleet at revision 53c949b30, measured on stibnite on 2026-11-26 with one fresh evaluation per figure, independent of this change, that the four evaluations in the scenario below cost the CPU time, thunks and bytes allocated stated there.
Any requirement whose discharge depends on this fact SHALL name it explicitly, and SHALL lose its discharge once the violation below is observed.

**Evidence**: `logs/cross-host-eval-cost-{b,b2,base-host,c,d}-20261126-*.stats.json` (`cpuTime`, `nrThunks`, `gc.totalBytes`). Differences between these figures are upper bounds on any saving, because the parts of the work may overlap.

#### Scenario: Measured on 2026-11-26

- **WHEN** the five stats files were read on 2026-11-26
- **THEN** they gave:
  - stibnite's toplevel derivation: 10.97 s of CPU, 24,376,302 thunks, 3,148,532,208 bytes (a repeat gave 10.70 s with the same thunk count);
  - stibnite's host-only baseline: 0.39 s, 681,965 thunks, 138,745,408 bytes;
  - forcing stibnite's `programs.ssh.knownHosts`: 1.37 s, 4,402,939 thunks, 562,100,704 bytes;
  - forcing magnetite's `stibnite-agent-session` public value alone: 0.57 s, 1,182,490 thunks, 176,070,096 bytes.

#### Scenario: The baseline moves before the after-measurement

- **WHEN** the before-measurement this change takes at its parent revision differs from these figures by more than run-to-run variance
- **THEN** this assumption is void as the comparison point; the `host-configuration-independence-interface` requirement `The evaluation saving is measured, not inferred` is discharged against the parent-revision measurement instead
