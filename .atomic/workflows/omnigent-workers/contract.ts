import { Type, type Static, type TSchema } from "typebox";
import { Value } from "typebox/value";

export const repository = "/Users/crs58/projects/vanixiets";
export const chain = "omnigent-magnetite";
export const model = "openai-codex/gpt-6-astra";
export const modelOptions = { model: `${model}:high`, thinkingLevel: "high", fallbackModels: [] } as const;
export const research = ".atomic/workflows/runs/fan-out-and-synthesize-cdf84325-0d11-4b73-8451-009787d3a765/synthesis.md";
export const hosts = ["magnetite", "pyrite", "stibnite"] as const;
export type Host = typeof hosts[number];
export const phases = ["capabilities", "linux", "darwin", "inventory", ...hosts, "closure"] as const;
export type Phase = typeof phases[number];
export const HostSchema = Type.Union([Type.Literal("magnetite"), Type.Literal("pyrite"), Type.Literal("stibnite")]);
export const PhaseSchema = Type.Union([Type.Literal("capabilities"), Type.Literal("linux"), Type.Literal("darwin"), Type.Literal("inventory"), Type.Literal("magnetite"), Type.Literal("pyrite"), Type.Literal("stibnite"), Type.Literal("closure")]);
const text = Type.String({ minLength: 1, maxLength: 4096 });
const sha = Type.String({ pattern: "^[a-f0-9]{40}$" });
const change = Type.String({ pattern: "^[k-z]{32}$" });
const revision = { sha, change, tree: sha };
const integratedJoin = Type.Object({ ...revision, parents: Type.Array(Type.Object({ sha, change }, { additionalProperties: false }), { minItems: 2 }) }, { additionalProperties: false });
export const Source = Type.Object({ ...revision, parents: Type.Array(sha, { minItems: 1 }), role: Type.Union([Type.Literal("chain"), Type.Literal("integrated")]), chain: Type.Literal(chain), source: text, workingCopy: change, joinParents: Type.Array(change, { minItems: 2 }), join: integratedJoin }, { additionalProperties: false });
export type Source = Static<typeof Source>;
export const StageReport = Type.Union([
  Type.Object({ kind: Type.Literal("implemented"), summary: text }, { additionalProperties: false }),
  Type.Object({ kind: Type.Literal("blocked"), reason: text }, { additionalProperties: false }),
]);
export const Review = Type.Union([
  Type.Object({ kind: Type.Literal("approved"), evidence: Type.Array(text, { minItems: 1 }) }, { additionalProperties: false }),
  Type.Object({ kind: Type.Literal("repair"), findings: Type.Array(text, { minItems: 1 }) }, { additionalProperties: false }),
  Type.Object({ kind: Type.Literal("contract_defect"), reason: text }, { additionalProperties: false }),
]);
export type Review = Static<typeof Review>;
export function parse<S extends TSchema>(schema: S, value: unknown): Static<S> {
  if (!Value.Check(schema, value)) throw new Stop("contract", "Malformed structured evidence");
  return value as Static<S>;
}
export const stopCategories = ["contract", "implementation", "reconcile", "human", "model", "infrastructure"] as const;
export class Stop extends Error {
  constructor(readonly category: typeof stopCategories[number], message: string) { super(message); this.name = `WorkerMigrationBlocked:${category}`; }
}
export function rethrowControl(error: unknown): void {
  const seen = new Set<object>();
  const control = (value: unknown): boolean => {
    if (!value || typeof value !== "object" || seen.has(value)) return false;
    seen.add(value);
    const name = String(Reflect.get(value, "name") ?? "").toLowerCase();
    const code = String(Reflect.get(value, "code") ?? "").toLowerCase();
    const stopReason = String(Reflect.get(value, "stopReason") ?? "").toLowerCase();
    if (["aborterror", "aborted", "cancelederror", "cancellederror", "canceled", "cancelled", "workflowbudgetexceedederror", "stagesessioncreationcancelled", "thrownerrorretrypaused"].includes(name)
      || ["aborterror", "abort_err", "aborted", "canceled", "cancelled", "ecanceled", "ecancelled", "err_canceled", "err_cancelled"].includes(code)
      || ["aborted", "canceled", "cancelled"].includes(stopReason)) return true;
    // Atomic 0.9.18 exposes no authoring guard for its symbol-branded exit rails.
    if (Object.getOwnPropertySymbols(value).some((symbol) => ["atomic-workflows.workflow-exit-signal", "atomic-workflows.parent-workflow-exit-abort"].includes(symbol.description ?? "") && Reflect.get(value, symbol) === true)) return true;
    const errors: unknown = Reflect.get(value, "errors");
    return control(Reflect.get(value, "cause")) || control(Reflect.get(value, "reason")) || (Array.isArray(errors) && errors.some(control));
  };
  if (control(error)) throw error;
}
export function unreachable(value: never): never { throw new Stop("contract", `Unexpected constructor: ${JSON.stringify(value)}`); }
export const Receipt = Type.Object({ phase: PhaseSchema, change, sha, evidence: text }, { additionalProperties: false });
export type Receipt = Static<typeof Receipt>;
export const outputs = { receipt: Receipt };
export const inputs = {
  start_at: Type.Integer({ minimum: 0, maximum: 7, default: 0, description: "First phase; earlier phases are reconciled once at the current chain tip, not replayed at historical SHAs." }),
  deploy: Type.Boolean({ default: false, description: "Allow host preparation/migration after explicit per-host confirmations." }),
  max_repairs: Type.Integer({ minimum: 0, maximum: 3, default: 2 }),
  build_timeout_minutes: Type.Integer({ minimum: 1, maximum: 180, default: 90 }),
};
export const childInputs = { phase: PhaseSchema, root: text, max_repairs: inputs.max_repairs, timeout: Type.Integer({ minimum: 1 }), verify_only: Type.Boolean({ default: false }), reads: Type.Array(text) };
export type ChildInputs = { phase: Phase; root: string; max_repairs: number; timeout: number; verify_only: boolean; reads: string[] };

const docs = ["docs/notes/development/omnigent/deployment-plan.md", "modules/clan/services/omnigent/README.md", "openspec/changes/deploy-omnigent-magnetite"];
const checks = ["modules/checks/omnigent-workers.nix"];
const inventory = ["modules/clan/inventory/services/omnigent.nix", "modules/clan/inventory/services/users/omnigent-workers.nix", "modules/machines/darwin/stibnite/default.nix"];
export type Slice = { phase: Phase; title: string; paths: string[]; objective: string; acceptance: string[] };
export function slice(phase: Phase): Slice {
  const common = { phase };
  switch (phase) {
    case "capabilities": return { ...common, title: "refactor(home): expose credential-free worker capabilities", paths: ["modules/home/ai/omnigent", "modules/home/ai/agent-settings.nix", "modules/home/ai/atomic/default.nix", "modules/home/ai/omp/default.nix", "modules/home/ai/pi/default.nix", "modules/home/ai/skills", "modules/home/tools/agents-md.nix", "modules/home/modules/agents-md.nix", "modules/home/terminal/ripgrep.nix", "modules/home/terminal/fd.nix", "modules/home/terminal/direnv.nix", "modules/home/development/gh.nix", "modules/home/development/nix-tools.nix", "modules/home/development/git.nix", "modules/home/development/jujutsu.nix", "modules/home/development/tools.nix", "modules/home/development/linear.nix", "modules/home/users/crs58/default.nix", ...checks, ...docs], objective: "Compose reusable worker HM capabilities from existing modules without contentPrivate, personal sops, signing/SSH sockets or whole-user aliases. Keep required runtime providers before the worker home.path. Preserve current human configurations and working legacy hosts.", acceptance: ["Provide checks.<system>.omnigent-worker-capabilities on both systems: real worker composition supplies rg/fd/gh/Linear/harnesses; profile-only executable resolves without shadowing required providers.", "Preserve the independently captured human package/artifact projection. Only self-root sops and home-file source locations are canonicalized by content for evaluation; original relative paths/content remain witnessed. Do not edit personal behavior to satisfy this gate. Any other projection difference blocks pending review.", "Tests reject personal secret/signing/foreign-home dependencies and prove mutable config merge preserves unknown keys and host.host_id, with malformed-input rejection."] };
    case "linux": return { ...common, title: "feat(omnigent): supervise per-user Linux workers", paths: ["modules/system/omnigent-worker-options.nix", "modules/nixos/omnigent-host.nix", "modules/home/ai/omnigent", "modules/clan/services/omnigent/flake-module.nix", ...checks, ...docs], objective: "Add the shared typed workers interface and Linux per-instance system services. Keep legacy execution intact, new instances disabled until enrolled, and the server unchanged. Derive identities/state from declared accounts; integrated HM activation precedes the host service.", acceptance: ["Provide checks.x86_64-linux.omnigent-worker-linux: evaluate two real module instances, root/duplicate user/home/admin/Nix-trusted negative fixtures, environment selector override rejection, private homes/umask, ordered runtime -> worker profile -> extras.", "Assert foreground host, existing restart/resource policy, soft networking, activation ordering and activation-failure prevention. No global privileged-user fallback or systemd user/linger design.", "Default execution disabled does not prevent account/HM preparation. Owner is intended association, not invented application-auth enforcement. Preserve Atomic-specific PI directory routing and independent omp state."] };
    case "darwin": return { ...common, title: "feat(omnigent): add dedicated Darwin worker adapter", paths: ["modules/darwin/omnigent-host.nix", "modules/system/omnigent-worker-options.nix", "modules/home/ai/omnigent", "modules/clan/services/omnigent/flake-module.nix", ...checks, ...docs], objective: "Add a system-domain launchd adapter running under the dedicated worker UID, with standalone HM activation before host execution. Preserve the current human HM agent until inventory migration. Reuse common capabilities, not a second interactive login.", acceptance: ["Provide checks.aarch64-darwin.omnigent-worker-darwin that inspects a realized module fixture: system-domain plist UserName, executable launcher, HM activation before exec and failure prevention, private HOME/log parents, no duplicate integrated HM activation.", "Inspect artifacts from the realized fixture's actual activation chain, not an independently evaluated generation. Negative fixture rejects wrong user/domain, missing runtime/profile, or host exec despite activation failure.", "Keep ProcessType Standard, restart throttling and sleep-compatible behavior; no sleep inhibition or worker desktop requirement. Actual logout/wake/authentication checks are post-deploy only."] };
    case "inventory": return { ...common, title: "feat(omnigent): prepare dedicated worker accounts", paths: [...inventory, "modules/clan/services/omnigent/flake-module.nix", ...checks, ...docs], objective: "Declare exactly Cameron+Raquel on magnetite and pyrite, Cameron only on stibnite; keep new execution disabled and legacy services unchanged. Use the operator-confirmed account metadata/collision report, not Raquel placeholder email or blackphos UID.", acceptance: ["Provide checks.<system>.omnigent-worker-inventory: exact five-worker matrix with private distinct homes, no admin/trusted daemon/SSH/signing inheritance, ordinary Nix/cache usage, no server changes.", "Retain prepared HM accounts while disabled. Declare no bot identity, model grants, key copies, account deletion or automatic credential enrollment.", "Worker settings stay serializable through clan except Nix-only extraHomeModules. Enabling a later host must not invalidate these structural tests."] };
    case "magnetite": case "pyrite": case "stibnite": return { ...common, title: `feat(omnigent): migrate ${phase} to personal workers`, paths: ["modules/clan/inventory/services/omnigent.nix", ...(phase === "stibnite" ? ["modules/machines/darwin/stibnite/default.nix"] : []), ...docs], objective: `Enable only ${phase}'s enrolled workers and disable its old lifecycle declaratively, preserving all homes, tokens, registrations and projects. The supplied onboarding receipt is human evidence, not permission to inspect/copy secrets. Do not enable another host.`, acceptance: ["Current-state gate must show exactly the expected per-host enable map and no old lifecycle for migrated hosts; pending hosts remain untouched.", "Preserve required runtime, profiles, private account permissions and unchanged server/foreign services. Real GitHub/Linear writes require operator approval and occur after activation, not slice review."] };
    case "closure": return { ...common, title: "docs(omnigent): record real-user worker acceptance", paths: docs, objective: "Reconcile existing OpenSpec, runbook and plan with the collected immutable-source and real-host evidence. Record actual identities and host IDs but never secrets. Preserve failed/not-tested outcomes; no publishing/landing claim.", acceptance: ["Distinguish evaluated, built, deployed, automated-runtime and human-attested outcomes, including per-harness/platform limits and external token/admin authority.", "Describe credential renewal, new registration vs old sessions, no unsafe privileged rollback, shared-store visibility, and future Modal/Freestyle/Hetzner needs without asserting KVM support or implementing providers."] };
    default: return unreachable(phase);
  }
}
export const invariants = `<keepContext>
Implement only this slice in /Users/crs58/projects/vanixiets. Confirm pwd first and read nearest README and relevant skills. Shared jj @/wip must never move. No VCS mutation, worktrees, new chains, deployment, SSH, credentials, OAuth, cloud provisioning or nested agents. The controller alone routes allowed paths as new tip commits. Never edit .atomic/workflows, old gates/history, server modules, or unrelated files. Return blocked for contract defects or material ambiguity; do not substitute a plan for implementation. Model selection: openai-codex/gpt-6-astra high.
Approved design: five real-human workers; Cameron on all three hosts, Raquel on Linux hosts only. Private worker-local credential files and shared-store visibility for approved projects accepted. Personal GitHub/Linear identities preferred; no bots granted. No admin/wheel/trusted-user/cache-upload/SSH-signer authority by inheritance. No wholesale profile/private-directory copy. Linux integrated HM, Darwin dedicated-UID system daemon with standalone HM. Preserve legacy execution until explicit host migration. Existing server stays narrow. Safe canaries, actual users and targeted live checks; no staging platform or provider framework. Credentials and application-admin grants retain their external authority.
Source contexts are distinct: author only the attributed chain delta while working in the shared integrated tree. Preserve the fixed integrated baseline including pre-existing Niri and other foreign contributions; the isolated chain baseline proves independent shippability, not equality with the filesystem. Local pre-edit comparisons must use the matching integrated context. Never regenerate either protected baseline from an edited candidate, revert foreign behavior, or absorb foreign owned-path contributions. Controller gates compare each candidate only with its same-role fixed baseline; later account/enablement phases intentionally change homes but must preserve the server.
Linux/Darwin adapter slices must make the intended child sandbox selection explicit and test its configured grants and Nix/profile visibility with real module fixtures. Do not infer confinement from bwrap being installed, extend an unavailable executor guarantee, or weaken the whole-worker boundary to make a tool work. Unsupported required protection is a contract blocker. Keep auxiliaries and project hooks inside the worker's authority even where child sandbox coverage differs; actual selected-harness checks follow activation.
</keepContext>`;
