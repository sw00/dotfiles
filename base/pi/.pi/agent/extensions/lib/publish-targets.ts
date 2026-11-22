/**
 * Publish-target recognition for the publish guard — zero dependencies on pi or
 * any framework. Split out of ./publish-scan.ts, which re-exports every symbol
 * here, so the recognition half can be read and tested on its own.
 *
 * publishTargets() recognises the publish verbs of gh/glab (skipping flags that
 * precede the group/verb, and treating an unrecognised gh/glab write as a
 * target rather than a skip) and extracts the files whose CONTENT will be
 * published, the $NAME variables the command expands, and the command
 * substitutions it cannot resolve. An unresolvable substitution — `$(date)`,
 * `$(curl …)`, `` `openssl rand` `` — is `unresolved`: the text being published
 * is invisible, so the caller must block and point at `--body-file`. A relative
 * file reference in a command that also runs `cd`/`pushd` is `cwdRelative`: it
 * would read a different file than this session's cwd resolves to.
 *
 * A verb whose OWN arguments are the payload (`gist create`, `release upload`)
 * contributes those positionals as `files` — no flag names them — and the shapes
 * no reader can resolve (no file at all ⇒ stdin, a bare `-`, a glob) are
 * `unresolved`, so they block instead of being published unscanned.
 */

// ── publish targets ──────────────────────────────────────────────────────────

/** What a publishing command will actually send. `files` are explicitly
 *  referenced — by a flag, or as the verb's own positional — and are therefore
 *  fail-closed: the wiring must read them (or block). `candidates` are
 *  path-shaped bare tokens — read and scanned when they happen to be a readable
 *  regular file, ignored otherwise (never a block on their own). */
export interface PublishTargets {
  files: string[];
  /** Aligned with `files`: the flag or form that named each one (`--body-file`,
   *  `@file`, `-F`, "a command substitution"). Lets a block reason name the
   *  flag without echoing the path it was given. */
  sources: string[];
  vars: string[];
  candidates: string[];
  /** Text being published that could not be resolved to the files/vars it reads:
   *  a substitution (`$(date)`, `<(curl …)`, an unterminated `$(`), or a
   *  positional the shell decides (stdin, a bare `-`, a glob). Non-empty ⇒ the
   *  caller BLOCKS: the published text is invisible to the scan. */
  unresolved: string[];
  /** Relative file references in a command that also runs `cd`/`pushd`: the
   *  path resolves against the new directory, not the session cwd. */
  cwdRelative: string[];
}

interface CliGroup {
  /** Verbs that publish text unconditionally. */
  publish: readonly string[];
  /** Verbs that publish only when a text-carrying flag (`--comment`, `--body`,
   *  `-m`, …) is present: `gh pr close 12` sends nothing, `gh pr close 12
   *  --comment hi` does. */
  conditional: readonly string[];
  /** Verbs that never publish text. */
  quiet: readonly string[];
}

/** gh/glab groups whose verbs publish text. A group absent from the table, or a
 *  verb absent from the group, resolves to `unknown` — and an unknown gh/glab
 *  invocation is a target, not a skip. */
const GITHUB_GROUPS: Record<string, CliGroup> = {
  pr: {
    publish: ["create", "edit", "comment", "review"],
    conditional: ["close", "merge", "reopen", "ready"],
    quiet: ["view", "list", "checkout", "diff", "status", "checks", "lock", "unlock", "update-branch"],
  },
  issue: {
    publish: ["create", "edit", "comment"],
    conditional: ["close", "reopen", "lock", "unlock", "pin", "transfer"],
    quiet: ["view", "list", "status", "develop", "delete"],
  },
  release: {
    publish: ["create", "edit", "upload"],
    conditional: [],
    quiet: ["view", "list", "download", "delete", "verify"],
  },
  gist: {
    publish: ["create", "edit"],
    conditional: [],
    quiet: ["list", "view", "delete", "clone", "rename"],
  },
  repo: {
    publish: ["create", "edit"],
    conditional: [],
    quiet: ["view", "list", "clone", "fork", "sync", "archive", "rename", "delete", "set-default", "credits"],
  },
  auth: {
    publish: [],
    conditional: [],
    quiet: ["status", "login", "logout", "token", "switch", "setup-git", "refresh"],
  },
};
const GITLAB_GROUPS: Record<string, CliGroup> = {
  mr: {
    publish: ["create", "update", "note", "comment"],
    conditional: ["merge", "approve", "close", "reopen", "discuss"],
    quiet: ["list", "view", "checkout", "diff", "rebase", "todo", "subscribe", "unsubscribe", "delete"],
  },
  issue: {
    publish: ["create", "update", "note", "comment"],
    conditional: ["close", "reopen", "move"],
    quiet: ["list", "view", "subscribe", "unsubscribe", "delete", "board"],
  },
  release: {
    publish: ["create", "edit", "upload"],
    conditional: [],
    quiet: ["list", "view", "download", "delete"],
  },
};

/** Flags whose value is a file path (content is published verbatim). */
const BODY_FILE_FLAGS = new Set(["--body-file", "--notes-file", "--description-file", "--input"]);
/** Flags whose value is `key=value`, where `value` may be `@file`. Exception:
 *  `gh` spells `-F` as `--body-file`/`--notes-file` on its text verbs, so there a
 *  bare value is a FILE — see BODY_FILE_FIELD_FLAGS. */
const FIELD_FLAGS = new Set(["-F", "-f", "--field", "--raw-field"]);
/** `<cli>:<group>:<verb>` invocations where `-F` does NOT mean `--field`: gh
 *  defines it as `--body-file` (`pr`/`issue` create|edit|comment) or
 *  `--notes-file` (`release` create|edit), verified against `gh --help` (2.94.0).
 *  A bare `-F <path>` there publishes that file verbatim, so it has to be read
 *  and scanned; treating it as an API field published it unscanned. `glab`
 *  mirrors the flag on its equivalent verbs. (`gh release upload` has no `-F`.) */
const BODY_FILE_FIELD_FLAGS = new Set([
  "gh:pr:create", "gh:pr:edit", "gh:pr:comment",
  "gh:issue:create", "gh:issue:edit", "gh:issue:comment",
  "gh:release:create", "gh:release:edit",
  "glab:mr:create", "glab:mr:update", "glab:mr:note", "glab:mr:comment",
  "glab:issue:create", "glab:issue:update", "glab:issue:note", "glab:issue:comment",
  "glab:release:create", "glab:release:edit",
]);
/** Verbs whose own bare arguments are the published payload, and the index of
 *  the first positional that names a FILE: `gh gist create <file…>`,
 *  `gh release upload <tag> <file…>`, `gh gist edit <id> [<file>]`. Nothing
 *  flags these paths, so they are required files rather than candidates.
 *  `stdin` marks the ONE verb that falls back to stdin when it is given no file:
 *  `gist create`. `release upload v1` (no asset) is a usage error, not stdin. */
const FILE_POSITIONALS: Record<string, { first: number; stdin?: boolean }> = {
  "gh:gist:create": { first: 0, stdin: true },
  "gh:release:upload": { first: 1 },
  // `release create <tag> [<files>…]` publishes its assets like upload, but a
  // tag with no assets publishes no local file — never stdin.
  "gh:release:create": { first: 1 },
  "glab:release:upload": { first: 1 },
  // `gist edit <id>` with no filename edits the gist in place: nothing local is
  // published, so a missing filename there is not stdin.
  "gh:gist:edit": { first: 1 },
};
/** Text-carrying flags: their presence turns a `conditional` verb into a publish. */
const TEXT_FLAGS = new Set([
  ...BODY_FILE_FLAGS,
  ...FIELD_FLAGS,
  "--body", "-b", "--comment", "-c", "--message", "-m",
  "--notes", "-n", "--description", "-d", "--title", "-t",
]);
/** gh/glab global flags that consume the NEXT token as their value — skipped
 *  together, so `gh -R org/repo pr create` still resolves group/verb. */
const GLOBAL_VALUE_FLAGS = new Set([
  "-R", "--repo", "-H", "--hostname", "--config", "--config-dir", "--jq", "-q", "--template", "--color",
]);
/** Global flags that consume nothing, so nothing is skipped after them. */
const GLOBAL_BOOLEAN_FLAGS = new Set(["-h", "--help", "-v", "--version", "--verbose", "--debug", "--prompt", "--no-color"]);
/** Flags whose NEXT token is their value, never a flag and never a payload: a
 *  token in that position stays one argument (`--body '-Fixed'` must not split
 *  into `-F`+`ixed`) and is never read as a positional file. */
const VALUE_FLAGS = new Set([
  "--body", "-b", "--title", "-t", "--notes", "-n", "--desc", "-d",
  "--add", "-a", "--remove", "-r", "--filename", "-F",
  "--notes-start-tag", "--discussion-category", "--tag", "--target",
]);
/** Commands that move the working directory mid-command. */
const DIR_CHANGE = new Set(["cd", "pushd"]);

interface Token {
  /** Source text of the token, quotes included. */
  raw: string;
  /** Token with shell quoting removed. */
  value: string;
  /** True when any part of the token was quoted. */
  quoted: boolean;
}

const META = new Set([" ", "\t", "\n", "\r", "|", "&", ";", "(", ")", "<", ">", "`"]);

/** Minimal shell tokenizer: quotes group, metacharacters split. Enough to see
 *  `gh`/`glab` argument positions without pretending to be a shell parser. */
function tokenizeCommand(cmd: string): Token[] {
  const out: Token[] = [];
  let value = "";
  let raw = "";
  let quoted = false;
  let mode: "plain" | "single" | "double" = "plain";

  const flush = () => {
    if (raw.length > 0) out.push({ raw, value, quoted });
    value = "";
    raw = "";
    quoted = false;
  };

  for (let i = 0; i < cmd.length; i++) {
    const ch = cmd[i];
    if (mode === "single") {
      raw += ch;
      if (ch === "'") {
        mode = "plain";
        quoted = true;
      } else value += ch;
      continue;
    }
    if (mode === "double") {
      if (ch === '"') {
        mode = "plain";
        raw += ch;
        quoted = true;
      } else if (ch === "\\" && i + 1 < cmd.length) {
        raw += ch + cmd[i + 1];
        value += cmd[i + 1];
        i++;
      } else {
        raw += ch;
        value += ch;
      }
      continue;
    }
    if (ch === "'") {
      mode = "single";
      raw += ch;
      quoted = true;
      continue;
    }
    if (ch === '"') {
      mode = "double";
      raw += ch;
      quoted = true;
      continue;
    }
    if (ch === "\\" && i + 1 < cmd.length) {
      // `\`+newline is a line continuation: it joins the lines, and the newline
      // is not part of the token (`--body-file` must not become "\n--body-file").
      if (cmd[i + 1] === "\n") {
        i++;
        continue;
      }
      raw += ch + cmd[i + 1];
      value += cmd[i + 1];
      quoted = true;
      i++;
      continue;
    }
    if (META.has(ch)) {
      flush();
      continue;
    }
    raw += ch;
    value += ch;
  }
  flush();
  // `-Fnotes.md` is a flag with an attached value, not a long flag name: split
  // it so the flag walk sees the two arguments the shell would. Quote state is
  // not consulted — `-F"notes.md"` is the same argv as `-Fnotes.md` — and a
  // value sitting behind a value-taking flag (`--body "-Foo bar"`) is never
  // split, because it is an argument the flag already consumed.
  const out2: Token[] = [];
  /** The previous token is a value-taking flag, so this one is its VALUE. */
  let afterValueFlag = false;
  for (const t of out) {
    if (afterValueFlag) {
      out2.push(t);
      afterValueFlag = false;
      continue;
    }
    const isFlag = /^-[^-]/.test(t.value);
    // …but `-F` (gh's body-file) keeps its split even when the attached value
    // carries whitespace (`-F"my notes.md"` is the same argv as `-Fmy notes.md`).
    // Every other short flag keeps the whitespace exemption. (`--foo` never
    // splits.) Only uppercase `-F`: gh's lowercase `-f` is a `key=value` field.
    const fileFlag = isFlag && t.value[1] === "F";
    if (t.value.length > 2 && (fileFlag || (isFlag && !/\s/.test(t.value)))) {
      out2.push({ raw: t.raw.slice(0, 2), value: t.value.slice(0, 2), quoted: false });
      out2.push({ raw: t.raw.slice(2), value: t.value.slice(2), quoted: false });
      continue;
    }
    out2.push(t);
    afterValueFlag = !t.value.includes("=") && VALUE_FLAGS.has(flagName(t.value));
  }
  return out2;
}

function baseName(token: string): string {
  const slash = token.lastIndexOf("/");
  return slash >= 0 ? token.slice(slash + 1) : token;
}

/** `$NAME`, `${NAME}` references anywhere in the raw command. */
function varRefs(cmd: string): string[] {
  const out: string[] = [];
  const re = /\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))/g;
  for (let m = re.exec(cmd); m; m = re.exec(cmd)) {
    const name = m[1] ?? m[2];
    if (!out.includes(name)) out.push(name);
  }
  return out;
}

// ── command substitutions ───────────────────────────────────────────────────

interface SubstScan {
  files: string[];
  vars: string[];
  /** One label per substitution whose output could not be resolved. */
  unresolved: string[];
}

/**
 * Resolve EVERY command substitution in `cmd` to the files/vars it reads, or
 * report it as unresolved.
 *
 * This is the hole B9 closed: `--body "$(cat a b)"` used to yield `a` only, and
 * `$(sed -n 1p f)`, `$(< f)`, `$(printenv TOKEN)` yielded nothing at all — the
 * published text was scanned without the file's content and a planted secret
 * went out. Anything this function cannot fully resolve (`$(date)`, `$(curl …)`,
 * a pipeline, an unterminated `$(`) comes back as `unresolved`, which the caller
 * turns into a block.
 */
function scanSubstitutions(cmd: string): SubstScan {
  const files: string[] = [];
  const vars: string[] = [];
  const unresolved: string[] = [];
  let mode: "plain" | "single" | "double" = "plain";

  for (let i = 0; i < cmd.length; i++) {
    const ch = cmd[i];
    if (mode === "single") {
      if (ch === "'") mode = "plain";
      continue;
    }
    if (ch === "\\") {
      i++; // escaped: never a substitution opener
      continue;
    }
    if (ch === '"') {
      mode = mode === "double" ? "plain" : "double";
      continue;
    }
    // `$(…)` and the process substitutions `<(…)`/`>(…)` all publish the output
    // of a command; `<(…)` reaches us as a /dev/fd path that no reader resolves.
    const paren =
      cmd[i + 1] === "(" && (ch === "$" || (mode === "plain" && (ch === "<" || ch === ">")));
    if (ch !== "`" && !paren) continue;

    const backtick = ch === "`";
    const open = backtick ? "`" : `${ch}(`; // `$(` `<(` `>(`
    const close = backtick ? closeBacktick(cmd, i + 1) : closeParen(cmd, i + 2);
    if (close < 0) {
      unresolved.push(backtick ? "`…`" : `${open}…)`);
      break;
    }
    const body = unescapeSubstitution(cmd.slice(backtick ? i + 1 : i + 2, close));
    const resolved = resolveSubstitution(body);
    if (resolved) {
      for (const f of resolved.files) if (!files.includes(f)) files.push(f);
      for (const v of resolved.vars) if (!vars.includes(v)) vars.push(v);
    } else {
      unresolved.push(backtick ? "`…`" : `${open}…)`);
    }
    i = close;
  }

  return { files, vars, unresolved };
}

function closeParen(cmd: string, start: number): number {
  let depth = 1;
  let mode: "plain" | "single" | "double" = "plain";
  for (let i = start; i < cmd.length; i++) {
    const ch = cmd[i];
    if (mode === "single") {
      if (ch === "'") mode = "plain";
      continue;
    }
    if (ch === "\\") {
      i++;
      continue;
    }
    if (ch === '"') {
      mode = mode === "double" ? "plain" : "double";
      continue;
    }
    if (mode === "double") continue;
    if (ch === "(") depth++;
    else if (ch === ")" && --depth === 0) return i;
  }
  return -1;
}

function closeBacktick(cmd: string, start: number): number {
  for (let i = start; i < cmd.length; i++) {
    if (cmd[i] === "\\") {
      i++;
      continue;
    }
    if (cmd[i] === "`") return i;
  }
  return -1;
}

/** Inside double quotes the shell unescapes `\"`, `\$`, `` \` `` before the
 *  substitution runs, so `--body "$(cat \"f\")"` really reads `f`. */
function unescapeSubstitution(body: string): string {
  return body.replace(/\\(["'\\$`])/g, "$1");
}

/**
 * `body` of one substitution → the files/vars it reads, or null when its output
 * is not fully determined by arguments we can see.
 */
function resolveSubstitution(body: string): { files: string[]; vars: string[] } | null {
  const text = body.trim();
  if (text.length === 0) return null;

  // `$(< f)` — bash's shorthand for `$(cat f)`.
  const shortcut = /^<\s*(\S+)$/.exec(text);
  if (shortcut) {
    const p = shortcut[1].replace(/^["']|["']$/g, "");
    return isReadableName(p) ? { files: [p], vars: [] } : null;
  }

  // Pipelines, redirections, lists and nesting hide part of the output.
  if (/[|;&<>\n]/.test(text) || /\$\(|`/.test(text)) return null;

  const tokens = tokenizeCommand(text);
  if (tokens.length === 0) return null;
  const head = baseName(tokens[0].value);
  const args = tokens.slice(1).map((t) => t.value);

  if (head === "cat") {
    const files: string[] = [];
    let flagsDone = false;
    for (const v of args) {
      if (!flagsDone && v === "--") {
        flagsDone = true;
        continue;
      }
      if (!flagsDone && v.startsWith("-") && v.length > 1) continue; // -n, -A, --squeeze-blank
      if (v === "-" || !isReadableName(v)) return null; // reads stdin / an invisible name
      files.push(v);
    }
    return files.length > 0 ? { files, vars: [] } : null; // bare `cat` reads stdin
  }

  if (head === "sed") {
    const files: string[] = [];
    let scriptSeen = false;
    for (let k = 0; k < args.length; k++) {
      const v = args[k];
      if (v === "-e" || v === "--expression" || v === "-f" || v === "--file") {
        scriptSeen = true;
        k++; // the next token is the script, never a file
        continue;
      }
      if (v.startsWith("-e") && v.length > 2) {
        scriptSeen = true;
        continue;
      }
      if (v.startsWith("-")) continue; // -n, -E, -r, …
      if (!scriptSeen) {
        scriptSeen = true; // the first bare argument is the sed program
        continue;
      }
      if (v === "-" || !isReadableName(v)) return null;
      files.push(v);
    }
    return files.length > 0 ? { files, vars: [] } : null; // pid-less sed reads stdin
  }

  if (head === "printenv") {
    const vars = args.filter((v) => v.length > 0 && !v.startsWith("-") && !v.startsWith("$"));
    // Bare `printenv` dumps the entire environment; nothing to pin the scan to.
    return vars.length > 0 ? { files: [], vars } : null;
  }

  return null;
}

/** A substitution argument we can name without the shell deciding it. */
function isReadableName(value: string): boolean {
  return value.length > 0 && !value.startsWith("$") && !value.includes("://");
}

function dedupe(values: string[]): string[] {
  const out: string[] = [];
  for (const v of values) if (!out.includes(v)) out.push(v);
  return out;
}

/** `--flag=value` / `-Fvalue` → `--flag` / `-F`. */
function flagName(value: string): string {
  if (!value.startsWith("-")) return "";
  const eq = value.indexOf("=");
  return eq > 0 ? value.slice(0, eq) : value;
}

/** Absolute on POSIX, Windows drive, or UNC. `~/x` is HOME-relative, not cwd. */
function isRelativePath(p: string): boolean {
  return !/^(?:\/|[A-Za-z]:[\\/]|\\\\)/.test(p) && !p.startsWith("~");
}

function changesDirectory(tokens: Token[]): boolean {
  return tokens.some((t) => DIR_CHANGE.has(t.value));
}

const PATHISH = /^(?:~|\.{1,2})?\/?[\w@%+.-]+(?:\/[\w@%+.-]+)*$/;

/** A bare token that could name a file (`notes.md`, `./body.md`, `/tmp/x.txt`).
 *  Deliberately conservative: no URLs, no flags, no variables, must have a
 *  separator or an extension. */
function looksLikePath(value: string): boolean {
  if (value.length === 0 || value.startsWith("-") || value.startsWith("$")) return false;
  if (value.includes("://") || value.includes("@")) return false;
  if (!PATHISH.test(value)) return false;
  return value.includes("/") || /\.[A-Za-z0-9]{1,8}$/.test(value);
}

/** Strip the `@` that prefix-marks a file in gh/glab arguments. */
function stripAt(value: string): string | null {
  if (!value.startsWith("@")) return null;
  const p = value.slice(1);
  return p.length > 0 && !p.startsWith("-") ? p : null;
}

/**
 * Recognise a publishing command and extract what it will send.
 *
 * Returns null only for commands that cannot publish at all (`git push`, `ls`,
 * `gh pr view`, …). A gh/glab invocation we cannot classify is still a target,
 * so a write we do not know about is scanned instead of being skipped.
 *   files        — explicit files whose content is published: a flag's value, or
 *                  the verb's own positional (`gh gist create <file…>`)
 *   sources      — the flag/form that named each file (aligned with `files`)
 *   vars         — $NAME variables the command expands
 *   candidates   — path-shaped bare tokens (scan when readable, else ignore)
 *   unresolved   — published text no reader can resolve (⇒ block)
 *   cwdRelative  — relative file references in a command that runs cd/pushd
 */
export function publishTargets(cmd: string): PublishTargets | null {
  const tokens = tokenizeCommand(cmd);
  const textFlag = tokens.some((t) => TEXT_FLAGS.has(flagName(t.value)));

  let resolvedCli = false;
  // `<cli>:<group>:<verb>` of the invocation we recognised, because a flag's
  // meaning can depend on the verb (`-F`).
  let publishKey: string | null = null;
  /** Index of the verb token, so its own positionals can be read. */
  let publishVerbIndex = -1;
  for (let i = 0; i < tokens.length; i++) {
    const cli = baseName(tokens[i].value);
    const groups = cli === "gh" ? GITHUB_GROUPS : cli === "glab" ? GITLAB_GROUPS : null;
    if (!groups) continue;
    const resolved = resolveCli(tokens, i, groups, cli === "gh", textFlag);
    if (resolved.verdict === "publish") {
      resolvedCli = true;
      if (resolved.group && resolved.verb) {
        publishKey = `${cli}:${resolved.group}:${resolved.verb}`;
        publishVerbIndex = resolved.verbIndex ?? -1;
      }
      break;
    }
    if (resolved.verdict === "unknown" && !resolvedCli) {
      resolvedCli = true;
      // An unrecognised pre-group flag does not make the verb unreadable: the
      // group/verb still resolved, so `-F` keeps its file meaning (fail-closed).
      if (resolved.group && resolved.verb) {
        publishKey = `${cli}:${resolved.group}:${resolved.verb}`;
        publishVerbIndex = resolved.verbIndex ?? -1;
      }
    }
  }

  if (!resolvedCli) return nestedTargets(tokens);

  const files: string[] = [];
  const sources: string[] = [];
  const candidates: string[] = [];
  const addFile = (p: string | null, source: string) => {
    if (!p || p.length === 0 || files.includes(p)) return;
    // An explicit reference outranks an earlier heuristic candidate: it must be
    // read (fail-closed) rather than merely scanned when readable.
    const at = candidates.indexOf(p);
    if (at >= 0) candidates.splice(at, 1);
    files.push(p);
    sources.push(source);
  };
  const addCandidate = (p: string) => {
    if (files.includes(p) || candidates.includes(p)) return;
    candidates.push(p);
  };

  for (let i = 0; i < tokens.length; i++) {
    const tok = tokens[i];
    const at = stripAt(tok.value);
    if (at) {
      addFile(at, "@file");
      continue;
    }
    if (!tok.value.startsWith("-")) {
      if (looksLikePath(tok.value)) addCandidate(tok.value);
      continue;
    }
    // --flag=value and -Fvalue forms carry the value inline.
    const eq = tok.value.indexOf("=");
    const name = eq > 0 ? tok.value.slice(0, eq) : tok.value;
    const inlineValue = eq > 0 ? tok.value.slice(eq + 1) : null;
    // `gh gist edit -a <file>` ADDS the file to the gist: its content is
    // published, so it must be read (fail-closed), not merely scanned.
    const addFlag = (name === "-a" || name === "--add") && publishKey === "gh:gist:edit";
    const takesValue = addFlag || BODY_FILE_FLAGS.has(name) || FIELD_FLAGS.has(name);
    if (!takesValue) continue;
    const value = inlineValue ?? tokens[i + 1]?.value ?? null;
    if (inlineValue === null && value !== null) i++; // consumed the value token

    if (addFlag) {
      addFile(value, name);
      continue;
    }
    if (BODY_FILE_FLAGS.has(name)) {
      addFile(value ? (stripAt(value) ?? value) : null, name);
      continue;
    }
    if (FIELD_FLAGS.has(name) && value) {
      // `key=value`, or a bare `@file`, is an API field.
      if (value.includes("=") || value.startsWith("@")) {
        const rhs = value.includes("=") ? value.slice(value.indexOf("=") + 1) : value;
        addFile(stripAt(rhs), `${name} body=@…`);
        continue;
      }
      // …but on the verbs where gh spells `-F` as --body-file/--notes-file, the
      // bare value IS the published file: `gh pr create -F notes.md` sends
      // notes.md verbatim. Reading it only for `@` published it unscanned.
      if (name === "-F" && publishKey !== null && BODY_FILE_FIELD_FLAGS.has(publishKey)) {
        addFile(value, `${name} body-file`);
      }
    }
  }

  // `--body "$(cat notes.md)"` — the file is behind a substitution, so the
  // token walk above never sees it as a path. Every file a resolvable
  // substitution reads is added; an unresolvable one is reported instead.
  const subst = scanSubstitutions(cmd);
  for (const p of subst.files) addFile(p, "a command substitution");

  // The verb's own positionals (`gh gist create <file…>`, `gh release upload
  // <tag> <file…>`): no flag names these paths, so nothing above sees them.
  const unresolved = [...subst.unresolved];
  const positional = publishKey === null ? undefined : FILE_POSITIONALS[publishKey];
  if (positional && publishVerbIndex >= 0) {
    let named = 0;
    for (let i = publishVerbIndex + 1, pos = 0; i < tokens.length; i++) {
      const v = tokens[i].value;
      if (v.length === 0) continue;
      if (v === "-") {
        unresolved.push("stdin"); // a bare `-` is stdin, not a path
        continue;
      }
      if (v.startsWith("-")) {
        const name = flagName(v);
        const takesNext =
          !v.includes("=") &&
          (GLOBAL_VALUE_FLAGS.has(v) ||
            BODY_FILE_FLAGS.has(name) ||
            FIELD_FLAGS.has(name) ||
            VALUE_FLAGS.has(name));
        if (takesNext) i++; // the flag's own value is not a payload
        continue;
      }
      if (pos++ < positional.first) continue; // `release upload <tag> …`
      if (/[*?[]/.test(v)) unresolved.push("a glob argument");
      else {
        // Path-shaped or not, a positional here is a required file: skipping a
        // word like `id_rsa` published it unscanned (`gist create a.md id_rsa`).
        addFile(v, "a positional argument");
        named++;
      }
    }
    // No file to read: `gist create` falls back to stdin. `release upload`
    // with no asset is a usage error and says so, instead of claiming stdin.
    if (positional.stdin && named === 0 && unresolved.length === 0 && subst.files.length === 0 && subst.vars.length === 0) {
      unresolved.push("stdin");
    }
  }

  return {
    files,
    sources,
    vars: dedupe([...varRefs(cmd), ...subst.vars]),
    candidates,
    unresolved: dedupe(unresolved),
    cwdRelative: changesDirectory(tokens) ? files.filter(isRelativePath) : [],
  };
}

/**
 * Classify one gh/glab invocation (token `start` is the CLI itself).
 *
 * Group and verb are the first two WORD tokens, skipping flags — and the value
 * of a flag we know consumes one, so `gh -R org/repo pr create` resolves to
 * pr/create. An unknown pre-group flag could have eaten the group, so it makes
 * the whole invocation `unknown` rather than guessing.
 */
interface CliResolution {
  verdict: "publish" | "quiet" | "unknown";
  /** The group/verb the arguments belong to, when both were resolved. */
  group?: string;
  verb?: string;
  /** Index of the verb token, so the caller can read the verb's positionals. */
  verbIndex?: number;
}

function resolveCli(
  tokens: Token[],
  start: number,
  groups: Record<string, CliGroup>,
  isGh: boolean,
  textFlag: boolean,
): CliResolution {
  let group: string | undefined;
  let verb: string | undefined;
  let verbIndex: number | undefined;
  let unknownFlag = false;
  /** Every exit names the group/verb it resolved, so a verb-dependent flag
   *  (`-F`) can be read correctly by the caller. */
  const out = (verdict: CliResolution["verdict"]): CliResolution => ({ verdict, group, verb, verbIndex });

  for (let j = start + 1; j < tokens.length; j++) {
    const v = tokens[j].value;
    if (v.length === 0) continue;
    if (v.startsWith("-")) {
      if (v.includes("=") || GLOBAL_BOOLEAN_FLAGS.has(v)) continue;
      if (GLOBAL_VALUE_FLAGS.has(v)) {
        j++; // skip the flag's value too
        continue;
      }
      if (group === undefined) unknownFlag = true;
      continue;
    }
    if (group === undefined) {
      group = v;
      continue;
    }
    if (verb === undefined) {
      verb = v;
      verbIndex = j;
      break;
    }
  }

  // Only global flags: `gh --help`, `gh --version`. Nothing to publish.
  if (group === undefined) return out(unknownFlag ? "unknown" : "quiet");
  if (unknownFlag) return out("unknown");

  const table = groups[group];
  if (!table) {
    // `gh api` writes fields (-f/-F/--input); a GET publishes nothing. Both
    // flags are in TEXT_FLAGS, so this is the same over-approximation as before:
    // scanning an extra gh api GET is harmless, missing a field write is not.
    if (isGh && group === "api") return out(textFlag ? "publish" : "quiet");
    return out("unknown");
  }
  // `gh pr` with no verb: could be anything the group offers.
  if (verb === undefined) return out(table.publish.length + table.conditional.length > 0 ? "unknown" : "quiet");
  if (table.publish.includes(verb)) return out("publish");
  if (table.conditional.includes(verb)) return out(textFlag ? "publish" : "quiet");
  if (table.quiet.includes(verb)) return out("quiet");
  return out("unknown"); // a verb we do not know: assume it may write
}

/**
 * `bash -c "gh pr create …"` hides the whole invocation inside one quoted
 * token, so the walk above cannot see an argument position. Look one quoting
 * level inside when the CLI heads the payload *or heads any command in it* —
 * `sh -c "cd x && gh pr create …"` is code. Prose that merely names the verb in
 * argument position stays prose, though a payload that separates sentences with
 * `;` can still over-collect: fail-safe, and cheaper than a nested parse.
 * Recursion is quote-bounded.
 *
 * shortcut: only a segment HEAD is inspected, so a payload that reaches the CLI
 * through another runner (`bash -c "env bash -c 'gh pr create …'"`) is still
 * missed; upgrade to a real nested parse if that shape shows up in practice.
 */
function nestedTargets(tokens: Token[]): PublishTargets | null {
  const segmentHead = (segment: string): string => {
    const inner = tokenizeCommand(segment);
    return inner[0] ? baseName(inner[0].value) : "";
  };
  for (const tok of tokens) {
    if (!tok.quoted || tok.value.length === 0) continue;
    const heads = tok.value.split(/&&|\|\||[;|&\n]/).map(segmentHead);
    if (!heads.some((h) => h === "gh" || h === "glab")) continue;
    const nested = publishTargets(tok.value);
    if (nested) return nested;
  }
  return null;
}

