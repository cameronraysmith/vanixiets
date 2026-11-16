import { execFile } from "node:child_process";
import { realpath, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const policyPresent = true;

export type EditWriteOperation = "edit" | "write";

// Decisions are classified by recoverability rather than severity: a mutation
// version control can undo is announced and allowed, and only a mutation
// nothing would bring back is refused. "notify" exists because Pi has no
// permission system, so a confirmation dialog on an autonomous session can
// have nobody to answer it and becomes an indefinite stall; announcing costs
// no turn and cannot deadlock.
export type PolicyDecision =
  | { readonly decision: "allow" }
  | { readonly decision: "notify"; readonly reason: string }
  | { readonly decision: "block"; readonly reason: string };

export interface EditWriteTarget {
  readonly canonicalPath: string;
}

export interface JjCurrentState {
  readonly conflicted: boolean;
  readonly divergent: boolean;
  readonly parentCount: number;
}

interface JjCommonState {
  readonly root: string;
  readonly at: JjCurrentState;
  readonly defaultBookmarksAtCurrent: readonly ("main" | "master")[];
}

export type WipState =
  | { readonly kind: "healthy" }
  | { readonly kind: "absent" }
  | { readonly kind: "moved" }
  | { readonly kind: "divergent" };

export type GitHead =
  | { readonly kind: "protected"; readonly branch: "main" | "master" }
  | { readonly kind: "feature"; readonly branch: string }
  | { readonly kind: "detached" };

export type RepositoryState =
  | { readonly kind: "outside-repository" }
  | {
      readonly kind: "git";
      readonly root: string;
      readonly head: GitHead;
    }
  | ({ readonly kind: "jj-ordinary" } & JjCommonState)
  | ({
      readonly kind: "jj-diamond";
      readonly join: {
        readonly conflicted: boolean;
        readonly parentCount: number;
        readonly parentsConflicted: boolean;
      };
      readonly wip: WipState;
    } & JjCommonState)
  | { readonly kind: "invalid"; readonly diagnostic: string };

export interface EditWriteInput {
  readonly operation: EditWriteOperation;
  readonly target: EditWriteTarget;
  readonly repository: RepositoryState;
}

export interface ProcessResult {
  readonly stdout: string;
  readonly stderr: string;
  readonly code: number;
}

export type GitRootResult =
  | { readonly kind: "inside"; readonly root: string }
  | { readonly kind: "outside" }
  | { readonly kind: "invalid"; readonly diagnostic: string };

export interface PolicyCapabilities {
  readonly filesystem: {
    homeDirectory(): string;
    canonicalize(target: string, cwd: string): Promise<string>;
    inspectionDirectory(target: string): Promise<string>;
  };
  readonly git: {
    root(directory: string): Promise<GitRootResult>;
    head(root: string): Promise<ProcessResult>;
  };
  readonly jj: {
    run(argv: readonly string[], cwd: string): Promise<ProcessResult>;
  };
  readonly notification: {
    // Pi's ui.notify is a no-op whenever the host has no dialog-capable UI
    // (core/extensions/runner.ts noOpUIContext), so a print-mode session
    // announces nothing. That is the accepted cost of never stalling: notify
    // is fire-and-forget in every mode and can therefore never deadlock.
    notify(message: string): void;
  };
}

export interface ToolCallEvent {
  readonly toolName: string;
  readonly input: unknown;
}

export interface ToolCallContext {
  readonly cwd: string;
  readonly ui: {
    notify(message: string, type?: "info" | "warning" | "error"): void;
  };
}

export type ToolCallResult = { readonly block: true; readonly reason: string } | undefined;

export type DecisionFunction = (input: EditWriteInput) => PolicyDecision;
export type CapabilityFactory = (context: ToolCallContext) => PolicyCapabilities;

const jjRead = (...args: string[]): readonly string[] => ["jj", "--ignore-working-copy", ...args];

export const JJ_READ_ARGV = {
  root: jjRead("root"),
  current: jjRead(
    "log",
    "-r",
    "@",
    "--no-graph",
    "-T",
    'change_id ++ "\\t" ++ commit_id ++ "\\t" ++ conflict ++ "\\t" ++ empty ++ "\\t" ++ parents.len() ++ "\\n"',
  ),
  currentIdentity: (changeId: string) =>
    jjRead("log", "-r", changeId, "--no-graph", "-T", 'commit_id ++ "\\n"'),
  defaultBookmarks: jjRead(
    "bookmark",
    "list",
    "exact:main",
    "exact:master",
    "-T",
    'if(!remote, added_targets.map(|c| name ++ "\\t" ++ c.commit_id() ++ "\\n").join(""))',
  ),
  classifyWip: jjRead(
    "bookmark",
    "list",
    "exact:wip",
    "-T",
    'if(!remote, name ++ "\\t" ++ conflict ++ "\\n")',
  ),
  resolveWip: jjRead(
    "bookmark",
    "list",
    "exact:wip",
    "-T",
    'if(!remote, added_targets.map(|c| c.commit_id() ++ "\\t" ++ conflict ++ "\\n").join(""))',
  ),
  join: jjRead(
    "log",
    "-r",
    "@-",
    "--no-graph",
    "-T",
    'commit_id ++ "\\t" ++ conflict ++ "\\t" ++ empty ++ "\\t" ++ parents.len() ++ "\\n"',
  ),
  parents: jjRead(
    "log",
    "-r",
    "parents(@-)",
    "--no-graph",
    "-T",
    'commit_id ++ "\\t" ++ conflict ++ "\\n"',
  ),
} as const;

const block = (reason: string): PolicyDecision => ({ decision: "block", reason });
const notify = (reason: string): PolicyDecision => ({ decision: "notify", reason });
const allow = (): PolicyDecision => ({ decision: "allow" });

const containsPath = (root: string, target: string): boolean => {
  const suffix = relative(root, target);
  return (
    suffix === "" || (suffix !== ".." && !suffix.startsWith(`..${sep}`) && !isAbsolute(suffix))
  );
};

const unreachable = (state: never): never => {
  throw new Error(`unhandled repository state: ${JSON.stringify(state)}`);
};

// Containment is the one jj condition that stays refusing: it means the probe
// resolved a repository the target does not live in, so version control is not
// covering the file about to change.
const validateJjCommon = (state: JjCommonState, target: string): PolicyDecision | undefined => {
  if (!containsPath(state.root, target)) {
    return block("jj repository identity does not contain the canonical target");
  }
  if (state.at.conflicted) return notify("jj current change is conflicted");
  if (state.at.divergent) return notify("jj current change identity is divergent");
  if (state.defaultBookmarksAtCurrent.length > 0) {
    return notify(
      `jj current change carries protected bookmark ${state.defaultBookmarksAtCurrent.join(", ")}`,
    );
  }
  return undefined;
};

export function decideEditWrite(input: EditWriteInput): PolicyDecision {
  const repository = input.repository;
  const target = input.target.canonicalPath;
  switch (repository.kind) {
    case "outside-repository":
      // No repository holds this path, so no history would return it. This is
      // the same hazard the containment refusals cover, reached by a different
      // route.
      return block(
        `${input.operation} targets a path outside a recognized repository, where version control cannot recover it`,
      );
    case "git":
      if (!containsPath(repository.root, target)) {
        return block("Git repository identity does not contain the canonical target");
      }
      if (repository.head.kind === "protected") {
        return notify(`Mutation on protected Git branch ${repository.head.branch}`);
      }
      return allow();
    case "jj-ordinary": {
      const unhealthy = validateJjCommon(repository, target);
      return unhealthy ?? allow();
    }
    case "jj-diamond": {
      const unhealthy = validateJjCommon(repository, target);
      if (unhealthy !== undefined) return unhealthy;
      if (repository.wip.kind !== "healthy") {
        return notify(`diamond wip bookmark is ${repository.wip.kind}`);
      }
      if (repository.at.parentCount !== 1) {
        return notify("diamond wip does not have exactly one parent");
      }
      if (repository.join.conflicted) return notify("diamond join is conflicted");
      if (repository.join.parentCount < 2) {
        return notify("diamond join has fewer than two parents");
      }
      if (repository.join.parentsConflicted) {
        return notify("diamond join has a conflicted immediate parent");
      }
      return allow();
    }
    case "invalid":
      // Fail open. A probe this policy could not parse says nothing about
      // whether the mutation is safe, and the two defects that made this arm
      // fire in practice -- a jj release adding a Hint line, an agent whose
      // edit tool carries no path field -- were both environmental. Refusing
      // on them cost every edit in the affected repositories and prevented no
      // unsafe write. The classification still carries its diagnostic so the
      // probe parsers stay observable to the policy check.
      return allow();
    default:
      return unreachable(repository);
  }
}

const strictOutputLines = (text: string): readonly string[] | undefined => {
  if (text.length === 0) return [];
  if (!text.endsWith("\n")) return undefined;
  const lines = text.slice(0, -1).split("\n");
  return lines.some((line) => line.length === 0 || line.trim() !== line) ? undefined : lines;
};

const parseBoolean = (value: string): boolean | undefined => {
  if (value === "true") return true;
  if (value === "false") return false;
  return undefined;
};

const singleOutputLine = (output: string): string | undefined => {
  const normalized = output.replaceAll("\r\n", "\n");
  const line = normalized.endsWith("\n") ? normalized.slice(0, -1) : normalized;
  if (line.length === 0 || line.includes("\n") || line.includes("\r") || line.trim() !== line) {
    return undefined;
  }
  return line;
};

const validGitBranch = (branch: string): boolean => {
  const forbidden = ["~", "^", ":", "?", "*", "[", "\\"];
  const components = branch.split("/");
  return (
    branch !== "HEAD" &&
    !branch.startsWith("-") &&
    !branch.startsWith("/") &&
    !branch.endsWith("/") &&
    !branch.endsWith(".") &&
    !branch.includes("..") &&
    !branch.includes("@{") &&
    !branch.includes("//") &&
    !/[\u0000-\u0020\u007f]/u.test(branch) &&
    !forbidden.some((character) => branch.includes(character)) &&
    components.every(
      (component) =>
        component.length > 0 &&
        component !== "." &&
        component !== ".." &&
        !component.endsWith(".lock"),
    )
  );
};

const parseGitHead = (result: ProcessResult): GitHead | string => {
  if (result.code === 1 && result.stdout.length === 0 && result.stderr.length === 0) {
    return { kind: "detached" };
  }
  if (result.code !== 0) {
    return `Git head probe failed (${result.code}): ${result.stderr.trim()}`;
  }
  const branch = singleOutputLine(result.stdout);
  if (branch === undefined || !validGitBranch(branch)) return "Git head probe is malformed";
  if (branch === "main" || branch === "master") return { kind: "protected", branch };
  return { kind: "feature", branch };
};

interface CurrentRecord {
  readonly changeId: string;
  readonly commitId: string;
  readonly conflicted: boolean;
  // Validated as part of the probe's strict column shape — a non-boolean here
  // makes the probe malformed — but deliberately never consulted by a decision:
  // neither @ nor @- may be required to be empty, and diamond health imposes no
  // working-copy-cleanliness requirement. Not dead code; dropping it would
  // loosen the template's shape check and invite the emptiness gate this policy
  // must not have.
  readonly empty: boolean;
  readonly parentCount: number;
}

const parseCurrent = (result: ProcessResult): CurrentRecord | string => {
  if (result.code !== 0) {
    return `jj current probe failed (${result.code}): ${result.stderr.trim()}`;
  }
  const lines = strictOutputLines(result.stdout);
  if (lines === undefined) return "jj current probe is malformed";
  if (lines.length !== 1) return "jj current probe is ambiguous";
  const fields = lines[0].split("\t");
  if (fields.length !== 5) return "jj current probe is malformed";
  const conflicted = parseBoolean(fields[2]);
  const empty = parseBoolean(fields[3]);
  const parentCount = Number.parseInt(fields[4], 10);
  if (
    fields[0].length === 0 ||
    fields[1].length === 0 ||
    conflicted === undefined ||
    empty === undefined ||
    !/^\d+$/.test(fields[4]) ||
    !Number.isSafeInteger(parentCount)
  ) {
    return "jj current probe is malformed";
  }
  return {
    changeId: fields[0],
    commitId: fields[1],
    conflicted,
    empty,
    parentCount,
  };
};

interface JoinRecord {
  readonly commitId: string;
  readonly conflicted: boolean;
  // Shape-validated, never consulted; see CurrentRecord.empty.
  readonly empty: boolean;
  readonly parentCount: number;
}

const parseJoin = (result: ProcessResult): JoinRecord | string => {
  if (result.code !== 0) {
    return `jj join probe failed (${result.code}): ${result.stderr.trim()}`;
  }
  const lines = strictOutputLines(result.stdout);
  if (lines === undefined || lines.length !== 1) return "jj join probe is malformed or ambiguous";
  const fields = lines[0].split("\t");
  if (fields.length !== 4) return "jj join probe is malformed";
  const conflicted = parseBoolean(fields[1]);
  const empty = parseBoolean(fields[2]);
  const parentCount = Number.parseInt(fields[3], 10);
  if (
    fields[0].length === 0 ||
    conflicted === undefined ||
    empty === undefined ||
    !/^\d+$/.test(fields[3]) ||
    !Number.isSafeInteger(parentCount)
  ) {
    return "jj join probe is malformed";
  }
  return { commitId: fields[0], conflicted, empty, parentCount };
};

const invalid = (diagnostic: string): RepositoryState => ({
  kind: "invalid",
  diagnostic,
});

// Both diagnostics match a prefix rather than the whole of stderr, because both
// tools append advice after the error line. jj 0.43.0 emits, whenever the probed
// directory holds a `.git` directory:
//
//   Error: There is no jj repo in "."
//   Hint: It looks like this is a git repo. You can create a jj repo backed by it by running this:
//   jj git init
//
// which is precisely the case that has to fall through to the Git branch below.
// Anchoring the match at the end of stderr made that fall-through unreachable at
// the root of every ordinary Git repository, so the Git arm of decideEditWrite
// was dead code exactly where it was meant to apply. The exit-code and
// empty-stdout conjuncts are kept: they are what distinguishes this diagnostic
// from a probe that failed some other way.
const JJ_OUTSIDE_REPOSITORY_DIAGNOSTIC = /^Error: There is no jj repo in "[^"\r\n]+"\n/;
const GIT_OUTSIDE_REPOSITORY_DIAGNOSTIC =
  "fatal: not a git repository (or any of the parent directories): .git\n";

const isCharacterizedJjOutsideRepository = (result: ProcessResult): boolean =>
  result.code === 1 &&
  result.stdout.length === 0 &&
  JJ_OUTSIDE_REPOSITORY_DIAGNOSTIC.test(result.stderr);

export const parseGitRootResult = (result: ProcessResult): GitRootResult => {
  if (result.code === 0) {
    const root = singleOutputLine(result.stdout);
    return root !== undefined && isAbsolute(root)
      ? { kind: "inside", root }
      : { kind: "invalid", diagnostic: "Git root probe is malformed or ambiguous" };
  }
  if (
    result.code === 128 &&
    result.stdout.length === 0 &&
    result.stderr.startsWith(GIT_OUTSIDE_REPOSITORY_DIAGNOSTIC)
  ) {
    return { kind: "outside" };
  }
  return {
    kind: "invalid",
    diagnostic: `Git root probe failed (${result.code}): ${result.stderr.trim()}`,
  };
};

const readProbeLines = async (
  capabilities: PolicyCapabilities,
  argv: readonly string[],
  cwd: string,
  label: string,
): Promise<readonly string[] | string> => {
  const result = await capabilities.jj.run(argv, cwd);
  if (result.code !== 0) {
    return `jj ${label} probe failed (${result.code}): ${result.stderr.trim()}`;
  }
  const lines = strictOutputLines(result.stdout);
  return lines === undefined ? `jj ${label} probe is malformed` : lines;
};

const inspectJj = async (
  root: string,
  target: string,
  cwd: string,
  capabilities: PolicyCapabilities,
): Promise<RepositoryState> => {
  if (!containsPath(root, target)) {
    return invalid("canonical jj root does not contain the canonical target");
  }

  const currentResult = await capabilities.jj.run(JJ_READ_ARGV.current, cwd);
  const current = parseCurrent(currentResult);
  if (typeof current === "string") return invalid(current);

  const identities = await readProbeLines(
    capabilities,
    JJ_READ_ARGV.currentIdentity(current.changeId),
    cwd,
    "current identity",
  );
  if (typeof identities === "string") return invalid(identities);
  if (identities.length === 0) return invalid("jj current identity probe is empty");
  const divergent = identities.length !== 1 || identities[0] !== current.commitId;

  const defaultBookmarkLines = await readProbeLines(
    capabilities,
    JJ_READ_ARGV.defaultBookmarks,
    cwd,
    "default bookmark",
  );
  if (typeof defaultBookmarkLines === "string") return invalid(defaultBookmarkLines);
  const defaultBookmarksAtCurrent: ("main" | "master")[] = [];
  for (const line of defaultBookmarkLines) {
    const fields = line.split("\t");
    if (
      fields.length !== 2 ||
      (fields[0] !== "main" && fields[0] !== "master") ||
      fields[1].length === 0
    ) {
      return invalid("jj default bookmark probe is malformed");
    }
    if (fields[1] === current.commitId) defaultBookmarksAtCurrent.push(fields[0]);
  }

  const common: JjCommonState = {
    root,
    at: {
      conflicted: current.conflicted,
      divergent,
      parentCount: current.parentCount,
    },
    defaultBookmarksAtCurrent,
  };

  const classification = await readProbeLines(
    capabilities,
    JJ_READ_ARGV.classifyWip,
    cwd,
    "wip classification",
  );
  if (typeof classification === "string") return invalid(classification);
  if (classification.length === 0) {
    return { kind: "jj-ordinary", ...common };
  }
  if (classification.length !== 1) {
    return invalid("jj wip classification probe is ambiguous");
  }
  const classificationFields = classification[0].split("\t");
  const classificationDivergent = parseBoolean(classificationFields[1] ?? "");
  if (
    classificationFields.length !== 2 ||
    classificationFields[0] !== "wip" ||
    classificationDivergent === undefined
  ) {
    return invalid("jj wip classification probe is malformed");
  }

  const resolutionLines = await readProbeLines(
    capabilities,
    JJ_READ_ARGV.resolveWip,
    cwd,
    "wip resolution",
  );
  if (typeof resolutionLines === "string") return invalid(resolutionLines);
  const resolutionRecords = resolutionLines.map((line) => line.split("\t"));
  const malformedResolution = resolutionRecords.some(
    (fields) =>
      fields.length !== 2 || fields[0].length === 0 || parseBoolean(fields[1]) === undefined,
  );
  if (malformedResolution) return invalid("jj wip resolution probe is malformed");

  let wip: WipState;
  if (classificationDivergent) {
    wip = { kind: "divergent" };
  } else if (resolutionRecords.length === 0) {
    wip = { kind: "absent" };
  } else if (
    resolutionRecords.length !== 1 ||
    resolutionRecords.some((fields) => parseBoolean(fields[1]) === true)
  ) {
    wip = { kind: "divergent" };
  } else if (resolutionRecords[0][0] !== current.commitId) {
    wip = { kind: "moved" };
  } else {
    wip = { kind: "healthy" };
  }

  const joinResult = await capabilities.jj.run(JJ_READ_ARGV.join, cwd);
  const join = parseJoin(joinResult);
  if (typeof join === "string") return invalid(join);

  const parentLines = await readProbeLines(
    capabilities,
    JJ_READ_ARGV.parents,
    cwd,
    "immediate parent",
  );
  if (typeof parentLines === "string") return invalid(parentLines);
  let parentsConflicted = false;
  for (const line of parentLines) {
    const fields = line.split("\t");
    const conflicted = parseBoolean(fields[1] ?? "");
    if (fields.length !== 2 || fields[0].length === 0 || conflicted === undefined) {
      return invalid("jj immediate parent probe is malformed");
    }
    parentsConflicted ||= conflicted;
  }

  if (parentLines.length !== join.parentCount) {
    return invalid("jj immediate parent probe count does not match the join");
  }

  return {
    kind: "jj-diamond",
    ...common,
    wip,
    join: {
      conflicted: join.conflicted,
      parentCount: join.parentCount,
      parentsConflicted,
    },
  };
};

export async function inspectRepository(
  target: string,
  inspectionDirectory: string,
  capabilities: PolicyCapabilities,
): Promise<RepositoryState> {
  if (!isAbsolute(inspectionDirectory) || !containsPath(inspectionDirectory, target)) {
    return invalid("repository inspection directory does not contain the canonical target");
  }

  const jjRootResult = await capabilities.jj.run(JJ_READ_ARGV.root, inspectionDirectory);
  let jjRoot: string | undefined;
  if (jjRootResult.code === 0) {
    const roots = strictOutputLines(jjRootResult.stdout);
    if (roots === undefined || roots.length !== 1 || !isAbsolute(roots[0])) {
      return invalid("jj root probe is malformed or ambiguous");
    }
    jjRoot = await capabilities.filesystem.canonicalize(roots[0], inspectionDirectory);
  } else if (!isCharacterizedJjOutsideRepository(jjRootResult)) {
    return invalid(`jj root probe failed (${jjRootResult.code}): ${jjRootResult.stderr.trim()}`);
  }

  const gitRootResult = await capabilities.git.root(inspectionDirectory);
  if (gitRootResult.kind === "invalid") return invalid(gitRootResult.diagnostic);
  const gitRoot =
    gitRootResult.kind === "inside"
      ? await capabilities.filesystem.canonicalize(gitRootResult.root, inspectionDirectory)
      : undefined;

  if (jjRoot !== undefined && gitRoot !== undefined && jjRoot !== gitRoot) {
    return invalid("ambiguous Git and jj repository identities");
  }
  if (jjRoot !== undefined) {
    return inspectJj(jjRoot, target, inspectionDirectory, capabilities);
  }
  if (gitRoot !== undefined) {
    if (!containsPath(gitRoot, target)) {
      return invalid("canonical Git root does not contain the canonical target");
    }
    const head = parseGitHead(await capabilities.git.head(gitRoot));
    if (typeof head === "string") return invalid(head);
    return { kind: "git", root: gitRoot, head };
  }
  return { kind: "outside-repository" };
}

export const MALFORMED_TOOL_INPUT_REASON =
  "malformed edit/write tool input: path must be a nonempty string";

export async function evaluateEditWrite(
  operation: EditWriteOperation,
  target: string,
  cwd: string,
  capabilities: PolicyCapabilities,
  decide: DecisionFunction = decideEditWrite,
): Promise<PolicyDecision> {
  let input: EditWriteInput;
  try {
    const normalized = normalizeToolPath(target, capabilities.filesystem.homeDirectory());
    if (normalized === undefined) return block(MALFORMED_TOOL_INPUT_REASON);
    const canonicalPath = await capabilities.filesystem.canonicalize(normalized, cwd);
    const inspectionDirectory = await capabilities.filesystem.inspectionDirectory(canonicalPath);
    const repository = await inspectRepository(canonicalPath, inspectionDirectory, capabilities);
    input = { operation, target: { canonicalPath }, repository };
  } catch (error) {
    // Fail open, as for an unparseable probe: a capability that threw has not
    // established that the mutation is unsafe.
    void error;
    return allow();
  }

  let decision: PolicyDecision;
  try {
    decision = decide(input);
  } catch (error) {
    void error;
    return allow();
  }

  if (decision.decision !== "notify") return decision;
  try {
    capabilities.notification.notify(`${operation}: ${decision.reason}`);
  } catch (error) {
    // A host that cannot display the announcement must not turn a permitted
    // mutation into a refused one.
    void error;
  }
  return decision;
}

// Mirrors Pi's resolveToCwd normalization (core/tools/path-utils.ts calling
// utils/paths.ts normalizePath with normalizeUnicodeSpaces and stripAtPrefix,
// expandTilde defaulting on) in the same order Pi applies it. The policy has to
// canonicalize the string Pi will actually open: resolving "~/secret" as a
// cwd-relative path put it inside the repository and permitted a write that
// really landed in the home directory. The Windows shell-path arm of Pi's
// normalizePath is omitted; this policy is deployed only to darwin and linux.
// atomic's resolveToCwd additionally passes the result through mapPathForCwd
// (core/resume/path-mapping.js), which moves a path under a checkout root that
// a resume restored into a snapshot worktree to the same place in that
// worktree. That remap is not mirrored: a session cwd inside such a worktree
// makes the policy judge the original checkout's path instead.
const UNICODE_SPACES = /[\u00A0\u2000-\u200A\u202F\u205F\u3000]/g;

export const normalizeToolPath = (target: string, homeDirectory: string): string | undefined => {
  let normalized = target.replace(UNICODE_SPACES, " ");
  if (normalized.startsWith("@")) normalized = normalized.slice(1);
  if (normalized === "~") return homeDirectory;
  if (normalized.startsWith("~/")) return join(homeDirectory, normalized.slice(2));
  if (/^file:\/\//.test(normalized)) {
    try {
      return fileURLToPath(normalized);
    } catch {
      return undefined;
    }
  }
  return normalized.trim().length > 0 ? normalized : undefined;
};

const canonicalizePath = async (target: string, cwd: string): Promise<string> => {
  const absolute = resolve(cwd, target);
  try {
    return await realpath(absolute);
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code !== "ENOENT") throw error;
    const parent = dirname(absolute);
    if (parent === absolute) throw error;
    return join(await canonicalizePath(parent, "/"), basename(absolute));
  }
};

const runProcess = (argv: readonly string[], cwd: string): Promise<ProcessResult> =>
  new Promise((complete) => {
    execFile(argv[0], argv.slice(1), { cwd, encoding: "utf8" }, (error, stdout, stderr) => {
      const numericCode =
        error === null
          ? 0
          : typeof (error as NodeJS.ErrnoException).code === "number"
            ? ((error as NodeJS.ErrnoException).code as number)
            : 127;
      complete({ stdout, stderr, code: numericCode });
    });
  });

const deepestExistingDirectory = async (target: string): Promise<string> => {
  const candidate = dirname(target);
  try {
    const canonical = await realpath(candidate);
    if (!(await stat(canonical)).isDirectory()) {
      throw new Error(`repository inspection ancestor is not a directory: ${canonical}`);
    }
    return canonical;
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code !== "ENOENT") throw error;
    if (dirname(candidate) === candidate) throw error;
    return deepestExistingDirectory(candidate);
  }
};

const defaultGitRoot = async (directory: string): Promise<GitRootResult> =>
  parseGitRootResult(
    await runProcess(["git", "-C", directory, "rev-parse", "--show-toplevel"], directory),
  );

const defaultGitHead = (root: string): Promise<ProcessResult> =>
  runProcess(["git", "-C", root, "symbolic-ref", "--quiet", "--short", "HEAD"], root);

export const createNodePolicyCapabilities: CapabilityFactory = (context) => ({
  filesystem: {
    homeDirectory: homedir,
    canonicalize: canonicalizePath,
    inspectionDirectory: deepestExistingDirectory,
  },
  git: {
    root: defaultGitRoot,
    head: defaultGitHead,
  },
  jj: {
    run: runProcess,
  },
  notification: {
    notify: (message) => context.ui.notify(message, "warning"),
  },
});

// Extraction only; normalizeToolPath owns every rewrite of the string, so that
// the value this policy canonicalizes and the value the tool opens are produced
// by one implementation. The predicate rejects a whitespace-only path here
// rather than letting resolve() map it to a directory under cwd.
//
// This shape is Pi's: both `edit` and `write` declare a required top-level
// `path` string. From atomic 0.9.72 atomic's `edit` is Pi's `path` + `edits[]`
// tool too, so the same extraction serves both agents.
const parseToolInput = (input: unknown): string | undefined => {
  if (input === null || typeof input !== "object") return undefined;
  const path = (input as { readonly path?: unknown }).path;
  if (typeof path !== "string") return undefined;
  return path.trim().length > 0 ? path : undefined;
};

// atomic 0.9.87's `write` (core/tools/write-selectors.js withWriteSelectors)
// takes `local://<rest>` before Pi's path handling and writes `<rest>` resolved
// under the call's cwd (resource-selectors.js fallbackInternalPath, `.+` after
// the scheme), refusing a `<rest>` that escapes cwd. Judging the raw string
// instead resolved `<cwd>/local:/<rest>`, a path no tool writes. Its other
// redirections need nothing here: archive members and SQLite rows are files
// named before the `:` under cwd, `conflict://` rewrites conflicted files under
// cwd, and `skill`, `artifact`, `history` and `tool-output` URLs are read-only.
// Pi's `write` has no `local://` and writes the literal `<cwd>/local:/<rest>`,
// which lies in the same directory tree, so judging `<rest>` serves both.
const LOCAL_URL = /^local:\/\/(.+)$/;

const writeTarget = (target: string, cwd: string): string | undefined => {
  if (!target.startsWith("local://")) return target;
  const rest = LOCAL_URL.exec(target)?.[1];
  return rest === undefined ? undefined : resolve(cwd, rest);
};

export function createEditWriteToolCallHandler(
  capabilities: CapabilityFactory = createNodePolicyCapabilities,
  options: { readonly decide?: DecisionFunction } = {},
): (event: ToolCallEvent, context: ToolCallContext) => Promise<ToolCallResult> {
  return async (event, context) => {
    if (event.toolName !== "edit" && event.toolName !== "write") return undefined;
    const path = parseToolInput(event.input);
    const target =
      path !== undefined && event.toolName === "write" ? writeTarget(path, context.cwd) : path;
    // The one refusal that survives an unreadable request rather than an
    // unrecoverable target: a tool call whose path this policy cannot read is a
    // call it cannot reason about at all, and letting it through would mean
    // permitting an unexamined mutation rather than an examined one.
    if (target === undefined) return { block: true, reason: MALFORMED_TOOL_INPUT_REASON };

    try {
      const decision = await evaluateEditWrite(
        event.toolName,
        target,
        context.cwd,
        capabilities(context),
        options.decide,
      );
      return decision.decision === "block" ? { block: true, reason: decision.reason } : undefined;
    } catch (error) {
      // Fail open on an adapter fault for the same reason the decision core
      // does: a thrown capability has established nothing about the mutation.
      void error;
      return undefined;
    }
  };
}

export default function editWritePolicy(pi: ExtensionAPI): void {
  pi.on("tool_call", createEditWriteToolCallHandler());
}
