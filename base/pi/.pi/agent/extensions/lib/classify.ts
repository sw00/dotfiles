/**
 * Pure classification logic for the mutation guard — zero dependencies on
 * pi or any framework. Kept separate from mutation-guard.ts so it can be
 * unit-tested with plain node/tsx without the pi runtime installed.
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
  /** Optional best-effort live context (e.g. current kubectl context) shown in confirms. */
  getContext?: () => Promise<string | null>;
}

export interface Invocation {
  cli: string;
  tokens: string[];
  fullCommand: string;
}

export type Classification =
  | { kind: "read" }
  | { kind: "mutation"; highRisk: boolean }
  | { kind: "unknown" };

// ── parsing ──────────────────────────────────────────────────────

/** Unwrap $(...), backticks, <(...) so a nested CLI becomes a plain word. */
export function normalizeCommand(command: string): string {
  return command.replace(/\$\(/g, " ").replace(/`/g, " ").replace(/[<>]\(/g, " ");
}

/** Basename, so `/usr/local/bin/aws` → `aws`. */
function baseName(word: string): string {
  return word.replace(/^\\/, "").split("/").pop() ?? word;
}

/**
 * True for a genuine dry-run flag. Deliberately excludes --dry-run=none /
 * =false (kubectl's "actually do it" value) so those do NOT bypass the guard.
 * \b can't anchor before "--", so we anchor on whitespace/start.
 */
export function hasDryRun(command: string): boolean {
  return /(?:^|\s)--(?:what-if|dry-?run(?:=(?:client|server|true|only))?)(?=\s|$)/.test(command);
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

  for (const segment of normalizeCommand(command).split(/[|;&\n\r]+/)) {
    const words = segment.trim().split(/\s+/).filter(Boolean);
    const cliIdx: number[] = [];
    for (let i = 0; i < words.length; i++) {
      if (cliNames.has(baseName(words[i]))) cliIdx.push(i);
    }

    for (let k = 0; k < cliIdx.length; k++) {
      const start = cliIdx[k];
      const end = k + 1 < cliIdx.length ? cliIdx[k + 1] : words.length;
      const tokens: string[] = [];
      for (let j = start + 1; j < end; j++) {
        if (!words[j].startsWith("-")) tokens.push(words[j]);
      }
      results.push({
        cli: baseName(words[start]),
        tokens,
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

export function classify(tool: ToolConfig, tokens: string[]): Classification {
  if (tokens.length === 0) return { kind: "read" }; // bare CLI = help/usage

  if (tool.verbPosition === "any") {
    const verbs = tokens.map((t) => t.toLowerCase()).filter(isVerb);
    if (tool.highRisk && verbs.some((v) => verbMatches(v, tool.highRisk!))) {
      return { kind: "mutation", highRisk: true };
    }
    if (verbs.some((v) => verbMatches(v, tool.mutation))) return { kind: "mutation", highRisk: false };
    if (verbs.some((v) => verbMatches(v, tool.read))) return { kind: "read" };
    return { kind: "unknown" };
  }

  // verbPosition === "first"
  const first = tokens[0].toLowerCase();
  const verb = tool.groupPrefixes?.has(first) && tokens[1] ? `${first} ${tokens[1].toLowerCase()}` : first;

  if (tool.alwaysRead?.has(verb)) return { kind: "read" };
  if (tool.highRisk?.has(verb) || tool.highRisk?.has(first)) return { kind: "mutation", highRisk: true };
  if (verbMatches(verb, tool.mutation) || verbMatches(first, tool.mutation)) return { kind: "mutation", highRisk: false };
  if (verbMatches(verb, tool.read) || verbMatches(first, tool.read)) return { kind: "read" };
  return { kind: "unknown" };
}
