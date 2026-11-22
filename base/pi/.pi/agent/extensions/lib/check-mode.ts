/**
 * /check mode's read-only shell classifier — the pure half of the gate.
 *
 * `optional/modes/index.ts` cannot be imported from a test: it pulls in
 * ./mutation-guard.ts, which imports `@earendil-works/pi-ai` and `typebox`
 * (neither resolves from this repo under `node --experimental-strip-types`).
 * So the allowlist lives here — no pi, no IO — and the extension keeps the
 * wiring, the same split as edit-guardian.ts ↔ lib/edit-diagnostic.ts and
 * infra-safety.ts ↔ lib/mutation-guard.ts. Test: ./check-mode.test.ts.
 *
 * Two layers, in this order:
 *   1. `domain.issues` — CLIs that have their own guard extension (aws,
 *      kubectl, terraform, …) are classified by that guard's verb tables,
 *      which are the single source of truth for infra read/mutation.
 *   2. the allowlist below for every other command.
 *
 * A command is read-only-safe only if EVERY segment is. It is a coarse,
 * quote-blind gate on purpose: over-blocking costs a `/change` switch, while
 * one allowlisted writer makes the whole mode decorative (that is why `env`,
 * `find`, `sort`, `fd`, `uniq`, `yq`, `tree` and `wget` are absent — each runs
 * or writes, and each fix below is a measured escape, not a guess).
 *
 * Load-bearing boundary: a leading env assignment (`FOO=bar cmd`) is NOT
 * stripped and classified as `cmd`. `DYLD_INSERT_LIBRARIES=/tmp/x.so git
 * status` plus an allowed `curl -o /tmp/x.so <url>` is write-then-execute
 * inside the mode that promises not to execute anything.
 */

import { splitSegments } from "./shell-parse.ts";

export interface CheckModeDomain {
  /** Domain-guard issues for `command`; empty means read-only-safe. From the
   *  guard's own verb tables — never re-implemented here. */
  issues: (command: string) => string[];
  /** CLIs at least one registered domain guard already vetted. */
  cliNames: ReadonlySet<string>;
}

// ── allowlists ────────────────────────────────────────────────────

const SIMPLE_READ = new Set([
  // file inspection & search
  "cat", "head", "tail", "less", "more", "grep", "rg", "ls", "pwd",
  "file", "stat", "wc", "du", "diff", "comm", "column", "cut", "paste", "tr",
  "jq", "strings", "nm", "objdump", "readelf", "ldd",
  // path & text helpers
  "basename", "dirname", "realpath", "readlink", "echo", "printf", "seq", "test", "true", "false",
  // system info
  // `env`, `find`, `sort`, `fd`, `uniq`, `yq` and `tree` are deliberately
  // absent: each runs a command or writes a file (`env <cmd>`,
  // `find -delete`/`-exec`, `sort -o <file>`, `fd -x`, `uniq`'s second
  // positional, `yq -i`, `tree -o`), which makes a read-only allowlist that
  // contains them decorative. Same for `man` (`man -P <cmd>` runs a pager).
  // Accepted residuals, kept because they need root or a terminal to do damage:
  // `date -s`, `hostname <name>`, `journalctl --vacuum-*`, `ss -K`,
  // `ifconfig <if> down` (root), and `less` (its `s` command saves a file —
  // interactive only). Listed so this comment is not read as a completeness
  // claim.
  "df", "free", "ps", "top", "htop", "printenv", "id", "whoami", "uname", "date", "uptime",
  "hostname", "which", "type", "whereis", "lscpu", "lsmem", "lsblk", "lsusb", "lspci", "vmstat",
  "iostat", "nproc", "getent", "journalctl",
  // network reads
  "ping", "dig", "nslookup", "host", "traceroute", "ss", "netstat", "ifconfig",
]);

const GIT_READ = new Set([
  "status", "log", "diff", "show", "blame", "rev-parse", "ls-files",
  "describe", "shortlog", "grep", "ls-remote", "whatchanged", "count-objects",
]);

/** Read-only verbs for the two-level host CLIs (`gh pr list`, `glab mr view`).
 *  Never add an executing verb here (`run`, `merge`, `cancel`). */
const HOST_READ = new Set(["status", "view", "list", "search", "diff"]);

/** `gh` and `glab` are two-level: `t[1]` is the group (`pr`, `issue`, `ci`), so
 *  the verb is `t[2]`. Checking both is what lets `gh pr list` through while
 *  `gh pr create` stays blocked; the group alone never decides. */
const hostCli = (t: string[]): boolean => HOST_READ.has(t[1] ?? "") || HOST_READ.has(t[2] ?? "");

/** `git branch` listing flags. No positional words: `git branch -D main` and
 *  `git branch new-branch` both write. */
const GIT_BRANCH_LIST = new Set([
  "-a", "--all", "-r", "--remotes", "-v", "-vv", "--verbose", "-l", "--list", "--show-current", "--no-color",
]);

/** `git remote <verb>` subcommands that only read. The rest (add, rename, rm,
 *  prune, set-head, set-branches, set-url, update) mutate. */
const GIT_REMOTE_READ = new Set(["show", "get-url"]);

/** Flags that write a file no matter how read-only the verb is:
 *  `git diff --output=F`, `git log --output=F`. */
const GIT_OUTPUT_FLAG = /^--output(?:=|$)/;

const SUBCOMMAND_READ: Record<string, Set<string> | ((t: string[]) => boolean)> = {
  git: (t) => {
    if (t.some((a) => GIT_OUTPUT_FLAG.test(a))) return false;
    // `git grep -O<cmd>` runs <cmd> as its pager; `--open-files-in-pager` is the
    // long spelling. Same exec-by-argument class as `env`/`find`/`sort`.
    if (t.some((a) => /^-O|^--open-files-in-pager/.test(a))) return false;
    // `git -C <dir> status` and `git -c k=v log`: the global flag's VALUE is not
    // the verb, and `-C` only moves the cwd (it never writes).
    let start = 1;
    while (start < t.length && (t[start] === "-C" || t[start] === "-c")) start += 2;
    const a = t.slice(start);
    const sub = a[0] ?? "";
    // branch/remote/reflog take mutating arguments, so the verb alone is not
    // enough — the argument shape decides.
    if (sub === "branch") return a.length === 1 || a.slice(1).every((x) => GIT_BRANCH_LIST.has(x));
    if (sub === "remote") {
      const listOnly = a.length === 1 || a.slice(1).every((x) => x === "-v" || x === "--verbose");
      return listOnly || GIT_REMOTE_READ.has(a[1] ?? "");
    }
    // `reflog expire` / `reflog delete` drop entries; everything else lists.
    if (sub === "reflog") return a.length === 1 || (a[1] !== "expire" && a[1] !== "delete");
    if (GIT_READ.has(sub)) return true;
    if (sub === "stash") return a[1] === "list";
    if (sub === "tag") return a.length === 1 || a[1] === "-l" || a[1] === "--list";
    if (sub === "config") return a.includes("--get") || a.includes("-l") || a.includes("--list");
    return false;
  },
  docker: (t) => {
    if (t[1] === "compose") return ["ps", "logs", "config", "top", "images"].includes(t[2] ?? "");
    return ["ps", "images", "logs", "inspect", "stats", "top", "version", "info"].includes(t[1] ?? "");
  },
  systemctl: new Set(["status", "list-units", "list-timers", "is-active", "is-enabled", "show", "cat"]),
  npm: new Set(["list", "ls", "outdated", "view", "info", "--version"]),
  pip: new Set(["show", "list", "--version"]),
  pip3: new Set(["show", "list", "--version"]),
  apt: new Set(["list", "show", "policy", "--version"]),
  "apt-cache": new Set(["show", "policy", "search"]),
  dpkg: new Set(["-l", "-s", "--list", "--status", "--version"]),
  gh: hostCli,
  glab: hostCli,
  snap: new Set(["list", "info", "--version"]),
  flatpak: new Set(["list", "info"]),
  mise: new Set(["ls", "list", "current", "which", "registry", "--version"]),
};

/** A short-flag token that makes `curl` a writer: output (`-o`, `-O`, `-D`,
 *  `-c`), upload (`-T`, `-F`) or data (`-d`), attached or clustered
 *  (`-Tsecret.txt`, `-sd@x`, `-sLo/tmp/x`, `-D/tmp/h`), plus `-X`. `-X` mutates
 *  for EVERY method, so `curl -X GET` is refused too: a method flag is never
 *  needed for a plain read. Whole tokens are tested because one spaced regex
 *  missed every attached form. (`-b`/`--cookie` only read, so they pass.)
 *  shortcut: the segment is split on whitespace, so a QUOTED value that itself
 *  starts with a dash (`curl -H "Referer: -o" url`) is a false block — the
 *  safe side; upgrade to a quote-aware tokenizer if that ever bites. */
const CURL_WRITE = /^-[A-Za-z]*(?:[oOTdDcFX]|F@)/;
/** The long spellings of the same flags, bare or `=`-attached. */
const CURL_WRITE_LONG =
  /^--(?:output|remote-name|remote-name-all|upload-file|request|json|post-data|post-file|method|form|form-string|cookie-jar|trace-ascii)(?:=|$)/;
/** `--data` in every spelling (`--data`, `--data-raw`, `--data-ascii`, …): the
 *  family grows, so it is prefix-matched rather than enumerated. */
const CURL_DATA = /^--data/;

/**
 * The `tool_call` decision for one shell command: null to allow, else the
 * block reason. `domain` supplies the guard layer (see the header).
 */
export function checkModeBlock(command: string, domain: CheckModeDomain): string | null {
  // Domain-guarded CLIs (aws, kubectl, terraform, …): defer to the guard's
  // own verb tables — single source of truth for infra read/mutation.
  const issues = domain.issues(command);
  if (issues.length) return issues.join(" ") + " (check mode)";

  const guarded = domain.cliNames;
  // Newlines and a bare `&` split like any other separator: `ls⏎rm -rf x` and
  // `ls & rm -rf x` are two commands, and only the first word of a segment is
  // classified. The lookarounds keep `2>&1` and `&>file` in one segment (the
  // `>` check below still blocks the latter). Quote-blind like the rest of this
  // gate, so a `&` inside a quoted argument over-blocks — the safe side.
  const segments = splitSegments(command).map((s) => s.trim()).filter(Boolean);

  for (const seg of segments) {
    // `<(cmd)` / `>(cmd)` run a command and hand back a path: process substitution
    // is a command runner like `$(…)`, and `cat <(rm -rf x)` has an allowlisted head.
    if (/`|\$\(|[<>]\(/.test(seg)) return `command substitution is blocked in check mode (read-only).`;

    // output redirection mutates files; allow fd redirects and /dev/null
    const noBenignRedir = seg.replace(/\d?>&\d/g, "").replace(/\d?>\s*\/dev\/null/g, "");
    if (noBenignRedir.includes(">")) return `output redirection is blocked in check mode (read-only).`;

    const tokens = seg.split(/\s+/);
    const cmd = tokens[0];
    // `command -v <cli>` / `command -V <cli>` only look the name up; they never
    // run it. (`command <cli>` does run it, so it stays un-allowlisted.)
    if (cmd === "command" && (tokens[1] === "-v" || tokens[1] === "-V")) continue;
    // `rg --pre <cmd>` runs <cmd> as a preprocessor (and `--pre-glob` feeds it);
    // rg stays allowlisted for every other shape.
    if (cmd === "rg" && tokens.some((t) => /^--pre(?:-glob)?(?:=|$)/.test(t))) {
      return `${cmd} --pre runs a program and is blocked in check mode (read-only).`;
    }
    if (guarded.has(cmd)) continue; // already vetted by the domain guard above
    if (SIMPLE_READ.has(cmd)) continue;

    if (cmd === "curl") {
      if (tokens.some((t) => CURL_WRITE.test(t) || CURL_WRITE_LONG.test(t) || CURL_DATA.test(t))) {
        return `${cmd} with upload/mutation/output flags is blocked in check mode (read-only).`;
      }
      continue;
    }

    const rule = SUBCOMMAND_READ[cmd];
    if (rule) {
      const ok = typeof rule === "function" ? rule(tokens) : rule.has(tokens[1] ?? "");
      if (ok) continue;
      return `${cmd} ${tokens[1] ?? ""}: only read-only ${cmd} subcommands are allowed in check mode.`;
    }

    return `${cmd}: not allowlisted in check mode (read-only). Switch to /change for mutations, or ask the user.`;
  }
  return null;
}
