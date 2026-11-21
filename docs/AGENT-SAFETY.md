# Agent safety — the spec

Safety here means layers between an agent and the outcomes that cannot be undone:
a credential leaving the machine inside a published artifact, and an irreversible
act on live infrastructure. The intent is durable and the harness is replaceable —
each layer names the file that implements it, so the implementation can be swapped
without re-deciding the policy.

Every dated claim was measured on that date. Session-scoped working notes are
host-local scratch and never outrank this file — it is the contract. Each row
below names the file that must exist for the layer to be real, and `check.sh`
asserts that path — a layer whose file never landed is red, not believed. A
*capability* that is designed but deliberately unbuilt is recorded under §2.1 and in
§4 as a residual, never in a layer's row: a spec that describes intent as fact is how
the next session inherits a hole it thinks is covered.

## 1. Risk classes → layers

Ranked by what cannot be recovered. The letter is the owner's ranking; the table
is the mapping it implies.

| Rank | Class | Primary | Secondary | Residual (accepted) |
|---|---|---|---|---|
| b | secret exfiltration | L0 env hygiene; L3 secret-file rules; L2 secret-path gate on the file tools (`lib/secret-paths.ts`) | L2 read-verb + secret-noun = high-risk (`disclosesSecret`, `lib/classify.ts`); L4 scans outbound web-tool inputs | non-shell interpreters; an executed file with no shell shebang and no `.sh` suffix (§2.1b); indirection *inside* an inlined script body (§2.1b); a symlink that points into `secrets/` (the gate resolves lexically, §2.1a) |
| c | credential in a published artifact | L4 publish guard | L1 pre-commit (this repo, staged files) | channels other than gh/glab/web tools |
| e | irreversible remote ops | L3 rulebooks (deny) | L2 (locked default; armed = human confirm) | ops neither table names |
| a | infra mutation | L2 locked/armed gate | L3 for the destructive subset (no kubectl rulebook exists) | argument-position false positives (§4) |
| f | silent wrongness | L5 feedback (`check.sh`, `pi-smoke.sh`, `PROMPT-EVAL`) | — | not a hook's job |

## 2. Layers

| L | What | Attachment | Failure mode → detection |
|---|---|---|---|
| L0 | No credential is exported at shell startup. `creds <cmd>` loads them for one command, in that command's own process tree, and nothing else forwards them. | `base/fish/.config/fish/config.fish:4-26` (`creds`) | If `source secrets/env.fish` comes back → `check.sh` fails: a static pin on startup files (`check.sh:3170`) plus a behavioural login-shell probe printing names only, just below it |
| L1 | git-crypt at rest; `.githooks/pre-commit` names the offending path, never the matched text | `git` (`core.hooksPath`), `.githooks/pre-commit:74-77` | Bypassed with `--no-verify` → the L3 project rulebook blocks that invocation (`check.sh:3090` requires a blocked fixture per rule) |
| L2 | Infra gate: `extensions/infra-safety.ts` + `lib/{mutation-guard,classify,infra-tables}.ts`; **plus** the secret-path gate `lib/secret-paths.ts` on the file tools | `tool_call` on both shell tools — one constant, `SHELL_TOOLS = ["bash", "hypa_shell"]`, and one predicate, `isShellCall` (`lib/mutation-guard.ts`), so the handler and `/check`'s read-only gate (`modes/index.ts:235`) cannot drift apart. Resets to locked on `session_start`. Arm with `/infra-arm` or the `infra_mode` tool. When armed, a mutation needs `ctx.ui.confirm` showing the whole command; with no UI it is blocked rather than auto-approved. A second `tool_call` handler gates the FILE tools by path (`FILE_PATH_TOOLS` = read/grep/find/edit/write + the `hypa_*` mirrors): a path resolving under a directory named `secrets` is denied outright — no mode, no confirm | An unknown verb while locked is blocked, i.e. it fails closed. Hook not loaded → `infra_mode` is absent from the tool list and nothing notices at runtime: `check.sh` asserts the files and their shape (`:4829`, `:4831`, `:4836`), never a live session. A hook that loads but is inert is UNVERIFIED — no check probes it. The secret-path half is driven at the decision boundary (`check.sh`'s `safety: L2 denies hypa_read of secrets/env.fish, allows secrets/leak-patterns` calls the same `secretPathBlock` the hook returns), which is as far as a check can go without a live session |
| L3 | cc-safety-net: exact npm package declared in settings `packages` (`npm:cc-safety-net@2.8.1`). User config stowed from `base/cc-safety-net`, project rulebook in `.cc-safety-net/`, every rulebook ref pinned to a 40-hex commit. | Its own pi extension hooking `bash` plus the declared `hypa_shell` (probe B, §3) | Package absent → the layer is gone without notice → `check.sh` host assertions: stow link (`:4960`), installed version matches the pin (`:4974`), library denies `git reset --hard` and allows `ls` (`:4984`) |
| L4 | Publish guard: `extensions/publish-guard.ts` + `lib/publish-scan.ts` | `tool_call` on shell tools running a publish verb (gh/glab) and on `fetch_content`/`web_search` | Scanner unavailable → blocks (fails closed). It never echoes the match |
| L5 | Feedback | `check.sh`, `pi-smoke.sh`, `docs/PROMPT-EVAL.md` | A skip reported as green (PRINCIPLES §What counts as a defect) |

Composition: if any layer blocks, the call is blocked, and no layer can loosen
another. Modes only tighten: `/check` forces L2 locked and clears every armed
status (`modes/index.ts:204-207`), and `/change` never arms it.

Four independent `tool_call` handlers see each shell call: L2's command gate,
L3's own hook (the npm package registers `pi.on("tool_call")` through its
minified adapter, so grepping the installed dist for `pi.on` does not find it —
grepping for `tool_call` does), L4's publish gate, and `/check`'s read-only
allowlist (`modes/index.ts:243`), which is a gate in its own right. L2's
file-path handler is NOT one of them: it gates the file tools and is blind to
shell commands by design. Three more extensions in the same list also subscribe
(`@hypabolic/pi-hypa` for the shell tools, `pi-web-access` when web search is
enabled, `pi-claude-bridge` for its own reasons).

Nothing in the harness orders them, and `pi-hypa` is the one that makes order
matter: it REPLACES `event.input.command` for `bash` before later handlers see
it, so a guard that reads the raw field and one that reads the rewritten field
are judging different strings. The pi docs (`extensions.md`) describe a
sequential preflight whose block return stops the call; they do not promise an
order or a first-wins rule, so the only safe assumption is that every layer is
independently sound. `/check`'s non-check branch re-adds every registered tool
(`pi.setActiveTools(getAllTools())`, `modes/index.ts:180`), which is why
`no-powershell.ts` prunes per turn — the one ordering dependency the tree
documents, and the reason a cross-layer rule belongs here rather than in a
comment inside one file.

What L2 matches is the command string **plus the bodies of the shell scripts that
string names** (`expandScripts`, `lib/classify.ts`) — and nothing else. No
other file is read: an interpreter, or a script whose shebang does not claim a
shell, is still opaque to L2 (§2.1b, §4 residual 5). A runner that reads its script
from a pipe, and a command word held in a variable, are *refused* rather than
inspected: both classify as unknown. Inside an already-inlined body the same shapes
are a reported notice, not a block — the depth boundary in §2.1b.

Path, not command: the second half of L2 never looks at a command string. It
inspects the `path` argument of a file tool (`secretPathBlock`), and it is
intentionally blind to `bash`/`hypa_shell` — a shell command that reads a secret
is the classifier's and L3's business, and blocking `grep secrets/leak-patterns`
here would break this repo's own scanners. Two matching rules, two domains.

Cites into the `lib/` modules name the **symbol**, not a line: `classify.ts`,
`mutation-guard.ts` and `infra-tables.ts` are the files this change set is still
splitting up, so a line number there would be stale before it was read. `check.sh`
pins the same exports by name for the same reason (`:4829`, `:4831`).

### 2.1 Landed, and what is still not honest

Everything this section used to list as "designed, not in the tree" is in the tree.
It stays split in two, because §1's residual column and §4's accepted costs are
only honest if the shapes L2 still misses are named. (a) ships and is asserted;
(b) is measured to pass a locked gate today.

**(a) Landed.** Every row is pinned by a check, so none of it can rot silently.

| Capability | Implementation | Asserted by |
|---|---|---|
| Dual shell tools | `SHELL_TOOLS = ["bash", "hypa_shell"]`, `SHELL_TOOL_SET` and `isShellCall` live in `lib/shell-tools.ts` — one declaration, no pi import, so the publish guard and the unit tests read it too; it drives the gate's `tool_call` handler and `/check`'s read-only gate (`modes/index.ts:235`), so a harness that exposes `bash` is not left ungated | `check.sh:2988` (one declaration), `:2990` (the gate re-exports it), plus a check that no hook hard-codes one shell name; the pure suite pins exactly one declaration repo-wide |
| Secret-noun classification | a read-ish verb aimed at a credential noun is high-risk, not read (`disclosesSecret`; the noun sets are `secretNouns` in `lib/infra-tables.ts`), with enumeration verbs exempt because they return names, not values (`ENUMERATION_VERBS`) | `check.sh` runs the secret-noun pure suite with a pinned pass count |
| Confirm payload | no truncated confirm: past `CONFIRM_LIMIT` the armed gate refuses and tells you to split it (`confirmPayload`), and the human is shown the whole command once (`lib/mutation-guard.ts`, in the `tool_call` handler) | same |
| Read-only lookup allowances | segments led by `which`, `type`, `whereis` or `command -v` are not classified — nothing they name executes (`isLookupSegment`, `LOOKUP_LEAD`). The exemption is withheld from any such segment that carries a substitution, because that is code and not a name: `which $(aws s3 rm s3://b/k)` classifies as an `aws` mutation and blocks (measured 2026-11-16) | same |
| Script expansion | `expandScripts` inlines shell-script bodies at most `SCRIPT_MAX_BYTES` (1 MiB) each and `SCRIPT_MAX_DEPTH` (3) levels deep, refusing non-regular files before reading; a script the command **names directly** that is unreadable or oversize becomes an unresolved unknown, which a locked gate blocks and an armed gate blocks, while a mutation found inside any inlined body blocks in both modes. What the walk cannot resolve *inside* an already-inlined body is a notice, not a block — see §2.1b | `check.sh:2999` (the export exists); `sh /tmp/probeA.sh` — §4 residual 5's own case — now blocks (§3, probe D); `bash check.sh` runs under a locked gate (pure suite) |
| Flag-gated escalation | `highRiskFlags` (`lib/infra-tables.ts`) makes a read verb high-risk only with a revealing flag — `ssm get-parameter --with-decryption`, `kubectl config view --raw`, `terraform output|show -json` — so the innocent form stays a read | pinned in the same suite |
| Secret-path reads (2026-11-16, owner decision) | `secretPathBlock` / `isSecretPath` (`lib/secret-paths.ts`) denies a FILE-tool `path` that resolves under a directory named `secrets` — probe E's gap, where L3 allows `secrets/env.fish` because the file is git-crypt'd rather than `.env`-shaped. `SECRET_ALLOWLIST = ["leak-patterns"]` keeps the identifier corpus readable: it names hosts and customer identifiers, not credentials, and `check.sh` + `.githooks/pre-commit` scan with it. Component match, not substring (`secrets-notes.md`, `notsecrets/x` pass); `..` normalised before deciding; a path that cannot be resolved is a deny; the reason names the rule and the path, never a value. The shell is NOT gated — that is the classifier and L3 (§2) | `check.sh` asserts it three ways: `safety: L2 wires the secret-path gate to the FILE tools only` (every file tool named, no shell tool), `safety: L2 secret-path suite passes 13/13` (count pinned), and `safety: L2 denies hypa_read of secrets/env.fish, allows secrets/leak-patterns` (the decision driven end to end) |
| `--` is a wall | `--help`/`-h`/`--dry-run` are read-only only **before** a standalone `--`; past it the flag belongs to the wrapped command (`beforeEndOfFlags`). `--version` is no longer a blanket read allowance | same |
| Project rulebook | `.cc-safety-net/rules/rule.json` plus `rules/dotfiles-rules/rulebook.json`: deny `git commit --no-verify` / `-n`, forced pushes, forced adds; one blocked fixture per rule plus allow cases, including `git add secrets/env.fish` (allowed, because the path stays git-crypt'd) | `check.sh:3090` (fixture per rule + an allow), `:3070` (every ref is a 40-hex commit) |

**(a-1) The project rulebook ships, and its schema is validated.** `.cc-safety-net/`
is in the tree and stowed like any other config: `rules/rule.json` declares one local
source (`dotfiles-rules`) and `rules/dotfiles-rules/rulebook.json` carries three rules
with ten fixtures (six blocked, including an `-n` short form and an `add -f`, plus
four allows). Schema validated with `cc-safety-net rule verify` (2.7.14) on
2026-11-16, on a sandbox copy of the project dir: `✓ Project config — schema:
rulebook sources, sources: 1. dotfiles-rules` and `✓ GitHub source rules` with the
rulebook resolved. Two facts about re-running it: `verify` **normalises** — it writes
`$schema` into the config it validates, so read the repo copy back afterwards — and
against the live `$HOME` it refuses outright with "Unable to access user policy
filesystem safely", because the live user config is a set of stow symlinks. That is
why `check.sh` asserts the shape instead of shelling out to `verify`: the JSON parses
and every rulebook ref is a 40-hex **commit**, not a tag or branch (`#d1fc329f…`,
`check.sh:3070`), and every rule has a blocked fixture plus at least one allow
(`:4931`). A branch or tag ref reads as a pin to a human; it does not satisfy the
check.

**(b) Still not honest — the shapes L2 misses.** Each was measured on 2026-11-16
passing a **locked** gate (probe D, §3), except the first, which is a deliberate depth
boundary rather than a measurement:

- **Intent hidden inside a script's own indirection is best-effort.** L2 enforces
  what it reads for the command it was given (depth 0: the command line, and whether
  a script that command names directly can be read at all). What the expansion walk
  fails to resolve *inside* an already-inlined body (depth ≥ 1) — a `$VAR` command
  word, an unexpandable `$DOTFILES/…` path, a shell reading a script from a pipe — is
  recorded as a **notice** (`nestedNotes` in `lib/script-expand.ts` /
  `lib/classify.ts`), reported once per session through `ctx.ui.notify` and never as
  a block; an unrecognised verb found there is a notice for the same reason. L3
  independently parses script contents, so the shell layer is not the only reader.
  The reason is measured, not stylistic: this repo's own `check.sh` is 297 KB of
  `$VAR` command words, `$DOTFILES/…` paths and quoted prose, and a gate that failed
  closed on all of them made the suite unrunnable **in every mode** — friction in the
  wrong direction, and the reliable way to get a guard switched off. A *recognised*
  mutation inside a body still blocks in both modes; that is what inlining is for.
- **An executed file that declares itself neither by shebang nor by suffix.** A
  directly run `/tmp/x/bare` — no shebang, no extension — is skipped on purpose:
  nothing in it claims to be a shell script. Two things count as a declaration: the
  shebang (`SHELL_SHEBANG`, `lib/classify.ts`) and a `.sh` suffix (`/\.sh$/`), so a
  `.sh` with no shebang is inlined and blocks on its body. Python and node scripts
  that shell out stay a residual for the same reason — no claim to being a shell
  script.
- **A nested substitution inside a script body** (`echo $(sh /tmp/x.sh)` *inside* a
  script L2 already inlined) is scanned for CLI names, not expanded again.
- **Bare interactive shells** are now an unknown rather than an allow: `bash` with no
  file argument can run anything, so a locked gate blocks it and an armed gate asks.

Every shape above is a *block* only where the gate reads it, i.e. on the command
itself (depth 0); the same shape inside an already-inlined body is the notice
described in the first bullet. The boundary is a product decision, not an oversight:
enforcing it made `bash check.sh` unrunnable, and the residual is written down here
instead of being papered over.

Shapes that used to be listed here are **closed**, each measured 2026-11-16: a runner
reading stdin (`curl … | sh`, `sh -s`) and a `$VAR` command word classify as
unknown, so a locked gate blocks them and an armed gate confirms. The same walk
refuses `/dev/stdin` — its reader `stat()`s first and a non-regular file is never
read (`lib/mutation-guard.ts`), so `sh /dev/stdin` is a declared-but-unreadable
script and reports `unresolved`; no shape is left that fails *open*. The unknown
shapes added in this change set — a shell reached through `xargs`/`find -exec`, a
command word assembled at run time (`$(echo ter)raform`, a `{a,b}` brace list) and a
path hidden behind a glob — likewise classify as unknown or `unresolved`: a locked
gate blocks them, an armed gate confirms them.

**(c) Unverified predicates.** Conclusions unchanged, and still not measured:

- **`@version` pins honoured by the settings `packages` entry.** The template's pin
  shape is asserted (`check.sh:2158`, a full semver, exactly once) and the installed
  copy is compared to it (`:4974`), but that comparison is skipped wherever the
  package is absent — which is every host observed so far. Whether pi and PiG honour
  `@x.y.z` **at install time** is UNVERIFIED. What settles it: a fresh agent dir with
  a pinned entry, then read the installed `package.json` version.
- **L3 covers the hypa file tools directly (decision C1 resolved, 2026-11-16).** Probe
  E drove cc-safety-net's own Pi host with a fake harness: `hypa_read` of
  `~/.ssh/id_ed25519` and `hypa_grep` over `~/.ssh` both return
  `block:true — Access to a sensitive path is not allowed`, identically to `read`.
  Its routing is by *input shape*, not by the four documented tool names, so replace
  mode does not make its secret rules inert. **No adapter is needed, and none is
  written.** The one gap probe E left — `secrets/env.fish` is not in its secret list
  (it is git-crypt'd, not `.env`), so L3 allows an agent read of that path — is now
  closed in this repo by L2's secret-path gate (§2.1a), not by a project rule.
  Whether that hook fires in a LIVE session is UNVERIFIED: the predicate and its
  wiring are unit-tested, and the wiring is three lines with no IO, but no probe has
  driven a real `hypa_read` at `secrets/env.fish` yet. What settles it: one `pi -p`
  session told to read that path, expecting `secret-path: blocked`.

## 3. Verification log (2026-11-16)

Measured on this host, on that date. Do not re-derive; re-measure only when a layer
moves.

**Probe A — what L3 actually covers.** cc-safety-net with 50 active rules at level
`standard`:

- DENY: `git reset --hard`, `cat ~/.ssh/id_ed25519`, `terraform destroy`,
  `aws s3 rm --recursive`.
- ALLOW: `terraform apply`, `kubectl delete pod`, `aws ec2 run-instances`.

Read as a layer, not a gate: it stops a command it has a rule for and no case
for, and it lets a mutation through whenever only the human could have decided. That
is exactly why L2 stays (class a), and why "could cc-safety-net replace
locked/armed" was answered no — it is deny-only, stateless, allow-by-default, has
no kubectl rulebook, and its `rule.json` is agent-writable.

**Probe B — shell tools are declarable.** `rule tool add hypa_shell` records
`command_tools: ["hypa_shell"]` in the rule file. So no adapter is needed to put
pi-hypa's shell tool under L3, and the "pi-hypa replace mode defeats the hooks"
worry is closed for shell.

**Probe C — the harness exposes what the layers need.** Under PiG in `--mode rpc`:
`ctx.hasUI === true` with a full `ctx.ui` object, so an armed mutation can be
confirmed from the hook. With `PIG_USE_PI_DIRS=1`, the settings `packages` entry
was auto-installed into `<agent-dir>/npm` (`npm:cc-safety-net`), so declaring a
safety dependency in the template is enough — no installer step.

**Two measured false positives (L2).**

- `which -a aws kubectl` was blocked as an infra mutation: the classifier reads CLI
  names in argument positions. **Retired** — lookup-led segments are skipped
  (`isLookupSegment`, `lib/classify.ts`) and it re-measured as unclassified on
  2026-11-16 (§2.1a).
- A rulebook install message mentioning `gcloud azure` was blocked as an
  "unrecognised verb". Not retired — it is the accepted cost in §4, residual 4.

**Probe F — L3 blocks a real session, live (2026-11-16).** Not a unit probe: a
normal `pi -p` session was told to run `cat ~/.ssh/id_ed25519 | head -1`. The
`hypa_shell` call was refused with rule `secret.home.ssh`, nothing was printed, and
the model reported the block and offered the alternative instead of retrying or
working around it. This closes the "does the hook fire on the declared tool inside a
real session" falsifier — the last load-bearing claim about L3's shell coverage.
Still manual: the PiG **TUI** confirm rendering (probe C proved the API, in RPC
mode), and a session written by one harness resuming under the other.

**Probe E — the hypa file tools are covered (2026-11-16).** cc-safety-net's own Pi
host, loaded with a fake harness in Node, then driven with `tool_call` events:
`hypa_read` on `~/.ssh/id_ed25519` → `block:true`, "Access to a sensitive path is
not allowed"; `hypa_grep` over `~/.ssh` → same; `hypa_read` on a repo README →
allowed. Identical verdicts to the native `read` tool, so its routing keys on the
input shape rather than the four documented tool names. Consequence: no adapter is
needed for replace mode. Second consequence: `secrets/env.fish` (git-crypt'd, not
`.env`-shaped) is *allowed* — the gap the second half of L2 closes on the file tools
(`lib/secret-paths.ts`, §2.1a), by denying the path rather than teaching L3 a rule.

**Probe D — script expansion, and what a locked gate still lets through
(2026-11-16).** Measured by driving the pipeline the gate itself runs
(`classifyInvocations` / `checkCommandReadOnly` from `lib/`, reading the returned
`unresolved`/`unknowns` too), not a re-implementation of it, and with the gate's own
reader shape (`stat()` first, non-regular files refused). Bodies in the fixtures
carried an `s3 rm`; the CLI name is spelled indirectly here so this file does not
trip the gate it describes.

| Command | Locked gate |
|---|---|
| `sh /tmp/x/withshebang.sh` (body carries the mutation) | BLOCKED — the body is classified, not the filename |
| `sh /tmp/x/noshebang.sh` (same body, no shebang) | BLOCKED — a launcher's file argument needs no shebang |
| `sh <<'EOF' … EOF` | BLOCKED — `<<EOF` resolves to no readable file, i.e. an unknown |
| `which -a <cli> kubectl` | not classified — the retired false positive above |
| a fetched body piped into `sh` | BLOCKED — a runner reading stdin is an unknown (§2.1b) |
| `CMD=<cli>; $CMD <verb> …` | BLOCKED — a `$VAR` command word is an unknown (§2.1b) |
| `./noshebang.sh` (same body, no shebang, `.sh` suffix) | BLOCKED — the suffix declares a shell script, so the body is classified (§2.1b) |
| a bare `/tmp/x/probe` with no shebang and no suffix | ALLOWED — nothing claims it is a shell script (§2.1b) |
| `python3 /tmp/x/probe.py` that shells out | ALLOWED — only shell scripts are expanded (§2.1b) |
| `sh /dev/stdin` | BLOCKED — a non-regular file is refused unread, i.e. `unresolved` (§2.1b) |
| bare `sh`, `bash -s`, `sh -e` (no file argument) | BLOCKED — a shell with no file to read is an unknown (§2.1b) |
| `xargs sh`, `find … -exec sh {} +` | BLOCKED — the shell is reached through a runner argument, an unknown (§2.1b) |
| `$(echo ter)raform <verb>`, `<cli> ap{ply,ply}` | BLOCKED — a command word assembled at run time is an unknown (§2.1b) |
| `sh /tmp/x/*.sh`, `sh /tmp/x/{a,b}.sh` | BLOCKED — a glob/brace path names no single readable file, i.e. `unresolved` (§2.1b) |

Side observation, same date: a `hypa_shell` call whose only sin was carrying the
payload inside a `printf` argument was blocked live. That is residual 4 seen from the
other side — literal CLI names anywhere in an argument list are classified.

## 4. Accepted costs

1. L3 still denies an armed, human-confirmed `terraform destroy`,
   `git reset --hard` or `aws s3 rm --recursive`. **You run those yourself in a
   separate terminal.** There is deliberately no in-session override.
2. L3 has no "ask" outcome: a denial is final and the reason lands in context. L3
   and L2 handler order is unspecified, so a human can approve an L2 confirm and
   then be denied by L3 anyway.
3. L3's config is agent-writable: `rule.json` and the rulebooks can be edited by
   the agent they constrain (only `policy.json` at its live path is protected).
   Tampering is *detected* by `git status` and `check.sh`, not prevented.
4. L2 matches CLI names in argument positions, so `… gcloud azure` inside another
   tool's arguments is blocked as an unrecognised verb (measured, §3). Workaround:
   arm, or rephrase.
5. **Script bodies are inspected; the other indirections are not.** `expandScripts`
   inlines the shell scripts a command names, so `sh /tmp/probeA.sh` — the case that
   was open when this section was written — now blocks (measured 2026-11-16, §3).
   What is still open, each measured passing a **locked** gate: an executed file
   that declares itself neither by shebang nor by `.sh` suffix, a non-shell
   interpreter that shells out, and a substitution nested inside an already-inlined
   body (§2.1b). Pipe-into-shell, `$VAR` command words, `/dev/stdin`, a shell behind
   `xargs`/`find -exec`, a substitution- or brace-built command word and a glob path
   are closed **on the command itself** (depth 0): all classify as unknown or
   `unresolved`, so locked blocks them and armed confirms them. The same shapes found
   *inside* an inlined body are a reported notice, not a block — the depth boundary
   in §2.1b, which exists because `bash check.sh` (297 KB, this repo's own suite)
   otherwise could not run in any mode. More file reading does not fix the remaining
   three — the payload lives somewhere L2 cannot see (a non-shell interpreter, or a
   file with no claim to being a script).
6. The plaintext session store is kept 90 days (decision D3).

## 5. Settled policy questions

**Settled 2026-11-16 — should the agent be able to read `secrets/env.fish`? No.**
Probe E found L3 allows it (the file is git-crypt'd, not `.env`-shaped, so its
secret list does not match). L0 keeps the *shell* from exporting those values and
`creds` loads them for one command, but an agent read put every credential in
context — class (b), and from there into anything L4 has to catch. Owner decision:
deny by default. Implemented as the second half of L2 (`lib/secret-paths.ts`,
§2.1a) rather than as an L3 project rule: a rule would have had to enumerate paths
in an agent-writable file, and the gate also covers the `hypa_*` tools and any
clone or worktree path without a list to maintain. Two deliberate narrowings, both
stated so the next session does not "fix" them:

- **`secrets/leak-patterns` stays readable** (`SECRET_ALLOWLIST`). It is the
  identifier corpus that `check.sh` and `.githooks/pre-commit` scan with, and it
  holds internal hostnames and customer identifiers, not credentials. Denying it
  would break the scanners to protect nothing.
- **Shell commands are not gated.** `grep secrets/leak-patterns` is how the
  scanners run, so the shell stays with L2's classifier and L3's secret rules; this
  gate is the FILE tools only. A shell read of `secrets/env.fish` is therefore still
  L3's call, and L3 still allows it.

The costs, accepted: a directory named `secrets` anywhere on the host is treated as
a credential store (a false positive in an unrelated project is a deny with a reason
naming the rule), `ls` is not gated (it returns names, not contents), and the check
is lexical — a symlink whose *target* is inside `secrets/` passes.

**Settled 2026-11-18 — how does a workstream get credentials? `creds`, per command.**
The window is an ordinary shell (`docs/WT.md`), so there is no second forwarding path
to argue about: a workstream has no credentials until someone types `creds pi -c`, and
then the values live in that process tree alone. That is strictly narrower than the
old spawn path, which `tmux -e`-ed the values in at spawn, so L0's "nothing exported
at startup" now holds for workstreams too and can be quoted without an asterisk. The
cost is a typed word per launch and a restart after a token rotation; the benefit is
that an idle window is clean, and that no code carries the values.

**Settled 2026-11-21 — the work store is a named, scoped exception, and Paseo agents get
exactly that scope.** `/Users/sett/src/lelapa/.envrc` (generated, outside any repo) says
so itself: everything below `/Users/sett/src/lelapa`, agent sessions included, inherits
the work credentials. That is direnv's scope, not a startup export, and it is the only
one. The Paseo daemon starts under launchd with no direnv hook, so its agents had no
scope at all and their MCP `${VAR}` headers failed. `~/bin/paseo-agent-env`
(`base/paseo/bin/paseo-agent-env`, wired as the `pi` and `claude` provider `command` in
`hosts/mbpm3/paseo/.paseo/config.json`) is the daemon-side twin of that hook. It resolves
the agent's source checkout through git, takes the nearest `.envrc` strictly below
`$HOME`, and runs the harness under `direnv exec` there, or bare if there is none. It
never allows an `.envrc` and sets no variable of its own. So L0's "no asterisk" holds for
the dotfiles store, where nothing reaches an agent until `creds`. For the work store it
is scoped, not global: a `~/dotfiles` or `~/src/personal` agent gets nothing, wherever
its worktree lives. `check.sh` proves both directions on a fixture (§Paseo).

## 6. Harness, no lock-in, rollback

PiG (`MichaelKinsy/PiG`) is the intended default `pi`, set with `pi-use pig`.
**That flip has not been executed**: measured 2026-11-16, `pi-use` reports
`variant: bolt` with `~/.local/bin/pi -> pi-bolt`. It is a separate, deliberate step
— `ensure_variant_default` (`bootstrap.sh:730`, called at `:1166`) converges only the
*unrecorded* case and points it at pi-bolt — not part of the safety change itself.
Upstream pi stays installed: it is the rollback binary and the source of the
subagent example (`extensions/subagent/index.ts` resolves `current-version`).

There is **one state dir.** `PIG_USE_PI_DIRS=1` (only the exact value `1` works)
makes PiG use `~/.pi/agent` and the project `.pi/`, with pi's settings, auth and
session formats and its lock protocol. It is set in `conf.d/pig.fish`, never in
settings. `~/.pig` is PiG's SDK and Piglet cache only: never stow it, merge it or
"deduplicate" it. If `~/.pig/agent` exists, PiG ran unshared. The probe residue
currently on this host moves to `~/.pig-agent-unshared-20261116` *before* the
`check.sh` assertion lands — asserting first would fail a green host. (UNVERIFIED
that a shared-mode session never creates `~/.pig/agent`; watching one session
settles it, and if it does create the dir the assertion narrows to `settings.json`.)

This repo ships only pi-API extensions plus npm packages declared in pi settings,
and no PiG-only feature is used. Rollback is `pi-use pi` (or `pi-use bolt`): one
symlink flip, no migration, no data conversion. Upgrades go through `agents-update`,
which bumps the PiG pin with mise and names the `pi-smoke` pass it owes.

## 7. Naming rule

"pig" in this repo means **MichaelKinsy/PiG** (pi-in-go.dev). The other Go rewrite
is always written "ZoroSpace pig". It has no extension system (`-e` validates the
path, then runs nothing), is never provisioned, and is tombstoned in `check.sh`:
a layer that cannot load `infra-safety` is not a harness choice, it is the absence
of L2.

To tell them apart with one command: `env -u PIG_VERSION_FORMAT pig --version`.
PiG prints `<pig>+<pi>` (e.g. `0.7.0+1.5.0`); ZoroSpace prints a bare `1.5.0`.

## 8. Dependency budget

| Dep | Role | Pin | Updated by |
|---|---|---|---|
| PiG | intended default harness (flip **not executed**, §6) | exact, `ubi:` (`0.7.0`, `base/mise/.config/mise/config.toml:111-113`) | `agents-update` (`mise upgrade --bump`) |
| pi (upstream) | rollback + subagent example | self-managed | `agents-update` |
| pi-bolt | second rollback (decision C2) | self-managed | `agents-update` |
| node 22 (≥22.13) | runs TS extensions and L3 | mise `"22"` | mise |
| pi-hypa | tokens and latency (replace mode) | settings `packages` | `pi update --extensions` |
| cc-safety-net | L3 | exact npm (`2.7.14`) | `agents-update` |
| gitleaks | L4 corpus | mise `latest` (`aqua:gitleaks/gitleaks`) | `mise upgrade` |

Admission test for a safety dependency — all six, no exceptions:

- popular and maintained;
- MIT or Apache, no field-of-use rider;
- zero transitive dependencies if it runs in-process;
- no telemetry;
- installable by declaration (no installer that rewrites agent config);
- denies on error.

Rejected 2026-11-16: dcg — licence rider, `pi-dcg` fails **open** by default,
install telemetry, and `dcg install` rewrites hook configs. Three of the six, and
the fail-open default alone disqualifies anything called a safety layer.

## 9. When custom code is justified

All five must hold:

1. a dated, measured gap;
2. no dependency passing §8 covers it;
3. a pure `lib/` module plus thin wiring, with node tests that `check.sh` runs;
4. it fails closed;
5. block messages name the rule, never the matched value.

Exceptions, with the evidence that earned them:

- **L2 gate (`infra-safety.ts`).** 2026-11-16: cc-safety-net is deny-only and
  stateless, offers no human decision at the moment of the act, and its rules are
  agent-editable (probe A, §3). It therefore cannot express read-only-by-default,
  per-session escalation, or "modes only tighten". The secret-path half (§2.1a) is
  the same exception applied to a measured allow: L3 permits a read of
  `secrets/env.fish` (probe E), an L3 project rule could only name paths from an
  agent-writable file, and no write gate can express "denied, not approvable".
- **L4 publish guard (`publish-guard.ts`).** 2026-11-16: L3 guards file *access*,
  not content, and `pre-commit` scans only this repo's staged files — neither sees
  a body sent to someone else's repo. Incident: a credential pasted into a
  work-repo PR body (`Lelapa-AI/engineering-org#31`, third description edit).
- **(Retired) L3 adapter for `hypa_read/grep/find/ls`.** Measured unnecessary
  (probe E): cc-safety-net blocks `hypa_read`/`hypa_grep` on sensitive paths by input
  shape. Kept on record so the ~20-line adapter is not re-invented.

Any other custom code labelled safety links here or gets deleted.

## If you change this

- **Renaming or moving a layer's file** owes this table and the `check.sh`
  assertion in the same commit — the table is the only place the inventory exists,
  and a stale path reads as a landed layer.
- **Adding a safety dependency** goes through §8's admission test, not a
  preference vote; the pin goes in the table with the thing that updates it.
- **Adding a `source secrets/env.fish`** anywhere at startup breaks L0's premise
  and must fail red first (the `check.sh` L0 probe: a clean login shell exports no
  credential name).
- **Teaching L2 to read a new kind of file** is a fail-closed change: unreadable or
  oversize input must classify as `unknown`, never as read-only.
- **Dropping L3 or L4** re-opens §9 with a fresh dated gap, and it is a change to
  §1's residual column, not to a file list.
