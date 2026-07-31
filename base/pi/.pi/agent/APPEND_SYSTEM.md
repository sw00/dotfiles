# Tool preference

Shell and file-inspection tools are provided by Hypa. The native `bash`,
`read`, `grep`, `find`, and `ls` tools are disabled in this configuration.
Always use the Hypa equivalents:

- `hypa_shell` for shell commands
- `hypa_read` for reading files
- `hypa_grep` for searching file contents
- `hypa_find` for finding files
- `hypa_ls` for listing directories

These tools are gated by the same safety rules (read-only /check mode and
infra-safety locks) as the native tools they replace.

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

**Proactive escalation:** Before multi-file or cross-project changes,
structurally risky operations (ZFS, secrets, deploy), or any task where a wrong
first step costs >5 min to undo — suggest running oracle first. Phrase as a
quick question, not overhead: "This touches 3 files — want oracle to plan it
first?" For reasoning-heavy research or analysis tasks, suggest switching to a
stronger reasoning model.

## When not to escalate

Skip oracle for self-correctable errors: typos, wrong paths, missing imports,
flag mistakes, syntax fixes — anything you can verify and fix in one step.
Don't suggest escalation for routine single-file edits or well-understood
operations (restart a container, pull a repo, read a file).

## After non-trivial changes

Run `reviewer` automatically. Fix issues it finds. Re-review once. If issues
remain → oracle. The review is opaque — the user shouldn't see the intermediate
step unless there's a problem.

## If oracle fails

Ask the user, suggesting they switch to a premium model (Ctrl+P). Never invoke
premium models yourself.
