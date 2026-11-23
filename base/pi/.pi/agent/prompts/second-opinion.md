---
description: Get oracle's verdict on the current plan, diff or claim, then reconcile it before acting
argument-hint: "[subject] [then action]"
---
Get a second opinion from `oracle`.

Subject: ${@:-the most recent plan, diff, claim or decision in this session}

State the subject back in one line before dispatching, so a wrong guess costs one
line instead of a round trip.

**Brief it the way `APPEND_SYSTEM.md` requires:** raw artifacts only — file paths,
the exact command and its output, the numbers. Your own hypothesis goes last and
labelled unverified. Never send a summary where the artifact fits, and never send
the transcript.

**Ask for:** a verdict (holds / does not hold), the load-bearing assumption it rests
on, the cheapest check that would falsify it, what it would cut, and what it would
do instead ranked by impact over effort. Ask it to say plainly what it has not
verified.

**On return:** check its factual claims against the artifacts before adopting any of
them — it is read-only and cannot have run what you ran. Then report agreement and
disagreement with reasons, in your own words, and say what you change as a result.
Never relay its answer as your own conclusion. A claim you cannot check is reported
as unverified, and you act on the rest.

**If the subject names a follow-up action** (`then apply`, `then merge`, `then
retry`, `then implement`): do it only once it agrees. On disagreement, stop and show
both positions — do not split the difference silently.

Wanting a *different model family* (`claude`, `opus`), or a review of a code diff
rather than a plan? That is `/paseo-advisor` or the `reviewer` agent — this template
is same-family rigor on the current work.
