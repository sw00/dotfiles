/**
 * Hypa command unwrapping — pure string manipulation, no pi deps.
 *
 * pi-hypa rewrites native `bash` tool calls into two shapes:
 *   1. `hypa -c "..."`      — generic compression wrapper
 *   2. `hypa <cli> ...`      — tool-specific wrapper (e.g. kubectl)
 *
 * Safety/mode guards classify the *inner* shell command, so we unwrap before
 * classification. Unknown hypa invocations are left as-is; the guard will see
 * `hypa` and either allow it (read-only) or block it as unrecognised.
 */

/** Remove a leading `hypa -c` or `hypa --command` wrapper and return the inner shell command. */
export function unwrapHypaC(command: string): string | null {
  const trimmed = command.trimStart();
  if (!trimmed.startsWith("hypa ")) return null;

  const m = trimmed.match(/^hypa\s+(?:-c|--command)\s+(.*)$/s);
  if (!m) return null;

  let inner = m[1].trimEnd();
  if (
    (inner.startsWith('"') && inner.endsWith('"')) ||
    (inner.startsWith("'") && inner.endsWith("'"))
  ) {
    inner = inner.slice(1, -1);
  }
  return inner;
}

/**
 * Remove a leading `hypa <cli> ...` wrapper when <cli> is one of the known
 * guarded CLI names. Returns the inner command (e.g. "kubectl get pods").
 */
export function unwrapHypaCli(command: string, knownClis: ReadonlySet<string>): string | null {
  const trimmed = command.trimStart();
  if (!trimmed.startsWith("hypa ")) return null;

  const tokens = trimmed.split(/\s+/);
  if (tokens.length < 2) return null;

  // Avoid conflating with `hypa -c` — handled by unwrapHypaC.
  if (tokens[1] === "-c" || tokens[1] === "--command") return null;

  const cli = tokens[1];
  if (!knownClis.has(cli)) return null;

  return tokens.slice(1).join(" ");
}

/**
 * Best-effort unwrapping: tries `hypa -c` first, then `hypa <known-cli>`.
 * Falls back to the original command.
 */
export function unwrapHypaCommand(
  command: string,
  knownClis: ReadonlySet<string>,
): string {
  return unwrapHypaC(command) ?? unwrapHypaCli(command, knownClis) ?? command;
}
