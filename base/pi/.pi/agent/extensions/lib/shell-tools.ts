/**
 * The shell tools a gate must listen on — ONE declaration, no imports at all.
 *
 * Why this file exists: the same two-name list used to be declared twice, once
 * in ./mutation-guard.ts (the write gate) and once privately in
 * ../publish-guard.ts, and a test pinned the copy. Duplication is how a gate
 * goes half-blind: add a third shell tool (or rename one) and only the copy
 * somebody remembered gets updated, leaving the other hook decorative. The
 * predicate lives here too, so `publish-guard.ts` can use it and still be
 * importable by the unit tests — it must not drag
 * `@earendil-works/pi-coding-agent` in, hence zero imports.
 *
 * `bash` is pi's native shell tool; `hypa_shell` is pi-hypa's replacement. Which
 * one a session actually gets depends on the harness (pi-hypa's `replace` mode
 * hides `bash`; plain pi and PiG expose it), so a gate wired to one name only
 * is bypassed by the other. Both, always.
 */

/** Every tool name that delivers a raw shell command. Add a tool here, once. */
export const SHELL_TOOLS = ["bash", "hypa_shell"] as const;

export type ShellTool = (typeof SHELL_TOOLS)[number];

/** Membership form, for call sites that hold a name and no event. */
export const SHELL_TOOL_SET: ReadonlySet<string> = new Set<string>(SHELL_TOOLS);

/** True when `name` is one of the shell tools. */
export function isShellTool(name: string): boolean {
  return SHELL_TOOL_SET.has(name);
}

/**
 * True for a tool_call carrying a shell command, whichever shell tool it is.
 * Checks `toolName` only: the hook is registered for `tool_call`, so the event
 * type is not in question, and this stays free of the harness package (pi's
 * `isToolCallEventType` would be a runtime import, which the tests cannot load).
 */
export function isShellCall(event: unknown): event is { input: { command: string } } {
  const name = (event as { toolName?: unknown } | null | undefined)?.toolName;
  return typeof name === "string" && SHELL_TOOL_SET.has(name);
}
