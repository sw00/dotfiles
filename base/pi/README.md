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

## Variants (`pi-use`)

`~/local/bin/pi` is a symlink, and `pi-use` (stowed from
`base/pi/.local/bin/pi-use`) is what moves it. Every variant reads the same
config only where the table says so.

| command | runs | config | extensions |
| --- | --- | --- | --- |
| `pi-use bolt` | pi-bolt 1.0.9 — pi 1.4.0 compiled AOT — **the default** | `~/.pi/agent` | all, via jiti in JSC's interpreter (runtime-verified) |
| `pi-use pi` | upstream managed install | `~/.pi/agent` | all — the rollback path and the zero-lag option |
| `pi-use pig` | PiG 0.7.0+1.5.0 — the same Pi, in Go (`PIG_USE_PI_DIRS=1`) | `~/.pi/agent` | all — PiG implements Pi's extension model (process-hosted TS) |

`pi-use status` reports the link, the variant and what is actually running, and
fails on drift (a recorded choice that the symlink no longer honours). A flip is
fully reversible: it changes one symlink and one state file, nothing else.

**bolt is the default because parity plus footprint beat version-freshness.**
It shares `~/.pi/agent` byte-for-byte (settings, auth, trust, models, skills,
sessions), so the whole extension stack — `infra-safety`, `subagent`,
`model-switch`, `usage`, `hypa`, web access, the Claude bridge — loads exactly as
under pi, and no per-variant provisioning exists. It reports `1.4.0 (Pi-Bolt
1.0.9, …)`: one minor behind upstream, which is the price. `agents-update`
updates it in place (`pi update --self` rewrites `~/.pi-bolt`); npm installs
cannot self-update and must run npm themselves. Rollback is `pi-use pi`, and
`pi-bolt update --rollback` exists for the bolt tree itself.

Rules that follow from the table:

- **A flip is a harness swap.** Sessions written by another variant live in the
  same tree but may not resume cleanly across the 1.4.0/1.5.0 gap — resume under
  the variant that wrote the session, and treat a flip (or a pi-bolt rebase) as
  owing the `pi-smoke.sh` pass.
- **`usage` comes from its package on both pi variants, and bolt's compiled-in copy
  is switched off.** bolt ships a `usage` extension of its own while
  `@tmustier/pi-usage-extension` registers the same `/usage`, so bolt skipped its
  builtin and warned on every start. The package is canonical — it is the only
  copy that exists under `pi-use pi`, and it is versioned and updated with the
  rest — so the settings template carries `"extensions": ["-builtin:usage"]`.
  Under bolt the behaviour is unchanged (the builtin was already the one that
  stepped aside); the line makes the choice explicit and silences the warning.
  Upstream pi ignores an unknown `-builtin:<name>` (measured: a `-p` run with the
  key present warns nothing and the stack loads), so the one shared settings file
  is right on both. The cost: no automatic fallback — drop the package and
  `/usage` goes away under bolt instead of falling back to the builtin. And
  `extensions` is *template-owned* like every key but `packages`: a toggle made in
  `pi-bolt config` is reverted by the next `pi-settings-apply`, so template first.
  A bolt upgrade can compile in more extensions; check the compiled-in list in
  `pi-bolt doctor` rather than waiting for a name collision to warn.
- **`pi-use pig` is PiG (MichaelKinsy/PiG, pi-in-go.dev), and it is a drop-in
  only through the shared-tree switch.** PiG is Pi reimplemented in Go: same CLI,
  same settings/auth/session formats, and Pi's *full* extension model, with TS
  extensions hosted in a Node child process (≥ 22.13) — so this repo's stack
  loads under it unchanged, because it ships Pi-API extensions and npm packages
  only and no PiG-only feature. With **`PIG_USE_PI_DIRS=1`** — the exact value
  `1`, nothing else — PiG reads `~/.pi/agent` and the project `.pi/` under Pi's
  own lock protocol: **one settings, trust, auth and session store**, so a flip
  re-asks nothing and a rollback is `pi-use pi` (one symlink, no migration). Any
  other value (unset, `0`, `true`) leaves it on `~/.pig/agent`, a second,
  unseeded tree — which is why `set_pig` refuses to flip without `1`. The
  variable lives in `conf.d/pig.fish`, never in settings: settings are shared, so
  a value written there would follow you back into upstream pi. **`~/.pig` is
  PiG's SDK/Piglet cache only** — never stow it, never merge it into
  `~/.pi/agent`, never delete it as "duplicate config". PiG is provisioned by
  mise (`ubi:MichaelKinsy/PiG`, pinned) and moves with `mise upgrade`; it has no
  self-update, so `agents-update` bumps the pin rather than calling
  `pi update --self`. **PiG never writes the settings template** — the template
  is intent and is pushed with `pi-settings-apply`, exactly as on the other
  variants.
- **"pig" here never means `ZoroSpace/pig`, the other Go rewrite.** That binary
  has **no extension system** at all (`-e file.ts` validates the path, then runs
  nothing), so flipping to it silently dropped `infra-safety` (the locked/armed
  write gate), `subagent`, `model-switch`, `usage`, `hypa`, web search and the
  Claude bridge, and it kept its own unseeded `~/.pig/agent` trust store that
  could not even prompt. It is not provisioned, and `check.sh` tombstones it.
  One command tells the two binaries apart:
  `env -u PIG_VERSION_FORMAT pig --version` — PiG prints `<pig>+<pi>`
  (`0.7.0+1.5.0`), ZoroSpace prints a bare `1.5.0`. `pi-use pig` refuses any
  version without a `+`, so the impostor cannot be flipped into place.

## Project trust

A trust store is a flat `{"<canonical abs path>": true|false}`. Resolution walks
**up** from the cwd to the nearest key (`findNearestTrustEntry`), so a **prefix**
entry trusts every repo beneath it — present and future. That is why the checkout
roots are stored as roots, never enumerated per project:

| entry | kind |
| --- | --- |
| `~/src/personal` | checkout root — every repo under it |
| `~/src/lelapa` | checkout root — every repo under it |

Anything narrower (a single repo that ships `.agents/skills`, say) is a *project*
entry: make it interactively under pi, or seed it by hand. It needs no mirroring
anywhere — every variant reads the same file.

**One store, one policy.** Upstream pi, pi-bolt, and PiG (under
`PIG_USE_PI_DIRS=1`) all read `~/.pi/agent/trust.json`, so a `pi-use` flip re-asks
nothing and there is a single trust boundary to audit. Seed it:

```sh
home=$(cd -P "$HOME" && pwd -P)   # a symlinked $HOME must not leak into the keys
s=$HOME/.pi/agent/trust.json
mkdir -p "${s%/*}"; [ -s "$s" ] || printf '{}\n' >"$s"
jq -S --arg home "$home" '. + {($home + "/src/personal"): true,
    ($home + "/src/lelapa"): true}' "$s" >"$s.tmp" && mv "$s.tmp" "$s"
```

Keys are canonical absolute paths, and matching is exact: the resolver walks up
from a canonicalised cwd comparing raw keys, so a non-canonical key trusts
nothing. `check.sh` asserts the set in the single store, so changing this table
means editing `_PI_TRUST_ENTRIES` in `check.sh` too. It is a security statement:
anything cloned under a trusted prefix can load that project's settings and
extensions, and under PiG in shared mode that grant is exactly the same one —
`PIG_USE_PI_DIRS=1` is a config switch, not a trust decision.

## Models

| Model | Role | Rationale |
|------|-------|-----------|
| `opencode-go/deepseek-v4.1-flash` | Daily driver / worker / pairing driver (default) | Fast, economical Go-quota use and a strong fit for routine coding work; the only one of the two DeepSeek Flashes that takes images |
| `opencode-go/glm-5.3` | Oracle | GLM family is preferred for reasoning escalation; low-volume oracle use justifies the fuller model |
| `opencode-go/glm-5.3-flash` | Pairing navigator | Scout-and-direction work is read-only probing plus one step of planning, so the navigator rides the cheaper GLM Flash; its context window is overridden to 500k in `models.json` on purpose — a scout that reads a handful of files has no use for the full 1M and a shorter transcript is less diluted by its own tool output |
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

`agent/extensions/optional/modes/index.ts` — `/chat`, `/check`, `/change` (or Ctrl+Alt+M
to cycle). It lives under `optional/` on purpose: pi discovers only
`extensions/*.ts` and `extensions/*/index.ts`, so the modes are opt-in through the
settings template, while a downstream appliance opts out by deleting one
directory. These are the only slash commands; `/plan` and `/review` were removed
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

**Brave Search, falling back to Exa**, via `pi-web-access` 0.47.0. Config at
`~/.pi/web-search.json` (`base/pi/.pi/web-search.json`): a `searchRouting` route
`brave → exa`, the `auto-summary` workflow (no browser curator), summaries
drafted by Flash, and `webSearch.allowedProviders: ["brave", "exa"]`. Keys resolve
per search through `~/bin/web-search-key`, which sources `secrets/env.fish` (git-crypt'd)
in a short-lived `fish` child and emits the value of exactly `BRAVE_SEARCH_API_KEY` or
`EXA_SEARCH_API_KEY` and nothing else, so the repo holds no credential and search works
without `creds` — Paseo agents included, measured (AGENT-SAFETY §5). The getter's own
stderr never
reaches the tool, so a failure shows only as `… credential resolution failed:
command-failed`: run `~/bin/web-search-key BRAVE_SEARCH_API_KEY` by hand to see why
(git-crypt locked, fish missing, empty value).

`firecrawlApiKey` is host-scoped on purpose: it names `$EYES_SHIM_TOKEN`, a token owned
by a LAN-only rendering service that is firewall-scoped to one host. That host's session
wrapper exports it; anywhere else it is unresolved *by design*, so `fetch_content` logs
one credential failure and falls back to the built-in extractors. Do not move it into `secrets/env.fish` or add it to the getter's allowlist:
that would be a second copy of a token owned elsewhere, with no drift guard of its own.

The fallback covers named failure kinds only — `quota | transient | network |
invalid-response | empty` (the last is a successful search with no results). A
Brave `auth`, `credential`, `invalid-request`, `config` or `aborted` failure
stops the route; `fallbackOn` does not accept those kinds, and an unresolvable
key should be fixed, not routed around. `source_check` rides the same route, and
config is read per process, so a running session keeps the old route until it
restarts. Per the package's own config reference (README §Configuration): a
scalar `provider` takes precedence over `searchRouting`, the allowlist refuses
other providers even when named per call, and `provider: "all"` aggregates only
the listed ones.

Hence **no scalar `provider` key** — one would silently disable the route — and
`check.sh` asserts its absence, because the curator's provider picker writes
that scalar back through the stowed symlink into this tracked file. An explicit
`provider: "exa"` on a call is honoured (Exa's `category` filter is the per-call
reason); other names are refused before any request.

Brave stays primary for its SOC 2 Type II Zero Data Retention. **Exa has no ZDR on
this plan**: Exa's ZDR is an Enterprise feature enabled per team ($12k/yr, 25
QPS), and its privacy policy says query data is used to train and fine-tune its
models — Exa acts as a processor under a DPA for API customers, but that
document's substance could not be verified (the public page renders no body).
So Exa is a fallback on Brave's failures, never a peer, and the query-hygiene
rule in `agent/AGENTS.md` applies to it exactly as to any other engine.

## ZDR posture

| Provider | Model(s) | Training? | Retention |
|---|---|---|---|
| Brave Search API | — | No | Zero (SOC 2 Type II) |
| Exa (keyed API) | — | Per privacy policy: queries train models | No ZDR here — Enterprise-only, enabled per team |
| OpenCode Go (Zen) | `deepseek-v4.1-flash` (daily driver, worker and pairing-driver subagents, web-search summaries), `glm-5.3` (oracle), `glm-5.3-flash` (pairing navigator), `claude-haiku-5-5` (reviewer — Claude routed via Go, not Anthropic), `gpt-5.6-luna` | No | Zero (paid tier) |
| Anthropic (Claude Pro/Max) | `claude-haiku-5-5`, `claude-sonnet-5-5`, `claude-opus-5-5` — all via the Claude Code bridge; no direct API route | No | Zero (subscription terms) |
| OpenRouter | varies by upstream | Configurable | Depends on upstream |

**Caveat:** OpenCode Go's **free** tier models (suffixed `-free`) explicitly
permit training. None are in the catalog today, and `check.sh` enforces that
`summaryModel` and all model entries in the `settings.desired.json` template are
free of `-free`
variants. The summary model here is the paid `deepseek-v4.1-flash` (no suffix)
— safe.

**OpenRouter:** ZDR is opt-in via OR's privacy settings, and upstream provider
data policies vary. The `models.json` registration below sets
`openRouterRouting.data_collection: "deny"` for every OR model. The OpenRouter
dashboard is configured for ZDR-only routing with model training disabled.

## Observability

**pi:** `@tmustier/pi-usage-extension` (installed via the template's `packages`
list)
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
    ├── settings.desired.json    tracked INTENT: provider, default model, cycle set
    │                           (pi never reads this file; the live one is
    │                            ~/.pi/agent/settings.json, host-local/untracked)
    ├── models.json              OpenRouter provider registration (shared core; env-var key)
    ├── claude-bridge.json       Claude Code bridge provider + AskClaude config
    ├── AGENTS.md                global rules (web search hygiene)
    ├── APPEND_SYSTEM.md         escalation ladder (always-on; keep lean)
    ├── agents/                  oracle, worker, reviewer, navigator, driver
    └── extensions/
        ├── subagent/            delegation tool (loads pi's shipped example)
        ├── optional/            NOT auto-loaded; enabled by the settings template,
        │   ├── modes/           /chat /check /change   stripped by the appliance
        │   └── infra-safety.ts  infra CLI mutation guard (wires infra-tables)
        ├── model-switch.ts      /use /cycle /models + rate-limit auto-fallback
        ├── no-powershell.ts     prunes the win32-only `powershell` builtin on non-Windows hosts
        └── lib/
            ├── mutation-guard.*  shared locked/armed engine (+ node --test)
            ├── classify.ts       pure verb parsing/classification (pi-free)
            └── infra-tables.ts   aws/az/gcloud/kubectl/terraform verb tables
                                  (pi-free; shared by infra-safety + tests)
```

## Shared core vs. profile

Everything under `agent/` except `settings.desired.json` is the **shared
core**: generic, host-agnostic, and free of deployment-specific defaults. The
laptop profile is the `settings.desired.json` template in this repo — intent
only, and never written by pi. The file pi actually reads and rewrites is
`~/.pi/agent/settings.json`: host-local, not stowed, not tracked, refreshed from
the template by `pi-settings-apply`. Other deployments own their own template
and any host-specific overlay extensions in their deployment repositories — they
are NOT tracked here, and the shared core must stay free of references to them.
`check.sh` enforces this.

## settle-notify

`agent/extensions/settle-notify.ts` — a desktop notification when the agent settles
(`agent_settled`, skipped when the run was aborted) or blocks on a prompt
(`ui_prompt_start`). Title is `repo/branch`; nothing is pushed for the pane you are
looking at. macOS `osascript`, a zero-dep WinRT toast on WSL, `notify-send` otherwise.
It also raises `@pi_waiting` on the pane's window for the tmux bar to render as `!`,
cleared when the window is looked at or a new run starts.
`PI_SETTLE_NOTIFY=0` mutes the push (the bar is unaffected); `SETTLE_NOTIFY_CMD` replaces
the transport for tests.

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

### Provider fallback (text-driven)

`providerFallbacks` covers the other failure shape: a provider that is unusable as
a whole, and fails **before a response streams**. `after_provider_response` is only
emitted once a response streams, so the status machinery above cannot see it —
measured on `opencode-go` with a lapsed subscription, where every request 403s
("An active OpenCode Go subscription is required to use Go models") and the error
text appears only on `turn_end`.

```json
"providerFallbacks": {
  "opencode-go": { "to": "opencode", "match": ["active OpenCode Go subscription"] }
}
```

On a match the session switches to the **same model id** on the target provider
(Zen shares `OPENCODE_API_KEY` and carries 19 of Go's 32 ids; the 13 with no
twin — Go's contributor/preview models plus `mimo-*`, `qwen3.7-plus`, `hy*` and
`longcat-2.0` — leave the model alone and say so). Because the switch happens on the failed
attempt, pi's own retry finishes the same turn on the twin; where pi classifies the
error as non-retryable (its list names OpenCode Go's usage-limit errors) one
continuation is forced at `agent_before_settle` instead. No cascades: a session
already on a target provider is never re-hopped.

### Recovery

An extension's `pi.setModel()` does **not** persist `defaultModel` (corrected
2026-10-22: `agent-session.js` writes it only for `options.persist`, which the
extension-facing wrapper does not pass) — but it DOES append a `model_change` to the
session, and a resumed session (`pi -c`, `--resume`, an explicit `--session-id`)
restores from that. So a fallback survives a resume, which is why the extension
re-probes the primary on `session_start`: a lapsed subscription is re-tested once per
session, and when it comes back the session returns to it by itself. The cost while
it is still lapsed is one failed attempt on the next turn. `/use` onto a twin is
never overridden.

What remains sticky is a twin recorded in a *session* — by a hop, or by a
`/use`/Ctrl+P — hence two recovery paths:

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
node --experimental-strip-types --test lib/provider-fallback.test.ts
pi -p --no-session "Reply OK"   # smoke: extensions parse and load
```

Prompt text (`APPEND_SYSTEM.md`, the global `AGENTS.md`, the subagent contracts)
has no unit test. `pi-smoke.sh` runs three behavioural scenarios and counts tool
calls; `docs/PROMPT-EVAL.md` holds the pass signatures, the measured baseline, the
method caveats, and the 500-word budget `check.sh` enforces on
`APPEND_SYSTEM.md`. Run it on both sides of a prompt change — it costs
`runs x 3` real model turns per side.
