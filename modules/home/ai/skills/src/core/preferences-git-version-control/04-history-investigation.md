# History investigation with pickaxe

When searching for when/why code changed, use git pickaxe options strategically to avoid context pollution:

Default search strategy (focused):

- Use `-G"pattern"` to find commits where lines matching pattern were added/removed
- Use `-S"string"` to find commits where the occurrence count of string changed (not in-file moves)
- Examine specific files: `git show <hash> -- <file>` or `git diff <base>..<hash> -- <file>`

Avoid `--pickaxe-all` by default:

- Without `--pickaxe-all`: shows only files matching the search (optimal for AI context)
- With `--pickaxe-all`: shows entire changeset if any file matches (causes information overload)
- Only use `--pickaxe-all` when broader context is explicitly needed to understand why a change was made

Key differences:

- `-S"numpy"` finds commits where "numpy" was added/removed (count changed)
- `-G"numpy"` finds commits where lines containing "numpy" were modified
- `-S` misses refactors that move text without changing occurrence count
- `-G` is more expensive but catches structural changes

Practical examples:

- `git log -G"dependencies" --oneline` then `git show <hash> -- <file>` (targeted)
- `git log -S"function_name" --pickaxe-regex --oneline` (exact occurrences)
- Avoid `git log -S"pattern" --pickaxe-all -p` unless user needs full changeset context

## See also

- [`SKILL.md`](SKILL.md) — top-level git version control principles and policy
