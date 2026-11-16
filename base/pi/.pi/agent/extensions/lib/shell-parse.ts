/**
 * Shell parsing for the mutation guard — zero dependencies on pi or any
 * framework. Split out of ./classify.ts, which re-exports every symbol here, so
 * the parsing half can be read and tested on its own.
 *
 * Everything here answers "what words did the shell write, and which of them
 * runs?": substitution unwrapping, basenames, dry-run / help allowances, lookup
 * segments, and findInvocations().
 */
export interface Invocation {
  cli: string;
  /** Positional tokens (flags excluded). */
  tokens: string[];
  /** Flag tokens as written (`--with-decryption`, `-o`, `--raw`). */
  flags: string[];
  fullCommand: string;
}

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
export function baseName(word: string): string {
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

export function isLookupSegment(words: string[]): boolean {
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
