# pwt — pi git-worktree: create/reuse a git worktree and open pi there, in a
# tmux window pinned to a stable session id. An open window for the worktree is
# REUSED rather than duplicated (see __pwt_open_window).
#
# Usage: pwt <slug> [base]   # worktree under <repo>/__worktrees/<slug>
#        pwt rm <slug>       # remove the worktree and its local branch
#        pwt jump <dir>      # go to the window whose cwd is <dir> (C-w panel)
#        pwt here <label>    # a workstream in THIS checkout, no worktree
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
# (~/.pi/agent/trust.json trusts the source-tree prefix) and can be filtered out
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

# Canonical form of a directory, for path comparison only. tmux reports the
# RESOLVED path (a window opened with -c /tmp shows /private/tmp), and git hands
# back a canonical toplevel, so a checkout reached through any symlinked parent
# would compare unequal to itself — and pwt would open a SECOND pi on the same
# transcript. repo-list carries the same lesson for the same reason.
function __pwt_realpath --description 'canonical path for comparison'
    if not test -d "$argv[1]"
        echo "$argv[1]"
        return 0
    end
    # `cd` inside a command substitution runs in THIS shell (fish does not fork
    # for it), so the caller must be put back: otherwise `pwt rm` strands the
    # shell inside the directory it just deleted, and `pwt <slug>` drags it into
    # whatever path was compared last.
    set -l here $PWD
    set -l resolved ''
    cd -- "$argv[1]"; and set resolved (command pwd -P)
    # Guarded: `cd` to a directory that has since vanished would otherwise print a
    # stray error to the caller's terminal.
    test -d "$here"; and cd -- "$here"
    test -n "$resolved"; or set resolved "$argv[1]"
    echo $resolved
end

# pi titles its window "<APP_TITLE> - [<session name> - ]<cwd basename>" (dist:
# modes/interactive/interactive-mode.js), which is the only reliable way to say
# "this pane is pi": pane_current_command is `node` for pi and for every other
# node program. pwt-pick keeps an identical default, and check.sh asserts the two
# agree so a rename cannot update one and miss the other.
function __pwt_pi_title --description 'pi window-title prefix'
    # -n, not just set: PWT_PI_TITLE="" would otherwise make every window
    # count as pi.
    if test -n "$PWT_PI_TITLE"
        echo $PWT_PI_TITLE
    else
        echo 'π - '
    end
end

# Attach the OSC 7501 state tap to <pane> (pwt-osc mirrors pi's working/blocked/
# done/error reports into @pi_state/@pi_alert for the status line).
#
# The command string is a strftime TEMPLATE before it is a format string — tmux
# calls format_expand_time on it (cmd-pipe-pane.c) — so a literal pane id like %3
# is mangled into "3", and every `tmux -t 3` afterwards silently targets WINDOW
# index 3 instead of the pane. `#{pane_id}` contains no %, so it survives that pass
# and is expanded after it. This held for tmux 3.4 as well, so the fix is not
# version-specific.
#
# Plain pipe-pane, NEVER `-o`: tmux closes an existing pipe before evaluating -o,
# so a second call would DETACH the tap rather than no-op.
function __pwt_tap --description 'attach the pwt-osc state tap to <pane>'
    set -l pane $argv[1]
    test -n "$pane"; or return 1
    # A pipe-pane job inherits the SERVER's environment, and that $TMUX can be
    # stale (verified: a server started with -S still handed jobs the DEFAULT
    # socket), so pin the socket this pwt is talking to.
    set -l sock (string split -m1 ',' -- "$TMUX")[1]
    command tmux pipe-pane -t "$pane" "exec env TMUX=$sock $HOME/bin/pwt-osc #{pane_id}"
end

# The window holding <path>, or nothing. Options:
#   pi-only  accept only a window actually running pi — a plain shell cd'd into the
#            worktree is not a workstream, though it IS enough to block removal
#   in-tree  also accept a pane whose cwd is anywhere BENEATH <path>
#
# Compared against the ONCE-canonicalised target. tmux already reports resolved
# pane cwds (a window opened at /tmp shows /private/tmp) while git hands back the
# path as given, so canonicalising the TARGET is what makes the two meet — whereas
# canonicalising each PANE would fire fish's PWD-change event per pane, which
# direnv hooks on, for every pane on the server.
function __pwt_window_for --description 'window (or pane) id at <path>; opts: pi-only, in-tree, pane-id'
    set -l want (__pwt_realpath "$argv[1]")
    set -l pi_only 0
    set -l in_tree 0
    set -l out_pane 0
    for opt in $argv[2..-1]
        switch $opt
            case pi-only
                set pi_only 1
            case in-tree
                set in_tree 1
            case pane-id
                set out_pane 1
        end
    end
    # list-PANES, not list-windows: the latter reports only the ACTIVE pane's cwd,
    # so pi running in a split that is not the active pane would be missed and
    # pwt would spawn the duplicate session this function exists to prevent.
    # Parsed here rather than with `list-panes -f`, which needs a newer tmux than
    # the apt 3.4 a degraded WSL launch can put on PATH.
    for line in (command tmux list-panes -a -F '#{window_id}|#{pane_id}|#{pane_current_path}' 2>/dev/null)
        # -m2, so a path containing '|' stays in the last field intact.
        set -l parts (string split -m2 '|' -- $line)
        test (count $parts) -eq 3; or continue
        set -l hit 0
        if test "$parts[3]" = "$want"
            set hit 1
        else if test $in_tree -eq 1; and string match -q "$want/*" -- "$parts[3]"
            set hit 1
        end
        test $hit -eq 1; or continue
        if test $pi_only -eq 1
            # Addressed by PANE id: display-message -t <window id> resolves to the
            # window's ACTIVE pane, which is a different pane whenever pi shares
            # its window with anything else.
            set -l title (command tmux display-message -p -t "$parts[2]" '#{pane_title}' 2>/dev/null)
            string match -q (__pwt_pi_title)'*' -- "$title"; or continue
        end
        # ...and return the WINDOW id (what select-window wants), or the PANE id
        # when the caller is going to attach a tap to it.
        if test $out_pane -eq 1
            echo $parts[2]
        else
            echo $parts[1]
        end
        return 0
    end
    return 1
end

# The window that DECLARES workstream <sid>, or nothing. pwt records @pwt_sid on
# every window it opens, which makes this the identity check: two in-place
# workstreams share one directory, so a cwd cannot tell them apart, and matching on
# it would hand the second one the first one's window — and with it the first one's
# transcript. Path matching stays the fallback for windows that predate the marker
# and for sessions adopted from the panel.
function __pwt_workstream_window --description 'window id declaring workstream <sid>'
    set -l out_pane 0
    test "$argv[2]" = pane-id; and set out_pane 1
    for line in (command tmux list-windows -a -F '#{window_id}|#{pane_id}|#{@pwt_sid}' 2>/dev/null)
        set -l parts (string split -m2 '|' -- $line)
        test (count $parts) -eq 3; or continue
        test "$parts[3]" = "$argv[1]"; or continue
        if test $out_pane -eq 1
            echo $parts[2]
        else
            echo $parts[1]
        end
        return 0
    end
    return 1
end

# Record a window as the home of a workstream. A window option, not something
# inferred from the pane's cwd, because the cwd cannot separate two in-place
# sessions — and because the C-w panel labels its rows from @pwt_label.
function __pwt_mark --description 'record the workstream sid and label on a pane window'
    command tmux set-window-option -t "$argv[1]" @pwt_sid "$argv[2]" 2>/dev/null
    command tmux set-window-option -t "$argv[1]" @pwt_label "$argv[3]" 2>/dev/null
end

# select-window only moves within the current session; a worktree window in
# another session needs the client moved first, or the jump looks like a no-op.
function __pwt_jump_to --description 'select <window id>, moving session if needed'
    set -l wid $argv[1]
    set -l target (command tmux display-message -p -t "$wid" '#{session_name}' 2>/dev/null)
    set -l current (command tmux display-message -p '#{session_name}' 2>/dev/null)
    if test -n "$target"; and test "$target" != "$current"
        command tmux switch-client -t "$target" 2>/dev/null
    end
    command tmux select-window -t "$wid"
end

# Open the worktree as a tmux window — or, if one already holds it, go there
# instead. Reusing is not cosmetic: a second pi on the same --session-id resumes
# the SAME transcript JSONL (dist: main.js opens the existing session), and pi
# rewrites that file from its own in-memory tree on branch/migration
# (session-manager.js _rewriteFile), so two writers silently clobber each other's
# turns. There is no session lock to catch it for us.
#   Reuse is matched by pane CWD, so a pi whose pane sits in a subdirectory of the
# worktree is not recognised and would be duplicated. pwt always opens pi AT the
# worktree root, so that only arises for a pi started by hand deeper in the tree.
function __pwt_open_window --description 'jump to a workstream window, else open pi in <dir>'
    set -l dir $argv[1]
    set -l label $argv[2]
    set -l sid $argv[3]
    # Identity first, path second. A window that DECLARES this workstream is the
    # right one even when another window shares its directory, which is the whole
    # point of the marker.
    set -l wid (__pwt_workstream_window "$sid")
    # The PATH fallback is for worktrees only, where the directory IS the workstream
    # and a window sitting in it is the workstream window (it still catches windows
    # opened before pwt wrote the marker). For an in-place workstream the directory
    # is shared, so a pi window found there may belong to a DIFFERENT in-place
    # workstream: falling back would land the new label in that window and it would
    # never exist as a workstream at all — silently, since the jump succeeds. So
    # in-place is identity or nothing.
    if test -z "$wid"; and test "$argv[4]" != identity-only
        set wid (__pwt_window_for "$dir" pi-only)
    end
    if test -n "$wid"
        # Say so: `pwt foo` that creates nothing looks like it failed.
        __pwt_jump_to "$wid"
        or begin; echo "pwt: could not select window $wid for $label" >&2; return 1; end
        echo "pwt: jumped to the open window for $label"
        return 0
    end
    # -P -F yields the pane we just made, so marking and tapping it need no racy
    # search (pi has not set its window title yet at this point).
    set -l pane (command tmux new-window -P -F '#{pane_id}' -n "$label" -c "$dir" pi --session-id "$sid")
    or return 1
    command tmux select-window -t "$pane" 2>/dev/null
    __pwt_mark "$pane" "$sid" "$label"
    __pwt_tap "$pane"
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
            # A worktree a window still holds is IN USE: removing it pulls the
            # directory out from under a running pi. Killing that window is its
            # own deliberate act (C-a C-x), so refuse and name what is open.
            # in-tree, not exact: pi whose pane has cd'd into a subdirectory of the
            # worktree is just as much in the way, and deleting the tree under it
            # leaves that shell sitting in a directory that no longer exists.
            # Deliberately NOT gated on $TMUX: `pwt rm` run from a plain terminal
            # while pi works in tmux is exactly when this matters. With no
            # reachable server the lookup returns empty, which is correct.
            set -l live (__pwt_window_for "$wt" in-tree)
            if test -n "$live"
                echo "pwt: window $live still holds $wt" >&2
                echo "     close it first: tmux kill-window -t $live" >&2
                return 1
            end
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
            echo "Usage: pwt <slug> [base] | pwt rm <slug> | pwt jump <dir> | pwt here <label>"
        case jump
            # Used by the C-w panel for rows that are live pi sessions rather
            # than worktrees: there is nothing to create, only a window to find.
            set -l dir "$argv[2]"
            test -n "$dir"; or begin; echo "usage: pwt jump <dir>" >&2; return 2; end
            set -q TMUX; or begin; echo "pwt: not in tmux" >&2; return 1; end
            set -l pane (__pwt_window_for "$dir" pi-only pane-id)
            set -l wid (__pwt_window_for "$dir" pi-only)
            test -n "$wid"; or begin; echo "pwt: no pi window with cwd $dir" >&2; return 1; end
            # Arriving at a session from the panel ADOPTS it, so state coverage
            # grows by use rather than needing a `pi` wrapper — which subagent would
            # trip, since it spawns pi as a child and would re-tap the parent pane.
            __pwt_tap "$pane"
            __pwt_jump_to "$wid"
        case here
            # A workstream in THIS checkout, with no worktree: same window naming,
            # same tap, same pinned session id. This is the fallback for repos where
            # a fresh checkout cannot be materialised — a git-crypt repo fails
            # `worktree add` at the smudge filter, and the new tree would need its
            # own key unlock anyway — or where it is not worth the provisioning:
            # .env, .venv, node_modules and `direnv allow` are keyed by path and do
            # not carry over. Isolation is the entire point of a worktree, so two
            # in-place workstreams in one repo share a working tree: they must not
            # be mutating the same files at the same time.
            set -l label "$argv[2]"
            test -n "$label"; or begin; echo "usage: pwt here <label>" >&2; return 2; end
            test -z "$argv[3]"; or begin
                echo "pwt: 'pwt here' takes no base ref — there is no worktree to base" >&2
                return 2
            end
            __pwt_valid_slug "$label"; or begin
                echo "pwt: invalid label '$label' (letters, digits, . _ -)" >&2
                return 2
            end
            set -l dir (__pwt_main_root); or return 1
            set -l sid (basename $dir)-$label
            if set -q TMUX
                # identity-only: see __pwt_open_window — a shared directory cannot
                # identify an in-place workstream.
                __pwt_open_window "$dir" "$label" "$sid" identity-only
            else
                echo "pwt: not in tmux — pi --session-id $sid"
            end
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
                __pwt_open_window "$wt" "$slug" "$sid"
            else
                echo "pwt: not in tmux — cd $wt && pi --session-id $sid"
            end
    end
end
