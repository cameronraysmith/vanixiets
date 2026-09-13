import { workflow } from "@bastani/atomic/workflows";
import { Type } from "typebox";
import { join } from "node:path";
import { quote } from "../bump/tools.js";
import implementation from "./slice.js";
import { HostSchema, repository, Stop, rethrowControl, type Host, type Source } from "./contract.js";
import { Operations } from "./operations.js";
import { gates, systemPath, workersExpr } from "./gates.js";

export function hostCommand(host: Host, command: string): string {
  return host === "stibnite" ? command : `ssh -o BatchMode=yes -o ConnectTimeout=20 root@${host}.zt ${quote(command)}`;
}
export async function reconcileActivation(ops: Operations, host: Host, system: string, source: Source, signal: AbortSignal) {
  const current = (await ops.command(hostCommand(host, "readlink /run/current-system"), signal)).trim();
  const profile = host === "stibnite" ? (await ops.command("cat /nix/var/nix/profiles/system/systemConfig", signal)).trim() : current;
  if (current === system && profile === system) return { kind: "already-activated" as const, host, system, sha: source.sha };
  if (host === "stibnite" && profile !== system) {
    await ops.command(`sudo -n nix-env -p /nix/var/nix/profiles/system --set ${quote(system)}`, signal);
    if ((await ops.command("cat /nix/var/nix/profiles/system/systemConfig", signal)).trim() !== system) throw new Stop("reconcile", "Darwin persistent profile target mismatch");
  }
  if (current !== system) {
    const activate = host === "stibnite" ? `sudo -n ${quote(`${system}/sw/bin/darwin-rebuild`)} activate` : `clan machines update ${host} --flake ${quote(source.source)}`;
    await ops.command(activate, signal);
  }
  const observed = (await ops.command(hostCommand(host, "readlink /run/current-system"), signal)).trim();
  if (observed !== system || (host === "stibnite" && (await ops.command("cat /nix/var/nix/profiles/system/systemConfig", signal)).trim() !== system)) throw new Stop("reconcile", `Activation/profile target mismatch on ${host}: ${observed}`);
  return { kind: "activated" as const, host, system: observed, sha: source.sha };
}
export async function liveProbe(ops: Operations, name: string, host: Host, source: Source, mode: "collision" | "prepared" | "running" | "canaries") {
  return ops.tool(name, { host, source, mode }, async (signal) => {
    const workers = await ops.command(`nix eval --no-write-lock-file --impure --json --expr ${quote(workersExpr(source.source, host))}`, signal);
    const d = host === "stibnite" ? "darwinConfigurations" : "nixosConfigurations";
    const python = (await ops.command(`nix build --no-write-lock-file --no-link --print-out-paths ${quote(`${source.source}#${d}.${host}.pkgs.python3`)}`, signal)).trim();
    if (!/^\/nix\/store\/[a-z0-9]{32}-[^\s]+$/.test(python)) throw new Stop("contract", "Invalid Python store path");
    if (host !== "stibnite") await ops.command(`nix copy --to ssh-ng://root@${host}.zt ${quote(python)}`, signal);
    const inner = `${quote(`${python}/bin/python3`)} - ${mode} ${host} ${quote(workers)}`;
    const command = `git show ${quote(`${source.sha}:.atomic/workflows/omnigent-workers/live.py`)} | ${host === "stibnite" ? `sudo -n ${inner}` : hostCommand(host, inner)}`;
    const observation = await ops.execute(repository, command, signal);
    let value: unknown;
    try { value = JSON.parse(observation.stdout); } catch { throw new Stop("infrastructure", `${name}: probe did not return JSON; see process log`); }
    if (!value || typeof value !== "object" || Reflect.get(value, "host") !== host || Reflect.get(value, "mode") !== mode || typeof Reflect.get(value, "passed") !== "boolean") throw new Stop("contract", "Invalid live probe result");
    return { passed: observation.exitCode === 0 && Reflect.get(value, "passed") === true, exitCode: observation.exitCode, artifact: await writeProbe(ops, name, value), sha: source.sha };
  });
}
async function writeProbe(ops: Operations, name: string, value: unknown) {
  const path = `${ops.root}/${name}.json`;
  await import("node:fs/promises").then((fs) => fs.writeFile(join(repository, path), JSON.stringify(value, null, 2), { mode: 0o600 }));
  return path;
}
export const acceptanceItems = [
  "Each human's Omnigent owner and GitHub/Linear identity match their intended accounts; a foreign-owned host cannot be selected. Existing application-admin exceptions are recorded.",
  "Each human completes a native and selected ACP turn with rg/fd/gh and a profile-only tool; an approved fresh-worktree devshell runs its tests and uses cached packages.",
  "The human explicitly approved and observed a real GitHub and Linear create/update operation under the intended identity; record object references, never tokens. No bot was substituted.",
  "Agent, terminal, auxiliary API and project-hook paths deny cross-account canary/private-socket access and prohibited local administration. Do not equate UID separation with hiding all process metadata.",
  "Restart preserves the new host registration and state; legacy/manual duplicate hosts are stopped and old state preserved. Sharing deliberately uses the owner's execution identity.",
  "Each worker produces a signed commit that verifies against its declared public key and canonical gitEmail principal in allowed_signers; record commit and public fingerprint references, never private key material.",
] as const;
export default workflow({
  name: "omnigent-worker-migration",
  description: "One host's reconciled preparation, human enrollment, scoped enablement and real-host acceptance.",
  inputs: { host: HostSchema, root: Type.String(), timeout: Type.Integer({ minimum: 1 }), max_repairs: Type.Integer({ minimum: 0, maximum: 3 }), reads: Type.Array(Type.String()) },
  outputs: { host: HostSchema, sha: Type.String(), system: Type.String(), evidence: Type.String(), acceptance: Type.Literal("human_attested") },
  run: async (ctx) => {
    const { host, root, timeout, max_repairs, reads } = ctx.inputs;
    const ops = new Operations(ctx, root, timeout);
    const activate = async (label: string, source: Source) => {
      await ops.stage(`coordinate-${label}`, {
        tools: ["intercom"], schema: Type.Object({ acknowledged: Type.Boolean() }, { additionalProperties: false }),
        prompt: `Coordinate imminent ${host} activation at ${source.sha} with live agents via Intercom: list sessions in the invocation group, notify relevant agents and resolve active deployment conflicts. Do not contact unrelated groups or perform any host action. If the broker cannot reach a concurrent deployer, report acknowledged=false; the operator must reconcile. Return acknowledged=true only after no known competing deployment remains.`,
      }).then((result) => {
        if (!result.structured || typeof result.structured !== "object" || Reflect.get(result.structured, "acknowledged") !== true) throw new Stop("reconcile", "Deployment coordination incomplete");
      });
      const system = await ops.tool(`build-${label}`, { host, source }, (signal) => systemPath(ops, host, source, signal));
      if (!await ctx.ui.confirm(`Activate ${host}: source ${source.sha}; target ${system}. Coordinate other agents' host activations and inspect the join's non-authored changes/one-way activation notes. Activate this exact integrated snapshot? Downtime is acceptable; credentials and data must remain preserved.`)) throw new Stop("human", "Activation declined");
      const receipt = await ops.tool(`activate-${label}`, { host, source, system }, (signal) => reconcileActivation(ops, host, system, source, signal));
      await ops.save(`activation-${label}`, receipt);
      return system;
    };
    try {
      let source = await ops.observeSource("prepare-join", "@-");
      const metadata = await ops.tool("worker-metadata", { host, source }, async (signal) => JSON.parse(await ops.command(`nix eval --no-write-lock-file --impure --json --expr ${quote(workersExpr(source.source, host))}`, signal)) as Record<string, { enabled: boolean; user: string; home: string; owner: string; hostName: string; name: string }>);
      const alreadyEnabled = Object.values(metadata).every((w) => w.enabled);
      if (!alreadyEnabled) {
        const previousPhase = host === "magnetite" ? "credentials" : host === "pyrite" ? "magnetite" : "pyrite";
        const checked = await gates(ops, "prepare-gates", previousPhase, source);
        if (!checked.passed) throw new Stop("implementation", "Integrated preparation gates failed");
        const collisions = await liveProbe(ops, "account-collisions", host, source, "collision");
        if (!collisions.passed) throw new Stop("reconcile", `Account collision; inspect ${collisions.artifact}`);
        if (!await ctx.ui.confirm(`Inspect ${collisions.artifact} and configured accounts ${JSON.stringify(metadata)}. Confirm actual account/home/UID/GID allocations are appropriate, existing matching accounts are intentionally adopted, and Janette (janettesmith) is the real enrolling user replacing only Raquel's experimental Linux workers. Cameron's accounts and both human profiles remain unchanged. No placeholder email is an identity.`)) throw new Stop("human", "Account metadata unconfirmed");
        await activate("prepare", source);
        const prepared = await liveProbe(ops, "prepared-accounts", host, source, "prepared");
        if (!prepared.passed) throw new Stop("reconcile", `Prepared account check failed: ${prepared.artifact}`);
      }
      const enrollment = await ctx.ui.editor(`Verify provisioned ${host} workers — non-secret record only. Accounts: ${JSON.stringify(metadata)}\nStatic signing/GitHub/Linear and optional native-Claude credentials must already be enrolled through the declarative Clan vars contract and delivered with worker ownership/mode 0400. Record prior approval/delivery evidence; if absent, stop for the separately gated provisioning step. Do not run gh auth login, linear auth login, or overwrite managed files.\nHumans complete only missing Omnigent browser tickets and selected model OAuth under each actual worker HOME; use the selected harness's installed-version flow and explicit auth directory. Never copy personal directories, age identities, bundles or tool-owned refresh stores. Omnigent: omnigent login https://omni.scientistexperience.net, with the human completing the browser ticket.\nVerify gh api --hostname github.com user --jq .login equals the expected GitHub login (Janette: janetteasmith; Cameron: his declared login); verify Linear auth whoami with the explicit declared workspace matches its intended person/workspace. Verify authenticated Omnigent /v1/me email matches the declared primary/SSO mail (Janette: janette.a.smith@gmail.com), owner/admin status and refresh readiness. Verify the delivered signing key fingerprint matches the declared public key, without printing private material. No token-output flags, auth dumps or credential-bearing logs.\nRecord owner, GitHub login, Linear identity/workspace, Omnigent email/host ID, public signing fingerprint and selected harnesses for each person, with no credentials. Existing enrollment is verified, not repeated; tool-owned OAuth state must remain mutable and untouched by deployment.\n`);
      if (!enrollment?.trim()) throw new Stop("human", "Provisioning/identity verification record missing");
      const enrollmentPath = await ops.save("enrollment", { host, kind: "human_attestation", record: enrollment });
      if (!await ctx.ui.confirm("Have all listed humans confirmed prior declarative static-credential enrollment/delivery, matching GitHub login, Linear person/workspace, Omnigent /v1/me email/owner and refresh readiness, signing-key public fingerprint, and selected model entitlement under these worker accounts? No secrets or token-output flags; provider and decryption authority must be intentional. No existing sessions are automatically rerouted.")) throw new Stop("human", "Provisioning/identity verification incomplete");
      const enabled = await ctx.workflow(implementation, { stageName: `enable-${host}`, inputs: { phase: host, root: `${root}/enable`, timeout, max_repairs, verify_only: alreadyEnabled, reads: [...reads, enrollmentPath] } });
      if (enabled.exited === true) return ctx.exit({ status: "blocked", reason: enabled.exitReason ?? `${host} enablement not verified` });
      source = await ops.observeSource("enable-join", "@-");
      const integrated = await gates(ops, "enable-join-gates", host, source);
      if (!integrated.passed) throw new Stop("implementation", "Integrated enabled-state gates failed");
      if (!await ctx.ui.confirm(`Stop ${host}'s old omnigent-host service/agent and any manually launched duplicate hosts before activating the new workers. Preserve homes, credentials, registrations and project data. Active legacy sessions may stop. Confirm you have identified and stopped these lifecycles; do not report merely deleting a plist as unloading it.`)) throw new Stop("human", "Legacy lifecycle retirement not confirmed");
      const system = await activate("enable", source);
      const running = await liveProbe(ops, "running-workers", host, source, "running");
      if (!running.passed) throw new Stop("reconcile", `Runtime identity/tools/authentication check failed: ${running.artifact}`);
      const canary = await liveProbe(ops, "account-canaries", host, source, "canaries");
      if (!canary.passed) throw new Stop("reconcile", `Canary check failed: ${canary.artifact}`);
      const attestations = [];
      const lifecycle = host === "stibnite" ? "Runs without a worker graphical login; cached operation while offline, logout/reboot, sleep/wake and network recovery all observed. Test worker denial of a protected personal-account canary too; automated canaries here have only one worker." : host === "pyrite" ? "Suspend/resume and network loss/reconnection observed without intervention or sleep inhibition." : "Server and co-located foreign services remain functional after activation.";
      for (const [index, item] of [...acceptanceItems, lifecycle].entries()) {
        const answer = await ctx.ui.select(`${host}: ${item}`, ["passed", "failed", "not-tested"] as const);
        attestations.push({ item, answer });
        await ops.save(`acceptance-${index}`, { host, sha: source.sha, attestations });
        if (answer !== "passed") throw new Stop("human", `${host} acceptance ${index}: ${answer}; deployment may have succeeded; do not reactivate blindly`);
      }
      const notes = await ctx.ui.editor("Record session IDs, approved external object references, tested harnesses and lifecycle observations. No tokens, private content or untested claims.");
      if (!notes?.trim()) throw new Stop("human", "Acceptance evidence references missing");
      const current = await ops.tool("reconcile-final-generation", { host, system }, async (signal) => ({
        active: (await ops.command(hostCommand(host, "readlink /run/current-system"), signal)).trim(),
        persistent: host === "stibnite" ? (await ops.command("cat /nix/var/nix/profiles/system/systemConfig", signal)).trim() : system,
      }));
      if (current.active !== system || current.persistent !== system) throw new Stop("reconcile", "Host generation/profile changed during acceptance");
      const evidence = await ops.save("accepted", { host, source, system, running, canary, attestations, notes, kind: "human_attested" });
      return { host, sha: source.sha, system, evidence, acceptance: "human_attested" as const };
    } catch (error) {
      rethrowControl(error);
      return ctx.exit({ status: "blocked", reason: `${error instanceof Stop ? error.category : "infrastructure"}: ${String(error)}; host=${host}; preserve side effects; evidence=${root}` });
    }
  },
});
