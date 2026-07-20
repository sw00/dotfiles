/**
 * model-switch — Graceful model switching & auto-fallback for the Telegram bridge.
 *
 * Config-driven: the fallback set is your `enabledModels` list in settings.json
 * (the same curated list used for Ctrl+P cycling). Nothing is hardcoded — to add
 * OpenRouter (or any provider) as a fallback, just add it to `enabledModels` and
 * configure its auth. This extension picks it up automatically.
 *
 * Manual (Telegram or TUI):
 *   /use <query>     — switch to a model by fuzzy id match (any authed model)
 *   /models          — list the fallback set + current model
 *   /cycle           — cycle to the next model in the fallback set
 *   plain text:      "use <query>" or "switch to <query>"
 *
 * Auto:
 *   On 429 (rate-limited) or 529 (overloaded) it hops to the next model in the
 *   fallback set, preferring a DIFFERENT provider (rate limits are usually
 *   provider/account-scoped). pi's built-in agent-level retry then re-issues the
 *   failed turn with the new model, so the conversation continues transparently.
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

  function fallbackSet(ctx: { modelRegistry: any; cwd: string }): MiniModel[] {
    return resolveFallbackSet(readEnabledModels(ctx.cwd), available(ctx));
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
    return match(fallbackSet(ctx)) ?? match(available(ctx));
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
    description: "List the fallback set (from enabledModels) and the active model",
    handler: async (_args, ctx) => {
      const cur = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : "none";
      const set = fallbackSet(ctx);
      const list = set.length
        ? set.map((m, i) => `${i + 1}. ${m.provider}/${m.id}`).join("\n")
        : "(none — enabledModels empty or unauthed)";
      ctx.ui.notify(`Active: ${cur}\nFallback set (from enabledModels):\n${list}`, "info");
    },
  });

  // ── /cycle ────────────────────────────────────────────────────────────────
  pi.registerCommand("cycle", {
    description: "Cycle to the next model in the fallback set",
    handler: async (_args, ctx) => {
      const set = fallbackSet(ctx);
      if (set.length === 0) {
        ctx.ui.notify("Fallback set is empty — check enabledModels.", "error");
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

  // ── Auto-fallback on rate limit / overload ─────────────────────────────────
  let inProgress = false;
  let lastAt = 0;

  pi.on("after_provider_response", async (event, ctx) => {
    if (event.status !== 429 && event.status !== 529) return;
    if (inProgress) return;
    const now = Date.now();
    if (now - lastAt < 2000) return; // throttle: max 1 fallback / 2s

    const cur = ctx.model;
    if (!cur) return;

    const set = fallbackSet(ctx);
    if (set.length < 2) return;

    // Rotate the set to start just after the current model.
    const idx = set.findIndex((m) => m.provider === cur.provider && m.id === cur.id);
    const rotated = idx >= 0 ? [...set.slice(idx + 1), ...set.slice(0, idx)] : set;

    // Prefer a different provider (rate limits are provider/account-scoped),
    // else take the next model in order.
    const next =
      rotated.find((m) => m.provider !== cur.provider) ?? rotated[0];
    if (!next || (next.provider === cur.provider && next.id === cur.id)) return;

    inProgress = true;
    lastAt = now;
    await switchTo(next, ctx, `Rate-limited (${event.status}) — `);
    inProgress = false;
  });
}
