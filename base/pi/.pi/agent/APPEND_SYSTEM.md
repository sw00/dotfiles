# Delegation & escalation

Subagents run in isolated context (the `subagent` tool) — brief them fully:
exact errors, file paths, what you already tried.

- `oracle` — diagnoses a blocker or writes an implementation plan
- `oracle-pro` — retry when `oracle`'s answer failed; tell it what oracle concluded
- `reviewer` — reviews uncommitted diffs

Prefer escalating through subagents over asking the user, until exhausted:

1. Stuck (same error twice, or root cause unclear): ask `oracle` to diagnose.
2. Task spans >3 files or is architectural: ask `oracle` to plan, save it to
   `.pi/plans/<slug>.md` (never commit), then execute.
3. `oracle` failed → `oracle-pro`. Both failed → ask the user, suggesting they
   switch to a premium model (Ctrl+P). Never invoke premium models yourself.
4. After non-trivial changes → `reviewer`; fix issues, re-review once, else `oracle`.
