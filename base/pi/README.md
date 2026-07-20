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
to cycle). These are the only slash commands; `/plan` and `/review` were removed
as redundant (the escalation ladder handles oracle/reviewer autonomously in
`/change` mode). Mode persists across session resume; a per-mode reminder is
injected each turn and filtered when stale.

| Mode | Tools | Model | Intent |
|------|-------|-------|--------|
| `change` (default) | full | worker | autonomous execution; ladder active |
| `check` | read-only (edit/write off, domain mode tools hidden, bash allowlisted) | worker | pair-troubleshooting; **user** is the escalation target, no delegation |
| `chat` | unrestricted | kimi-k3 | conceptual altitude; no changes unless asked |

Toolset is a pure function of the mode (stateless — no snapshot/restore).
In check mode, domain mode tools (e.g. `infra_mode`) are also removed since
every guard is force-locked and cannot be opened from within check.
Entering `/chat` switches to kimi-k3 and restores the prior model on exit,
unless the user manually switched during chat.

### infra-safety integration

`infra-safety.ts` gates live-infra CLIs (aws/az/gcloud/kubectl/terraform) with
its own independent locked/armed write-gate state, built on `lib/mutation-guard.ts`. The
modes extension **tightens, never loosens**: `/check` forces every registered
domain guard to locked; `/change` does *not* open the infra write gate — that
still needs `/infra-arm` + confirmation (two-key safety). In `/check`,
commands touching a guarded CLI are classified by the guard's own verb tables
(single source of truth), so `aws … describe` runs while `terminate` is blocked.
New domains: `import { createMutationGuard }` with your own verb tables and a
distinct `domain` string; they auto-register into the modes integration.

### Subagent safety (defense-in-depth)

Subagent processes spawned by pi (`oracle`, `reviewer`, etc.) load infra-safety
independently, default to locked, and run with `hasUI=false` — so live-infra
mutations are physically blocked even when the agent prompt says "read-only
inspection." General bash (test runners, builds) stays unguarded because oracle
needs these for diagnosis; the read-only constraint for non-infra commands
relies on the agent prompt, not a tool gate.

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
    ├── settings.json            LAPTOP profile: provider, default model, cycle set
    ├── AGENTS.md                global rules (web search hygiene)
    ├── APPEND_SYSTEM.md         escalation ladder (always-on; keep lean)
    ├── agents/                  oracle, oracle-pro, reviewer
    └── extensions/
        ├── subagent/            vendored delegation tool
        ├── modes/               /chat /check /change
        ├── model-switch.ts      /use /cycle /models + rate-limit auto-fallback
        ├── infra-safety.ts      infra CLI mutation guard (wires infra-tables)
        └── lib/
            ├── mutation-guard.*  shared locked/armed engine (+ node --test)
            ├── classify.ts       pure verb parsing/classification (pi-free)
            └── infra-tables.ts   aws/az/gcloud/kubectl/terraform verb tables
                                  (pi-free; shared by infra-safety + tests)
```

## Profiles: laptop vs. agentbox

Everything under `agent/` except `settings.json` is the **shared core**, used
identically on the laptop (stowed) and on the always-on Telegram agentbox
(CT 105 in `sw00/homelab`, where the role **copies** the core into `~/.pi/agent/`).
`settings.json` is **per-profile** — two hand-maintained files:

| | Laptop (this file) | Agentbox (`homelab:ansible/roles/agentbox/files/pi-settings.json`) |
|---|---|---|
| default model | `opencode-go/deepseek-v4-flash` (attended) | `opencode-go/kimi-k3` (unattended) |
| `packages` | no telegram | + `pi-telegram` |
| `rateLimitFallbacks` | — (attended; manual switch) | OpenRouter twins (auto-fallback) |

Keep the `enabledModels` roster and shared `packages` in sync between the two by
hand (JSON can't carry a note). The agentbox profile is owned by the homelab
repo, not here.

## model-switch

`agent/extensions/model-switch.ts` — `/use <q>` (fuzzy-switch any authed model),
`/cycle` (rotate the **cycle set** = `enabledModels`), `/models` (show active +
cycle set + fallback map). On HTTP 429/529 it consults the **fallback map**
(`rateLimitFallbacks`, primary → OpenRouter twin) and hops to the twin if authed;
absent map (laptop) → no-op. Fallbacks are **sticky** (pi persists `defaultModel`),
so it switches back to the primary on `session_start`. OpenRouter mirrors live
**only** in `rateLimitFallbacks`, never in `enabledModels`.

## Tests

```bash
cd base/pi/.pi/agent/extensions
node --experimental-strip-types --test lib/mutation-guard.test.ts
pi -p --no-session "Reply OK"   # smoke: extensions parse and load
```
