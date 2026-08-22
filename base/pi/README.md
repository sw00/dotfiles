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

**Brave Search** via `pi-web-access`. Config at `~/.pi/web-search.json`
(`base/pi/.pi/web-search.json`) — provider `brave`, `auto-summary` workflow (no
browser curator), summaries drafted by Flash. Key resolved from
`BRAVE_SEARCH_API_KEY` (or `BRAVE_API_KEY`). Brave is SOC 2 Type II attested
with explicit Zero Data Retention — stronger posture than the prior Exa
integration. Query-hygiene rule in `agent/AGENTS.md`.

## ZDR posture

| Provider | Model(s) | Training? | Retention |
|---|---|---|---|
| Brave Search API | — | No | Zero (SOC 2 Type II) |
| OpenCode Go (Zen) | `deepseek-v4-pro`, `deepseek-v4-flash`, `glm-5.2`, `kimi-k2.6` | No | Zero (paid tier) |
| Anthropic (Console) | `claude-haiku-4-5`, `claude-opus-4-8` | No | Zero (API/Pro) |
| OpenRouter | varies by upstream | Configurable | Depends on upstream |

**Caveat:** OpenCode Go's **free** tier models (suffixed `-free`, e.g.
`deepseek-v4-flash-free`) explicitly permit training. The summary model here
is the paid `deepseek-v4-flash` (no suffix) — safe. `check.sh` enforces that
`summaryModel` and all model entries in `settings.json` are free of `-free`
variants.

**OpenRouter:** ZDR is opt-in via OR's privacy settings, and upstream provider
data policies vary. The `models.json` registration below sets
`openRouterRouting.data_collection: "deny"` for every OR model. The OpenRouter
dashboard is configured for ZDR-only routing with model training disabled.

## Observability

**pi:** `@tmustier/pi-usage-extension` (installed via `settings.json` packages)
provides a `/usage` command with a full TUI dashboard: braille line-chart
explorer (cost/tokens/messages over time, per-provider/per-model), sortable
table with export to CSV, and automated insights (cache-miss alarms, project
mix, burn trend, upfront tax warnings). Uses **real USD cost** from API
responses — when you're on subscriptions the marginal cost is £0; the dashboard
quantifies your subscription value and flags when metered fallback spend is
non-zero. Entirely local (reads `~/.pi/agent/sessions/` JSONL), no external
service, no ZDR compromise.

**Jan:** Native per-conversation usage display. A unified cross-tool tracker
is deferred — see TODO.md.

## Hypa integration

This config uses `@hypabolic/pi-hypa` in **replace mode** (`~/.hypa-pi/config.json`:
`{"mode": "replace"}`). The native `bash`, `read`, `grep`, `find`, and `ls` tools
are disabled; the model is expected to use the Hypa equivalents (`hypa_shell`,
`hypa_read`, `hypa_grep`, `hypa_find`, `hypa_ls`). This is enforced by the tool
preference note in `APPEND_SYSTEM.md`.

Because commands arrive through `hypa_shell` rather than the native `bash` tool,
the safety stack (`infra-safety.ts` and the `/check` mode shell gate) intercepts
`hypa_shell` directly and classifies the raw command. No wrapper-unwrapping is
needed in replace mode. `lib/mutation-guard.test.ts` is exercised by `check.sh` to
prevent regressions.

## File map

```
.pi/
├── web-search.json              → ~/.pi/web-search.json (pi-web-access config)
└── agent/                       → ~/.pi/agent/
    ├── settings.json            LAPTOP profile: provider, default model, cycle set
    ├── models.json              OpenRouter provider registration (shared core; env-var key)
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
cycle set + fallback map).

### Auto-fallback (map-driven)

On any status in `rateLimitFallbackStatuses` (default `[429, 529, 503, 402]` —
rate limit, Anthropic overloaded, DeepSeek/OpenAI/OpenRouter capacity 503,
OpenAI insufficient-quota 402), the extension consults `rateLimitFallbacks`
(primary → OpenRouter twin) and hops if authed. **The laptop `settings.json`
now includes `rateLimitFallbacks` for all 8 primary models** — when a
subscription rate-limits or a provider is capacity-bound, pi automatically
switches to the OpenRouter twin. The hop sets a recovery cooldown
(`rateLimitFallbackRecoveryCooldownSec`, default 120s) floored by the
response's `retry-after` when present.

OpenRouter models are registered in `models.json` so they appear in `/models` and
can be reached manually via `/use`, but they are **excluded from** `enabledModels`.

Note: some map entries are tier-adjacent rather than exact mirrors
(`glm-5.2 → openrouter/z-ai/glm-5`, `claude-opus-4-8 →
openrouter/anthropic/claude-opus-4`) — a hop is a deliberate capability
change, not a perfect substitute. Trigger set is config-driven and validated
by `check.sh`; 403 is opt-in only (permission/region 403s are not fixed by a
same-gateway twin).

### Recovery

Fallbacks are **sticky** (pi persists `defaultModel`), so two recovery paths:

1. `session_start` — if the persisted model is a fallback twin and its primary
   is authed again, switch back. Skipped when the user explicitly picked the
   twin this session via `/use`/Ctrl+P (tracked through the `model_select`
   event). A twin persisted from a *previous* run (hop or `/use`) is still
   recovered — cross-restart `/use` choice is not preserved.
2. Gated 2xx recovery — after an in-process hop, once the cooldown has
   elapsed and the twin was not user-chosen, a successful response switches
   back to the primary. The cooldown prevents mid-turn yanks back to a
   still-rate-limited primary (thrash) and misreading stream errors that
   arrive as a committed 200. The two directions have independent 2s
   throttles, so a recovery can never suppress the next fallback.

## Tests

```bash
cd base/pi/.pi/agent/extensions
node --experimental-strip-types --test lib/mutation-guard.test.ts
pi -p --no-session "Reply OK"   # smoke: extensions parse and load
```
