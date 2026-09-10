import assert from "node:assert/strict";
import { readFileSync, realpathSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { dirname, resolve, join } from "node:path";
import { pathToFileURL } from "node:url";
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
await (await import("./controller-checks.mjs")).controllerChecks({ definition, sliceDefinition, migrationDefinition: migration.default, Operations: operations.Operations, contracts, source, compact });
for (const expression of [gates.baselineExpr(source.source), gates.stateExpr(source.source, ["magnetite"]), gates.workersExpr(source.source, "stibnite")]) {
  execFileSync("nix-instantiate", ["--parse", "--expr", expression], { stdio: ["ignore", "pipe", "pipe"] });
}
for (const host of contracts.hosts) execFileSync("bash", ["-n", "-c", migration.hostCommand(host, "readlink /run/current-system")]);
console.log("PASS generated Nix parsing and shell syntax (no evaluation or host execution)");
execFileSync("python3", ["-B", `${root}/live-checks.py`], { stdio: "inherit" });
await (await import("./regression-checks.mjs")).regressionChecks({ definition, sliceDefinition, migrationDefinition: migration.default, migration, contracts, operations, gates, source });
