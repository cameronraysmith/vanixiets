import { mkdir, readFile, writeFile, lstat, readlink } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import type { WorkflowRunContext, WorkflowSerializableValue, WorkflowTaskOptions, WorkflowTaskResult } from "@bastani/atomic/workflows";
import { capture, changed, quote, requireSuccess, processCheckpoint } from "../bump/tools.js";
import { within } from "../bump/types.js";
import { chain, model, modelOptions, repository, parse, Source, Stop, rethrowControl, stopCategories, type Slice } from "./contract.js";

export type Port = Pick<WorkflowRunContext, "tool" | "task" | "ui">;
export type Execute = typeof capture;
export const digest = (value: unknown) => createHash("sha256").update(JSON.stringify(value)).digest("hex");
export async function currentModel(ctx: object): Promise<string> {
  const catalog: unknown = Reflect.get(ctx, "models");
  if (!catalog || typeof catalog !== "object") throw new Stop("model", "Atomic current-model catalog unavailable; select the requested model before launch");
  const selected: unknown = Reflect.get(catalog, "currentModel");
  if (selected === undefined) throw new Stop("model", "Atomic current-model metadata missing; select the requested model before launch");
  const provider: unknown = selected && typeof selected === "object" ? Reflect.get(selected, "provider") : undefined;
  const id: unknown = selected && typeof selected === "object" ? Reflect.get(selected, "id") : undefined;
  const fullId = typeof selected === "string" ? selected : typeof provider === "string" && typeof id === "string" ? `${provider}/${id}` : undefined;
  if (!fullId || !/^[^/\s]+\/\S+$/.test(fullId)) throw new Stop("model", "Atomic current-model metadata malformed; expected provider/id model identity");
  if (fullId !== model && fullId !== `${model}:high`) throw new Stop("model", `Configured current model is not ${model}`);
  return fullId;
}
export function modelEvidence(result: WorkflowTaskResult) {
  const attempts = result.modelAttempts ?? [];
  if (!attempts.length) throw new Stop("model", "No observed model-attempt metadata");
  for (const a of attempts) {
    if (a.model !== model && a.model !== `${model}:high`) throw new Stop("model", "Observed off-policy model; stop before activation");
    if (a.reasoningLevel !== undefined && a.reasoningLevel !== "high") throw new Stop("model", "Observed off-policy thinking effort");
  }
  const successful = attempts.filter((a) => a.success).at(-1);
  if (!successful || successful.reasoningLevel !== "high") throw new Stop("model", "Successful stage lacks observed high-thinking metadata");
  return { attempts: attempts.map((a) => ({ model: a.model, thinking: a.reasoningLevel ?? null, success: a.success })), incompleteFailedAttemptEffort: attempts.some((a) => !a.success && a.reasoningLevel === undefined) };
}
export function allowedChanges(before: Record<string, string>, after: Record<string, string>, paths: string[]) {
  const delta = changed(before, after);
  return { owned: delta.filter((p) => paths.some((a) => within(p, a))), foreign: delta.filter((p) => !paths.some((a) => within(p, a))) };
}
export function routeCommand(target: string, paths: string[], allowed: string[]): string {
  if (!/^[k-z]{32}$/.test(target) || !paths.length || paths.some((p) => p.startsWith("/") || p.split("/").includes("..") || !allowed.some((a) => within(p, a)))) throw new Stop("contract", "Invalid squash destination or attributed paths");
  return `jj squash --from @ --into ${quote(target)} --use-destination-message --keep-emptied -- ${paths.map(quote).join(" ")}`;
}
export class Operations {
  constructor(readonly ctx: Port, readonly root: string, readonly timeout: number, readonly execute: Execute = capture) {}
  async tool<T extends WorkflowSerializableValue>(name: string, identity: Record<string, WorkflowSerializableValue>, action: (signal: AbortSignal) => Promise<T>, timeout = this.timeout): Promise<T> {
    const result = await this.ctx.tool(name, { root: this.root, ...identity }, async ({ signal }) => {
      signal.throwIfAborted();
      await mkdir(join(repository, this.root), { recursive: true, mode: 0o700 });
      return processCheckpoint(this.root, name, () => action(signal));
    }, { timeoutMs: timeout, failureMode: "return", retriesAllowed: false });
    if (!result.ok) {
      rethrowControl(result.error);
      throw new Stop(stopCategories.find((category) => result.error.name === `WorkerMigrationBlocked:${category}`) ?? "infrastructure", `${name}: ${result.error.message}`);
    }
    return result.value.evidence;
  }
  async save(file: string, value: WorkflowSerializableValue) {
    return this.tool(`save-${file}`, { file, digest: digest(value) }, async (signal) => {
      signal.throwIfAborted();
      const path = `${this.root}/${file}.json`;
      await mkdir(join(repository, this.root), { recursive: true });
      await writeFile(join(repository, path), JSON.stringify(value, null, 2) + "\n", { mode: 0o600 });
      return path;
    });
  }
  async stage(name: string, options: WorkflowTaskOptions) {
    // Atomic 0.9.18 appends the current model even with []. These are observations, not a session lock.
    await currentModel(this.ctx);
    const result = await this.ctx.task(name, { ...options, ...modelOptions, context: "fresh", mcp: { allow: [] } });
    const observed = result.modelAttempts?.map((a) => ({ model: a.model, thinking: a.reasoningLevel ?? null, success: a.success })) ?? [];
    await this.save(`model-${name}`, { observed });
    modelEvidence(result);
    return result;
  }
  async command(command: string, signal: AbortSignal): Promise<string> { return requireSuccess(await this.execute(repository, command, signal)); }
  async id(rev: string, signal: AbortSignal): Promise<string> {
    const text = (await this.command(`jj --ignore-working-copy log --no-graph -r ${quote(rev)} -T 'change_id ++ "\\n"'`, signal)).trim();
    if (!/^[k-z]{32}$/.test(text)) throw new Stop("reconcile", `Ambiguous jj revision: ${rev}`);
    return text;
  }
  async healthy(signal: AbortSignal, expected?: string): Promise<string> {
    const working = await this.id("@", signal);
    if (expected && expected !== working) throw new Stop("reconcile", "Working copy identity moved");
    const conflicts = await this.command("jj --ignore-working-copy log --no-graph -r 'ancestors(@) & conflicts()' -T 'change_id'", signal);
    const log = await this.command("jj --ignore-working-copy log --no-graph -r 'ancestors(@) & mutable()'", signal);
    if (conflicts.trim() || /\(divergent\)|wip\?\?/.test(log)) throw new Stop("reconcile", "Conflicted or divergent development join");
    const parents = (await this.command(`jj --ignore-working-copy log --no-graph -r 'parents(@-)' -T 'change_id ++ "\\n"'`, signal)).trim().split("\n");
    const tip = await this.id(chain, signal);
    if (parents.length < 2 || !parents.includes(tip)) throw new Stop("reconcile", "Chain tip must be a direct parent of the integrated join");
    return working;
  }
  async source(rev: string, signal: AbortSignal): Promise<Source> {
    const workingCopy = await this.healthy(signal);
    const change = await this.id(rev, signal);
    const sha = (await this.command(`jj --ignore-working-copy log --no-graph -r ${quote(change)} -T 'commit_id'`, signal)).trim();
    await this.command(`git cat-file -e ${quote(`${sha}^{commit}`)}`, signal);
    const joinParents = (await this.command(`jj --ignore-working-copy log --no-graph -r 'parents(@-)' -T 'change_id ++ "\\n"'`, signal)).trim().split("\n");
    return parse(Source, { change, sha, workingCopy, joinParents, source: `git+file://${repository}?rev=${sha}` });
  }
  async observeSource(name: string, rev = chain): Promise<Source> { return this.tool(name, { rev }, (signal) => this.source(rev, signal)); }
  async filesystemTree(signal: AbortSignal): Promise<Record<string, string>> {
    const files = (await this.command("git ls-files --cached --others --exclude-standard -z", signal)).split("\0").filter(Boolean);
    const tree: Record<string, string> = {};
    for (const file of files) {
      signal.throwIfAborted();
      try {
        const path = join(repository, file), info = await lstat(path);
        const mode = info.isSymbolicLink() ? "120000" : info.isFile() ? (info.mode & 0o100 ? "100755" : "100644") : undefined;
        if (!mode) throw new Stop("reconcile", `Unclassifiable file: ${file}`);
        const bytes = info.isSymbolicLink() ? Buffer.from(await readlink(path)) : await readFile(path);
        tree[file] = `${mode}:${createHash("sha1").update(`blob ${bytes.length}\0`).update(bytes).digest("hex")}`;
      } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
    }
    return tree;
  }
  async storedTree(rev: string, spec: Slice, signal: AbortSignal): Promise<Record<string, string>> {
    const sha = (await this.command(`jj --ignore-working-copy log --no-graph -r ${quote(rev)} -T commit_id`, signal)).trim();
    if (!/^[a-f0-9]{40}$/.test(sha)) throw new Stop("reconcile", "Ambiguous stored baseline");
    const entries = (await this.command(`git ls-tree -r -z ${quote(sha)} -- ${spec.paths.map(quote).join(" ")}`, signal)).split("\0").filter(Boolean);
    const tree: Record<string, string> = {};
    for (const entry of entries) {
      const match = /^(100644|100755|120000) blob ([a-f0-9]{40})\t([\s\S]+)$/.exec(entry);
      if (!match) throw new Stop("reconcile", "Unsupported stored entry in owned scope");
      tree[match[3]!] = `${match[1]}:${match[2]}`;
    }
    return tree;
  }
  assertOwnedEqual(spec: Slice, expected: Record<string, string>, actual: Record<string, string>, message: string) {
    if (changed(expected, actual).some((p) => spec.paths.some((a) => within(p, a)))) throw new Stop("reconcile", message);
  }
  async snapshot(name: string, spec?: Slice): Promise<string> {
    return this.tool(name, { paths: spec?.paths ?? [] }, async (signal) => {
      const tree = await this.filesystemTree(signal);
      if (spec) this.assertOwnedEqual(spec, await this.storedTree("@-", spec, signal), tree, "Pre-existing in-scope edits: preserve and reconcile before writing");
      const path = `${this.root}/${name}.json`;
      await writeFile(join(repository, path), JSON.stringify(tree), { mode: 0o600 });
      return path;
    });
  }
  async tree(path: string): Promise<Record<string, string>> { return JSON.parse(await readFile(join(repository, path), "utf8")) as Record<string, string>; }
  async assertCleanScope(spec: Slice) {
    await this.tool(`clean-${spec.phase}`, { paths: spec.paths }, async (signal) => {
      const stored = await this.storedTree("@-", spec, signal);
      const actual = await this.filesystemTree(signal);
      this.assertOwnedEqual(spec, stored, actual, "Pre-existing in-scope edits: preserve and reconcile before writing");
      const paths = (await this.command("jj --ignore-working-copy diff -r @ --name-only", signal)).split("\n").filter(Boolean);
      if (paths.some((p) => spec.paths.some((a) => within(p, a)))) throw new Stop("reconcile", "Pre-existing in-scope recorded edits: reconcile before writing");
      return { foreignPaths: paths };
    });
  }
  async route(name: string, spec: Slice, beforeFile: string, afterFile: string, previous: Source): Promise<Source> {
    const before = await this.tree(beforeFile), after = await this.tree(afterFile);
    const delta = allowedChanges(before, after, spec.paths);
    if (delta.foreign.length && !await this.ctx.ui.confirm(`Unrelated paths changed during ${spec.phase}: ${delta.foreign.join(", ")}. Confirm they belong to other agents, not this writer. They will not be routed.`)) throw new Stop("reconcile", "Foreign-change attribution unresolved");
    return this.tool(name, { phase: spec.phase, owned: delta.owned, content: digest(after), previous }, async (signal) => {
      const workingCopy = await this.healthy(signal, previous.workingCopy);
      this.assertOwnedEqual(spec, before, await this.storedTree("@-", spec, signal), "Owned baseline changed before routing; reconcile whole-path delta");
      const now = await this.filesystemTree(signal);
      this.assertOwnedEqual(spec, after, now, "Owned bytes changed between observation and route");
      const marker = `${spec.title}\n\nOmnigent-Workers-Step: ${this.root}/${spec.phase}`;
      let tip = await this.id(chain, signal);
      const description = (await this.command(`jj --ignore-working-copy log --no-graph -r ${quote(tip)} -T description`, signal)).trim();
      let target: string;
      if (description === marker) target = tip;
      else {
        if (tip !== previous.change) throw new Stop("reconcile", "Chain tip changed before routing");
        const child = await this.id(`${tip}+`, signal);
        const joinId = await this.id("@-", signal);
        if (child !== joinId) throw new Stop("reconcile", "Unfinished splice requires explicit reconciliation");
        if (!delta.owned.length) return this.source(chain, signal);
        await this.command(`jj new --no-edit -A ${quote(tip)} -m ${quote(marker)}`, signal);
        target = await this.id(`${tip}+`, signal);
      }
      if (delta.owned.length) {
        this.assertOwnedEqual(spec, after, await this.filesystemTree(signal), "Owned bytes changed before squash");
        this.assertOwnedEqual(spec, before, await this.storedTree("@-", spec, signal), "Owned baseline changed before squash");
        await this.command(routeCommand(target, delta.owned, spec.paths), signal);
        this.assertOwnedEqual({ ...spec, paths: delta.owned }, after, await this.storedTree(target, spec, signal), "Attributed destination differs from observed writer output");
      }
      await this.command(`jj bookmark set ${quote(chain)} -r ${quote(target)}`, signal);
      await this.healthy(signal, workingCopy);
      for (const parent of previous.joinParents) {
        if (await this.id(`${parent} & ancestors(@-)`, signal) !== parent) throw new Stop("reconcile", "Routing removed a development-join chain");
      }
      const observed = await this.filesystemTree(signal);
      if (delta.owned.some((p) => observed[p] !== after[p])) throw new Stop("reconcile", "Routed bytes differ");
      const remaining = (await this.command("jj --ignore-working-copy diff -r @ --name-only", signal)).split("\n");
      if (delta.owned.some((p) => remaining.includes(p))) throw new Stop("reconcile", "Attributed paths remain in @ after routing");
      return this.source(chain, signal);
    });
  }
}
