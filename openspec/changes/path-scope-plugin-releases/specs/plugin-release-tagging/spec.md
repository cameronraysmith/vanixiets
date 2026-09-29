## ADDED Requirements

### Requirement: Path-scoped release line for the plugins tree

The repository SHALL provide a semantic-release line whose commit analysis is scoped to `modules/home/ai/plugins/`, distinct from the existing `packages/docs` release line, extending `semantic-release-monorepo` from a package manifest that lives inside the scoped directory itself.
On a qualifying release, this line SHALL produce a canonical tag identifying the release and, at the same commit, one lightweight alias tag per first-party plugin directory named `<directory-name>-v<version>`.

This interface establishes that the release line exists, is scoped to the correct directory, and produces the named tags at the release commit.
It does not establish that any particular commit deserves a release — that judgment remains semantic-release's own commit-analyzer behavior — and it does not establish that a downstream consumer correctly resolves the pushed tags.

#### Scenario: Commit under the plugins tree is analyzed for release

- **WHEN** a commit reaching `main` touches a file at or below `modules/home/ai/plugins/`
- **THEN** that commit is included in the plugins release line's next commit analysis
- **AND** a commit touching only files outside `modules/home/ai/plugins/` is excluded from that analysis

#### Scenario: A qualifying release mints the canonical tag and every alias tag together

- **WHEN** the plugins release line determines a release is due
- **THEN** it creates the canonical release tag and one alias tag per first-party plugin directory that exists at that commit
- **AND** every alias tag and the canonical tag point at the same commit

#### Scenario: Alias tag name matches its directory exactly

- **WHEN** an alias tag is created for a first-party plugin directory
- **THEN** the alias tag's name is that directory's own name followed by `-v` and the release version, with no additional prefix or suffix

---

### Requirement: Existing release infrastructure owns tag creation and push

Tag creation and push for the plugins release line SHALL be performed by the same effect that already performs this role for the existing `packages/docs` release line, authenticated the same way, with no new release-execution mechanism introduced for this line.

This interface establishes which system component is authoritative for pushing plugins-release tags.
It does not establish that GitHub Actions plays any role in that push — the deprecated GitHub Actions release workflows are out of scope for this requirement and MUST NOT be reactivated to satisfy it.

#### Scenario: The existing release effect discovers and dispatches the new release line

- **WHEN** the effect that iterates every discoverable release package runs on a push to `main`
- **THEN** it discovers the plugins release line's package manifest using the same discovery mechanism it already uses for `packages/docs`
- **AND** it dispatches the same per-package release runner against it, unmodified

#### Scenario: A rehearsal run exercises the plugins release line without pushing tags

- **WHEN** the hermetic `release-rehearsal` check, which runs the release effect's program against stubs, is built for a commit touching `modules/home/ai/plugins/`
- **THEN** the plugins release line is analyzed and a rehearsal outcome is reported
- **AND** no tag is pushed to the remote as a result
