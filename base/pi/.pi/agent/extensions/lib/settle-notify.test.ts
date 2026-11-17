/**
 * settle-notify.test.ts — the extension's behaviour, with a fake `pi`.
 *
 * It lives in lib/ because that is where every suite this harness runs lives, but it
 * imports the extension itself: the point is that a notification is dispatch-only, so the
 * whole module can be driven by a stand-in for `pi.exec`/`pi.on` and never touch a real
 * transport. Count is pinned by check.sh.
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
  /** Make every exec throw, i.e. no transport at all. */
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
      if (opts.throws) throw new Error("no transport");
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

/** Title and body are the last two args for every transport. */
function lastPush(calls: string[][]): [string, string] {
  const last = calls.at(-1) ?? [];
  return [last.at(-2) ?? "", last.at(-1) ?? ""];
}

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
  process.env.TMUX = "/tmp/tmux-1000/default,1,0";
  process.env.TMUX_PANE = "%1";
  try {
    const { handlers, calls } = harness({ tmux: "11" });
    await handlers.get("agent_settled")!({ aborted: false }, ctx);
    assert.equal(calls.length, 1, "only the focus probe, no push");
    assert.equal(calls[0][0], "tmux");
  } finally {
    delete process.env.TMUX;
    delete process.env.TMUX_PANE;
  }
});

test("a failing transport is swallowed, never surfaced to the session", async () => {
  const { handlers } = harness({ throws: true });
  await assert.doesNotReject(handlers.get("agent_settled")!({ aborted: false }, ctx));
});

test("the mute switch suppresses registration at load", async () => {
  process.env.PI_SETTLE_NOTIFY = "0";
  try {
    // A fresh module instance: the switch is read once, at load.
    const muted = await import("../settle-notify.ts?muted=1");
    const { handlers } = harness({}, muted.default);
    assert.equal(handlers.size, 0, "nothing is subscribed when muted");
  } finally {
    delete process.env.PI_SETTLE_NOTIFY;
  }
});
