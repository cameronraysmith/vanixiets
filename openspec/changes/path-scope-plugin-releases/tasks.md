## 1. Release-package discovery

- [ ] 1.1 Generalize `modules/apps/cluster/list-packages-json.sh` to also emit `{"name": "plugins", "path": "modules/home/ai/plugins"}` when `modules/home/ai/plugins/package.json` exists, alongside its existing `packages/<name>/package.json` discovery — verify: run `nix run .#list-packages-json` before and after step 2.2 and diff the JSON output for the new entry.
- [ ] 1.2 Confirm the emitted path string is byte-identical to what `modules/apps/release/release.sh`'s `cd "$package_path"` expects (relative to repo root, no trailing slash) — verify: `nix run .#release -- modules/home/ai/plugins -- --dry-run` (needs `GITHUB_TOKEN`) completes the `cd` without error.

## 2. Plugins release-line package

- [ ] 2.1 Create `modules/home/ai/plugins/package.json`: `"name": "@vanixiets/plugins"`, `"private": true`, `"release"` block extending `semantic-release-monorepo`, matching `packages/docs/package.json`'s plugin set (commit-analyzer, release-notes-generator, changelog, github) minus `npmPublish` where not applicable — verify: `bun run test-release` (or `semantic-release --dry-run --no-ci`) invoked with `cwd=modules/home/ai/plugins` completes without a config-validation error.
- [ ] 2.2 Add `semantic-release-major-tag` to that release config's plugins list with `customTags` listing all 18 first-party directory names as `<name>-v${major}.${minor}.${patch}` templates — verify: enumerate `modules/home/ai/plugins/*/apm.yml` and diff the directory-name set against the `customTags` array to confirm all 18 (and no extras) are present.
- [ ] 2.3 Add an explanatory comment above the `customTags` array recording why alias tags are bare `<name>-v<version>` with no `@vanixiets/` prefix (apm's final-path-segment name inference, D2/D3 in design.md) — verify: comment present and cites the `apm outdated` behavior by name.

## 3. Rehearsal verification

- [ ] 3.1 Run the hermetic `release-rehearsal` check (`nix build .#checks.<system>.release-rehearsal`; before it lands, the local equivalent is `nix run .#release -- modules/home/ai/plugins -- --dry-run` with `GITHUB_TOKEN`) against a commit touching `modules/home/ai/plugins/` — verify: rehearsal log shows the plugins package discovered and analyzed, and no tag is pushed.
- [ ] 3.2 Confirm the docs release line's rehearsal outcome is unchanged by this addition — verify: run the same rehearsal and confirm `packages/docs` is still discovered with no new failures attributable to this change.

## 4. First-party dependency repointing

- [ ] 4.1 After the first real `@vanixiets/plugins-v1.0.0` release (and its 18 aliases) exists on the remote, repoint each of the 18 `dependencies.apm` entries in the root `apm.yml` from `#main` to `#<group>-v1.0.0`, matching each entry's own directory name to its alias tag — verify: `grep -c '#main' apm.yml` under the `modules/home/ai/plugins/` block drops from 18 to 0.
- [ ] 4.2 Add a per-entry (or single block-level) manifest comment recording the departure from the repo's blanket "full 40-char SHA required" convention and its justification (these deps are consumed only by the network-permitted `apm-skills-install.sh` app, never inside the sandboxed `apm-skills-compose` derivation) — verify: comment present adjacent to the repointed block.
- [ ] 4.3 Run `just agents-relock` and review the `apm.lock.yaml` diff for the 18 affected entries — verify: each entry's `resolved_ref` reads the new alias tag name (not `main`), and `resolved_commit` is a full 40-char SHA.
- [ ] 4.4 Run `apm outdated` against the relocked state and confirm none of the 18 first-party entries report `status: unknown` — verify: `apm outdated` output shows `up-to-date` or `outdated` (not `unknown`) with `source: git tags` for all 18.

## 5. Relock notification workflow

- [ ] 5.1 Add a new GitHub Actions workflow triggered on `push: tags: ['@vanixiets/plugins-v*']` that checks out the tag, runs `just agents-relock`, and opens a pull request with the diff, following `regenerate-lock-files.yaml`'s amend-and-push pattern — verify: workflow YAML lints (`nix run .#checks.<system>.<name>` or the repo's existing workflow-lint check) and the trigger glob matches `@vanixiets/plugins-v1.0.0` via a local `git check-ref-format`/glob test.
- [ ] 5.2 Push a throwaway test tag matching the glob (e.g. `@vanixiets/plugins-v0.0.0-test`) to confirm the GH Actions trigger actually fires for a ref containing `@` and `/` (open question 2 in design.md) — verify: a workflow run appears in the Actions tab for that tag push; delete the test tag afterward.

## 6. Integration Verification

- [ ] 6.1 Verify the full chain end-to-end: a commit touching `modules/home/ai/plugins/some-group/SKILL.md` reaches `main`, the `release-packages` effect cuts a new `@vanixiets/plugins-v*` release with a matching `some-group-v*` alias tag, the relock-notify workflow opens a PR repointing that one dependency, and `apm outdated` reported it as outdated immediately beforehand — with an end-to-end log/PR trail as the observable result.
- [ ] 6.2 Verify a commit touching only files outside `modules/home/ai/plugins/` (for example a docs-only change) does NOT advance the plugins release line's tags and does NOT trigger the relock-notify workflow — with the absence of a new `@vanixiets/plugins-v*` tag and absence of a new relock PR as the observable result.
- [ ] 6.3 Verify the deployed skill tree is unaffected: `nix build .#homeConfigurations.<host>.activationPackage` (or the equivalent `aiSkills.composed` build) succeeds unchanged before and after this change lands, confirming the local-path-based compose derivation never observed the repointed refs.
