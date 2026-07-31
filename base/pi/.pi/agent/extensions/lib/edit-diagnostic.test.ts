/**
 * Regression tests for the pure diagnostic builder in ./edit-diagnostic.ts.
 *
 * buildDiagnostic() takes file text (no IO), so this runs standalone — no pi
 * runtime install required:
 *
 *   node --experimental-strip-types --test edit-diagnostic.test.ts
 *
 * It lives in lib/ (not the extensions root) so pi's extension discovery —
 * which loads every root-level *.ts — never mistakes this test for an
 * extension. Each case pins a residual failure the built-in fuzzy matcher does
 * NOT cover (blank-line count, leading indent, unfolded non-ASCII like U+2194).
 */

import assert from "node:assert/strict";
import { test } from "node:test";
import { buildDiagnostic } from "./edit-diagnostic.ts";

test("surfaces blank-line COUNT mismatch (the 2-vs-3-newline bug)", () => {
  const file = ['    "$AGENT_CFG"', "", "", "# 6. TMUX CONFIG", ""].join("\n");
  // Model assumed ONE blank line; file has TWO.
  const oldText = '    "$AGENT_CFG"\n\n# 6. TMUX CONFIG';
  const diag = buildDiagnostic(file, "check.sh", oldText, 0)!;
  assert.ok(diag, "expected a diagnostic");
  // Between the two content anchors the file has exactly TWO blank lines; the
  // model provided one. Count blanks strictly between them in the shown region.
  const lines = diag.split("\n");
  const a = lines.findIndex((l) => l.includes('"$AGENT_CFG"') && l.includes("│"));
  const b = lines.findIndex((l, i) => i > a && l.includes("TMUX CONFIG") && l.includes("│"));
  const blanks = lines.slice(a + 1, b).filter((l) => /│ ""$/.test(l)).length;
  assert.equal(blanks, 2, "both blank lines shown between the anchors");
  assert.match(diag, /You provided/);
});

test("escapes non-ASCII so U+2194 is unmistakable from ASCII '<->'", () => {
  const file = ["intro", "  parity: a \u2194 b", "end"].join("\n");
  const oldText = "  parity: a <-> b\nWRONGLINE";
  const diag = buildDiagnostic(file, "doc.md", oldText, 1)!;
  assert.ok(diag);
  assert.match(diag, /\\u2194/, "arrow escaped as \\u2194");
  assert.match(diag, /edits\[1\]/, "names the failing edit index");
});

test("leading-indent mismatch still locates the region", () => {
  const file = ["def foo():", "    return 1", ""].join("\n");
  const oldText = "return 1"; // model dropped the 4-space indent
  const diag = buildDiagnostic(file, "x.py", oldText, 0)!;
  assert.ok(diag);
  assert.match(diag, /"    return 1"/, "shows the real leading indent");
});

test("honest 'not found' when the block is absent", () => {
  const file = ["totally", "unrelated", "content"].join("\n");
  const oldText = "supercalifragilistic anchor line\nsecond line";
  const diag = buildDiagnostic(file, "x.txt", oldText, 0)!;
  assert.ok(diag);
  assert.match(diag, /not found/);
});

test("escapes tabs and reveals them in the region", () => {
  const file = ["header", "\tindented with tab", "footer"].join("\n");
  const oldText = "    indented with tab"; // spaces vs a real tab
  const diag = buildDiagnostic(file, "Makefile", oldText, 0)!;
  assert.ok(diag);
  assert.match(diag, /\\tindented with tab/, "tab shown as \\t");
});

test("null when oldText is empty (nothing useful to say)", () => {
  const file = "a\nb\n";
  assert.equal(buildDiagnostic(file, "x", "", 0), null);
});
