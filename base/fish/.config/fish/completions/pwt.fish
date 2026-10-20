# Completions for pwt — pi workstreams (git worktree + tmux window + pinned session).
#
# Verbs at the first position, then the workstream slugs of the repo around $PWD:
# a bare `pwt <slug>` only ever addresses THIS repo's worktrees, so offering the
# others would be offering a name that cannot resolve. `rm` takes a slug too;
# `jump` takes a DIRECTORY (file completion re-enabled); `here` takes a free-form
# label, which nothing here can guess.
#
# Fish's helper functions (__fish_use_subcommand, __fish_seen_subcommand_from) are
# autoloaded from fish's own data directory, so this file also works under
# `fish --no-config`, which is how check.sh exercises it.

function __fish_pwt_worktrees
    # Via the COMMON git dir, never --show-toplevel: called from inside a worktree,
    # --show-toplevel answers with the worktree itself and the list would be empty.
    set -l common (command git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    or return
    set -l wt (command dirname -- $common)/__worktrees
    test -d "$wt"; or return
    for d in $wt/*/
        # An unmatched glob arrives literally; only real directories are slugs.
        test -d "$d"; or continue
        command basename -- $d
    end
end

complete -c pwt -f

complete -c pwt -n __fish_use_subcommand -a help -d 'usage'
complete -c pwt -n __fish_use_subcommand -a ls -d 'list workstreams and live sessions'
complete -c pwt -n __fish_use_subcommand -a rm -d 'remove a worktree and its branch'
complete -c pwt -n __fish_use_subcommand -a here -d 'a workstream in THIS checkout, no worktree'
complete -c pwt -n __fish_use_subcommand -a jump -d 'go to the pi window at a directory'
complete -c pwt -n __fish_use_subcommand -a close -d 'end a live workstream: close its pi window'
complete -c pwt -n __fish_use_subcommand -a '(__fish_pwt_worktrees)' -d workstream

complete -c pwt -n '__fish_seen_subcommand_from rm' -a '(__fish_pwt_worktrees)' -d workstream
complete -c pwt -n '__fish_seen_subcommand_from jump close' -F
