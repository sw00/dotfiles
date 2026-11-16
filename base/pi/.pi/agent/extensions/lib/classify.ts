/**
 * Pure classification logic for the mutation guard — zero dependencies on
 * pi or any framework. Kept separate from mutation-guard.ts so it can be
 * unit-tested with plain node/tsx without the pi runtime installed.
 *
 * Everything the gate decides lives here: invocation finding, verb tables,
 * secret-noun escalation, script-body expansion, the locked-gate read-only
 * check, and the armed-gate confirm payload. mutation-guard.ts adds only the
 * pi wiring, so a rule change is testable without a harness.
 */

export type VerbPosition = "any" | "first";

export interface ToolConfig {
  /** Executable name(s) sharing this grammar, e.g. ["terraform", "tofu"]. */
  names: string[];
  /** "any" = verb anywhere (aws/az/gcloud); "first" = verb is token 1 (kubectl/terraform). */
  verbPosition: VerbPosition;
  /** "first" only: prefixes whose real verb is the 2nd token ("config use-context", "state rm"). */
  groupPrefixes?: Set<string>;
  /** Effective verbs always read-only regardless of trailing args ("auth can-i delete pods"). */
  alwaysRead?: Set<string>;
  read: Set<string>;
  mutation: Set<string>;
  /** Always-mutation verbs that also get an extra-strength prompt (kubectl exec, terraform destroy). */
  highRisk?: Set<string>;
  /** Read-ish verbs that only disclose material when carrying a specific flag
   *  (`aws ssm get-parameter --with-decryption`, `terraform show -json`).
   *  A verb listed without its flag stays an ordinary read. */
  highRiskFlags?: HighRiskFlagRule[];
  /** Resource nouns whose *content* is credential material (secret, secrets, …).
   *  A read-ish verb aimed at one of these discloses material, so the command
   *  classifies high-risk even though the verb alone is read-only. */
  secretNouns?: Set<string>;
  /** Verbs that report *metadata* about a secret even when aimed at one of the
   *  secretNouns (`kubectl describe secret db-creds` prints keys and sizes, not
   *  values). Enumerating verbs are covered by ENUMERATION_VERBS; this is for
   *  the verbs that read a single named secret without opening it. */
  secretMetadataVerbs?: Set<string>;
  /** Optional best-effort live context (e.g. current kubectl context) shown in confirms. */
  getContext?: () => Promise<string | null>;
}

export interface Invocation {
  cli: string;
  /** Positional tokens (flags excluded). */
  tokens: string[];
  /** Flag tokens as written (`--with-decryption`, `-o`, `--raw`). */
  flags: string[];
  fullCommand: string;
}

/** One flag-gated escalation rule: `verb` aimed at `flags` discloses material. */
export interface HighRiskFlagRule {
  verb: string;
  flags: string[];
}

export type Classification =
  | { kind: "read" }
  | { kind: "mutation"; highRisk: boolean }
  | { kind: "unknown" };

// ── parsing ──────────────────────────────────────────────────────

/** Unwrap $(...), backticks, <(...) so a nested CLI becomes a plain word, and
 *  drop shell quote characters: quotes only wrap words, and a quoted payload
 *  (`bash -c "terraform destroy"`) must resolve to the real command names
 *  instead of hiding the verb behind a trailing quote. */
export function normalizeCommand(command: string): string {
  return command
    .replace(/\$\(/g, " ")
    .replace(/`/g, " ")
    .replace(/[<>]\(/g, " ")
    .replace(/["']/g, "");
}

/** Basename, so `/usr/local/bin/aws` → `aws`. Leading/trailing shell quotes are
 *  stripped too, so `bash -c "kubectl delete pod x"` resolves the quoted words
 *  to real command names instead of hiding them behind a quote character.
 *  Backslashes are removed too: shell escaping means `ku\bectl` *is* `kubectl`,
 *  and an escape must not launder a command name. Also strips a leading `(`,
 *  because `(terraform destroy)` carries its verb inside a subshell paren. */
function baseName(word: string): string {
  const unescaped = word.replace(/\\/g, "");
  const unquoted = unescaped.replace(/^[("']+/, "").replace(/["',;|&)]+$/, "");
  return unquoted.split("/").pop() ?? unquoted;
}

/** Everything before the first standalone `--`. Past it the arguments belong
 *  to the command being wrapped (`kubectl exec pod -- sh -c '…'`), so a flag
 *  there says nothing about the CLI this segment is classified as. */
function beforeEndOfFlags(command: string): string {
  const sep = command.search(/(?:^|\s)--(?=\s|$)/);
  return sep === -1 ? command : command.slice(0, sep);
}

/**
 * True for a genuine dry-run flag. The LAST dry-run-ish flag decides, because
 * that is what the CLI does: the last flag wins, so
 * `--dry-run=client --dry-run=none` performs the delete for real and only
 * `--dry-run=client` alone would have been harmless. `=none` / `=false` (and
 * any value the CLI does not recognise as a dry run) is not a dry run.
 * \b can't anchor before "--", so we anchor on whitespace/start.
 */
export function hasDryRun(command: string): boolean {
  let verdict = false;
  // one pass over every occurrence, so the last one wins
  for (const m of beforeEndOfFlags(command).matchAll(/(?:^|\s)--(?:what-if|dry-?run)(?:=([A-Za-z-]+))?(?=\s|$)/g)) {
    verdict = m[1] === undefined || /^(?:client|server|true|only)$/i.test(m[1]);
  }
  return verdict;
}

/** True for --help / -h: the command prints documentation and performs
 *  nothing, so an invocation carrying one is a read. The allowance stops at the
 *  first standalone `--`: past it the flags belong to the command being wrapped
 *  (`kubectl exec pod -- sh -c '…' -h`), not to the CLI being classified.
 *  `--version` is deliberately NOT an allowance — it says nothing about what
 *  the rest of the command does, and it waved `kubectl delete pod x` through. */
export function hasHelpFlag(command: string): boolean {
  return /(?:^|\s)(?:--help|-h)(?=\s|$)/.test(beforeEndOfFlags(command));
}

/** A substitution is code, not a word: `$( )`, backticks, `<( )`, `>( )`. */
export function hasSubstitution(text: string): boolean {
  return /\$\(|`|[<>]\(/.test(text);
}

/**
 * Segments led by one of these only *look up* a command (which/type/whereis/
 * `command -v`). Nothing they name is executed, so the named CLI must not be
 * classified (`which -a aws kubectl` is read-only; `aws s3 rm x && which aws`
 * still gates the first segment).
 */
const LOOKUP_LEAD = new Set(["which", "type", "whereis"]);

function isLookupSegment(words: string[]): boolean {
  const first = words[0] ? baseName(words[0]) : "";
  if (LOOKUP_LEAD.has(first)) return true;
  return first === "command" && (words[1] === "-v" || words[1] === "-V");
}

/** Strip shell wrappers from a token: `(destroy)` → `destroy`, `destroy)` → `destroy`. */
function tokenText(word: string): string {
  const unescaped = word.replace(/\\/g, "");
  return unescaped.replace(/^[("']+/, "").replace(/["'),;|&]+$/, "");
}

/**
 * Find every configured-CLI invocation. Splits on shell separators AND
 * newlines, handles command substitution, absolute paths, and multiple
 * CLIs per segment (e.g. `aws ... $(kubectl delete ...)`). Keeps all
 * non-flag tokens — over-collecting only adds false positives (fail safe);
 * skipping risks swallowing the verb (fail open).
 */
export function findInvocations(command: string, cliNames: Set<string>): Invocation[] {
  const results: Invocation[] = [];

  // Split the RAW text: normalizeCommand flattens `$(…)`/backticks to spaces, so
  // the substitution has to be visible when deciding what the segment is.
  for (const rawSegment of command.split(/[|;&\n\r]+/)) {
    const words = normalizeCommand(rawSegment).trim().split(/\s+/).filter(Boolean);
    // `which aws` names aws, it does not run it. But the exemption is only
    // honest when the segment really is just a lookup: a substitution inside
    // it is code, and normalization turned it into ordinary-looking words
    // (`which $(aws s3 rm s3://b)` is an aws call, not a lookup of aws).
    if (!hasSubstitution(rawSegment) && isLookupSegment(words)) continue;
    const cliIdx: number[] = [];
    for (let i = 0; i < words.length; i++) {
      if (cliNames.has(baseName(words[i]))) cliIdx.push(i);
    }

    for (let k = 0; k < cliIdx.length; k++) {
      const start = cliIdx[k];
      const end = k + 1 < cliIdx.length ? cliIdx[k + 1] : words.length;
      const tokens: string[] = [];
      const flags: string[] = [];
      for (let j = start + 1; j < end; j++) {
        if (words[j].startsWith("-")) flags.push(words[j]);
        else tokens.push(tokenText(words[j]));
      }
      results.push({
        cli: baseName(words[start]),
        tokens,
        flags,
        fullCommand: words.slice(start, end).join(" "),
      });
    }
  }

  return results;
}

// ── classification ───────────────────────────────────────────────

/** Verb-shaped: lowercase word (hyphen/underscore segments), no path/URL/ARN chars. */
function isVerb(token: string): boolean {
  return /^[a-z][a-z0-9]*(?:[-_][a-z0-9]+)*$/.test(token);
}

/** Exact, or root-word (before first -/_) membership. "run-instances" → root "run". */
function verbMatches(verb: string, set: Set<string>): boolean {
  if (set.has(verb)) return true;
  const i = verb.search(/[-_]/);
  return i > 0 && set.has(verb.slice(0, i));
}

/** Read verbs that only enumerate resource *names*, so pairing one with a
 *  secret noun reveals metadata, not material (`aws secretsmanager
 *  list-secrets`, `list-secret-version-ids`). Everything else is matched
 *  exactly, because the verbs that hand out a value are named one by one
 *  (`get-secret-value`, `batch-get-secret-value`, `get-parameters`). */
const ENUMERATION_VERBS = new Set(["list", "ls", "list-secrets"]);

/**
 * Read-ish verb + credential noun = disclosure.
 * `aws secretsmanager get-secret-value` root-reduces to "get", which sits in
 * the read set, so before this rule a LOCKED gate happily allowed a secret
 * read (class-b hole). dry-run does not make a secret read harmless, and a
 * mutation verb is already caught earlier.
 */
function disclosesSecret(tool: ToolConfig, tokens: string[], verb: string): boolean {
  if (!tool.secretNouns?.size) return false;
  if (ENUMERATION_VERBS.has(verb)) return false;
  // Metadata verbs describe the object, they do not open it: `kubectl describe
  // secret` prints key names and byte counts, so it stays a read.
  if (tool.secretMetadataVerbs && verbMatches(verb, tool.secretMetadataVerbs)) return false;
  // Resource tokens carry a scope and a list: `secret/db-creds`, `secret,cm`.
  // A URI is one token, not a resource path — `s3://bucket/secret` is a prefix
  // name, and splitting it would block a plain listing as a secret read.
  const parts = (t: string) => (t.includes("://") ? [t] : t.split(/[/,]/));
  return tokens.some((t) =>
    parts(t.toLowerCase()).some((part) => tool.secretNouns!.has(part)),
  );
}

/** True when any of `verbs` is paired with one of its disclosing flags. */
function flagEscalates(rules: HighRiskFlagRule[] | undefined, verbs: string[], flags: string[]): boolean {
  if (!rules?.length) return false;
  const given = new Set(flags.map((f) => f.split("=")[0]));
  return rules.some(
    (r) => verbs.includes(r.verb) && r.flags.some((f) => given.has(f)),
  );
}

/** True when the token is a verb this tool knows anything about. */
function isKnownVerb(tool: ToolConfig, verb: string): boolean {
  if (tool.alwaysRead?.has(verb) || tool.highRisk?.has(verb)) return true;
  return verbMatches(verb, tool.mutation) || verbMatches(verb, tool.read);
}

/** High-risk verbs match the WHOLE verb, never a root word: root-matching let
 *  gcloud's `access` (a credential read: `secrets versions access`) swallow
 *  `access-context-manager policies list`, a plain read, because the word
 *  before the first hyphen was `access`. Every high-risk entry is written out
 *  in full, so exact matching loses nothing. */
function isHighRiskVerb(tool: ToolConfig, verb: string): boolean {
  return tool.highRisk?.has(verb) ?? false;
}

export function classify(tool: ToolConfig, tokens: string[], flags: string[] = []): Classification {
  if (tokens.length === 0) return { kind: "read" }; // bare CLI = help/usage

  if (tool.verbPosition === "any") {
    const verbs = tokens.map((t) => t.toLowerCase()).filter(isVerb);
    if (tool.highRisk && verbs.some((v) => isHighRiskVerb(tool, v))) {
      return { kind: "mutation", highRisk: true };
    }
    if (flagEscalates(tool.highRiskFlags, verbs, flags)) return { kind: "mutation", highRisk: true };
    if (verbs.some((v) => verbMatches(v, tool.mutation))) return { kind: "mutation", highRisk: false };
    const readVerbs = verbs.filter((v) => verbMatches(v, tool.read));
    if (readVerbs.length > 0) {
      if (readVerbs.some((v) => disclosesSecret(tool, tokens, v))) return { kind: "mutation", highRisk: true };
      return { kind: "read" };
    }
    return { kind: "unknown" };
  }

  // verbPosition === "first"
  const lower = tokens.map((t) => t.toLowerCase());
  const first = lower[0];
  let verb = tool.groupPrefixes?.has(first) && lower[1] ? `${first} ${lower[1]}` : first;
  // A global flag's *value* is not the verb: `kubectl -n prod delete pod x`
  // leaves "prod" in token 0 and `terraform -var x=y destroy` leaves "x=y", so
  // the real verb sat behind an unrecognised token and the command came out
  // unknown (silently unwatched in an armed gate). Walk forward to the first
  // token that is a known verb.
  if (!isKnownVerb(tool, verb)) {
    for (let k = 1; k < lower.length; k++) {
      const cand = tool.groupPrefixes?.has(lower[k]) && lower[k + 1] ? `${lower[k]} ${lower[k + 1]}` : lower[k];
      if (isKnownVerb(tool, cand)) {
        verb = cand;
        break;
      }
    }
  }
  const verbCandidates = verb === first ? [verb] : [verb, first];

  if (tool.alwaysRead?.has(verb)) return { kind: "read" };
  if (isHighRiskVerb(tool, verb) || isHighRiskVerb(tool, first)) return { kind: "mutation", highRisk: true };
  if (flagEscalates(tool.highRiskFlags, verbCandidates, flags)) return { kind: "mutation", highRisk: true };
  if (verbMatches(verb, tool.mutation) || verbMatches(first, tool.mutation)) return { kind: "mutation", highRisk: false };
  if (verbMatches(verb, tool.read) || verbMatches(first, tool.read)) {
    if (disclosesSecret(tool, tokens, verb) || disclosesSecret(tool, tokens, first)) {
      return { kind: "mutation", highRisk: true };
    }
    return { kind: "read" };
  }
  return { kind: "unknown" };
}

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
  if (!word || /^["']/.test(word)) return false; // a quoted word never expands
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
    ctx.unknowns.push(`${raw}: variable command word, cannot resolve what runs`);
    return;
  }

  // A word the shell assembles is not the word that runs — never a read.
  if (hasExpansion(raw)) {
    ctx.unknowns.push(`${raw}: command word built by shell expansion, cannot resolve what runs`);
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
        ctx.unknowns.push(`${cmd}: reads its script from stdin or a pipeline, cannot inspect it`);
        return;
      }
      // `find -exec sh {} +`: the path is only known once find has run.
      if (FIND_PLACEHOLDER.test(unquote(scriptArg))) {
        ctx.unknowns.push(`${cmd} ${scriptArg}: script path is a run-time placeholder, cannot inspect it`);
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
      ctx.unknowns.push(
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
      if (declaredShell) ctx.unresolved.push(path);
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
      scoped.unknowns.push(`${rawWord}: command word built by shell expansion, cannot resolve what runs`);
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
    written: new Set(),
    depth: 0,
  };
  collectScripts(command, ctx);
  if (ctx.bodies.length === 0) return { text: command, unresolved: ctx.unresolved, unknowns: ctx.unknowns };
  return { text: [command, ...ctx.bodies].join("\n"), unresolved: ctx.unresolved, unknowns: ctx.unknowns };
}

// ── invocation verdicts (shared by both gate modes) ──────────────

export interface InvocationVerdict {
  inv: Invocation;
  tool: ToolConfig;
  result: Classification;
}

export interface CommandVerdicts {
  /** The command with every inspected script body inlined — what a human must
   *  be shown, because the launcher line hides the payload. */
  text: string;
  /** Every guarded invocation found, including dry-run/help ones. */
  invocations: Invocation[];
  /** The invocations that actually do something, with their classification. */
  verdicts: InvocationVerdict[];
  /** Scripts that could not be inspected — an unknown the gate must not pass. */
  unresolved: string[];
  /** Executing shapes with no inspectable body (pipe into a shell, `$VAR`). */
  unknowns: string[];
}

/**
 * The single classification pipeline both gate modes run: expand scripts,
 * find invocations, drop real dry-runs and help/version requests, classify the
 * rest. Keeping it here (not in mutation-guard.ts) means the tests exercise the
 * exact code the gate runs.
 *
 * Expansion always runs, even without a reader: the shapes it cannot resolve
 * (pipe-into-shell, `$VAR`) are found by the same walk, and a script nobody can
 * read is an unknown either way. A missing reader therefore means "cannot
 * inspect", never "nothing to inspect".
 */
export function classifyInvocations(
  command: string,
  cliNames: Set<string>,
  toolByName: ReadonlyMap<string, ToolConfig>,
  readFile?: ReadFile,
): CommandVerdicts {
  const { text, unresolved, unknowns } = expandScripts(command, readFile ?? (() => null));
  const invocations = findInvocations(text, cliNames);
  const verdicts: InvocationVerdict[] = [];

  for (const inv of invocations) {
    const tool = toolByName.get(inv.cli);
    if (!tool) continue;
    // A real dry-run performs nothing; help/version prints documentation.
    if (hasDryRun(inv.fullCommand) || hasHelpFlag(inv.fullCommand)) continue;
    verdicts.push({ inv, tool, result: classify(tool, inv.tokens, inv.flags) });
  }

  return { text, invocations, verdicts, unresolved, unknowns };
}

/**
 * Locked-gate read-only check: one message per offending invocation, empty when
 * the command is read-only-safe. An uninspectable script is reported as
 * unknown, so the locked gate blocks what it cannot verify.
 */
export function checkCommandReadOnly(
  command: string,
  cliNames: Set<string>,
  toolByName: ReadonlyMap<string, ToolConfig>,
  domain: string,
  readFile?: ReadFile,
): string[] {
  const { verdicts, unresolved, unknowns } = classifyInvocations(command, cliNames, toolByName, readFile);
  const issues: string[] = [];

  if (unresolved.length > 0) {
    issues.push(
      `${unresolved.join(", ")}: script body unreadable or too large to inspect — unknown, blocked: ${domain} gate is locked.`,
    );
  }

  for (const unknown of unknowns) {
    issues.push(`${unknown} — unknown, blocked: ${domain} gate is locked.`);
  }

  for (const { inv, result } of verdicts) {
    const verb = inv.tokens.slice(0, 2).join(" ") || inv.cli;
    if (result.kind === "mutation") {
      issues.push(
        `${inv.cli} ${verb}: ${result.highRisk ? "high-risk op" : "mutation"} blocked: ${domain} gate is locked.`,
      );
    } else if (result.kind === "unknown") {
      issues.push(`${inv.cli} ${verb}: unrecognised verb, blocked: ${domain} gate is locked.`);
    }
  }

  return issues;
}

// ── armed-gate confirm payload (4c) ──────────────────────────────

/** Longest command the human is asked to review in one confirmation. */
export const CONFIRM_LIMIT = 2000;

export type ConfirmPayload = { ok: true; text: string } | { ok: false; reason: string };

/**
 * What the armed confirmation shows. Never a truncated command: a payload
 * hidden past the cut is a payload the human cannot judge (a `slice(0, 400)`
 * used to hide whatever sat past character 400). Past CONFIRM_LIMIT the
 * command is refused outright, so the only way forward is to split it.
 */
export function confirmPayload(command: string): ConfirmPayload {
  if (command.length > CONFIRM_LIMIT) {
    return {
      ok: false,
      reason: `command too long to confirm (${command.length} > ${CONFIRM_LIMIT} chars); split it into smaller commands.`,
    };
  }
  return { ok: true, text: command };
}
