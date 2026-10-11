# pi-prune-sessions — delete pi session transcripts older than N days.
#
# Why: pi writes every tool result into ~/.pi/agent/sessions/<project>/*.jsonl,
# so any command that prints a credential leaves it on disk indefinitely. pi
# itself has no retention setting (only sessionDir / PI_CODING_AGENT_SESSION_DIR),
# so trimming has to happen out here.
#
# MANUAL ONLY — never schedule this. The transcripts are the only source for
# session review and for the /usage dashboard (which reads this directory), so
# deleting them must stay an explicit, deliberate act. A conf.d scheduler was
# added and removed on 2026-10-11; check.sh now tombstones its absence.
#
# Usage: pi-prune-sessions [days]      # default 30
function pi-prune-sessions --description 'Prune pi session transcripts older than N days'
    set -l days 30
    if test (count $argv) -ge 1
        set days $argv[1]
    end
    if not string match -qr '^[0-9]+$' -- $days
        echo "pi-prune-sessions: days must be a non-negative integer" >&2
        return 2
    end

    set -l dir "$HOME/.pi/agent/sessions"
    if not test -d "$dir"
        echo "pi-prune-sessions: no session directory at $dir" >&2
        return 1
    end

    set -l before (du -sh "$dir" 2>/dev/null | awk '{print $1}')
    set -l doomed (find "$dir" -type f -name '*.jsonl' -mtime +$days)
    set -l n (count $doomed)

    if test $n -eq 0
        echo "pi-prune-sessions: nothing older than $days days (sessions: $before)"
        return 0
    end

    find "$dir" -type f -name '*.jsonl' -mtime +$days -delete
    find "$dir" -mindepth 1 -type d -empty -delete 2>/dev/null
    set -l after (du -sh "$dir" 2>/dev/null | awk '{print $1}')
    echo "pi-prune-sessions: deleted $n transcript(s) older than $days days ($before -> $after)"
end
