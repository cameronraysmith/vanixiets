import { IMPL, type Gate, type Slice } from "./types.js";
import { runtimeFixture, hostBinding, runtimePathExpr, runtimePackagesFile } from "./s9-s10.js";

const eq = (expr: string): Gate => ({ kind: "NixEval", target: { kind: "Expr", expr }, expect: { kind: "Equal", value: true } });
export const toolingDarwinPathExpr = runtimePathExpr("stibnite").replace("required = [ p.bash p.which p.direnv p.nix ];", "required = [ p.bash p.which p.direnv p.nix p.gh ];");
export const toolingBindingExpr = (name: string, server = false) => `${runtimeFixture} ${hostBinding(name)}
unit = c.systemd.services.omnigent;
linux = p.stdenv.hostPlatform.isLinux;
packages = ${server ? "unit.path" : "f.lib.omnigentRuntimePackages p"};
expected = ${server ? '{ lsof = "${p.lib.getBin p.lsof}/bin/lsof"; }' : '{ gh = "${p.lib.getBin p.gh}/bin/gh"; } // (if linux then { ps = "${p.lib.getBin p.procps}/bin/ps"; lsof = "${p.lib.getBin p.lsof}/bin/lsof"; } else { ps = "/bin/ps"; lsof = "/usr/sbin/lsof"; })'};
in assert c.services.omnigent-host.extraPackages == [];
${server ? "assert builtins.elem p.lsof unit.path; assert builtins.all (x: x == p.lsof || !(builtins.elem x unit.path)) (f.lib.omnigentRuntimePackages p); assert !(builtins.elem c.services.omnigent-host.package unit.path);" : ""}
{ path = ${server ? "unit.environment.PATH" : "path"}; inherit expected;
  version = f.packages.\${p.stdenv.hostPlatform.system}.omnigent.version;
  outputs = map (x: toString (p.lib.getBin x)) packages;
}`;
const probe = (name: string, server = false): Gate => ({
  kind: "Command", argv: ["python3", "__OMNIGENT_PRIMARY__/.atomic/workflows/omnigent/tooling-resolution.py", "--binding-expr", toolingBindingExpr(name, server), "--host", name, ...(server ? ["--server"] : [])], expectExitZero: true, expectStdoutIncludes: ["runtime-tooling-resolution-ok"],
});
export function toolingSlice(plan: string): Slice {
  return {
    id: 11, title: "runtime-tooling", implModel: IMPL,
    allowedPaths: [runtimePackagesFile, "modules/nixos/omnigent.nix", plan],
    reviewReads: [plan, ".atomic/workflows/omnigent/tooling-manifest.json"],
    objective: "Add gh to the shared runner runtime after nix, and procps/lsof after bubblewrap in its Linux-only list. Add only lsof to the server unit path, not the runner profile. Preserve existing user-scoped OAuth state, all environment and lifecycle settings. Document the audited 0.13.0 executable boundary and unsupported optional UI vendor installation. Do not edit historical gates, credentials, extensions or unrelated services.",
    acceptance: ["Complete ordered Darwin PATH retains empty-extras and configured executable identity with gh added.", "Both shared consumers retain the reviewed common/Linux partition before extras and no account literals.", "Reviewed executable manifest resolves under all three runner PATHs and the separate server PATH; gh uses the existing user OAuth location without copying secrets.", "Optional UI vendor installs remain unsupported; dynamic executable names require a new audit on version upgrades."],
    gates: [
      eq(toolingDarwinPathExpr),
      { kind: "Command", argv: ["python3", "__OMNIGENT_PRIMARY__/.atomic/workflows/omnigent/runtime-contract-checks.py", "__OMNIGENT_SANDBOX__", "--runtime-tooling"], expectExitZero: true, expectStdoutIncludes: ["shared-runtime-contract-ok"] },
      ...["magnetite", "pyrite", "stibnite"].map((name) => probe(name)),
      probe("magnetite", true),
      { kind: "GrepAssert", file: "modules/nixos/omnigent.nix", pattern: "path = \\[ pkgs\\.lsof \\];" },
      { kind: "GrepAssert", file: plan, pattern: "S11 runtime tooling[\\s\\S]*optional UI vendor installs remain unsupported" },
    ],
  };
}
