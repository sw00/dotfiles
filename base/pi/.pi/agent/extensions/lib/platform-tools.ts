/**
 * Pure platform-conditional tool filter (no IO, no pi runtime) used by
 * ../no-powershell.ts. Kept pi-free so it is unit-testable standalone:
 *
 *   node --experimental-strip-types --test platform-tools.test.ts
 *
 * Lives in lib/ (not the extensions root) so pi's extension discovery —
 * which loads every root-level *.ts — never mistakes this for an extension.
 */

/** Builtin tool names that only work on the listed platforms. */
const WIN32_ONLY_TOOLS = new Set(["powershell"]);

/**
 * Drop platform-invalid builtin tools from an active-tool list.
 * Remove-only: never adds, reorders, or deduplicates; does not mutate the input.
 * `platform` is a parameter (not read from `process`) so tests are deterministic.
 */
export function prunePlatformTools(tools: string[], platform: string): string[] {
  if (platform === "win32") return tools;
  return tools.filter((name) => !WIN32_ONLY_TOOLS.has(name));
}