/**
 * Pure classification logic for the mutation guard — zero dependencies on
 * pi or any framework. Kept separate from mutation-guard.ts so it can be
 * unit-tested with plain node/tsx without the pi runtime installed.
 *
 * Split by concern, both halves re-exported below so importers keep using this
 * file:
 *   ./shell-parse.ts   — what the shell wrote, and which word runs
 *   ./script-expand.ts — the bodies of the scripts a command executes
 *
 * What stays here is the decision: verb tables, secret-noun escalation, the
 * locked-gate read-only check, and the armed-gate confirm payload.
 * mutation-guard.ts adds only the pi wiring, so a rule change is testable
 * without a harness.
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

/** One flag-gated escalation rule: `verb` aimed at `flags` discloses material. */
export interface HighRiskFlagRule {
  verb: string;
  flags: string[];
}

export type Classification =
  | { kind: "read" }
  | { kind: "mutation"; highRisk: boolean }
  | { kind: "unknown" };


// ── split modules (re-exported: importers keep using this file) ──
// ./shell-parse.ts holds the words the shell wrote — normalizeCommand,
// findInvocations, isLookupSegment, baseName, and the two allowances: hasDryRun
// (the LAST dry-run-ish flag decides, because that is what the CLI does) and
// hasHelpFlag. ./script-expand.ts holds script-body expansion.

import { findInvocations, hasDryRun, hasHelpFlag } from "./shell-parse.ts";
import type { Invocation } from "./shell-parse.ts";
import { expandScripts } from "./script-expand.ts";
import type { ReadFile, ScriptExpansion } from "./script-expand.ts";

export * from "./shell-parse.ts";
export type { ReadFile, ScriptExpansion } from "./script-expand.ts";
export { SCRIPT_MAX_BYTES, writeTargets } from "./script-expand.ts";

/**
 * Inline the bodies of every shell script this command executes, so
 * classification sees what the script does rather than its filename. Defined in
 * ./script-expand.ts; re-exported here because importers address it here.
 */
export { expandScripts };

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

  // A global flag's VALUE can itself be a verb: `kubectl -n get delete deploy
  // api` is a namespace named `get`, so token 0 is a known read verb and the
  // real verb is token 1 — the read path below took it and the delete passed a
  // locked gate. Only token 1 is considered (that is the exact artifact of one
  // flag consuming the verb slot); a resource name further along must not block
  // `kubectl get <resource> <name>`. Exact membership only: a ROOT match here
  // made the resource name a verb (`kubectl logs label-studio-0` reads as
  // `label`), blocking benign reads.
  if (lower[1] && (isHighRiskVerb(tool, lower[1]) || tool.mutation.has(lower[1]))) {
    return { kind: "mutation", highRisk: isHighRiskVerb(tool, lower[1]) };
  }
  // The flag's value can be a word that reads as a verb too: `kubectl -n get
  // rollout restart deploy/x` leaves `get` in token 1, so the real two-word
  // verb is the group pair 2/3 (`config use-context` in the same shape). Only
  // group pairs are looked for past token 1 — a lone token 2 is never a verb,
  // so `kubectl get pods delete` stays a read.
  for (let k = 1; k + 1 < lower.length; k++) {
    if (!tool.groupPrefixes?.has(lower[k])) continue;
    const cand = `${lower[k]} ${lower[k + 1]}`;
    if (isHighRiskVerb(tool, cand) || tool.mutation.has(cand)) {
      return { kind: "mutation", highRisk: isHighRiskVerb(tool, cand) };
    }
  }

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

// ── invocation verdicts (shared by both gate modes) ──────────────

export interface InvocationVerdict {
  inv: Invocation;
  tool: ToolConfig;
  result: Classification;
  /** True when this invocation came from an inlined script body (depth >= 1)
   *  rather than from the command the caller typed. An unrecognised verb at
   *  that depth is recorded as a note, not enforced — see `nestedNotes`. */
  nested: boolean;
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
  /** Shapes recorded but NOT enforced: whatever the walk could not resolve
   *  inside an already-inlined body (depth >= 1), plus an unrecognised verb
   *  found there. Reported to the user, never a block — the honest claim is
   *  that intent hidden inside a script's own indirection is best-effort. */
  nestedNotes: string[];
}

/** A key that identifies the same invocation in the command text and in the
 *  expanded text, so a verdict can be attributed to its depth. */
function invocationKey(inv: Invocation): string {
  return [inv.cli, ...inv.tokens, "\u0000", ...inv.flags, "\u0000", inv.fullCommand].join("\u0000");
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
 *
 * Depth policy (see ./script-expand.ts): an invocation is `nested` when it came
 * from an inlined body rather than the command itself. A nested *mutation* still
 * blocks — `sh /tmp/x.sh` must not smuggle a delete — but a nested
 * *unrecognised verb* is a note, not an unknown, because inside a large script
 * (this repo's own `check.sh`) most verb-shaped words are quoted prose and
 * grep patterns, and failing closed on all of them made the suite unrunnable.
 */
export function classifyInvocations(
  command: string,
  cliNames: Set<string>,
  toolByName: ReadonlyMap<string, ToolConfig>,
  readFile?: ReadFile,
): CommandVerdicts {
  const { text, unresolved, unknowns, nestedNotes } = expandScripts(command, readFile ?? (() => null));
  const invocations = findInvocations(text, cliNames);
  const verdicts: InvocationVerdict[] = [];
  const notes = [...nestedNotes];

  // The expanded text is `command` then the bodies, so the depth-0 invocations
  // are found first. Counting them makes attribution an in-order match: an
  // invocation whose key is still available at depth 0 IS the depth-0 one.
  // Anything left over came from a body. A body that repeats the command's own
  // text reads as depth 0, which only makes the gate stricter.
  const atDepth0 = new Map<string, number>();
  for (const inv of findInvocations(command, cliNames)) {
    const key = invocationKey(inv);
    atDepth0.set(key, (atDepth0.get(key) ?? 0) + 1);
  }

  for (const inv of invocations) {
    const tool = toolByName.get(inv.cli);
    if (!tool) continue;
    // A real dry-run performs nothing; help/version prints documentation.
    if (hasDryRun(inv.fullCommand) || hasHelpFlag(inv.fullCommand)) continue;
    const key = invocationKey(inv);
    const remaining = atDepth0.get(key) ?? 0;
    const nested = remaining === 0;
    if (!nested) atDepth0.set(key, remaining - 1);

    const result = classify(tool, inv.tokens, inv.flags);
    if (nested && result.kind === "unknown") {
      const verb = inv.tokens.slice(0, 2).join(" ") || inv.cli;
      notes.push(`${inv.cli} ${verb}: unrecognised verb inside an inlined script body, so not enforced`);
    }
    verdicts.push({ inv, tool, result, nested });
  }

  return { text, invocations, verdicts, unresolved, unknowns, nestedNotes: notes };
}

/** What one command inspection yields: the blocking issues a locked gate acts
 *  on, plus the depth >= 1 notes it only reports. */
export interface CommandInspection {
  /** One message per blocking issue. Empty means read-only-safe. */
  issues: string[];
  /** Depth >= 1 findings: reported to the user, never a block. */
  nestedNotes: string[];
}

/**
 * Locked-gate inspection: what blocks, and what is only worth a notice.
 *
 * Depth 0 keeps the fail-closed behaviour (`unresolved`, `unknowns`, a mutation
 * or an unrecognised verb in the command itself). Depth >= 1 contributes
 * `nestedNotes` instead, with one exception kept from the original contract: a
 * *recognised mutation* inside an inlined body still blocks, because that is
 * the whole point of inlining the body.
 */
export function inspectCommand(
  command: string,
  cliNames: Set<string>,
  toolByName: ReadonlyMap<string, ToolConfig>,
  domain: string,
  readFile?: ReadFile,
): CommandInspection {
  const { verdicts, unresolved, unknowns, nestedNotes } = classifyInvocations(
    command,
    cliNames,
    toolByName,
    readFile,
  );
  const issues: string[] = [];

  if (unresolved.length > 0) {
    issues.push(
      `${unresolved.join(", ")}: script body unreadable or too large to inspect — unknown, blocked: ${domain} gate is locked.`,
    );
  }

  for (const unknown of unknowns) {
    issues.push(`${unknown} — unknown, blocked: ${domain} gate is locked.`);
  }

  for (const { inv, result, nested } of verdicts) {
    const verb = inv.tokens.slice(0, 2).join(" ") || inv.cli;
    if (result.kind === "mutation") {
      issues.push(
        `${inv.cli} ${verb}: ${result.highRisk ? "high-risk op" : "mutation"} blocked: ${domain} gate is locked.`,
      );
    } else if (result.kind === "unknown" && !nested) {
      issues.push(`${inv.cli} ${verb}: unrecognised verb, blocked: ${domain} gate is locked.`);
    }
  }

  return { issues, nestedNotes };
}

/**
 * Locked-gate read-only check: one message per offending invocation, empty when
 * the command is read-only-safe. An uninspectable script the command names is
 * reported as unknown, so the locked gate blocks what it cannot verify; shapes
 * the walk could not resolve inside an inlined body are notes, not issues.
 */
export function checkCommandReadOnly(
  command: string,
  cliNames: Set<string>,
  toolByName: ReadonlyMap<string, ToolConfig>,
  domain: string,
  readFile?: ReadFile,
): string[] {
  return inspectCommand(command, cliNames, toolByName, domain, readFile).issues;
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
