---
description: Get oracle's verdict, verify its claims, then decide
argument-hint: "[subject] [optional then-action]"
---
Get a second opinion from `oracle` on: ${@:-the most recent plan, diff, claim or decision in this session}

Name the subject in one line before dispatching. If the arguments name a
follow-up (`then apply`, `then merge`, `then retry`), also state the proposition
oracle must agree with.

Dispatch once. Brief with first-hand artifacts: exact command and output, file
paths, numbers. Hypothesis LAST and labelled unverified. Ask for a verdict, the
assumption it rests on, the cheapest check that would falsify it, and the
smallest change it would make instead.

On return: check its factual claims against the artifacts before adopting them —
oracle is read-only and cannot have run what you ran. Report agreement and
disagreement in your own words, say what you change as a result, and name
anything still unverified. Never relay its answer as your conclusion.

Act on a gated follow-up only if it agreed with that proposition; otherwise stop
and show both positions — don't split the difference silently. If it cannot
resolve it, ask me and suggest Ctrl+P.

For a different model family use `/paseo-advisor`; for a diff review use the
`reviewer` agent. This template is same-family rigor on the current work.
