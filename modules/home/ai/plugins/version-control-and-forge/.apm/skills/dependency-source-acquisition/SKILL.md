---
name: dependency-source-acquisition
description: Acquire a correct local copy of a dependency's or research-reference repo's upstream source and review it whole, instead of reading it one file at a time through the GitHub API or web UI. Use when acquiring or reviewing the source of a Category-2 dependency or reference repo, downloading upstream source to study locally, resolving a package's source-repository URL from cargo/uv/bun/nix metadata, or working with ghq to clone and catalog upstream sources.
---

# Dependency source acquisition

## When to fire

When working in — or researching for potential inclusion — a dependency or reference repository we do not primarily maintain, acquire a correct local copy of its upstream source and review it as a whole, rather than fetching one file at a time through the GitHub API or web UI.
Whole-tree review with `rg`, `fd`, and direct file reads surfaces cross-file structure, call sites, and conventions that piecemeal API fetches miss, and it costs one clone instead of many round trips.

This skill governs Category 2 only.
Category 1 — repositories we develop or maintain — stays under `~/projects/<topic>-workspace/<repo>/` per the `~/projects/` lookup convention in preferences-style-and-conventions.
Category 2 — third-party dependencies and research-reference repositories we consult but do not maintain — is acquired and cataloged through ghq, described below.
The distinguishing question is authorship: if we cut releases or land commits upstream it is Category 1; if we only read it, it is Category 2.

## Engine: ghq

`ghq` is both the acquisition engine and the catalog.
It clones into a predictable path derived from the remote URL — `$(ghq root)/<host>/<owner>/<repo>` — so the same repository always resolves to the same location regardless of who runs it.
The root is always `$(ghq root)`; the default root is `~/ghq`, but never hardcode a path.

Check first, then fetch.
The idempotency gate is `ghq list`:

```bash
ghq list -p <name>   # -p prints absolute paths; -e forces an exact match; a hit means it is already local
ghq list             # prints host/owner/repo (relative paths) for everything already cloned; prefix https:// for the URL
```

A hit means the source is already local — review it in place, do not re-clone.

On a miss, fetch lazily — shallow, blobless, no submodules — which is enough to review the current tree:

```bash
ghq get --shallow --partial blobless --no-recursive <host>/<owner>/<repo>
# also accepts a full https URL
```

`--shallow` is depth-1, `--partial blobless` is a blobless partial clone, and `--no-recursive` skips submodules.

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

The `~/projects/` Category-1 lookup convention in preferences-style-and-conventions is the policy anchor for this skill; this skill is its Category-2 arm.
