/**
 * Pure diagnostic core for the edit-guardian extension.
 *
 * pi-free and IO-free: buildDiagnostic() takes file text and the failed edit,
 * so it runs standalone under `node --experimental-strip-types --test` (see
 * ./edit-diagnostic.test.ts). The pi wiring + filesystem read live in the thin
 * top-level ../edit-guardian.ts, mirroring infra-safety.ts ↔ mutation-guard.ts.
 *
 * Purpose: pi's built-in edit already tolerates trailing whitespace + folds
 * smart quotes / em-en-dashes (edit-diff.ts:normalizeForFuzzyMatch). The
 * residual failures it does NOT cover are blank-line COUNT and LEADING-indent
 * mismatches, plus unfolded non-ASCII (e.g. U+2194 ↔). This surfaces the ACTUAL
 * bytes so the model fixes the edit in one retry instead of guessing. Matching
 * is never altered here — this is diagnostic-only.
 */

const MAX_DIAG_LINES = 48; // cap appended output
const CANDIDATE_LIMIT = 2; // show at most N matching regions
const CONTEXT_LINES = 1; // extra file lines around the region

/** Python-repr-style single line: quotes reveal leading/trailing spaces; tabs,
 *  CRs, control chars and all non-ASCII are escaped so `—` (\u2014) is
 *  unmistakable from `-`. */
export function reprLine(s: string): string {
  let out = '"';
  for (const ch of s) {
    const code = ch.codePointAt(0)!;
    if (ch === "\\") out += "\\\\";
    else if (ch === '"') out += '\\"';
    else if (ch === "\t") out += "\\t";
    else if (ch === "\r") out += "\\r";
    else if (code < 0x20) out += "\\x" + code.toString(16).padStart(2, "0");
    else if (code > 0x7e)
      out += code > 0xffff ? `\\u{${code.toString(16)}}` : `\\u${code.toString(16).padStart(4, "0")}`;
    else out += ch;
  }
  return out + '"';
}

export function normalizeToLF(text: string): string {
  return text.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
}

/** Extract `{ path, edits }` from a possibly-legacy edit tool input (edits as a
 *  JSON string, or top-level oldText/newText). Returns null if unusable. */
export function parseEditInput(
  input: Record<string, unknown>,
): { path: string; edits: Array<{ oldText: string; newText: string }> } | null {
  let path = input.path ?? input.file_path;
  if (typeof path !== "string" || path.length === 0) return null;
  if (path.startsWith("@")) path = path.slice(1);

  let edits: unknown = input.edits;
  if (typeof edits === "string") {
    try {
      edits = JSON.parse(edits);
    } catch {
      /* handled below */
    }
  }
  if (!Array.isArray(edits)) {
    if (typeof input.oldText === "string" && typeof input.newText === "string") {
      edits = [{ oldText: input.oldText, newText: input.newText }];
    } else {
      return null;
    }
  }
  const clean = (edits as unknown[]).filter(
    (e): e is { oldText: string; newText: string } =>
      !!e && typeof (e as { oldText?: unknown }).oldText === "string",
  );
  if (clean.length === 0) return null;
  return { path, edits: clean };
}

/** Build the failure diagnostic from file text (no IO). Returns null when there
 *  is nothing useful to say (empty/all-blank oldText). */
export function buildDiagnostic(
  fileText: string,
  displayPath: string,
  oldText: string,
  editIndex: number,
): string | null {
  if (oldText.trim().length === 0) return null; // no anchor to locate
  const raw = fileText.startsWith("\uFEFF") ? fileText.slice(1) : fileText;
  const fileLines = normalizeToLF(raw).split("\n");
  const oldLines = normalizeToLF(oldText).split("\n");

  const out: string[] = [];
  out.push(`── edit-guardian: edits[${editIndex}] did not match ${displayPath} ──`);
  out.push(`You provided (whitespace & non-ASCII escaped):`);
  for (const l of oldLines.slice(0, MAX_DIAG_LINES / 3)) out.push(`  ${reprLine(l)}`);

  // Locate the region to show. Similarity is used ONLY to pick which region to
  // display back — never to change what gets matched/applied. Three tiers:
  //   1. any oldText line matching a file line exactly (trimmed),
  //   2. any oldText line contained in a file line,
  //   3. token-overlap fallback (catches the anchor line itself being the typo,
  //      e.g. the model wrote `<->` where the file has an unfolded `↔`).
  const oldAnchors = oldLines
    .map((l, i) => ({ text: l.trim(), i }))
    .filter((a) => a.text.length > 0)
    .sort((a, b) => b.text.length - a.text.length);

  let candidates: number[] = [];
  let anchorIdxInOld = 0;
  for (const a of oldAnchors) {
    const hits = fileLines.map((l, i) => (l.trim() === a.text ? i : -1)).filter((i) => i >= 0);
    if (hits.length > 0) {
      candidates = hits;
      anchorIdxInOld = a.i;
      break;
    }
  }
  if (candidates.length === 0) {
    for (const a of oldAnchors) {
      if (a.text.length < 3) continue;
      const hits = fileLines.map((l, i) => (l.includes(a.text) ? i : -1)).filter((i) => i >= 0);
      if (hits.length > 0) {
        candidates = hits;
        anchorIdxInOld = a.i;
        break;
      }
    }
  }
  if (candidates.length === 0 && oldAnchors.length > 0) {
    const longest = oldAnchors[0];
    const tokens = longest.text.split(/\s+/).filter((t) => t.length >= 2);
    if (tokens.length > 0) {
      let best = { i: -1, score: 0 };
      fileLines.forEach((l, i) => {
        const hit = tokens.filter((t) => l.includes(t)).length / tokens.length;
        if (hit > best.score) best = { i, score: hit };
      });
      if (best.i >= 0 && best.score >= 0.5) {
        candidates = [best.i];
        anchorIdxInOld = longest.i;
      }
    }
  }

  if (candidates.length === 0) {
    out.push(`Closest region not found — the block may not exist in the file at all.`);
  } else {
    out.push(`Closest region${candidates.length > 1 ? "s" : ""} actually in the file (1-based line numbers):`);
    for (const c of candidates.slice(0, CANDIDATE_LIMIT)) {
      const start = Math.max(0, c - anchorIdxInOld - CONTEXT_LINES);
      const end = Math.min(fileLines.length, c - anchorIdxInOld + oldLines.length + CONTEXT_LINES);
      for (let i = start; i < end && out.length < MAX_DIAG_LINES; i++) {
        const marker = i === c ? ">" : " ";
        out.push(`  ${marker}${String(i + 1).padStart(4)}│ ${reprLine(fileLines[i])}`);
      }
      if (candidates.length > 1) out.push("  ─");
    }
    out.push(`Compare blank-line count, leading indent, and any \\u-escaped punctuation, then retry.`);
  }

  if (out.length > MAX_DIAG_LINES) {
    out.length = MAX_DIAG_LINES;
    out.push("  … (truncated)");
  }
  return out.join("\n");
}
