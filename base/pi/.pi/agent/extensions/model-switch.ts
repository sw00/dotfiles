/**
 * model-switch — Graceful model switching & auto-fallback.
 *
 * Two DECOUPLED sets (config-driven, nothing hardcoded):
 *
 *   1. CYCLE SET = `enabledModels` in settings.json (the curated Ctrl+P list).
 *      Used by /cycle, /use, /models. OpenRouter mirrors
 *      must NOT appear here — they are fallback-only.
 *
 *   2. FALLBACK MAP = `rateLimitFallbacks` in settings.json: a map of
 *      "provider/id" (primary) -> "provider/id" (OpenRouter twin). Consulted
 *      ONLY on HTTP 429/529. If the key is absent/empty (e.g. an attended
 *      profile), auto-fallback does NOTHING — the user handles rate limits
 *      manually. An unattended deployment populates this map so it stays
 *      alive on a metered OpenRouter twin when its subscription provider
 *      rate-limits. This map is per-profile config, owned by each host's
 *      settings.json — never hardcoded here.
 *
 * STICKY, CORRECTED 2026-10-22: pi.setModel() from an extension does NOT persist
 * to settings — `agent-session.js` writes defaultModel only for
 * `options.persist`, which the extension-facing wrapper does not pass. It DOES
 * append a `model_change` to the session, and a continued or resumed session
 * restores from that, so a hop can outlive the process it happened in. Both
 * recovery paths below therefore matter: session_start re-probes the primary for
 * BOTH maps (rate-limit twins and provider-fallback twins, each with its own
 * provenance check) and a 2xx can switch back mid-session for a rate-limit twin.
 *
 *   3. PROVIDER FALLBACK = `providerFallbacks` in settings.json: a per-provider
 *      map for failures that arrive WITHOUT a streamed response, where
 *      `after_provider_response` never fires (measured: a 403 from opencode-go
 *      while its subscription is inactive). Detected on the error TEXT at
 *      `turn_end`, switched immediately so pi's own retry finishes the same turn
 *      on the twin, plus one forced continuation at `agent_before_settle` for
 *      the shapes pi calls non-retryable. Pure logic in
 *      ./lib/provider-fallback.ts.
 *
 * Manual (TUI):
 *   /use <query>     — switch to a model by fuzzy id match (any authed model)
 *   /models          — show active model, the cycle set, and the fallback map
 *   /cycle           — cycle to the next model in the cycle set
 *
 * NOTE: this extension is host-agnostic and has NO knowledge of any specific
 * bridge or appliance. ctx.ui.notify renders in the tmux TUI footer and may
 * not be surfaced on non-TUI frontends; if silent model changes are a concern
 * on a given deployment, surface them from that deployment's own extension.
 */
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

import {
  parseProviderFallbacks,
  planProviderHop,
  shouldReprobePrimary,
} from "./lib/provider-fallback.ts";
import type { ProviderFallbackMap } from "./lib/provider-fallback.ts";

type MiniModel = { provider: string; id: string };

// ── Settings / enabledModels ────────────────────────────────────────────────

function settingsPaths(cwd: string): string[] {
  // Global first, then project override (project entries appended after).
  return [
    join(homedir(), ".pi", "agent", "settings.json"),
    join(cwd, ".pi", "settings.json"),
  ];
}

function readEnabledModels(cwd: string): string[] {
  const merged: string[] = [];
  for (const p of settingsPaths(cwd)) {
    try {
      const json = JSON.parse(readFileSync(p, "utf8"));
      if (Array.isArray(json.enabledModels)) merged.push(...json.enabledModels);
    } catch {
      /* missing / unreadable — ignore */
    }
  }
  return merged;
}

/**
 * Read the `rateLimitFallbacks` map (primary "provider/id" -> OR twin
 * "provider/id"). Shallow-merge global then project, project wins per key
 * (mirrors pi's settings merge). Missing/unparseable file -> {} (no fallback).
 */
function readFallbackMap(cwd: string): Record<string, string> {
  const merged: Record<string, string> = {};
  for (const p of settingsPaths(cwd)) {
    try {
      const json = JSON.parse(readFileSync(p, "utf8"));
      const m = json.rateLimitFallbacks;
      if (m && typeof m === "object" && !Array.isArray(m)) {
        for (const [k, v] of Object.entries(m)) {
          if (typeof v === "string") merged[k.toLowerCase()] = v.toLowerCase();
        }
      }
    } catch {
      /* missing / unreadable — ignore */
    }
  }
  return merged;
}

/**
 * Read the `providerFallbacks` block (see ./lib/provider-fallback.ts for the
 * shape and why it exists next to `rateLimitFallbacks`). Same merge rule as the
 * other readers: global then project, and a malformed entry is DROPPED. An
 * absent block yields {} — no provider fallback, i.e. the previous behaviour.
 */
function branchModelFacts(ctx: {
  sessionManager?: { getBranch?: () => unknown[] };
}): { lastModelChange?: string; messageCount: number } {
  const branch = ctx.sessionManager?.getBranch?.() ?? [];
  let lastModelChange: string | undefined;
  let messageCount = 0;
  for (const raw of branch) {
    const e = raw as { type?: string; provider?: string; modelId?: string };
    if (e?.type === "model_change" && e.provider && e.modelId)
      lastModelChange = `${e.provider}/${e.modelId}`.toLowerCase();
    else if (e?.type === "message") messageCount++;
  }
  return { lastModelChange, messageCount };
}
function readProviderFallbacks(cwd: string): ProviderFallbackMap {
  const merged: ProviderFallbackMap = {};
  for (const p of settingsPaths(cwd)) {
    try {
      const json = JSON.parse(readFileSync(p, "utf8"));
      Object.assign(merged, parseProviderFallbacks(json.providerFallbacks));
    } catch {
      /* missing / unreadable — ignore */
    }
  }
  return merged;
}

// ── Fallback behaviour defaults / config readers ─────────────────────────────

const DEFAULT_FALLBACK_STATUSES = [429, 529, 503, 402];
const DEFAULT_RECOVERY_COOLDOWN_SEC = 120;

/**
 * Status codes that trigger the fallback hop; configurable per-profile via
 * `rateLimitFallbackStatuses` in settings.json (project overrides global).
 * Allowlist is deliberate:
 *   429 — rate limit (OpenAI/DeepSeek/OpenRouter; incl. quota-exceeded-as-429)
 *   529 — Anthropic overloaded
 *   503 — capacity: DeepSeek "server overloaded", OpenAI "engine overloaded",
 *         OpenRouter "no available provider"
 *   402 — OpenAI insufficient quota (standalone account-limit form)
 * NOT included: 400 (real request bug — falling back masks it and burns
 * metered spend), 401 (broken auth — a same-gateway twin cannot fix it),
 * 403 (opt-in only — some are permission/region issues a same-gateway twin
 * cannot fix). The after_provider_response hook exposes status + headers only
 * (no body), so error-type-based detection (e.g. 400 + rate_limit_exceeded)
 * is impossible here.
 */
function readFallbackStatuses(cwd: string): number[] {
  let out: number[] = [...DEFAULT_FALLBACK_STATUSES];
  const allowed = new Set([402, 403, 429, 503, 529]);
  for (const p of settingsPaths(cwd)) {
    try {
      const json = JSON.parse(readFileSync(p, "utf8"));
      const arr = json.rateLimitFallbackStatuses;
      if (Array.isArray(arr)) {
        const ok = arr.filter(
          (n: unknown) =>
            typeof n === "number" && Number.isInteger(n) && allowed.has(n),
        );
        if (ok.length > 0) out = ok;
      }
    } catch {
      /* missing / unreadable — ignore */
    }
  }
  return out;
}

/** Dwell time (seconds) before 2xx recovery may switch back off the twin. */
function readRecoveryCooldownSec(cwd: string): number {
  let out = DEFAULT_RECOVERY_COOLDOWN_SEC;
  for (const p of settingsPaths(cwd)) {
    try {
      const json = JSON.parse(readFileSync(p, "utf8"));
      const n = json.rateLimitFallbackRecoveryCooldownSec;
      if (typeof n === "number" && n > 0) out = n;
    } catch {
      /* missing / unreadable — ignore */
    }
  }
  return out;
}

/** Lowercased "provider/id" — map keys/values are normalized at read time. */
function normId(m?: { provider?: string; id?: string } | null): string {
  return m && m.provider && m.id
    ? `${m.provider}/${m.id}`.toLowerCase()
    : "";
}

function parseId(s: string): MiniModel | undefined {
  const slash = s.indexOf("/");
  if (slash < 0) return undefined;
  return { provider: s.slice(0, slash), id: s.slice(slash + 1) };
}

function globToRe(glob: string): RegExp {
  const esc = glob.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
  return new RegExp(`^${esc}$`, "i");
}

/**
 * Resolve `enabledModels` patterns (e.g. "claude-bridge/*", "opencode-go/glm-*",
 * "gpt-5.6-luna") against the set of currently-authed models, preserving order
 * and de-duplicating. Falls back to all available models if the list is empty.
 */
function resolveFallbackSet(entries: string[], available: MiniModel[]): MiniModel[] {
  if (entries.length === 0) return available;
  const out: MiniModel[] = [];
  const seen = new Set<string>();
  for (const entry of entries) {
    const slash = entry.indexOf("/");
    const provPat = slash >= 0 ? entry.slice(0, slash) : "*";
    const idPat = slash >= 0 ? entry.slice(slash + 1) : entry;
    const pRe = globToRe(provPat);
    const iRe = globToRe(idPat);
    for (const m of available) {
      if (pRe.test(m.provider) && iRe.test(m.id)) {
        const key = `${m.provider}/${m.id}`;
        if (!seen.has(key)) {
          seen.add(key);
          out.push({ provider: m.provider, id: m.id });
        }
      }
    }
  }
  return out;
}

// ── Extension ───────────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  function available(ctx: { modelRegistry: any }): MiniModel[] {
    return (ctx.modelRegistry.getAvailable() as MiniModel[]).map((m) => ({
      provider: m.provider,
      id: m.id,
    }));
  }

  // The CYCLE SET (from enabledModels) — used by /cycle, /use, /models.
  function cycleSet(ctx: { modelRegistry: any; cwd: string }): MiniModel[] {
    return resolveFallbackSet(readEnabledModels(ctx.cwd), available(ctx));
  }

  // Registry membership only — NOT credential validity. The real auth gate is
  // pi.setModel() (the session runtime checks hasConfiguredAuth and returns
  // false). This check just avoids hopping to an id the registry doesn't know.
  function isAuthed(m: MiniModel, ctx: { modelRegistry: any }): boolean {
    return available(ctx).some((a) => a.provider === m.provider && a.id === m.id);
  }

  async function switchTo(m: MiniModel, ctx: { modelRegistry: any; ui: any }, reason = ""): Promise<boolean> {
    const model = ctx.modelRegistry.find(m.provider, m.id);
    if (!model) {
      ctx.ui.notify(`${m.provider}/${m.id} not found in registry`, "error");
      return false;
    }
    const ok = await pi.setModel(model);
    ctx.ui.notify(
      ok
        ? `${reason}Model → ${m.provider}/${m.id}`
        : `No usable auth for ${m.provider} — leaving model unchanged`,
      ok ? "info" : "error",
    );
    return ok;
  }

  // Fuzzy resolve a user query ("sonnet", "opus", "openrouter/...") to a model.
  // Prefer the curated fallback set (ordered), then fall back to any authed model.
  function resolveQuery(query: string, ctx: { modelRegistry: any; cwd: string }): MiniModel | undefined {
    const q = query.trim().toLowerCase();
    if (!q) return undefined;
    const match = (list: MiniModel[]) =>
      list.find((m) => `${m.provider}/${m.id}`.toLowerCase() === q) ??
      list.find((m) => m.id.toLowerCase() === q) ??
      list.find((m) => `${m.provider}/${m.id}`.toLowerCase().includes(q)) ??
      list.find((m) => m.id.toLowerCase().includes(q));
    return match(cycleSet(ctx)) ?? match(available(ctx));
  }

  // ── /use <query> ──────────────────────────────────────────────────────────
  pi.registerCommand("use", {
    description: "Switch model by name, e.g. /use sonnet | /use openrouter/anthropic/claude",
    handler: async (args, ctx) => {
      const q = args.trim();
      if (!q) {
        ctx.ui.notify("Usage: /use <model>. Run /models to see the set.", "info");
        return;
      }
      const m = resolveQuery(q, ctx);
      if (!m) {
        ctx.ui.notify(`No authed model matches '${q}'. Run /models.`, "error");
        return;
      }
      await switchTo(m, ctx);
    },
  });

  // ── /models ─────────────────────────────────────────────────────────────
  pi.registerCommand("models", {
    description: "Show active model, the cycle set (enabledModels), and the fallback map",
    handler: async (_args, ctx) => {
      const map = readFallbackMap(ctx.cwd);
      const curId = ctx.model ? normId(ctx.model) : "none";
      const isTwin = curId !== "none" && Object.values(map).includes(curId);
      const cur = `${curId}${isTwin ? "  (⚠ rate-limit fallback — metered)" : ""}`;

      const set = cycleSet(ctx);
      const list = set.length
        ? set.map((m, i) => `${i + 1}. ${m.provider}/${m.id}`).join("\n")
        : "(none — enabledModels empty or unauthed)";

      const mapKeys = Object.keys(map);
      const mapStr = mapKeys.length
        ? mapKeys.map((k) => `  ${k} → ${map[k]}`).join("\n")
        : "  (none — no auto-fallback; attended profile)";

      const statuses = readFallbackStatuses(ctx.cwd);
      const cdSec = readRecoveryCooldownSec(ctx.cwd);

      ctx.ui.notify(
        `Active: ${cur}\n\nCycle set (enabledModels):\n${list}\n\nFallback map (rateLimitFallbacks):\n${mapStr}\n\nFallback trigger statuses: ${statuses.join(", ")}\nRecovery cooldown: ${cdSec}s (floored by retry-after)`,
        "info",
      );
    },
  });

  // ── /cycle ────────────────────────────────────────────────────────────────
  pi.registerCommand("cycle", {
    description: "Cycle to the next model in the cycle set (enabledModels)",
    handler: async (_args, ctx) => {
      const set = cycleSet(ctx);
      if (set.length === 0) {
        ctx.ui.notify("Cycle set is empty — check enabledModels.", "error");
        return;
      }
      const cur = ctx.model;
      const idx = cur ? set.findIndex((m) => m.provider === cur.provider && m.id === cur.id) : -1;
      const next = set[(idx + 1) % set.length];
      await switchTo(next, ctx, "Cycled — ");
    },
  });

  // ── User-chosen twin tracking ───────────────────────────────────────────────
  // If the user explicitly picks a fallback twin (via /use or Ctrl+P), mark it
  // so neither 2xx recovery nor session_start yanks them back. The declared
  // "restore" source is never emitted in 1.3.0, and an automatic hop arrives as
  // "set" — which is why automatic hops set pendingHopTwinId to suppress it.
  pi.on("model_select", (event, ctx) => {
    const pickedId = normId(event.model);
    if (pendingHopTwinId) {
      if (pickedId === pendingHopTwinId) return; // our own hop — ignore
      pendingHopTwinId = null; // a different selection supersedes the pending hop
    }
    const map = readFallbackMap(ctx.cwd);
    // A deliberate /use or Ctrl+P onto a provider-fallback twin counts too: the
    // recovery handler below must not drag the user back off a model they chose.
    const pf = readProviderFallbacks(ctx.cwd);
    const isTwin =
      Object.values(map).includes(pickedId) ||
      Object.values(pf).some((entry) => pickedId.startsWith(`${entry.to}/`));
    userPickedTwin = isTwin && (event.source === "set" || event.source === "cycle");
  });


  // ── Auto-fallback on rate limit / overload (MAP-DRIVEN) ────────────────────
  // Fires ONLY when `rateLimitFallbacks` maps the current model to an authed
  // OpenRouter twin. If the map is absent/empty (attended profile) this is a
  // no-op, and the user handles rate limits manually via /use or Ctrl+P.
  // Guards:
  //  - inProgress: reentrancy — never run two switches in parallel.
  //  - lastFallbackAt / lastRecoveryAt: INDEPENDENT 2s throttles per direction.
  //    A recovery must never arm a throttle that suppresses the next fallback
  //    (a 429 right after a switch-back is exactly when you need the hop).
  //  - hopCooldownUntil: dwell window set at hop time (floored by retry-after);
  //    2xx recovery is ignored until it elapses — no mid-turn yank back to a
  //    still-rate-limited primary.
  //  - userPickedTwin: true when the user /use'd or /cycle'd onto a fallback
  //    twin — never "recover" away from a deliberate choice.
  //  - pendingHopTwinId: suppresses our own pi.setModel model_select event so
  //    an automatic hop is not misclassified as a user pick.
  let inProgress = false;
  let lastFallbackAt = 0;
  let lastRecoveryAt = 0;
  let hopCooldownUntil = 0;
  let userPickedTwin = false;
  let pendingHopTwinId: string | null = null;

  pi.on("after_provider_response", async (event, ctx) => {
    if (inProgress) return;
    const now = Date.now();

    const cur = ctx.model;
    if (!cur) return;
    const curId = normId(cur);
    const map = readFallbackMap(ctx.cwd);

    // T3 (gated): switch BACK to the primary on a 2xx — but only after an
    // in-process hop and once the dwell cooldown has elapsed, and never when
    // the user deliberately chose the twin. Without the guards, the first 2xx
    // mid-turn would yank the session back to a primary still inside its rate
    // window (thrash), and a stream error delivered as a committed 200
    // (OpenRouter overload-after-stream-start) would be misread as recovered.
    if (event.status >= 200 && event.status < 300) {
      if (userPickedTwin) return; // deliberate /use or Ctrl+P — leave it
      if (hopCooldownUntil === 0) return; // no in-process hop — session_start owns recovery
      if (now < hopCooldownUntil) return; // dwell window not elapsed
      if (now - lastRecoveryAt < 2000) return; // recovery throttle (own clock)

      const primaryId = Object.keys(map).find((k) => map[k] === curId);
      if (!primaryId) return; // not on a fallback twin
      const primary = parseId(primaryId);
      if (!primary || !isAuthed(primary, ctx)) return; // primary still unavailable
      if (downProviders.has(primary.provider)) return; // a provider that failed whole

      inProgress = true;
      lastRecoveryAt = now;
      try {
        await switchTo(primary, ctx, "Primary recovered — ");
      } finally {
        inProgress = false;
      }
      return;
    }

    // Fallback direction — throttled by ITS OWN clock, so a recent recovery
    // can never suppress the next fallback.
    if (now - lastFallbackAt < 2000) return; // fallback throttle (own clock)
    const statuses = readFallbackStatuses(ctx.cwd);
    if (!statuses.includes(event.status)) return; // not a limit/overload status

    // T1: a fallback twin must not itself be a map key — no cascades.
    const twinId = map[curId];
    if (!twinId) return; // no mapping for the current model — do nothing
    if (map[twinId]) return; // twin-of-twin guard

    const twin = parseId(twinId);
    if (!twin) return;

    inProgress = true;
    lastFallbackAt = now;
    try {
      if (isAuthed(twin, ctx)) {
        // Honor retry-after as the recovery cooldown floor (numeric seconds
        // only; HTTP-date values are ignored and fall back to the config).
        const ra = Object.entries(event.headers ?? {}).find(
          ([h]) => h.toLowerCase() === "retry-after",
        )?.[1];
        const raSec = ra && /^\d+$/.test(ra) ? parseInt(ra, 10) : 0;
        const cdSec = Math.max(readRecoveryCooldownSec(ctx.cwd), raSec);
        hopCooldownUntil = now + cdSec * 1000;
        userPickedTwin = false; // automatic hop — not a user pick
        pendingHopTwinId = twinId; // suppress our own model_select event
        try {
          await switchTo(twin, ctx, `Rate-limited (${event.status}) — `);
        } finally {
          pendingHopTwinId = null;
        }
      } else {
        // isAuthed is registry membership; the real gate — pi.setModel returning
        // false inside switchTo — surfaces via its "No usable auth" notify.
        ctx.ui.notify(
          `Rate-limited (${event.status}) but fallback ${twinId} has no usable auth — leaving model unchanged.`,
          "error",
        );
      }
    } finally {
      inProgress = false; // never wedge the guard, even if switchTo throws
    }
  });

  // ── Provider fallback: failures that never stream ──────────────────────────
  // A provider that refuses BEFORE a response streams produces no
  // after_provider_response event at all, so the status-driven machinery above
  // cannot see it (measured: opencode-go's subscription 403). The error text on
  // `turn_end` is the only signal, and acting there is enough — pi re-issues the
  // request after a model change, so its retry lands on the twin.
  //   `hopArmed` covers the OTHER shape: pi classifies some of these errors as
  // non-retryable (its own list names OpenCode Go's usage-limit errors), and then
  // no retry follows and the turn would die with the hop already made. It also
  // survives a turn in which the TWIN fails with an unrelated error, forcing one
  // request on the twin anyway — bounded, because the twin has no entry and so
  // nothing can re-arm.
  // `agent_before_settle` is the documented boundary for asking for exactly one
  // more model request, and it fires once per run — after the retries have run
  // out. A successful turn clears the flag, so a turn that recovered through
  // pi's retry does not also get a spurious extra request.
  let hopArmed = false;
  // Providers this process has seen fail as a whole. The rate-limit 2xx recovery
  // below must not switch back into one of these: with both maps populated it would
  // flip to the dead primary on the next success and bounce straight back (one 403
  // per step). Cleared with the process, which is also when the re-probe runs.
  const downProviders = new Set<string>();

  pi.on("turn_end", async (event, ctx) => {
    const msg = event.message as { stopReason?: string; errorMessage?: string } | undefined;
    if (msg?.stopReason !== "error") {
      hopArmed = false; // this turn is answering — nothing left to rescue
      return;
    }
    const cur = ctx.model;
    if (!cur || inProgress) return;
    const hop = planProviderHop({
      provider: cur.provider,
      id: cur.id,
      errorText: msg.errorMessage,
      map: readProviderFallbacks(ctx.cwd),
    });
    if (!hop) return;
    const twin = ctx.modelRegistry.find(hop.to, hop.id);
    if (!twin) {
      // Fail soft: 13 of Go's 32 ids have no Zen twin (its contributor/preview
      // models, plus mimo-*/qwen3.7-plus/hy*/longcat-2.0), and those must leave
      // the session where it is rather than throw.
      ctx.ui.notify(
        `Provider ${cur.provider} failed but ${hop.to}/${hop.id} is not in the registry — leaving model unchanged.`,
        "error",
      );
      return;
    }
    inProgress = true;
    pendingHopTwinId = `${hop.to}/${hop.id}`.toLowerCase(); // our own hop, not a user pick
    downProviders.add(cur.provider);
    try {
      const ok = await pi.setModel(twin);
      if (!ok) {
        ctx.ui.notify(`No usable auth for ${hop.to} — leaving model unchanged`, "error");
        return;
      }
      hopArmed = true; // one forced continuation, for the non-retryable shapes
      ctx.ui.notify(
        `Provider ${cur.provider} unavailable — model → ${hop.to}/${hop.id} (metered twin)`,
        "info",
      );
    } finally {
      pendingHopTwinId = null;
      inProgress = false;
    }
  });

  // ONE more model request when a hop could not be rescued by pi's own retry.
  // `continue: true` ALONE IS NOT ENOUGH and is rejected at runtime — measured:
  // "agent_before_settle requested continuation without runnable model context".
  // A continuation is valid only when the projection does not END on an assistant
  // message (`contextCanContinue = hasNonSystemContext && finalRole !== "assistant"`,
  // agent-session.js:_buildBoundaryContext), and a failed attempt is exactly an
  // assistant message with an error and no content. So the handler chains a
  // custom_message entry, which both satisfies the contract and tells the model why
  // its previous answer is missing. Guarded by a flag a successful turn clears, so
  // this can never loop.
  pi.on("agent_before_settle", async () => {
    if (!hopArmed) return;
    hopArmed = false;
    return {
      entries: [
        {
          type: "custom_message" as const,
          customType: "provider-fallback",
          content:
            "An earlier attempt in this conversation failed because its provider was unavailable, and was retried on an alternate provider.",
          display: false, // context for the retry, not a user-facing message
        },
      ],
      continue: true,
    };
  });

  // ── Switch-back: recover from a deliberate /use onto a rate-limit twin ────
  // Corrected 2026-10-22: an automatic hop does NOT persist (extension-facing
  // pi.setModel passes no `persist`), so this is not about hops at all — it is
  // about a twin PERSISTED by a deliberate /use or Ctrl+P. Fires only when the
  // active model is a VALUE of `rateLimitFallbacks`; the provider fallback below
  // keeps its own map and is deliberately absent here.
  // Provider fallback: a hop does not persist in SETTINGS, but pi.setModel()
  // appends a `model_change` to the SESSION, and a resumed session (`pi -c`,
  // `--resume`, or pwt's re-run `--session-id`) restores from it. Without this a
  // session that once hopped would stay on the metered twin forever, and a lapsed
  // subscription that comes back would never be picked up again. The cost while it
  // is still lapsed is one failed attempt on the next turn — the hop immediately
  // returns to the twin, and for the non-retryable shapes the continuation above
  // rescues that turn.
  //   Provenance decides, via ./lib/provider-fallback.ts:shouldReprobePrimary —
  // the twin must have come from the SESSION (a hop's leftover), not from an
  // explicit `--model` on this invocation, which is the user's own choice. Gating
  // on the start REASON cannot do this: pwt re-runs `pi --session-id <sid>` for
  // every workstream window and pi reports that as "startup", not "resume".
  // `reload` is skipped outright — the extension is re-imported with its guards
  // reset, so acting there would silently undo a deliberate `/use`.
  pi.on("session_start", async (event, ctx) => {
    if (event.reason === "reload") return;
    if (inProgress || userPickedTwin) return;
    const cur = ctx.model;
    if (!cur) return;
    const rateMap = readFallbackMap(ctx.cwd);
    if (Object.values(rateMap).includes(normId(cur))) return; // handler below owns it
    const pf = readProviderFallbacks(ctx.cwd);
    const primaryProvider = Object.keys(pf).find((k) => pf[k].to === cur.provider);
    if (!primaryProvider) return; // not on a provider-fallback twin
    const primary = ctx.modelRegistry.find(primaryProvider, cur.id);
    if (!primary) return; // this id has no counterpart on the primary provider
    if (!shouldReprobePrimary({ current: normId(cur), ...branchModelFacts(ctx) })) return;
    inProgress = true;
    try {
      const ok = await pi.setModel(primary);
      if (ok)
        ctx.ui.notify(
          `Provider fallback: re-trying ${primaryProvider}/${cur.id} (was on ${cur.provider})`,
          "info",
        );
      else
        ctx.ui.notify(
          `No usable auth for ${primaryProvider} — staying on ${cur.provider}`,
          "error",
        );
    } finally {
      inProgress = false;
    }
  });

  pi.on("session_start", async (event, ctx) => {
    if (event.reason === "reload") return; // guards reset on reload — see the handler above
    if (inProgress) return;
    if (userPickedTwin) return; // user asked for this twin — don't override
    if (Date.now() - lastRecoveryAt < 2000) return; // dedupe a same-tick 2xx recovery

    const cur = ctx.model;
    if (!cur) return;
    const curId = normId(cur);
    const map = readFallbackMap(ctx.cwd);

    // Find the primary whose twin is the current model.
    const primaryId = Object.keys(map).find((k) => map[k] === curId);
    if (!primaryId) return; // not on a fallback twin — nothing to do

    const primary = parseId(primaryId);
    if (!primary || !isAuthed(primary, ctx)) return; // primary still unavailable

    inProgress = true;
    lastRecoveryAt = Date.now();
    try {
      await switchTo(primary, ctx, "Recovered from fallback — ");
    } finally {
      inProgress = false;
    }
  });
}
