# General Practices

- Write one sentence per line in markdown, text, and documentation files.
- Always at least consider testing changes with the relevant framework like bash shell commands where you can validate output, `cargo test`, `pytest`, `vitest`, `nix eval` or `nix build`, a task runner like `just test` or `make test`, or `gh workflow run` before considering any work to be complete and correct.
- Be judicious about test execution. If a test might take a very long time, be resource-intensive, or require elevated security privileges but is important, pause to provide the proposed command and reason why it's an important test.
- Use performant CLI tools matched to task intent:
  - File search (by name/path): use `fd` instead of `find`
  - Content search (within files): use `rg` (ripgrep) instead of `grep`
  - Disk usage (directory sizes): use `diskus` instead of `du -sh`
- When given a GitHub file URL (e.g., `https://github.com/org/repo/blob/ref/path/to/file.ext#L119-L131`), check for a local copy before using web tools:
  1. Search for repo: `fd -t d '^repo$' ~/projects` (repo name may have variants)
  2. Verify remote: `cd candidate-dir && git remote -v` (confirm origin matches GitHub org/repo)
  3. Read the file with line range using the Read tool
  4. Only use WebFetch/WebSearch if no local copy exists
- When given a GitHub issue/PR URL (e.g., `https://github.com/org/repo/issues/2491`), use `gh issue view 2491 -R org/repo` or `gh pr view 2491 -R org/repo` to access discussion content and metadata.

