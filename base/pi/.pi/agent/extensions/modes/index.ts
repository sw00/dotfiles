/**
 * Modes Extension — /chat, /check, /change workflow modes.
 *
 *   change (default) – full tools, Flash worker, escalation ladder active
 *   check            – read-only gate: edit/write disabled, bash restricted
 *                      to read-only commands, domain guards (infra, …)
 *                      forced locked. Pair-troubleshooting: the user is
 *                      the escalation target, no subagent delegation.
 *   chat             – conceptual altitude: model switches to kimi-k3,
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
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { getGuards } from "../lib/mutation-guard.ts";

type Mode = "change" | "check" | "chat";

const CHAT_MODEL = { provider: "opencode-go", id: "kimi-k3" };
const MODE_ORDER: Mode[] = ["change", "check", "chat"];
const MODE_ICON: Record<Mode, string> = { change: "⚡", check: "🔍", chat: "💬" };

const CHECK_PROMPT = `[CHECK MODE — read-only]
Pair-troubleshooting with the user (an expert, in the loop). Understand, don't change: edit/write are off and bash is read-only. Investigate empirically — run read-only commands, form and test hypotheses against the system's real state. Report findings and discuss before proposing fixes. Do NOT delegate to subagents here; the user is your partner. For changes, ask the user to switch to /change.]`;

const CHAT_PROMPT = `[CHAT MODE — conceptual]
Birds-eye problem-space thinking with the user: problem statements, domain mapping, trade-offs, options. Tools are unrestricted but do not change anything unless explicitly asked. Prefer research and discussion over action; deliver insight and, when asked, plans.]`;

// ── read-only bash classification (check mode) ────────────────────

const SIMPLE_READ = new Set([
  // file inspection & search
  "cat", "head", "tail", "less", "more", "grep", "rg", "find", "fd", "ls", "pwd", "tree",
  "file", "stat", "wc", "du", "diff", "comm", "sort", "uniq", "column", "cut", "paste", "tr",
  "jq", "yq", "strings", "nm", "objdump", "readelf", "ldd",
  // path & text helpers
  "basename", "dirname", "realpath", "readlink", "echo", "printf", "seq", "test", "true", "false",
  // system info
  "df", "free", "ps", "top", "htop", "env", "printenv", "id", "whoami", "uname", "date", "uptime",
  "hostname", "which", "whereis", "man", "lscpu", "lsmem", "lsblk", "lsusb", "lspci", "vmstat",
  "iostat", "nproc", "getent", "journalctl",
  // network reads
  "ping", "dig", "nslookup", "host", "traceroute", "ss", "netstat", "ifconfig",
]);

const GIT_READ = new Set([
  "status", "log", "diff", "show", "branch", "blame", "remote", "rev-parse", "ls-files",
  "describe", "shortlog", "reflog", "grep", "ls-remote", "whatchanged", "count-objects",
]);

const SUBCOMMAND_READ: Record<string, Set<string> | ((t: string[]) => boolean)> = {
  git: (t) => {
    const sub = t[1] ?? "";
    if (GIT_READ.has(sub)) return true;
    if (sub === "stash") return t[2] === "list";
    if (sub === "tag") return t.length === 2 || t[2] === "-l" || t[2] === "--list";
    if (sub === "config") return t.includes("--get") || t.includes("-l") || t.includes("--list");
    return false;
  },
  docker: (t) => {
    if (t[1] === "compose") return ["ps", "logs", "config", "top", "images"].includes(t[2] ?? "");
    return ["ps", "images", "logs", "inspect", "stats", "top", "version", "info"].includes(t[1] ?? "");
  },
  systemctl: new Set(["status", "list-units", "list-timers", "is-active", "is-enabled", "show", "cat"]),
  npm: new Set(["list", "ls", "outdated", "view", "info", "--version"]),
  pip: new Set(["show", "list", "--version"]),
  pip3: new Set(["show", "list", "--version"]),
  apt: new Set(["list", "show", "policy", "--version"]),
  "apt-cache": new Set(["show", "policy", "search"]),
  dpkg: new Set(["-l", "-s", "--list", "--status", "--version"]),
  gh: new Set(["status", "view", "list", "search", "diff"]),
  snap: new Set(["list", "info", "--version"]),
  flatpak: new Set(["list", "info"]),
  mise: new Set(["ls", "list", "current", "which", "registry", "--version"]),
};

function guardedNames(): Set<string> {
  const names = new Set<string>();
  for (const g of getGuards().values()) for (const n of g.cliNames) names.add(n);
  return names;
}

/** Returns a block reason, or null if the command is read-only-safe. */
function checkBashAllowed(command: string): string | null {
  // Domain-guarded CLIs (aws, kubectl, terraform, …): defer to the guard's
  // own verb tables — single source of truth for infra read/mutation.
  for (const guard of getGuards().values()) {
    const issues = guard.checkCommand(command);
    if (issues.length) return issues.join(" ") + " (check mode)";
  }

  const guarded = guardedNames();
  const segments = command.split(/&&|\|\||[;|]/).map((s) => s.trim()).filter(Boolean);

  for (const seg of segments) {
    if (/`|\$\(/.test(seg)) return `command substitution is blocked in check mode (read-only).`;

    // strip leading env assignments (FOO=bar cmd …)
    const stripped = seg.replace(/^(?:\w+=\S+\s+)+/, "");

    // output redirection mutates files; allow fd redirects and /dev/null
    const noBenignRedir = stripped.replace(/\d?>&\d/g, "").replace(/\d?>\s*\/dev\/null/g, "");
    if (noBenignRedir.includes(">")) return `output redirection is blocked in check mode (read-only).`;

    const tokens = stripped.split(/\s+/);
    const cmd = tokens[0];
    if (guarded.has(cmd)) continue; // already vetted by the domain guard above
    if (SIMPLE_READ.has(cmd)) continue;

    if (cmd === "curl" || cmd === "wget") {
      if (/-X\s*(POST|PUT|DELETE|PATCH)\b|--data|\s-d\s|--upload-file|-T\s|-F\s|--post-data|--post-file|--method/.test(stripped)) {
        return `${cmd} with upload/mutation flags is blocked in check mode (read-only).`;
      }
      continue;
    }

    const rule = SUBCOMMAND_READ[cmd];
    if (rule) {
      const ok = typeof rule === "function" ? rule(tokens) : rule.has(tokens[1] ?? "");
      if (ok) continue;
      return `${cmd} ${tokens[1] ?? ""}: only read-only ${cmd} subcommands are allowed in check mode.`;
    }

    return `${cmd}: not allowlisted in check mode (read-only). Switch to /change for mutations, or ask the user.`;
  }
  return null;
}

// ── extension ─────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  let mode: Mode = "change";
  let savedModel: { provider: string; id: string } | null = null;

  const updateStatus = (ctx: ExtensionContext) => {
    if (mode === "change") ctx.ui.setStatus("mode", undefined);
    else ctx.ui.setStatus("mode", `${MODE_ICON[mode]} ${mode}`);
  };

  // Toolset is a pure function of mode: check drops edit/write and domain
  // mode tools (e.g. infra_mode), since guards are force-locked and cannot
  // be opened from within check. Otherwise all tools.
  const applyToolGate = (m: Mode) => {
    const all = pi.getAllTools().map((t) => t.name);
    if (m === "check") {
      const domainModeTools = new Set(
        [...getGuards().values()].map((g) => `${g.domain}_mode`)
      );
      pi.setActiveTools(all.filter((t) => t !== "edit" && t !== "write" && !domainModeTools.has(t)));
    } else {
      pi.setActiveTools(all);
    }
  };

  async function applyMode(next: Mode, ctx: ExtensionContext, persist = true) {
    const prev = mode;
    if (next === prev) return;

    // model transitions: chat → kimi-k3; leaving chat → restore previous
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
      description: `Switch to ${m} mode${m === "check" ? " (read-only, pair-troubleshooting)" : m === "chat" ? " (conceptual, kimi-k3)" : " (default, full execution)"}`,
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

  // read-only bash gate (check mode only)
  pi.on("tool_call", async (event) => {
    if (mode !== "check" || !isToolCallEventType("bash", event)) return;
    const reason = checkBashAllowed(event.input.command);
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
