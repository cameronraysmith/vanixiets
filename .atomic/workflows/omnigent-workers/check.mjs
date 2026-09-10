import assert from "node:assert/strict";
import { readFileSync, realpathSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, resolve, join } from "node:path";
import { pathToFileURL } from "node:url";
import { runInNewContext } from "node:vm";
const require = createRequire(import.meta.url);
const atomic = resolve(dirname(realpathSync(execFileSync("bash", ["-c", "command -v atomic"], { encoding: "utf8" }).trim())), "../lib/node_modules/@bastani/atomic");
const compiler = execFileSync("bash", ["-c", "printf '%s\\n' /nix/store/*typescript*/lib/node_modules/typescript/lib/typescript.js | head -1"], { encoding: "utf8" }).trim();
const ts = require(compiler);
const root = ".atomic/workflows/omnigent-workers";
const files = [`${root}.ts`, ...["contract", "operations", "gates", "slice", "migration"].map((n) => `${root}/${n}.ts`)];
const options = { noEmit: true, strict: true, module: ts.ModuleKind.NodeNext, moduleResolution: ts.ModuleResolutionKind.NodeNext, target: ts.ScriptTarget.ES2022, skipLibCheck: true, typeRoots: [resolve(atomic, "node_modules/@types")], types: ["node"], paths: { "@bastani/atomic/workflows": [resolve(atomic, "dist/builtin/workflows/src/authoring.d.ts")], typebox: [resolve(atomic, "node_modules/typebox/build/index.d.mts")], "typebox/value": [resolve(atomic, "node_modules/typebox/build/value/index.d.mts")] } };
const diagnostics = ts.getPreEmitDiagnostics(ts.createProgram(files, options));
if (diagnostics.length) { console.error(ts.formatDiagnosticsWithColorAndContext(diagnostics, { getCanonicalFileName: (f) => f, getCurrentDirectory: () => process.cwd(), getNewLine: () => "\n" })); process.exit(1); }
console.log("PASS strict TypeScript against installed Atomic and TypeBox");
const urls = new Map();
function moduleUrl(file) {
  const path = resolve(file);
  if (urls.has(path)) return urls.get(path);
  let code = ts.transpileModule(readFileSync(path, "utf8"), { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText;
  code = code.replace(/from "([^"]+)"/g, (whole, name) => {
    if (name === "@bastani/atomic/workflows") return `from ${JSON.stringify(pathToFileURL(join(atomic, "dist/builtin/workflows/src/index.js")).href)}`;
    if (name === "typebox" || name === "typebox/value") return `from ${JSON.stringify(pathToFileURL(join(atomic, "node_modules/typebox", name === "typebox" ? "build/index.mjs" : "build/value/index.mjs")).href)}`;
    if (name.startsWith(".")) return `from ${JSON.stringify(moduleUrl(resolve(dirname(path), name.replace(/\.js$/, ".ts"))))}`;
    return whole;
  });
  const url = `data:text/javascript;base64,${Buffer.from(code).toString("base64")}`;
  urls.set(path, url); return url;
}
const contracts = await import(moduleUrl(`${root}/contract.ts`));
const operations = await import(moduleUrl(`${root}/operations.ts`));
const gates = await import(moduleUrl(`${root}/gates.ts`));
const migration = await import(moduleUrl(`${root}/migration.ts`));
const definition = (await import(moduleUrl(`${root}.ts`))).default;
// Evaluate only the installed pure factory, never the extension's registration code.
const catalogSource = ts.createSourceFile("catalog.mjs", readFileSync(join(atomic, "dist/builtin/workflows/src/extension/index.bundle.mjs"), "utf8"), ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
const catalogFactory = catalogSource.statements.find((n) => ts.isFunctionDeclaration(n) && n.name?.text === "workflowModelCatalogFromContext");
assert(catalogFactory, "Installed Atomic catalog factory must be inspectable");
const makeCatalog = runInNewContext(`(${catalogFactory.getText(catalogSource)})`);
const selectedModel = { provider: "openai-codex", id: "gpt-6-astra" };
const models = makeCatalog({ model: selectedModel });
assert.equal(models.currentModel, selectedModel);
assert.equal(await operations.currentModel({ models }), contracts.model);
await assert.rejects(operations.currentModel({ models: makeCatalog({ modelRegistry: { getAvailable: () => [] } }) }), /current-model metadata missing/);
for (const currentModel of [null, {}, { provider: "openai-codex" }, { provider: 1, id: "gpt-6-astra" }, { provider: "openai-codex", id: "" }, "", "gpt-6-astra", []]) {
  await assert.rejects(operations.currentModel({ models: { currentModel } }), /current-model metadata malformed/);
}
for (const [catalog, reason] of [
  [makeCatalog({ model: { provider: "fixture", id: "gpt-6-astra" } }), /Configured current model is not/],
  [makeCatalog({ model: { provider: "openai-codex", id: "foreign" } }), /Configured current model is not/],
  [makeCatalog({}), /catalog unavailable/],
  [makeCatalog({ modelRegistry: { getAvailable: () => [] } }), /current-model metadata missing/],
  [{ currentModel: { fullId: contracts.model } }, /current-model metadata malformed/],
]) {
  let effects = 0;
  const ctx = { cwd: contracts.repository, models: catalog, task: async () => { effects++; }, tool: async () => { effects++; } };
  await assert.rejects(operations.currentModel(ctx), reason);
  await assert.rejects(definition.run(ctx), reason);
  await assert.rejects(new operations.Operations(ctx, "fixture", 1000).stage("fixture", {}), reason);
  assert.equal(effects, 0);
}
assert.equal(await operations.currentModel({ models: { currentModel: `${contracts.model}:high` } }), `${contracts.model}:high`);
for (const catalog of [undefined, null, false, "invalid"]) await assert.rejects(operations.currentModel({ models: catalog }), /catalog unavailable/);
const sdkSource = ts.createSourceFile("sdk.js", readFileSync(join(atomic, "dist/builtin/workflows/src/index.js"), "utf8"), ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
const reasoning = ["effectiveCandidateReasoning", "modelAttemptReasoning"].map((name) => {
  const fn = sdkSource.statements.find((n) => ts.isFunctionDeclaration(n) && n.name?.text === name);
  assert(fn, `Installed Atomic ${name} must be inspectable`);
  return fn.getText(sdkSource);
}).join("\n");
const controller = sdkSource.statements.find((n) => ts.isClassDeclaration(n) && n.name?.text === "StageSessionController");
const record = controller?.members.find((n) => ts.isMethodDeclaration(n) && n.name?.getText(sdkSource) === "recordSuccessfulAttempt");
assert(record, "Installed Atomic result metadata writer must be inspectable");
const recordSuccess = runInNewContext(`${reasoning}\n({ ${record.getText(sdkSource)} }).recordSuccessfulAttempt`);
function modelResult(candidate = { id: contracts.model }, options = contracts.modelOptions) {
  const state = { modelAttempts: [], effectiveStageOptions: options, pendingFallbackWarnings: [], takeAttemptUsage: () => undefined, notifySuccessfulModelFallbackMeta: () => {} };
  recordSuccess.call(state, candidate);
  return { modelAttempts: state.modelAttempts };
}
for (const candidate of [{ id: contracts.model, reasoningLevel: "high" }, { id: contracts.model }]) {
  assert.equal(operations.modelEvidence(modelResult(candidate)).attempts[0].thinking, "high");
}
assert.throws(() => operations.modelEvidence(modelResult({ id: "fixture/foreign" })), /off-policy model/);
assert.throws(() => operations.modelEvidence(modelResult({ id: contracts.model, reasoningLevel: "medium" })), /off-policy thinking/);
assert.throws(() => operations.modelEvidence(modelResult({ id: contracts.model }, {})), /lacks observed high-thinking metadata/);
console.log("PASS installed catalog factory object identity, fail-closed preflight/stage guards and SDK-created primary/compatibility high attempt metadata");
assert.equal(definition.name, "omnigent-workers");
assert.equal(typeof definition.run, "function");
assert.throws(() => contracts.parse(contracts.Review, { kind: "approved", evidence: [] }));
assert.throws(() => contracts.parse(contracts.Review, { kind: "approved", evidence: ["receipt"], bypass: true }));
assert.throws(() => contracts.parse(contracts.StageReport, { kind: "done" }));
assert.deepEqual(contracts.parse(contracts.Review, { kind: "repair", findings: ["wrong identity"] }).kind, "repair");
assert.equal(await operations.currentModel({ models: { currentModel: contracts.model } }), contracts.model);
await assert.rejects(operations.currentModel({ models: { currentModel: "fixture/foreign" } }));
await assert.rejects(operations.currentModel({}));
assert.throws(() => operations.modelEvidence({ modelAttempts: [{ model: "fixture/foreign", reasoningLevel: "high", success: true }] }));
assert.throws(() => operations.modelEvidence({ modelAttempts: [{ model: contracts.model, success: true }] }));
assert.throws(() => operations.modelEvidence({ modelAttempts: [{ model: contracts.model, reasoningLevel: "medium", success: true }] }));
assert.equal(operations.modelEvidence({ modelAttempts: [{ model: contracts.model, reasoningLevel: "high", success: false }, { model: contracts.model, reasoningLevel: "high", success: true }] }).attempts.length, 2);
console.log("PASS closed schema rejection and requested/observed same-model high policy");
if (process.argv.includes("--model-only")) process.exit(0);
const id = "k".repeat(32), sha = "a".repeat(40);
const source = { change: id, workingCopy: "l".repeat(32), joinParents: [id, "m".repeat(32)], sha, source: `git+file:///fixture?rev=${sha}` };
assert.throws(() => operations.routeCommand(id, ["../outside"], ["."]));
assert.throws(() => operations.routeCommand(id, ["modules/foreign"], ["modules/owned"]));
assert.match(operations.routeCommand(id, ["modules/owned/test.nix"], ["modules/owned"]), /--use-destination-message --keep-emptied --/);
assert.deepEqual(operations.allowedChanges({ owned: "a", foreign: "a" }, { owned: "b", foreign: "b" }, ["owned"]), { owned: ["owned"], foreign: ["foreign"] });
assert.deepEqual(gates.expectedEnabled("inventory"), []);
assert.deepEqual(gates.expectedEnabled("pyrite"), ["magnetite", "pyrite"]);
assert.deepEqual(gates.expectedEnabled("closure"), contracts.hosts);
for (const phase of contracts.phases) {
  for (const command of gates.gateCommands(phase, source)) assert(command.includes(source.source));
}
console.log("PASS scope/squash constraints and pinned gate targets");
execFileSync("python3", ["-c", `import ast; ast.parse(open('${root}/live.py').read()); print('PASS Python parse')`], { stdio: "inherit" });
console.log("PASS definition import and shape (no registry reload, models, VCS or host effects)");
const sliceDefinition = (await import(moduleUrl(`${root}/slice.ts`))).default;
const compact = (await import(moduleUrl(".atomic/workflows/bump/tools.ts"))).assertCompactCheckpoint;
await (await import("./controller-checks.mjs")).controllerChecks({ definition, sliceDefinition, migrationDefinition: migration.default, Operations: operations.Operations, contracts, source, compact, models, modelResult });
for (const expression of [gates.baselineExpr(source.source), gates.stateExpr(source.source, ["magnetite"]), gates.workersExpr(source.source, "stibnite")]) {
  execFileSync("nix-instantiate", ["--parse", "--expr", expression], { stdio: ["ignore", "pipe", "pipe"] });
}
for (const host of contracts.hosts) execFileSync("bash", ["-n", "-c", migration.hostCommand(host, "readlink /run/current-system")]);
console.log("PASS generated Nix parsing and shell syntax (no evaluation or host execution)");
execFileSync("python3", ["-B", `${root}/live-checks.py`], { stdio: "inherit" });
await (await import("./regression-checks.mjs")).regressionChecks({ definition, sliceDefinition, migrationDefinition: migration.default, migration, contracts, operations, gates, source, models });
