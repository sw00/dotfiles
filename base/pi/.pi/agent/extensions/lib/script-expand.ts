/**
 * Script-body expansion for the mutation guard — zero dependencies on pi or any
 * framework. Split out of ./classify.ts, which re-exports every symbol here.
 *
 * A pure expander: `sh /tmp/x.sh` is judged by the body it will run, never by
 * its filename. File contents come from an injected reader, so this stays free
 * of node:fs and unit-testable.
 */

import { baseName, hasSubstitution, isLookupSegment, normalizeCommand } from "./shell-parse.ts";

// ── script indirection (4e) ──────────────────────────────────────
// `sh /tmp/probeA.sh` used to run freely under a locked gate: the launcher is
// not a guarded CLI and the body was never read. A pure expander appends the
// referenced script bodies before classification, so the body is judged, not
// the wrapper. File contents come from an injected reader, so this stays free
// of node:fs and unit-testable.

export type ReadFile = (path: string) => string | null;

/** Shell launchers whose file arguments are executed as a script. */
const SCRIPT_RUNNERS = new Set(["sh", "bash", "zsh", "dash", "source", "."]);

/** Wrappers that keep the launcher in command position (`sudo sh x.sh`). */
const LEAD_THROUGH = new Set(["sudo", "env", "time", "timeout", "nohup", "exec", "command", "nice"]);

/** Wrapper flags whose *next* word is their value (`sudo -u root sh x.sh`).
 *  Without this the value looked like the command and the launcher was lost. */
const WRAPPER_VALUE_FLAGS: Record<string, Set<string>> = {
  sudo: new Set([
    "-u", "--user", "-g", "--group", "-p", "--prompt", "-C", "--close-from", "-h", "--host",
    "-r", "--role", "-t", "--type", "-U", "--other-user", "-T", "--command-timeout",
    "-D", "--chdir", "-R", "--chroot",
  ]),
  env: new Set(["-u", "--unset", "-C", "--chdir", "-S", "--split-string"]),
  timeout: new Set(["-s", "--signal", "-k", "--kill-after"]),
  nice: new Set(["-n", "--adjustment"]),
};

/** Leading non-flag words a wrapper consumes before the real command
 *  (`timeout 5 sh x.sh` — the duration is not the command). */
const WRAPPER_POSITIONALS: Record<string, number> = { timeout: 1 };

/** Per-body cap. Past it the gate cannot honestly claim to have inspected the
 *  script, so the file is treated as unverifiable (unknown) instead. 1 MiB is
 *  deliberately above this repo's own largest test script (check.sh, ~270 KB):
 *  a cap that made `bash check.sh` un-runnable would push a daily action behind
 *  the gate, which is friction the wrong way round. */
export const SCRIPT_MAX_BYTES = 1024 * 1024;

/** Nested `a.sh -> sh b.sh` chains: bounded, so a cycle cannot hang the gate. */
const SCRIPT_MAX_DEPTH = 3;

/** A directly executed file is a shell script only if it says so. */
const SHELL_SHEBANG = /^#![^\n]*\b(?:sh|bash|zsh|dash|ksh)\b/;

/** Flags whose value is inline shell code, not a file (`sh -c '…'`). */
const INLINE_CODE_FLAGS = new Set(["-c", "--command"]);

/** Runner flags that take a value which is an option, not a script
 *  (`sh -o errexit x.sh`) — the file still comes after them. */
const RUNNER_VALUE_FLAGS = new Set(["-o", "-O", "--rcfile", "--init-file"]);

export interface ScriptExpansion {
  /** The original command plus every inlined script body. */
  text: string;
  /** Script paths whose bodies could not be inlined (unreadable/oversized). */
  unresolved: string[];
  /** Executing shapes that cannot be resolved to a body at all — a pipeline
   *  into a shell, a `$VAR` command word. Fail closed: the locked gate blocks
   *  them, the armed gate confirms them loudly. */
  unknowns: string[];
  /** What the walk failed to resolve INSIDE an already-inlined body (depth
   *  >= 1): a `$VAR` command word there, an unexpandable path, a nested script
   *  that could not be read. Recorded, never blocking — see DEPTH below. */
  nestedNotes: string[];
}

// ── DEPTH: what is enforced vs. what is only recorded ────────────
// A guard that blocks what it merely cannot follow three levels down becomes
// friction in the wrong direction: `bash check.sh` — this repo's own 270 KB
// suite — carries `$VAR` command words and `$DOTFILES/…` paths by the dozen,
// so an expansion walk that failed closed on all of them made the repo's own
// test suite unrunnable in every mode. That is how a gate gets switched off.
//
// So enforcement follows what the gate actually reads:
//   depth 0 — the command the caller typed, and whether a script it names
//             directly can be read. Unknowns stay unknowns and unreadable
//             scripts stay `unresolved`: locked blocks, armed confirms.
//   depth >= 1 — anything found while walking an inlined body. Collected into
//             `nestedNotes`, reported to the user once per session, never a
//             block and never an `unknown`.

/** A shape the walk could not resolve. Depth decides the consequence: at
 *  depth 0 it is an `unknown` (fail closed, as it always was); inside an
 *  inlined body it is a note. */
function recordUnknown(ctx: ScriptCtx, message: string): void {
  if (ctx.depth === 0) ctx.unknowns.push(message);
  else ctx.nestedNotes.push(`${message} — inside an inlined script body, so not enforced`);
}

/** A declared shell script that could not be read. Directly named by the
 *  command → `unresolved` (a locked gate blocks it); named from inside a body →
 *  a note. */
function recordUnresolved(ctx: ScriptCtx, path: string): void {
  if (ctx.depth === 0) ctx.unresolved.push(path);
  else ctx.nestedNotes.push(`${path}: script body unreadable or too large to inspect — inside an inlined script body, so not enforced`);
}

function resolveScriptPath(path: string): string {
  return path.startsWith("~/") ? `${process.env.HOME ?? ""}${path.slice(1)}` : path;
}

function unquote(word: string): string {
  return word.replace(/^["'\\]+/, "").replace(/["'\\,;|&)]+$/, "");
}

/** A word that names a file rather than a PATH command (`./deploy`, `/x/y`). */
function isFilePath(word: string): boolean {
  return word.includes("/") || /\.sh$/.test(word);
}

/**
 * Index of the real command word, past env assignments and pass-through
 * wrappers — including the wrappers' own flags, flag values and positionals,
 * which used to be read as the command (`env FOO=1 sh x.sh`, `sudo -E sh
 * x.sh`, `timeout 5 sh x.sh`).
 */
function commandPosition(words: string[]): number {
  let i = 0;
  while (i < words.length) {
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(words[i])) { i++; continue; } // env FOO=1
    const wrapper = baseName(words[i]);
    if (!LEAD_THROUGH.has(wrapper)) break;
    i++;
    const valueFlags = WRAPPER_VALUE_FLAGS[wrapper];
    let positionals = WRAPPER_POSITIONALS[wrapper] ?? 0;
    while (i < words.length) {
      const a = words[i];
      if (a === "--") { i++; break; }
      if (a.startsWith("-")) {
        i++;
        if (!a.includes("=") && valueFlags?.has(a)) i++; // sudo -u root cmd
        continue;
      }
      if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(a)) { i++; continue; } // env FOO=1 cmd
      if (positionals > 0) { positionals--; i++; continue; } // timeout 5 cmd
      break;
    }
  }
  return i;
}

/** `xargs`: the words after its own flags are the command it runs, and any
 *  further arguments come from the pipe. `echo x.sh | xargs sh` therefore runs a
 *  script path that nothing on the command line names. */
const XARGS = "xargs";

/** xargs flags whose *next* word is their value (`xargs -n 1 sh`). */
const XARGS_VALUE_FLAGS = new Set([
  "-a", "--arg-file", "-d", "--delimiter", "-E", "--eof", "-I", "--replace",
  "-L", "--max-lines", "-n", "--max-args", "-P", "--max-procs", "-s", "--max-chars",
]);

/** find's execute predicates: the words after one are a command find runs. */
const FIND_EXEC = new Set(["-exec", "-execdir", "-ok", "-okdir"]);

/** find's placeholder for the path it found, and the words that end its payload. */
const FIND_PLACEHOLDER = /^\{\}+$/;
const FIND_TERMINATORS = new Set([";", "+"]);

/** Everything one expansion walk collects into. `seen`, `bodies`, `unresolved`,
 *  `unknowns` and `written` are shared across the whole walk (recursion spreads
 *  this object, so the references survive); only `depth` is per level. */
interface ScriptCtx {
  readFile: ReadFile;
  seen: Set<string>;
  bodies: string[];
  unresolved: string[];
  unknowns: string[];
  /** Depth >= 1 findings: recorded, never blocking (see DEPTH above). */
  nestedNotes: string[];
  /** Paths this command writes before running — see writeTargets(). */
  written: Set<string>;
  depth: number;
}

/** Words the shell assembles at run time. A COMMAND word carrying one is not the
 *  word that runs: `$(echo ter)raform destroy` names terraform to the shell and
 *  nothing to the gate, `{terraform,destroy}` runs two commands, and `terr*`
 *  globs to whichever binary is on PATH. Argument words are untouched —
 *  `grep -rn $(printf x) src/` stays an ordinary read.
 *
 *  Deliberately narrow, because an inlined script body is walked the same way: a
 *  bare `{`/`}` is shell grouping (every block end starts a line with `}`), a
 *  bare `*`/`(*)`/`[[:space:]]` is a case pattern or a regex fragment, and `\[`
 *  is an escaped literal. None of those expand to a command name. */
function hasExpansion(word: string): boolean {
  // Only a SINGLE-quoted word cannot expand: `$(…)` and backticks run inside
  // double quotes, so exempting them hid every assembly written the obvious way.
  if (!word || word.startsWith("'")) return false;
  if (/\$\(|`|[<>]\(|\$\{/.test(word)) return true; // substitution / parameter expansion
  const bare = word.replace(/\\./g, "_"); // an escaped metacharacter is a literal
  // Brace expansion carries a comma or a range: `{a,b}`, `{1..5}`.
  if (/\{[^}]*[,.]/.test(bare) && bare.includes("}")) return true;
  // A glob has to have a NAME next to it (`terr*`); punctuation alone does not
  // name a command, it matches a pattern.
  if (!/[A-Za-z0-9]/.test(bare.replace(/[?*[\]{}()]/g, ""))) return false;
  return /[*?]/.test(bare) || /\[[^\]]+\]/.test(bare);
}

/** The command word as WRITTEN, before normalization flattened a substitution
 *  into separate words: `$(echo ter)raform` has to be seen whole to be refused. */
function rawCommandWord(rawSegment: string): string | null {
  const rawWords = rawSegment.trim().split(/\s+/).filter(Boolean);
  return rawWords[commandPosition(rawWords)] ?? null;
}

/** A runner's inline-code payload (`bash -c …`, `sh --command …`) as text, with
 *  the surrounding quote pair removed: the shell that ran the segment already
 *  consumed those quotes, so what the child shell expands is the text inside.
 *  Walks the RAW segment, because normalizeCommand flattens `$(…)` into separate
 *  words and the assembly is exactly what has to stay visible. */
function inlinePayload(rawSegment: string): string | null {
  const rawWords = rawSegment.trim().split(/\s+/);
  const cmdAt = commandPosition(rawWords);
  const first = cmdAt >= 0 ? rawWords[cmdAt] : undefined;
  const cmd = first === undefined ? "" : baseName(unquote(first));
  if (!SCRIPT_RUNNERS.has(cmd)) return null;
  const flagAt = rawWords.findIndex((w, i) => i > cmdAt && INLINE_CODE_FLAGS.has(unquote(w)));
  if (flagAt < 0) return null;
  const rest = rawWords.slice(flagAt + 1).join(" ").trim();
  if (rest.length === 0) return null;
  return rest.replace(/^(["'])([\s\S]*)\1$/, "$2");
}

/** Index of the command xargs runs, past its own flags and their values. */
function xargsCommandStart(words: string[], at: number): number | null {
  for (let j = at + 1; j < words.length; j++) {
    const w = words[j];
    if (w.startsWith("-")) {
      if (!w.includes("=") && XARGS_VALUE_FLAGS.has(w)) j++; // -n 1, -I {}
      continue;
    }
    return j;
  }
  return null;
}

/** Each `find … -exec …` payload in a segment, trimmed at find's `;` / `+`. */
function findExecWords(words: string[], from: number): string[][] {
  const out: string[][] = [];
  for (let i = from; i < words.length; i++) {
    if (!FIND_EXEC.has(words[i])) continue;
    const sub: string[] = [];
    for (let j = i + 1; j < words.length; j++) {
      if (FIND_TERMINATORS.has(unquote(words[j]))) break;
      sub.push(words[j]);
    }
    if (sub.length > 0) out.push(sub);
    i += sub.length + 1; // step past the payload and its terminator
  }
  return out;
}

/** Comparison key for a script path: quotes stripped, `~` expanded, `./` folded. */
function scriptKey(path: string): string {
  return unquote(resolveScriptPath(path)).replace(/^\.\//, "").replace(/\/+$/, "");
}

/** True when one of `written` names the same file as `path`. A relative name and
 *  an absolute one are the same file when the base names match — as close as a
 *  static gate gets without assuming a working directory. */
function writesPath(written: Set<string>, path: string): boolean {
  if (written.size === 0) return false;
  const key = scriptKey(path);
  if (written.has(key)) return true;
  const base = key.slice(key.lastIndexOf("/") + 1);
  for (const w of written) {
    if (w.slice(w.lastIndexOf("/") + 1) !== base) continue;
    if (!key.includes("/") || !w.includes("/")) return true;
  }
  return false;
}

/**
 * Paths a command writes BEFORE anything runs: redirection targets, `tee`
 * targets, and a cp/mv/install destination. Executing one of these in the same
 * command executes the OLD file on disk (`printf … > h.sh; sh h.sh` writes h.sh
 * and runs whatever was there before), so its contents cannot be judged.
 */
export function writeTargets(command: string): Set<string> {
  const out = new Set<string>();
  // `> f`, `>> f`, `>| f`, `&> f`, `2> f`
  for (const m of command.matchAll(/(?:>>?\|?|&>>?)\s*([^\s;&|()<>]+)/g)) {
    const target = m[1];
    if (/^\d+$/.test(target) || target.startsWith("&") || target.startsWith("$")) continue; // fd dup / variable
    out.add(scriptKey(target));
  }
  for (const rawSegment of command.split(/[|;&\n\r]+/)) {
    const words = normalizeCommand(rawSegment).trim().split(/\s+/).filter(Boolean);
    const at = commandPosition(words);
    const cmd = baseName(words[at] ?? "");
    const args = words.slice(at + 1).filter((w) => !w.startsWith("-"));
    if (cmd === "tee") {
      for (const w of args) out.add(scriptKey(w));
    } else if (cmd === "cp" || cmd === "mv" || cmd === "install") {
      const dest = args[args.length - 1]; // cp/mv write their last argument
      if (dest) out.add(scriptKey(dest));
    }
  }
  return out;
}

/** One command in command position, plus the runner forms that hide a second
 *  command behind an argument (`xargs`, `find -exec`). */
function collectFromWords(words: string[], ctx: ScriptCtx): void {
  const at = commandPosition(words);
  const raw = words[at] ?? "";
  if (!raw) return;

  // `$SHELL x.sh`, `c=terraform; $c destroy`: which program runs — and whether
  // it is even a shell — is decided at run time. The gate cannot resolve it,
  // so it must not guess.
  if (raw.startsWith("$")) {
    recordUnknown(ctx, `${raw}: variable command word, cannot resolve what runs`);
    return;
  }

  // A word the shell assembles is not the word that runs — never a read.
  if (hasExpansion(raw)) {
    recordUnknown(ctx, `${raw}: command word built by shell expansion, cannot resolve what runs`);
    return;
  }

  const cmd = baseName(raw);

  // `… | xargs sh`: the runner is xargs's argument and the paths it passes on
  // come from the pipe, so a shell behind it has no script the gate can read.
  if (cmd === XARGS) {
    const next = xargsCommandStart(words, at);
    if (next !== null) collectFromWords(words.slice(next), ctx);
    return;
  }

  // `find … -exec sh {} +`: what runs is find's own argument list.
  if (cmd === "find") {
    for (const sub of findExecWords(words, at + 1)) collectFromWords(sub, ctx);
    return;
  }

  const viaRunner = SCRIPT_RUNNERS.has(cmd);
  const candidates: string[] = [];
  let inlineCode = false;
  let stdinScript = false;

  if (viaRunner) {
    let scriptArg: string | null = null;
    for (let j = at + 1; j < words.length; j++) {
      const w = words[j];
      if (INLINE_CODE_FLAGS.has(w)) { inlineCode = true; break; } // the payload is code, classified in place
      if (w === "-s" || w === "--stdin") { stdinScript = true; continue; }
      if (RUNNER_VALUE_FLAGS.has(w)) { j++; continue; } // `sh -o errexit x.sh`
      if (w.startsWith("-")) continue;
      scriptArg = w; // only the FIRST non-flag word is the script; rest are $1..$n
      break;
    }
    if (!inlineCode) {
      // `cat x.sh | bash`, `base64 -d f | sh`, `… | xargs sh`: the body arrives
      // on stdin, so there is nothing to read and nothing to judge.
      if (scriptArg === null || stdinScript) {
        recordUnknown(ctx, `${cmd}: reads its script from stdin or a pipeline, cannot inspect it`);
        return;
      }
      // `find -exec sh {} +`: the path is only known once find has run.
      if (FIND_PLACEHOLDER.test(unquote(scriptArg))) {
        recordUnknown(ctx, `${cmd} ${scriptArg}: script path is a run-time placeholder, cannot inspect it`);
        return;
      }
      candidates.push(scriptArg);
    }
  } else if (isFilePath(raw)) {
    candidates.push(raw); // ./deploy, ./probe.sh, /abs/path
  }

  for (const candidate of candidates) {
    const path = resolveScriptPath(unquote(candidate));
    if (!path || ctx.seen.has(path)) continue;
    // Written by this same command, then executed: the body on disk is the OLD
    // one, so reading it would judge text that never runs.
    if (writesPath(ctx.written, path)) {
      recordUnknown(
        ctx,
        `${path}: written and then executed by the same command, its contents on disk cannot be trusted`,
      );
      continue;
    }
    // A runner's argument is always script text; a bare path is only a script
    // if its shebang says so, and a `.sh` suffix already says so.
    const declaredShell = viaRunner || /\.sh$/.test(path);

    const body = ctx.readFile(path);
    if (body === null || body.length > SCRIPT_MAX_BYTES) {
      // A declared shell script we cannot read is unverifiable → block. A path
      // we only suspected is not evidence of a script, and a file that cannot
      // be read cannot be executed as one either.
      if (declaredShell) recordUnresolved(ctx, path);
      continue;
    }
    if (!declaredShell && !SHELL_SHEBANG.test(body)) continue;

    ctx.seen.add(path);
    ctx.bodies.push(body);
    collectScripts(body, { ...ctx, depth: ctx.depth + 1 });
  }
}

function collectScripts(command: string, ctx: ScriptCtx): void {
  if (ctx.depth > SCRIPT_MAX_DEPTH) return;
  // Writes are collected for the whole command, because the write and the run
  // can sit in different segments (`… > h.sh; sh h.sh`).
  const scoped: ScriptCtx = { ...ctx, written: new Set([...ctx.written, ...writeTargets(command)]) };

  for (const rawSegment of command.split(/[|;&\n\r]+/)) {
    // A script body starts with a shebang and is full of comments: neither runs
    // anything, and reading `#!` as the command `bash` would make every script
    // look like a shell on stdin.
    if (rawSegment.trimStart().startsWith("#")) continue;
    const words = normalizeCommand(rawSegment).trim().split(/\s+/).filter(Boolean);
    if (words.length === 0) continue;
    // `command -v bash` / `which sh` name a shell, they do not run it — the same
    // lookup exemption findInvocations applies. (A substitution inside the
    // segment is code, so the exemption does not hold there.)
    const lookupLed = isLookupSegment(words);
    if (lookupLed && !hasSubstitution(rawSegment)) continue;
    // Checked on the RAW segment: normalization splits `$(echo ter)raform` into
    // words that reassemble into something unrecognisable — and read-only. A
    // lookup-led segment is exempt: `command -v $(terraform destroy)` runs the
    // substitution (classified in place) and never the word it builds.
    const rawWord = rawCommandWord(rawSegment);
    if (!lookupLed && rawWord && hasExpansion(rawWord)) {
      recordUnknown(scoped, `${rawWord}: command word built by shell expansion, cannot resolve what runs`);
      continue;
    }
    // `bash -c "$(echo ter)raform destroy"`: the assembled name lives in the
    // payload, which the `-c` branch below never walks (it stops at the flag) and
    // `findInvocations` only ever sees as raw text, so `ter)raform` never
    // reassembles. The payload IS a script, so walk it as one — same
    // commandPosition/lead-word handling (`sudo`, `x=1`, `/bin/bash`), same
    // substitution refusal, and nested `-c` payloads recurse.
    const payload = inlinePayload(rawSegment);
    if (payload !== null) {
      // Same depth: a `-c` payload is the command line, not a body read from a
      // file, so an unknown inside it stays a BLOCK (recordUnknown downgrades to
      // a note only below depth 0). The text strictly shrinks each level, so
      // nested `-c` recursion terminates.
      collectScripts(payload, scoped);
      continue;
    }
    collectFromWords(words, scoped);
  }
}

/**
 * Inline the bodies of every shell script this command executes, so
 * classification sees what the script does rather than its filename.
 * Unreadable/oversized bodies are reported, never silently skipped: a locked
 * gate must fail closed on a script it cannot read.
 */
export function expandScripts(command: string, readFile: ReadFile): ScriptExpansion {
  const ctx: ScriptCtx = {
    readFile,
    seen: new Set(),
    bodies: [],
    unresolved: [],
    unknowns: [],
    nestedNotes: [],
    written: new Set(),
    depth: 0,
  };
  collectScripts(command, ctx);
  const { unresolved, unknowns, nestedNotes } = ctx;
  if (ctx.bodies.length === 0) return { text: command, unresolved, unknowns, nestedNotes };
  return { text: [command, ...ctx.bodies].join("\n"), unresolved, unknowns, nestedNotes };
}
