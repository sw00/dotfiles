/**
 * Infrastructure Safety Extension
 *
 * Live-infrastructure CLIs: aws, az, gcloud, kubectl, terraform/tofu.
 *
 *   locked – read-only: mutation commands are physically blocked
 *   armed  – write gate open: mutations allowed with confirmation
 *            (high-risk operations get a stronger confirmation)
 *
 * Commands: /infra-lock, /infra-arm
 * Tool:     infra_mode (mode "locked" | "armed"; for LLM self-regulation)
 *
 * Built on the shared engine in lib/mutation-guard.ts. The per-CLI verb
 * tables live in lib/infra-tables.ts (pure data, shared with the tests).
 * The engine gates every tool in SHELL_TOOLS (hypa_shell under pi-hypa, bash
 * wherever the harness exposes it), so this file needs no tool names.
 * If you want to gate other tool domains (git, databases, package managers,
 * ...), write a new extension that imports createMutationGuard() with its
 * own verb tables and its own `domain` string — don't grow this file into a
 * catch-all. Different domains have different danger signals (SQL content,
 * git flags, etc.) that don't fit this CLI-verb-token model anyway.
 *
 * The one exception, because it is not a CLI-verb domain at all: L2 also gates
 * agent READS under a `secrets/` directory (lib/secret-paths.ts), on the FILE
 * tools rather than the shell. It has no mode and no confirm — an unreadable
 * credential store is not something a human should be able to approve into the
 * transcript — and it is deliberately not applied to shell commands, which are
 * the classifier's and L3's business (docs/AGENT-SAFETY.md §2 L2, §2.1a).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createMutationGuard, execForContext } from "./lib/mutation-guard.ts";
import type { ToolConfig } from "./lib/classify.ts";
import { AWS, AZ, GCLOUD, KUBECTL, TERRAFORM } from "./lib/infra-tables.ts";
import { secretPathBlock } from "./lib/secret-paths.ts";

// KUBECTL's getContext (live current-context, shown in confirm prompts) is
// pi-wired via execForContext, so it can't live in the pi-free tables module.
// Compose it on here.
const kubectl: ToolConfig = {
  ...KUBECTL,
  getContext: () => execForContext("kubectl", ["config", "current-context"]),
};

export default function (pi: ExtensionAPI) {
  createMutationGuard(pi, {
    domain: "infra",
    icon: "☁️",
    tools: [AWS, AZ, GCLOUD, kubectl, TERRAFORM],
  });

  // Second thing L2 gates: a file-tool path under a `secrets/` directory. The
  // decision (and its reason) is pure — lib/secret-paths.ts — so it stays
  // testable without the harness; this is only the hook. A call the predicate
  // cannot resolve blocks (fail closed); a file tool with no path is not this
  // check's business and passes through.
  pi.on("tool_call", async (event, ctx) => secretPathBlock(event.toolName, event.input, ctx.cwd) ?? undefined);
}
