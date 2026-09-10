import assert from "node:assert/strict";
import { mkdir, writeFile, readFile, chmod, symlink, unlink } from "node:fs/promises";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { humanChecks } from "./human-checks.mjs";

export async function regressionChecks({ definition, sliceDefinition, migrationDefinition, migration, contracts, operations, gates, source, models }, only) {
  if (!only || only === "F1") await humanChecks(gates);
  const ctx = {
    cwd: contracts.repository, inputs: { start_at: 4, deploy: false, max_repairs: 2, build_timeout_minutes: 1 }, models,
    tool: async (name) => name === "allocate-evidence" ? ".atomic/workflows/runs/fixture" : { ok: true, value: { receipt: [], evidence: source } },
    workflow: async () => { throw Error("unexpected child"); }, exit: (value) => value,
  };
  if (!only || only === "F4") {
    for (const start_at of [4, 5, 6]) {
      const result = await definition.run({ ...ctx, inputs: { ...ctx.inputs, start_at } });
      assert.equal(result.status, "blocked", `F4 start_at=${start_at} must withhold readiness without evidence`);
      assert.match(result.reason, /implementation evidence/i);
    }
    console.log("PASS F4 actual definition: 4/5/6 without deployment withhold readiness");
  }
  if (!only || only === "F6") {
    const host = { host: "stibnite", sha: source.sha, system: "/nix/store/fixture", evidence: "fixture", acceptance: "human_attested" };
    assert.deepEqual(contracts.parse(definition.outputs.hosts.items, host), host);
    assert.throws(() => contracts.parse(definition.outputs.hosts.items, { ...host, unexpected: true }), /Malformed/);
    console.log("PASS F6 actual nested host schema rejects unknown properties");
  }
  if (!only || only === "F3") {
    const desired = "/nix/store/" + "a".repeat(32) + "-system", old = "/nix/store/old-system";
    for (const [profileNew, activeNew] of [[false, false], [true, false], [false, true], [true, true]]) {
      let profile = profileNew ? desired : old, active = activeNew ? desired : old;
      const commands = [];
      const ops = { command: async (command) => {
        commands.push(command);
        if (command === "readlink /run/current-system") return active;
        if (command === "cat /nix/var/nix/profiles/system/systemConfig") return profile;
        if (command.includes("nix-env") && command.includes("--set")) { assert(command.includes(desired)); profile = desired; return ""; }
        if (command.includes("sudo -n") && command.includes("activate")) { assert.equal(profile, desired, "persistent profile must precede activation"); active = desired; return ""; }
        throw Error(`Unexpected lifecycle command: ${command}`);
      } };
      const result = await migration.reconcileActivation(ops, "stibnite", desired, source, new AbortController().signal);
      assert.equal(profile, desired); assert.equal(active, desired);
      assert.equal(result.kind, profileNew && activeNew ? "already-activated" : "activated");
      assert.equal(commands.filter((c) => c.includes("--set")).length, profileNew ? 0 : 1);
      const activates = commands.filter((c) => c.includes("sudo -n") && c.includes("activate"));
      assert.equal(activates.length, activeNew ? 0 : 1);
      for (const command of activates) assert(command.includes(`${desired}/sw/bin/darwin-rebuild`) && command.endsWith(" activate"));
      for (const command of commands) execFileSync("bash", ["-n", "-c", command]);
    }
    for (const failAt of ["profile", "activate"]) {
      let profile = old;
      const failure = Error(`failed ${failAt}`);
      const ops = { command: async (command) => {
        if (command === "readlink /run/current-system") return old;
        if (command === "cat /nix/var/nix/profiles/system/systemConfig") return profile;
        if (command.includes("--set")) { if (failAt === "profile") throw failure; profile = desired; return ""; }
        throw failure;
      } };
      await assert.rejects(migration.reconcileActivation(ops, "stibnite", desired, source, new AbortController().signal), (error) => error === failure);
    }
    console.log("PASS F3 persistent/active four-state reconciliation and failed profile/activation");
  }
  if (!only || only === "F2") {
    const root = `.atomic/workflows/runs/omnigent-workers-attribution-${Date.now()}`;
    await mkdir(root, { recursive: true });
    const owned = `${root}/owned.nix`, foreign = `${root}/foreign.nix`, link = `${root}/link`;
    const bytes = "{ behavior = true; }\n";
    await writeFile(owned, bytes); await writeFile(foreign, "foreign edit\n"); await symlink("original", link);
    const oid = (text) => createHash("sha1").update(`blob ${Buffer.byteLength(text)}\0`).update(text).digest("hex");
    const spec = { ...contracts.slice("linux"), paths: [owned, link] };
    const commands = [];
    const execute = async (_cwd, command) => {
      commands.push(command);
      let stdout;
      if (command === "jj --ignore-working-copy diff -r @ --name-only") stdout = "";
      else if (command.includes("commit_id")) stdout = source.sha;
      else if (command.startsWith("git ls-tree")) stdout = `100644 blob ${oid(bytes)}\t${owned}\0` + `120000 blob ${oid("original")}\t${link}\0` + (command.endsWith("-- ") ? `100644 blob ${oid("foreign edit\n")}\t${foreign}\0` : "");
      else if (command.startsWith("git ls-files")) stdout = `${owned}\0${foreign}\0${link}\0`;
      else throw Error(`Unexpected command (no mutations allowed): ${command}`);
      return { stdout, stderr: "", exitCode: 0, command, state: "exited", terminationSignal: null, logPath: "fixture", tail: "" };
    };
    const port = { tool: async (_name, _args, callback) => ({ ok: true, value: await callback({ signal: new AbortController().signal }) }) };
    const ops = new operations.Operations(port, root, 1000, execute);
    await writeFile(owned, bytes + "# pre-existing foreign edit\n");
    await assert.rejects(ops.assertCleanScope(spec), /Pre-existing in-scope/, "F2 stored jj diff empty must not authorize filesystem delta");
    const contaminatedBefore = await ops.snapshot("contaminated-before");
    await writeFile(owned, bytes + "# pre-existing foreign edit\n# writer edit\n");
    const contaminatedAfter = await ops.snapshot("contaminated-after");
    ops.healthy = async () => source.workingCopy;
    await assert.rejects(ops.route("contaminated-route", spec, contaminatedBefore, contaminatedAfter, source), /Owned baseline changed/);
    await writeFile(owned, bytes); await chmod(owned, 0o755);
    await assert.rejects(ops.assertCleanScope(spec), /Pre-existing in-scope/);
    await chmod(owned, 0o644);
    await unlink(link); await symlink("changed-target", link);
    await assert.rejects(ops.assertCleanScope(spec), /Pre-existing in-scope/);
    await unlink(link); await symlink("original", link);
    const cleanBefore = await ops.snapshot("clean-before", spec);
    await writeFile(owned, bytes + "# writer edit\n");
    const writerAfter = await ops.snapshot("writer-after");
    await writeFile(owned, bytes + "# concurrent edit after observation\n");
    await assert.rejects(ops.route("drift-route", spec, cleanBefore, writerAfter, source), /Owned bytes changed/);
    await writeFile(owned, bytes);
    await ops.assertCleanScope(spec);
    assert.equal(await readFile(foreign, "utf8"), "foreign edit\n");
    assert(commands.every((c) => c.startsWith("jj --ignore-working-copy") || c.startsWith("git ls-")));
    await writeFile(owned, bytes + "# writer edit\n");
    let simulatedSquashes = 0;
    const routeOps = new operations.Operations(port, root, 1000, async (cwd, command, signal) => {
      const observation = (stdout) => ({ stdout, stderr: "", exitCode: 0, command, state: "exited", terminationSignal: null, logPath: "fixture", tail: "" });
      if (command.includes("-T description")) return observation(`${spec.title}\n\nOmnigent-Workers-Step: ${root}/${spec.phase}`);
      if (command.startsWith("jj squash")) { simulatedSquashes++; return observation(""); }
      return execute(cwd, command, signal);
    });
    routeOps.healthy = async () => source.workingCopy;
    routeOps.id = async () => source.change;
    routeOps.source = async () => source;
    await assert.rejects(routeOps.route("wrong-destination", spec, cleanBefore, writerAfter, source), /Attributed destination differs/);
    assert.equal(simulatedSquashes, 1, "actual route callback must read back the attributed destination, not just the filesystem");
    console.log("PASS F2 actual clean/snapshot/route callbacks: pre-existing bytes/mode/link edits and later drift rejected before routing; wrong destination rejected after simulated squash; foreign file preserved");
  }
  if (!only || only === "F5") {
    const controls = [new DOMException("fixture cancellation", "AbortError"), { [Symbol("atomic-workflows.workflow-exit-signal")]: true, status: "blocked", scope: {} }, Object.assign(Error("parent exited"), { [Symbol("atomic-workflows.parent-workflow-exit-abort")]: true })];
    for (const control of controls) {
      const controller = new AbortController(); controller.abort(control);
      for (const [definitionToRun, inputs, boundary] of [
        [definition, { ...ctx.inputs, start_at: 0 }, "preflight"],
        [sliceDefinition, { phase: "linux", root: ".atomic/workflows/runs/fixture", timeout: 1000, max_repairs: 2, verify_only: false, reads: [] }, "baseline-owned"],
        [migrationDefinition, { host: "stibnite", root: ".atomic/workflows/runs/fixture", timeout: 1000, max_repairs: 2, reads: [] }, "prepare-join"],
      ]) {
        let exits = 0;
        const tool = async (name, _args, callback) => name === boundary ? callback({ signal: controller.signal }) : ctx.tool(name);
        await assert.rejects(definitionToRun.run({ ...ctx, inputs, tool, exit: () => { exits++; return {}; } }), (error) => error === control);
        assert.equal(exits, 0);
      }
      let exits = 0;
      const nested = { ...ctx, inputs: { ...ctx.inputs, deploy: true }, exit: () => { exits++; return {}; }, workflow: async (_child, options) => migrationDefinition.run({ ...ctx, inputs: options.inputs, tool: (_name, _args, callback) => callback({ signal: controller.signal }) }) };
      await assert.rejects(definition.run(nested), (error) => error === control);
      assert.equal(exits, 0);
    }
    const ordinary = await definition.run({ ...ctx, tool: async (name) => { if (name === "preflight") throw Error("ordinary failure"); return ctx.tool(name); } });
    assert.equal(ordinary.status, "blocked"); assert.match(ordinary.reason, /infrastructure: Error: ordinary failure/);
    let exitCalls = 0;
    const exitRail = controls[1];
    await assert.rejects(definition.run({ ...ctx, inputs: { ...ctx.inputs, start_at: 0 }, workflow: async () => ({ exited: true, exitReason: "child blocked" }), exit: () => { exitCalls++; throw exitRail; } }), (error) => error === exitRail);
    assert.equal(exitCalls, 1, "SDK ctx.exit must not be caught and called a second time");
    console.log("PASS F5 actual tool callbacks and nested root/migration propagation preserve AbortError and SDK exit rails");
  }
}
