# Gotchas (learnt the hard way)

Reference material — load when debugging a specific issue. Not always-loaded context.

## Neovim

- Headless nvim checks: always `nvim -u NONE --headless ... -c 'qa!'` — the user's init.lua may be broken and block on a prompt; plain `qa` hangs on modified buffers.
- nvim-treesitter v1.0 (`branch = main`, entrypoint `lua/nvim-treesitter/init.lua`): the top-level module exposes ONLY `setup()` and `indentexpr()`. Use `require('nvim-treesitter').setup { ensure_install = { ... } }` — note `ensure_install` (singular, no `ed`). `config.setup` runs the install asynchronously. The old `highlight = { enable = true }` module is gone; use `vim.treesitter.start` in a FileType autocmd instead. Gotcha: the working tree can lag lazy-lock.json after an update — HEAD on the old master lineage while the lockfile pins v1.0 main. Fix: `:Lazy restore`.
- nvim-treesitter v1.0 removed the `nvim-treesitter.configs` module and `ft_to_lang`/`get_parser` from `nvim-treesitter.parsers`. telescope.nvim previewers rely on all three. Fix: a compatibility shim in `treesitter.lua`'s `config()` that injects a `package.loaded['nvim-treesitter.configs']` stub and patches `parsers` with fallback implementations. Must run before telescope loads (treesitter `lazy = false` ensures this).
- Migrating from packer.nvim to lazy.nvim: the old `plugin/packer_compiled.lua` file and `~/.local/share/nvim/site/pack/packer/` directory persist after switching package managers. The compiled loader still runs on every startup and adds old plugins to the runtimepath, causing circular-dependency errors.
- `checkhealth vim.provider` hangs on WSL when `xsel` is installed but no X server is running. Fix: `apt remove xsel` (wsl-clipboard.lua provides clipboard via clip.exe).

## stow lifecycle

- Always use `--no-folding`. Manual stow needs absolute dirs: `stow --restow --no-folding -d "$HOME/dotfiles/base" -t "$HOME" <pkg>`.
- Adding a file to an already-stowed package doesn't symlink it — re-stow (same command).
- Deleting a package leaves dangling symlinks stow can't unstow. Remove by hand first, then re-stow.
- Pre-existing config files from other tools (e.g. `**/.claude/settings.local.json`) create stow conflicts. Merge, remove blocking file, re-stow.
- stow prints "BUG in find_stowed_path" for symlinks it can't own (e.g. WSL's /mnt/c cross-filesystem links). Known noise; bootstrap.sh filters it.
- `base/fish/.config/fish/.gitignore` is an **allowlist** (`functions/*`, `conf.d/*`, `completions/` are ignored unless explicitly negated), so a new own-file is silently *untracked*: `git add` stages nothing, warns "The following paths are ignored", and the commit then asserts a file only the author has — CI fails on assertions the author's run cannot see. Negate the path there, re-stow, and let `check.sh` guard it (it covers both the named file and the class: no own file under `fish/functions` may be untracked or ignored).

## git-crypt / GPG

- git-crypt GPG subkey may expire. Use the repository's symmetric key backup as the documented fallback.
- `gpg --export-secret-subkeys` copies the ENCRYPTED stub — no passphrase prompt at export time. The prompt fires on first signing USE on the receiving machine.
- `gpg-agent.conf`'s `pinentry-program` line parser truncates at the first space. Leave it unset on Windows (Gpg4win defaults to its GUI pinentry-qt).
- **`secrets/*.fish` is hand-edited and committed later, so a dirty working copy is normal work-in-progress — never `git checkout --` it without asking.** There is no machine snapshot of an uncommitted edit: mbpm3 has no APFS local snapshots and no Time Machine destination, and a `vi` session leaves no swap file once closed. On 2026-10-14 a 09:16 `vi secrets/env.fish` edit was reverted this way and was unrecoverable. To tell real content from filter noise, decrypt HEAD and compare instead: `git show HEAD:secrets/<f> | git-crypt smudge | cmp - secrets/<f>` — identical means ciphertext-only noise (safe to re-checkout), different means the plaintext really moved. The clean filter is deterministic here, so a reported modification is never *only* a nonce artefact.
- Gpg4win installs to `C:\Program Files\GnuPG\bin\`, NOT `Program Files (x86)`.
- Gpg4win's `--list-secret-keys` shows a `[keyboxd]` keyring; that's normal.

## WSL / Windows

- WSL interop can vanish mid-session (binfmt_misc/WSLInterop disappears). Re-register: `sudo bash -c 'echo ":WSLInterop:M::MZ::/init:PF" > /proc/sys/fs/binfmt_misc/register'`
- Windows-side `git.exe` spawned from WSL cannot read message files in WSL `/tmp` (separate filesystem). Use `/mnt/c/Users/<u>/AppData/Local/Temp/` instead.
- git credential.helper values with spaces need `!\"...\"` quoting (`os/wsl/git/.gitconfig-wsl`); canonical remotes are SSH anyway.

## pi

- pi config spans two roots under `base/pi/.pi/`: `agent/` (settings, extensions, agents, prompts) stows to `~/.pi/agent/`, and `web-search.json` stows to `~/.pi/web-search.json` — a sibling, not inside it.
- `pi-hypa` replace mode disables the native `bash`/`read`/`grep`/`find`/`ls` tools.
  Safety extensions (`infra-safety`, `/check` mode) intercept `hypa_shell` directly
  and classify the raw command; no wrapper-unwrapping is needed.
- `pi-web-access` is not redundant — Pi core has no native `web_search`,
  `fetch_content`, `source_check`, or `get_search_content` tools.
- **pi writes runtime state into the tracked `settings.json`.** Selected model, theme, thinking level, `lastChangelogVersion` and the package list go back through the stowed symlink from every session, so a commit made while sessions run sweeps up whatever the last one selected — and the assertions above (defaultModel, cycle set, kimi tombstone) read that same live file, so the suite can go red for nothing. There is no setting to suppress the write. Fix: `pi-settings-reset` — reverts to HEAD, keeps `packages` / `lastChangelogVersion` and reports them, `--all` discards those too, `-n` reports only — instead of hand-reverting `git diff`. Mechanism, and the residual upstream races (1.3.0 locks and merges per top-level key; same-key LWW, the first write to an absent file, and a non-atomic write that can leave an unparsable file all remain), are in the function header.
- **pi and claude are not mise-managed** (AGENTS.md, `base/pi/README.md`). `mise uninstall` leaves the shim behind, and a stale shim shadows the real entrypoint: `command -v pi` answers with the shim, which then errors. `ensure_pi` / `ensure_claude` prune it and `check.sh` guards it — but re-check after `mise reshim`, which was observed to resurrect a `pi` shim for a tool with no install at all (`mise which pi` errors; source record not found in mise state or config). A shim for a tool the mise config no longer declares must go.
- Shims are **per-binary, not per-tool** (`2to3` comes from the python install), and they cover installed-but-inactive tools too. So neither shim-name-vs-`mise ls` nor `mise which <bin>` from `$HOME` is a staleness oracle — checking the second way deleted 85 legitimate shims here, and `mise reshim` restored them. Don't sweep shims on a heuristic; prune unused tool *versions* (`mise prune`) instead, and then re-check for pi/claude-class shims.
- pi safety has two independent axes: session posture (change/check/chat) vs. per-domain write-gate (locked/armed). Never conflate. See `base/pi/README.md`.
- Subagents load infra-safety locked with `hasUI=false` → infra mutations hard-blocked. General bash stays unguarded (oracle needs it). Intentional asymmetry.
- pi infra-safety false-positives on commit messages: `git commit -m "...terraform..."` parses as a terraform invocation → blocked. Fix: `git commit -F <file>`. The scanner reads the whole command text, not just the first word, so an inline list of a guarded CLI plus any following word (`for t in kubectl k9s …`, a spot-check naming `gcloud`, even `rm`-ing shims in the same line) is likewise parsed as an invocation and blocked while the gate is locked. Run such loops from a script file, or split the command.
- pi agent discovery: the `subagent` tool's `description:` frontmatter is not shown to the model except on an error path. The model learns agents from `APPEND_SYSTEM.md` only.
- pi TS extensions: relative imports need explicit `.ts` extensions (`./classify.ts`) for node --experimental-strip-types.
- **Shared core must be host-agnostic.** `base/pi/.pi/agent/` is copied verbatim to every deployment. Host-specific bridge packages, commands, and overlays belong in the deployment repository, not the shared core. `check.sh` enforces this.
- **Never reintroduce `pi-claude-auth`.** It copied Claude Code's Keychain credential into pi's `auth.json` and re-synced every 5 minutes, so pi and the `claude` CLI held the *same* refresh token — one rotation invalidates the other. Credentials pi owns must never be a hand-me-down from another tool's store.
- **Claude on a Pro/Max plan only works through the bridge; the direct Anthropic provider is third-party-repriced, so no credential for it is kept.** pi's native `/login` → *Anthropic (Claude Pro/Max)* mints a real subscription grant, but any request carrying pi's harness system prompt is treated as a third-party app: `400 … "Third-party apps now draw from your extra usage, not your plan limits"`. Verified A/B: a minimal `--system-prompt` succeeds where pi's normal prompt 400s, so the client is not *categorically* repriced — but that pair does not isolate what the gate keys on (prompt text vs. tool definitions vs. request metadata), so "avoid pi's harness-shaped request" is the working rule, not a mechanism. `pi-claude-auth` hid this by pinning Claude Code's version "for billing header computation" (impersonation); `pi-claude-bridge` is the supported route — it does not forward pi's system prompt verbatim (pi's structured parts are re-projected into Claude Code's own preset) and fails loudly if a forwarded part carries the `docs/custom-provider.md` + `docs/packages.md` pair. Never pin a mode or roster entry to `anthropic/*`, and keep `auth.json` free of an `anthropic` key — it can only 400 or bill extra usage.
- **`/check`'s tool gate is a denylist**, not an allowlist (`modes/index.ts`: `all.filter(...)`). Every write-capable tool registered by a package stays active in read-only mode unless its name is listed in `CHECK_HIDDEN_TOOLS`. `AskClaude` is listed because it accepts `mode: "full"`; a renamed tool via `askClaude.name` would slip past it (config `allowFullMode: false` is the backstop). New write-capable tools need adding there.
- **A stowed config file that the extension writes to dirties the repo.** `pi-claude-bridge` records `startupNoticeShown` in `claude-bridge.json` when it shows its first-run notice; the dotfile sets `provider.plan` and `askClaude.enabled` so the notice never fires. Check `git status` after any pi extension upgrade.
- **The subagent extension loads pi's example from the active release; it is not vendored.**  pi ships that extension as an example inside its own package, so a copy in the repo drifted silently and needed a re-vendor + re-stamp on every upgrade.  The two non-vendoring routes do not work: `pi install` discovers extensions only through a package manifest or a conventional `extensions/` dir (the example has neither), and a path pinned to `releases/<version>/…` is deleted by pi's release pruning on the next self-update — it keeps only the active and running releases — so it would dangle with no warning (the pin comparison was the only thing making that visible).  The loader reads `~/.pi/agent/install/current-version` and imports the example when the extension loads, which is version-matched by construction and therefore depends on pi's release layout (`managed-install.json`: `schemaVersion` 1, `layout` releases-v1, `examples/` in the tarball); a layout change fails loudly at extension load, naming the path it tried.  The cost: upstream example churn is no longer gated by a human look, so `agents-update` still owes the pi-smoke / `docs/PROMPT-EVAL.md` pass after a version move.  The example imports `@earendil-works/pi-coding-agent` from the release's own `node_modules`, which is the same absolute path the running pi loads, so one ESM instance in practice — an `instanceof` failure across that boundary is the trigger to revisit the shim.
- **`bootstrap.sh` stopped being interactive because pi's installer `exec`'d pi over itself.** On a first install the upstream installer asks *"Start pi now? [Y/n]"* and on yes runs `exec "$start_pi_path"`: the installer's process *becomes* pi — same PID, so `ps lstart` reports the installer's fork time and pi looks **older** than the install that created it (`managed-install.json`'s mtime is the truth) — it inherits the terminal, and the bootstrap that launched it waits in `do_wait` under that pi session until pi exits. Fix (in `_ensure_self_managed`): pipe the installer's stdout (`curl -fsSL "$url" | "$shell" 2>&1 | cat >&2`) so its `[ -t 1 ] || return 0` guard declines the offer while output stays visible and streaming — and never redirect the installer's **stdin**: `$shell` reads its own script from there, so `</dev/null` feeds it an empty script and the install silently no-ops with exit 0. The installer's node/npm prompt is `/dev/tty`-only but unreachable here — `ensure_pi` runs after `ensure_mise`, so node 22 is already on PATH.
- **Unattended bootstrap:** `sudo -v` in a real terminal first, then `./bootstrap.sh >log 2>&1`. With no tty *and* no cached ticket it now fails fast on the `sudo -v` instruction instead of blocking on a prompt nobody can answer, and a cached ticket gets the keepalive loop too (it used to start only in the password branch, so a ticket-cached run could still lose the ticket mid-`up.sh`). Don't background anything that inherits the pipeline's stdout: `( while sudo -v -n; do sleep 60; done ) &` alongside `./bootstrap.sh | tee log` holds the pipe open, so `tee` never sees EOF and the command never returns even though bootstrap finished minutes earlier — `ensure_sudo`'s own loop is detached (`>/dev/null 2>&1 &`) for exactly that reason, and it exits once bootstrap is gone — liveness is the bootstrap PID *plus* its start time, so a recycled PID cannot leave it renewing a sudo ticket on the host forever (a bare `kill -0` can; the loop is tick-capped as well).

## macOS

- `bootstrap.sh` must not reload Homebrew-managed launch agents (`homebrew.mxcl.*`).
  `load_macos_launch_agents()` only reloads plists that are symlinks into the
  dotfiles repo (`$DOTFILES`). Homebrew agents are skipped to avoid transient
  `launchctl bootstrap` failures (e.g. colima mid-start) aborting the whole run.
- Colima/Lima injects `Include .../.colima/ssh_config` into `~/.ssh/config`. Pre-empted: base already includes `~/.colima/ssh_config` (harmless when absent).
- `brew bundle` (host Brewfile) can hit 600s timeout when several large casks download. Idempotent — just re-run.
- Docker Desktop uninstall leaves privileged helpers behind. Manual `sudo rm -f /Library/PrivilegedHelperTools/com.docker.socket`.
- `mas`-managed casks need an active Mac App Store session — `brew bundle` fails otherwise.
- Discord brew cask can leave a dangling Caskroom symlink. Fix: `brew reinstall --cask discord`.
- Discord auto-updater caches old versions in `~/Library/Application Support/discord/app-*`. Fix: quit Discord, remove old dirs + updater state files, relaunch.

## tmux

- **A `pipe-pane` shell command is a `strftime(3)` template before it is a format
  string.** tmux runs `format_expand_time` over it (`cmd-pipe-pane.c`), so a literal
  pane id `%3` becomes `3`, and every later `tmux -t 3` silently targets **window
  index 3** with rc 0 — no error, wrong window. Use `#{pane_id}`: it contains no `%`,
  so it survives that pass and is expanded afterwards. The same call exists in 3.4,
  so it is not a version quirk, and any `%` in the string (a path or socket
  containing one) is mangled the same way. The job's stdout and stderr are `dup2`'d
  to `/dev/null`, so a broken tap fails *silently* — redirect inside the command
  string when debugging one.
- **A `pipe-pane` job inherits the server's environment, and that `$TMUX` can be
  stale or absent.** A server started with `-S <private-sock>` still handed its jobs
  the *default* socket, so a job that calls `tmux` should be given `env TMUX=<sock>`
  explicitly (which is also what makes such a job testable). Same class of bug for
  hooks: `run-shell "tmux …"` spawns a client that needs `$TMUX` to find the server
  and quietly clears nothing without it. Write hooks as **tmux commands**
  (`set-hook -g after-select-window 'set-window-option -u @pi_alert'`) — the server
  runs those itself, with no shell and no socket lookup.
- **`set-environment` does NOT reach a pane or a `pipe-pane` job created later.** Both
  inherit the environment tmux was STARTED with (what the creating client had), not the
  live global table: setting a variable and then creating the pane or re-running the
  pipe in the same server leaves it without it — verified directly, twice (a pane's
  `PATH` stayed the startup `PATH`; a session-scoped `set-environment` on the session
  did not reach a window created in it either). So a knob for the tap has to be in the
  client's environment *before* the server starts, or passed in the pipe command itself
  (`pipe-pane … "exec env VAR=value …"`), which is also how check.sh configures the
  notifier. A tmux **user option** is the way to have something changeable at runtime,
  since the tap can read it per report — and `remain-on-exit on` is the way to keep a
  pane (and its `#{pane_start_command}`) around after its command exits, which is how
  the pwt tests survive a machine with no pi installed.
- **`#{window_active}` does not mean "someone is looking at it".** tmux sets that
  flag on the current window of *every* session in the server — including sessions no
  client is attached to, and including a server with no clients at all (verified: a
  detached session's current window still reports `window_active=1`). Gating an alert
  on it as "the user is already watching this" silently suppresses the flag and the
  notification for exactly the cases worth notifying about: a workstream in another
  session's current window, and everything while tmux is detached. Ask the clients
  instead — per `list-clients -F '#{client_tty}'`,
  `display-message -p -c <tty> '#{window_id}'` is that client's current window, so
  comparing it with the pane's own `#{window_id}` answers the real question. No clients
  attached then means nobody is looking, which is when a push is *most* wanted.
- **BSD/macOS `tr` block-buffers its output**: `{ printf a; sleep 1; printf b; } |
  tr a X` writes nothing until EOF, so a `tr`-based stream splitter delivers nothing
  until the process feeding it exits. For a streaming split use
  `perl -e '$| = 1; while (sysread(STDIN,$b,8192)) { … print $b }'`. `stdbuf` is
  GNU-only and unavailable here.
- **`grep -o` is line-based on its INPUT, not just its output.** A TUI draws with
  escape sequences and can go a long time without a newline, so matches sit in
  grep's buffer and never appear; split the stream on ESC first, then match
  `^]7501;.*`. Related: `[^\n]` inside a *single-quoted* pattern is a literal
  backslash and `n`, not a newline class.
- **`pane-focus-in` fires only for a real client.** A detached or probe server never
  fires it, which reads exactly like "my hook is broken". `after-select-window` does
  fire without a client, so wire both (they are idempotent) and test the one that can
  fire. `set-hook` does reject names tmux does not know, so a typo fails at config
  load — but a valid hook that never fires fails silently.
- **Testing a pane tap: a finite emitter proves nothing.** When the feeding process
  exits, its buffered output arrives in one flush, so a *dead* consumer still looks
  like it works — as does a one-shot `printf | consumer`, which pipes EOF
  immediately. Use an emitter that never exits, plus a bounded poll, plus a
  distractor window at the index a mangled pane id would hit, so a wrong-target bug
  is visible instead of landing on the right window by luck.
- **Probes inherit the developer's `TMUX`, so a "private socket" test will still
  write to the live server.** Every `tmux` call inside a probe needs `-S <sock>` or
  `env -u TMUX`; testing a consumer without that put window options on the author's
  real windows.

## General

- bash `${var#...}` tolerates no spaces around the operator.
- `read` with a tab IFS **collapses empty fields**: a tab is IFS *whitespace*, so
  consecutive tabs are one delimiter and everything after an empty middle field shifts
  left — `a<TAB>b<TAB><TAB>c` reads as `a b c`. Emit a placeholder for any field that
  can be empty (a tmux format can: `#{?#{@var},#{@var},-}`), or parse with a
  non-whitespace separator. This is how a pane's state came to be read as its own
  label, and then sorted by it.
- `check.sh` `check_has` patterns are line-based grep. Multi-line assertions need `bash -c "... grep -A1 ... | grep -q ..."`. `check_not` is a plain `grep -qE` against the file, so its pattern must be `^-anchored` (or otherwise tight) whenever the file can contain prose that legitimately mentions the thing — a loose substring turns a passing repo into a false failure. Structured files (JSON) are safe unanchored.
- Mosh needs system packages (protobuf, utempter, openssl) — no mise/ubi binary.
- Linux/WSL has no system ssh-agent: `base/fish/.../conf.d/ssh-agent.fish` runs a shared agent on `~/.ssh/agent.sock`. Extend that file, don't add another.
- ssh always forwards LANG/LC_*: macOS/Ubuntu ship `SendEnv LANG LC_*` in `/etc/ssh/ssh_config`, and ssh reads the USER config first then APPENDS the systemwide file's patterns — `SendEnv -LANG` in `~/.ssh/config` runs too early and can't remove them (verified: `ssh -G` still shows `sendenv LANG LC_*`). Bare `SendEnv` is a fatal parse error. Fix: `conf.d/ssh-locale.fish` wraps ssh with `-F ~/.ssh/config`, which makes ssh ignore the systemwide file entirely (`Include` directives inside the user config still work). Caveat: scp/sftp/git exec the ssh binary directly and bypass the wrapper.
- shellcheck runs at `-S warning`; info-level findings are acceptable.
- `gh repo delete` needs the `delete_repo` scope. `gh auth refresh -h github.com -s delete_repo` first.
- VSCodium `--install-extension` emits harmless `DEP0169` warnings. Extensions install fine.
- Electron apps bundle their own Node.js — mise/system Node is never involved in their issues.
- **Before killing a process, walk your own ancestry.** `ps -o pid,ppid,args` up from
  `$$`: a stalled `bootstrap.sh` turned out to be the *parent* of the pi session
  diagnosing it, and killing it took the whole tmux session down with it (a different
  tmux server PID afterwards — the pane was not the only casualty). The mechanism
  matters less than the rule: if the target is in your own ancestry, say what the kill
  would take with it and let the human choose (Ctrl-C in the pane, or an explicit yes)
  instead of reasoning about signal delivery.
- **A probe's shell is not a given.** Commands run through the agent's shell wrapper have
  executed under `sh` (`[[: not found`), which made a bash guard print a confident but
  false "would be skipped" that was nearly acted on. When a probe's answer changes what
  happens next, write it to a file and run it with an explicit interpreter
  (`bash /tmp/probe.sh`), the way the `ensure_sudo` unit harness does.
- **`fzf --preview` runs under `$SHELL`, which is fish here.** A multi-line POSIX
  preview (`n=$(git rev-list …); [ "$n" -gt 0 ] && …`) is a fish *syntax error*, and its
  output lands in the preview pane — so the panel looks broken rather than the snippet
  ("fish: Unsupported use of '='." with the offending line echoed under it). Keep a
  preview to one line that sh, fish and zsh all parse, or put it in a script with its
  own shebang (`base/tmux/bin/pwt-preview`). fzf's shell is inherited, never chosen
  deliberately; the same applies to `execute(...)`.
