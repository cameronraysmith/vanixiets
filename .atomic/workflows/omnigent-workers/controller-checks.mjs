import assert from "node:assert/strict";
import { mkdir, writeFile, readFile } from "node:fs/promises";

export async function controllerChecks({ definition, sliceDefinition, sliceModule, migrationDefinition, Operations, operations, contracts, source, compact, models, modelResult, realArtifacts }) {
  const root = `.atomic/workflows/runs/omnigent-workers-tests/${Date.now()}`;
  await mkdir(root, { recursive: true });
  const tree = `${root}/tree.json`;
  await writeFile(tree, "{}");
  const load = async (name) => JSON.parse(await readFile(`.atomic/workflows/runs/omnigent-workers-real-provenance-${name}.json`, "utf8"));
  const values = realArtifacts ? { c0: await load("snapshot-c0"), c1: await load("snapshot-c1"), j0: await load("j0"), j1: await load("snapshot-j1"), negative: await load("snapshot-j-negative") } : { c0: { humans: { generation: "chain" }, server: "server" }, c1: { humans: { generation: "chain" }, server: "server" }, j0: { humans: { generation: "integrated-with-niri" }, server: "server" }, j1: { humans: { generation: "integrated-with-niri" }, server: "server" }, negative: { humans: { generation: "integrated-niri-changed" }, server: "server" } };
  assert.deepEqual(values.c0, values.c1);
  assert.deepEqual(values.j0, values.j1);
  assert.notDeepEqual(values.c0, values.j0);
  assert.notDeepEqual(values.j0, values.negative);
  const routed = { ...source, change: "o".repeat(32), sha: "b".repeat(40), tree: "b".repeat(40), source: `git+file://${contracts.repository}?rev=${"b".repeat(40)}`, joinParents: source.joinParents.map((p) => p === source.change ? "o".repeat(32) : p), join: { ...source.join, sha: "c".repeat(40), tree: "c".repeat(40), parents: source.join.parents.map((p) => p.change === source.change ? { change: "o".repeat(32), sha: "b".repeat(40) } : p) } };
  const advanced = (base, metadataOnly = false) => ({ ...base, join: { ...base.join, sha: "d".repeat(40), tree: metadataOnly ? base.join.tree : "e".repeat(40), parents: base.join.parents.map((p, i) => i === 0 ? { ...p, sha: "f".repeat(40) } : p) } });
  const originalCommand = Operations.prototype.command;
  Operations.prototype.command = async function (command) {
    const match = /^nix eval .* --file '([^']+)' > '([^']+)'$/.exec(command);
    assert(match, `Unexpected command in controller fixture: ${command}`);
    const expression = await readFile(match[1], "utf8"), sha = /\?rev=([a-f0-9]{40})/.exec(expression)?.[1];
    const config = this.ctx.fixtureConfig;
    if (config.evalFailure && sha === routed.join.sha) throw Error("fixture integrated evaluation failed");
    const value = sha === source.sha ? values.c0 : sha === routed.sha ? values.c1 : sha === source.join.sha ? values.j0 : sha === routed.join.sha ? (config.integratedFailure ? values.negative : values.j1) : sha === "d".repeat(40) ? (config.foreignDrift ? values.negative : values.j0) : undefined;
    assert(value, `Unknown immutable fixture source ${sha}`);
    let projected = value;
    if (expression.includes("janette = let")) {
      const candidate = sha === routed.sha || sha === routed.join.sha;
      const email = candidate ? (config.janetteMailDiff ? "wrong@example.com" : contracts.janetteMailExclusion.canonicalEmail) : this.ctx.inputs.phase === "identity" ? "old@example.com" : contracts.janetteMailExclusion.canonicalEmail;
      const behavior = candidate && config.janetteBehaviorDiff ? "changed-human-behavior" : "preserved-human-behavior";
      projected = { ...value, janette: { human: { email, behavior }, mailIndependent: { behavior }, author: { gitEmail: email, jjEmail: email, principal: email, allowedSigners: `${email} namespaces="git" public-key\n` } }, stibniteWorker: { generation: candidate && config.stibniteWorkerDiff ? "changed-worker-generation" : "worker-generation", output: "worker-output" } };
    }
    await writeFile(match[2], JSON.stringify(projected), { mode: 0o600 });
    return "";
  };
  let scenario = 0;
  class Exit extends Error { constructor(value) { super(value.reason); this.value = value; } }
  function context(inputs, config = {}) {
    const events = [];
    const seen = new Set();
    let review = 0, didRoute = false;
    const node = (name) => { assert(!seen.has(name), `reopened DAG ancestor ${name}`); seen.add(name); events.push(name); };
    const ctx = {
      cwd: contracts.repository, inputs: { ...inputs, root: `${root}/scenario-${++scenario}` }, models, events, fixtureConfig: config,
      observations: [],
      exit: (value) => { throw new Exit(value); },
      ui: { confirm: async () => config.confirm ?? true, editor: async () => config.editor ?? "fixture human receipt", select: async () => "passed" },
      task: async (name, opts) => {
        node(name);
        ctx.observations.push({ name, options: opts });
        assert.equal(opts.model, `${contracts.model}:high`);
        assert.equal(opts.thinkingLevel, "high");
        assert.deepEqual(opts.fallbackModels, []);
        let structured = { kind: "implemented", summary: "fixture implementation" };
        if (name.startsWith("review")) {
          review++;
          structured = config.contractFault ? { kind: "contract_defect", reason: "gate cannot check required property" } : { kind: "approved", evidence: [tree] };
          const evidence = JSON.parse(await readFile(opts.reads[1], "utf8"));
          ctx.reviewEvidence = evidence;
          assert.equal(evidence.protectedResult.baseline.source.sha, source.sha);
          assert.equal(evidence.integratedResult.baseline.source.sha, source.join.sha);
          assert.equal(evidence.integratedResult.candidate.source.sha, evidence.source.join.sha);
          assert.equal(evidence.attribution.preservation?.current.join.sha, evidence.attribution.context.join.sha, "review must receive the pre-route context preservation evidence, not only the resulting join");
          assert(opts.prompt.includes(evidence.source.sha) && opts.prompt.includes(evidence.source.join.sha));
        }
        return { structured, ...modelResult() };
      },
      tool: async (name, args, callback, options) => {
        node(name);
        ctx.observations.push({ name, args });
        if (name.startsWith("protected-") || name.startsWith("save-")) {
          const value = await callback({ signal: new AbortController().signal });
          compact(value);
          return { ok: true, value, attempts: 1, cached: false };
        }
        assert(Number.isFinite(options.timeoutMs) && options.timeoutMs > 0);
        let evidence;
        if (name === "allocate-evidence") return root;
        if (name.startsWith("route-")) {
          assert.equal(args.previous.role, "chain");
          assert.equal(args.previous.sha, didRoute ? routed.sha : source.sha);
          didRoute = true;
        }
        if (name.includes("source") || name.includes("join") || name === "preflight" || name.startsWith("route-") || name.startsWith("post-review-")) evidence = didRoute ? routed : source;
        if ((config.foreignDrift || config.metadataOnly) && name.startsWith("pre-route-source")) evidence = advanced(source, config.metadataOnly);
        if (config.laterJoin && name.startsWith("post-review")) evidence = advanced(routed, true);
        if (args.rev === "@-") evidence = operations.integrated(evidence);
        if (name === "baseline-owned" || name.startsWith("acceptance-owned-") || name.startsWith("before-") || name.startsWith("after-") || name.startsWith("diff-")) evidence = tree;
        if (name.startsWith("gates-") || name.endsWith("-gates")) evidence = { passed: !(config.gateFailure && review === 0), results: [{ command: "fixture-check", exitCode: config.gateFailure && review === 0 ? 1 : 0 }], source: didRoute ? routed : source };
        if (name.startsWith("clean-")) evidence = { foreignPaths: [] };
        if (name === "worker-metadata") evidence = { cameron: { enabled: config.enabled ?? true, user: "fixture-cameron", home: "/fixture/cameron", owner: "cameron", hostName: "fixture" } };
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
        return { exited: false, outputs: { receipt: { phase: options.inputs.phase === "credentials" && config.staleReceipt ? "inventory" : options.inputs.phase, change: source.change, sha: source.sha, evidence: tree } } };
      },
    };
    return ctx;
  }
  const input = { start_at: 0, deploy: false, max_repairs: 2, build_timeout_minutes: 1 };
  let ctx = context(input);
  const result = await definition.run(ctx);
  assert.equal(result.status, "implementation-ready");
  assert.deepEqual(ctx.events.filter((n) => n.startsWith("slice-")), ["slice-capabilities", "slice-linux", "slice-darwin", "slice-inventory", "slice-identity", "slice-credentials"]);
  assert(!ctx.events.some((n) => n.startsWith("migrate")));
  assert.equal(result.slices.at(-1).phase, "credentials");
  ctx = context(input, { staleReceipt: true });
  await assert.rejects(definition.run(ctx), /verify credentials before claiming readiness/);
  for (const [start_at, previous] of [[1, "capabilities"], [2, "linux"], [3, "darwin"], [4, "inventory"], [5, "identity"], [9, "stibnite"]]) {
    ctx = context({ ...input, start_at });
    const resumed = await definition.run(ctx);
    assert(ctx.events.includes(`reconcile-current-${previous}`));
    assert.equal(resumed.status, start_at === 9 ? "partial-resume" : "implementation-ready");
  }
  ctx = context(input, { childFailure: true });
  await assert.rejects(definition.run(ctx), /fixture child blocked/);
  assert.equal(ctx.events.filter((n) => n.startsWith("slice-")).length, 1);
  ctx = context({ ...input, deploy: true });
  const completed = await definition.run(ctx);
  assert.equal(completed.status, "human-attested");
  assert.deepEqual(completed.hosts.map((h) => h.host), contracts.hosts);
  assert(ctx.events.indexOf("migrate-stibnite") < ctx.events.indexOf("slice-closure"));
  ctx = context({ ...input, deploy: true, start_at: 8 });
  assert.equal((await definition.run(ctx)).status, "partial-resume");

  const j0 = source.join.sha;
  const capabilities = { phase: "capabilities", root, timeout: 1000, max_repairs: 0, verify_only: false, reads: [] };
  ctx = context(capabilities);
  const preservation = await sliceDefinition.run(ctx);
  assert.equal(preservation.receipt.sha, routed.sha, "receipt continues to name independently shippable chain source");
  const writer = ctx.observations.find((e) => e.name === "implement-capabilities-0");
  assert(writer.options.prompt.includes(j0), "writer must receive the immutable integrated baseline identity, not just the isolated chain baseline");
  assert(writer.options.prompt.includes(source.sha));
  assert(ctx.observations.some((e) => e.args?.source?.sha === routed.join.sha && e.name.startsWith("protected-")), "acceptance must establish matched integrated preservation");
  assert(ctx.reviewEvidence.protectedResult.humansUnchanged && ctx.reviewEvidence.integratedResult.humansUnchanged);
  ctx = context(capabilities, { integratedFailure: true });
  await assert.rejects(sliceDefinition.run(ctx), /Unverified capabilities/);
  assert(ctx.reviewEvidence.protectedResult.humansUnchanged && !ctx.reviewEvidence.integratedResult.humansUnchanged, "chain equality cannot waive an integrated-only Niri change");
  ctx = context(capabilities, { evalFailure: true });
  await assert.rejects(sliceDefinition.run(ctx), /integrated evaluation failed/);
  assert(!ctx.events.includes("review-capabilities-0"));
  ctx = context({ ...capabilities, max_repairs: 2 }, { foreignDrift: true });
  await assert.rejects(sliceDefinition.run(ctx), /Relevant foreign integrated behavior changed/);
  assert(!ctx.events.some((n) => n.startsWith("route-") || n === "implement-capabilities-1"));
  ctx = context(capabilities, { metadataOnly: true, laterJoin: true });
  const metadata = await sliceDefinition.run(ctx);
  assert.equal(metadata.receipt.sha, routed.sha);
  assert(!ctx.events.some((n) => n.startsWith("protected-route-context") || n.startsWith("protected-acceptance-context")));
  const accepted = JSON.parse(await readFile(metadata.receipt.evidence, "utf8"));
  assert.equal(accepted.verifiedIntegrated.sha, routed.join.sha);
  assert.equal(accepted.acceptanceContext.current.join.sha, "d".repeat(40), "an advanced join must not relabel the old integrated receipt");
  console.log(`PASS paired controller preservation${realArtifacts ? " backed by real immutable projection artifacts" : " (offline differentiated fixtures)"}: matching roles, attributed chain route, integrated-only negative, tool failure, foreign drift, metadata-only movement and labelled later join`);
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
  for (const phase of ["identity", "credentials"]) {
    ctx = context({ ...childInput, phase }, { gateFailure: true });
    assert.equal((await sliceDefinition.run(ctx)).receipt.phase, phase);
    const baselines = JSON.parse(await readFile(`${ctx.inputs.root}/baselines.json`, "utf8"));
    for (const [key, expectedSha] of [["supplementalBaseline", source.sha], ["supplementalIntegratedBaseline", source.join.sha]]) {
      const fixed = baselines[key];
      assert.equal(fixed.source.sha, expectedSha);
      assert.equal(fixed.phase, phase);
      const captures = ctx.observations.filter((e) => e.name === fixed.path.split("/").at(-1).replace(".json", ""));
      assert.equal(captures.length, 1, "Repairs must not recapture a supplemental baseline");
      for (const writer of ctx.observations.filter((e) => e.name.startsWith("implement-"))) {
        assert(writer.options.reads.includes(fixed.path) && writer.options.reads.includes(fixed.expression));
        assert(writer.options.prompt.includes(fixed.path) && writer.options.prompt.includes(expectedSha));
        assert(ctx.events.indexOf(captures[0].name) < ctx.events.indexOf(writer.name));
      }
    }
    for (const failure of ["janetteMailDiff", "janetteBehaviorDiff", "stibniteWorkerDiff"]) {
      ctx = context({ ...childInput, phase, max_repairs: 0 }, { [failure]: true });
      await assert.rejects(sliceDefinition.run(ctx), new RegExp(`Unverified ${phase}`));
    }
  }
  console.log("PASS identity/credentials controller: supplemental C0/J0 files reach writers and gates, stay fixed through repair, accept canonical identity mail only and reject other human/worker drift");

  ctx = context({ host: "stibnite", root, timeout: 1000, max_repairs: 2, reads: [] }, { confirm: false });
  await assert.rejects(migrationDefinition.run(ctx), /Provisioning\/identity verification incomplete/);
  assert(!ctx.events.some((n) => n.startsWith("activate-") || n.startsWith("enable-")));
  for (const [host, phase] of [["magnetite", "credentials"], ["pyrite", "magnetite"], ["stibnite", "pyrite"]]) {
    ctx = context({ host, root, timeout: 1000, max_repairs: 2, reads: [] }, { enabled: false, gateFailure: true });
    await assert.rejects(migrationDefinition.run(ctx), /Integrated preparation gates failed/);
    assert.equal(ctx.observations.find((e) => e.name === "prepare-gates").args.phase, phase);
    assert(!ctx.events.some((n) => n.startsWith("activate-") || n.startsWith("enable-")));
  }

  const tamperCtx = context(capabilities);
  const projectionOps = new Operations(tamperCtx, tamperCtx.inputs.root, 1000);
  const fixed = await sliceModule.projection(projectionOps, "protected-fixed", source);
  await assert.rejects(sliceModule.projection(projectionOps, "protected-recapture", operations.integrated(source)).then((candidate) => sliceModule.protectedComparison(projectionOps, "protected-cross-role", fixed, candidate.source)), /crosses source roles/);
  await writeFile(fixed.path, JSON.stringify(values.negative));
  await assert.rejects(sliceModule.protectedComparison(projectionOps, "protected-tampered", fixed, routed), /never recapture from candidate/);
  const collisionOps = new Operations(context(capabilities), projectionOps.root, 1000);
  await assert.rejects(sliceModule.projection(collisionOps, "protected-fixed", routed), /EEXIST/);
  Operations.prototype.command = originalCommand;
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
  await sourceRouteChecks({ Operations, operations, contracts, source, routed, root, compact });
  console.log("PASS controller: disabled deployment, child stop, gate/repair/success, contract fault without repair, current-state failure, pending login, topology fault, compact receipts and fresh DAG nodes");
}

async function sourceRouteChecks({ Operations, operations, contracts, source, routed, root, compact }) {
  const spec = { ...contracts.slice("capabilities"), paths: ["modules/owned.nix"] };
  const entry = (n) => `100644:${String(n).repeat(40)}`;
  const before = { "modules/owned.nix": entry(1), "modules/home/niri/default.nix": entry(3) };
  const after = { ...before, "modules/owned.nix": entry(2) };
  const beforeFile = `${root}/route-before.json`, afterFile = `${root}/route-after.json`;
  await writeFile(beforeFile, JSON.stringify(before), { mode: 0o600 });
  await writeFile(afterFile, JSON.stringify(after), { mode: 0o600 });
  function fixture(config = {}) {
    const commands = [];
    let inserted = false, squashed = false, bookmarked = false, captures = 0;
    const current = () => {
      const own = bookmarked ? { ...routed, parents: [source.sha] } : source;
      const parent = inserted ? { change: routed.change, sha: squashed ? routed.sha : "9".repeat(40) } : { change: source.change, sha: source.sha };
      const parents = source.join.parents.map((p) => p.change === source.change ? parent : config.foreignDuringRoute && squashed && p.change === source.join.parents[0].change ? { ...p, sha: "f".repeat(40) } : p);
      const join = { ...source.join, sha: squashed ? routed.join.sha : inserted ? "e".repeat(40) : source.join.sha, tree: squashed ? routed.join.tree : source.join.tree, parents };
      return { ...own, join, joinParents: parents.map((p) => p.change) };
    };
    const execute = async (_cwd, command) => {
      commands.push(command);
      const now = current();
      let stdout;
      if (command.includes("parents.map")) {
        captures++;
        const working = command.includes("-T 'change_id ++ \" \" ++ commit_id") ? `${source.workingCopy} ${(config.snapshotNote && captures % 2 === 0 ? "6" : "8").repeat(40)}` : source.workingCopy;
        stdout = `${working}\n${now.join.change} ${config.captureDrift && captures % 2 === 0 ? "7".repeat(40) : now.join.sha}\n` + now.join.parents.map((p) => `${p.change} ${p.sha}`).join("\n");
      } else if (command.startsWith("git show -s")) {
        const sha = /'([a-f0-9]{40})'$/.exec(command)?.[1];
        stdout = sha === now.join.sha ? `${now.join.tree} ${now.join.parents.map((p) => p.sha).join(" ")}` : sha === now.sha ? `${now.tree} ${now.parents.join(" ")}` : undefined;
      } else if (command.startsWith("git ls-tree")) {
        const sha = /git ls-tree -r -z '([^']+)'/.exec(command)?.[1];
        const full = command.endsWith("-- ");
        const tree = sha === source.sha ? { "modules/owned.nix": entry(config.overlap ? 0 : 1) } : sha === routed.sha ? { "modules/owned.nix": entry(2) } : sha === routed.join.sha ? after : before;
        stdout = Object.entries(tree).filter(([p]) => full || p === "modules/owned.nix").map(([p, value]) => { const [mode, hash] = value.split(":"); return `${mode} blob ${hash}\t${p}\0`; }).join("");
      } else if (command.includes("-T commit_id")) {
        stdout = command.includes("'@-'") ? now.join.sha : command.includes(routed.change) ? routed.sha : now.sha;
      } else if (command.includes("-T description")) stdout = "fixture existing tip";
      else if (command.includes("conflicts()") || command.includes("mutable()") || command === "jj --ignore-working-copy diff -r @ --name-only") stdout = "";
      else if (command.includes("-r 'parents(@-)'") ) stdout = now.joinParents.join("\n");
      else if (command.startsWith("jj --ignore-working-copy log")) {
        const rev = /-r '([^']+)'/.exec(command)?.[1];
        stdout = rev === "@" ? source.workingCopy : rev === "@-" ? now.join.change : rev === contracts.chain ? now.change : rev === `${source.change}+ & ancestors(@-)` ? config.unfinishedSplice ? routed.change : inserted ? routed.change : source.join.change : rev === `${source.change}+` ? `${source.join.change}\n${"p".repeat(32)}` : rev?.includes(" & ancestors(@-)") ? rev.split(" ")[0] : undefined;
      } else if (command.startsWith("jj new --no-edit")) { assert(command.includes(source.change)); inserted = true; stdout = ""; }
      else if (command.startsWith("jj squash")) { assert(command.includes(routed.change) && command.includes("--keep-emptied -- 'modules/owned.nix'")); squashed = true; stdout = ""; }
      else if (command.startsWith("jj bookmark set")) { assert(squashed); bookmarked = true; stdout = ""; }
      assert.notEqual(stdout, undefined, `Unexpected source/route command: ${command}`);
      return { stdout, stderr: "", command, exitCode: 0, state: "exited", terminationSignal: null, logPath: "fixture", tail: "" };
    };
    const port = { ui: { confirm: async () => true }, tool: async (_name, _args, callback) => { const value = await callback({ signal: new AbortController().signal }); compact(value); return { ok: true, value }; } };
    const ops = new Operations(port, root, 1000, execute);
    ops.filesystemTree = async () => ({ ...(config.clean ? before : after), ...(config.dirtyForeign ? { "modules/home/niri/default.nix": entry(4) } : {}), ...(config.notes ? { "docs/notes/unrelated.md": entry(5) } : {}) });
    return { ops, commands };
  }
  let f = fixture({ clean: true });
  assert.deepEqual(await f.ops.observeSource("fixture-chain-source"), source);
  assert.deepEqual(await f.ops.observeSource("fixture-integrated-source", "@-"), operations.integrated(source));
  assert(f.commands.every((c) => c.startsWith("jj --ignore-working-copy") || c.startsWith("git show -s")));
  f = fixture({ captureDrift: true });
  await assert.rejects(f.ops.observeSource("fixture-drifting-source"), /changed across observation boundary/);
  f = fixture({ snapshotNote: true, clean: true, notes: true });
  assert.deepEqual(await f.ops.observeSource("fixture-note-snapshot-source"), source, "snapshotting unrelated working notes must not fabricate source-context drift");
  for (const [config, reason] of [[{ overlap: true, clean: true }, /Foreign contributions overlap owned paths/], [{ dirtyForeign: true, clean: true }, /Unstored relevant foreign inputs/]]) {
    f = fixture(config);
    await assert.rejects(f.ops.snapshot("fixture-before", spec, source), reason);
    assert(!f.commands.some((c) => /^jj (new|squash|bookmark)/.test(c)));
  }
  f = fixture({ clean: true, notes: true });
  await f.ops.snapshot("fixture-notes-before", spec, source);
  for (const [config, reason] of [[{ overlap: true }, /Foreign contributions overlap owned paths/], [{ dirtyForeign: true }, /Unstored relevant foreign inputs/]]) {
    f = fixture(config);
    await assert.rejects(f.ops.route("fixture-rejected-route", spec, beforeFile, afterFile, source), reason);
    assert(!f.commands.some((c) => /^jj (new|squash|bookmark)/.test(c)));
  }
  f = fixture();
  const context = await f.ops.routeContext("fixture-pre-route-source", spec, beforeFile, afterFile, source);
  const result = await f.ops.route("fixture-route", spec, beforeFile, afterFile, source, context);
  assert.equal(result.sha, routed.sha);
  assert.equal(result.join.sha, routed.join.sha);
  assert.deepEqual(operations.foreignParents(result), operations.foreignParents(source));
  assert.deepEqual(f.commands.filter((c) => /^jj (new|squash|bookmark)/.test(c)).map((c) => c.split(" ")[1]), ["new", "squash", "bookmark"]);
  assert.equal(f.commands.filter((c) => c.includes(`-r '${source.change}+ & ancestors(@-)'`)).length, 2, "both child lookups exclude off-join peers");
  f = fixture({ unfinishedSplice: true });
  await assert.rejects(f.ops.route("fixture-unfinished-route", spec, beforeFile, afterFile, source), /Unfinished splice requires explicit reconciliation/);
  assert(!f.commands.some((c) => /^jj (new|squash|bookmark)/.test(c)));
  f = fixture({ foreignDuringRoute: true });
  await assert.rejects(f.ops.route("fixture-foreign-route", spec, beforeFile, afterFile, source), /Foreign-parent provenance changed during routing/);
  console.log("PASS actual source/snapshot/route callbacks: immutable Git parent/tree binding, capture drift, owned overlap, relevant unstored input rejection, dirty-note tolerance, explicit chain splice and foreign-parent continuity");
}
