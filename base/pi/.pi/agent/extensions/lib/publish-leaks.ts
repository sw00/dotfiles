/**
 * Known credential values for the publish guard — zero dependencies on pi or
 * any framework. Split out of ./publish-scan.ts, which re-exports the types
 * here, and holds the decision (`scan`) that consumes them.
 *
 * The exact-value half of L4: the $NAMEs in secrets/env.fish are parsed here, so
 * a credential in the model's context can be matched by value even when no
 * gitleaks rule recognises its shape. A git-crypt locked (ciphertext) or binary
 * file yields no values rather than garbage ones.
 */

// ── known credential values (secrets/env.fish) ───────────────────────────────

export interface KnownValue {
  /** Variable name, with or without a leading `$`. */
  name: string;
  value: string;
}

/** Shorter values would match ordinary prose; the spec says ">= 12 chars". */
export const MIN_VALUE_LEN = 12;

/** `set -gx NAME 'value'` — fish's own form, as written in secrets/env.fish. */
const ENV_LINE = /^\s*set\s+-[A-Za-z]*x[A-Za-z]*\s+([A-Za-z_][A-Za-z0-9_]*)\s+(.+?)\s*$/;
/** Placeholder shapes that are not credentials (never block on the template). */
export const PLACEHOLDER = /^(?:x{8,}|\*{6,}|<.*>|changeme.*|your[_-].*|example.*|\.\.\.)$/i;

function unquoteFish(raw: string): string {
  const first = raw[0];
  if (first !== "'" && first !== '"') return raw.replace(/\\(.)/g, "$1");
  const last = raw.lastIndexOf(first);
  const body = last > 0 ? raw.slice(1, last) : raw.slice(1);
  return body.replace(/\\(['"\\$])/g, "$1");
}

/**
 * Parse credential values out of secrets/env.fish text.
 *
 * A git-crypt LOCKED file is ciphertext: it is skipped (returns []) rather than
 * mis-parsed, and the wiring BLOCKS the publish instead of pretending the
 * exact-value half ran.
 */
export function parseSecretValues(envFileText: string): KnownValue[] {
  const head = envFileText.slice(0, 16);
  if (head.includes("GITCRYPT") || envFileText.includes("\u0000")) return []; // ciphertext
  const out: KnownValue[] = [];
  for (const line of envFileText.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed.length === 0 || trimmed.startsWith("#")) continue;
    const m = ENV_LINE.exec(line);
    if (!m) continue;
    const value = unquoteFish(m[2]);
    if (value.length < MIN_VALUE_LEN || PLACEHOLDER.test(value)) continue;
    if (out.some((k) => k.name === m[1])) continue;
    out.push({ name: m[1], value });
  }
  return out;
}

/** Result of running the secret scanner over the outgoing text. The wiring owns
 *  the process; this type is the seam that keeps the tests hermetic. */
export type LeakScan =
  | { kind: "ok"; ruleIds: string[] }
  | { kind: "error"; detail: string };

export interface ScanVerdict {
  /** `<ruleId>` or `value of $NAME` — never the matched secret. */
  label: string;
  /** Ready-to-return block reason; the template lives with the decision in
   *  ./publish-scan.ts so the "never echo the secret" property is unit-tested
   *  rather than re-implemented. */
  reason: string;
  /** True when the scanner could not run and we blocked on that instead of on
   *  a match (fail-closed). */
  failClosed?: boolean;
}
