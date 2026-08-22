---
name: make-it-so
description: Orchestrator-worker flow for large, multi-step EXECUTION tasks that require making changes across many files with heavy tool-calling. Use when a task is genuinely complex and decomposable — NOT for research or verification (those stay read-only). Force with "make it so: <task>" or /skill:make-it-so.
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

## Step 1 — Plan
Write `.pi/plans/<slug>.md`:
- Goal (one sentence).
- Sub-tasks, each small and independently verifiable.
- A FILE-OWNERSHIP MAP: which sub-task owns which files. Workers must NOT edit
  overlapping files. If two sub-tasks must touch the same file, SEQUENCE them
  (chain), don't parallelise.
- Parallel vs sequential ordering.
- Per-sub-task verification.

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
  workers. ELEVATE does not suspend them.
- Research/verification sub-tasks stay read-only — do NOT spawn write-workers
  for "look into X"; use web_search/fetch/read inline or a read-only flow.
- The expensive model is bounded to your planning/aggregation turns; the bulk
  token volume runs in cheap workers. That's the point — don't do the bulk
  yourself.
