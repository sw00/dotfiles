/**
 * Modes Extension — /chat, /check, /change workflow modes.
 *
 *   change (default) – full tools, Pro worker, escalation ladder active
 *   check            – read-only gate: edit/write disabled, bash restricted
 *                      to read-only commands, domain guards (infra, …)
 *                      forced locked. Pair-troubleshooting: the user is
 *                      the escalation target, no subagent delegation.
 *   chat             – conceptual altitude: model switches to
 *                      claude-bridge/claude-sonnet-5-5,
 *                      tools unrestricted, problem-space framing.
 *
 * Integration with mutation-guard domains (infra-safety.ts): modes may
 * TIGHTEN domain guards (entering check forces them to locked), never
 * LOOSEN them — /change does not auto-open any domain write gate. In
 * check mode, commands touching a guarded CLI (aws, kubectl, …) are
 * classified by that guard's own verb tables, so read-only infra poking
 * works while mutations stay blocked. Single source of truth for verbs.
 *
 * State persists across session resume via pi.appendEntry("modes", ...).
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { checkModeBlock } from "../../lib/check-mode.ts";
import type { CheckModeDomain } from "../../lib/check-mode.ts";
import { getGuards, isShellCall } from "../../lib/mutation-guard.ts";

type Mode = "change" | "check" | "chat";

const CHAT_MODEL = { provider: "claude-bridge", id: "claude-sonnet-5-5" };
const MODE_ORDER: Mode[] = ["change", "check", "chat"];
const MODE_ICON: Record<Mode, string> = { change: "⚡", check: "🔍", chat: "💬" };

const CHECK_PROMPT = `[CHECK MODE — read-only]
Pair-troubleshooting with the user (an expert, in the loop). Understand, don't change: edit/write are off and shell commands are read-only. Investigate empirically — run read-only commands, form and test hypotheses against the system's real state. Report findings and discuss before proposing fixes. Do NOT delegate to subagents here; the user is your partner. For changes, ask the user to switch to /change.]`;

const CHAT_PROMPT = `[CHAT MODE — conceptual]
Birds-eye problem-space thinking with the user: problem statements, domain mapping, trade-offs, options. Tools are unrestricted but do not change anything unless explicitly asked. Prefer research and discussion over action; deliver insight and, when asked, plans.]`;

// ── read-only shell adapter (check mode) ──────────────────────────

function guardedNames(): Set<string> {
  const names = new Set<string>();
  for (const g of getGuards().values()) for (const n of g.cliNames) names.add(n);
  return names;
}

/** The classifier itself is pi-free in ../../lib/check-mode.ts, because a test
 *  cannot import this file (../lib/mutation-guard.ts pulls in pi-ai/typebox).
 *  Domain guards come first — their verb tables are the single source of truth
 *  for infra verbs — and everything else falls through to the read-only list. */
const checkDomain = (): CheckModeDomain => ({
  issues: (c) => [...getGuards().values()].flatMap((g) => g.checkCommand(c)),
  cliNames: guardedNames(),
});

// ── extension ─────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  let mode: Mode = "change";
  let savedModel: { provider: string; id: string } | null = null;

  const updateStatus = (ctx: ExtensionContext) => {
    if (mode === "change") ctx.ui.setStatus("mode", undefined);
    else ctx.ui.setStatus("mode", `${MODE_ICON[mode]} ${mode}`);
  };

  // Toolset is a pure function of mode: check drops edit/write, domain mode
  // tools (e.g. infra_mode), and anything that can write *indirectly*. Guards
  // are force-locked and cannot be opened from within check. `subagent` is
  // hidden because it hands write access to another process: it can spawn the
  // write-capable `worker`, and delegation is a second write path no matter how
  // the worker's shell is named (check mode's own prompt already says not to
  // delegate). `AskClaude` accepts `mode: "full"`; the askclaude package is NOT
  // installed today, so that entry is a no-op kept ahead of the install
  // (`allowFullMode: false` in claude-bridge.json is the backstop).
  const CHECK_HIDDEN_TOOLS = new Set(["edit", "write", "AskClaude", "subagent"]);
  const domainModeTools = () => new Set([...getGuards().values()].map((g) => `${g.domain}_mode`));
  const applyToolGate = (m: Mode) => {
    // Remove-only on entry; on exit re-add only what WE hide, never the whole
    // tool list. getAllTools() is safe here because the filter is this module's
    // own hide-list: a tool another extension pruned (see no-powershell.ts) is
    // not `hidden`, so it is never re-added — and unlike a snapshot of what we
    // dropped, this survives a /reload rebuilding the active list.
    const hidden = (t: string) => CHECK_HIDDEN_TOOLS.has(t) || domainModeTools().has(t);
    const active = pi.getActiveTools();
    if (m === "check") {
      pi.setActiveTools(active.filter((t) => !hidden(t)));
    } else {
      pi.setActiveTools([...active, ...pi.getAllTools().map((t) => t.name).filter((t) => hidden(t) && !active.includes(t))]);
    }
  };

  async function applyMode(next: Mode, ctx: ExtensionContext, persist = true) {
    const prev = mode;
    if (next === prev) return;

    // model transitions: chat → claude-bridge/claude-sonnet-5-5; leaving chat
    // → restore previous
    if (next === "chat" && prev !== "chat") {
      savedModel = ctx.model ? { provider: ctx.model.provider, id: ctx.model.id } : null;
      const m = ctx.modelRegistry.find(CHAT_MODEL.provider, CHAT_MODEL.id);
      if (m) {
        const ok = await pi.setModel(m);
        if (!ok) ctx.ui.notify(`No API key for ${CHAT_MODEL.provider}/${CHAT_MODEL.id} — keeping current model`, "warning");
      } else {
        ctx.ui.notify(`${CHAT_MODEL.provider}/${CHAT_MODEL.id} not in model registry — keeping current model`, "warning");
      }
    } else if (prev === "chat" && savedModel) {
      // Only restore if the user didn't manually switch models during chat.
      const stillChatModel =
        ctx.model?.provider === CHAT_MODEL.provider && ctx.model?.id === CHAT_MODEL.id;
      if (stillChatModel) {
        const m = ctx.modelRegistry.find(savedModel.provider, savedModel.id);
        if (m) await pi.setModel(m);
      }
      savedModel = null;
    }

    applyToolGate(next);

    // tighten domain guards, never loosen them; also clear their status
    // so an armed gate indicator doesn't survive being force-locked
    if (next === "check") for (const g of getGuards().values()) {
      g.setMode("locked");
      ctx.ui.setStatus(`${g.domain}-mode`, undefined);
    }

    mode = next;
    updateStatus(ctx);
    ctx.ui.notify(`${MODE_ICON[next]} mode → ${next}`, "info");
    if (persist) pi.appendEntry("modes", { mode: next, savedModel });
  }

  for (const m of MODE_ORDER) {
    pi.registerCommand(m, {
      description: `Switch to ${m} mode${m === "check" ? " (read-only, pair-troubleshooting)" : m === "chat" ? " (conceptual, claude-sonnet-5-5 via bridge)" : " (default, full execution)"}`,
      handler: async (_args, ctx) => applyMode(m, ctx),
    });
  }

  pi.registerShortcut("ctrl+alt+m", {
    description: "Cycle modes (change → check → chat)",
    handler: async (ctx) => {
      const next = MODE_ORDER[(MODE_ORDER.indexOf(mode) + 1) % MODE_ORDER.length];
      await applyMode(next, ctx);
    },
  });

  // read-only shell gate (check mode only): gates every tool that delivers a
  // shell command (SHELL_TOOLS — hypa_shell under pi-hypa, bash wherever the
  // harness still exposes it).
  pi.on("tool_call", async (event) => {
    if (mode !== "check") return;
    if (!isShellCall(event)) return;
    const command = event.input.command;
    const reason = checkModeBlock(command, checkDomain());
    if (reason) return { block: true, reason };
  });

  // drop stale mode-context injections (re-injected per turn when active)
  pi.on("context", async (event) => ({
    messages: event.messages.filter((m) => (m as { customType?: string }).customType !== "modes-context"),
  }));

  pi.on("before_agent_start", async () => {
    if (mode === "check") return { message: { customType: "modes-context", content: CHECK_PROMPT } };
    if (mode === "chat") return { message: { customType: "modes-context", content: CHAT_PROMPT } };
  });

  pi.on("session_start", async (_event, ctx) => {
    // restore last mode from session entries (survives resume/fork)
    let restored: Mode = "change";
    let restoredModel: { provider: string; id: string } | null = null;
    for (const e of ctx.sessionManager.getBranch()) {
      if (e.type === "custom" && e.customType === "modes") {
        const data = e.data as { mode?: Mode; savedModel?: { provider: string; id: string } | null } | undefined;
        restored = data?.mode ?? "change";
        restoredModel = data?.savedModel ?? null;
      }
    }
    mode = restored;
    savedModel = restoredModel;
    applyToolGate(mode);
    if (mode === "check") {
      for (const g of getGuards().values()) {
        g.setMode("locked");
        ctx.ui.setStatus(`${g.domain}-mode`, undefined);
      }
    } else if (mode === "chat") {
      const m = ctx.modelRegistry.find(CHAT_MODEL.provider, CHAT_MODEL.id);
      if (m) await pi.setModel(m);
    }
    updateStatus(ctx);
  });
}
