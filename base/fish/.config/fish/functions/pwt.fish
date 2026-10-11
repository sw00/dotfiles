# pwt — pi git-worktree: create/reuse a git worktree and open pi in a new tmux
# window there, pinned to a stable session id.
#
# Usage: pwt <slug> [base]   # worktree under <repo>/__worktrees/<slug>
#        pwt rm <slug>       # remove the worktree and its local branch
#
# Why a worktree: several pi sessions in ONE checkout share a working tree, so
# parallel mutating agents collide at the file level. Sessions alone do not fix
# that — git worktrees do, and they are native git rather than a new tool.
#
# Why an explicit session id: resuming "the most recent session for the current
# directory" races as soon as a repo holds more than one session. <repo>-<slug>
# is a stable handle, so closing pi (to authenticate or export vars) and
# re-running pwt lands back in the same transcript.
#
# Worktrees live under __worktrees/ so they stay inside the trusted path prefix
# (~/.pi/agent/trust.json trusts /Users/sett/src/lelapa) and can be filtered out
# of the sesh/zoxide picker (see the C-f binding in tmux.conf).

function __pwt_root
    set -l root (command git rev-parse --show-toplevel 2>/dev/null)
    or begin; echo "pwt: not inside a git repository" >&2; return 1; end
    echo $root
end

function pwt --description 'pi git-worktree helper (tmux window + pinned session)'
    set -l cmd "$argv[1]"
    switch "$cmd"
        case rm remove
            set -l slug "$argv[2]"
            test -n "$slug"; or begin; echo "usage: pwt rm <slug>" >&2; return 2; end
            set -l root (__pwt_root); or return 1
            set -l wt "$root/__worktrees/$slug"
            test -d "$wt"; or begin; echo "pwt: no worktree at $wt" >&2; return 1; end
            # Deliberately unforced: `worktree remove` refuses a dirty tree and
            # `branch -d` refuses an unmerged branch, so losing work needs intent.
            command git -C "$root" worktree remove "$wt"; and command git -C "$root" branch -d "$slug"
        case help ''
            echo "Usage: pwt <slug> [base] | pwt rm <slug>"
        case '*'
            set -l slug "$argv[1]"
            test -n "$slug"; or begin; echo "pwt: missing slug" >&2; return 2; end
            set -l base "$argv[2]"
            set -l root (__pwt_root); or return 1
            set -l wt "$root/__worktrees/$slug"
            if not test -d "$wt"
                if test -n "$base"
                    command git -C "$root" worktree add "$wt" "$base"; or return 1
                else
                    command git -C "$root" worktree add "$wt"; or return 1
                end
            end
            # Per-worktree state does not carry over: .env, .venv, node_modules
            # and `direnv allow` are all keyed by path. Re-allow explicitly.
            set -l sid (basename $root)-$slug
            if set -q TMUX
                tmux new-window -n "$slug" -c "$wt" pi --session-id "$sid"
            else
                echo "pwt: not in tmux — cd $wt && pi --session-id $sid"
            end
    end
end
