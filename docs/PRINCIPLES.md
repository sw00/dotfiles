# PRINCIPLES.md — how changes are made here

Read this before your first change. It is not taste: every rule below exists
because breaking it caused a real incident, and each names the mechanism that
holds it. `AGENTS.md` says what the system should be; this file says how to
change it without lying to the next session. `docs/GOTCHAS.md` holds the
incidents — read it when you touch the area it covers, not as background.

If a rule and the tree disagree, one of them is a bug. Fix whichever is wrong
in the same change, and say which in the commit.

## The rules

1. **Measure before you claim, and date the measurement.** `# Measured
   2026-11-05: upstream titles itself 'π - …', bolt 'Pi-Bolt - …'`. What you did
   not measure is labelled `UNVERIFIED`, with what would settle it. No
   plausible-sounding assertion, no stale header number, no conclusion from an
   underpowered sample.

2. **Red first, and add a control.** A new check must fail on the unfixed code.
   If it is a predicate test, add a second check that still passes unfixed —
   otherwise "accepts everything" satisfies it. Only a full `bash check.sh` run
   is a gate; a filtered or extracted run is a debugging aid.

3. **Fail loudly; never degrade silently.** Refuse and name the way out
   (`pwt rm` names `--stash`). Skip visibly with the reason. Error on a wrong
   environment. A silent no-op is the worst outcome, above all in a hook.

4. **Read recorded facts, not observed state.** Allowlists, not blocklists
   (`__pwt_is_shell`). Never infer identity from a signal something else can
   spoof — pane titles, `pane_current_command`, `#{window_active}`. Prefer the
   file that records the fact (`@pwt_sid`, `session_path`).

5. **Nothing irreversible without a recovery path.** Move, don't delete. Stash
   before remove. Keep what exists nowhere else. Never `--zap` in a migration,
   and never revert a deliberate human act (`packages` stay live-wins; secrets
   are never `git checkout`ed without asking).

6. **One owner per fact, action and tool.** One `respawn-pane`, one place
   pinning a session id, one doc owning each fact, one package manager per tool.
   When a fact must exist in several languages, duplicate it as a byte-identical
   marker line and assert the copies agree — do not build indirection to avoid
   the duplication.

7. **Put the why at the line it constrains.** The mechanism, the cost, and the
   alternative you rejected — not what the code does. CAPS the load-bearing word
   (`REPLACES`, `NEVER`, `LAST`). Contract docs keep an "If you change this"
   list where each invariant says why, not just what.

8. **Pin what must not drift.** A removal gets a tombstone (`check_not` on the
   invocation line — prose mentioning the thing must not trip it). "Exactly one"
   gets a count assertion. A copy across a language boundary gets a parity check.

9. **Intent and live state are different files.** Templates are tracked; what a
   running app or session writes is host-local and never committed. Run
   `git status` after anything touches stowed config.

10. **Test in a sandbox that cannot reach the live session.** Private tmux
    sockets, stub binaries, `<TOOL>_<THING>` seams that *replace* the shipped
    default. If you override `HOME`, re-resolve your tools first — mise treats a
    sandbox as untrusted and will exit or, worse, install into it.

11. **Every deferral carries a trigger.** `Next action:` for work; for a
    non-goal, what would change the decision. "Not built, on purpose" with the
    reason beats an unexplained gap. Record at the lowest capture tier that
    fits — and never point a committed file at `.pi/plans/`, which exists on one
    host.

12. **Always-on text is budgeted.** `APPEND_SYSTEM.md` 500 words, global
    `AGENTS.md` 185, this repo's `AGENTS.md` 1200. A bump names the incident
    that justified it, in the commit message. A prompt edit owes a `pi-smoke`
    A/B, read as per-run distributions, never means.

13. **Close the loop before committing.** Reviewer on multi-file behaviour
    diffs. Re-read every doc that states the fact you changed, last. Then the
    commit says: outcome → measured cause → fix → what you deliberately did not
    change → the suite count.

## Change anatomy

A change ships as code + guard + docs + commit message, together. The comment
carries the reasoning at the line; the commit body carries the story: symptom,
measured root cause, fix, deliberate non-changes, verification numbers. A fix
whose rationale lives only in the commit is half-shipped.

## What counts as a defect

- A test that can pass for the wrong reason: reads its own fixture, has no
  control, or its seam extends the real set instead of replacing it.
- An unmeasured or stale claim — including a doc header the tree contradicts.
- Silent degradation, or a skip reported as green.
- Drift: tracking runtime state, a stowed file that is not live, a new file in a
  stowed package that an app rewrites, an own-file missing from an allowlist.
- Speculative surface: code for a case nobody has; an abstraction whose drift
  the suite already catches.
- Undeclared ownership: a tool installed by two managers, a fact with two homes.
- Ceremony instead of a guard: prose saying "don't" where a tombstone would hold.
