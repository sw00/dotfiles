# pi-prune — prune pi session transcripts at most once a day, in the background.
#
# pi writes every tool result into ~/.pi/agent/sessions/<project>/*.jsonl, so a
# credential that a command printed stays on disk indefinitely. Each worktree
# also adds a session directory keyed by a path that stops existing when the
# worktree is removed, orphaning its transcripts. pi has no retention setting of
# its own, so pruning has to happen out here (see pi-prune-sessions.fish).
#
# Interactive shells only: non-interactive shells (VSCodium server, scripts)
# have no business pruning. The bare mkdir is an atomic lock, so two shells
# starting at once race on the lock rather than both running the prune. WSL is
# skipped because process spawn there is the documented slow path and the prune
# is never urgent.
status --is-interactive; or return
if string match -qi '*microsoft*' (uname -r 2>/dev/null)
    return
end

set -l _dir "$HOME/.cache/pi-prune"
command mkdir -p "$_dir"
set -l _stamp "$_dir/last"
if command mkdir "$_dir/lock" 2>/dev/null
    # No stamp yet → treat as maximally old so the first interactive shell primes it.
    set -l _age 999999
    if test -f "$_stamp"
        set _age (math (date +%s) - (path mtime -- "$_stamp"))
    end
    if test $_age -gt 86400
        pi-prune-sessions 30 >/dev/null 2>&1
        touch "$_stamp"
    end
    command rmdir "$_dir/lock"
end
