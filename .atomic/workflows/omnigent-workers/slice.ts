import { workflow } from "@bastani/atomic/workflows";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { quote } from "../bump/tools.js";
import { childInputs, outputs, slice, invariants, research, repository, StageReport, Review, Stop, rethrowControl, parse, type Source, type Phase } from "./contract.js";
import { Operations, digest, integrated, foreignContextChanged } from "./operations.js";
import { gates, baselineExpr } from "./gates.js";

type Projection = { source: Source; path: string; digest: string; expression: string; expressionDigest: string; controller: string; command: string };
type Protected = { humans: unknown; server: string };
export async function projection(ops: Operations, name: string, source: Source): Promise<Projection> {
  return ops.tool(name, { source }, async (signal) => {
    const expression = `${ops.root}/${name}.nix`, path = `${ops.root}/${name}.json`, text = baselineExpr(source.source);
    const controller = digest(await Promise.all(["contract", "operations", "slice", "gates"].map((file) => readFile(join(repository, `.atomic/workflows/omnigent-workers/${file}.ts`), "utf8"))));
    await writeFile(join(repository, expression), text, { mode: 0o600, flag: "wx" });
    await writeFile(join(repository, path), "", { mode: 0o600, flag: "wx" });
    const command = `nix eval --no-write-lock-file --impure --json --file ${quote(join(repository, expression))} > ${quote(join(repository, path))}`;
    await ops.command(command, signal);
    const value = await readFile(join(repository, path), "utf8");
    const parsed: Protected = JSON.parse(value);
    if (typeof parsed.server !== "string" || !parsed.humans) throw new Stop("contract", "Malformed protected projection");
    return { source, path, digest: digest(value), expression, expressionDigest: digest(text), controller, command };
  });
}
export async function protectedComparison(ops: Operations, name: string, baseline: Projection, source: Source) {
  if (source.role !== baseline.source.role) throw new Stop("contract", "Protected comparison crosses source roles");
  const candidate = await projection(ops, `${name}-candidate`, source);
  return ops.tool(name, { baseline, source, candidate }, async (signal) => {
    signal.throwIfAborted();
    const oldText = await readFile(join(repository, baseline.path), "utf8"), newText = await readFile(join(repository, candidate.path), "utf8");
    if (digest(oldText) !== baseline.digest || digest(newText) !== candidate.digest || baseline.controller !== candidate.controller) throw new Stop("reconcile", "Protected baseline, candidate or controller changed; never recapture from candidate");
    const old: Protected = JSON.parse(oldText), current: Protected = JSON.parse(newText);
    return { baseline, candidate, serverUnchanged: old.server === current.server, humansUnchanged: digest(old.humans) === digest(current.humans) };
  });
}
const preserved = (phase: Phase, result: { serverUnchanged: boolean; humansUnchanged: boolean }) => result.serverUnchanged && (phase !== "capabilities" || result.humansUnchanged);
async function contextPreserved(ops: Operations, name: string, phase: Phase, baseline: Projection, previous: Source, current: Source) {
  if (current.sha !== previous.sha || current.workingCopy !== previous.workingCopy || current.join.change !== previous.join.change) throw new Stop("reconcile", "Authoring source or shared join moved");
  if (!foreignContextChanged(previous, current)) return { previous, current, contentUnchanged: true };
  const result = await protectedComparison(ops, name, baseline, integrated(current));
  if (!preserved(phase, result)) throw new Stop("reconcile", "Relevant foreign integrated behavior changed against the fixed baseline; reconcile once before proceeding");
  return { previous, current, result };
}
export default workflow({
  name: "omnigent-worker-slice",
  description: "One scoped implementation, immutable-source gates and independent review with bounded forward-only repairs.",
  inputs: childInputs,
  outputs,
  run: async (ctx) => {
    const input = ctx.inputs, spec = slice(input.phase);
    const ops = new Operations(ctx, input.root, input.timeout);
    let source = await ops.observeSource("slice-source");
    const base = source;
    let feedback: string[] = [];
    try {
      if (!input.verify_only) await ops.assertCleanScope(spec);
      const baselineOwned = await ops.snapshot("baseline-owned", spec, base);
      const baseline = await projection(ops, "protected-baseline-chain", base);
      const integratedBaseline = await projection(ops, "protected-baseline-integrated", integrated(base));
      const baselineEvidence = await ops.save("baselines", { baseline, integratedBaseline, baselineOwned });
      for (let attempt = 0; attempt <= input.max_repairs; attempt++) {
        const suffix = `${spec.phase}-${attempt}`;
        const writerSource = await ops.observeSource(`writer-source-${suffix}`);
        const writerContext = await contextPreserved(ops, `protected-writer-context-${suffix}`, spec.phase, integratedBaseline, source, writerSource);
        source = writerSource;
        const before = await ops.snapshot(`before-${suffix}`, spec, source);
        let attribution = { before, after: before, context: source, preservation: writerContext };
        if (!input.verify_only) {
          const report = await ops.stage(`implement-${suffix}`, {
            tools: ["read", "search", "find", "ls", "bash", "write", "edit"], schema: StageReport,
            reads: [research, baselineEvidence, baseline.path, integratedBaseline.path, ...input.reads, ...feedback], output: `${input.root}/implement-${suffix}.md`, outputMode: "file-only",
            prompt: `${invariants}\nObjective: ${spec.objective}\nAllowed paths: ${spec.paths.join(", ")}\nAcceptance: ${spec.acceptance.join("\n")}\nChain baseline C0 ${base.sha} (${base.source}), ${baseline.path}: independently shippable authoring context, not the filesystem baseline. Integrated baseline J0 ${integratedBaseline.source.sha} (${integratedBaseline.source.source}), ${integratedBaseline.path}: preserve the shared-tree human/server behavior including foreign contributions. Current authoring tip ${source.sha}, integrated context ${source.join.sha}. Local pre-edit checks must use matching context; repairs retain both original baselines and must not compare a known failed candidate as a new baseline. Read ${research}, ${baselineEvidence}, and supplied evidence before editing. Implement and test the exact named checks using actual modules and discriminating negative fixtures, not constant-success derivations. Preserve all server/foreign-service configuration. Do not run full flake checks or change historical workflow gates. Feedback: ${feedback.join(", ") || "none"}. Report implementation or a concrete blocker through the schema.`,
          });
          const result = parse(StageReport, report.structured);
          if (result.kind === "blocked") throw new Stop("contract", result.reason);
          const after = await ops.snapshot(`after-${suffix}`);
          const context = await ops.routeContext(`pre-route-source-${suffix}`, spec, before, after, source);
          const preservation = await contextPreserved(ops, `protected-route-context-${suffix}`, spec.phase, integratedBaseline, source, context);
          attribution = { before, after, context, preservation };
          source = await ops.route(`route-${suffix}`, spec, before, after, source, context);
        }
        const gate = await gates(ops, `gates-${suffix}`, spec.phase, source);
        const protectedResult = await protectedComparison(ops, `protected-chain-${suffix}`, baseline, source);
        const integratedResult = await protectedComparison(ops, `protected-integrated-${suffix}`, integratedBaseline, integrated(source));
        const evidence = await ops.save(`gates-${suffix}`, { gate, protectedResult, integratedResult, baselineEvidence, source, attribution, writerContext });
        const diff = await ops.tool(`diff-${suffix}`, { base, source }, async (signal) => {
          const path = `${input.root}/diff-${suffix}.patch`;
          const content = await ops.command(`git --no-pager diff ${quote(base.sha)} ${quote(source.sha)} -- ${spec.paths.map(quote).join(" ")}`, signal);
          await import("node:fs/promises").then((fs) => fs.writeFile(join(repository, path), content));
          return path;
        });
        const reviewPath = `${input.root}/review-${suffix}.md`;
        const report = await ops.stage(`review-${suffix}`, {
          tools: ["read", "search", "find", "ls", "bash"], schema: Review,
          reads: [research, evidence, diff, ...input.reads], output: reviewPath, outputMode: "file-only",
          prompt: `${invariants}\nREAD ONLY review: no edits, mutation, credentials, builds or runtime actions. Inspect independently shippable chain source C1 at git revision ${source.sha}, attributed diff against C0 ${base.sha}, and integrated source J1 ${source.join.sha} against fixed J0 ${integratedBaseline.source.sha}, not the current working tree. Inspect the source-bound paired preservation receipts and writer byte attribution / foreign-parent continuity in ${evidence}. These checks do not certify a later join; deployment requires fresh exact integrated-source gates. Objective: ${spec.objective}\nAcceptance: ${spec.acceptance.join("\n")}\nInspect ${evidence}, ${diff} and the realized artifacts produced by checks. A test name, worker summary, or successful build with vacuous checks is not coverage. Verify negative fixtures actually reject plausible wrong module identities, ordering and privileges. ${input.verify_only ? "This is current-state resume verification: read the actual implementation, not merely the empty diff. Earlier historical gates are intentionally not replayed." : "Review the attributed diff."}\nPredeployment review cannot demand live authentication, successful deployment or human lifecycle observations. An unrepairable contract/gate defect is contract_defect, not repair. Approval requires actual gates plus both same-role source comparisons; model approval never overrides tool failure. Repair lists only in-scope implementation defects. Preserve any material unverified requirement.`,
        });
        const review = parse(Review, report.structured);
        const observed = await ops.observeSource(`post-review-${suffix}`);
        const acceptanceContext = await contextPreserved(ops, `protected-acceptance-context-${suffix}`, spec.phase, integratedBaseline, source, observed);
        const acceptanceOwned = await ops.snapshot(`acceptance-owned-${suffix}`, spec, observed);
        const decisionPath = await ops.save(`decision-${suffix}`, { review, prose: reviewPath, gates: evidence, source, acceptanceContext, acceptanceOwned, verifiedIntegrated: source.join });
        if (review.kind === "contract_defect") throw new Stop("contract", review.reason);
        if (review.kind === "approved" && gate.passed && preserved(spec.phase, protectedResult) && preserved(spec.phase, integratedResult)) {
          const receipt = { phase: spec.phase, change: source.change, sha: source.sha, evidence: decisionPath };
          await ops.save(`verified-${spec.phase}`, { receipt, gates: evidence });
          return { receipt };
        }
        if (input.verify_only || attempt === input.max_repairs) throw new Stop("implementation", `Unverified ${spec.phase}; retain ${source.change} and inspect ${evidence} / ${reviewPath}`);
        feedback = [evidence, decisionPath];
        source = observed;
      }
      throw new Stop("contract", "Unreachable repair boundary");
    } catch (error) {
      rethrowControl(error);
      const category = error instanceof Stop ? error.category : "infrastructure";
      return ctx.exit({ status: "blocked", reason: `${category}: ${String(error)}; phase=${spec.phase}; change=${source.change}; evidence=${input.root}` });
    }
  },
});
