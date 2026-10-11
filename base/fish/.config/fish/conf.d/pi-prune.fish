# pi-prune — prune pi session transcripts at most once a day.
#
# pi writes every tool result into ~/.pi/agent/sessions/<project>/*.jsonl, so a
# credential that a command printed stays on disk indefinitely. Each worktree
# also adds a session directory keyed by a path that stops existing when the
# worktree is removed, orphaning its transcripts. pi has no retention setting of
# its own, so pruning has to happen out here (see pi-prune-sessions.fish).
#
# Interactive shells only: non-interactive shells (VSCodium server, scripts)
# have no business pruning. The bare mkdir is an atomic lock, so two shells
# starting at once race on the lock rather than both pruning. A lock older than
# 10 minutes is debris from a killed shell and is reaped — without that, a single
# SIGKILL would shut the gate permanently and silently.
#
# The prune runs in the foreground: it is a find/du/delete over a local
# directory, so paying it once a day on a shell that is starting anyway is
# cheaper than the bookkeeping needed to background it and release the lock.
status --is-interactive; or return

set -l _dir "$HOME/.cache/pi-prune"
command mkdir -p "$_dir"
set -l _stamp "$_dir/last"

if test -d "$_dir/lock"
    command find "$_dir/lock" -maxdepth 0 -mmin +10 -exec rmdir {} + 2>/dev/null
end

if command mkdir "$_dir/lock" 2>/dev/null
    # Portable age gate: `find -mmin` behaves the same on BSD and GNU, and needs
    # neither `path mtime` (fish >= 3.5) nor date arithmetic.
    set -l _stale (command find "$_stamp" -maxdepth 0 -mmin +1440 2>/dev/null)
    if not test -f "$_stamp"; or test (count $_stale) -gt 0
        # Only a successful prune is recorded: a failure must be retried on the
        # next shell rather than masked for a day.
        if pi-prune-sessions 30 >/dev/null 2>&1
            touch "$_stamp"
        end
    end
    command rmdir "$_dir/lock" 2>/dev/null
end
