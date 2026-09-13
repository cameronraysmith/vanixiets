import { workflow } from "@bastani/atomic/workflows";
import { Type } from "typebox";
import { mkdir } from "node:fs/promises";
import { randomUUID } from "node:crypto";
import { join } from "node:path";
import implementation from "./omnigent-workers/slice.js";
import migration from "./omnigent-workers/migration.js";
import { inputs, repository, phases, hosts, Receipt, Stop, rethrowControl, research, type Receipt as SliceReceipt } from "./omnigent-workers/contract.js";
import { Operations, currentModel } from "./omnigent-workers/operations.js";

export default workflow({
  name: "omnigent-workers",
  description: "Dedicated real-user workers: six scoped implementation children, three reconciled host migrations, then evidence closure on omnigent-magnetite.",
  heartbeatIntervalMinutes: 15,
  inputs,
  outputs: {
    status: Type.Union([Type.Literal("implementation-ready"), Type.Literal("human-attested"), Type.Literal("partial-resume")]),
    evidence_root: Type.String(),
    slices: Type.Array(Receipt),
    hosts: Type.Array(Type.Object({ host: Type.String(), sha: Type.String(), system: Type.String(), evidence: Type.String(), acceptance: Type.Literal("human_attested") }, { additionalProperties: false })),
  },
  run: async (ctx) => {
    if ((ctx.cwd ?? process.cwd()) !== repository) return ctx.exit({ status: "blocked", reason: `Run from ${repository}` });
    await currentModel(ctx);
    const root = await ctx.tool("allocate-evidence", {}, async ({ signal }) => {
      signal.throwIfAborted();
      const path = `.atomic/workflows/runs/omnigent-workers/${randomUUID()}`;
      await mkdir(join(repository, path), { recursive: true, mode: 0o700 });
      return path;
    }, { timeoutMs: 30_000 });
    const timeout = ctx.inputs.build_timeout_minutes * 60_000;
    const ops = new Operations(ctx, root, timeout);
    const receipts: SliceReceipt[] = [];
    const migrated: { host: string; sha: string; system: string; evidence: string; acceptance: "human_attested" }[] = [];
    const reads = [research];
    try {
      await ops.observeSource("preflight");
      if (ctx.inputs.start_at > 0 && (ctx.inputs.start_at < phases.indexOf(hosts[0]) || phases[ctx.inputs.start_at] === "closure")) {
        const previous = phases[ctx.inputs.start_at - 1]!;
        const verified = await ctx.workflow(implementation, {
          stageName: `reconcile-current-${previous}`,
          inputs: { phase: previous, root: `${root}/reconcile`, timeout, max_repairs: 0, verify_only: true, reads },
        });
        if (verified.exited === true) return ctx.exit({ status: "blocked", reason: verified.exitReason ?? "Current state could not be reconciled", outputs: { evidence_root: root } });
        receipts.push(verified.outputs.receipt);
        reads.push(verified.outputs.receipt.evidence);
      }
      for (const [index, phase] of phases.entries()) {
        if (index < ctx.inputs.start_at) continue;
        if (phase === "magnetite" || phase === "pyrite" || phase === "stibnite") {
          if (!ctx.inputs.deploy) {
            if (!receipts.some((receipt) => receipt.phase === "credentials")) throw new Stop("reconcile", "No current implementation evidence; start at an implementation phase to verify credentials before claiming readiness");
            return { status: "implementation-ready" as const, evidence_root: root, slices: receipts, hosts: migrated };
          }
          const result = await ctx.workflow(migration, {
            stageName: `migrate-${phase}`,
            inputs: { host: phase, root: `${root}/${phase}`, timeout, max_repairs: ctx.inputs.max_repairs, reads: [...reads] },
          });
          if (result.exited === true) return ctx.exit({ status: "blocked", reason: result.exitReason ?? `${phase} migration incomplete`, outputs: { evidence_root: root, slices: receipts, hosts: migrated } });
          migrated.push(result.outputs);
          reads.push(result.outputs.evidence);
        } else {
          if (phase === "inventory" && !await ctx.ui.confirm("Authorize preparing the five dedicated account declarations with execution disabled? Check prospective Unix names/home/UID/GID against existing account metadata before choosing them; Raquel's placeholder email and another machine's UID are not authoritative. Collision readback and enrollment occur before execution.")) throw new Stop("human", "Account declaration approval missing");
          const result = await ctx.workflow(implementation, {
            stageName: `slice-${phase}`,
            inputs: { phase, root: `${root}/${phase}`, timeout, max_repairs: ctx.inputs.max_repairs, verify_only: false, reads: [...reads] },
          });
          if (result.exited === true) return ctx.exit({ status: "blocked", reason: result.exitReason ?? `${phase} unverified`, outputs: { evidence_root: root, slices: receipts, hosts: migrated } });
          receipts.push(result.outputs.receipt);
          reads.push(result.outputs.receipt.evidence);
        }
      }
      const status = migrated.length === hosts.length ? "human-attested" as const : "partial-resume" as const;
      await ops.save("result", { status, slices: receipts, hosts: migrated });
      return { status, evidence_root: root, slices: receipts, hosts: migrated };
    } catch (error) {
      rethrowControl(error);
      return ctx.exit({ status: "blocked", reason: `${error instanceof Stop ? error.category : "infrastructure"}: ${String(error)}`, outputs: { evidence_root: root, slices: receipts, hosts: migrated } });
    }
  },
});
