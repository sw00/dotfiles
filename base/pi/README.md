# pi coding agent config

Minimal model roster for the [pi](https://pi.dev) coding agent: each model
has a distinct role; escalation is driven by uncertainty, not failure counters.
Three explicit modes shape each session. Stows to `~/.pi/`.

## Installation

pi installs itself with its **own managed installer** — deliberately not via
mise (the dotfiles' normal tool route):

```bash
curl -fsSL https://pi.dev/install.sh | sh                  # macOS / Linux / WSL
powershell -c "irm https://pi.dev/install.ps1 | iex"       # Windows (npm/pnpm only)
```

`ensure_pi()` in `bootstrap.sh` runs this (skipped when a managed install is
already live). The layout: entrypoint `~/.local/bin/pi` → launcher
`~/.pi/agent/bin/pi`, which exports `PI_MANAGED_INSTALL_ROOT` and execs
`~/.pi/agent/install/releases/<version>/node_modules/.bin/pi`.

Why the exception:

- **Only this layout self-updates.** pi classifies its install by path; an
aqua-extracted binary is `unknown` and a mise/npm copy is not under the global
npm root it computes, so `pi update --self` refuses with *"cannot self-update
this installation"*. With the managed root exported, `pi update` (and `--self`)
work.
- **mise cannot drive the version either.** It re-resolves `latest` only when
`mise upgrade` runs — this host sat on 0.80.10 while upstream reached 1.2.0 —
and its install dir precedes `~/.local/bin` on PATH, silently shadowing the
managed entrypoint. That combination is what produces "moved pi to a managed
installation and it can't self-update".
- **Trade-off accepted:** the installer passes npm's `--min-release-age=0`
(dependency graph pinned by npm-shrinkwrap), so there is no release-age soak
window as mise's own gate would give. `pi update` is manual; that is the
control.

Never re-add `pi` to `~/.config/mise/config.toml` — `check.sh` fails if it
reappears, or if `pi` resolves back into the mise tree. Removing the entry is
not enough on a host that already had pi installed: `mise uninstall pi` leaves
a stale shim at `~/.local/share/mise/shims/pi`, which keeps mise first on PATH
(and errors outright if `~/.local/bin` leaves PATH). `ensure_pi()` deletes that
shim and prunes the stale install dir; `check.sh` asserts both are gone.

`ensure_pi()` installs but never upgrades: a host that is already self-managed is
skipped, because an upgrade swaps the harness under the prompts this repo ships
and has to be paired with the smoke eval that only a human can judge. Upgrades
are therefore deliberate — `agents-update` (in `base/fish`) runs
`pi update --self` and `claude update`, then reports whether pi's version moved
and, when it did, points at `pi-smoke.sh` and `docs/PROMPT-EVAL.md` (see Tests).
Nothing needs re-vendoring: the subagent extension loads pi's own example from
the active release at load time.

## Models

| Model | Role | Rationale |
|------|-------|-----------|
| `opencode-go/deepseek-v4.1-flash` | Daily driver / worker (default) | Fast, economical Go-quota use and a strong fit for routine coding work; the only one of the two DeepSeek Flashes that takes images |
| `opencode-go/glm-5.3` | Oracle | GLM family is preferred for reasoning escalation; low-volume oracle use justifies the fuller model |
| `opencode-go/claude-haiku-5-5` | Reviewer | Fast, subscription-backed review path; won the Haiku-vs-GLM-Flash trial |
| `opencode-go/gpt-5.6-luna` | Vision / difficult multimodal work | Stable multimodal model for image input and difficult multimodal work |
| `claude-bridge/claude-sonnet-5-5` | Manual premium control | Mature second opinion covered by the Claude Pro entitlement; also `/chat`'s model |
| `claude-bridge/claude-opus-5-5` | Exceptional manual escalation | Highest-quality premium control; Ctrl+P only |
| `claude-bridge/claude-haiku-5-5` | Manual premium Haiku | Premium-route alternative to the reviewer's Go-quota Haiku; the trial this row was created for concluded in Haiku's favour |

OpenRouter PAYG models remain manual-only and are not part of the curated
cycle. Experimental `*-exp` models are also excluded from the
normal roster. Web summarisation uses the daily-driver model unless explicitly
changed.

## Claude Code bridge

Premium turns run through `npm:pi-claude-bridge`: it drives the installed
Claude Code over the Agent SDK and registers its models as `claude-bridge/*`,
so the subscription is consumed the way Claude Code consumes it. It needs an
authenticated `claude` binary (the Agent SDK ships its own copy of Claude Code;
`provider.pathToClaudeCodeExecutable` overrides it), not a pi credential.
Config: `agent/claude-bridge.json`
(stowed — see the write-back note below).

The `claude` binary on PATH is Claude Code's **native install**, not a mise copy:
`ensure_claude()` in bootstrap.sh runs Anthropic's installer (`~/.local/bin/claude`
→ `~/.local/share/claude/versions/<v>`) and keeps it on latest with `claude update`
— the app owns itself, for the same reasons pi does (AGENTS.md). Note what the
bridge actually executes: by default the Agent SDK's *bundled* Claude Code, with
`provider.pathToClaudeCodeExecutable` reserved for overriding it. The PATH binary
is the interactive CLI; what the bridge needs from it is the shared credential
store (`~/.claude` plus the macOS Keychain entry), which is why moving claude off
mise is transparent to the bridge.

- `provider.plan` — `"pro"` (default); `"max"` unlocks Opus 4.6's 1M window.
- `provider.strictMcpConfig: true` — blocks `~/.claude.json` / `.mcp.json` MCP
  servers inside bridge turns.
- `askClaude.enabled: true` + `allowFullMode: false` — the opt-in delegation
  tool, read-only by default, for when another provider gets stuck. `/check`
  also hides it (it can otherwise be given `mode: "full"`).

Both `provider.plan` and `askClaude.enabled` are set explicitly on purpose: the
bridge's one-time "settings live here" notice only fires when one is unset, and
recording it would write `startupNoticeShown` through the stowed symlink and
dirty this repo.

Context windows follow what the bridge has *measured*, not what pi-ai declares:
Opus 5.5 and Sonnet 5.5 are served at 1M through the `[1m]` suffix, Haiku 5.5 at
200K. `provider.longContextExtraUsage` opts into the metered 1M paths (only
Opus 4.6 and Sonnet 4.6 are gated on this plan). Bridge
models are registered at `cost: 0`, so `/usage` counts their tokens but reports
no USD for them — read that quota from Claude Code instead.

Upstream notes an Anthropic Agent-SDK billing change that was announced and
then unannounced; a metered turn would show up as non-zero spend.

There is deliberately **no** direct Anthropic credential here. pi's native
`/login` → *Anthropic (Claude Pro/Max)* does mint a real subscription grant, but
a request carrying pi's harness system prompt is treated as a third-party app:
`400 … "Third-party apps now draw from your extra usage, not your plan limits"`.
Verified — a minimal `--system-prompt` succeeds where pi's normal prompt 400s.
pi-claude-auth concealed this by pinning Claude Code's version "for billing
header computation" (impersonation); the bridge is the supported route, because
it does not forward pi's system prompt verbatim — pi's structured parts are
re-projected into Claude Code's own preset. Everything Claude goes through
`claude-bridge/*`, and no `anthropic` entry is kept in `auth.json`, so nothing
can silently bill extra usage. Do not reintroduce `pi-claude-auth`
either: it copied Claude Code's Keychain credential into `auth.json` and
re-synced it every five minutes, so both sides rotated **one** refresh token.

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

Subagents run in isolated pi subprocesses (`agent/extensions/subagent/` loads the
example pi ships, from the active release — nothing to re-vendor on upgrade).

## Modes

`agent/extensions/modes/index.ts` — `/chat`, `/check`, `/change` (or Ctrl+Alt+M
to cycle). These are the only slash commands; `/plan` and `/review` were removed
as redundant (the escalation ladder handles oracle/reviewer autonomously in
`/change` mode). Mode persists across session resume; a per-mode reminder is
injected each turn and filtered when stale.

| Mode | Tools | Model | Intent |
|------|-------|-------|--------|
| `change` (default) | full | worker | autonomous execution; ladder active |
| `check` | read-only (edit/write/subagent off, domain mode tools hidden, bash allowlisted) | worker | pair-troubleshooting; **user** is the escalation target, no delegation |
| `chat` | unrestricted | `claude-bridge/claude-sonnet-5-5` | conceptual altitude; no changes unless asked |

Toolset is a pure function of the mode (stateless — no snapshot/restore).
In check mode, domain mode tools (e.g. `infra_mode`) are also removed since
every guard is force-locked and cannot be opened from within check.
Entering `/chat` switches to `claude-bridge/claude-sonnet-5-5` and restores the
prior model on exit,
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
independently, default to locked, and run with `hasUI=false`. The guards hook
`hypa_shell` **only**, and pi-hypa's replace filter drops a builtin only when
its hypa twin is in the *same* active tool list — so this holds only because
`agents/*.md` request the hypa tools. An agent that asked for `bash` would get
native bash, which no guard sees; `check.sh` asserts the agents never do.
General shell (test runners, builds) stays unguarded because oracle needs it for
diagnosis; the read-only constraint for non-infra commands relies on the agent
prompt, not a tool gate.

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
| OpenCode Go (Zen) | `deepseek-v4.1-flash` (daily driver, worker subagent, web-search summaries), `glm-5.3` (oracle), `claude-haiku-5-5` (reviewer — Claude routed via Go, not Anthropic), `gpt-5.6-luna` | No | Zero (paid tier) |
| Anthropic (Claude Pro/Max) | `claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5` — all via the Claude Code bridge; no direct API route | No | Zero (subscription terms) |
| OpenRouter | varies by upstream | Configurable | Depends on upstream |

**Caveat:** OpenCode Go's **free** tier models (suffixed `-free`) explicitly
permit training. None are in the catalog today, and `check.sh` enforces that
`summaryModel` and all model entries in `settings.json` are free of `-free`
variants. The summary model here is the paid `deepseek-v4.1-flash` (no suffix)
— safe.

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
service, no ZDR compromise. Exception: `claude-bridge/*` turns are registered
at `cost: 0`, so they appear with tokens and no USD — read their quota from
Claude Code, not this dashboard.

**Jan:** Native per-conversation usage display. A unified cross-tool tracker
is deferred — see TODO.md.

## Hypa integration

This config uses `@hypabolic/pi-hypa` in **replace mode** (`~/.hypa-pi/config.json`:
`{"mode": "replace"}`). The native `bash`, `read`, `grep`, `find`, and `ls` tools
are disabled; the model is expected to use the Hypa equivalents (`hypa_shell`,
`hypa_read`, `hypa_grep`, `hypa_find`, `hypa_ls`). Enforced by replace mode plus
the agents' `tools:` lists; `APPEND_SYSTEM.md` no longer restates it (the tool
descriptions and pi-hypa's `promptGuidelines` carry the mapping).

Because commands arrive through `hypa_shell` rather than the native `bash` tool,
the safety stack (`infra-safety.ts` and the `/check` mode shell gate) intercepts
`hypa_shell` directly and classifies the raw command. No wrapper-unwrapping is
needed in replace mode. This holds in the subagent processes too, but only
because their `tools:` lists name the hypa tools (`agents/*.md`) — requesting
`bash` there would restore an unguarded native shell. `lib/mutation-guard.test.ts`
is exercised by `check.sh` to prevent regressions.

## File map

```
.pi/
├── web-search.json              → ~/.pi/web-search.json (pi-web-access config)
└── agent/                       → ~/.pi/agent/
    ├── settings.json            LAPTOP profile: provider, default model, cycle set
    ├── models.json              OpenRouter provider registration (shared core; env-var key)
    ├── claude-bridge.json       Claude Code bridge provider + AskClaude config
    ├── AGENTS.md                global rules (web search hygiene)
    ├── APPEND_SYSTEM.md         escalation ladder (always-on; keep lean)
    ├── agents/                  oracle, reviewer
    └── extensions/
        ├── subagent/            delegation tool (loads pi's shipped example)
        ├── modes/               /chat /check /change
        ├── model-switch.ts      /use /cycle /models + rate-limit auto-fallback
        ├── infra-safety.ts      infra CLI mutation guard (wires infra-tables)
        ├── no-powershell.ts     prunes the win32-only `powershell` builtin on non-Windows hosts
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

Prompt text (`APPEND_SYSTEM.md`, the global `AGENTS.md`, the subagent contracts)
has no unit test. `pi-smoke.sh` runs three behavioural scenarios and counts tool
calls; `docs/PROMPT-EVAL.md` holds the pass signatures, the measured baseline, the
method caveats, and the 500-word budget `check.sh` enforces on
`APPEND_SYSTEM.md`. Run it on both sides of a prompt change — it costs
`runs x 3` real model turns per side.
