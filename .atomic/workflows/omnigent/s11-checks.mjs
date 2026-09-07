import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

export function runToolingChecks({ contract, additions, tooling }) {
  assert.equal(contract.slices[11].title, "runtime-tooling");
  const names = ["claude-code", "atomic", "codex", "pi", "omp", "bun", "nodejs_22", "python3", "tmux", "git", "uv", "bash", "which", "direnv", "nix", "gh"];
  const bins = names.map((name) => `/fixture/${name}/bin`);
  const suffix = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"];
  const packages = Object.fromEntries(names.map((name) => [name, `/fixture/${name}`]));
  const model = { packages: { "aarch64-darwin": packages }, inputs: { "llm-agents": { packages: { "aarch64-darwin": packages } } } };
  for (const [label, paths, executable, extras, expected] of [
    ["complete", [...bins, ...suffix], "/fixture/omnigent/bin/omnigent", [], true],
    ...names.map((name) => [`missing ${name}`, [...bins.filter((bin) => bin !== `/fixture/${name}/bin`), ...suffix], "/fixture/omnigent/bin/omnigent", [], false]),
    ["reordered", [...bins].reverse().concat(suffix), "/fixture/omnigent/bin/omnigent", [], false],
    ["wrong executable", [...bins, ...suffix], "/fixture/wrong", [], false],
    ["extra packages", [...bins, ...suffix], "/fixture/omnigent/bin/omnigent", ["extra"], false],
    ["extra path", [...bins, "/ambient", ...suffix], "/fixture/omnigent/bin/omnigent", [], false],
    ["missing suffix", bins, "/fixture/omnigent/bin/omnigent", [], false],
  ]) {
    const prefix = `let f = builtins.fromJSON ${JSON.stringify(JSON.stringify(model))};
      p = (builtins.fromJSON ${JSON.stringify(JSON.stringify(packages))}) // { lib = {
        getExe = x: x + "/bin/omnigent";
        makeBinPath = xs: builtins.concatStringsSep ":" (map (x: x + "/bin") xs);
      }; };
      c.services.omnigent-host = { extraPackages = builtins.fromJSON ${JSON.stringify(JSON.stringify(extras))}; package = "/fixture/omnigent"; };
      h.launchd.agents.omnigent-host.config.ProgramArguments = [ ${JSON.stringify(executable)} ];
      path = ${JSON.stringify(paths.join(":"))};`;
    const expr = tooling.toolingDarwinPathExpr.replace(`${additions.runtimeFixture} ${additions.hostBinding("stibnite")}`, prefix);
    const result = execFileSync("nix", ["eval", "--json", "--expr", expr], { encoding: "utf8" });
    assert.equal(JSON.parse(result), expected, label);
    console.log(`PASS S11 ordered PATH control ${label}: ${result.trim()}`);
  }
  for (const gate of contract.slices[11].gates) {
    if (gate.kind === "NixEval") execFileSync("nix-instantiate", ["--parse", "--expr", gate.target.expr], { stdio: "pipe" });
    if (gate.kind === "Command" && gate.argv.includes("--binding-expr")) execFileSync("nix-instantiate", ["--parse", "--expr", gate.argv[gate.argv.indexOf("--binding-expr") + 1]], { stdio: "pipe" });
  }
}

export async function runToolingEmpirical({ contract, tooling }) {
  const cwd = process.cwd();
  const jj = (rev) => execFileSync("jj", ["--ignore-working-copy", "log", "-r", rev, "--no-graph", "-T", "commit_id"], { encoding: "utf8" }).trim();
  const joinSha = jj("@-");
  const tipSha = jj("omnigent-magnetite");
  const source = (sha) => `git+file://${cwd}?rev=${sha}`;
  const candidate = realpathSync(mkdtempSync(join(tmpdir(), "omnigent-s11-")));
  const archive = execFileSync("git", ["archive", joinSha], { maxBuffer: 128 * 1024 * 1024 });
  execFileSync("tar", ["-xf", "-", "-C", candidate], { input: archive });
  for (const file of contract.slices[11].allowedPaths) writeFileSync(join(candidate, file), readFileSync(resolve(file)));
  const candidateSource = `path:${candidate}`;
  console.log(JSON.stringify({ joinSha, tipSha, candidateSource, provenance: "git archive of resolved join plus only S11 allowed-path working-copy files; not a routed join" }));
  const evaluate = (label, expr, ref, expected) => {
    const command = ["eval", "--impure", "--json", "--expr", expr.replaceAll("__OMNIGENT_SOURCE__", ref)];
    const result = spawnSync("nix", command, { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
    console.log(JSON.stringify({ label, command: ["nix", ...command], ...result }));
    assert.equal(result.status, 0, result.stderr);
    const value = JSON.parse(result.stdout);
    assert.deepEqual(value, expected, label);
  };
  evaluate("S11:0 rejects current tip", tooling.toolingDarwinPathExpr, source(tipSha), false);
  evaluate("S11:0 rejects current join", tooling.toolingDarwinPathExpr, source(joinSha), false);
  for (const [slice, index] of [[7, 10], [8, 22], [10, 8]]) evaluate(`superseded S${slice}:${index}`, contract.slices[slice].gates[index].target.expr, candidateSource, false);
  evaluate("S11:0 candidate carrier", tooling.toolingDarwinPathExpr, candidateSource, true);
  for (const index of [0, 4]) evaluate(`retained Linux membership S10:${index}`, contract.slices[10].gates[index].target.expr, candidateSource, true);
  const structural = (root, toolingFlag) => spawnSync("python3", [".atomic/workflows/omnigent/runtime-contract-checks.py", root, ...(toolingFlag ? ["--runtime-tooling"] : [])], { encoding: "utf8" });
  const baseline = realpathSync(mkdtempSync(join(tmpdir(), "omnigent-s11-tip-")));
  for (const file of ["modules/home/ai/omnigent/runtime-packages.nix", "modules/nixos/omnigent-host.nix", "modules/darwin/omnigent-host.nix"]) {
    mkdirSync(resolve(baseline, file, ".."), { recursive: true });
    writeFileSync(join(baseline, file), execFileSync("git", ["show", `${tipSha}:${file}`]));
  }
  const tipOldStructural = structural(baseline, false);
  const tipNewStructural = structural(baseline, true);
  console.log(JSON.stringify({ tipOldStructural, tipNewStructural }));
  assert.equal(tipOldStructural.status, 0);
  assert.notEqual(tipNewStructural.status, 0);
  const oldStructural = structural(candidate, false);
  const newStructural = structural(candidate, true);
  console.log(JSON.stringify({ oldStructural, newStructural }));
  assert.notEqual(oldStructural.status, 0);
  assert.equal(newStructural.status, 0);
  for (const gate of contract.slices[11].gates.filter((gate) => gate.kind === "Command" && gate.argv.includes("--binding-expr"))) {
    const argv = gate.argv.map((arg) => arg.replaceAll("__OMNIGENT_SOURCE__", candidateSource).replaceAll("__OMNIGENT_PRIMARY__", cwd));
    const result = spawnSync(argv[0], argv.slice(1), { encoding: "utf8", maxBuffer: 16 * 1024 * 1024 });
    console.log(JSON.stringify({ command: argv, ...result }));
    assert.equal(result.status, 0, result.stderr);
  }
  console.log("S11 empirical candidate witnesses and executable-resolution gates passed; routed-join witnesses pending routing");
}
