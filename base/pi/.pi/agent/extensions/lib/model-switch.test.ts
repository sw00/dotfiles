/**
 * model-switch.test.ts — the extension's handlers, driven through a fake `pi`.
 *
 * It lives in lib/ because that is where every suite this harness runs lives, but it
 * imports the extension itself: every handler is dispatch-only, so model-switch.ts can
 * be driven by stand-ins for pi.setModel/pi.on and the session ctx without a real pi,
 * a real settings file or a real network. Count is pinned by check.sh.
 *
 * The two defects these tests exist for:
 *  - the rate-limit session_start handler used to ignore BRANCH provenance, so an
 *    explicit `--model <twin>` was silently undone before the first turn;
 *  - turn_end marked the provider down BEFORE its hop landed, so a failed setModel
 *    latched the primary out of 2xx recovery for the rest of the process.
 */

import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { after, before, test } from "node:test";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import modelSwitch from "../model-switch.ts";

type MiniModel = { provider: string; id: string };
type Handler = (event: any, ctx: any) => Promise<unknown>;

const PRIMARY: MiniModel = { provider: "primary", id: "model-a" };
const TWIN: MiniModel = { provider: "twin", id: "model-a" }; // same id, different provider

// settingsPaths() reads the GLOBAL settings at os.homedir(), and this host's live
// settings.json is untracked — so point HOME at an empty temp tree for the suite.
const ROOT = mkdtempSync(join(tmpdir(), "model-switch-test-"));
const HOME = join(ROOT, "home");
let realHome: string | undefined;

before(() => {
  mkdirSync(join(HOME, ".pi", "agent"), { recursive: true }); // no settings.json on purpose
  realHome = process.env.HOME;
  process.env.HOME = HOME;
});

after(() => {
  if (realHome === undefined) delete process.env.HOME;
  else process.env.HOME = realHome;
  assert.notEqual(homedir(), HOME, "HOME restored");
});

/** Both maps populated, and a 1ms dwell so a test can drive both directions. */
function settings(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    rateLimitFallbacks: { "primary/model-a": "twin/model-a" },
    rateLimitFallbackStatuses: [429],
    rateLimitFallbackRecoveryCooldownSec: 0.001,
    providerFallbacks: { primary: { to: "twin", match: ["active OpenCode Go subscription"] } },
    ...extra,
  };
}

interface Opts {
  settings?: Record<string, unknown>;
  model?: MiniModel;
  /** Session branch as sessionManager.getBranch() reports it. */
  branch?: unknown[];
  /** One answer per pi.setModel call; missing → true. */
  setModelResults?: boolean[];
}

function harness(opts: Opts = {}) {
  const cwd = mkdtempSync(join(ROOT, "project-"));
  mkdirSync(join(cwd, ".pi"), { recursive: true });
  writeFileSync(join(cwd, ".pi", "settings.json"), JSON.stringify(opts.settings ?? {}));

  const available: MiniModel[] = [PRIMARY, TWIN];
  const ctx = {
    cwd,
    model: opts.model,
    modelRegistry: {
      getAvailable: () => available,
      find: (provider: string, id: string) =>
        available.find((m) => m.provider === provider && m.id === id),
    },
    ui: { notify: () => {} },
    sessionManager: { getBranch: () => opts.branch ?? [] },
  };

  const handlers = new Map<string, Handler[]>();
  const setModelCalls: string[] = [];
  const results = [...(opts.setModelResults ?? [])];
  const pi = {
    on(event: string, fn: Handler) {
      handlers.set(event, [...(handlers.get(event) ?? []), fn]);
    },
    registerCommand() {},
    registerTool() {},
    async setModel(m: MiniModel) {
      setModelCalls.push(`${m.provider}/${m.id}`);
      const ok = results.shift() ?? true;
      if (ok) ctx.model = m; // a successful switch is effective, as in pi
      return ok;
    },
  };
  modelSwitch(pi as unknown as ExtensionAPI);

  // Every handler for the event runs, in registration order: there are TWO
  // session_start handlers and the provider-fallback one must see the event first.
  const fire = async (event: string, payload: object) => {
    for (const fn of handlers.get(event) ?? []) await fn(payload, ctx);
  };
  return { fire, ctx, setModelCalls };
}

const MESSAGE = { type: "message" };
const change = (m: MiniModel) => ({ type: "model_change", provider: m.provider, modelId: m.id });

test("session_start leaves an explicit --model twin alone (the flag beat the transcript)", async () => {
  // `--model twin/model-a` on top of a session whose last model_change is the
  // primary: the branch disagrees with the effective model, so this is the user's
  // choice and the rate-limit recovery must not undo it.
  const h = harness({
    settings: settings(),
    model: TWIN,
    branch: [change(PRIMARY), MESSAGE],
  });
  await h.fire("session_start", { reason: "startup" });
  assert.deepEqual(h.setModelCalls, [], "no switch away from the flag's model");
});

test("session_start re-probes the primary for a twin restored from a hop", async () => {
  // The twin here is a hop's leftover: the branch's last model_change IS the
  // effective model. Recovery must still run, or a lapsed subscription would
  // never come back by itself.
  const h = harness({
    settings: settings(),
    model: TWIN,
    branch: [change(TWIN), MESSAGE],
  });
  await h.fire("session_start", { reason: "startup" });
  assert.deepEqual(h.setModelCalls, ["primary/model-a"]);
});

test("a failed provider hop does not latch the primary out of recovery", async () => {
  const h = harness({
    settings: settings(),
    model: PRIMARY,
    // 1st setModel = the provider hop, refused for lack of auth; 2nd = rate-limit hop.
    setModelResults: [false],
  });

  // The provider refuses before streaming: the error text fires the hop, but the
  // twin has no usable auth, so the session stays on the primary.
  await h.fire("turn_end", {
    message: { stopReason: "error", errorMessage: "An active OpenCode Go subscription is required" },
  });
  assert.deepEqual(h.setModelCalls, ["twin/model-a"], "the hop was attempted");

  // A 429 hop to the twin opens the 2xx recovery window (1ms here).
  await h.fire("after_provider_response", { status: 429, headers: {} });
  assert.deepEqual(h.ctx.model, TWIN, "now dwelling on the twin");

  // The twin answers: recovery to the primary must still be allowed — the failed
  // hop never happened, so it had no business marking the primary down.
  await new Promise((r) => setTimeout(r, 5));
  await h.fire("after_provider_response", { status: 200, headers: {} });
  assert.equal(h.setModelCalls.at(-1), "primary/model-a");
  assert.deepEqual(h.ctx.model, PRIMARY);
});
