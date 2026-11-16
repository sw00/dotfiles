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

import { MIN_VALUE_LEN, PLACEHOLDER, parseSecretValues } from "./publish-leaks.ts";
import type { KnownValue, LeakScan, ScanVerdict } from "./publish-leaks.ts";

export * from "./publish-targets.ts";
export type { KnownValue, LeakScan, ScanVerdict } from "./publish-leaks.ts";

/**
 * Decide whether `text` can be published.
 *
 * `known` is either the raw text of secrets/env.fish (parsed here) or explicit
 * entries — the wiring passes the `$NAME` values it expanded.
 * `leaks` is the injected scanner result; an error/timeout is a MATCH.
 */
export function scan(
  text: string,
  known: string | readonly KnownValue[],
  leaks: LeakScan,
): ScanVerdict | null {
  if (leaks.kind === "error") {
    return {
      label: `secret scanner unavailable (${leaks.detail})`,
      reason:
        `publish-guard: blocked — outgoing text could not be scanned (${leaks.detail}); ` +
        `publishing unscanned is not allowed. Fix the scanner, then retry.`,
      failClosed: true,
    };
  }

  const ruleId = leaks.ruleIds.find((r) => typeof r === "string" && r.length > 0);
  if (ruleId) {
    return { label: ruleId, reason: matchReason(ruleId) };
  }

  const values = typeof known === "string" ? parseSecretValues(known) : known;
  for (const entry of values) {
    const value = typeof entry?.value === "string" ? entry.value : "";
    if (value.length < MIN_VALUE_LEN || PLACEHOLDER.test(value)) continue;
    if (!text.includes(value)) continue;
    const name = String(entry.name ?? "").replace(/^\$+/, "");
    const label = name ? `value of $${name}` : "a known credential value";
    return { label, reason: matchReason(label) };
  }

  return null;
}

function matchReason(label: string): string {
  return `publish-guard: blocked — outgoing text matches ${label}. Remove it; do not repeat it.`;
}
