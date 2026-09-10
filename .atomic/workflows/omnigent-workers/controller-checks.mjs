import assert from "node:assert/strict";
import { mkdir, writeFile } from "node:fs/promises";

export async function controllerChecks({ definition, sliceDefinition, migrationDefinition, Operations, contracts, source, compact, models, modelResult }) {
  const root = `.atomic/workflows/runs/omnigent-workers-tests/${Date.now()}`;
  await mkdir(root, { recursive: true });
  const tree = `${root}/tree.json`;
  await writeFile(tree, "{}");
  class Exit extends Error { constructor(value) { super(value.reason); this.value = value; } }
  function context(inputs, config = {}) {
    const events = [];
    const seen = new Set();
    let review = 0;
    const node = (name) => { assert(!seen.has(name), `reopened DAG ancestor ${name}`); seen.add(name); events.push(name); };
    const ctx = {
      cwd: contracts.repository, inputs, models, events,
      exit: (value) => { throw new Exit(value); },
      ui: { confirm: async () => config.confirm ?? true, editor: async () => config.editor ?? "fixture human receipt", select: async () => "passed" },
      task: async (name, opts) => {
        node(name);
        assert.equal(opts.model, `${contracts.model}:high`);
        assert.equal(opts.thinkingLevel, "high");
        assert.deepEqual(opts.fallbackModels, []);
        let structured = { kind: "implemented", summary: "fixture implementation" };
        if (name.startsWith("review")) {
          review++;
          structured = config.contractFault ? { kind: "contract_defect", reason: "gate cannot check required property" } : { kind: "approved", evidence: [tree] };
        }
        return { structured, ...modelResult() };
      },
      tool: async (name, args, callback, options) => {
        node(name);
        assert(Number.isFinite(options.timeoutMs) && options.timeoutMs > 0);
        let evidence;
        if (name === "allocate-evidence") return root;
        if (name.includes("source") || name.includes("join") || name === "preflight" || name.startsWith("route-") || name.startsWith("post-review-")) evidence = source;
        if (name === "protected-baseline" || name.startsWith("before-") || name.startsWith("after-") || name.startsWith("diff-") || name.startsWith("save-")) evidence = tree;
        if (name.startsWith("gates-") || name.endsWith("-gates")) evidence = { passed: !(config.gateFailure && review === 0), results: [{ command: "fixture-check", exitCode: config.gateFailure && review === 0 ? 1 : 0 }], source };
        if (name.startsWith("protected-") && name !== "protected-baseline") evidence = { serverUnchanged: true, humansUnchanged: true };
        if (name.startsWith("clean-")) evidence = { foreignPaths: [] };
        if (name === "worker-metadata") evidence = { cameron: { enabled: true, user: "fixture-cameron", home: "/fixture/cameron", owner: "cameron", hostName: "fixture" } };
        assert.notEqual(evidence, undefined, `Unexpected effect requested in mock: ${name}`);
        const value = { receipt: [], evidence };
        compact(value);
        return { ok: true, value, attempts: 1, cached: false };
      },
      workflow: async (_child, options) => {
        node(options.stageName);
        assert(!options.worktree && !options.inputs.git_worktree_dir);
        if (config.childFailure) return { exited: true, exitReason: "fixture child blocked" };
        if (options.stageName.startsWith("migrate-")) return { exited: false, outputs: { host: options.inputs.host, sha: source.sha, system: "/nix/store/fixture-system", evidence: tree, acceptance: "human_attested" } };
        return { exited: false, outputs: { receipt: { phase: options.inputs.phase, change: source.change, sha: source.sha, evidence: tree } } };
      },
    };
    return ctx;
  }
  const input = { start_at: 0, deploy: false, max_repairs: 2, build_timeout_minutes: 1 };
  let ctx = context(input);
  const result = await definition.run(ctx);
  assert.equal(result.status, "implementation-ready");
  assert.deepEqual(ctx.events.filter((n) => n.startsWith("slice-")), ["slice-capabilities", "slice-linux", "slice-darwin", "slice-inventory"]);
  assert(!ctx.events.some((n) => n.startsWith("migrate")));
  ctx = context(input, { childFailure: true });
  await assert.rejects(definition.run(ctx), /fixture child blocked/);
  assert.equal(ctx.events.filter((n) => n.startsWith("slice-")).length, 1);
  ctx = context({ ...input, deploy: true });
  const completed = await definition.run(ctx);
  assert.equal(completed.status, "human-attested");
  assert.deepEqual(completed.hosts.map((h) => h.host), contracts.hosts);
  assert(ctx.events.indexOf("migrate-stibnite") < ctx.events.indexOf("slice-closure"));
  ctx = context({ ...input, deploy: true, start_at: 6 });
  assert.equal((await definition.run(ctx)).status, "partial-resume");

  const childInput = { phase: "linux", root, timeout: 1000, max_repairs: 2, verify_only: false, reads: [] };
  ctx = context(childInput, { gateFailure: true });
  const repaired = await sliceDefinition.run(ctx);
  assert.equal(repaired.receipt.phase, "linux");
  assert(ctx.events.includes("implement-linux-1"));
  assert(!ctx.events.includes("implement-linux-2"));
  assert(ctx.events.indexOf("review-linux-0") < ctx.events.indexOf("implement-linux-1"));
  ctx = context(childInput, { contractFault: true });
  await assert.rejects(sliceDefinition.run(ctx), /gate cannot check required property/);
  assert(!ctx.events.includes("implement-linux-1"));
  ctx = context({ ...childInput, verify_only: true }, { gateFailure: true });
  await assert.rejects(sliceDefinition.run(ctx), /Unverified linux/);
  assert(!ctx.events.some((n) => n.startsWith("implement-")));

  ctx = context({ host: "stibnite", root, timeout: 1000, max_repairs: 2, reads: [] }, { confirm: false });
  await assert.rejects(migrationDefinition.run(ctx), /Enrollment incomplete/);
  assert(!ctx.events.some((n) => n.startsWith("activate-") || n.startsWith("enable-")));

  const commands = [];
  const capture = async (_cwd, command) => {
    commands.push(command);
    const stdout = command.includes("-r '@'") ? `${source.workingCopy}\n` : command.includes("conflicts()") ? "fixture-conflict" : "";
    return { stdout, stderr: "", command, exitCode: 0, state: "exited", terminationSignal: null, logPath: "fixture", tail: stdout };
  };
  const ops = new Operations({}, root, 1000, capture);
  await assert.rejects(ops.healthy(new AbortController().signal), /Conflicted or divergent/);
  assert(commands.every((c) => c.startsWith("jj --ignore-working-copy log")));
  assert.throws(() => compact({ stdout: "raw" }));
  assert.throws(() => compact({ tail: "x".repeat(8193) }));
  const rejected = new Operations({ tool: async () => ({ ok: false, error: { name: "WorkerMigrationBlocked:reconcile", message: "topology changed" }, attempts: 1, cached: false }) }, root, 1000);
  await assert.rejects(rejected.tool("reject", {}, async () => { throw new Error("callback must not execute"); }), (error) => error.category === "reconcile");
  console.log("PASS controller: disabled deployment, child stop, gate/repair/success, contract fault without repair, current-state failure, pending login, topology fault, compact receipts and fresh DAG nodes");
}
