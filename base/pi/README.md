# pi coding agent config

Minimal model roster for the [pi](https://pi.dev) coding agent: each model
has a distinct role; escalation is driven by uncertainty, not failure counters.
Three explicit modes shape each session. Stows to `~/.pi/`.

## Models

| Model | Role | Rationale |
|------|-------|-----------|
| `opencode-go/deepseek-v4-pro` | Worker (default) | Best price/performance; strong meta-cognition for self-escalation |
| `opencode-go/glm-5.2` | Oracle | Low hallucination rate (~28%); strong at long-horizon diagnosis |
| `anthropic/claude-haiku-4-5` | Reviewer | Outperforms larger models on code review (academic eval); also falls back for web summaries |
| `opencode-go/deepseek-v4-flash` | Web summaries (preferred) | Cheapest, fastest; summaries are low-stakes |
| `opencode-go/kimi-k2.6` | Chat mode | Fast and cheap for conceptual discussion; K3 is overkill (slow, expensive, locked to max reasoning) |
| `anthropic/claude-opus-4-8` | Manual premium | Premium last resort; never invoked by agents — Ctrl+P only |

All models except Opus are subscription-included. Web summarisation falls
through Flash → Haiku → deterministic if the preferred model is unavailable.

## Escalation

Defined in `agent/APPEND_SYSTEM.md` (always in the system prompt — keep lean).
Principle-driven: escalate on **uncertainty**, not failure count. No rigid
file-count thresholds. Explicit skip-list for self-correctable errors (typos,
wrong paths, missing imports).

```
Worker (Pro)
  ├─ uncertain about root cause / surprised by result → oracle: diagnose
  ├─ need plan before multi-file work                 → oracle: plan → .pi/plans/<slug>.md
  ├─ oracle failed                                    → ask user (Ctrl+P to Opus)
  └─ after non-trivial change                         → reviewer → fix → re-review once → oracle if stuck
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
| `chat` | unrestricted | kimi-k2.6 | conceptual altitude; no changes unless asked |

Toolset is a pure function of the mode (stateless — no snapshot/restore).
In check mode, domain mode tools (e.g. `infra_mode`) are also removed since
every guard is force-locked and cannot be opened from within check.
Entering `/chat` switches to kimi-k2.6 and restores the prior model on exit,
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

Known false positive: the scanner (`findInvocations`) is quote-unaware, so CLI
names inside a `git commit -m "…"` message are parsed as invocations and
blocked while locked — commit via `git commit -F <file>` instead. (Stripping
quoted strings in `normalizeCommand` would be the real fix.)

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
    ├── agents/                  oracle, reviewer
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

## Shared core vs. profile

Everything under `agent/` except `settings.json` is the **shared core**:
generic, host-agnostic, no knowledge of any particular deployment (no Telegram
bridge, no appliance defaults). The laptop profile is the `settings.json` in
this repo. Other deployments (e.g. an always-on agentbox) own their own
`settings.json` and any host-specific overlay extensions **in their host
repos** — they are NOT tracked here, and the shared core must stay free of
references to them (no `[telegram]`, no `agentbox`, no appliance model
defaults). `check.sh` enforces this.

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
