/**
 * Shared mutation-guard engine.
 *
 * Generic helpers for "locked / armed" gate extensions that gate CLI tools
 * with live, hard-to-reverse side effects (cloud, orchestration, IaC, ...).
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
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import { execFile } from "node:child_process";
import { classify, findInvocations, hasDryRun } from "./classify.ts";
import type { ToolConfig } from "./classify.ts";

export type { ToolConfig, VerbPosition, Classification, Invocation } from "./classify.ts";
export { classify, findInvocations, hasDryRun, normalizeCommand } from "./classify.ts";

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
  const checkCommand = (command: string): string[] => {
    const issues: string[] = [];
    for (const inv of findInvocations(command, allNames)) {
      const tool = toolByName.get(inv.cli)!;
      if (hasDryRun(inv.fullCommand)) continue; // real dry-run, scoped to this invocation

      const result = classify(tool, inv.tokens);
      const verb = inv.tokens.slice(0, 2).join(" ") || inv.cli;

      if (result.kind === "mutation") {
        issues.push(
          `${inv.cli} ${verb}: ${result.highRisk ? "high-risk op" : "mutation"} blocked: ${domain} gate is locked.`,
        );
      } else if (result.kind === "unknown") {
        issues.push(`${inv.cli} ${verb}: unrecognised verb, blocked: ${domain} gate is locked.`);
      }
    }
    return issues;
  };

  guardRegistry.set(domain, {
    domain,
    cliNames: allNames,
    getMode: () => mode,
    setMode: (m) => void (mode = m),
    checkCommand,
  });

  pi.on("tool_call", async (event, ctx) => {
    if (!isToolCallEventType("bash", event)) return;

    if (mode === "locked") {
      const issues = checkCommand(event.input.command);
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

    for (const inv of findInvocations(event.input.command, allNames)) {
      const tool = toolByName.get(inv.cli)!;
      if (hasDryRun(inv.fullCommand)) continue; // real dry-run, scoped to this invocation

      const result = classify(tool, inv.tokens);

      if (result.kind === "mutation") {
        if (!ctx.hasUI) {
          return { block: true, reason: `${Domain} mutation needs interactive confirmation, unavailable here.` };
        }
        let note = "";
        if (tool.getContext) {
          try {
            const c = await tool.getContext();
            if (c) note = `Current context: ${c}\n\n`;
          } catch {
            /* best-effort */
          }
        }
        const title = result.highRisk ? `⚠️⚠️ HIGH-RISK ${domain.toUpperCase()}` : `${icon} ${Domain} mutation`;
        const ok = await ctx.ui.confirm(title, `${note}${inv.fullCommand.slice(0, 400)}\n\nAllow?`);
        if (!ok) return { block: true, reason: `User denied ${domain} mutation` };
      }
    }
  });

  pi.on("session_start", (_e, ctx) => {
    mode = "locked";
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
