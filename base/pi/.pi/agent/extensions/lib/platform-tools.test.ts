/**
 * Regression tests for the pure platform tool filter in ./platform-tools.ts.
 * prunePlatformTools() is pure (no IO, no pi runtime install required):
 *
 *   node --experimental-strip-types --test platform-tools.test.ts
 *
 * It lives in lib/ (not the extensions root) so pi's extension discovery —
 * which loads every root-level *.ts — never mistakes this test for an
 * extension. Each case pins one behavior of the no-powershell extension.
 */

import assert from "node:assert/strict";
import { test } from "node:test";
import { prunePlatformTools } from "./platform-tools.ts";

test("drops powershell on darwin and linux (WSL pi runs as linux)", () => {
  const tools = ["read", "bash", "powershell", "hypa_shell", "subagent"];
  assert.deepEqual(prunePlatformTools(tools, "darwin"), ["read", "bash", "hypa_shell", "subagent"]);
  assert.deepEqual(prunePlatformTools(tools, "linux"), ["read", "bash", "hypa_shell", "subagent"]);
});

test("keeps powershell on win32 (the only platform where the builtin runs)", () => {
  const tools = ["read", "bash", "powershell"];
  assert.deepEqual(prunePlatformTools(tools, "win32"), tools);
});

test("no-op when powershell is absent (skip-the-write path)", () => {
  const tools = ["read", "bash", "edit", "write"];
  assert.deepEqual(prunePlatformTools(tools, "darwin"), tools);
  assert.equal(prunePlatformTools(tools, "darwin").length, tools.length);
});

test("does not mutate the input array (setActiveTools gets a fresh list)", () => {
  const tools = ["powershell", "read"];
  prunePlatformTools(tools, "darwin");
  assert.deepEqual(tools, ["powershell", "read"]);
});