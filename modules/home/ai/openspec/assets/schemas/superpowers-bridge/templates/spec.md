<!--
Delta spec template for a change.

This template demonstrates the four delta section types; use whichever the change actually needs:
- ADDED / MODIFIED / REMOVED / RENAMED
File name and location: openspec/changes/<change-name>/specs/<capability>/spec.md
(`<capability>` matches the openspec/specs/<capability>/ directory name)

Hard formatting rules (OpenSpec will validate these):
- The Requirement sentence MUST contain `SHALL` or `MUST`
- Every Requirement MUST have at least one `#### Scenario:`
- A Scenario MUST use level-4 (`####`); level-3 or a bullet will silently fail
-->

## ADDED Requirements

<!-- New behavior. List the new Requirements this change adds to the capability. -->

### Requirement: <!-- requirement name -->
<!-- requirement text — must contain SHALL or MUST -->

#### Scenario: <!-- scenario name -->
- **WHEN** <!-- condition -->
- **THEN** <!-- expected outcome -->

---

## MODIFIED Requirements

<!--
Modify an existing Requirement. **MUST use the exact same normalized header as
openspec/specs/<capability>/spec.md** (compared after trim, case-sensitive); otherwise the delta apply
at archive time will fail because it cannot find the corresponding requirement.

**MUST paste the complete modified content** (not just a diff), because OpenSpec archive
applies MODIFIED by full-text replacement.
-->

### Requirement: <!-- the same header as in the existing spec -->
<!-- the complete modified requirement text — contains SHALL or MUST -->

#### Scenario: <!-- scenario name (may be added or modified) -->
- **WHEN** <!-- condition -->
- **THEN** <!-- expected outcome -->

---

## REMOVED Requirements

<!--
Remove an existing Requirement. MUST include a Reason and a Migration note so the reviewer
understands why it is being removed and how existing references should migrate.
-->

### Requirement: <!-- the header to remove, exactly the same as in the existing spec -->

**Reason**: <!-- why it is being removed -->

**Migration**: <!-- how existing callers/dependents should adjust -->

---

## RENAMED Requirements

<!--
Rename a Requirement header. The format is fixed: FROM / TO use a code-fence header.
If the name changes and the content changes, list the name change in RENAMED **and** also
write the full content under the **new** header in MODIFIED.

Archive apply order: RENAMED → REMOVED → MODIFIED → ADDED
-->

- FROM: `### Requirement: <Old Name>`
- TO: `### Requirement: <New Name>`
