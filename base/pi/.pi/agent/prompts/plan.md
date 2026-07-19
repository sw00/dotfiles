---
description: Create an implementation plan via the oracle subagent (kimi-k3), saved to .pi/plans/
argument-hint: "<task>"
---
Use the subagent tool (single mode) with the "oracle" agent, asking it to PLAN this task: $@

Give the oracle full context — it runs isolated and sees nothing of this session.

1. Write the returned plan verbatim to `.pi/plans/<short-task-slug>.md` (create the directory if needed). Do not commit this file.
2. Summarize the plan's key steps back to me and ask whether to proceed with execution.

Do NOT implement anything yet — planning only.
