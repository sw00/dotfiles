/**
 * settle-notify.test.ts — the extension's behaviour, with a fake `pi`.
 *
 * It lives in lib/ because that is where every suite this harness runs lives, but it
 * imports the extension itself: both surfaces are dispatch-only, so the whole module can
 * be driven by a stand-in for `pi.exec`/`pi.on` and never touch a real transport or a real
 * tmux server. Count is pinned by check.sh.
 */

import assert from "node:assert/strict";
import { test } from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import settleNotify from "../settle-notify.ts";

type Handler = (event: { aborted?: boolean }, ctx: { cwd: string }) => Promise<void>;
type Factory = (pi: ExtensionAPI) => void;

interface Opts {
  /** What `git rev-parse --abbrev-ref HEAD --show-toplevel` answers. */
  git?: string;
  /** What `tmux display-message … '#{pane_active}#{window_active}'` answers. */
  tmux?: string;
  /** Make every exec throw, i.e. no transport and no tmux at all. */
  throws?: boolean;
}

function harness(opts: Opts = {}, factory: Factory = settleNotify) {
  const handlers = new Map<string, Handler>();
  const calls: string[][] = [];
  const pi = {
    on(event: string, fn: Handler) {
      handlers.set(event, fn);
    },
    async exec(cmd: string, args: string[] = [], _options?: unknown) {
      if (opts.throws) throw new Error("nothing to run");
      calls.push([cmd, ...args]);
      if (cmd === "git") return { stdout: opts.git ?? "feature\n/tmp/proj", code: 0 };
      if (cmd === "tmux") return { stdout: opts.tmux ?? "10", code: 0 };
      return { stdout: "", code: 0 };
    },
  };
  factory(pi as unknown as ExtensionAPI);
  return { handlers, calls };
}

const ctx = { cwd: "/tmp/proj" };

/** Everything that is not a probe: the actual notification. */
function pushes(calls: string[][]): string[][] {
  return calls.filter((c) => c[0] !== "git" && c[0] !== "tmux");
}

/** Title and body are the last two args for every transport. */
function lastPush(calls: string[][]): [string, string] {
  const last = pushes(calls).at(-1) ?? [];
  return [last.at(-2) ?? "", last.at(-1) ?? ""];
}

function inTmux(): () => void {
  process.env.TMUX = "/tmp/tmux-1000/default,1,0";
  process.env.TMUX_PANE = "%1";
  return () => {
    delete process.env.TMUX;
    delete process.env.TMUX_PANE;
  };
}

const flagSets = (calls: string[][]) => calls.filter((c) => c[0] === "tmux" && c.includes("@pi_waiting") && c.at(-1) === "1");
const flagClears = (calls: string[][]) => calls.filter((c) => c[0] === "tmux" && c.includes("@pi_waiting") && c.includes("-u"));

test("a settled run pushes repo/branch and why", async () => {
  const { handlers, calls } = harness();
  await handlers.get("agent_settled")!({ aborted: false }, ctx);
  assert.deepEqual(lastPush(calls), ["proj/feature", "settled — waiting on you"]);
});

test("an aborted run pushes nothing (Escape means the human is there)", async () => {
  const { handlers, calls } = harness();
  await handlers.get("agent_settled")!({ aborted: true }, ctx);
  assert.deepEqual(calls, []);
});

test("a blocking prompt pushes, and says it needs an answer", async () => {
  const { handlers, calls } = harness();
  await handlers.get("ui_prompt_start")!({}, ctx);
  assert.deepEqual(lastPush(calls), ["proj/feature", "needs an answer"]);
});

test("the pane being looked at is never pushed for", async () => {
  const reset = inTmux();
  try {
    const { handlers, calls } = harness({ tmux: "11" });
    await handlers.get("agent_settled")!({ aborted: false }, ctx);
    assert.deepEqual(pushes(calls), [], "only probes and the flag, no push");
  } finally {
    reset();
  }
});

test("a failing transport is swallowed, never surfaced to the session", async () => {
  const reset = inTmux();
  try {
    const { handlers } = harness({ throws: true });
    await assert.doesNotReject(handlers.get("agent_settled")!({ aborted: false }, ctx));
  } finally {
    reset();
  }
});

test("the mute switch silences the push but keeps the window flag", async () => {
  process.env.PI_SETTLE_NOTIFY = "0";
  const reset = inTmux();
  try {
    // A fresh module instance: the switch is read once, at load.
    const muted = await import("../settle-notify.ts?muted=1");
    const { handlers, calls } = harness({}, muted.default);
    await handlers.get("agent_settled")!({ aborted: false }, ctx);
    assert.deepEqual(pushes(calls), [], "muted");
    assert.equal(flagSets(calls).length, 1, "the bar still gets flagged");
  } finally {
    reset();
    delete process.env.PI_SETTLE_NOTIFY;
  }
});

test("settling raises the window flag", async () => {
  const reset = inTmux();
  try {
    const { handlers, calls } = harness();
    await handlers.get("agent_settled")!({ aborted: false }, ctx);
    assert.equal(flagSets(calls).length, 1);
  } finally {
    reset();
  }
});

test("a new run clears the flag (work resumed)", async () => {
  const reset = inTmux();
  try {
    const { handlers, calls } = harness();
    await handlers.get("agent_start")!({}, ctx);
    assert.equal(flagClears(calls).length, 1);
  } finally {
    reset();
  }
});

test("outside tmux there is no window to flag", async () => {
  const { handlers, calls } = harness();
  await handlers.get("agent_settled")!({ aborted: false }, ctx);
  assert.deepEqual(calls.filter((c) => c[0] === "tmux"), []);
  assert.equal(pushes(calls).length, 1, "the desktop push still happens");
});
