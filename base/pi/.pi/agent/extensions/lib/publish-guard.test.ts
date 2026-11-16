/**
 * Wiring tests for ../publish-guard.ts — the pi-facing half of the publish
 * guard (process spawn, file reads, the fail-closed decisions around them).
 *
 * publish-scan.test.ts proves the pure decision with an INJECTED scanner; this
 * file exercises the wiring the way pi drives it: a fake `tool_call` event, a
 * fake ExtensionContext, and a fake `gitleaks` binary on disk. That is where
 * the fail-closed claim actually lives (spawn failures, unreadable files, a
 * locked secret store), so it is tested against real subprocesses:
 *
 *   node --experimental-strip-types --test lib/publish-guard.test.ts
 *
 * It lives in lib/ so pi's extension discovery (every root-level *.ts) never
 * loads it as an extension.
 */

import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { createOnToolCall, type GuardOptions } from "../publish-guard.ts";

/** Not a credential shape, so only the exact-value half can match it. */
const PLANTED = "planted-fake-value-0d1e2f";

const ROOT = mkdtempSync(join(tmpdir(), "publish-guard-wiring-"));

/** A `gitleaks` stand-in: a shell script, so the real spawn path is used. */
function bin(name: string, shell: string): string {
  const dir = mkdtempSync(join(ROOT, "bin-"));
  const path = join(dir, name);
  writeFileSync(path, `#!/bin/sh\n${shell}\n`);
  chmodSync(path, 0o755);
  return path;
}

function workdir(): string {
  return mkdtempSync(join(ROOT, "cwd-"));
}

function file(dir: string, name: string, content: string): string {
  const path = join(dir, name);
  writeFileSync(path, content);
  return path;
}

type Result = { block: true; reason: string } | undefined;

/** A guard with the secret store stubbed to "empty but readable" by default. */
function guard(overrides: Partial<GuardOptions> = {}) {
  const call = createOnToolCall({ readSecretsFile: () => "", ...overrides });
  return (toolName: string, input: Record<string, unknown>, cwd = workdir()): Promise<Result> =>
    call({ toolName, input } as never, { cwd, ui: { notify() {} } } as never);
}

const CLEAN_BIN = () => bin("gitleaks", "cat > /dev/null; echo '[]'");

// ── the two publish classes the wiring classifies ────────────────────────────

test("a web tool's arguments are scanned; a rule id blocks", async () => {
  const gitleaks = bin("gitleaks", "cat > /dev/null; echo '[{\"RuleID\":\"github-pat\"}]'");
  const res = await guard({ gitleaksBin: gitleaks })("fetch_content", { url: "https://example.test/x?q=1" });
  assert.ok(res, "expected a block");
  assert.equal(res.block, true);
  assert.match(res.reason, /github-pat/);
  assert.ok(!res.reason.includes("example.test"), "reason must not echo the published text");
});

test("a clean web call passes through untouched", async () => {
  const res = await guard({ gitleaksBin: CLEAN_BIN() })("web_search", { query: "sourdough starter" });
  assert.equal(res, undefined);
});

test("non-publishing calls are never inspected", async () => {
  const missing = join(ROOT, "not-a-binary");
  const g = guard({ gitleaksBin: missing, readSecretsFile: () => "" });
  assert.equal(await g("bash", { command: "git status" }), undefined, "read-only shell");
  assert.equal(await g("read", { path: "notes.md" }), undefined, "unknown tool");
  assert.equal(await g("fetch_content", {}), undefined, "web tool with no arguments");
});

// ── referenced files ────────────────────────────────────────────────────────

test("a readable --body-file is scanned and a known value blocks by variable name", async () => {
  const cwd = workdir();
  file(cwd, "notes.md", `This PR adds the token ${PLANTED} to CI.`);
  const res = await guard({
    gitleaksBin: CLEAN_BIN(),
    readSecretsFile: () => `set -gx GITHUB_TOKEN '${PLANTED}'`,
  })("bash", { command: "gh pr create --title x --body-file notes.md" }, cwd);
  assert.ok(res, "expected a block");
  assert.match(res.reason, /value of \$GITHUB_TOKEN/);
  assert.ok(!res.reason.includes(PLANTED), "reason must not echo the secret");
});

test("a missing --body-file blocks, and the reason names the flag not the path", async () => {
  const cwd = workdir();
  const res = await guard({ gitleaksBin: CLEAN_BIN() })(
    "bash",
    { command: "gh pr create --body-file ./token-shaped-notes.md" },
    cwd,
  );
  assert.ok(res, "expected a block");
  assert.match(res.reason, /could not be read/);
  assert.match(res.reason, /--body-file/, "reason must name the flag");
  assert.ok(!res.reason.includes("token-shaped-notes.md"), "reason must not echo the supplied path");
});

// ── scanner failure modes: every one blocks ─────────────────────────────────

test("a scanner that is not installed blocks", async () => {
  const res = await guard({ gitleaksBin: join(ROOT, "definitely-absent") })("bash", {
    command: "gh pr create --body 'ordinary prose'",
  });
  assert.ok(res);
  assert.match(res.reason, /not installed/);
  assert.match(res.reason, /^publish-guard: blocked — /);
});

test("a scanner that exits non-zero blocks", async () => {
  const res = await guard({ gitleaksBin: bin("gitleaks", "cat > /dev/null; exit 2") })("bash", {
    command: "gh pr create --body 'ordinary prose'",
  });
  assert.ok(res);
  assert.match(res.reason, /exit 2/);
});

test("a scanner that times out blocks", async () => {
  const res = await guard({ gitleaksBin: bin("gitleaks", "sleep 5"), scanTimeoutMs: 300 })("bash", {
    command: "gh pr create --body 'ordinary prose'",
  });
  assert.ok(res);
  assert.match(res.reason, /timed out/);
});

test("a scanner that prints malformed JSON blocks", async () => {
  const res = await guard({ gitleaksBin: bin("gitleaks", "cat > /dev/null; echo not-json") })("bash", {
    command: "gh pr create --body 'ordinary prose'",
  });
  assert.ok(res);
  assert.match(res.reason, /not JSON/);
});

test("a scanner that stops reading stdin blocks instead of crashing", async () => {
  // 1.5 MB of body: larger than a pipe buffer, so the write hits a closed pipe
  // once the child exits without reading. Without an stdin `error` listener that
  // is an unhandled 'error' event — the process dies instead of blocking.
  const cwd = workdir();
  file(cwd, "big.md", "a".repeat(1_500_000));
  const res = await guard({ gitleaksBin: bin("gitleaks", "sleep 1; exit 1"), scanTimeoutMs: 10_000 })(
    "bash",
    { command: "gh pr create --body-file big.md" },
    cwd,
  );
  assert.ok(res, "expected a block");
  assert.equal(res.block, true);
});

// ── classification, secret store, substitutions, cwd changes ────────────────

test("a classification failure blocks rather than letting the call through", async () => {
  const input: Record<string, unknown> = {};
  Object.defineProperty(input, "command", {
    enumerable: true,
    get() {
      throw new Error("unreadable input");
    },
  });
  const res = await guard({ gitleaksBin: CLEAN_BIN() })("bash", input);
  assert.ok(res, "an uninspectable call must block");
  assert.match(res.reason, /could not be classified/);
});

test("a locked secret store blocks and names the file", async () => {
  const locked = () => "\u0000GITCRYPT\u0000\u0002\u0013binary-ciphertext";
  const res = await guard({ gitleaksBin: CLEAN_BIN(), readSecretsFile: locked })("bash", {
    command: "gh pr create --body 'ordinary prose'",
  });
  assert.ok(res, "locked secrets must block");
  assert.match(res.reason, /secrets\/env\.fish/);
  assert.match(res.reason, /git-crypt/);

  const unreadable = await guard({
    gitleaksBin: CLEAN_BIN(),
    readSecretsFile: () => {
      throw Object.assign(new Error("nope"), { code: "ENOENT" });
    },
  })("bash", { command: "gh pr create --body 'ordinary prose'" });
  assert.ok(unreadable, "an unreadable secret store must block");
  assert.match(unreadable.reason, /secrets\/env\.fish/);
});

test("an unresolvable substitution blocks and points at --body-file", async () => {
  const res = await guard({ gitleaksBin: CLEAN_BIN() })("bash", {
    command: 'gh pr create --body "$(date)"',
  });
  assert.ok(res, "expected a block");
  assert.match(res.reason, /--body-file/);
});

test("a relative file behind cd/pushd blocks", async () => {
  const res = await guard({ gitleaksBin: CLEAN_BIN() })("bash", {
    command: "cd /other && gh pr create --body-file notes.md",
  });
  assert.ok(res, "expected a block");
  assert.match(res.reason, /relative path/);
  assert.ok(!res.reason.includes("notes.md"), "reason must not echo the supplied path");
});

// ── the block result shape the harness consumes ─────────────────────────────

test("blocked() has exactly the shape pi's tool_call hook expects", async () => {
  const res = await guard({ gitleaksBin: join(ROOT, "definitely-absent") })("bash", {
    command: "gh pr create --body 'x'",
  });
  assert.ok(res);
  assert.deepEqual(Object.keys(res).sort(), ["block", "reason"]);
  assert.equal(res.block, true);
  assert.equal(typeof res.reason, "string");
  assert.match(res.reason, /^publish-guard: blocked — /);
  assert.ok(res.reason.length > 20, "the reason must say what to do");
});
