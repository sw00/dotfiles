/**
 * Pure core for the provider-level fallback in ./../model-switch.ts.
 *
 * pi-free and IO-free: planProviderHop() takes the current model, the failed
 * attempt's error text and the parsed config, so it runs standalone under
 * `node --experimental-strip-types --test` (see ./provider-fallback.test.ts).
 * The settings read and the pi wiring live in the top-level extension.
 *
 * WHY THIS EXISTS, next to `rateLimitFallbacks`:
 * that map is driven by `after_provider_response`, which pi emits only once a
 * response STREAMS. A provider that refuses before the stream — measured: a 403
 * from opencode-go while its subscription is inactive — never produces that
 * event, so the status allowlist in model-switch.ts cannot see it and a status-
 * keyed map entry would be a no-op. The only signal is the error TEXT, which
 * arrives per attempt on `turn_end`.
 *
 * The two mechanisms cover disjoint shapes:
 *   - `rateLimitFallbacks`      status-driven: 402/429/503/529, incl. errors
 *                               delivered mid-stream.
 *   - `providerFallbacks` (here) text-driven: a provider that is unavailable as
 *                               a whole (subscription lapsed, permission).
 *
 * Config, per provider, so future models need no new entries:
 *
 *   "providerFallbacks": {
 *     "opencode-go": { "to": "opencode", "match": ["active OpenCode Go subscription"] }
 *   }
 *
 * `match` entries are plain substrings, matched case-insensitively — NOT regexes:
 * they come from a settings file, and a stray `.` or `*` silently widening the
 * match is a failure this cannot report.
 */

/** One provider's fallback: where to go, and which errors mean "go". */
export interface ProviderFallback {
  to: string;
  match: string[];
}

export type ProviderFallbackMap = Record<string, ProviderFallback>;

/**
 * Tolerant parse of the `providerFallbacks` block. Anything malformed is
 * DROPPED rather than defaulted: a half-understood entry would hop on an error
 * nobody configured, and the failure mode of not hopping is merely the status
 * quo. Returns {} for a missing/!object block.
 */
export function parseProviderFallbacks(raw: unknown): ProviderFallbackMap {
  const out: ProviderFallbackMap = {};
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out;
  for (const [provider, value] of Object.entries(raw as Record<string, unknown>)) {
    if (!provider) continue;
    if (!value || typeof value !== "object" || Array.isArray(value)) continue;
    const v = value as Record<string, unknown>;
    const to = typeof v.to === "string" ? v.to.trim() : "";
    if (!to) continue;
    const rawMatch = Array.isArray(v.match) ? v.match : [];
    const match = rawMatch
      .filter((m): m is string => typeof m === "string")
      .map((m) => m.trim())
      .filter((m) => m.length > 0);
    if (match.length === 0) continue; // no text to match → never fires
    out[provider] = { to, match };
  }
  return out;
}

/** Does `errorText` carry one of this fallback's configured substrings? */
export function matchesProviderError(errorText: string, patterns: string[]): boolean {
  const hay = errorText.toLowerCase();
  // A blank pattern is a substring of ANY string, so it would hop on every error.
  // parseProviderFallbacks already drops those; this is the second lock on the same
  // door, because a map handed straight to planProviderHop need not have gone
  // through it (the unit test calls it that way on purpose).
  return patterns.some((p) => p.length > 0 && hay.includes(p.toLowerCase()));
}

/**
 * Decide whether this failed attempt should move the session to another
 * provider, and to which model. Returns null for every "do nothing" outcome:
 *
 *  - the provider has no entry (the common case);
 *  - the error text matches none of its patterns — the whole point of matching
 *    text: a request bug or a permission error must not silently move providers;
 *  - the model is ALREADY on the target provider: no cascade, and no hop loop
 *    when both providers are down;
 *  - no model id to carry over (a provider-wide entry still needs an id).
 *
 * Resolution to a physical model stays in the caller: the registry is pi state.
 */
/**
 * Should a session that STARTED on a fallback twin be moved back to its primary?
 *
 * This is the recovery half of the provider fallback, and it needs a provenance
 * signal, because the twin's model can come from two very different places:
 *
 *  - the SESSION's own transcript (pi appends a `model_change` to the session, and
 *    a continued or resumed session — `-c`, `--resume`, pwt's re-run
 *    `--session-id` — restores from it). That is a hop's leftover: re-testing the
 *    primary here is how a lapsed subscription comes back by itself.
 *  - THIS invocation (an explicit `--model <twin>`), which is the user's own
 *    choice and must win.
 *
 * pi reports both as `session_start` with reason "startup" (measured: pwt's
 * re-run `--session-id` is NOT "resume"), and its `model_select` "restore" source
 * is declared but never emitted — so the branch is what tells them apart:
 * `--model` is applied ON TOP of the transcript, so a last `model_change` that
 * disagrees with the effective model means the flag won; a branch with no message
 * entries has nothing that could have been restored.
 */
export function shouldReprobePrimary(o: {
  /** effective model, "provider/id" */
  current: string;
  /** last `model_change` in the session branch, if any */
  lastModelChange?: string;
  /** message entries in the branch — 0 means a fresh session */
  messageCount: number;
}): boolean {
  if (!o.current) return false;
  if (o.messageCount === 0) return false; // fresh session: nothing was restored
  // The CLI overrode the transcript's model, so this is a deliberate choice.
  if (o.lastModelChange && o.lastModelChange !== o.current) return false;
  return true;
}

export function planProviderHop(opts: {
  provider?: string;
  id?: string;
  errorText?: string;
  map: ProviderFallbackMap;
}): { to: string; id: string } | null {
  const { provider, id, errorText, map } = opts;
  if (!provider || !id) return null;
  if (!errorText) return null;
  const entry = map[provider];
  if (!entry) return null;
  if (entry.to === provider) return null; // self-hop would loop
  if (!matchesProviderError(errorText, entry.match)) return null;
  return { to: entry.to, id };
}
