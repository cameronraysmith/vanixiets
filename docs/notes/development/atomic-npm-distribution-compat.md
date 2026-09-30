# Atomic npm-distribution compatibility findings

Measured on atomic 0.9.13, comparing the npm distribution built by `pkgs/by-name/atomic` against the previous release-archive split-launcher binary.
Load verdicts come from an RPC-mode driver: synthetic provider, `get_state` and `get_commands` requests, scratch agent directories, offline mode, exit status plus `extension_error` records.

## Why the distribution matters for extension loading

The two distributions select different module maps in `core/extensions/loader-virtual-modules.ts`.
The split launcher's single-file build selects `virtualModules`, which omits the pi coding-agent specifiers, while the npm distribution selects `_aliases`, which carries `@earendil-works/pi-coding-agent`.
Every pi-ecosystem extension that value-imports that scope is a fatal load error under the release binary and loads under the npm distribution.
The legacy `@mariozechner/pi-coding-agent` scope is absent from both maps, so extensions importing it fail under every atomic distribution.

## Load matrix for the fleet's registered set

| extension | npm distribution | release split-launcher |
|---|---|---|
| pi-vim 0.14.2 (pristine) | loads (re-measured on atomic 0.9.24: exit 0, no `extension_error`) | fails: `Cannot find module '@earendil-works/pi-coding-agent'` (measured with 0.14.1 on 0.9.13; not re-measured) |
| @burneikis/pi-vim | fails: `Cannot find module '@mariozechner/pi-coding-agent'` | same failure |
| rytswd direnv, permission-gate, questionnaire, slow-mode, stash | load; commands registered | load identically |
| rytswd statusline | loads | loads |
| edit-write-policy.ts | loads | loads |
| pi-openai-server-compaction (pristine upstream) | loads without the empty-manifest workaround | fails: same resolution error |

The `@burneikis/pi-vim`, statusline, and edit-write-policy rows are distribution-independent and stay broken or excluded for upstream reasons: the legacy scope absent from both maps, the `setFooter` warn-once stub in isolated interactive mode, and atomic's `edit` tool schema that cannot carry a top-level `path`.
Interactive custom-editor hosting (`setEditorComponent`) is a stub in every atomic distribution; a vim extension under atomic loads with one warning and a dead editor rather than failing.

## Closure and runtime costs

| | release archive | npm distribution |
|---|---|---|
| output size | 302,982,304 B | 754,746,296 B |
| closure | 433.5 MiB, 5 paths | 2119.4 MiB, 52 paths |
| `--version` latency, 5-run average | 75 ms | 86 ms |

The closure delta is dominated by nodejs and its slim variants plus the node_modules payload.

## Upstream defects the build surfaced

1. The `prepublishOnly` shrinkwrap generator emits the 9 `@bastani/atomic-natives*` entries with `resolved` URLs but no `integrity`; nix's `prefetch-npm-deps` parser refuses the lockfile outright with `non-git dependencies should have associated integrity`.
2. The published package.json carries 12 devDependencies the generated shrinkwrap does not cover, so `npm ci` against the published artifact tries to resolve them from the registry and dies `ENOTCACHED` offline; upstream never runs `npm ci` on the tarball, and the two files are mutually inconsistent for that operation.
3. nixpkgs at rev `9bc02893134c733dd85de46ee4fb2fac696b5529`: `buildNpmPackage` forwards `patches` to its internal `fetchNpmDeps` but strips it from the main derivation, observed as an empty `env.patches` with the config hook's lockfile-consistency check then failing; `postPatch` reaches both consumers and is the working channel.

The repairs for 1 and 2 live in `pkgs/by-name/atomic/npm-dist-repairs.patch`, and `pkgs/by-name/atomic/update.sh` re-derives that patch per bump, verifying the tarball against the registry's published `dist.integrity` before hashing.
