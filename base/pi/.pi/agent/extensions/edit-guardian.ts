/**
 * Edit Guardian Extension
 *
 * Turns a failed `edit` into a *loud, informative* failure instead of a blind
 * retry. When the built-in edit tool cannot apply a replacement, this appends a
 * whitespace-/Unicode-escaped view of BOTH what the model provided and the
 * closest region actually in the file, so the model can diff them and fix the
 * edit in one retry.
 *
 * This file is only the pi wiring + filesystem read; all matching/formatting
 * logic (and its unit tests) live in ./lib/edit-diagnostic.ts, mirroring the
 * infra-safety.ts ↔ lib/mutation-guard.ts split. Deliberately scoped to a
 * diagnostic only — no tolerant matcher (the built-in already fuzzy-matches),
 * no read-before-write gate, no validator (check.sh is the canonical harness).
 *
 * Edit-only, read-only (never mutates files), fail-safe (any handler error is
 * swallowed so the original tool result always passes through unchanged).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync, statSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import { buildDiagnostic, parseEditInput } from "./lib/edit-diagnostic.ts";

const MAX_FILE_BYTES = 2 * 1024 * 1024; // skip huge files

function errorTextOf(content: unknown): string {
  if (!Array.isArray(content)) return "";
  return content
    .filter((c): c is { type: string; text?: string } => !!c && (c as { type?: string }).type === "text")
    .map((c) => c.text ?? "")
    .join("\n");
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_result", (event, ctx) => {
    try {
      if (event.toolName !== "edit" || !event.isError) return;
      const input = event.input as Record<string, unknown> | undefined;
      if (!input) return;
      const parsed = parseEditInput(input);
      if (!parsed) return;

      // The built-in throws on the FIRST failing edit and names it in the
      // message ("edits[N]" for multi-edit, plain text for a single edit).
      const m = errorTextOf(event.content).match(/edits\[(\d+)\]/);
      const idx = m ? Number(m[1]) : 0;
      const edit = parsed.edits[idx] ?? parsed.edits[0];
      if (!edit || edit.oldText.length === 0) return;

      const absPath = isAbsolute(parsed.path) ? parsed.path : resolve(ctx.cwd, parsed.path);
      let fileText: string;
      try {
        if (statSync(absPath).size > MAX_FILE_BYTES) return;
        fileText = readFileSync(absPath, "utf-8");
      } catch {
        return;
      }

      const diag = buildDiagnostic(fileText, parsed.path, edit.oldText, m ? idx : 0);
      if (!diag) return;

      const prior = Array.isArray(event.content) ? event.content : [];
      return { content: [...prior, { type: "text" as const, text: "\n" + diag }] };
    } catch {
      // Fail-safe: never let the guard break the tool result.
      return;
    }
  });
}
