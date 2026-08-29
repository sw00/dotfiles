# pi coding agent config

Minimal model roster for the [pi](https://pi.dev) coding agent: each model
has a distinct role; escalation is driven by uncertainty, not failure counters.
Three explicit modes shape each session. Stows to `~/.pi/`.

## Models

| Model | Role | Rationale |
|------|-------|-----------|
| `opencode-go/deepseek-v4-flash` | Daily driver / worker (default) | Fast, economical Go-quota use and a strong fit for routine coding work |
| `opencode-go/glm-5.3` | Oracle | GLM family is preferred for reasoning escalation; low-volume oracle use justifies the fuller model |
| `opencode-go/glm-5.3-flash` | Reviewer | Fast, subscription-backed review path |
| `opencode-go/gpt-5.6-luna` | Vision / difficult multimodal work | Stable multimodal model for image input and difficult multimodal work |
| `anthropic/claude-sonnet-4-6` | Manual premium control | Mature second opinion covered by the Claude Pro entitlement |
| `anthropic/claude-opus-4-8` | Exceptional manual escalation | Highest-quality premium control; Ctrl+P only |
| `opencode-go/kimi-k2.7-code` | Manual coding alternative | Meaningful historical usage; retain as an alternative |
| `opencode-go/kimi-k2.6` | Manual coding alternative | Meaningful historical usage; retain as an alternative |
| `anthropic/claude-haiku-4-5` | Manual reviewer comparison | Retained for the Haiku-vs-GLM-Flash empirical trial |

OpenRouter PAYG models, including Kimi K3, remain manual-only and are not part
of the curated cycle. Experimental `*-exp` models are also excluded from the
normal roster. Web summarisation uses the daily-driver model unless explicitly
changed.

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
| OpenCode Go (Zen) | `deepseek-v4-flash`, `glm-5.3`, `glm-5.3-flash`, `gpt-5.6-luna`, `kimi-k2.6`, `kimi-k2.7-code` | No | Zero (paid tier) |
| Anthropic (Console) | `claude-haiku-4-5`, `claude-sonnet-4-6`, `claude-opus-4-8` | No | Zero (API/Pro) |
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
generic, host-agnostic, and free of deployment-specific defaults. The laptop
profile is the `settings.json` in this repo. Other deployments own their own
`settings.json` and any host-specific overlay extensions in their deployment
repositories — they are NOT tracked here, and the shared core must stay free of
references to them. `check.sh` enforces this.

## model-switch

`agent/extensions/model-switch.ts` — `/use <q>` (fuzzy-switch any authed model),
`/cycle` (rotate the **cycle set** = `enabledModels`), `/models` (show active +
cycle set + fallback map).

### Auto-fallback (map-driven)

On any status in `rateLimitFallbackStatuses` (laptop explicitly uses
`[429, 529, 503]`), the extension consults `rateLimitFallbacks`
(primary → OpenRouter twin) and hops if authed. The laptop intentionally has an
empty fallback map: subscription quota exhaustion or provider trouble must be
visible rather than silently converting Claude Pro/OpenCode Go usage into
OpenRouter PAYG spend. Select an OpenRouter model manually when desired.

OpenRouter models are registered in `models.json` so they appear in `/models` and
can be reached manually via `/use`, but they are **excluded from** `enabledModels`.

Trigger set is config-driven and validated by `check.sh`; 403 is opt-in only
(permission/region 403s are not fixed by a same-gateway twin).

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
