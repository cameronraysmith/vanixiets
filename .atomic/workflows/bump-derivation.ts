import { readFile, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { homedir } from "node:os";
import process from "node:process";
import { isDeepStrictEqual } from "node:util";
import { workflow, type WorkflowTaskOptions, type WorkflowTaskResult, type WorkflowSerializableValue } from "@bastani/atomic/workflows";
import { Type } from "typebox";
import { Value } from "typebox/value";
import { packages } from "./bump/packages.js";
import { Blocked, Claim, DerivationMap, completedRun, relativePath, unreachable, validateClaimReplacement, validateMap, verifyRegistrySkills, witness, within, type SkillDep } from "./bump/types.js";
import { capture, changed, discoverReleaseSource, pinGate, processCheckpoint, processReceipt, quote, requireSuccess, resolveRelease, resolveUpdaterCommand, save, scopeGate, snapshot, topology, vendoredDirectory, verifyTopology, verifyVendored, type VendoredEvidence } from "./bump/tools.js";

// The first-party fable route rejects this client's reported version. Openrouter
// reaches the same model without that gate and therefore leads the fallback chain.
const RECON = { model: "anthropic/claude-fable-5-2:medium", fallbackModels: ["openrouter/anthropic/claude-fable-5.2:medium", "anthropic/claude-sonnet-4-6:medium"] };
const IMPL = { model: "openai-codex/gpt-6-astra:high", fallbackModels: ["openai-codex/gpt-5.6-terra:high"] };
const REVIEW = { model: "anthropic/claude-opus-5-5:max", fallbackModels: ["anthropic/claude-opus-5:max"] };
const READ_ONLY = { tools: ["read", "search", "find", "ls"], mcp: { allow: [] } };
const LAND = { model: "anthropic/claude-opus-5-5:high", fallbackModels: ["anthropic/claude-opus-5:high"] };
const keep = (text: string) => `<keepContext>\n${text}\n</keepContext>`;
const Probe = Type.Object({ claim: Type.Integer({ minimum: 0 }), kind: Type.Union([Type.Literal("Help"), Type.Literal("Source"), Type.Literal("Vendored")]), args: Type.Array(Type.String()) });
const Probes = Type.Object({ probes: Type.Array(Probe) });
const Attestations = Type.Object({ claims: Type.Array(Type.Object({ claim: Type.Integer({ minimum: 0 }), quote: Type.String({ minLength: 1, maxLength: 8192 }), verifiedAgainst: Type.String(), repaired: Type.Boolean(), replacement: Type.Optional(Claim) })) });
const Review = Type.Object({ verdict: Type.Union([Type.Literal("approved"), Type.Literal("changes_requested")]), findings: Type.Array(Type.Object({ severity: Type.Union([Type.Literal("blocking"), Type.Literal("major"), Type.Literal("minor")]), location: Type.String(), evidence: Type.String() })) });

export default workflow({
  name: "bump-derivation",
  description: "Bump a derivation using a classified updater, build and skill witnesses, independent review, and path-scoped jj splicing.",
  autoAttach: true,
  inputs: {
    package: Type.String(), target_version: Type.Optional(Type.String()), plan_only: Type.Boolean({ default: false }),
    splice_after: Type.Optional(Type.String({ description: "Required in jj mode: change id after which the ordered delivery changes are spliced." })),
    max_repair_attempts: Type.Integer({ default: 2, minimum: 0 }),
    build_timeout_minutes: Type.Integer({ default: 45, minimum: 1 }),
  },
  outputs: {
    status: Type.String(), summary: Type.String(), package: Type.String(), target_version: Type.String(), recon_artifact: Type.String(),
    build_log: Type.String(), build_attempts: Type.Number(), review_verdict: Type.String(), landed: Type.Boolean(), changes: Type.Array(Type.String()),
    skill_deps_verified: Type.Boolean(), self_maintained_repaired: Type.Array(Type.String()),
  },
  run: async (ctx) => {
    const cwd = ctx.cwd ?? process.cwd();
    const pkg = ctx.inputs.package;
    const target = ctx.inputs.target_version;
    const root = `.atomic/workflows/runs/bump-derivation/${pkg}`;
    const prefix = `pkgs/by-name/${pkg}`;
    const reconFile = `${root}/recon.md`, manifestFile = `${root}/manifest.json`, ledgerFile = `${root}/ledger.json`;
    const ledger: unknown[] = [];
    let version = target ?? "", buildLog = "", attempts = 0;
    let repaired: string[] = [];
    const timeout = ctx.inputs.build_timeout_minutes * 60_000;
    const rest = () => ({ package: pkg, target_version: version, recon_artifact: reconFile, build_log: buildLog, build_attempts: attempts, review_verdict: "", skill_deps_verified: false, self_maintained_repaired: repaired });
    const tool = async <T extends WorkflowSerializableValue>(name: string, action: (signal: AbortSignal) => Promise<T>, timeoutMs = 120_000): Promise<T> => {
      const result = await ctx.tool(name, { package: pkg }, async ({ signal }) => processCheckpoint(root, name, () => action(signal)), { failureMode: "return", timeoutMs });
      ledger.push({ node: name, result }); await save(cwd, ledgerFile, ledger);
      if (!result.ok) throw new Blocked(`${name}: ${JSON.stringify(result.error)}`);
      return result.value.evidence;
    };
    const stage = async (name: string, options: WorkflowTaskOptions): Promise<WorkflowTaskResult> => {
      const result = await ctx.task(name, options);
      const actual = result.modelAttempts?.filter((attempt) => attempt.success).at(-1);
      ledger.push({ node: name, model: actual?.model ?? result.model ?? null, thinking: actual?.reasoningLevel ?? null, attempts: result.modelAttempts ?? [], metadataMissing: actual?.reasoningLevel === undefined });
      await save(cwd, ledgerFile, ledger);
      if (!actual?.model || !actual.reasoningLevel) throw new Blocked(`${name}: actual model/thinking metadata unavailable; see ledger`);
      return result;
    };
    const prompt = (role: string, instruction: string) => keep(`${role}\nPackage: ${pkg}; target: ${version}; repository: ${cwd}; artifacts: ${root}.\nNever move @; never jj edit, new without --no-edit, new -r, abandon, rebase, undo, op restore, workspace, git checkout/switch/commit/stash/worktree. Never push, activate a system, edit upstream sources or vendored skills. No edits outside your explicitly allowed paths.\n${instruction}`);
    try {
      if (!relativePath(pkg) || pkg.includes("/")) throw new Blocked("Package must name one pkgs/by-name directory");
      if (!Number.isFinite(timeout) || timeout <= 0 || !Number.isInteger(ctx.inputs.max_repair_attempts) || ctx.inputs.max_repair_attempts < 0) throw new Blocked("Invalid bounded execution inputs");
      await stat(join(cwd, ".jj"));
      if (!ctx.inputs.splice_after) throw new Blocked("splice_after is required in jj mode");
      const initial = await tool("capture-initial-state", async (signal) => ({ tree: await snapshot(cwd, signal), commit: requireSuccess(await capture(cwd, "git rev-parse HEAD", signal)), topology: await topology(cwd, ctx.inputs.splice_after!, signal) }));
      const entry = Object.hasOwn(packages, pkg) ? packages[pkg] : undefined;
      const release = await tool("resolve-release", async (signal) => {
        const source = entry?.releaseSource ?? discoverReleaseSource(await readFile(join(cwd, prefix, "package.nix"), "utf8"));
        return resolveRelease(source, target, signal);
      }, 90_000);
      version = release.version;
      await save(cwd, `${root}/release.json`, { ...release, registry: entry ?? null, initial });

      const mapped = await stage("map-derivation", {
        ...RECON, ...READ_ONLY, context: "fresh", reads: [`${root}/release.json`], schema: DerivationMap, output: reconFile, outputMode: "file-only",
        prompt: prompt("You are a read-only derivation mapper. Do not edit any tracked file or execute an updater/build.", `Read the derivation, updater, modules/apps/updates.nix and all registry skill paths. Verify registry release/skill entries against the tree and report drift; do not silently rewrite them. For an unregistered package discover all skill dependencies and block unclassifiable facts. Discover the updater from passthru.updateScript (nix eval .#${pkg}.passthru.updateScript), app definitions or nix-update-script usage; do not infer argument support from a filename. Enumerate every version and hash pin with file, field, exact current literal value and mustChange: version-keyed src/binaries true; closure FOD npmDepsHash/denoDeps.outputHash false. For every hash that may legitimately stay unchanged (mustChange false), supply witnessAttr naming the flake attribute whose build realizes exactly that fixed-output derivation, and include it in gateAttrs.attrs; otherwise validation blocks. Include cross-system attributes such as packages.x86_64-linux.linear-cli.denoDeps when required: remote builders are configured, so cross-system attributes are buildable. witnessAttr must omit the .# prefix. Enumerate actual system and all covering build/check attributes, never guessed attributes. gateAttrs.attrs must contain flake attribute paths such as packages.aarch64-darwin.linear-cli or checks.aarch64-darwin.package-linear-cli, with no .# prefix. Report all other version pins outside the prefix. Call structured_output with the full manifest, matching your file:line observations. Registry data is in the release artifact.`),
      });
      const map = validateMap(mapped.structured, pkg);
      await save(cwd, manifestFile, map);
      const pinBaseline = await tool("validate-map", async (signal) => {
        scopeGate(initial.tree, await snapshot(cwd, signal), []);
        if (!isDeepStrictEqual(map.releaseSource, release.source)) throw new Blocked("Recon release source drift");
        const augmentations = verifyRegistrySkills(entry?.skillDeps ?? [], map.skillDeps);
        await save(cwd, `${root}/registry-augmentations.json`, augmentations);
        const files: Record<string, string> = {};
        for (const pin of map.pinSet) files[pin.file] = await readFile(join(cwd, pin.file), "utf8");
        for (const dep of map.skillDeps) {
          switch (dep.kind) {
            case "Vendored":
              if (pkg === "linear-cli" && !(await readFile(join(cwd, "modules/home/users/crs58/default.nix"), "utf8")).includes(dep.deliveryExpr)) throw new Blocked("Vendored delivery expression drift");
              break;
            case "SelfMaintained":
              await stat(join(cwd, dep.skillPath));
              for (const claim of dep.citedClaims) {
                const text = await readFile(join(cwd, claim.file), "utf8");
                if (!claim.text.split("; ").every((part) => text.includes(part))) throw new Blocked(`Registry claim drift: ${claim.file}:${claim.lines}`);
              }
              break;
            default: unreachable(dep);
          }
        }
        const artifactPath = `${root}/pin-baseline.json`;
        await save(cwd, artifactPath, files);
        return { artifactPath, augmentations };
      });
      const pinBefore = JSON.parse(await readFile(join(cwd, pinBaseline.artifactPath), "utf8")) as Record<string, string>;
      const updateCommand = await tool("validate-updater-target", (signal) => resolveUpdaterCommand(map.updater, release, target !== undefined, signal), 90_000);
      if (map.skillDeps.some((dep) => dep.kind === "Vendored" && dep.pinKind === "ApmGitDep")) throw new Blocked("unsupported (slice C): ApmGitDep");
      if (ctx.inputs.plan_only) {
        await save(cwd, `${root}/plan.json`, { release, map, witnesses: ledger, terminalBefore: "run-updater" });
        return { ...rest(), status: "completed", summary: "Plan only: release and map observed; updater and land unreachable.", landed: false, changes: [] };
      }

      await tool("run-updater", async (signal) => {
        requireSuccess(await capture(cwd, updateCommand, signal, `${root}/updater.json`));
        scopeGate(initial.tree, await snapshot(cwd, signal), [prefix]);
        const after: Record<string, string> = {};
        for (const pin of map.pinSet) after[pin.file] = await readFile(join(cwd, pin.file), "utf8");
        pinGate(map, pinBefore, after);
        if (requireSuccess(await capture(cwd, `nix eval --raw --no-write-lock-file ${quote(`.#${pkg}.version`)}`, signal)) !== version) throw new Blocked("Updater did not produce the resolved version");
        return { version };
      }, timeout);

      const command = `nix build --no-link --log-format internal-json -v ${map.gateAttrs.attrs.map((attr) => quote(`.#${attr}`)).join(" ")}`;
      for (let round = 0; round <= ctx.inputs.max_repair_attempts; round++) {
        attempts++;
        buildLog = `${root}/build-${attempts}.json`;
        const build = await tool(`build-${attempts}`, async (signal) => processReceipt(await capture(cwd, command, signal, buildLog)), timeout);
        if (build.exitCode === 0) break;
        if (round === ctx.inputs.max_repair_attempts) throw new Blocked(`Build failed after ${attempts} attempts: ${buildLog}`);
        await stage(`build-repair-${round + 1}`, {
          ...IMPL, context: "fresh", reads: [reconFile, manifestFile, buildLog], output: `${root}/build-repair-${round + 1}.md`,
          prompt: prompt("Repair only the failed build; you may edit only the derivation prefix.", `Allowed path: ${prefix}. Search the full build log, do not read it wholesale. Never weaken checks, narrow the enumerated attributes, modify an updater, or invent hashes. Use only actual tool-observed hashes. Do not commit. The next workflow-owned build executes the unchanged gate.`),
        });
        await tool(`build-repair-scope-${round + 1}`, async (signal) => scopeGate(initial.tree, await snapshot(cwd, signal), [prefix]));
      }
      await tool("verify-built-pins", async (signal) => {
        scopeGate(initial.tree, await snapshot(cwd, signal), [prefix]);
        const after: Record<string, string> = {};
        for (const pin of map.pinSet) after[pin.file] = await readFile(join(cwd, pin.file), "utf8");
        const pins = pinGate(map, pinBefore, after);
        if (requireSuccess(await capture(cwd, `nix eval --raw --no-write-lock-file ${quote(`.#${pkg}.version`)}`, signal)) !== version) throw new Blocked("Build repair changed the target version");
        return pins;
      });

      const vendored = await tool("verify-vendored-delivery", async (signal) => {
        const paths: VendoredEvidence[] = [];
        for (let index = 0; index < map.skillDeps.length; index++) {
          const dep = map.skillDeps[index]!;
          switch (dep.kind) {
            case "SelfMaintained": break;
            case "Vendored": {
              let attr: string;
              switch (dep.pinKind) {
                case "SrcCarried": attr = `.#${pkg}.src`; break;
                case "NpmBundled": attr = `.#${pkg}`; break;
                case "ApmGitDep": throw new Blocked("unsupported (slice C): ApmGitDep");
                default: unreachable(dep.pinKind);
              }
              const output = requireSuccess(await capture(cwd, `nix build --no-link --print-out-paths ${quote(attr)}`, signal, `${root}/vendored-build-${index}.json`));
              if (!output.startsWith("/nix/store/") || output.includes("\n")) throw new Blocked("Ambiguous vendored output");
              const exprPrefix = dep.pinKind === "SrcCarried" ? `\${pkgs.${pkg}.src}/` : `\${pkgs.${pkg}}/`;
              if (!dep.deliveryExpr.startsWith(exprPrefix)) throw new Blocked("Unclassifiable vendored delivery expression");
              const suffix = dep.deliveryExpr.slice(exprPrefix.length);
              if (!relativePath(suffix)) throw new Blocked("Invalid delivery path");
              const delivered = dep.pinKind === "SrcCarried" ? join(output, dep.upstreamSubtree) : join(output, suffix);
              if (dep.pinKind === "SrcCarried" && !within(dep.upstreamSubtree, suffix)) throw new Blocked("Source subtree not covered by delivery expression");
              const extracted = await vendoredDirectory(cwd, root, index);
              switch (release.source.kind) {
                case "GitHubRelease": {
                  const upstream = join(homedir(), "ghq/github.com", release.source.owner, release.source.repo);
                  const tag = release.source.tagPrefix + version;
                  requireSuccess(await capture(cwd, `git -C ${quote(upstream)} archive ${quote(tag)} -- ${quote(dep.upstreamSubtree)} | tar -x -C ${quote(extracted)}`, signal));
                  break;
                }
                case "Npm":
                  if (!release.tarball) throw new Blocked("No npm tarball observation");
                  requireSuccess(await capture(cwd, `curl --fail --location ${quote(release.tarball)} | tar -xz --strip-components=1 -C ${quote(extracted)}`, signal));
                  break;
                default: unreachable(release.source);
              }
              paths.push(await verifyVendored(cwd, delivered, extracted, dep.upstreamSubtree, signal, `${root}/vendored-diff-${index}.json`)); break;
            }
            default: unreachable(dep);
          }
        }
        return paths;
      }, timeout);
      await save(cwd, `${root}/vendored.json`, vendored);

      const self = map.skillDeps.filter((dep): dep is Extract<SkillDep, { kind: "SelfMaintained" }> => dep.kind === "SelfMaintained");
      const skillPaths = self.map((dep) => dep.skillPath);
      const registryUpdates: { skillPath: string; previous: Claim; replacement: Claim }[] = [];
      await save(cwd, `${root}/registry-updates.json`, registryUpdates);
      const preSkills = await tool("capture-before-self-maintained", (signal) => snapshot(cwd, signal));
      for (let index = 0; index < self.length; index++) {
        const dep = self[index]!;
        const claimsFile = `${root}/claims-${index}.json`;
        await save(cwd, claimsFile, dep);
        const planned = await stage(`revalidate-self-maintained-probes-${index}`, {
          ...IMPL, ...READ_ONLY, context: "fresh", reads: [manifestFile, claimsFile, `${root}/vendored.json`], output: `${root}/probes-${index}.md`, schema: Probes,
          prompt: prompt("You are planning read-only observations, not editing prose or asserting truth.", "For every cited claim return one or more probes: Help with args naming a CLI subcommand (the tool appends --help), Source with one source file beneath the built package's .src store path, or Vendored with one relative path beneath a verified vendored skill. claim is the zero-based citedClaims index. Include linear label list help for the workspace-slug claim; source src/utils/graphql.ts and src/config.ts for credential precedence/conflict. Probe every invoked Linear verb and its flags. Source probes build .#<package>.src through a tool, then read the store path; use that primary source for CLI internals rather than asking the controller for excerpts. Never invoke a real authenticated operation. Do not edit files."),
        });
        if (!Value.Check(Probes, planned.structured)) throw new Blocked("Invalid claim probe plan");
        const probes = planned.structured.probes;
        if (dep.citedClaims.some((_, i) => !probes.some((p) => p.claim === i)) || probes.some((p) => p.claim >= dep.citedClaims.length)) throw new Blocked("Probe plan does not cover every claim");
        const observations = await tool(`self-maintained-probes-${index}`, async (signal) => {
          const output = requireSuccess(await capture(cwd, `nix path-info ${quote(`.#${pkg}`)}`, signal));
          const binary = requireSuccess(await capture(cwd, `nix eval --raw ${quote(`.#${pkg}.meta.mainProgram`)}`, signal));
          const sourcePath = probes.some((p) => p.kind === "Source") ? requireSuccess(await capture(cwd, `nix build --no-link --print-out-paths ${quote(`.#${pkg}.src`)}`, signal)) : "";
          if (sourcePath && (!sourcePath.startsWith("/nix/store/") || sourcePath.includes("\n"))) throw new Blocked("Ambiguous built source output");
          const results: { claim: number; artifactPath: string }[] = [];
          for (const probe of probes) {
            let observation: string;
            switch (probe.kind) {
              case "Help":
                if (probe.args.some((arg) => !/^[a-zA-Z0-9_-]+$/.test(arg) || arg.startsWith("-"))) throw new Blocked("Unsafe help arguments");
                observation = requireSuccess(await capture(cwd, `${quote(join(output, "bin", binary))} ${probe.args.map(quote).join(" ")} --help`, signal)); break;
              case "Source":
                if (probe.args.length !== 1 || !relativePath(probe.args[0]!) || !sourcePath) throw new Blocked("Unclassifiable source probe");
                observation = `Source: ${join(sourcePath, probe.args[0]!)}\n\n${await readFile(join(sourcePath, probe.args[0]!), "utf8")}`; break;
              case "Vendored":
                if (probe.args.length !== 1 || !relativePath(probe.args[0]!) || !vendored.length) throw new Blocked("Unclassifiable vendored probe");
                observation = (await Promise.all(vendored.map((dep) => readFile(join(dep.deliveredPath, probe.args[0]!), "utf8")))).join("\n"); break;
              default: unreachable(probe.kind);
            }
            const artifactPath = `${root}/claim-observation-${index}-${results.length}.txt`;
            await writeFile(join(cwd, artifactPath), observation);
            results.push({ claim: probe.claim, artifactPath });
          }
          return results;
        });
        const evidenceFile = `${root}/claim-observations-${index}.json`;
        await save(cwd, evidenceFile, observations);
        const quoteEvidence = await Promise.all(observations.map(async (o) => ({ claim: o.claim, observation: await readFile(join(cwd, o.artifactPath), "utf8") })));
        let attested = false;
        for (let round = 0; round <= ctx.inputs.max_repair_attempts && !attested; round++) {
          const beforeAttempt = await tool(`self-maintained-baseline-${index}-${round}`, (signal) => snapshot(cwd, signal));
          const result = await stage(`revalidate-self-maintained-${index}-${round}`, {
            ...IMPL, context: "fresh", reads: [claimsFile, evidenceFile, ...observations.map((o) => o.artifactPath)], output: `${root}/attestation-${index}-${round}.md`, schema: Attestations,
            prompt: prompt("Revalidate every claim against tool observations, minimally repairing prose or documented checks where needed.", `Allowed edit directories: ${skillPaths.join(", ")}; they form the union of all SelfMaintained skill paths for change2. This stage owns the claims in ${claimsFile}. Never edit vendored content or derivation files. A contradicted claim gets an evidence-backed fail-closed prose repair by default; block only when no such repair exists. A documented example snippet that is itself a check may be corrected when a probe shows it misses forms upstream accepts; quote the upstream excerpt. Source artifacts identify the built .src store path, which you may read directly to verify CLI internals; do not ask the controller for excerpts. Re-attest or repair each claim and record 'verified against v${version}' in its source prose. Return one attestation per claim with an exact quotation from that claim's observation, verifiedAgainst exactly v${version}, and repaired indicating whether substantive prose was corrected. For each claim whose original literal text no longer occurs, include replacement with the same file, its new numeric line or line range, new literal text at the corresponding location, and verifiedAgainst v${version}. The tool validates replacements against the file and writes registered changes to ${root}/registry-updates.json for mechanical registry catch-up. Do not claim an unsupported attestation. Repair only within the bounded attempt; do not commit.`),
          });
          await tool(`self-maintained-scope-${index}-${round}`, async (signal) => scopeGate(beforeAttempt, await snapshot(cwd, signal), skillPaths));
          if (!Value.Check(Attestations, result.structured)) continue;
          const attestations = result.structured.claims;
          attested = attestations.length === dep.citedClaims.length && dep.citedClaims.every((claim, i) => {
            const a = attestations.filter((a) => a.claim === i);
            return a.length === 1 && a[0]!.verifiedAgainst === `v${version}` && quoteEvidence.some((o) => o.claim === i && o.observation.includes(a[0]!.quote));
          });
          if (attested) for (const claim of dep.citedClaims) if (!(await readFile(join(cwd, claim.file), "utf8")).toLowerCase().includes(`verified against v${version}`.toLowerCase())) attested = false;
          if (attested) {
            const updates: typeof registryUpdates = [];
            for (const [claimIndex, claim] of dep.citedClaims.entries()) {
              const content = await readFile(join(cwd, claim.file), "utf8");
              let replacement: Claim | null;
              try { replacement = validateClaimReplacement(claim, attestations.find((a) => a.claim === claimIndex)?.replacement, content, version); }
              catch (error) { if (!(error instanceof Blocked)) throw error; attested = false; break; }
              if (!replacement) continue;
              if (entry?.skillDeps.some((registered) => registered.kind === "SelfMaintained" && registered.skillPath === dep.skillPath && registered.citedClaims.some((c) => isDeepStrictEqual(c, claim)))) updates.push({ skillPath: dep.skillPath, previous: claim, replacement });
            }
            if (attested) {
              registryUpdates.push(...updates);
              await save(cwd, `${root}/registry-updates.json`, registryUpdates);
            }
          }
        }
        if (!attested) throw new Blocked(`Self-maintained claims not revalidated: ${dep.skillPath}`);
      }
      await tool("verify-registry-updates", async () => {
        const updates: typeof registryUpdates = [];
        for (const dep of entry?.skillDeps ?? []) if (dep.kind === "SelfMaintained") {
          for (const previous of dep.citedClaims) {
            const proposed = registryUpdates.find((u) => u.skillPath === dep.skillPath && isDeepStrictEqual(u.previous, previous));
            const replacement = validateClaimReplacement(previous, proposed?.replacement, await readFile(join(cwd, previous.file), "utf8"), version);
            if (replacement) updates.push({ skillPath: dep.skillPath, previous, replacement });
          }
        }
        await save(cwd, `${root}/registry-updates.json`, updates);
        return { artifactPath: `${root}/registry-updates.json`, updatedClaims: updates.length };
      });
      repaired = await tool("self-maintained-repair-paths", async (signal) => changed(preSkills, await snapshot(cwd, signal)));
      const reviewedTree = await tool("capture-review-diff", async (signal) => {
        requireSuccess(await capture(cwd, `git diff --no-ext-diff ${quote(initial.commit)} -- ${[prefix, ...self.map((s) => s.skillPath)].map(quote).join(" ")}`, signal, `${root}/review-diff.json`));
        return snapshot(cwd, signal);
      });

      const reviewed = await stage("review", {
        ...REVIEW, ...READ_ONLY, context: "fresh", reads: [manifestFile, buildLog, ledgerFile, `${root}/vendored.json`, `${root}/review-diff.json`], output: `${root}/review.md`, schema: Review,
        prompt: prompt("You did not implement this bump. Falsify it from actual diffs, source and tool artifacts, never a worker's self-report. Read-only; no edits.", `Check every version/pin and gate coverage, updater provenance, optional FOD hash build witness, vendored comparison, each claim and repair against observations, scope, model metadata and landing readiness. Evidence is the named tool nodes' checkpointed receipt and evidence fields and the files under ${root}/. Process receipts provide command, exitCode, logPath and tail (plus state and terminationSignal); inspect the bounded tail and targeted logPath excerpts, never a whole raw log. Pin evidence names its baseline predicate, observed literal and build witness; vendored evidence names the subtree, delivered path, file count and comparison result. If a node's result is insufficient to judge a criterion, record a finding against the workflow in the verdict rather than reconstructing evidence by hand or asking the controller. You have no shell and must not request one. Return changes_requested iff a blocking/major finding is evidenced; invent no requirements. Missing evidence for a required criterion blocks approval.`),
      });
      if (!Value.Check(Review, reviewed.structured) || reviewed.structured.verdict !== "approved" || reviewed.structured.findings.some((f) => f.severity !== "minor")) throw new Blocked("Independent review did not approve");
      await tool("review-read-only-gate", async (signal) => scopeGate(reviewedTree, await snapshot(cwd, signal), []));
      if (!(await ctx.ui.confirm(`Bump ${pkg} to ${version} passed gates. Create local jj delivery change(s)?`))) return { ...rest(), status: "completed", summary: "Verified; operator declined landing.", review_verdict: "approved", skill_deps_verified: true, landed: false, changes: [] };

      const allowed = repaired.length ? [[prefix], self.map((s) => s.skillPath)] : [[prefix]];
      const baseline = await tool("capture-land-topology", async (signal) => {
        scopeGate(initial.tree, await snapshot(cwd, signal), allowed.flat());
        const state = await topology(cwd, ctx.inputs.splice_after!, signal);
        if (state.workingCopy !== initial.topology.workingCopy) throw new Blocked("Working copy moved before landing");
        return state;
      });
      await save(cwd, `${root}/land-plan.json`, { baseline, allowed, changes: allowed.length });
      await stage("land", {
        ...LAND, context: "fresh", reads: [`${root}/land-plan.json`, buildLog, `${root}/review.md`], output: `${root}/land.md`,
        prompt: prompt("Land only the already-built and reviewed bump. You may create exactly the ordered delivery changes in the plan; no source edits.", `Verify @ remains ${baseline.workingCopy} before every mutation; stop on conflict, divergence or surprise. Create change1 exactly with jj new --no-edit -A ${baseline.splice} -m '<repo-style derivation message>'. If two changes, create change2 with jj new --no-edit -A <change1> -m '<skill repair message>'. Route only each plan's allowed paths with jj squash --from @ --into <that-new-change> --use-destination-message --keep-emptied -- <paths>. Never -B @; never unscoped squash; never modify preexisting changes. Leave unrelated paths alone and report them. The verifier checks ordered splice children, former child preservation, exact count and path sets, unchanged @ and no allowed paths left in @. Do not rebuild or push.`),
      });
      const verified = await ctx.tool("verify-land", { package: pkg }, async ({ signal }) => processCheckpoint(root, "verify-land", async () => {
        scopeGate(reviewedTree, await snapshot(cwd, signal), []);
        return verifyTopology(cwd, baseline, allowed, signal);
      }), { timeoutMs: 120_000, failureMode: "return" });
      ledger.push({ node: "verify-land", result: verified }); await save(cwd, ledgerFile, ledger);
      const landed = witness("verify-land", verified, (v) => ({ value: v.evidence.landed, evidence: v.evidence.evidence }));
      const changes = witness("verify-land", verified, (v) => ({ value: v.evidence.changes, evidence: v.evidence.evidence }));
      if (!landed?.value || !changes) throw new Blocked(`Landing unverified: ${JSON.stringify(verified)}`);
      return completedRun(landed, changes, { ...rest(), status: "completed", summary: `Bumped ${pkg} to ${version}; verified ${changes.value.length} spliced changes.`, review_verdict: "approved", skill_deps_verified: true });
    } catch (error) {
      ctx.exit({ status: "blocked", reason: String(error), outputs: { ...rest(), status: "blocked", summary: String(error), landed: false, changes: [] } });
      throw error;
    }
  },
});
