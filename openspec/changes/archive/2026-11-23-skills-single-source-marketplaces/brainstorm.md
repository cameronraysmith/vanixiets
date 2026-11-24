<!--
Raw capture of the decision chain for this change.
No interactive brainstorming session ran: the operator's decisions S1 and S2 (2026-11-23) fixed the direction, and experiments E1-E4 and X1-X3 settled the open forks.
The evidence files named below sit outside the repository (session artifacts and /tmp scratch trees); the conclusions are restated here so this file stands alone.
-->

# Brainstorm: one source tree for the skills library, three ways to install it

## Background

The skills library is 22 plugin groups under `modules/home/ai/plugins/<group>/`.
Eighteen hold 126 first-party skills under `.apm/skills/`; four (`agent-context-*`) hold only `.apm/instructions/`.
Four groups declare remote apm dependencies that add 51 skills from 10 upstream repositories, so the composed corpus is 177 skills.

Three installation routes must keep working from that one tree:

- R1: the fleet's hosts receive the corpus through home-manager from a hermetic Nix build that runs apm (`pkgs/by-name/apm-skills-compose`).
- R2: other people register this repository as an apm marketplace and install groups with `apm install <group>@vanixiets`.
- R3: people add `cameronraysmith/vanixiets` in the marketplace dialog of Claude Code or the Claude desktop app and install groups as Claude plugins.

Today each group carries a hand-written `apm.yml` and a root-level `plugin.json` (`"skills": ["./.apm/skills"]`, added on 2026-09-02 because apm 0.29.0 deployed nothing without it).
The root `apm.yml` lists the 22 packages again with a version, and a hand-run `apm pack` writes `.github/plugin/marketplace.json` in Claude's format at Copilot's path.
No `.claude-plugin/marketplace.json` exists on `main`; an unmerged prototype branch (`claude-marketplace`, one commit d68d40ed0) generates it plus 18 per-group `.claude-plugin/plugin.json` with a sync script and a drift check.

The llm-agents bump that moved apm from 0.36.0 to 0.38.0 broke the build twice (lockfile v4 changed the download hash; mattpocock/skills deployed as a whole native plugin, dropping `tdd`).
That was the ninth apm-caused break since June.
The operator asked whether the library's relation to apm plugins, Claude plugins and marketplaces is unnatural.

## Operator decisions that fix the direction

- S1 (2026-11-23): apm stays in the Nix build, because the build is our own consumer-side proof of R2. apm is not pinned apart from the `llm-agents` input. Design against apm >= 0.38, then land the bump with the adaptation.
- S2 (2026-11-23): in a public scratch repository the Claude desktop app listed, installed and showed all five skills for three layouts, including `.apm/skills` with no per-plugin manifest and a marketplace entry carrying `skills: ["./.apm/skills"]` and `strict: false`, at `modules/home/ai/plugins/<group>` depth. No file moves and no per-group Claude manifest are needed.

## Decision chain

Q1. Can the 0.38 bump land on its own first?
Yes. Listing mattpocock's 25 plugin skills explicitly keeps it flat (apm's native-plugin route skips a dependency with a `skills:` selection), the download hash is identical on aarch64-darwin and x86_64-linux, and all 177 skill directories are byte-identical to `main`'s on both systems (E4).
`apm-marketplace-validate` failed only for the four instructions groups, because 0.38 no longer writes `.claude/rules`; recognising them by the fragments apm stages fixes it, and the script then passes 22/22 under 0.38.0 and 0.36.0 (run in this change's workspace on 2026-11-23).

Q2. Is the per-group root `plugin.json` still needed?
No (X1). With all 22 removed, the compose built from a scratch flake copy produced 177 skills in each tree with `nix hash path` equal to `main`'s (`sha256-YI99ZQ…B8F0=`), `diff -rq` empty; the remote-dependency download rebuilt (`--rebuild`) to the same hash; a third-party apm consumer still got flat, byte-identical skills; `apm pack` still wrote the same marketplace file.
No code reads the files; only prose does (the plugins README, the `agent-context-vanixiets` architecture fragment, the `first-party-skill-distribution` spec).
apm types each group `apm_package` because it has `.apm/` (the "eligible apm.yml" rule), and that rule wins over any plugin manifest.

Q3. Can every version go?
Not from the group `apm.yml`: apm 0.38.0 refuses a dependency whose `apm.yml` lacks `version` ("Missing required field 'version'"), verified by building the compose with the field removed.
The root `packages[].version` is redundant: `apm pack` inherits the group's version and the generated file is byte-identical without it.
Claude must see no version: with none, Claude versions a git-marketplace plugin by commit hash (observed `6832a512c2fe` from a git source, `9b57e72a448b` from a local git checkout); with `0.0.0` it pins every install.
So: the group keeps `version: 0.0.0` for apm, and the Claude file drops it.

Q4. Can apm write the Claude marketplace file we need?
No. Its Claude mapper emits a fixed field set (name, description, version, author, license, repository, tags, category, homepage, source); the package-entry schema refuses unknown keys, so `skills` and `strict` cannot be passed through; an output profile accepts only `path`, so no output can drop the four instructions groups; and `version` disappears only when the group `apm.yml` has none, which apm install refuses (Q3).
The smallest generator is `apm pack` run on a dependency-free copy of the root manifest, followed by one jq filter that keeps the skill-bearing groups, deletes `version`, and adds `skills` and `strict`.

Q5. Why does `apm pack` fail on the real root `apm.yml`?
A `dependencies:` block makes `apm pack` build a bundle from `apm.lock.yaml` as well as the marketplace files, and the bundle step fails until an install has populated the deployed files. No flag skips the bundle.
The 18 `#main` self-dependencies exist for `apm-skills-install` (`just agents-install`, `just agents-relock`), which materialises this repository's own packages from GitHub `main` into `.agents/skills` on hosts without home-manager. Nothing else reads them.
Keeping them and stripping them in the generator's private copy costs one `yq` expression; moving them would change a working recipe for no gain.

Q6. What about `.github/plugin/marketplace.json`?
apm probes `marketplace.json`, then `.github/plugin/marketplace.json`, then `.claude-plugin/marketplace.json`.
Served alone, the Claude-ready `.claude-plugin/marketplace.json` (18 entries, with `skills`, `strict`, no `version`) registered and installed cleanly under apm 0.38.0 and 0.36.0, so apm ignores the Claude-only fields; but the four instructions groups would then vanish from the apm marketplace.
A real Copilot-profile file at `.github/plugin/` (22 entries) registered and installed under both versions, including `agent-context-core`.
Choice: emit the Copilot profile at its own path for apm and Copilot, and the Claude file at Claude's path. Both come from one `apm pack` run.

Q7. Does the candidate end state hold for all groups?
Yes (X3). `claude plugin validate` passes the generated marketplace; in an isolated config directory, installing all 18 plugins gave 126 skills, each plugin's skill names equal to its `.apm/skills` children; the same install-and-count ran offline in a Linux build sandbox on magnetite with Claude Code 2.1.330.
An offline apm consumer route also ran in the sandbox (served bare repository plus a `url.insteadOf` rewrite) for groups without remote dependencies.

Q8. Do the 51 remote skills reach Claude users?
No, and this change does not try. A Claude plugin's `dependencies` name whole plugins in a marketplace, not skill subsets of a repository; cross-marketplace dependencies need an allowlist in our marketplace; apm 0.38's native-plugin route deploys into an apm consumer's project, not into a Claude marketplace.
Claude users who want superpowers install it from `claude-plugins-official`, as the plugins README already advises for the hook.

## Trade-offs weighed

- Generated marketplace files committed under a drift check, against a generator run on every build without committing: Claude and apm read the files from git, so they must be committed.
- `apm pack` plus jq, against a pure jq/yq generator: the pure generator re-implements apm's mappers and would hide apm format changes that apm consumers see; apm in the generator surfaces them as drift on the next llm-agents bump.
- Per-group `.claude-plugin/plugin.json` (prototype) against entry-only manifests: S2 showed the entry-only form works in the desktop app, and it avoids 18 more generated copies of name and description.
- Moving skills to `skills/` (the layout both vendors document): works in Claude Code and apm (E1), but changes apm's package typing, touches 126 directories, and buys nothing that S2 did not already show; kept as the fallback if the hidden path stops working.
- A standing check per regulator, against one-off proofs: `--no-frozen` and `$out` reproducibility get one-off proofs, because no plausible build environment sets `CI` and the tree oracle already covers the skill trees.
