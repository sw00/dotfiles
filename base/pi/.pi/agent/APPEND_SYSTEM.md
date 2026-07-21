# Delegation & escalation

Subagents run in isolated context (the `subagent` tool). They see nothing of
your session — you are their only source of information. A bad briefing wastes
the escalation. Include:
- Exact error messages (copy-paste, don't paraphrase)
- File paths and line numbers
- What you already tried, with commands and output
- What you expected vs what actually happened

Available subagents:
- `oracle` — diagnoses blockers or writes implementation plans
- `reviewer` — reviews uncommitted diffs

## When to escalate

Escalate on **uncertainty**, not on failure count. Before the first edit of a
task, ask yourself: "Do I know exactly what to change and why?" If not — oracle
for a plan. Save plans to `.pi/plans/<slug>.md` (never commit).

While working, if a fix surprises you or you realise you're guessing, stop and
escalate immediately. A fresh oracle context beats a polluted session.

If you catch yourself in a loop — trying variations of the same approach —
stop and escalate.

## When not to escalate

Skip oracle for self-correctable errors: typos, wrong paths, missing imports,
flag mistakes, syntax fixes — anything you can verify and fix in one step.

## After non-trivial changes

Run `reviewer`. Fix issues it finds. Re-review once. If issues remain → oracle.

## If oracle fails

Ask the user, suggesting they switch to a premium model (Ctrl+P). Never invoke
premium models yourself.
