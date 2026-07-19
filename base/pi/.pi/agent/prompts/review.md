---
description: Review uncommitted changes via reviewer subagent (sonnet), fix issues, re-review once
argument-hint: "[goal or plan reference]"
---
Use the subagent tool (single mode) with the "reviewer" agent.

Goal for the review: ${@:-the task as discussed in this session}

If a relevant plan file exists in `.pi/plans/`, include its contents so the reviewer can check plan adherence.

When it returns:
- Verdict PASS: report and stop.
- Verdict ISSUES: fix the issues, then run the reviewer once more. If issues persist after this second round, escalate with the "consult" agent rather than asking me immediately.
