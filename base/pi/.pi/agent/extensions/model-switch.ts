/**
 * model-switch — Graceful model switching & auto-fallback.
 *
 * Two DECOUPLED sets (config-driven, nothing hardcoded):
 *
 *   1. CYCLE SET = `enabledModels` in settings.json (the curated Ctrl+P list).
 *      Used by /cycle, /use, /models, plain-text switching. OpenRouter mirrors
 *      must NOT appear here — they are fallback-only.
 *
 *   2. FALLBACK MAP = `rateLimitFallbacks` in settings.json: a map of
 *      "provider/id" (primary) -> "provider/id" (OpenRouter twin). Consulted
 *      ONLY on HTTP 429/529. If the key is absent/empty (e.g. the laptop
 *      profile), auto-fallback does NOTHING — an attended user handles rate
 *      limits manually. The agentbox profile populates this map so the
 *      unattended Telegram bridge stays alive on a metered OpenRouter twin.
 *
 * STICKY caveat: pi.setModel() persists defaultModel to settings.json, so a
 * fallback survives turns/sessions/restarts. To avoid getting stuck on the
 * metered twin, we switch BACK to the primary on session_start whenever the
 * current model is a fallback twin and its primary's provider is authed again.
 *
 * Manual (Telegram or TUI):
 *   /use <query>     — switch to a model by fuzzy id match (any authed model)
 *   /models          — show active model, the cycle set, and the fallback map
 *   /cycle           — cycle to the next model in the cycle set
 *   plain text:      "use <query>" or "switch to <query>"
 *
 * NOTE (S7): ctx.ui.notify renders in the tmux TUI footer; it may NOT be
 * mirrored to the Telegram chat by pi-telegram. If a silent metered switch is a
 * concern, surface it as an assistant message instead. Left as notify for now.
 */
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

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
          if (typeof v === "string") merged[k] = v;
        }
      }
    } catch {
      /* missing / unreadable — ignore */
    }
  }
  return merged;
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
 * Resolve `enabledModels` patterns (e.g. "anthropic/claude-*", "openrouter/*",
 * "kimi-k3") against the set of currently-authed models, preserving order and
 * de-duplicating. Falls back to all available models if the list is empty.
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
      const curId = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : "none";
      const map = readFallbackMap(ctx.cwd);
      const isTwin = Object.values(map).includes(curId);
      const cur = `${curId}${isTwin ? "  (⚠ rate-limit fallback — metered)" : ""}`;

      const set = cycleSet(ctx);
      const list = set.length
        ? set.map((m, i) => `${i + 1}. ${m.provider}/${m.id}`).join("\n")
        : "(none — enabledModels empty or unauthed)";

      const mapKeys = Object.keys(map);
      const mapStr = mapKeys.length
        ? mapKeys.map((k) => `  ${k} → ${map[k]}`).join("\n")
        : "  (none — no auto-fallback; attended profile)";

      ctx.ui.notify(
        `Active: ${cur}\n\nCycle set (enabledModels):\n${list}\n\nFallback map (rateLimitFallbacks):\n${mapStr}`,
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

  // ── plain-text switching (robust over the Telegram [telegram] prefix) ──────
  pi.on("input", async (event, ctx) => {
    const m = event.text.trim().match(/(?:^|\s)(?:switch\s+to\s+|(?:\/)?use\s+)([a-zA-Z0-9._/-]+)\b/i);
    if (!m) return;
    const model = resolveQuery(m[1], ctx);
    if (!model) return; // not a known model — let it pass through to the LLM
    await switchTo(model, ctx);
    return { action: "handled" };
  });

  // ── Auto-fallback on rate limit / overload (MAP-DRIVEN) ────────────────────
  // Fires ONLY when `rateLimitFallbacks` maps the current model to an authed
  // OpenRouter twin. If the map is absent/empty (laptop) this is a no-op, and
  // the user handles rate limits manually via /use or Ctrl+P. Once on a twin
  // (openrouter/...), that id is not a map key, so repeated 429s during pi's
  // retry backoff are self-limiting no-ops — no cascade.
  let inProgress = false;
  let lastAt = 0;

  pi.on("after_provider_response", async (event, ctx) => {
    if (event.status !== 429 && event.status !== 529) return;
    if (inProgress) return;
    const now = Date.now();
    if (now - lastAt < 2000) return; // throttle: max 1 fallback / 2s

    const cur = ctx.model;
    if (!cur) return;

    const map = readFallbackMap(ctx.cwd);
    const twinId = map[`${cur.provider}/${cur.id}`];
    if (!twinId) return; // no mapping for the current model — do nothing

    const twin = parseId(twinId);
    if (!twin) return;

    inProgress = true;
    lastAt = now;
    try {
      if (isAuthed(twin, ctx)) {
        await switchTo(twin, ctx, `Rate-limited (${event.status}) — `);
      } else {
        ctx.ui.notify(
          `Rate-limited (${event.status}) but fallback ${twinId} has no usable auth — leaving model unchanged.`,
          "error",
        );
      }
    } finally {
      inProgress = false; // never wedge the guard, even if switchTo throws
    }
  });

  // ── Switch-back: recover from a sticky fallback on session start ───────────
  // pi.setModel() persists defaultModel, so a prior fallback survives restarts.
  // If the active model is a fallback TWIN and its PRIMARY is authed again,
  // switch back so the box returns to its subscription default (e.g. kimi-k3).
  pi.on("session_start", async (_event, ctx) => {
    if (inProgress) return;
    const cur = ctx.model;
    if (!cur) return;
    const curId = `${cur.provider}/${cur.id}`;
    const map = readFallbackMap(ctx.cwd);

    // Find the primary whose twin is the current model.
    const primaryId = Object.keys(map).find((k) => map[k] === curId);
    if (!primaryId) return; // not on a fallback twin — nothing to do

    const primary = parseId(primaryId);
    if (!primary || !isAuthed(primary, ctx)) return; // primary still unavailable

    inProgress = true;
    try {
      await switchTo(primary, ctx, "Recovered from fallback — ");
    } finally {
      inProgress = false;
    }
  });
}
