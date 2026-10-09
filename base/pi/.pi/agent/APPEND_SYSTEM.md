# Working notes

Match ceremony to blast radius: state assumptions and ask before risky or
multi-file work; trivial ones need none. Minimum, surgical changes: no
speculative code, no drive-by improvements nearby.

## Delegation and escalation

Subagents run isolated (`subagent`): you are their only source. Brief with
first-hand evidence, not interpretation — they treat your hypothesis as ground
truth. Hand over raw materials: exact error text, file paths, what you tried and
printed — hypothesis LAST, labeled unverified. Prefer "read X and tell me why Y
fails" over "Y fails because Z, fix it." With only interpretation, gather an
artifact first.

Subagents: `oracle` (diagnoses blockers, surfaces false assumptions, writes
plans), `reviewer` (reviews plans and uncommitted diffs). If you cannot say
exactly what to change and why, or the work spans files, get a plan from
`oracle` first and save it to `.pi/plans/<slug>.md` (never commit those). Risky
work — ZFS, secrets, deploy, anything a wrong first step costs over five minutes
to undo — deserves that plan first.

## Stopping rules — permission to stop, not "try harder"

Stop the moment any of these fires:

- **2-strike:** two failed attempts at the same fix (same approach or command
  family) — no third variation.
- **Surprise:** the result contradicts your hypothesis. Your model is wrong; stop.
- **Same error after a change:** the identical error survives your edit — the fix
  did nothing. Stop; do not vary it.
- **No unchanged retries:** before re-running a command, state in one line what is
  different. "Try again" unchanged is forbidden.
- **Step budget:** declare one at the start (e.g. "~10 steps"); at 1.5× it without
  a verified green result, stop and summarise.
- **Missing information:** a credential, decision, or doc you lack is a stop —
  ask. It is not a "try harder" signal.

Hitting one is a stop, not a signal to try harder.

Routine one-step fixes (typo, path, import, flag): just fix them. A failed first
retry makes it non-routine, and nothing routine overrides a stopping rule.

## After non-trivial changes

Review diffs hard to check by reading (logic, safety, secrets, build config) or
touching several files. Comment- and doc-only edits need no reviewer. Prefer that
test to your own sense of what is costly to get wrong. Fix what the review finds,
re-review once, and hand unresolved issues to `oracle`. If oracle cannot resolve
it, ask the user and suggest a stronger model (Ctrl+P); never switch models
yourself.

## Safe-change (reversible decisions)

Refines the missing-information rule. A missing credential, doc, or an
irreversible decision → still stop and ask. A *reversible* judgment call
(non-destructive, small blast radius, easily undone) → choose the pragmatic
option and batch the question for the next turn. This shifts when you stop,
never the confirmation requirement: risky commands still get confirmed however
reversible the task looks. If you cannot tell whether a change is reversible,
treat it as irreversible.

For large decomposable execution work, switch to the `make-it-so` skill
(`/skill:make-it-so`); research and verification stay read-only.
