---
name: dependency-source-acquisition
description: Resolve a named repository to a local copy before reasoning about it, and acquire one when missing. Covers two lookup kinds, maintained repositories under ~/projects/<repo> and reference repositories under ~/ghq via ghq. Use whenever a repository is named in a task, when about to state a substantive technical claim grounded in a project's source, options, defaults, API, or upstream documentation, when resolving a package's source-repository URL from cargo/uv/bun/nix metadata, when a "(see local)" marker is appended to a name, or when given a GitHub file, issue, or PR URL.
---

# Dependency source acquisition

## When to fire

When a repository is named — or a substantive technical claim is about to rest on a project's source, options, defaults, API, or upstream documentation — check for a local copy first; treat the lookup as the default and bypass it only with explicit justification.
Whole-tree review with `rg`, `fd`, and direct file reads surfaces cross-file structure, call sites, and conventions that piecemeal API fetches miss, and it costs one clone instead of many round trips.

Resolve the org first: a bare name is often ambiguous — `gh search repos <name>` returns dozens of matches for a common word — and the org determines everything downstream.
A fully-qualified `org/repo` or a forge URL settles identity outright; when more than one plausible match survives a search, ask which one was meant rather than guessing.

Then branch on authorship.
The distinguishing question: if we cut releases or land commits upstream it is a maintained repo; if we only read it, it is a reference repo.

## Maintained-repo lookup

Maintained repositories live under `~/projects/<repo>/` (copies may sit deeper; repo names can have variants such as `<repo>.jl` or `<repo>-rs`).

1. Search the tree: `fd -t d -d 4 '^<repo>$' ~/projects`
2. Verify the match: `cd <candidate> && git remote -v` to confirm the origin matches the expected forge URL.
   Name collisions are common with single-token repo names, so this step is required, not optional, before treating a candidate as authoritative.
3. On hit: treat the local path as the source of truth, dispatch research subagents to it, and use that path in prompts and writeups.
4. On miss: surface the failure to the user and ask them to clone it to `~/projects/<repo>/` (or provide the path if it lives elsewhere) before proceeding; propose the exact command — `git clone <url> ~/projects/<repo>/` for reference-only work, or `gh repo fork <org>/<repo> --clone --remote -- ~/projects/<repo>/` when contribution back upstream is anticipated.
   Do not silently fall back to web tools for substantive research when a local copy would be more authoritative; web tools remain appropriate only for genuinely web-native content (release notes, issue discussions, blog posts).
   Pause the work thread until the clone is in place or the user provides an alternative path.

Never ask the user to clone a reference repo into `~/projects/`.

## Reference-repo lookup

The gate is `ghq list -p <name>` (under "Engine: ghq" below): authoritative because it walks the filesystem directly rather than consulting an index.
`zoxide query -l <name>` is a fast-path cache only — validate any hit against `ghq list -p` before relying on it.
On a miss, acquire the repository with `ghq-sync <url>`, which clones shallow and blobless and registers the path with zoxide; a raw `ghq get` clone does not register.
Prefer the canonical upstream; acquire a personal fork only when contribution back to upstream is anticipated.
A shallow clone sits at HEAD, which is usually not the revision we pin — read at the pinned revision or every line anchor you cite will be wrong.
On magnetite, pyrite and stibnite every account's `$(ghq root)` is the host's one shared tree, `/var/lib/ghq`, and `~/ghq` is a link to it, so `ghq list -p` prints paths under the shared root rather than under `~/ghq`; elsewhere the root is ghq's default `~/ghq`.
The shared tree has a single writer account and is read-only to you: `ghq get`, `ghq-sync`, `ghq-sync --deepen` and `ghq-sync --full` are carried out by that account on your behalf, and `git fetch`, `git gc`, editing a file or setting configuration inside a reference repository fail with a permission error by design.
To change a reference repository's working tree, copy it out with `git clone <path> <dir>` into a directory you own.

## The `(see local)` marker

When the user appends `(see local)` — or a close variant such as `(see local clone)` or `(local)` — to a name, the lookup above is unconditional: do not answer from general knowledge, do not reach for web tools, and do not ask whether a clone exists.
If the lookup returns no hit, fall through to that category's on-miss handling: the maintained-repo clone request above, or the `ghq-sync` acquisition under "Reference-repo lookup" above.

## GitHub URL handling

Given a GitHub file URL (e.g. `https://github.com/org/repo/blob/ref/path#L119-L131`), apply the lookup for `repo`, then read the file with the line range.
Given an issue or PR URL (e.g. `https://github.com/org/repo/issues/2491`), use `gh issue view 2491 -R org/repo` or `gh pr view 2491 -R org/repo`.

## Engine: ghq

`ghq` is both the acquisition engine and the catalog.
It clones into a predictable path derived from the remote URL — `$(ghq root)/<host>/<owner>/<repo>` — so the same repository always resolves to the same location regardless of who runs it.
The root is always `$(ghq root)`; the default root is `~/ghq`, a host-shared tree changes it, so never hardcode a path.

Check first, then fetch.
The idempotency gate is `ghq list`:

```bash
ghq list -p <name>   # -p prints absolute paths; -e forces an exact match; a hit means it is already local
ghq list             # prints host/owner/repo (relative paths) for everything already cloned; prefix https:// for the URL
```

A hit means the source is already local — review it in place, do not re-clone.

On a miss, fetch with `ghq-sync <url>`, which performs the lazy clone — shallow, blobless, no submodules, enough to review the current tree — and registers the path with zoxide:

```bash
ghq-sync <url>   # shallow + blobless clone into $(ghq root)/<host>/<org>/<repo>, registered with zoxide
```

The lower-level `ghq get --shallow --partial blobless --no-recursive <host>/<owner>/<repo>` performs the same clone without registering the path with zoxide; use it only when registration is unwanted, and complete registration manually otherwise.

When the review needs full history, blame, or submodule contents, promote the lazy clone to a full one.
`ghq get -u` only updates the existing clone in place — it runs a fast-forward pull or fetch and leaves the clone grafted (shallow) and blobless — so it does not promote a lazy clone to full.
Use the `ghq-sync` sibling tool instead, which unshallows the clone, removes the partial-clone filter, backfills the missing objects with `--refetch`, and initializes submodules:

```bash
ghq-sync --full <host>/<owner>/<repo>   # git unshallow + partial-filter removal + --refetch backfill + submodule init
```

The in-place promotion it performs is: unset `remote.origin.partialclonefilter`, set an all-branches fetch refspec, `git fetch --unshallow`, `git fetch --refetch`, unset `remote.origin.promisor` then gc, fast-forward to `@{u}`, and `git submodule update`.

## Resolving a source URL

Often you have a package name, not a repository URL.
Resolve the URL in this precedence order:
first, the ecosystem's package manager or lockfile, preferring metadata already fetched locally so the answer is offline and matches the installed version;
on a gap, the registry's own metadata;
as a last resort, a web or `gh` lookup.

Then normalize the resolved URL and re-run the `ghq list -p` gate on the resolved name before fetching.
Shared normalization before ghq strips a `git+` prefix, converts `git@host:owner/repo` and `ssh://` forms to `https://host/owner/repo`, drops a trailing `.git`, and drops any `/tree/...` path or `?.../#...` suffix.

## Per-ecosystem recipes

Ordered by reliability.

### Nix flake inputs

Highest reliability: `flake.lock` records an exact locked source for every input.

```bash
nix flake metadata --json | jq .locks.nodes        # inspect all nodes
nix flake metadata --json | jq -r '.locks.nodes | to_entries[] | .value.locked | select(.type=="github") | "\(.owner)/\(.repo)"'
```

Each locked node's `.locked` carries `{type, owner, repo, url, ...}`.
A `github` type maps to `https://github.com/<owner>/<repo>`; `gitlab` maps similarly; a `git` type carries the source directly in `.locked.url`.
Map an input name to its node through `.locks.nodes.root.inputs`.

### Rust (cargo)

High reliability.

```bash
cargo tree                                  # human-readable
cargo metadata --format-version 1           # machine-readable; --offline works after `cargo fetch`
cargo metadata --format-version 1 \
  | jq -r '.packages[] | select(.source!=null) | (.repository // .homepage // .documentation) | select(.!=null)' \
  | sed -E 's#\.git$##; s#/tree/.*$##' | sort -u
```

Do not pass `--no-deps` — it drops the dependency packages you are resolving.
For each package prefer `.repository`; else parse `.source` (a `git+<url>` form — strip the `git+` prefix and any `?.../#...` suffix); else fall back to `.homepage` then `.documentation`.
Workspace and path members have `.source == null` and are skipped; a rare empty `.repository` needs a web fallback.

### TypeScript / JavaScript (bun)

High reliability via local reads.

```bash
bun pm ls                                       # direct deps; --all for the full tree
bun pm ls --all
bun pm pkg get dependencies devDependencies     # project package.json may be JSON5 — use this, not raw jq on the file
```

The authoritative URL for the exact installed version is the installed package's own manifest: read `node_modules/<pkg>/package.json` `.repository`.
This is correct even for npm-aliased installs.
Normalize the shapes: a string `"owner/repo"` is GitHub shorthand; a `github:` / `gitlab:` / `bitbucket:` prefix names the host; an object carries `.url`.
The in-file fallback order is `.repository`, then `.homepage`, then `.bugs.url`.
For transitive dependencies, iterate `node_modules/*/package.json` and `node_modules/@*/*/package.json`.

Do not rely on `npm view <pkg> repository.url` or `bun pm view` as the primary source: they hit the network, return the latest rather than the installed version, and are wrong for aliased installs (for example `vite` installed as `npm:rolldown-vite`).
Use them only as a last-resort fallback.

### Python (uv)

Medium reliability (roughly 93%; the remainder needs a web lookup).

```bash
uv tree                # dependency tree; --depth 1 for direct deps only
```

Do not use `uv pip list` — it reports the active environment and can silently target the wrong interpreter.
`uv` and `pip` surface no repository URL, so read the installed distribution metadata: scan `Project-URL:` lines in `.venv/lib/python*/site-packages/<pkg>-<ver>.dist-info/METADATA`.
Pick the first forge-host URL (github, gitlab, codeberg, bitbucket, sr.ht) by key priority: source code, then source, then repository, then code, then github, then homepage, then any.
For git dependencies, read `uv.lock`, where the `source = { git = ... }` entry carries the URL (strip `?.../#...`).
On a gap, fall back to `https://pypi.org/pypi/<pkg>/json` `.info.project_urls` (the same declared fields, so it will not rescue a genuine gap), then a web or `gh` lookup.

## Review, then stop

Once the source is local, review the whole tree with `rg`, `fd`, and file reads rather than fetching individual files through the GitHub API.
Record nothing extra: `ghq list` is the catalog, so there is no manifest to maintain.

This skill is the canonical home for both lookup categories; the global context file's session protocol and the style skill both defer to it.
