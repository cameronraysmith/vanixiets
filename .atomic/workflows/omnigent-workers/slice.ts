import { workflow } from "@bastani/atomic/workflows";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { quote } from "../bump/tools.js";
import { childInputs, outputs, slice, invariants, research, repository, StageReport, Review, Stop, rethrowControl, parse } from "./contract.js";
import { Operations, digest } from "./operations.js";
import { gates, baselineExpr } from "./gates.js";

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
    const baseline = await ops.tool("protected-baseline", { base }, async (signal) => {
      const value: unknown = JSON.parse(await ops.command(`nix eval --no-write-lock-file --impure --json --expr ${quote(baselineExpr(base.source))}`, signal));
      const path = `${input.root}/${spec.phase}-protected-baseline.json`;
      await import("node:fs/promises").then((fs) => fs.writeFile(join(repository, path), JSON.stringify(value), { mode: 0o600 }));
      return path;
    });
    let feedback: string[] = [];
    try {
      if (!input.verify_only) await ops.assertCleanScope(spec);
      for (let attempt = 0; attempt <= input.max_repairs; attempt++) {
        const suffix = `${spec.phase}-${attempt}`;
        if (!input.verify_only) {
          const before = await ops.snapshot(`before-${suffix}`, spec);
          const report = await ops.stage(`implement-${suffix}`, {
            tools: ["read", "search", "find", "ls", "bash", "write", "edit"], schema: StageReport,
            reads: [research, baseline, ...input.reads, ...feedback], output: `${input.root}/implement-${suffix}.md`, outputMode: "file-only",
            prompt: `${invariants}\nObjective: ${spec.objective}\nAllowed paths: ${spec.paths.join(", ")}\nAcceptance: ${spec.acceptance.join("\n")}\nRead ${research}, ${baseline}, and supplied evidence before editing. Implement and test the exact named checks using actual modules and discriminating negative fixtures, not constant-success derivations. Preserve all server/foreign-service configuration. Do not run full flake checks or change historical workflow gates. Feedback: ${feedback.join(", ") || "none"}. Report implementation or a concrete blocker through the schema.`,
          });
          const result = parse(StageReport, report.structured);
          if (result.kind === "blocked") throw new Stop("contract", result.reason);
          const after = await ops.snapshot(`after-${suffix}`);
          source = await ops.route(`route-${suffix}`, spec, before, after, source);
        }
        const gate = await gates(ops, `gates-${suffix}`, spec.phase, source);
        const protectedResult = await ops.tool(`protected-${suffix}`, { base, source, phase: spec.phase }, async (signal) => {
          const old: { humans: unknown; server: string } = JSON.parse(await readFile(join(repository, baseline), "utf8"));
          const current: { humans: unknown; server: string } = JSON.parse(await ops.command(`nix eval --no-write-lock-file --impure --json --expr ${quote(baselineExpr(source.source))}`, signal));
          return { serverUnchanged: old.server === current.server, humansUnchanged: digest(old.humans) === digest(current.humans) };
        });
        const evidence = await ops.save(`gates-${suffix}`, { gate, protectedResult, baseline, source });
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
          prompt: `${invariants}\nREAD ONLY review: no edits, mutation, credentials, builds or runtime actions. Inspect actual source at git revision ${source.sha}, not the current working tree. Objective: ${spec.objective}\nAcceptance: ${spec.acceptance.join("\n")}\nInspect ${evidence}, ${diff} and the realized artifacts produced by checks. A test name, worker summary, or successful build with vacuous checks is not coverage. Verify negative fixtures actually reject plausible wrong module identities, ordering and privileges. ${input.verify_only ? "This is current-state resume verification: read the actual implementation, not merely the empty diff. Earlier historical gates are intentionally not replayed." : "Review the attributed diff."}\nPredeployment review cannot demand live authentication, successful deployment or human lifecycle observations. An unrepairable contract/gate defect is contract_defect, not repair. Approval requires actual gates plus source agreement; repair lists only in-scope implementation defects. Preserve any material unverified requirement.`,
        });
        const review = parse(Review, report.structured);
        const decisionPath = await ops.save(`decision-${suffix}`, { review, prose: reviewPath, gates: evidence, source });
        const observed = await ops.observeSource(`post-review-${suffix}`);
        if (observed.sha !== source.sha) throw new Stop("reconcile", `Reviewed source drifted: ${source.sha} -> ${observed.sha}; current-state re-verification required`);
        if (review.kind === "contract_defect") throw new Stop("contract", review.reason);
        if (review.kind === "approved" && gate.passed && protectedResult.serverUnchanged && (spec.phase !== "capabilities" || protectedResult.humansUnchanged)) {
          const receipt = { phase: spec.phase, change: source.change, sha: source.sha, evidence: decisionPath };
          await ops.save(`verified-${spec.phase}`, { receipt, gates: evidence });
          return { receipt };
        }
        if (input.verify_only || attempt === input.max_repairs) throw new Stop("implementation", `Unverified ${spec.phase}; retain ${source.change} and inspect ${evidence} / ${reviewPath}`);
        feedback = [evidence, decisionPath];
      }
      throw new Stop("contract", "Unreachable repair boundary");
    } catch (error) {
      rethrowControl(error);
      const category = error instanceof Stop ? error.category : "infrastructure";
      return ctx.exit({ status: "blocked", reason: `${category}: ${String(error)}; phase=${spec.phase}; change=${source.change}; evidence=${input.root}` });
    }
  },
});
