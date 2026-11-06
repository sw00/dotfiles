---
name: make-it-so
description: 'Orchestrator-worker flow for large, multi-step EXECUTION tasks that require making changes across many files with heavy tool-calling. Use when a task is genuinely complex and decomposable — NOT for research or verification (those stay read-only). Force with "make it so: <task>" or /skill:make-it-so.'
disable-model-invocation: false
---

# make-it-so — orchestrator-worker execution

You are switching from single-agent execution to orchestrator-worker mode for a
large, decomposable EXECUTION task. The bulk work is done by cheap `worker`
subagents; you (the orchestrator) plan, partition, dispatch, aggregate, and
review. Do NOT do the bulk execution yourself.

## Step 0 — Scope gate (do this first)
Estimate the task. If it is NOT genuinely complex — ≤ ~8 steps, single-file, or
read-only (research/verification) — abandon this skill and handle it inline with
normal flow. Over-orchestrating a small task is a failure mode. Only proceed if
the task is large, multi-step, multi-file, and execution-shaped (makes changes).

**Re-run this gate whenever the brief changes.** Expansion is the normal way an
orchestrated task goes wrong: "also fix X", "complete everything", or a phase that
turns out to need a verification loop. Before opening one, re-quote the original goal
and multiply the per-run cost by the run count — a 17-second suite run 150 times is
most of an hour. If the brief has outgrown the estimate, say so and re-scope rather
than absorbing it.

## Step 1 — Plan
Write `.pi/plans/<slug>.md`:
- Goal (one sentence).
- Sub-tasks, each small and independently verifiable.
- A FILE-OWNERSHIP MAP: which sub-task owns which files. Workers must NOT edit
  overlapping files. If two sub-tasks must touch the same file, SEQUENCE them
  (chain), don't parallelise.
- Parallel vs sequential ordering.
- Per-sub-task verification.
- An **ANSWERS LEDGER**: every decision an oracle, reviewer or worker gives you, and
  the exact question that produced it. A later brief quotes the ledger instead of
  re-asking. Re-asking what an earlier answer already settled is the most common way
  consultation cost doubles in a long session.

If planning is uncertain → escalate to `oracle` (PLAN mode) for the plan.

## Step 2 — Partition check
Before dispatch, confirm no two parallel workers share a file. Re-route any
overlap into a sequential (chain) step.

## Step 3 — Dispatch
Spawn `worker` subagents via the `subagent` tool:
- `parallel` mode for independent sub-tasks (disjoint files).
- `chain` mode for dependent sub-tasks (each gets the previous result).

Each brief MUST be complete (workers see nothing of your session): the plan
path, the sub-task, exact files/paths/functions, constraints, and the
verification to run + what to return.

## Step 4 — Aggregate
Reconcile results. Handle conflicts and failures. A worker that returned a
blocker → escalate that blocker to `oracle` (do not blindly re-spawn;
tripwires apply).

## Step 5 — Review
Run `reviewer` on the full diff. Fix issues. Re-review once.

## Step 6 — Deliver
Consolidated summary: what changed, verification status, any open blockers.

## Invariants
- Tripwires (2-strike, no-unchanged-retries, step budget) apply to you AND
  workers; entering this mode does not suspend them.
- Research/verification sub-tasks stay read-only — do NOT spawn write-workers
  for "look into X"; use web_search/fetch/read inline or a read-only flow.
- The expensive model is bounded to your planning/aggregation turns; the bulk
  token volume runs in cheap workers. That's the point — don't do the bulk
  yourself.
- **Two loops then dispatch.** If you have run two verification loops (a mutation
  sweep, a mutant-by-mutant proof, a batch of suite runs) yourself, stop and
  dispatch the rest to workers. The rule above is easy to agree with and easy to
  erode one "this one is quick" at a time; the count is the tripwire.
- Safe-change applies at the orchestrator→user boundary: a worker blocker that is
  a *reversible* decision → decide and batch the question for the user, don't
  reflexively escalate to `oracle`; irreversible/credential/doc blockers stop.
  Workers report blockers up rather than making unbriefed changes.
