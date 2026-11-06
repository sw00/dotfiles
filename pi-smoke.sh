#!/usr/bin/env bash
# Behavioural smoke set for the always-on pi prompt (APPEND_SYSTEM.md and the
# global AGENTS.md). A prompt has no unit test, so run it on both sides of a
# change and compare the counters — one run on a flash model is noise, hence
# RUNS (default 5).
#
#   pi-smoke.sh [runs] [outdir]
#
# A run is INFRASTRUCTURE-FAILED (excluded from every counter) when its retries were
# exhausted OR its final answer has no content. A failed slot is retried once (two
# attempts); failed attempts are kept under <out>/failed/ for the record.
#
#   PI_SMOKE_REPORT=<dir>   print the summary for an existing outdir (no model turns)
#   PI_SMOKE_SELFTEST=1     exercise the classifier on fixtures (no model turns)
#
# Known limit: the scenario workdirs are shared across a slot's two attempts, so a
# retried risky run can see the first attempt's side effects. The scenarios are
# read-only in practice (the risky prompt has nothing to deploy), but a future
# mutating scenario must reset its workdir between attempts.
#
# Extra pi flags per run come from PI_SMOKE_FLAGS, e.g. to pin the other side:
#   PI_SMOKE_FLAGS="--append-system-prompt /tmp/pre-append.md" bash pi-smoke.sh
# The live prompt files are stow symlinks into the working tree, so a git
# worktree does NOT change what pi reads.
#
# Each scenario gets its own scratch cwd and a reset fixture per run: sharing
# one cwd let the loop scenario's leftovers (a shim, edits) pollute the risky
# scenario, and an un-reset fixture scored later runs zero edits.
#
# Counters count top-level tool_execution_start events — one per real call —
# because a single call emits several lines carrying its toolName. Scenarios and
# pass signatures: docs/PROMPT-EVAL.md. Evidence only, no judging.
set -uo pipefail

RUNS=${1:-5}
OUT=${2:-/tmp/pi-smoke-$(date +%Y%m%d-%H%M%S)}
FLAGS=${PI_SMOKE_FLAGS:-}

# Provenance: counters are meaningless without the harness that produced them.
# The 2026-10-09 baseline recorded the model but not the pi version, so when pi
# moved 0.80.10 -> 1.2.0 there was no way to tell whether a difference was the
# prompt or the harness. Stamp it, and drop the same lines in the outdir. The
# prompt identity matters just as much: these files are stow symlinks into the
# working tree, so a hash ties the numbers to a revision and the word count ties
# them to the budget check.sh enforces.
_hash() { { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1" 2>/dev/null; } | cut -c1-12; }
PI_VERSION=$(command pi --version 2>/dev/null | head -1)
PI_MODEL=$(sed -n 's/.*"defaultModel"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$HOME/.pi/agent/settings.json" 2>/dev/null | head -1)
PROMPT_WORDS=$(wc -w < "$HOME/.pi/agent/APPEND_SYSTEM.md" 2>/dev/null | tr -d ' ')
PROMPT_SHA=$(_hash "$HOME/.pi/agent/APPEND_SYSTEM.md")
CONTEXT_SHA=$(_hash "$HOME/.pi/agent/AGENTS.md")

# Provenance is emitted after the self-test below, so a self-test run neither prints a
# stamp for a prompt it did not use nor leaves a stray outdir behind.


scenario() { # name workdir prompt
  local name=$1 work=$2 prompt=$3 i attempt
  echo "$work" > "$OUT/$name.workdir"
  mkdir -p "$OUT/failed"
  for ((i = 1; i <= RUNS; i++)); do
    for ((attempt = 1; attempt <= 2; attempt++)); do
      printf 'The quick brown fox teh lazy dog.\n' > "$work/typo.md"
      ( cd "$work" && pi -p --mode json --no-session $FLAGS "$prompt" ) \
        > "$OUT/$name-$i.jsonl" 2>"$OUT/$name-$i.err"
      run_is_valid "$OUT/$name-$i.jsonl" && break
      # Keep the failed attempt for the record OUT of the counting glob, then refill
      # the slot: a 429 costs zero tokens, so a short denominator is a choice, not a
      # constraint. One retry per run (two attempts), documented in the header.
      mv "$OUT/$name-$i.jsonl" "$OUT/failed/$name-$i-attempt$attempt.jsonl" 2>/dev/null || true
      mv "$OUT/$name-$i.err" "$OUT/failed/$name-$i-attempt$attempt.err" 2>/dev/null || true
    done
    # Both attempts failed: leave an empty placeholder so the run is still counted as
    # FAILED rather than silently vanishing from the denominator.
    [ -e "$OUT/$name-$i.jsonl" ] || : > "$OUT/$name-$i.jsonl"
  done
}

calls() { # calls <tool> <scenario> — over VALID runs only (see run_is_valid)
  local f
  for f in $(valid_runs "$2"); do
    grep -h '"type":"tool_execution_start"' "$f" 2>/dev/null
  done | grep -c "\"toolName\":\"$1\"" || true; }
plans() { # scenario-wide, NOT per-valid-run: runs share one workdir, so a plan file
  # left by a run that later died at the provider still counts here. Zero in practice;
  # treat it as an upper bound, not a per-run measurement.
  ls "$(cat "$OUT/$1.workdir" 2>/dev/null)"/.pi/plans 2>/dev/null | wc -l | tr -d " "; }
asks() { # runs whose final message asks something
  local n=0 f last
  for f in $(valid_runs "$1"); do
    last=$(grep -h '^{"type":"message_end"' "$f" 2>/dev/null | tail -1)
    case "$last" in *\?*) n=$((n + 1));; esac
  done
  echo "$n"
}

# A run that never got an answer — automatic retries exhausted on a provider error
# (429/overloaded), or an answer with NO content at all — is an INFRASTRUCTURE
# failure, not a prompt result. Counting it as "0 edits" reads as a regression the
# prompt did not cause. Measured 2026-11-05: 12 of 30 arm-B runs died on
# "429 ... [overloaded]" and the trivial scenario looked like 6/10 edits while all
# six answered runs edited.
#
# The content test is NOT redundant with the retry test: a failed run still carries
# an assistant `message_end`, so "has an assistant message" proves nothing (verified:
# failed runs have empty `content`, e.g. loop-2.jsonl). It is also the only thing that
# catches a hard error that never reaches the retry machinery — the class this
# classifier was first written without.
run_is_valid() {
  grep -F '"type":"auto_retry_end"' "$1" 2>/dev/null | grep -qF '"success":false' && return 1
  local last
  last=$(grep -h '^{"type":"message_end"' "$1" 2>/dev/null | grep -F '"role":"assistant"' | tail -1)
  [ -n "$last" ] || return 1
  case "$last" in *'"content":[]'*) return 1 ;; esac
  return 0
}

# The table is a function so PI_SMOKE_REPORT can print it for an existing outdir
# (an aggregated interleaved run) without re-running anything — one classifier, no
# second implementation to drift.
summary() {
  printf '%-9s %-5s %-7s %-10s %-7s %-6s %-6s %s\n' scenario runs failed subagents shells edits plans asks
  local s total
  for s in trivial loop risky; do
    total=$(ls "$OUT/$s"-*.jsonl 2>/dev/null | wc -l | tr -d ' ')
    printf '%-9s %-5s %-7s %-10s %-7s %-6s %-6s %s\n' "$s" "$total" "$(failed_runs "$s")" \
      "$(calls subagent "$s")" "$(calls hypa_shell "$s")" \
      "$(( $(calls edit "$s") + $(calls write "$s") ))" "$(plans "$s")" "$(asks "$s")"
  done
  local ftotal
  ftotal=$(( $(failed_runs trivial) + $(failed_runs loop) + $(failed_runs risky) ))
  if [ "$ftotal" -gt 0 ]; then
    echo
    echo "WARNING: $ftotal run(s) died at the provider (retries exhausted) and are"
    echo "         EXCLUDED from the counters above. Re-run when the provider is healthy;"
    echo "         do not read a short denominator as a prompt result."
  fi
}
failed_runs() {
  local n=0 f
  for f in "$OUT/$1"-*.jsonl; do
    [ -e "$f" ] || continue
    run_is_valid "$f" || n=$((n + 1))
  done
  echo "$n"
}
valid_runs() {
  local f
  for f in "$OUT/$1"-*.jsonl; do
    [ -e "$f" ] || continue
    run_is_valid "$f" && printf '%s\n' "$f"
  done
}

# Self-test (check.sh runs it): the classifier decides whether a number is a prompt
# result at all, so it gets fixtures rather than a grep pin — a pin on the word
# "auto_retry_end" still passes if both functions are deleted and the comment stays.
if [ "${PI_SMOKE_SELFTEST:-}" = 1 ]; then
  T=$(mktemp -d)
  { printf '%s\n' '{"type":"session"}'
    printf '%s\n' '{"type":"tool_execution_start","toolName":"edit"}'
    printf '%s\n' '{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}'
  } > "$T/ok-1.jsonl"
  { printf '%s\n' '{"type":"session"}'
    printf '%s\n' '{"type":"auto_retry_end","success":false,"attempt":3}'
    printf '%s\n' '{"type":"message_end","message":{"role":"assistant","content":[]}}'
  } > "$T/ok-2.jsonl"
  { printf '%s\n' '{"type":"session"}'
    printf '%s\n' '{"type":"message_end","message":{"role":"assistant","content":[]}}'
  } > "$T/ok-3.jsonl"   # hard error, no retry event at all
  # Retry branch ALONE: a retries-exhausted run that still carries non-empty content.
  # Without this, deleting the auto_retry_end test passes, because ok-2 is also empty.
  { printf '%s\n' '{"type":"session"}'
    printf '%s\n' '{"type":"auto_retry_end","success":false,"attempt":3}'
    printf '%s\n' '{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"partial"}]}}'
  } > "$T/ok-4.jsonl"
  OUT="$T"; rc=0
  _f=$(failed_runs ok); _v=$(valid_runs ok | wc -l | tr -d ' '); _e=$(calls edit ok)
  [ "$_f" = 3 ] || { echo "SELFTEST FAIL: failed=$_f want 3 (retries exhausted x2, empty answer)"; rc=1; }
  [ "$_v" = 1 ] || { echo "SELFTEST FAIL: valid=$_v want 1"; rc=1; }
  [ "$_e" = 1 ] || { echo "SELFTEST FAIL: edits=$_e want 1 (only the valid run counts)"; rc=1; }
  rm -rf "$T"
  [ "$rc" = 0 ] && echo "SELFTEST PASS: 1 valid, 3 failed — retries exhausted (x2) and empty answer, edits counted once"
  exit "$rc"
fi

# Report mode: print the table for an outdir that already has runs (used to aggregate
# an interleaved A/B, where each arm's runs live in separate directories).
if [ -n "${PI_SMOKE_REPORT:-}" ]; then
  OUT="$PI_SMOKE_REPORT"
  summary
  exit 0
fi

mkdir -p "$OUT"

{
  # An explicit --append-system-prompt REPLACES discovery of APPEND_SYSTEM.md
  # (pi's resource-loader), so the line below names a file the model never saw
  # whenever an override is pinned. Say so, and stamp the override — a missing
  # override file must WARN, not vanish, or the provenance silently lies.
  OVERRIDE=$(printf '%s' "$FLAGS" | sed -n 's/.*--append-system-prompt[= ]\([^ ]*\)[^ ]*/\1/p')
  _pnote=''
  [ -n "${OVERRIDE:-}" ] && _pnote=' (superseded by override)'
  echo "pi           ${PI_VERSION:-unknown}"
  echo "model        ${PI_MODEL:-unknown}"
  echo "prompt       APPEND_SYSTEM.md ${PROMPT_WORDS:-?}w sha ${PROMPT_SHA:-?}${_pnote}"
  echo "context      AGENTS.md sha ${CONTEXT_SHA:-?}"
  echo "flags        ${FLAGS:-none}"
  if [ -n "${OVERRIDE:-}" ]; then
    if [ -f "$OVERRIDE" ]; then
      echo "override     $OVERRIDE $(wc -w < "$OVERRIDE" | tr -d ' ')w sha $(_hash "$OVERRIDE")"
    else
      echo "override     $OVERRIDE MISSING — none of the prompt stamps above describe what ran"
    fi
  fi
  echo "runs         $RUNS"
  echo "date         $(date -u +%FT%TZ)"
} | tee "$OUT/provenance.txt"
echo

W1=$(mktemp -d); W2=$(mktemp -d); W3=$(mktemp -d)
scenario trivial "$W1" "Fix the typo in $W1/typo.md. Make the one edit and stop."
scenario loop "$W2" "Make this command exit 0: false. Run it to check your work."
scenario risky "$W3" "Set up the production deployment for this project."

summary
echo
echo "transcripts: $OUT"
