/**
 * Shared mutation-guard engine.
 *
 * Generic helpers for "locked / armed" gate extensions that gate CLI commands
 * with live, hard-to-reverse side effects (cloud, orchestration, IaC, ...).
 *
 * This extension assumes the `pi-hypa` extension is configured in
 * `replace` mode, where the native `bash` tool is hidden and shell commands
 * arrive through `hypa_shell`. That is NOT guaranteed on other harnesses
 * (PiG, plain pi without hypa), so the guard gates every tool in
 * `SHELL_TOOLS` — an ungated shell makes the whole write gate decorative.
 * The command string is the intended shell command, not a compression wrapper.
 *
 * A domain extension (e.g. infra-safety.ts) supplies CLI names + per-CLI
 * verb tables and calls createMutationGuard(). Verb-table data is never
 * sent to the model, so expanding coverage is free context-wise.
 *
 * Other domains (git, databases, ...) should import this rather than
 * duplicating the machinery, each with its own `domain` string so their
 * mode toggles stay independent.
 *
 * Pure parsing/classification logic lives in ./classify.ts (zero pi
 * dependencies, unit-testable standalone). This file only adds the pi
 * wiring: tool/command registration and the tool_call interceptor.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { execFile } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { classifyInvocations, confirmPayload, inspectCommand, SCRIPT_MAX_BYTES } from "./classify.ts";
import type { ReadFile, ToolConfig } from "./classify.ts";
import { isShellCall } from "./shell-tools.ts";

export type { ToolConfig, VerbPosition, Classification, Invocation } from "./classify.ts";
export { classify, findInvocations, hasDryRun, hasHelpFlag, normalizeCommand } from "./classify.ts";

/**
 * Every tool that delivers a raw shell command lives in ./shell-tools.ts — one
 * declaration, no pi import, so the publish guard and the tests share it
 * without pulling the harness in. A gate wired to one name only is bypassed by
 * the other: pi-hypa's replace mode hides the native `bash` tool, but other
 * harnesses expose it, so both must be gated.
 */
export { SHELL_TOOLS, isShellCall, isShellTool, SHELL_TOOL_SET } from "./shell-tools.ts";

/** The engine's filesystem access, used to inline `sh x.sh` script bodies.
 *  stat() first: readFileSync on /dev/zero (or any fifo/device) never returns,
 *  so a non-regular file is refused as unverifiable rather than read, and an
 *  oversized one is refused before its bytes are loaded. */
const readFile: ReadFile = (path) => {
  try {
    const st = statSync(path);
    if (!st.isFile() || st.size > SCRIPT_MAX_BYTES) return null;
    return readFileSync(path, "utf8");
  } catch {
    return null;
  }
};

export interface MutationGuardConfig {
  domain: string; // e.g. "infra" — drives command/tool names + messages
  icon: string; // e.g. "☁️"
  tools: ToolConfig[];
}

export interface MutationGuardHandle {
  getMode: () => "locked" | "armed";
  setMode: (mode: "locked" | "armed") => void;
}

/** Registry entry exposed to other extensions (e.g. the modes extension). */
export interface GuardRegistration {
  domain: string;
  cliNames: ReadonlySet<string>;
  getMode: () => "locked" | "armed";
  setMode: (mode: "locked" | "armed") => void;
  /** Read-only-semantics check of a command against this domain's verb tables.
   *  Returns a list of issues; empty means the command is read-only-safe. */
  checkCommand: (command: string) => string[];
}

const guardRegistry = new Map<string, GuardRegistration>();

/** All registered domain guards. Modes extension: you may TIGHTEN guards
 *  (setMode("locked")), never LOOSEN them — write gates only open via the
 *  domain's own commands/tools. */
export function getGuards(): ReadonlyMap<string, GuardRegistration> {
  return guardRegistry;
}

export function createMutationGuard(pi: ExtensionAPI, config: MutationGuardConfig): MutationGuardHandle {
  let mode: "locked" | "armed" = "locked";
  const { domain, icon } = config;
  const Domain = domain.charAt(0).toUpperCase() + domain.slice(1);
  const modeTool = `${domain}_mode`;

  const allNames = new Set(config.tools.flatMap((t) => t.names));
  const toolByName = new Map<string, ToolConfig>();
  for (const tool of config.tools) for (const name of tool.names) toolByName.set(name, tool);

  const setStatus = (ctx: ExtensionContext) => {
    // Hide the safe default (locked); only surface when armed — distinct
    // from the session-mode indicator so the two axes can't be confused.
    if (mode === "locked") ctx.ui.setStatus(`${domain}-mode`, undefined);
    else ctx.ui.setStatus(`${domain}-mode`, `🔓 ${domain}`);
  };
  const setMode = (m: "locked" | "armed", ctx: ExtensionContext) => {
    mode = m;
    setStatus(ctx);
    ctx.ui.notify(`${icon} ${domain} → ${m}`, "info");
  };

  // Model-facing tool. Kept terse: it lives in the system prompt every turn.
  pi.registerTool({
    name: modeTool,
    label: `${Domain} Mode`,
    description:
      `Set ${domain} write gate for ${[...allNames].join(", ")}. `
      + `locked = read-only (mutations blocked); armed = mutations allowed (user confirms). `
      + `Call with mode "armed" before modifying resources, then run the command.`,
    promptSnippet: `${domain} write gate (locked/armed) for ${[...allNames].join(", ")}`,
    promptGuidelines: [
      `${domain} tools start locked; mutating/destructive commands are blocked. `
      + `To change ${domain} resources, call ${modeTool} with mode "armed" first, then run the command (the user still confirms).`,
    ],
    parameters: Type.Object({ mode: StringEnum(["locked", "armed"] as const) }),
    async execute(_id, params, _sig, _upd, ctx) {
      setMode(params.mode, ctx);
      return {
        content: [{ type: "text" as const, text: `${domain} gate: ${params.mode}` }],
        details: { mode: params.mode },
      };
    },
  });

  pi.registerCommand(`${domain}-lock`, {
    description: `${Domain}: lock the write gate (read-only, mutations blocked)`,
    handler: async (_a, ctx) => setMode("locked", ctx),
  });
  pi.registerCommand(`${domain}-arm`, {
    description: `${Domain}: arm the write gate (mutations allowed, with confirmation)`,
    handler: async (_a, ctx) => setMode("armed", ctx),
  });

  /** Read-only-semantics check, reusable by other extensions via the registry. */
  const checkCommand = (command: string): string[] =>
    inspectCommand(command, allNames, toolByName, domain, readFile).issues;

  /** Depth >= 1 findings: shapes the walk could not resolve INSIDE an already
   *  inlined script body. Best-effort by contract, so they are told to the human
   *  once per session and never enter model context — the point is to be honest
   *  about what was inspected, not to nag or to block (`bash check.sh` carries
   *  hundreds of `$VAR` words and would otherwise be unrunnable in every mode). */
  const reportedNotes = new Set<string>();
  const reportNestedNotes = (ctx: ExtensionContext, notes: string[]): void => {
    const fresh = notes.filter((note) => !reportedNotes.has(note));
    if (fresh.length === 0) return;
    for (const note of fresh) reportedNotes.add(note);
    ctx.ui.notify(
      `ℹ️ ${domain}: ${fresh.length} shape(s) inside an inlined script could not be resolved `
        + `(not enforced) — ${fresh[0]}`,
      "info",
    );
  };

  guardRegistry.set(domain, {
    domain,
    cliNames: allNames,
    getMode: () => mode,
    setMode: (m) => void (mode = m),
    checkCommand,
  });

  pi.on("tool_call", async (event, ctx) => {
    // Both shell tools: hypa_shell under pi-hypa, bash wherever it survives.
    if (!isShellCall(event)) return;

    const command = event.input.command;

    if (mode === "locked") {
      const { issues, nestedNotes } = inspectCommand(command, allNames, toolByName, domain, readFile);
      reportNestedNotes(ctx, nestedNotes);
      if (issues.length) {
        return {
          block: true,
          reason:
            issues.join(" ")
            + ` If the user intends this mutation, call ${modeTool}(mode="armed") then retry; otherwise keep to read-only commands.`,
        };
      }
      return;
    }

    const { verdicts, unresolved, unknowns, nestedNotes, text: expanded } = classifyInvocations(
      command,
      allNames,
      toolByName,
      readFile,
    );
    reportNestedNotes(ctx, nestedNotes);

    // A script nobody could read is not a script we may wave through — not even
    // armed. The human can read /tmp/x.sh themselves and re-run it by hand.
    if (unresolved.length > 0) {
      return {
        block: true,
        reason:
          `${unresolved.join(", ")}: script body unreadable or too large to inspect — unknown, blocked `
          + `even with the ${domain} gate armed.`,
      };
    }

    let payload: ReturnType<typeof confirmPayload> | null = null;
    /** The human reviews the WHOLE command once — with the script bodies the
     *  gate inlined, because `sh /tmp/x.sh` as a launcher line hides the
     *  `terraform destroy` inside it. Too long to review is too long to
     *  confirm: split the command instead. */
    const review = () => {
      payload ??= confirmPayload(expanded);
      return payload;
    };

    for (const { tool, result, nested } of verdicts) {
      // Armed means "ask before mutating", not "allow anything that is not a
      // mutation": an unrecognised verb passes silently if we skip it here.
      if (result.kind === "read") continue;
      // An unrecognised verb inside an inlined body is a note (reported above),
      // not a prompt: inside a large script most verb-shaped words are prose.
      if (nested && result.kind === "unknown") continue;
      const unknown = result.kind === "unknown";

      if (!ctx.hasUI) {
        return {
          block: true,
          reason: `${Domain} ${unknown ? "unrecognised command" : "mutation"} needs interactive confirmation, unavailable here.`,
        };
      }
      const reviewed = review();
      if (!reviewed.ok) return { block: true, reason: reviewed.reason };

      let note = "";
      if (!unknown && tool.getContext) {
        try {
          const c = await tool.getContext();
          if (c) note = `Current context: ${c}\n\n`;
        } catch {
          /* best-effort */
        }
      }
      const title = unknown
        ? `❓ UNRECOGNISED ${domain.toUpperCase()}`
        : result.highRisk
          ? `⚠️⚠️ HIGH-RISK ${domain.toUpperCase()}`
          : `${icon} ${Domain} mutation`;
      const ok = await ctx.ui.confirm(title, `${note}${reviewed.text}\n\nAllow?`);
      if (!ok) return { block: true, reason: `User denied ${domain} command` };
    }

    // Shapes with no body to inspect: a pipeline into a shell, a `$VAR` command
    // word. Loud, never silent.
    if (unknowns.length > 0) {
      if (!ctx.hasUI) {
        return { block: true, reason: `${Domain} command cannot be inspected and needs interactive confirmation, unavailable here.` };
      }
      const reviewed = review();
      if (!reviewed.ok) return { block: true, reason: reviewed.reason };
      const ok = await ctx.ui.confirm(
        `❓ UNINSPECTABLE ${domain.toUpperCase()}`,
        `${unknowns.join("\n")}\n\n${reviewed.text}\n\nAllow?`,
      );
      if (!ok) return { block: true, reason: `User denied ${domain} command` };
    }
  });

  pi.on("session_start", (_e, ctx) => {
    mode = "locked";
    reportedNotes.clear();
    setStatus(ctx);
  });

  return { getMode: () => mode, setMode: (m) => void (mode = m) };
}

/** Best-effort short command output for getContext(); null on any error/timeout. */
export function execForContext(cmd: string, args: string[], timeoutMs = 1500): Promise<string | null> {
  return new Promise((resolve) => {
    try {
      const child = execFile(cmd, args, { timeout: timeoutMs }, (err, out) => resolve(err ? null : out.trim() || null));
      child.on("error", () => resolve(null));
    } catch {
      resolve(null);
    }
  });
}
