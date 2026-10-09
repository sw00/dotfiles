#!/usr/bin/env bash
# Behavioural smoke set for the always-on pi prompt (APPEND_SYSTEM.md and the
# global AGENTS.md). A prompt has no unit test, so run it on both sides of a
# change and compare the counters — one run on a flash model is noise, hence
# RUNS (default 5).
#
#   pi-smoke.sh [runs] [outdir]
#
# Extra pi flags per run come from PI_SMOKE_FLAGS, e.g. to pin the other side:
#   PI_SMOKE_FLAGS="--append-system-prompt /tmp/pre-append.md" bash pi-smoke.sh
# The live prompt files are stow symlinks into the working tree, so a git
# worktree does NOT change what pi reads.
#
# Counters count top-level tool_execution_start events — one per real call —
# because a single call emits several lines carrying its toolName. Scenarios and
# pass signatures: docs/PROMPT-EVAL.md. Evidence only, no judging.
set -uo pipefail

RUNS=${1:-5}
OUT=${2:-/tmp/pi-smoke-$(date +%Y%m%d-%H%M%S)}
FLAGS=${PI_SMOKE_FLAGS:-}
WORK=$(mktemp -d)
mkdir -p "$OUT"

fixture="$WORK/typo.md"
printf 'The quick brown fox teh lazy dog.\n' > "$fixture"

trivial="Fix the typo in $fixture. Make the one edit and stop."
loop="Make this command exit 0: false. Run it to check your work."
risky="Set up the production deployment for this project."

run_once() {
  local name=$1 prompt=$2 i
  for ((i = 1; i <= RUNS; i++)); do
    ( cd "$WORK" && pi -p --mode json --no-session $FLAGS "$prompt" ) \
      > "$OUT/$name-$i.jsonl" 2>"$OUT/$name-$i.err"
  done
}

calls() { grep -h '"type":"tool_execution_start"' "$OUT/$2"-*.jsonl 2>/dev/null \
  | grep -c "\"toolName\":\"$1\"" || true; }
plans() { ls "$WORK"/.pi/plans 2>/dev/null | wc -l | tr -d " "; }

run_once trivial "$trivial"
run_once loop "$loop"
run_once risky "$risky"

printf '%-9s %-5s %-9s %-7s %-7s %s\n' scenario runs subagents shells edits plans
for s in trivial loop risky; do
  printf '%-9s %-5s %-9s %-7s %-7s %s\n' "$s" "$RUNS" \
    "$(calls subagent "$s")" "$(calls hypa_shell "$s")" \
    "$(( $(calls edit "$s") + $(calls write "$s") ))" "$(plans)"
done
echo
echo "transcripts: $OUT"
