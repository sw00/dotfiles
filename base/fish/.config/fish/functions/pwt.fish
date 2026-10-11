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
# re-running pwt lands back in the same transcript. Caveat: pi-prune-sessions
# drops transcripts untouched for 30 days, so a workstream left idle longer than
# that starts fresh.
#
# Worktrees live under __worktrees/ so they stay inside the trusted path prefix
# (~/.pi/agent/trust.json trusts /Users/sett/src/lelapa) and can be filtered out
# of the sesh/zoxide picker (see the C-f binding in tmux.conf).

function __pwt_main_root
    # --show-toplevel returns the WORKTREE when called from inside one, so a
    # nested pwt would build __worktrees/<a>/__worktrees/<b> and mis-key the
    # session id. The common git dir always points at the main repository.
    set -l common (command git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    or begin; echo "pwt: not inside a git repository" >&2; return 1; end
    command dirname "$common"
end

function __pwt_valid_slug
    string match -qr '^[A-Za-z0-9][A-Za-z0-9._-]*$' -- "$argv[1]"
end

function pwt --description 'pi git-worktree helper (tmux window + pinned session)'
    set -l cmd "$argv[1]"
    switch "$cmd"
        case rm remove
            set -l slug "$argv[2]"
            test -n "$slug"; or begin; echo "usage: pwt rm <slug>" >&2; return 2; end
            __pwt_valid_slug "$slug"; or begin; echo "pwt: invalid slug '$slug'" >&2; return 2; end
            set -l root (__pwt_main_root); or return 1
            set -l wt "$root/__worktrees/$slug"
            test -d "$wt"; or begin; echo "pwt: no worktree at $wt" >&2; return 1; end
            # `worktree remove` refuses only on TRACKED modifications; ignored
            # files (.env, .venv, node_modules) are deleted without a word. Those
            # are exactly the untracked-by-design files a worktree accumulates,
            # so refuse while any are present — losing them must be deliberate.
            set -l ignored (command git -C "$wt" status --porcelain --ignored 2>/dev/null | string match -r '^!!.*')
            if test (count $ignored) -gt 0
                echo "pwt: $wt holds ignored files (.env/.venv/node_modules) — refusing." >&2
                echo "     Remove them yourself first, then re-run: pwt rm $slug" >&2
                return 1
            end
            command git -C "$root" worktree remove "$wt"; and command git -C "$root" branch -d "$slug"
        case help ''
            echo "Usage: pwt <slug> [base] | pwt rm <slug>"
        case '*'
            set -l slug "$argv[1]"
            test -n "$slug"; or begin; echo "pwt: missing slug" >&2; return 2; end
            __pwt_valid_slug "$slug"; or begin
                echo "pwt: invalid slug '$slug' (letters, digits, . _ -)" >&2
                return 2
            end
            set -l base "$argv[2]"
            set -l root (__pwt_main_root); or return 1
            set -l wt "$root/__worktrees/$slug"
            if not test -d "$wt"
                if test -n "$base"
                    # -b is required, not cosmetic: without it git refuses when
                    # <base> is already checked out in another worktree — which is
                    # the common case (your main branch) — and where it does
                    # succeed it leaves a DETACHED head, so the branch that
                    # `pwt rm` deletes never exists. With -b both forms produce a
                    # branch named after the slug, differing only in their base.
                    command git -C "$root" worktree add -b "$slug" "$wt" "$base"; or return 1
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
