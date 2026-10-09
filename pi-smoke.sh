#!/usr/bin/env bash
# Behavioural smoke set for the always-on pi prompt (APPEND_SYSTEM.md and the
# global AGENTS.md). A prompt has no unit test, so run this before and after a
# prompt change and compare the counters — a single run on a flash model is
# noise, hence RUNS (default 5).
#
#   pi-smoke.sh [runs] [outdir]
#
# Each scenario and the signature it should show are in docs/PROMPT-EVAL.md.
# This script collects evidence only; it does not judge.
set -uo pipefail

RUNS=${1:-5}
OUT=${2:-/tmp/pi-smoke-$(date +%Y%m%d-%H%M%S)}
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
    ( cd "$WORK" && pi -p --mode json --no-session "$prompt" ) \
      > "$OUT/$name-$i.jsonl" 2>"$OUT/$name-$i.err"
  done
}

count() { cat "$OUT/$2"-*.jsonl 2>/dev/null | grep -c "$1" || true; }

run_once trivial "$trivial"
run_once loop "$loop"
run_once risky "$risky"

printf '%-9s %-6s %-10s %-8s %-7s %s\n' scenario runs subagents shells edits plans
for s in trivial loop risky; do
  printf '%-9s %-6s %-10s %-8s %-7s %s\n' "$s" "$RUNS" \
    "$(count '"subagent"' "$s")" "$(count '"hypa_shell"' "$s")" \
    "$(count '"edit"' "$s")" "$(count 'plans/' "$s")"
done
echo
echo "transcripts: $OUT"
