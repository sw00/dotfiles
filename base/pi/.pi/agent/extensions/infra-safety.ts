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
 * If you want to gate other tool domains (git, databases, package managers,
 * ...), write a new extension that imports createMutationGuard() with its
 * own verb tables and its own `domain` string — don't grow this file into a
 * catch-all. Different domains have different danger signals (SQL content,
 * git flags, etc.) that don't fit this CLI-verb-token model anyway.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createMutationGuard, execForContext } from "./lib/mutation-guard.ts";
import type { ToolConfig } from "./lib/classify.ts";
import { AWS, AZ, GCLOUD, KUBECTL, TERRAFORM } from "./lib/infra-tables.ts";

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
}
