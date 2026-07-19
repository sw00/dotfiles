# pi coding agent config

Flash-first workflow for the [pi](https://pi.dev) coding agent: a cheap fast
model does most of the work and escalates to stronger models only when it gets
stuck. Three explicit modes shape each session. Stows to `~/.pi/`.

## Models per role

| Role | Model | Cost | Where |
|------|-------|------|-------|
| Worker (main session) | `opencode-go/deepseek-v4-flash` | subscription | `settings.json` default |
| `oracle` (diagnose/plan) | `opencode-go/kimi-k3` | subscription | `agent/agents/oracle.md` |
| `oracle-pro` (2nd rung) | `opencode-go/deepseek-v4-pro` | subscription | `agent/agents/oracle-pro.md` |
| `reviewer` (diff review) | `anthropic/claude-haiku-4-5` | subscription | `agent/agents/reviewer.md` |
| Premium escape hatch | `anthropic/claude-opus-4-8` | metered | manual Ctrl+P only |

Rationale: small models handle ~80% of execution; escalation rungs are all
free (subscription) so the agent climbs them without a cost conversation.
`oracle` (Moonshot) is a different family from the DeepSeek worker for review
diversity; `reviewer` stays on Anthropic for the same reason. Opus is metered,
so the agent never invokes it — the user switches to it deliberately.

## Escalation ladder

Defined in `agent/APPEND_SYSTEM.md` (always in the system prompt — keep lean):

```
Flash worker
  ├─ stuck (error twice / root cause unclear) → oracle: diagnose
  ├─ task >3 files / architectural           → oracle: plan → .pi/plans/<slug>.md
  ├─ oracle failed                           → oracle-pro (auto, free)
  ├─ both failed                             → ask user (suggest Ctrl+P to Opus)
  └─ after non-trivial change                → reviewer → fix → re-review once
```

Subagents run in isolated pi subprocesses (vendored `agent/extensions/subagent/`,
from pi examples — re-vendor on pi upgrades if the extension API changes).

## Modes

`agent/extensions/modes/index.ts` — `/chat`, `/check`, `/change` (or Ctrl+Alt+M
to cycle). Mode persists across session resume; a per-mode reminder is injected
each turn and filtered when stale.

| Mode | Tools | Model | Intent |
|------|-------|-------|--------|
| `change` (default) | full | worker | autonomous execution; ladder active |
| `check` | read-only (edit/write off, bash allowlisted) | worker | pair-troubleshooting; **user** is the escalation target, no delegation |
| `chat` | unrestricted | kimi-k3 | conceptual altitude; no changes unless asked |

Toolset is a pure function of the mode (stateless — no snapshot/restore).
Entering `/chat` switches to kimi-k3 and restores the prior model on exit,
unless the user manually switched during chat.

### infra-safety integration

`infra-safety.ts` gates live-infra CLIs (aws/az/gcloud/kubectl/terraform) with
its own independent check/change state, built on `lib/mutation-guard.ts`. The
modes extension **tightens, never loosens**: `/check` forces every registered
domain guard to check; `/change` does *not* open the infra write gate — that
still needs `/infra-change` + confirmation (two-key safety). In `/check`,
commands touching a guarded CLI are classified by the guard's own verb tables
(single source of truth), so `aws … describe` runs while `terminate` is blocked.
New domains: `import { createMutationGuard }` with your own verb tables and a
distinct `domain` string; they auto-register into the modes integration.

## Web search

Exa zero-config MCP (no API key). Config at `~/.pi/web-search.json`
(`base/pi/.pi/web-search.json`) — provider `exa`, `auto-summary` workflow (no
browser curator), summaries drafted by Flash. Query-hygiene rule in
`agent/AGENTS.md`.

## File map

```
.pi/
├── web-search.json              → ~/.pi/web-search.json (pi-web-access config)
└── agent/                       → ~/.pi/agent/
    ├── settings.json            provider, default model, enabled model cycle
    ├── AGENTS.md                global rules (web search hygiene)
    ├── APPEND_SYSTEM.md         escalation ladder (always-on; keep lean)
    ├── agents/                  oracle, oracle-pro, reviewer
    ├── prompts/                 /plan, /review
    └── extensions/
        ├── subagent/            vendored delegation tool
        ├── modes/               /chat /check /change
        ├── infra-safety.ts      infra CLI mutation guard
        └── lib/mutation-guard.* shared check/change engine (+ node --test)
```

## Tests

```bash
cd base/pi/.pi/agent/extensions
node --experimental-strip-types --test lib/mutation-guard.test.ts
pi -p --no-session "Reply OK"   # smoke: extensions parse and load
```
