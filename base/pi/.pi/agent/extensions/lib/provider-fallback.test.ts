/**
 * Regression tests for the pure provider fallback in ./provider-fallback.ts.
 *
 * No pi runtime and no IO, so this runs standalone:
 *
 *   node --experimental-strip-types --test provider-fallback.test.ts
 *
 * It lives in lib/ (not the extensions root) because pi's extension discovery
 * loads every root-level *.ts.
 *
 * The fixture error text is the REAL one, measured from opencode-go while its
 * subscription was inactive — a shortened stand-in would not prove that the
 * match survives the surrounding JSON the provider wraps it in.
 */

import assert from "node:assert/strict";
import { test } from "node:test";
import {

  matchesProviderError,
  parseProviderFallbacks,
  planProviderHop,
  shouldReprobePrimary,
} from "./provider-fallback.ts";

const GO_403 =
  '403: {"type":"server_error","message":"Upstream request failed: An active OpenCode Go subscription is required to use Go models."}';

const MAP = parseProviderFallbacks({
  "opencode-go": { to: "opencode", match: ["active OpenCode Go subscription"] },
});

test("hops to the twin with the SAME model id when the error text matches", () => {
  const hop = planProviderHop({
    provider: "opencode-go",
    id: "glm-5.3",
    errorText: GO_403,
    map: MAP,
  });
  assert.deepEqual(hop, { to: "opencode", id: "glm-5.3" });
});

test("matching is case-insensitive and substring-based", () => {
  assert.deepEqual(
    planProviderHop({
      provider: "opencode-go",
      id: "glm-5.3",
      errorText: "…ACTIVE OPENCODE GO SUBSCRIPTION IS REQUIRED…",
      map: MAP,
    }),
    { to: "opencode", id: "glm-5.3" },
  );
});

// The mutant this kills: hopping on the provider alone (status/naive detection),
// which would move providers on a request bug or a permission error.
test("does NOT hop when the error text matches none of the patterns", () => {
  assert.equal(
    planProviderHop({
      provider: "opencode-go",
      id: "glm-5.3",
      errorText: "400: invalid request: unknown parameter 'temperature'",
      map: MAP,
    }),
    null,
  );
});

test("does NOT hop for a provider that has no entry", () => {
  assert.equal(
    planProviderHop({
      provider: "opencode",
      id: "glm-5.3",
      errorText: GO_403,
      map: MAP,
    }),
    null,
  );
});

// The mutant this kills: allowing a twin to hop (cascade) — with both providers
// down that is an endless switch loop instead of one failed turn.
test("does NOT hop when already on the target provider", () => {
  const selfMap = parseProviderFallbacks({
    "opencode-go": { to: "opencode-go", match: ["subscription"] },
  });
  assert.equal(
    planProviderHop({
      provider: "opencode-go",
      id: "glm-5.3",
      errorText: "…subscription…",
      map: selfMap,
    }),
    null,
  );
});

test("does NOT hop without an error text or a model id", () => {
  assert.equal(
    planProviderHop({ provider: "opencode-go", id: "glm-5.3", errorText: "", map: MAP }),
    null,
  );
  assert.equal(
    planProviderHop({ provider: "opencode-go", errorText: GO_403, map: MAP }),
    null,
  );
});

test("re-probe only when the twin came from the session, not from --model", () => {
  const twin = "opencode/glm-5.3";
  // Fresh session: no transcript, so nothing was restored — a --model twin stands.
  assert.equal(
    shouldReprobePrimary({ current: twin, lastModelChange: twin, messageCount: 0 }),
    false,
  );
  // Continued/resumed session whose recorded model IS the twin: a hop's leftover.
  assert.equal(
    shouldReprobePrimary({ current: twin, lastModelChange: twin, messageCount: 7 }),
    true,
  );
  // --model applied on top of a transcript that recorded something else: the flag won.
  assert.equal(
    shouldReprobePrimary({
      current: twin,
      lastModelChange: "opencode-go/glm-5.3",
      messageCount: 7,
    }),
    false,
  );
  // Defensive: no effective model at all.
  assert.equal(shouldReprobePrimary({ current: "", messageCount: 7 }), false);
});

test("parse keeps well-formed entries and drops malformed ones", () => {
  const parsed = parseProviderFallbacks({
    good: { to: "twin", match: ["boom"] },
    "no-to": { match: ["boom"] },
    "no-match": { to: "twin", match: [] },
    "blank-to": { to: "   ", match: ["boom"] },
    "bad-types": { to: "twin", match: [42, "", "  ", "real"] },
    "not-an-object": "twin",
    "an-array": [],
  });
  assert.deepEqual(Object.keys(parsed), ["good", "bad-types"]);
  assert.deepEqual(parsed["bad-types"].match, ["real"]);
});

test("parse returns {} for a missing or non-object block", () => {
  for (const raw of [undefined, null, "x", 7, [], {}]) {
    assert.deepEqual(parseProviderFallbacks(raw), {});
  }
});

// Patterns are SUBSTRINGS, never regexes: a repo named foo.nvim in a settings file
// must not widen the match because "." was read as a wildcard.
test("a literal dot in a pattern does not act as a wildcard", () => {
  assert.equal(matchesProviderError("aXb subscription", ["a.b subscription"]), false);
  assert.equal(matchesProviderError("a.b subscription", ["a.b subscription"]), true);
});

test("any one of several patterns is enough", () => {
  assert.equal(
    matchesProviderError(GO_403, ["never seen this", "active OpenCode Go subscription"]),
    true,
  );
});

// The guard that matters most in practice: the field is optional on the event.
test("does NOT hop when errorText is undefined", () => {
  assert.equal(
    planProviderHop({ provider: "opencode-go", id: "glm-5.3", errorText: undefined, map: MAP }),
    null,
  );
});

// Belt and braces for the parse: a map that did NOT come through
// parseProviderFallbacks must still not match everything via a blank pattern.
test("a blank pattern cannot match, even if it reaches the matcher", () => {
  assert.equal(
    planProviderHop({
      provider: "opencode-go",
      id: "glm-5.3",
      errorText: "400: unknown parameter 'temperature'",
      map: { "opencode-go": { to: "opencode", match: [""] } },
    }),
    null,
  );
});

test("an all-blank pattern list drops the entry, so nothing matches everything", () => {
  // '' is a substring of every string: a blank pattern left in the map would
  // make the provider hop on ANY error, which is the naive-detection mutant.
  assert.deepEqual(parseProviderFallbacks({ p: { to: "t", match: ["", "  "] } }), {});
});
