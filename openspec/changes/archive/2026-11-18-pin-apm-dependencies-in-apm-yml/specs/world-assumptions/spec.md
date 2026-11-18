## ADDED Requirements

### Requirement: A136 — apm installs a locked remote dependency from apm_modules without fetching

It is true of apm 0.36.x, independent of what this fleet builds, that `apm install` with a lock recording a remote dependency and that dependency's tree in `apm_modules` installs it without git or network.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: 2026-11-18 spike and magnetite sandbox runs, 10/10 `(cached)` (`logs/apm-sandboxlinux-compose-*`).

#### Scenario: apm stops reusing apm_modules

- **WHEN** the pinned apm leaves 0.36.x before this evidence is re-run, or an offline install with a matching lock and tree attempts a fetch
- **THEN** this assumption is void, and `third-party-plugin-dependency` requirement `The composition installs remote apm dependencies offline from the download` loses its discharge

### Requirement: A137 — apm installs a virtual-subdirectory dependency as that directory alone

It is true of apm 0.36.x that an `owner/repo/<path>#<sha>` dependency installs only `<path>` as the package root, so files outside it, hooks included, are never seen.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: experiments E3, E9 and E10 and the v7.0.2 addendum run f1 (`logs/apm-superpowersd1-*`).

#### Scenario: a subdirectory dependency brings repository files

- **WHEN** the pinned apm leaves 0.36.x before this evidence is re-run, or a subdirectory dependency installs a hook or file from outside its path
- **THEN** this assumption is void, and `third-party-plugin-dependency` requirement `superpowers and agency are consumed per skill directory` loses its discharge

### Requirement: A138 — apm removes a downloaded package whose content no longer matches its lock

It is true of apm 0.36.x that an installed package whose tree differs from its lock's content hash is deleted and re-fetched rather than used.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: F6, `apm_cli/install/phases/integrate.py:281-300` (`logs/apm-verify-f5f6v-*`).

#### Scenario: an edited download is used

- **WHEN** the pinned apm leaves 0.36.x before this evidence is re-run, or an install uses a package whose tree differs from its locked hash
- **THEN** this assumption is void, and `third-party-plugin-dependency` requirement `Upstream tool skills are delivered unmodified` loses its discharge

### Requirement: A139 — apm's download bytes change only with apm's version

It is true of apm that, for full-SHA refs, its download is byte-identical across runs and platforms for one apm version, and differs between versions only through apm's own normalization (0.36 carries each repository LICENSE into every skill).
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: U1, R2 and R3 (`logs/apm-verify-r3-*`, `logs/apm-sandboxlinux-deps-*`).

#### Scenario: the same apm version yields different bytes

- **WHEN** a cold build of the download under an unchanged apm version reports a hash mismatch
- **THEN** this assumption is void, and `third-party-plugin-dependency` requirement `Remote apm dependencies are downloaded in one guarded fixed-output derivation` loses its discharge

### Requirement: A140 — apm lock records commits and content hashes but no deployed files

It is true of apm 0.36.x that `apm lock` writes, per remote dependency, its resolved commit and content hash, with no deployed-files records, so `--frozen` cannot install from it.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: U3 and F5 (`logs/apm-verify-f5f6v-*`).

#### Scenario: the lock shape changes

- **WHEN** the pinned apm leaves 0.36.x before this evidence is re-run, or its `apm lock` output gains deployed files or loses commits or content hashes
- **THEN** this assumption is void, and the `third-party-plugin-dependency` requirements `Remote apm dependencies are downloaded in one guarded fixed-output derivation` and `The composition installs remote apm dependencies offline from the download` lose their discharge

### Requirement: A141 — GitHub serves a shallow, blobless fetch of a commit by its SHA

It is true of GitHub that `git fetch --depth 1 --filter=blob:none <url> <sha>` retrieves that commit's tree without a branch or tag naming it.
Any requirement relying on this SHALL name it and SHALL lose its discharge once the condition below is observed.

**Evidence**: to be observed by this change's first task inside the fixed-output sandbox; apm's own full-SHA fetches succeeded there (R1, R2).

#### Scenario: GitHub refuses a fetch by SHA

- **WHEN** the download's superpowers-list step fails to fetch the declared commit while GitHub is reachable
- **THEN** this assumption is void, and `third-party-plugin-dependency` requirement `superpowers and agency are consumed per skill directory` loses the discharge of its upstream-list scenario
