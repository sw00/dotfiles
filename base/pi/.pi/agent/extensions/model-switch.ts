/**
 * model-switch — Graceful model switching & auto-fallback for Telegram bridge
 *
 * Manual:  "use <alias>" or "switch to <alias>" in Telegram chat
 *          /models — list available aliases
 *          /cycle — cycle to next enabled model
 * Auto:    on 429/529 from the provider, falls back to the next separate-quota
 *          model in the chain so pi's built-in auto-retry continues the turn.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// ── Model aliases ──────────────────────────────────────────────────────────
// Keys = short aliases the user types.  IDs must match `pi --list-models` output.
// The entry marked `defaultFallback` is the default anchor when cycling or
// when no current model matches any alias.
const MODELS: Array<{
  key: string;
  provider: string;
  id: string;
  label: string;
}> = [
  { key: "opus",     provider: "anthropic",   id: "claude-opus-4-8",        label: "Claude Opus 4·8" },
  { key: "sonnet",   provider: "anthropic",   id: "claude-sonnet-5",        label: "Claude Sonnet 5" },
  { key: "haiku",    provider: "anthropic",   id: "claude-haiku-4-5",       label: "Claude Haiku 4·5" },
  { key: "kimi",     provider: "opencode-go", id: "kimi-k3",                label: "Kimi K3" },
  { key: "minimax",  provider: "opencode-go", id: "minimax-m3",             label: "MiniMax M3" },
  { key: "deepseek", provider: "opencode-go", id: "deepseek-v4-flash",      label: "DeepSeek V4 Flash" },
  { key: "qwen",     provider: "opencode-go", id: "qwen3.7-plus",           label: "Qwen 3·7 Plus" },
  { key: "glm",      provider: "opencode-go", id: "glm-5.2",                label: "GLM 5·2" },
  { key: "pro",      provider: "opencode-go", id: "deepseek-v4-pro",        label: "DeepSeek V4 Pro" },
];

// Fallback chain: when a model in this list is rate-limited, auto-switch to
// the next one.  Order = most-constrained → most-headroom.
const FALLBACK_CHAIN = ["opus", "sonnet", "haiku", "kimi", "minimax", "deepseek"];

// ── Helpers ────────────────────────────────────────────────────────────────

function findModel(key: string) {
  return MODELS.find((m) => m.key === key.toLowerCase());
}

function findKeyForModel(provider: string, id: string): string | undefined {
  return MODELS.find((m) => m.provider === provider && m.id === id)?.key;
}

function aliasList(): string {
  return MODELS.map((m) => `\`${m.key}\``).join(", ");
}

// ── Extension ──────────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  // ── Switch helper ──────────────────────────────────────────────────────

  async function switchTo(
    key: string,
    ctx: { modelRegistry: any; model: any; ui: any },
    reason = "",
  ): Promise<boolean> {
    const entry = findModel(key);
    if (!entry) {
      ctx.ui.notify(
        `Unknown model '${key}'. Aliases: ${aliasList()}`,
        "error",
      );
      return false;
    }

    const model = ctx.modelRegistry.find(entry.provider, entry.id);
    if (!model) {
      ctx.ui.notify(
        `${entry.provider}/${entry.id} not found in registry`,
        "error",
      );
      return false;
    }

    const ok = await pi.setModel(model);
    if (ok) {
      const prefix = reason ? `${reason} ` : "";
      ctx.ui.notify(
        `${prefix}Model → ${entry.label} (${entry.provider}/${entry.id})`,
        "info",
      );
    } else {
      ctx.ui.notify(
        `No API key configured for ${entry.provider}`,
        "error",
      );
    }
    return ok;
  }

  // ── /use <alias>  (manual switch, extension command) ───────────────────

  pi.registerCommand("use", {
    description: `Switch model: /use ${MODELS.map((m) => m.key).join("|")}`,
    handler: async (args, ctx) => {
      const key = args.trim().split(/\s+/)[0]; // take first word only
      if (!key) {
        ctx.ui.notify(`Usage: /use <model>.  Aliases: ${aliasList()}`, "info");
        return;
      }
      await switchTo(key, ctx);
    },
  });

  // ── /models  (list available) ─────────────────────────────────────────

  pi.registerCommand("models", {
    description: "List model aliases and the active model",
    handler: async (_args, ctx) => {
      const cur = ctx.model;
      const curLabel = cur
        ? `${cur.provider}/${cur.id}`
        : "none";
      ctx.ui.notify(
        `Active: ${curLabel}\nAliases: ${aliasList()}\nFallback chain: ${FALLBACK_CHAIN.map((k) => `\`${k}\``).join(" → ")}`,
        "info",
      );
    },
  });

  // ── /cycle  (move to next enabled model) ──────────────────────────────

  pi.registerCommand("cycle", {
    description: "Cycle to the next model in the fallback chain",
    handler: async (_args, ctx) => {
      const cur = ctx.model;
      const curKey = cur ? findKeyForModel(cur.provider, cur.id) : undefined;
      const idx = curKey ? FALLBACK_CHAIN.indexOf(curKey) : -1;
      const nextKey = FALLBACK_CHAIN[(idx + 1) % FALLBACK_CHAIN.length];
      await switchTo(nextKey, ctx, "Cycled — ");
    },
  });

  // ── input event: plain-text model switching ───────────────────────────
  // More reliable from Telegram than extension commands because pi-telegram
  // wraps messages with a [telegram] prefix.  The input event fires before
  // the text is sent to the LLM, so we can intercept and handle locally.
  //
  // Triggers on:  "use <alias>"  |  "switch to <alias>"  |  "/use <alias>"

  pi.on("input", async (event, ctx) => {
    const text = event.text.trim();

    // Match "use <key>", "switch to <key>", "/use <key>"
    const match = text.match(/(?:^|\s)(?:switch\s+to\s+|(?:\/)?use\s+)([a-zA-Z0-9.-]+)\b/i);
    if (!match) return;

    const key = match[1].toLowerCase();
    const entry = findModel(key);
    if (!entry) return; // not a known model alias — let it pass through to the LLM

    await switchTo(key, ctx);
    return { action: "handled" }; // don't send to LLM
  });

  // ── Auto-fallback on rate limit / overload ────────────────────────────
  // When the provider returns 429 (rate-limited) or 529 (overloaded),
  // hop to the next fallback model.  pi's built-in agent-level retry
  // (retry.enabled, default true) re-issues the failed turn with the new
  // model, so the turn continues transparently.

  let fallbackInProgress = false;
  let lastFallbackAt = 0;

  pi.on("after_provider_response", async (event, ctx) => {
    if (event.status !== 429 && event.status !== 529) return;

    // Guard: don't cascade (retry of a retry) and throttle to 1 fallback/sec
    if (fallbackInProgress) return;
    const now = Date.now();
    if (now - lastFallbackAt < 2000) return;

    const cur = ctx.model;
    if (!cur) return;

    const curKey = findKeyForModel(cur.provider, cur.id);
    if (!curKey) return; // current model not in our alias list — don't touch

    const idx = FALLBACK_CHAIN.indexOf(curKey);
    if (idx < 0 || idx >= FALLBACK_CHAIN.length - 1) return; // already at end

    const nextKey = FALLBACK_CHAIN[idx + 1];

    fallbackInProgress = true;
    lastFallbackAt = now;

    await switchTo(nextKey, ctx, `Rate-limited — `);

    fallbackInProgress = false;
  });
}
