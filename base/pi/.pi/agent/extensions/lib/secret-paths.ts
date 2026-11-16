/**
 * Secret-path gate — class (b): a credential read into the model's context.
 *
 * The gap it closes, measured 2026-11-16 (probe E, docs/AGENT-SAFETY.md §3):
 * L3 (cc-safety-net) blocks `read`/`hypa_read` of `~/.ssh/id_ed25519` by *input
 * shape*, but `secrets/env.fish` is not in its secret list — the file is
 * git-crypt'd, not `.env`-shaped — so an agent read of this repo's credential
 * store is ALLOWED. One read puts every value in the transcript, and from there
 * into whatever gets published next (which is L4's problem).
 *
 * So L2 gates a second thing (docs/AGENT-SAFETY.md §2 L2, §2.1a): the FILE
 * tools, whose input carries a path. Shell commands are deliberately NOT gated
 * here — the shell is L2's classifier and L3's secret rules, and blocking
 * `grep secrets/leak-patterns` would break this repo's own `check.sh` and
 * pre-commit hook, which scan with exactly that command.
 *
 * The rule, and nothing wider: a path resolving under a directory named
 * `secrets` is a credential store, except the basenames in SECRET_ALLOWLIST.
 * Component matching is exact and case-insensitive — `secrets/`, `SECRETS/`
 * (APFS usually resolves both to the same inode) are secret paths, while
 * `secrets-notes.md`, `notsecrets/x` and a bare `env.fish` outside one are not.
 *
 * pi-free and IO-free, so it runs standalone under
 * `node --experimental-strip-types --test` (see ./secret-paths.test.ts). The
 * wiring is three lines in ../infra-safety.ts, mirroring
 * publish-guard.ts ↔ lib/publish-scan.ts.
 *
 * Fail-closed: a path this module cannot resolve (a non-string, or a relative
 * path with no usable cwd) is a DENY. An ABSENT path however is not this
 * check's business — `secretPathBlock` returns null and the tool decides.
 *
 * Known boundary, stated rather than papered over: resolution is lexical, so a
 * symlink that points into a `secrets/` directory is not followed, and the
 * decision is made on the path as typed. A caller that cares about symlinks
 * must `realpath` before asking. `ls` is not gated either, by design: it
 * returns names, not contents.
 */

import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";

/** The directory name that marks a credential store, matched as a component. */
export const SECRETS_DIRNAME = "secrets";

/**
 * Basenames readable even under `secrets/`. `leak-patterns` is the identifier
 * corpus (`check.sh` and `.githooks/pre-commit` scan with it): it names
 * internal hosts and customer identifiers, not credentials, so denying it
 * would break the scanners to protect nothing.
 */
export const SECRET_ALLOWLIST = ["leak-patterns"] as const;

/**
 * The FILE tools whose input carries a path — the complete list of what this
 * gate listens on. `read`/`grep`/`find`/`edit`/`write` are pi's built-ins,
 * `hypa_*` is pi-hypa's same-shaped replacements, and both are named for the
 * reason `SHELL_TOOLS` names both shells: a gate wired to one harness's names
 * only is bypassed by the other. Shell tools belong to the classifier, never
 * here (see the header).
 */
export const FILE_PATH_TOOLS = [
  "read",
  "hypa_read",
  "grep",
  "hypa_grep",
  "find",
  "hypa_find",
  "edit",
  "write",
] as const;

export type FilePathTool = (typeof FILE_PATH_TOOLS)[number];

const FILE_PATH_TOOL_SET: ReadonlySet<string> = new Set<string>(FILE_PATH_TOOLS);

const ALLOW: ReadonlySet<string> = new Set(SECRET_ALLOWLIST.map((name) => name.toLowerCase()));

/** Both separators: a Windows-shaped path is still recognised on any host. */
const SEPARATORS = /[\\/]+/;

/** Longest path echoed back in a block reason. */
const MAX_LABEL = 120;

/** True when `name` is a file-path tool this gate listens on. */
export function isFilePathTool(name: string): boolean {
  return FILE_PATH_TOOL_SET.has(name);
}

/**
 * True when `path` resolves under a directory named `secrets` and is not on the
 * allowlist. `cwd` is the session working directory, used for relative paths.
 *
 * Deny (true) is also the answer when the decision cannot be made: a non-string
 * path, or a relative path with no usable cwd.
 */
export function isSecretPath(path: string, cwd: string): boolean {
  if (typeof path !== "string") return true;

  const expanded = expandHome(path);
  if (typeof cwd !== "string" || cwd.length === 0) {
    // An absolute path needs no anchor, so it is still decidable.
    if (!isAbsolute(expanded)) return true;
  }

  let abs: string;
  try {
    abs = isAbsolute(expanded) ? resolve(expanded) : resolve(cwd, expanded);
  } catch {
    return true; // cannot resolve to decide ⇒ fail closed
  }

  const parts = abs
    .split(SEPARATORS)
    .filter((part) => part.length > 0)
    .map((part) => part.toLowerCase());

  if (!parts.includes(SECRETS_DIRNAME)) return false;
  return !ALLOW.has(parts[parts.length - 1] ?? "");
}

/**
 * The `tool_call` decision for one file-tool call: null to let it through, or
 * the block (with its reason) to return from the handler.
 *
 * Absent/unparseable input is NOT a block — a file tool with no path is not
 * this check's business, and inventing a deny there would break calls that
 * merely omit the default-cwd argument.
 */
export function secretPathBlock(
  toolName: string,
  input: unknown,
  cwd: string,
): { block: true; reason: string } | null {
  if (!isFilePathTool(toolName)) return null;
  const path = (input as { path?: unknown } | null | undefined)?.path;
  if (typeof path !== "string") return null;
  if (!isSecretPath(path, cwd)) return null;
  return { block: true, reason: reasonFor(toolName, path) };
}

/**
 * The block reason: names the rule and the path, never the file's contents (and
 * nothing recalled from it) — the point of the block is that a value must not
 * reach the transcript, so the message must not be a second copy of one.
 */
function reasonFor(toolName: string, path: string): string {
  return (
    `secret-path: blocked — ${toolName} on ${label(path)}. Paths under a directory named ` +
    `"${SECRETS_DIRNAME}" are credential stores: reading one puts every value in the transcript, and ` +
    `from there into whatever is published next. The only readable basename there is ` +
    `${SECRET_ALLOWLIST.join(", ")} (the scanners' identifier corpus, which holds no credentials). ` +
    `To use a value, run one command in a shell with \`creds <cmd>\`.`
  );
}

/** The path as typed, flattened and bounded: a caller-controlled string, so it
 *  is never echoed raw (newlines would forge lines in the transcript). */
function label(path: string): string {
  const flat = path.replace(/[\r\n\t]+/g, " ").trim();
  return flat.length > MAX_LABEL ? `${flat.slice(0, MAX_LABEL)}…` : flat;
}

/** `~/x` and `~x`-free forms, without touching the filesystem. */
function expandHome(path: string): string {
  if (path === "~") return homedir();
  if (path.startsWith("~/") || path.startsWith("~\\")) return resolve(homedir(), path.slice(2));
  return path;
}
