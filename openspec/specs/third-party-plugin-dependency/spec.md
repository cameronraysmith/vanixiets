# third-party-plugin-dependency Specification

## Purpose
TBD - created by archiving change apm-skills-marketplace. Update Purpose after archive.

## Requirements

### Requirement: Remote apm dependency commits are written once, in the declaring package's manifest

Each remote apm dependency's commit MUST be written only in the `dependencies.apm` entry of the declaring first-party package's `apm.yml`, as a full 40-character lowercase hexadecimal SHA.
No Nix expression SHALL carry a second copy of that commit to compose the dependency.
Evaluation SHALL fail, naming the manifest, the entry and the ref, when a remote ref is not such a SHA or an entry has a form the evaluation cannot read.
Only the root manifest MAY declare local-path dependencies.

#### Trust boundary

Evaluation establishes where each commit is written and that every ref is a full SHA. It does not establish that a pinned upstream commit is benign.

#### Scenario: a ref that is not a full commit SHA

- **WHEN** a remote entry in any first-party package manifest declares a branch name, a tag, or a shortened SHA as its ref
- **THEN** evaluation of the composition fails with a message naming the manifest, the entry and the ref

#### Scenario: an entry in an unreadable form

- **WHEN** a remote entry is written in a YAML shape other than the `owner/repo[/path]#ref` string form or the `git:` object form, such as a flow mapping or a quoted value
- **THEN** evaluation fails naming the manifest, rather than skipping the entry

---

### Requirement: Remote apm dependencies are downloaded in one guarded fixed-output derivation

Nix SHALL obtain every remote apm dependency in one fixed-output derivation that runs apm's own resolution over the generated root consumer manifest and outputs the downloaded trees plus a lock of the remote entries only, under one committed `apmDepsHash`.
Its name SHALL carry a digest, computed at evaluation time from the committed manifests without import-from-derivation, over every key of every remote entry, the package declaring it, and the apm version.

#### Trust boundary

Evaluation and build results establish that the download's name changes whenever a remote entry or the apm version changes, and that its bytes match `apmDepsHash`. They do not establish that a rebuild of the same apm version produces the same bytes: such a change is reported as a hash mismatch only on a machine that does not already hold the earlier download.

#### Scenario: the download is identical across build platforms

- **WHEN** the fixed-output derivation is built from the same committed manifests and apm version on x86_64-linux and on aarch64-darwin
- **THEN** both builds produce output with the same NAR hash, equal to the committed `apmDepsHash`

#### Scenario: a changed ref without a hash update

- **WHEN** a remote entry's ref changes and `apmDepsHash` does not, on a machine whose store already holds the download built from the previous ref
- **THEN** the download's derivation name changes, Nix builds it, and the build fails with a hash mismatch that prints the new output hash

#### Scenario: an apm version change without a hash update

- **WHEN** the apm version in use changes, its output differs from the previous version's, and `apmDepsHash` is not updated
- **THEN** the download's derivation name changes and the build fails with a hash mismatch that prints the new output hash

#### Scenario: unrelated edits do not refetch

- **WHEN** a commit changes only first-party skill content, manifest descriptions, comments, or the order of remote entries
- **THEN** the download's derivation name is unchanged and the composition reuses the existing download without fetching

#### Scenario: the generated lock is reproducible

- **WHEN** the fixed-output derivation completes
- **THEN** its lock lists only the remote dependencies, each with its resolved commit and content hash, and carries no generation timestamp or apm version field

---

### Requirement: The composition installs remote apm dependencies offline from the download

`apm-skills-compose` SHALL install every remote apm dependency with plain `apm install` from the fixed-output download, with no network access and no git executable, and SHALL NOT write into apm's cache directory before installing.

#### Trust boundary

The build establishes that the composition resolves every remote dependency from the download inside a network-isolated sandbox. It does not establish that a harness loads the composed skills.

#### Scenario: offline root-manifest composition

- **WHEN** the composition generates a root consumer `apm.yml` whose `dependencies.apm` lists the first-party package directories as local relative paths, copies the download's `apm_modules/` and lock under the install root `$out`, and runs `apm install --root $out` with no git executable on PATH inside a network-isolated build
- **THEN** every remote dependency resolves from the download, the install exits 0, and the composed `.claude/skills` and `.agents/skills` trees contain every first-party skill and every skill the remote entries select

#### Scenario: the download is withheld

- **WHEN** the composition runs inside a network-isolated build without the download, or with one remote dependency removed from it
- **THEN** the install fails for the missing dependencies rather than fetching them

---

### Requirement: superpowers and agency are consumed per skill directory

superpowers and agency SHALL be consumed as one apm virtual-subdirectory dependency per skill directory, at one shared commit per repository, unforked and with the downloaded trees unedited.
superpowers' entries SHALL name every directory under `skills/` at that commit and nothing else; agency's SHALL name exactly `hickey`, `lowy` and `fact-check` under `.apm/skills/`.
No hook file or settings entry from either repository SHALL reach any install target.

#### Trust boundary

Install results and file listings establish which skills and hook files a plain apm install and the Nix composition produce for the tested targets and apm version. They do not establish how a marketplace user's own apm version, harness or prior installs behave, and per-skill consumption by construction omits superpowers' SessionStart bootstrap and agency's subagents and rule.

#### Scenario: a plain apm install succeeds for every target with no hooks

- **WHEN** plain apm installs `planning-and-development` for each of the `claude`, `agent-skills`, `cursor`, `codex`, `copilot`, `opencode` and `gemini` targets
- **THEN** each install exits 0, every listed superpowers and agency skill is present in the target's skills directory, and no hook file or settings entry from `obra/superpowers` or `srid/agency` is written

#### Scenario: both composed trees carry the per-skill dependencies

- **WHEN** the Nix composition runs for the `agent-skills` and `claude` targets
- **THEN** all listed superpowers and agency skills are present under both `.claude/skills` and `.agents/skills`, and no file under either tree links into `apm_modules`

#### Scenario: the superpowers list diverges from upstream

- **WHEN** the superpowers commit is bumped to one whose `skills/` directory adds or removes a skill and the manifest's list is not updated to match
- **THEN** the build of the fixed-output download fails, naming the skills present upstream but not declared, or declared but absent upstream

---

### Requirement: A same-ref check guards the per-skill upstream dependencies

A check SHALL fail, naming the manifest, the entry and the refs, when the entries for `obra/superpowers` or `srid/agency` across all first-party manifests carry more than one ref, when any of those refs is not a full commit SHA, when an entry names either repository without a skill-directory path, or when a path is not exactly one skill directory (`skills/<name>` or `.apm/skills/<name>`).

#### Trust boundary

The check establishes the shape and agreement of the committed entries. It does not establish that the shared commit is the intended release.

#### Scenario: a whole-repository entry or a mixed ref

- **WHEN** a first-party manifest declares `obra/superpowers` or `srid/agency` without a skill-directory path, or declares two entries for one of those repositories at different refs
- **THEN** the same-ref check fails, naming the manifest, the entry and the refs

---

### Requirement: Upstream plugins are extended additively without forking

Extension of an upstream plugin MUST be additive co-shipping rather than patch or override, since apm provides no patch or override mechanism.
A dependency source that lacks any packaging signal MUST gain one before it can be consumed.
The `openspec-schemas-superpowers-bridge` SHALL remain an OpenSpec schema delivered by its own home-manager module, neither forked nor given an apm packaging signal.

#### Trust boundary

Inspection of the composition and the manifests establishes how a collision is resolved and that no patch layer exists. It does not establish which of two same-name skills a harness prefers.

#### Scenario: additive co-ship with no patch or override

- **WHEN** first-party skills are shipped alongside an upstream plugin's skills and a same-name collision occurs
- **THEN** the collision is resolved by precedence or `--force`, not by any declarative patch or override layer

---

### Requirement: Each CLI and its agent skill resolve to the same upstream release

For mergify-cli, linear-cli, playwright-cli, worktrunk and gh-stack, whose agent skills come from the same upstream release as the tool, the tool's Nix package SHALL record that release's commit, and a structural check SHALL fail, naming both values, when the skill's `apm.yml` ref differs from it.
None of those sources SHALL feed the apm composition.

#### Trust boundary

Evaluation and build results establish that each recorded commit equals the skill's declared ref. Where a package fetches by tag or by release asset rather than by commit, they establish that the recorded commit is the tagged one only to the extent a check refetches the tagged tree at that commit; they do not establish that the upstream guidance is correct.

#### Scenario: tool and skill releases agree

- **WHEN** the release-alignment check reads each tool's recorded commit (`mergify-cli-bin.passthru.sourceRev`, `linear-cli.skillSrc.rev`, `playwright-cli.src.rev`, `worktrunk-bin.passthru.sourceRev`, `gh-stack.passthru.sourceRev`) and the corresponding skill's `apm.yml` ref
- **THEN** each pair is equal and every alignment check build succeeds

#### Scenario: a skill drifts from its tool's release

- **WHEN** a tool's package is bumped to a new release and the skill's `apm.yml` ref is left at the earlier commit, or the reverse
- **THEN** that pair's alignment check fails, naming the recorded commit and the declared ref

---

### Requirement: The release-alignment checker is exercised with a deliberate mismatch

The repository SHALL run the release-alignment comparison on unequal fixtures in a negative control that passes only when the comparison rejects them and its diagnostic names both fixture values.

#### Trust boundary

The negative control establishes that the comparison can fail. It does not establish that every pair is wired to it.

#### Scenario: the checker rejects unequal values

- **WHEN** the negative control invokes the shared comparison with two different commits
- **THEN** the invocation fails, the diagnostic names both values, and the negative control passes

---

### Requirement: Upstream tool skills are delivered unmodified

The upstream skills and reference files of the aligned tools MUST remain unedited, and a structural check SHALL fail when the delivered `playwright-cli` skill in either composed tree differs from `skills/playwright-cli` in `playwright-cli.src`, excluding carried license files.

#### Trust boundary

Byte comparison establishes that delivered files equal the release source. It does not establish that the guidance in them is correct.

#### Scenario: upstream skills compose without modification

- **WHEN** the composition installs a tool's skill from the fixed-output download
- **THEN** the skill and its reference files match the upstream tree at the declared commit without patching, forking or rewriting, and the delivered `playwright-cli` skill equals `skills/playwright-cli` in `playwright-cli.src` apart from license files

---

### Requirement: A remote apm dependency bump is one reviewed manifest edit

Bumping a remote apm dependency SHALL require editing only its `ref:` lines in the declaring package's `apm.yml` (all of a repository's lines together) and the committed `apmDepsHash`, plus, for an aligned tool, the tool's recorded commit; no other file SHALL need to change for the composed trees to reflect the bump.

#### Trust boundary

The diff and the build establish which files a bump touches and that the composed trees reflect it. They do not establish that the root lock was refreshed.

#### Scenario: a bump touches two places

- **WHEN** a remote dependency is moved to a new commit
- **THEN** the change edits the dependency's `ref:` lines and `apmDepsHash` (plus the tool's recorded commit for an aligned tool) and no other file
- **AND** the composition builds and its trees contain the skills at the new commit

---

### Requirement: The root apm lock is refreshed after a dependency change reaches main

The root `apm.lock.yaml` SHALL be refreshed by `just agents-relock`, reviewed and committed only after a dependency change reaches `main`, because that relock resolves the first-party packages from GitHub `main` (`modules/apps/apm-skills-install.sh`) and cannot see an unmerged edit.
Until then, Nix-composed `$out` evidence SHALL NOT be claimed for repository-local `.agents/` delivery.

#### Trust boundary

The repository history establishes when the root lock was regenerated. It does not establish that the root lock matches `main` at any later time.

#### Scenario: the root lock follows the merge

- **WHEN** a dependency change is on a branch whose root manifest still resolves the first-party packages from `main`
- **THEN** the branch leaves the root `apm.lock.yaml` unchanged, and a fresh frozen `just agents-install` materializes the pre-change set
- **AND** after the change reaches `main`, `just agents-relock` regenerates the root lock, which is reviewed and committed before frozen repository-local delivery of the changed dependency is claimed

### Requirement: A whole-plugin upstream is consumed through a skill list equal to its plugin manifest

A remote apm dependency on a repository that publishes a Claude plugin manifest (today `mattpocock/skills`) SHALL be declared with a `skills:` list naming exactly the skill directories that upstream's `.claude-plugin/plugin.json` lists at the declared commit, so that apm deploys them flat rather than the whole plugin.
The fixed-output download SHALL fail when the declared list differs from upstream's.

**Relies on**: A214.

#### Trust boundary

The download's build establishes that the declared list equals upstream's manifest at the declared commit. It does not establish that every listed skill is wanted, or that upstream's list is complete with respect to its repository.

#### Scenario: the list diverges from upstream

- **WHEN** the declared commit is bumped to one whose plugin manifest adds or removes a skill and the `skills:` list is not updated to match, or a name is removed from the list
- **THEN** the build of the fixed-output download fails, naming the skills listed upstream but not declared, or declared but not listed upstream

#### Scenario: the selection is removed

- **WHEN** the `skills:` list is removed from the entry
- **THEN** the composition fails because the plugin's skills are missing from the flat trees
