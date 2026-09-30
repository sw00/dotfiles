/**
 * No-PowerShell Extension
 *
 * pi registers the `powershell` builtin on every platform, but it refuses to
 * run off Windows (dist/utils/shell.js: getPowerShellConfig() throws unless
 * process.platform === "win32"). Worse, when it sits in the active tool set
 * without native grep/find/ls, the system-prompt builder emits a "Use
 * PowerShell for file operations..." guideline — actively misleading on
 * macOS/Linux/WSL. The modes extension's tool gate re-adds it on every mode
 * switch (setActiveTools(getAllTools())), so the prune must run per turn,
 * not once at startup: before_agent_start fires after any re-add and before
 * the request's system prompt / tool definitions are built.
 *
 * This file is only the pi wiring; the pure filter (and its unit tests) live
 * in ./lib/platform-tools.ts, mirroring the edit-guardian.ts ↔
 * lib/edit-diagnostic.ts and infra-safety.ts ↔ lib/mutation-guard.ts splits.
 *
 * Remove-only filter: composes with hypa's replace-mode filter regardless of
 * extension load order (both filters only ever drop names). Fail-open: if the
 * tool API is somehow missing, or nothing changed, do nothing.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { prunePlatformTools } from "./lib/platform-tools.ts";

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", () => {
    // getActiveTools/setActiveTools are standard ExtensionAPI members
    // (dist/core/extensions/types.d.ts); the guard is belt-and-braces so an
    // older pi degrades to a no-op instead of crashing the turn.
    if (typeof pi.getActiveTools !== "function" || typeof pi.setActiveTools !== "function") return;

    const current = pi.getActiveTools();
    const pruned = prunePlatformTools(current, process.platform);
    // Remove-only; skip the write when nothing changed (common fail-open path).
    if (pruned.length !== current.length) pi.setActiveTools(pruned);
  });
}