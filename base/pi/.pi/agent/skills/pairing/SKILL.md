---
name: pairing
description: 'Pairing flow for MEDIUM-complexity tasks that mix discovery and implementation: a read-only `navigator` subagent scouts the sites of change and sets design direction, a `driver` subagent implements one small verified step at a time, and you relay between them and own the state. Use when you must explore before you can implement, and the work is a handful of steps rather than many files — too big to wing, too small for make-it-so. Force with "pair: <task>" or /skill:pairing.'
disable-model-invocation: false
---

# pairing — navigator + driver

You are the channel of a pairing session, not its typist. `navigator`
(read-only, GLM-5.3-Flash) scouts ahead and around the sites of change and decides the
direction; `driver` (DeepSeek V4.1 Flash) implements one small step and proves it.
Neither sees the other or the user: every fact that crosses between them crosses
your turn, verbatim. You hold the state, run the final verification, and talk to
the user.

## Step 0 — Scope gate
Pairing fits a task with a genuine unknown and roughly 3–15 steps: you cannot yet
name the files, the design, or the constraint that decides it. Abandon this skill
and work inline when you can already see the change (1–2 steps, one file) — a
subagent round-trip costs more than the edit. Hand off to `make-it-so` when the
work is mechanical, multi-file, or big enough to partition.

**Re-run this gate whenever the brief grows.** A "while you're in there" that
adds a second unknown turns one session into two, and each dispatches three models.

## Step 1 — Frame
Write down, in one line each: the goal; the definition of done as something
checkable (a command, a behaviour, a test); what is unknown; and a step budget.
If the ask hides a decision that is the user's (destroys data, changes a public
interface, costs money), ask now, once, before spending dispatches on it.

## Step 2 — Navigate
Dispatch `navigator` (single mode) with the goal, the definition of done, and the
raw materials you have: paths, exact error text, commands you ran and what they
printed. Give it the *intent* too — what the user actually wants and the repo rules
that govern the area (AGENTS.md principles, the layer that owns it) — because
congruency is judged against the ideal, and it cannot judge an ideal it was not
told. Your own hypothesis goes last, labelled unverified — a navigator handed a
conclusion checks it instead of the code.

Parallel navigators (2, no more) are allowed only when the unknowns are genuinely
separate — "how is this wired" versus "what does the suite need" — so no write
conflict is possible. Reconcile them yourself into one direction, preferring the
one backed by evidence.

**`SPLIT`** → the next step cannot be verified in one pass. Re-run the Step 0 scope
gate on one half and dispatch the first of the two steps it proposed. If both halves
are large, that is `make-it-so`, not a longer pairing session.

## Step 3 — Confirm the direction
The design direction is often a real decision: user-visible behaviour, an
irreversible edit, a new dependency, a preference the repo does not settle. That
one gets a short question to the user before any edit. A reversible, in-idiom
direction → proceed (the safe-change rule) and batch the question for the next turn.

## Step 4 — Drive
Dispatch `driver` with ONE step. The brief must be complete: the step, the files
and functions, the constraint it must respect, the verification command with the
expected result, and what to report. Give the step and its traps — never the whole
navigator report, and never two steps because they look quick. State the bias
explicitly: minimum viable change, and a decision past the step's edge comes back
up — inside that edge the driver decides and reports it under `Decided`.

**No driver step without a check that settles it.** If you cannot name the command
that proves the step, you do not yet have a step; go back to Step 2.

Doing one step inline when it is a single edit you could write in a sentence is
fine and cheaper. Doing the whole task inline means you wanted normal flow, not
pairing.

## Step 5 — Relay
Read the driver's report, then run the protocol:

- **Green, direction intact** → next step, or Step 6 when the definition of done
  is met.
- **Surprise, failed check, or a trap fired** → back to Step 2 with the evidence
  verbatim: the error text, the diff, the command output. That is what the
  navigator needs; your paraphrase is bias.
- **`Decided` lines** → review each one. A call that stayed inside the step's edge
  stands; one that crossed it gets reversed or escalated before the next dispatch.
- **Blocker that is the user's decision** → ask. A reversible one → decide, and
  tell the user what you decided.

Never re-dispatch the same step unchanged: quote what is different, or escalate to
`oracle`. Two failed attempts at one step is a stop, not a third variation — the
navigator's model of the code is wrong, and a better brief for the same wrong
model will not fix it.

## Step 6 — Verify and deliver
Run the checks yourself and read the diff yourself. You are the pair's memory and
its only claim to accuracy: the subagents forget everything when they return, so
"the driver said it passed" is not verification.

Then: a non-trivial diff (logic, safety, secrets, build config, several files) gets
`reviewer`; fix what it finds, re-review once. Doc- and comment-only edits need
neither. Summarise what changed, what proved it, what is still open, and where the
task was written down (`TODO.md`, or `.pi/plans/<slug>.md` if it is still moving).

## Invariants
- **Design congruency is a gate, not a nicety.** A step that passes its check while
  adding a second way to do what the repo already does is a defect you shipped green.
  When the navigator's congruency section and its next step disagree, the step is
  wrong: send it back, or accept the compromise out loud and record the payoff trigger.
- **Answers ledger.** Keep every navigator direction and the question that produced
  it. Quote the ledger instead of re-asking; re-asking what a previous answer
  settled is how a pairing session doubles its cost without changing its result.
- **Asymmetric briefs.** navigator → driver carries a *step*. driver → navigator
  carries *evidence*. Mixing the two is the failure that makes pairing slower than
  working alone: a driver briefed with a research dump stalls, a navigator briefed
  with your summary of the failure plans against your bias.
- **Tripwires bind all three of you.** 2-strike, surprise, same-error-after-a-change,
  no unchanged retries, step budget, missing information. A blocker that arrived
  intact is a good outcome; a loop is not.
- **You may skip the ceremony, not the evidence.** Front-load a single dispatch when
  the design is already settled — but spend it where it buys something (a navigator
  on the constraint, or `reviewer` on the diff), never to have your own conclusion
  blessed.
- **Cost is per step, not per edit.** One step = one coherent, verifiable change.
  Batched too fine, you pay two dispatches per line; too coarse, a failed check
  throws away work no one can attribute.
