/**
 * Pure scan core for the publish guard (class (c): a credential already in the
 * model's context pasted into a published artifact).
 *
 * pi-free and IO-free, so it runs standalone under
 * `node --experimental-strip-types --test` (see ./publish-scan.test.ts). The pi
 * wiring, filesystem reads and the gitleaks process live in the thin top-level
 * ../publish-guard.ts, mirroring infra-safety.ts ↔ lib/mutation-guard.ts and
 * edit-guardian.ts ↔ lib/edit-diagnostic.ts.
 *
 * Split by concern, re-exported here so callers need one module:
 *   ./publish-targets.ts — is this command publishing text? what files/vars?
 *   ./publish-leaks.ts   — known credential values, scanner result, verdict
 *   this file            — the decision: scan() and its block reason
 *
 * Fail-closed: a scanner that could not run is a MATCH, not a pass. The block
 * reason it returns names the rule (or the variable) and never the matched
 * value, so the secret is not copied into the transcript a second time.
 */

// ── the decision ─────────────────────────────────────────────────────────────

import { parseSecretValues } from "./publish-leaks.ts";
import type { LeakScan, ScanVerdict } from "./publish-leaks.ts";

export * from "./publish-targets.ts";
export { isGitCryptLocked } from "./publish-leaks.ts";
export type { KnownValue, LeakScan, ScanVerdict } from "./publish-leaks.ts";

/**
 * Decide whether `text` can be published.
 *
 * `known` is the raw text of secrets/env.fish, parsed here.
 * `leaks` is the injected scanner result; an error/timeout is a MATCH.
 */
export function scan(text: string, known: string, leaks: LeakScan): ScanVerdict | null {
  if (leaks.kind === "error") {
    return {
      reason:
        `publish-guard: blocked — outgoing text could not be scanned (${leaks.detail}); ` +
        `publishing unscanned is not allowed. Fix the scanner, then retry.`,
    };
  }

  const ruleId = leaks.ruleIds.find((r) => typeof r === "string" && r.length > 0);
  if (ruleId) {
    return { reason: matchReason(ruleId) };
  }

  for (const { name, value } of parseSecretValues(known)) {
    if (!text.includes(value)) continue;
    return { reason: matchReason(`value of $${name}`) };
  }

  return null;
}

function matchReason(label: string): string {
  return `publish-guard: blocked — outgoing text matches ${label}. Remove it; do not repeat it.`;
}
