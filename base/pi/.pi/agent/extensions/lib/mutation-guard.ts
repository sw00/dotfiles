/**
 * Shared mutation-guard engine.
 *
 * Generic helpers for "check / change" mode extensions that gate CLI tools
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
import { classify, findInvocations, hasDryRun } from "./classify";
import type { ToolConfig } from "./classify";

export type { ToolConfig, VerbPosition, Classification, Invocation } from "./classify";
export { classify, findInvocations, hasDryRun, normalizeCommand } from "./classify";

export interface MutationGuardConfig {
  domain: string; // e.g. "infra" — drives command/tool names + messages
  icon: string; // e.g. "☁️"
  tools: ToolConfig[];
}

export interface MutationGuardHandle {
  getMode: () => "check" | "change";
  setMode: (mode: "check" | "change") => void;
}

export function createMutationGuard(pi: ExtensionAPI, config: MutationGuardConfig): MutationGuardHandle {
  let mode: "check" | "change" = "check";
  const { domain, icon } = config;
  const Domain = domain.charAt(0).toUpperCase() + domain.slice(1);
  const modeTool = `${domain}_mode`;

  const allNames = new Set(config.tools.flatMap((t) => t.names));
  const toolByName = new Map<string, ToolConfig>();
  for (const tool of config.tools) for (const name of tool.names) toolByName.set(name, tool);

  const setStatus = (ctx: ExtensionContext) => ctx.ui.setStatus(`${domain}-mode`, `${icon} ${mode}`);
  const setMode = (m: "check" | "change", ctx: ExtensionContext) => {
    mode = m;
    setStatus(ctx);
    ctx.ui.notify(`${icon} ${domain} → ${m}`, "info");
  };

  // Model-facing tool. Kept terse: it lives in the system prompt every turn.
  pi.registerTool({
    name: modeTool,
    label: `${Domain} Mode`,
    description:
      `Set ${domain} safety mode for ${[...allNames].join(", ")}. `
      + `check = read-only (mutations blocked); change = mutations allowed (user confirms). `
      + `Call with mode "change" before modifying resources, then run the command.`,
    promptSnippet: `${domain} safety mode (check/change) for ${[...allNames].join(", ")}`,
    promptGuidelines: [
      `${domain} tools start in check mode; mutating/destructive commands are blocked. `
      + `To change ${domain} resources, call ${modeTool} with mode "change" first, then run the command (the user still confirms).`,
    ],
    parameters: Type.Object({ mode: StringEnum(["check", "change"] as const) }),
    async execute(_id, params, _sig, _upd, ctx) {
      setMode(params.mode, ctx);
      return {
        content: [{ type: "text" as const, text: `${domain} mode: ${params.mode}` }],
        details: { mode: params.mode },
      };
    },
  });

  pi.registerCommand(`${domain}-check`, {
    description: `${Domain}: read-only mode (mutations blocked)`,
    handler: async (_a, ctx) => setMode("check", ctx),
  });
  pi.registerCommand(`${domain}-change`, {
    description: `${Domain}: allow mutations (with confirmation)`,
    handler: async (_a, ctx) => setMode("change", ctx),
  });

  pi.on("tool_call", async (event, ctx) => {
    if (!isToolCallEventType("bash", event)) return;

    const issues: string[] = [];
    for (const inv of findInvocations(event.input.command, allNames)) {
      const tool = toolByName.get(inv.cli)!;
      if (hasDryRun(inv.fullCommand)) continue; // real dry-run, scoped to this invocation

      const result = classify(tool, inv.tokens);
      const verb = inv.tokens.slice(0, 2).join(" ") || inv.cli;

      if (mode === "check") {
        if (result.kind === "mutation") {
          issues.push(
            `${inv.cli} ${verb}: ${result.highRisk ? "high-risk op" : "mutation"} blocked in check mode.`,
          );
        } else if (result.kind === "unknown") {
          issues.push(`${inv.cli} ${verb}: unrecognised verb, blocked in check mode.`);
        }
      } else if (result.kind === "mutation") {
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

    if (issues.length) {
      return {
        block: true,
        reason:
          issues.join(" ")
          + ` If the user intends this change, call ${modeTool}(mode="change") then retry; otherwise keep to read-only commands.`,
      };
    }
  });

  pi.on("session_start", (_e, ctx) => {
    mode = "check";
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
