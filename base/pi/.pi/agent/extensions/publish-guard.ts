/**
 * Publish Guard Extension — class (c): a credential in a published artifact.
 *
 * The gap it closes (docs/AGENT-SAFETY.md §2 L4, incident: a work-repo PR
 * body): a credential already sitting in the model's context can be pasted into
 * anything that leaves the machine — `gh pr create --body …`, a gist, a release
 * note, a fetched URL, a search query. No dependency covers it: cc-safety-net
 * guards file ACCESS, and `.githooks/pre-commit` only scans this repo's staged
 * files after the fact.
 *
 * Two questions, one decision:
 *   1. Is this call publishing outgoing text?  SHELL_TOOL_SET (lib/shell-tools.ts)
 *      + the publish verbs of gh/glab (lib/publish-scan.ts: publishTargets); or a
 *      web tool, which publishes its own arguments by definition.
 *   2. Does that text carry a known credential?  gitleaks' default rules over
 *      the same text, plus exact values from secrets/env.fish.
 *
 * This file is only the pi wiring + IO: process spawn, file reads, notify. All
 * matching/decision logic (and its unit tests) live in ./lib/publish-scan.ts,
 * mirroring infra-safety.ts ↔ lib/mutation-guard.ts. The wiring is exercised
 * directly by ./lib/publish-guard.test.ts through `createOnToolCall()`.
 *
 * Fail-closed — every one of these BLOCKS, because a guard that cannot see must
 * not let text out: a call the classifier could not read, a scanner that is
 * missing / errors / times out / rejects its input, a referenced file that
 * cannot be read, a command substitution whose output cannot be resolved
 * (`--body "$(date)"`), a relative file path behind `cd`/`pushd`, and a
 * secrets/env.fish that is unreadable or git-crypt locked (the exact-value half
 * would be silently skipped otherwise). The block reason names the rule, the
 * flag or the variable — never the matched value or the path we were given — so
 * the secret is not copied into the transcript again.
 *
 * Dependency: `gitleaks` on PATH (mise: aqua:gitleaks/gitleaks). Absent ⇒ every
 * publish and web call is blocked, loudly, until it is installed.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { execFile } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { isAbsolute, resolve } from "node:path";
import { publishTargets, scan, type LeakScan } from "./lib/publish-scan.ts";
import { SHELL_TOOL_SET } from "./lib/shell-tools.ts";

/** Web tools publish their arguments; these are the fields that leave the host. */
const WEB_TOOL_FIELDS: Record<string, readonly string[]> = {
  fetch_content: ["url", "urls", "prompt"],
  web_search: ["query", "queries"],
};

/** gitleaks: JSON report to stdout, secrets redacted in it, no banner. Exit 1
 *  means "leaks found" and is handled as a normal result, not an error. */
const GITLEAKS_ARGS = ["stdin", "--report-format", "json", "--report-path", "-", "--redact", "--no-banner"];
const SCAN_TIMEOUT_MS = 5000;
const MAX_FILE_BYTES = 2 * 1024 * 1024; // a publishable file bigger than this is refused, not truncated

/** Canonical secret store; git-crypt filtered. Same path `creds` uses. */
const SECRETS_FILE = resolve(homedir(), "dotfiles", "secrets", "env.fish");
/** Display name for block reasons: the repo path, not the absolute one. */
const SECRETS_LABEL = "secrets/env.fish";

/** The IO the wiring needs, overridable so the wiring itself is testable. */
export interface GuardOptions {
  secretsPath: string;
  /** Read the secret store. Throwing means "cannot read" — a block. */
  readSecretsFile: (path: string) => string;
  gitleaksBin: string;
  scanTimeoutMs: number;
}

export const DEFAULT_GUARD_OPTIONS: GuardOptions = {
  secretsPath: SECRETS_FILE,
  readSecretsFile: (path) => readFileSync(path, "utf-8"),
  gitleaksBin: "gitleaks",
  scanTimeoutMs: SCAN_TIMEOUT_MS,
};

interface Targets {
  /** Text the tool will send, as typed. */
  text: string;
  /** Files whose content is published — fail-closed. */
  files: string[];
  /** The flag/form that named each file (aligned with `files`). */
  sources: string[];
  /** `$NAME` variables the command expands. */
  vars: string[];
  /** Path-shaped bare tokens — scanned when readable, ignored otherwise. */
  candidates: string[];
  /** Substitutions whose output could not be resolved — a block. */
  unresolved: string[];
  /** Relative file references in a command that runs cd/pushd — a block. */
  cwdRelative: string[];
  /** "unknown": a gh/glab write we could not classify, still a target. */
  scope: "known" | "unknown";
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", createOnToolCall());
}

/**
 * The `tool_call` handler, with its IO injectable so the wiring's fail-closed
 * behaviour is testable without touching the real secret store or gitleaks.
 * Returns `undefined` to let the call through, or `{ block: true, reason }`.
 */
export function createOnToolCall(overrides: Partial<GuardOptions> = {}) {
  const opts: GuardOptions = { ...DEFAULT_GUARD_OPTIONS, ...overrides };

  return async function onToolCall(
    event: { toolName: string; input?: unknown },
    ctx: ExtensionContext,
  ): Promise<{ block: true; reason: string } | undefined> {
    // Classification failure is itself a block: an uninspected call is exactly
    // the thing this guard exists to prevent.
    let targets: Targets | null;
    try {
      targets = targetsFor(event.toolName, (event.input ?? {}) as Record<string, unknown>);
    } catch {
      return blocked(
        "publish-guard: blocked — this call could not be classified as publishing or not, " +
          "so it cannot be inspected; refusing to run it. Re-issue it differently (a plain command or " +
          "a --body-file) to get a call that can be checked.",
      );
    }
    if (!targets) return;

    // From here on the call publishes: every failure blocks.
    try {
      if (targets.unresolved.length > 0) {
        return blocked(
          `publish-guard: blocked — the command publishes the output of a command substitution ` +
            `(${targets.unresolved[0]}) that cannot be scanned. Put the text in a file and pass it with ` +
            `--body-file / --notes-file / --input (or @file) instead.`,
        );
      }

      if (targets.cwdRelative.length > 0) {
        return blocked(
          "publish-guard: blocked — the command changes directory (cd/pushd) and references a " +
            "relative path, so it would publish a different file than this session would read. " +
            "Use an absolute path, or drop the cd/pushd.",
        );
      }

      const secrets = readSecrets(opts);
      if ("error" in secrets) {
        return blocked(
          `publish-guard: blocked — ${secrets.error}, so the exact-value scan cannot run; ` +
            `refusing to publish on gitleaks rules alone. Unlock it (git-crypt unlock) and retry.`,
        );
      }

      const parts: string[] = [targets.text];

      for (let i = 0; i < targets.files.length; i++) {
        const read = readText(targets.files[i], ctx.cwd);
        if ("error" in read) {
          return blocked(
            `publish-guard: blocked — the file named by ${targets.sources[i] ?? "a file flag"} ` +
              `could not be read (${read.error}); refusing to publish unscanned. Fix the path, or drop ` +
              `the flag and pass the text with --body/--notes.`,
          );
        }
        parts.push(read.text);
      }
      for (const path of targets.candidates) {
        const read = readText(path, ctx.cwd);
        if (!("error" in read)) parts.push(read.text);
      }

      // `--body "$GITHUB_TOKEN"` is harmless prose literally; the shell expands
      // it at execution time. Put the value there so the scanner sees what
      // would actually be published.
      for (const name of targets.vars) {
        const value = process.env[name];
        if (typeof value === "string" && value.length >= 12) parts.push(value);
      }

      const text = parts.join("\n");
      const verdict = scan(text, secrets.text, await runScanner(text, opts));
      if (verdict) return blocked(verdict.reason);
    } catch {
      return blocked("publish-guard: blocked — the outgoing text could not be inspected; refusing to publish unscanned.");
    }
  };
}

function blocked(reason: string): { block: true; reason: string } {
  return { block: true, reason };
}

/** Which tool calls publish text, and what they will send. */
function targetsFor(toolName: string, input: Record<string, unknown>): Targets | null {
  if (SHELL_TOOL_SET.has(toolName)) {
    const command = input.command;
    if (typeof command !== "string" || command.length === 0) return null;
    const t = publishTargets(command);
    if (!t) return null;
    return {
      text: command,
      files: t.files,
      sources: t.sources,
      vars: t.vars,
      candidates: t.candidates,
      unresolved: t.unresolved,
      cwdRelative: t.cwdRelative,
      scope: t.scope,
    };
  }

  const fields = WEB_TOOL_FIELDS[toolName];
  if (!fields) return null;
  const strings: string[] = [];
  for (const field of fields) {
    const v = input[field];
    if (typeof v === "string") strings.push(v);
    else if (Array.isArray(v)) for (const item of v) if (typeof item === "string") strings.push(item);
  }
  if (strings.length === 0) return null;
  return {
    text: strings.join("\n"),
    files: [],
    sources: [],
    vars: [],
    candidates: [],
    unresolved: [],
    cwdRelative: [],
    scope: "known",
  };
}

/** Read a referenced file (relative to the session cwd, `~` expanded).
 *  The failure side is a CODE only: the path came from the command and can be
 *  token-shaped, so it never travels into a block reason. */
function readText(path: string, cwd: string): { text: string } | { error: string } {
  try {
    const expanded = path.startsWith("~/") ? resolve(homedir(), path.slice(2)) : path;
    const abs = isAbsolute(expanded) ? expanded : resolve(cwd, expanded);
    const stat = statSync(abs);
    if (!stat.isFile()) return { error: "not a regular file" };
    if (stat.size > MAX_FILE_BYTES) return { error: "too large to scan" };
    return { text: readFileSync(abs, "utf-8") };
  } catch (err) {
    const code = (err as NodeJS.ErrnoException)?.code ?? "read failed";
    return { error: code === "ENOENT" ? "missing" : code };
  }
}

/**
 * secrets/env.fish text, or the reason it cannot be used.
 *
 * A missing/unreadable file (git-crypt locked) and a locked file's ciphertext
 * are both ERRORS, not "empty": the caller blocks, because running with only
 * the gitleaks half would silently skip every exact known value.
 */
function readSecrets(opts: GuardOptions): { text: string } | { error: string } {
  let text: string;
  try {
    text = opts.readSecretsFile(opts.secretsPath);
  } catch {
    return { error: `${SECRETS_LABEL} could not be read (git-crypt locked?)` };
  }
  if (text.slice(0, 16).includes("GITCRYPT")) {
    return { error: `${SECRETS_LABEL} is git-crypt locked` };
  }
  return { text };
}

/** Run `gitleaks stdin` over `text`. Never throws; every failure is a LeakScan
 *  error, which the pure core turns into a block. */
function runScanner(text: string, opts: GuardOptions): Promise<LeakScan> {
  return new Promise((settle) => {
    let done = false;
    const finish = (result: LeakScan) => {
      if (done) return; // the callback and an stdin error can both fire
      done = true;
      settle(result);
    };

    try {
      const child = execFile(
        opts.gitleaksBin,
        GITLEAKS_ARGS,
        { timeout: opts.scanTimeoutMs, maxBuffer: 16 * 1024 * 1024, killSignal: "SIGKILL" },
        (err, stdout) => {
          const code = (err as NodeJS.ErrnoException | null)?.code;
          if (err && code === "ENOENT") {
            finish({ kind: "error", detail: "gitleaks not installed" });
            return;
          }
          if (err && (err.killed || err.signal)) {
            finish({ kind: "error", detail: `gitleaks timed out after ${opts.scanTimeoutMs} ms` });
            return;
          }
          const out = (stdout ?? "").trim();
          if (out.length === 0) {
            finish({ kind: "error", detail: err ? `gitleaks exit ${code ?? "unknown"}` : "gitleaks produced no report" });
            return;
          }
          let parsed: unknown;
          try {
            parsed = JSON.parse(out);
          } catch {
            // stderr is deliberately not quoted: it could carry report text.
            finish({ kind: "error", detail: err ? `gitleaks exit ${code ?? "unknown"}` : "gitleaks output was not JSON" });
            return;
          }
          if (!Array.isArray(parsed)) {
            finish({ kind: "error", detail: "gitleaks output was not a findings array" });
            return;
          }
          const ruleIds = parsed
            .map((f) => (f as { RuleID?: unknown } | null)?.RuleID)
            .filter((r): r is string => typeof r === "string" && r.length > 0);
          finish({ kind: "ok", ruleIds });
        },
      );
      // A scanner that stops reading (EPIPE) has not scanned the text. Without
      // this listener that is an unhandled 'error' event — a crash instead of a
      // block.
      child.stdin?.on("error", () => finish({ kind: "error", detail: "gitleaks did not accept the input" }));
      child.stdin?.end(text);
    } catch {
      finish({ kind: "error", detail: "gitleaks could not be started" });
    }
  });
}
