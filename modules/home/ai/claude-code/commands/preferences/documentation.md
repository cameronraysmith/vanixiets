# Documentation

## References

1. Méndez Fernández, D., Penzenstadler, B.: Artefact-based requirements
   engineering: The AMDiRE approach. Requir. Eng. 20, 405–434 (2015).
   https://arxiv.org/abs/1611.10024
2. Chuprina, T., Mendez, D., Wnuk, K.: Towards artefact-based requirements
   engineering for data-centric systems. arXiv [cs.SE]. (2021)
3. ISO/IEC/IEEE international standard - systems and software engineering
   – life cycle processes – requirements engineering, (2018)
4. IEEE standard for information technology–systems design–software design
   descriptions, (2009)
5. Diátaxis: A systematic approach to technical documentation authoring.
   https://diataxis.fr.

## Location

- Most repositories use `docs/` for their active documentation but some have
  both `docs/` and another directory like `site/`, `website/`, `nbs/`, etc.
- Most `README.md` files in the repository root should aim to include minimal
  content with relevant links to the docs website unless they do not yet have
  docs.

## Structure

Generally assume we intend to follow this standard structure for repository
documentation combining user-facing and development documentation:

```
docs/
├── tutorials/           # Diataxis: Learning-oriented lessons
├── guides/              # Diataxis: Task-oriented how-tos
├── concepts/            # Diataxis: Understanding-oriented explanations
├── reference/           # Diataxis: Information-oriented API docs (optional)
├── about/               # Contributing, conduct, links into development
├── development/         # Development documentation (adapted AMDiRE-based)
│   ├── index.md         # Development overview and navigation
│   ├── context/         # Context Specification (problem domain)
│   │   ├── index.md     # Context overview and table of contents
│   │   └── context.md   # Problem domain, stakeholders, objectives
│   ├── requirements/    # Requirements Specification (problem ↔ solution bridge)
│   │   ├── index.md     # Requirements overview and traceability matrix
│   │   └── requirements.md  # Functional/non-functional requirements
│   ├── architecture/    # System Specification (solution space)
│   │   ├── index.md     # Architecture overview and table of contents
│   │   └── architecture.md  # System design and component structure
│   ├── traceability/    # Requirements traceability
│   │   ├── index.md     # Traceability overview
│   │   └── testing.md   # Test framework and validation approach
│   └── work-items/      # Work packages and implementation tracking
│       ├── index.md     # Work items overview and status dashboard
│       ├── active/      # In-progress work items
│       ├── completed/   # Finished items with PR/ADR/RFC/RFD references
│       └── backlog/     # Planned but not yet started items
└── notes/               # EPHEMERAL: Working notes excluded from rendering
    └── [category]/      # Temporary staging (see "Working notes" section)
```

### Document evolution

Many projects will begin with only `docs/development/` and add the user docs
directories later. Initial development drafts context.md, requirements.md,
architecture.md, and testing.md as single comprehensive documents. As complexity
grows—expected for most real projects—decompose each document by major
subsection into separate files with descriptive names (e.g., context.md →
stakeholders.md, objectives.md, constraints.md). Update the corresponding
index.md to serve as table of contents and navigation after sharding. This
pattern maintains manageability while preserving traceability as documentation
scales. If the documentation becomes sufficiently complex, we can continue to
refactor into a directory tree with additional levels.

### Working notes

The `docs/notes/` directory serves as ephemeral staging for development notes
that have not been formalized into the permanent documentation structure. These
notes are explicitly temporary and must be either migrated to formal
documentation or discarded.

**Organization**: Use category-based subdirectories with kebab-case filenames:
```
docs/notes/
├── security/           # Security investigations
├── architecture/       # Architectural exploration
├── performance/        # Performance analysis
└── [category]/         # Other categorized notes
```

**Exclusion from rendering**: Working notes must never appear in rendered
documentation sites. Configure your documentation system accordingly:

- **Astro** (content collections): Only include specific directories in
  `src/content/config.ts`, implicitly excluding `notes/`
- **Quarto** (`_quarto.yml`):
  ```yaml
  project:
    render:
      - "!docs/notes/**"
  ```
- **Docusaurus** (`docusaurus.config.js`):
  ```javascript
  docs: {
    exclude: ['**/notes/**']
  }
  ```
- **MkDocs** (`mkdocs.yml`):
  ```yaml
  exclude_docs: |
    notes/
  ```

**Lifecycle**: Every working note must eventually follow one of two paths:

1. **Migrate to formal documentation**: Extract valuable insights, revoice from
   informal working notes to formal documentation style, and move content to the
   appropriate location in the user-facing docs (`tutorials/`, `guides/`,
   `concepts/`, `reference/`) or development docs
   (`development/context/`, `development/requirements/`,
   `development/architecture/`, etc.). Delete the working note after migration.

2. **Discard when no longer relevant**: Delete notes that served temporary
   investigation purposes, documented abandoned approaches, or have been
   superseded by other documentation.

Working notes should not persist indefinitely. Regularly audit `docs/notes/` for
stale content and progress notes through their lifecycle. The goal is to keep
this directory empty or minimal in stable projects.

**Relationship to work items**: Unlike `docs/development/work-items/` which
maintains a permanent record of development efforts with traceability to issues
and PRs, working notes in `docs/notes/` are ephemeral drafts that get cleaned
up after their content is either formalized or determined to be no longer needed.

### Markdown formatting conventions

Some documentation generators like Astro Starlight require markdown files to use YAML frontmatter with a title like
```yaml
---
title: "Title: subtitle"
---
```
instead of the `# Title: subtitle` format.
As such it's best to primarily use this convention when authoring markdown.
Note that quotes are required in YAML when the title contains special characters like colons; simple titles without special characters don't require quotes.
Not all markdown documents require subtitles—the subtitle format is shown here for completeness to demonstrate proper quoting.

Plain markdown systems (GitHub, static markdown) also support frontmatter titles, making this convention broadly compatible.
When working in a documentation directory, check for frontmatter in existing files to confirm the convention in use.
If files contain `title:` in YAML frontmatter, use `##` to start content sections to avoid duplicate titles in rendered output.

Consecutive `**Term**: description` lines merge into one paragraph when rendered.
Use `- **Term**: description` bullet format for 2+ definitions.

### Key principles

- Separate user documentation (diataxis framework) from development
  documentation (AMDiRE methodology)
- User docs focus on helping users learn, accomplish tasks, understand concepts,
  and find reference information
- Development docs provide traceability: context (why) → requirements (what) →
  architecture (how) → work items (implementation)
- Work items bridge planning to execution with workflow state tracking (backlog
  → active → completed)
- Maintain bidirectional traceability between requirements, architecture
  decisions, and implementation artifacts
- Reference GitHub issues, pull requests, ADRs, RFCs, or RFDs in completed work
  items for full audit trail
- Name files in the work-items directory using the pattern
  `<issue-id>-<very-short-description>.md` with zero-padded issue IDs to support
  up to four digits (e.g. GitHub issue #12 becomes `0012-description.md` in
  `work-items`).

## Code

- In code, prefer docstrings relevant to a given programming language over code comments
  as the docstrings end up in `docs/reference/` files automatically generated by
  most language API reference documentation tools.
- Only add comments to code for reference or to explain awkward or complex code,
  but prefer to include it in docstrings when possible.

## Maintenance

- When making code changes, immediately identify all affected documentation artifacts
  with surgical precision:
  - `docs/development/context/` if problem domain or stakeholders change
  - `docs/development/requirements/` if functional/non-functional requirements change
  - `docs/development/architecture/` if design decisions, components, or technology change
  - `docs/development/traceability/` if test strategy or validation approach changes
  - `docs/development/work-items/` for implementation status tracking
  - Repository README.md and user-facing docs/ if behavior changes
- Update affected documentation immediately in the same session, not at an undetermined
  future point.
- Commit documentation updates atomically in series with the related code changes,
  following the same proactive atomic commit workflow specified in
  `~/.claude/commands/preferences/git-version-control.md`.
- Be judicious in the use of documentation, ensuring that it is clear, concise,
  and accurate for humans to read and understand.
- Proactively remove, refactor, and consolidate documentation as relevant to
  maintain optimal correspondence between the code and documentation.
