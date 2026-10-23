# pwt — pi git-worktree: create/reuse a git worktree and open pi there, in a
# tmux window pinned to a stable session id. An open window for the worktree is
# REUSED rather than duplicated (see __pwt_open_window).
#
# Usage: pwt <slug> [base]   # worktree under <repo>/__worktrees/<slug>
#        pwt rm <slug>       # remove the worktree and its local branch
#        pwt jump <dir>      # go to the window whose cwd is <dir> (C-w panel)
#        pwt here <label>    # a workstream in THIS checkout, no worktree
#        pwt ls              # list workstreams (the C-w panel's rows)
#        pwt reload [--force] <dir>  # re-exec pi there with the current secrets env
#        pwt revive [--dry-run] <dir>...  # re-open pi in a worktree a restore left bare
#
# Why a worktree: several pi sessions in ONE checkout share a working tree, so
# parallel mutating agents collide at the file level. Sessions alone do not fix
# that — git worktrees do, and they are native git rather than a new tool.
#
# Why an explicit session id: resuming "the most recent session for the current
# directory" races as soon as a repo holds more than one session. <repo>-<slug>
# is a stable handle, so closing pi (to authenticate or export vars) and
# re-running pwt lands back in the same transcript. Caveat: pi-prune-sessions
# (MANUAL only — never scheduled) drops transcripts untouched for 90 days, so a
# workstream left idle longer than that starts fresh once you actually run it.
#
# Worktrees live under __worktrees/ so they stay inside the trusted path prefix
# (~/.pi/agent/trust.json trusts the source-tree prefix) and can be filtered out
# of the sesh/zoxide picker (see the C-f binding in tmux.conf).

# An ARGUMENT is a directory to resolve instead of the caller's cwd: __pwt_open_window
# holds the workstream's own path, not a cwd. `git -C` keeps the common-dir rule
# identical for both callers, so a worktree still resolves to the MAIN repo.
function __pwt_main_root
    set -l where
    test -n "$argv[1]"; and set where -C "$argv[1]"
    # --show-toplevel returns the WORKTREE when called from inside one, so a
    # nested pwt would build __worktrees/<a>/__worktrees/<b> and mis-key the
    # session id. The common git dir always points at the main repository.
    set -l common (command git $where rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
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
#
# `path resolve` and NOT a `cd …; pwd -P` round trip. A fish function runs in the
# CALLER's process, so cd'ing here fired a PWD-change event on every comparison (direnv
# hooks PWD) and the shell then had to be put back — bookkeeping whose failure mode was
# a shell stranded in a deleted directory. The builtin also leaves a nonexistent path
# as given and prints nothing for an empty one, which is what the hand-written guard
# was there to do. It resolves `..` lexically after following links, so a caller passing
# `..` behind a symlink can disagree with the kernel; every real caller hands over an
# absolute path from tmux or git, where the two agree.
function __pwt_realpath --description 'canonical path for comparison'
    path resolve -- "$argv[1]"
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
function __pwt_window_for --description 'window (or pane) id at <path>; opts: pi-only, in-tree, pane-id, no-worktrees'
    set -l want (__pwt_realpath "$argv[1]")
    set -l pi_only 0
    set -l in_tree 0
    set -l out_pane 0
    set -l no_wt 0
    for opt in $argv[2..-1]
        switch $opt
            case pi-only
                set pi_only 1
            case in-tree
                set in_tree 1
            case pane-id
                set out_pane 1
            case no-worktrees
                set no_wt 1
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
        # A worktree root's __worktrees/ holds DIFFERENT workstreams, so a check that
        # means "the checkout itself" (the in-place collision warning) must not be
        # answered by a sibling worktree's pi.
        if test $no_wt -eq 1; and string match -q -- "$want/__worktrees/*" "$parts[3]"
            continue
        end
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

# The window that DECLARES workstream <sid> at <dir>, or nothing. pwt records the
# identity on every window it opens, which makes this the identity check: two
# in-place workstreams share one directory, so a cwd cannot tell them apart, and
# matching on it would hand the second one the first one's window — and with it the
# first one's transcript. Path matching stays the fallback for sessions adopted from
# the panel.
#
# TWO TIERS, sid+dir then unmarked-windows-by-cwd. Not sid alone: the
# basename-derived sid is shared by two repos with the same name and by `here` vs
# worktree of the same name, so matching it without a directory teleports the user
# into the other workstream — and reports success. The second tier exists only for
# windows opened before @pwt_dir was written, and it is restricted twice over: the
# window must have no @pwt_dir, AND its pane cwd must sit in the workstream's tree.
# An unconditional sid match would hand a legacy `here` window to the same-named
# worktree (and vice versa); no cwd evidence at all would let a legacy window whose
# pi has since cd'd outside the tree be duplicated, which is the transcript clobber.
# In-tree, not exact, for the same reason `pwt rm` uses it: one `cd` into a
# subdirectory must not turn the window invisible.
#
# list-PANES, not list-windows: both formats answer with the ACTIVE pane's cwd, so a
# legacy window with pi in a non-active split would look absent — and a `here`
# workstream is identity-only, with no path fallback behind it, so the miss would
# open a second pi on one session id, which is the at-clobber this exists to avoid.
function __pwt_workstream_window --description 'window id declaring workstream <sid> at <dir>'
    set -l want_dir ''
    test -n "$argv[2]"; and set want_dir (__pwt_realpath "$argv[2]")
    test -n "$want_dir"; or return 1
    set -l lines (command tmux list-panes -a -F '#{window_id}|#{pane_id}|#{@pwt_sid}|#{@pwt_dir}|#{pane_current_path}' 2>/dev/null)
    for tier in 1 2
        for line in $lines
            # -m4 keeps a path containing '|' intact in the last field.
            set -l parts (string split -m4 '|' -- $line)
            test (count $parts) -eq 5; or continue
            test "$parts[3]" = "$argv[1]"; or continue
            if test $tier -eq 1
                test "$parts[4]" = "$want_dir"; or continue
            else
                test -z "$parts[4]"; or continue
                set -l cwd "$parts[5]"
                # In-tree, except for __worktrees/: a worktree root's __worktrees/
                # holds DIFFERENT workstreams, so a here-query must not be answered
                # by a sibling worktree's window (and vice versa).
                test "$cwd" = "$want_dir"; or begin
                    string match -q -- "$want_dir/*" "$cwd"; or continue
                    string match -q -- "$want_dir/__worktrees/*" "$cwd"; and continue
                end
            end
            echo $parts[1]
            return 0
        end
    end
    return 1
end

# Record a window as the home of a workstream. Window options, not something
# inferred from the pane's cwd, because the cwd cannot separate two in-place
# sessions — and because the C-w panel labels its rows from @pwt_label.
#
# @pwt_dir is the workstream's OWN home: the worktree for `pwt <slug>`, the main
# root for `pwt here`. The REPO root cannot do this job — a here window and a
# worktree window in one repo record the same root, and would still collide. And
# it is RECORDED, never observed: matching a pane's live cwd would stop matching a
# pi that cd'd elsewhere, which lets a second pi open on the same session id — the
# transcript clobber __pwt_open_window exists to prevent.
#
# Chained with `and` and not silenced, for the opposite reason: a successful mark is
# the best available proof that the pane SURVIVED (tmux hands back a pane id for a
# command it cannot exec and then closes the window with it). It is a snapshot, not a
# guarantee — pi can still exit a moment later — but it turns "silently opened
# nothing" into a message.
function __pwt_mark --description 'record a workstream identity on a pane window'
    # A missing dir would be written as an EMPTY @pwt_dir, which reads as "pre-marker
    # window" — the one state the fallback tier trusts. Fail instead of degrading.
    test -n "$argv[4]"; or return 1
    command tmux set-window-option -t "$argv[1]" @pwt_sid "$argv[2]" 2>/dev/null
    and command tmux set-window-option -t "$argv[1]" @pwt_dir (__pwt_realpath "$argv[4]") 2>/dev/null
    and command tmux set-window-option -t "$argv[1]" @pwt_label "$argv[3]" 2>/dev/null
end

# select-window only moves within the current session; a worktree window in
# another session needs the client moved first, or the jump looks like a no-op.
# Both lookups ask for the session ID: tmux rewrites '.' and ':' in a session NAME,
# and a name starting with '$' cannot be reached by a name target at all — while the
# id is also what __pwt_parent_session hands out, and survives a rename between the
# two commands.
function __pwt_jump_to --description 'select <window id>, moving session if needed'
    set -l wid $argv[1]
    set -l target (command tmux display-message -p -t "$wid" '#{session_id}' 2>/dev/null)
    set -l current (command tmux display-message -p '#{session_id}' 2>/dev/null)
    if test -n "$target"; and test "$target" != "$current"
        command tmux switch-client -t "$target" 2>/dev/null
    end
    command tmux select-window -t "$wid"
end

# The session a workstream window belongs to: the one that already owns this repo's
# MAIN checkout. Sessions are not pwt's to create — sesh makes them from a path
# (`new-session -c <path>`) and tmux RECORDS that starting directory as
# `session_path`, so the answer is read rather than observed.
#
# Observed (pane cwd, or "a path inside the tree") re-creates the very bug this
# fixes: panes cd, and a scratch session is routinely the one hosting worktree panes
# (session `0` on this machine), so an in-tree match would resolve that session as the
# PARENT of the repo whose worktree it holds. __pwt_window_for carries the same
# lesson under `no-worktrees`.
#
# Compared canonically on BOTH sides: tmux reports `session_path` AS GIVEN (/tmp where
# git hands back /private/tmp on macOS), and a repo reached through a symlinked parent
# would otherwise never match its own session.
#
# Empty output means "no project session", and the caller then keeps the old
# behaviour: open in the CALLER's session. pwt never creates one — sessions are
# sesh's, and a second creator would be a second session manager competing with
# C-f/C-o/C-j for the same names.
#
# Returns a session ID, not a name: tmux rewrites '.'/':' in names and cannot target
# a name beginning with '$' at all, so only the id is a dependable handle.
function __pwt_parent_session --description 'session id owning <repo root>; opts: path-only'
    # One canonicaliser for the whole file: __pwt_realpath is a builtin call now, not
    # a cd, so asking it once per session costs no PWD-change events (which direnv
    # hooks on) and there is no second definition of "same path" to drift.
    set -l root (__pwt_realpath "$argv[1]")
    test -n "$root"; or return 1
    # A repo called foo.nvim can only ever be found under foo_nvim: tmux rewrites '.'
    # and ':' in a session NAME to '_'.
    set -l want (string replace -a -r '[.:]' '_' -- (string replace -r '.*/' '' -- $root))
    set -l fallback
    # ':' separates the fields and -m 2 keeps the tail intact: tmux forbids ':' in a
    # session name and a session id ($N) has none either, so the first two fields are
    # exact while the PATH — which may legitimately hold ':' or '|' — stays whole.
    for line in (command tmux list-sessions -F '#{session_id}:#{session_name}:#{session_path}' 2>/dev/null)
        set -l parts (string split -m 2 ':' -- $line)
        test (count $parts) -eq 3; or continue
        # Skipped, not compared: an empty session_path (a tmux without it, or a session
        # that never got one) would reach test with no right-hand operand and print
        # "test: Missing argument" into the caller's terminal.
        test -n "$parts[3]"; or continue
        test (__pwt_realpath "$parts[3]") = "$root"; or continue
        # A session NAMED after the repo is the one the user's own switchers pick
        # (sesh names a session after the directory), so it wins a tie.
        if test "$parts[2]" = "$want"
            echo $parts[1]
            return 0
        end
        test -n "$fallback"; or set fallback $parts[1]
    end
    test -n "$fallback"; and begin
        echo $fallback
        return 0
    end
    # Tier 2: a session named after the repo whose start directory has since
    # wandered. Strictly AFTER the path tier — two repos can share a basename, so a
    # name alone is never proof. `=` makes the target exact: a bare name is a PREFIX
    # match, and `foo` would then happily hit `foobar`. Callers that MOVE an existing
    # window pass `path-only` and stop at the line above: a name is enough to create
    # beside, not enough to drag an existing workstream across sessions.
    test "$argv[2]" = path-only; and return 1
    command tmux has-session -t "=$want" 2>/dev/null; or return 1
    command tmux display-message -p -t "=$want:" '#{session_id}' 2>/dev/null
end

# Move a workstream window into the session that owns its repo NOW. Placement is a
# property pwt MAINTAINS, not a one-shot at creation: a window opened before its
# project session existed sat in the caller's session, and the moment you go to it
# again (reuse through `pwt <slug>`, or `pwt jump`) is the moment the right session
# is known to exist. That is why this rides those verbs instead of growing a snap
# verb of its own — the panel's `enter` already reaches both.
#
# Silent on the two normal non-events: nowhere to go (no project session) and
# already home. A "nothing to do" line on every reuse would be noise.
#
# Callers pass a window they already resolved, and `pwt jump` checks @pwt_sid first:
# a pi someone started by hand is not pwt's to relocate.
function __pwt_snap_home --description 'move <window id> into the session owning <repo root>'
    set -l wid $argv[1]
    # Only a window pwt OPENED is pwt's to move. The gate lives HERE, not in the
    # callers: __pwt_open_window's path fallback can match a pi someone started by
    # hand inside the worktree (titled but unmarked), and that window is not a
    # workstream — relocating it would drag a stranger's pane across sessions.
    set -l own (command tmux display-message -p -t "$wid" '#{@pwt_sid}' 2>/dev/null)
    test -n "$own"; or return 0
    # path-only: a MOVE needs the recorded path, never just a name. Tier 2 is fair
    # evidence when CREATING (nothing better is known and the window has to go
    # somewhere), but not for dragging an existing workstream: another repo with the
    # same basename may own the session that shares the name.
    set -l sess (__pwt_parent_session "$argv[2]" path-only)
    test -n "$sess"; or return 0
    set -l here (command tmux display-message -p -t "$wid" '#{session_id}' 2>/dev/null)
    test -n "$here"; or return 1
    test "$here" = "$sess"; and return 0
    set -l label (command tmux display-message -p -t "$wid" '#{@pwt_label}' 2>/dev/null)
    # The window's own name before the REPO's: announcing a workstream as its repo is
    # how a message stops being useful.
    test -n "$label"; or set label (command tmux display-message -p -t "$wid" '#{window_name}' 2>/dev/null)
    test -n "$label"; or set label (command basename -- "$argv[2]")
    # detach-on-destroy is ON by default (this repo does not change it), so moving a
    # session's LAST window out of it destroys that session and DETACHES any client
    # sitting in it. Move the client first, while the source still exists — the same
    # reason __pwt_jump_to switches before selecting.
    set -l windows (command tmux list-windows -t "$here" -F '#{window_id}' 2>/dev/null)
    if test (count $windows) -eq 1
        echo "pwt: '$label' is the only window in its session, so this move ends that session" >&2
    end
    command tmux switch-client -t "$sess" 2>/dev/null
    command tmux move-window -s "$wid" -t "$sess:"
    or begin
        echo "pwt: could not move '$label' into its repo's session" >&2
        return 1
    end
    set -l where (command tmux display-message -p -t "$sess" '#{session_name}' 2>/dev/null)
    echo "pwt: moved '$label' to $where"
end

# pi must resolve before a window is SPAWNED — a missing pi makes the pane exit at
# once, tmux takes the window down with it, and every later step (select, mark, tap)
# fails silently, leaving a created worktree and nothing else.
#
# This checks the CALLER's PATH, which is a proxy: the pane resolves pi against the
# tmux server's environment. They agree because tmux.conf injects the mise shims
# into that environment. The honest check is the mark below — a window that died
# anyway cannot take its window options.
function __pwt_need_pi --description 'fail unless pi is on PATH'
    command -sq pi; or begin
        echo "pwt: pi is not on PATH — the tmux window would die at once" >&2
        return 1
    end
end

# Is <pid> a plain shell — the shape a resurrect restore leaves at the end of its
# `cat <pane contents>; exec <shell>`? comm's BASENAME, with the leading '-' a login
# shell carries (tmux starts its default shell as one: measured, a restored pane's
# pid reports `-sh`). `pane_current_command` cannot answer this: tmux reports a shell
# for a pane whose real command it has wrapped, so it says `fish` for a pane running
# `cat`, while pane_pid tells the truth.
function __pwt_is_shell --description 'comm of <pid> is a shell'
    set -l raw (command ps -o comm= -p "$argv[1]" 2>/dev/null)
    test -n "$raw"; or return 1
    set -l bare (string replace -r '^-' '' -- (command basename -- "$raw" 2>/dev/null))
    contains -- $bare sh bash zsh fish dash ksh ksh93 mksh ash
end

# Panes that are a bare, IDLE shell sitting exactly at <dir>: resurrect's leftover for
# a pwt window, since a pwt pane runs pi directly and its saved command is empty.
#
# One candidate per line as `<pane id>|<window id>`. The caller decides what to do
# with more than one; this is the predicate, so it never prints, mutates or guesses.
#
# `ps`/`pgrep`, NOT pane_current_command (see __pwt_is_shell). comm(pane_pid) is a
# shell AND it has no children: a live pi's pid is `node` (excluded by comm) and a
# hand-started pi is that shell's CHILD (excluded by pgrep).
function __pwt_revive_panes --description 'idle-shell panes at worktree <dir>'
    set -l want (__pwt_realpath "$argv[1]")
    for line in (command tmux list-panes -a -F '#{pane_id}|#{window_id}|#{@pwt_sid}|#{pane_current_path}|#{pane_pid}' 2>/dev/null)
        set -l parts (string split -m4 '|' -- $line)
        test (count $parts) -eq 5; or continue
        test "$parts[4]" = "$want"; or continue
        # Never a live workstream: pwt marks every window it opens, and a restored one
        # lost the mark — so an EMPTY @pwt_sid is exactly the "restored" state.
        test -z "$parts[3]"; or continue
        # Respawning the pane pwt itself runs in kills pwt mid-command.
        test "$parts[1]" != "$TMUX_PANE"; or continue
        __pwt_is_shell "$parts[5]"; or continue
        set -l kids (command pgrep -P "$parts[5]" 2>/dev/null)
        test (count $kids) -eq 0; or continue
        echo $parts[1]'|'$parts[2]
    end
end

# Is the pane pwt is RUNNING IN the restored bare shell for <dir>? __pwt_revive_panes
# deliberately excludes $TMUX_PANE (respawning it would kill pwt mid-command), so from
# inside that very shell the candidate count is 0 and the slug path would open a
# SECOND window — the exact reported symptom. This re-applies the same idle-shell
# evidence to the caller's own pane. A marked workstream needs no separate gate here:
# a live pwt window's pane pid is pi (`node`), which __pwt_is_shell already rejects.
function __pwt_revive_self --description 'is the pane pwt runs in the bare shell at <dir>'
    test -n "$TMUX_PANE"; or return 1
    set -l want (__pwt_realpath "$argv[1]")
    # display-message resolves the pane against the same server $TMUX names, so no
    # `-S` is needed. `|` is a literal in a tmux format; -m2 keeps a path with one in it.
    set -l parts (string split -m2 '|' -- (command tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}|#{pane_pid}' 2>/dev/null))
    test (count $parts) -eq 2; or return 1
    test "$parts[1]" = "$want"; or return 1
    __pwt_is_shell "$parts[2]"; or return 1
    set -l kids (command pgrep -P "$parts[2]" 2>/dev/null)
    test (count $kids) -eq 0
end

# Re-exec pi INTO an existing pane, keeping its id, window name and the layout around
# it. This is the whole of a restart: `pwt reload` runs it on a live workstream and
# `pwt revive` on a restored bare shell. The respawn command appears exactly once in
# this file (check.sh asserts it) because a second copy would drift.
#
# <envargs> is the `-e NAME=VALUE` argv from __pwt_forward_env; the caller passes it in
# so it can also count it for the "no secrets forwarded" message.
function __pwt_respawn_pi --description 're-exec pi into <pane>, keeping its layout'
    set -l pane $argv[1]
    set -l dir $argv[2]
    set -l sid $argv[3]
    command tmux respawn-pane -k -t "$pane" -c "$dir" $argv[4..-1] pi --session-id "$sid"
    or return 1
    # A respawn whose command cannot exec takes the pane down instead of failing — the
    # same trap __pwt_mark guards against at open time. The result must be STORED
    # first: `test -n (cmd)` with an empty output collapses to a lone `-n`, which is a
    # non-empty string and therefore true — a check that can never fail. pane_dead too,
    # because with remain-on-exit a corpse keeps answering with a pane id.
    set -l alive (command tmux display-message -p -t "$pane" '#{pane_id}' 2>/dev/null)
    set -l dead (command tmux display-message -p -t "$pane" '#{pane_dead}' 2>/dev/null)
    test -n "$alive"; and test "$dead" != 1
    or return 1
    # The dead run's state must not outlive it: the panel would keep showing 'working'
    # (or an alert) for a process that no longer exists.
    command tmux set-window-option -t "$pane" -u @pi_state 2>/dev/null
    command tmux set-window-option -t "$pane" -u @pi_alert 2>/dev/null
    # Belt and braces: the pipe-pane job survives a respawn (it follows the pane, not
    # the process) and a plain pipe-pane — never -o — replaces the pipe with the
    # identical command rather than detaching it.
    __pwt_tap "$pane"
end

# Bring ONE restored worktree window back as pi. The explicit `pwt revive <dir>` verb
# and the adoption `pwt <slug>` does after a restore share this.
#
# <dir> is a worktree path, whose shape IS the identity: sid = <repo basename>-<slug>,
# because resurrect preserves the cwd and nothing else. Anything that is not a bare,
# idle shell at that exact path is refused — a live pi (comm node), a pane with a child
# (a hand-started pi), a marked workstream and the pane pwt runs in are all never
# touched. <dry> = 1 reports what it would do and changes nothing.
function __pwt_revive --description 'respawn pi into a restored bare shell at <dir>'
    set -l raw "$argv[1]"
    set -l dry 0
    test "$argv[2]" = 1; and set dry 1
    set -l dir (__pwt_realpath "$raw")
    set -l parent (command dirname -- "$dir")
    # The `*/` before the name is load-bearing twice over: it is the shape test
    # (<root>/__worktrees/<slug>), and it keeps a bare `__worktrees` token out of the
    # fish-autoload grep check.sh runs over every function file.
    string match -q -- '*/__worktrees' "$parent"; or begin
        echo "pwt: not a worktree: $raw" >&2
        return 1
    end
    test -d "$dir"; or begin
        echo "pwt: no such worktree: $raw" >&2
        return 1
    end
    set -l root (command dirname -- "$parent")
    set -l slug (command basename -- "$dir")
    set -l sid (command basename -- "$root")-$slug
    set -l panes (__pwt_revive_panes "$dir")
    if test (count $panes) -eq 0
        # The pane pwt is in is excluded from the candidates above, so from inside the
        # restored shell the count is 0 for a reason worth naming, not the generic miss.
        if __pwt_revive_self "$dir"
            echo "pwt: the pane pwt runs in IS the bare shell at $dir — run pwt from another pane, or: pwt revive $dir" >&2
        else
            echo "pwt: nothing to revive at $dir" >&2
        end
        return 1
    end
    # Two candidates could mean two pis on one --session-id, which silently clobbers
    # one transcript. Refuse and name them instead of guessing.
    if test (count $panes) -gt 1
        echo "pwt: "$dir" has "(count $panes)" idle panes — refusing to pick one" >&2
        for cand in $panes
            echo "     "(string replace -r '\|.*' '' -- $cand) >&2
        end
        return 1
    end
    set -l pane (string replace -r '\|.*' '' -- $panes[1])
    if test $dry -eq 1
        echo "pwt: would revive '$slug' at $dir"
        return 0
    end
    __pwt_need_pi; or return 1
    set -l envargs (__pwt_forward_env)
    __pwt_respawn_pi "$pane" "$dir" "$sid" $envargs
    or begin
        echo "pwt: could not revive the window at $dir — is pi runnable there?" >&2
        return 1
    end
    __pwt_mark "$pane" "$sid" "$slug" "$dir"
    or begin
        echo "pwt: revived the pane at $dir but could not mark it" >&2
        return 1
    end
    echo "pwt: revived '$slug'"
end

# ── the secrets environment ───────────────────────────────────────────────────
# pwt opens the window with `pi` directly — no shell — so nothing in there re-reads
# secrets/env.fish, and a RUNNING pi can never be given new variables (there is no
# portable way to change a live process's env; closing and restarting is the only
# one). What pwt can do is hand the values to the spawn: tmux's `-e NAME=VALUE` on
# the commands that create or respawn a process. That keeps the fix inside the
# workstream it is meant for — `tmux setenv -g` would instead outlive the run and
# reach every future window on the server, with nothing that ever clears it.
#
# The values are read from the FILE at call time, not taken from the calling shell's
# exports: pwt is normally typed into a pane older than the edit, and `pwt reload`
# exists precisely to pick an edit up — forwarding the caller's copy would re-inject
# the stale secret and report success.
function __pwt_secrets_file --description 'the secrets file config.fish sources'
    if set -q PWT_SECRETS; and test -n "$PWT_SECRETS"
        echo $PWT_SECRETS
        return 0
    end
    echo "$HOME/dotfiles/secrets/env.fish"
end

# Names come from `set -<flags>x NAME` lines. ANCHORED: the live file carries
# commented-out `set -gx NAME` lines (rotated and retired keys), and an unanchored
# match cheerfully forwards those stale names. PWT_FORWARD_ENV overrides the scrape
# wholesale — it is the hatch for a machine whose secrets live somewhere else, and
# the way the test suite names a fixture.
function __pwt_forward_names --description 'env names to refresh in a pi window'
    if set -q PWT_FORWARD_ENV
        # `string split` on an EMPTY string yields one empty element, not none.
        test -n "$PWT_FORWARD_ENV"; or return 1
        string split ' ' -- $PWT_FORWARD_ENV
        return 0
    end
    set -l file (__pwt_secrets_file)
    test -r "$file"; or return 1
    set -l names
    for name in (string match -rg '^[[:space:]]*set[[:space:]]+-[a-zA-Z]*x[a-zA-Z]*[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)' <"$file")
        contains -- $name $names; and continue
        set -a names $name
    end
    test (count $names) -gt 0; or return 1
    printf '%s\n' $names
end

# Re-source the secrets file, guarded the way config.fish guards it: a git-crypt
# LOCKED checkout still has a file at that path, just without the values, and
# sourcing it is at best a no-op. This runs in pwt's own process — the calling
# shell — so those exports refresh there too. That is deliberate and idempotent: it
# is the same file, in the same place, that shell sourced at startup.
function __pwt_source_secrets --description 're-source the secrets file into this shell'
    set -l file (__pwt_secrets_file)
    test -r "$file"; or return 1
    set -l first (command head -n 1 "$file" 2>/dev/null)
    string match -q 'set*' -- "$first"; or return 1
    # >/dev/null: `source` runs inside a command substitution at the call site, so a
    # stray top-level `echo` in the file would otherwise become an argv word for tmux.
    source "$file" >/dev/null
end

# The `-e` arguments for tmux: one flag and one NAME=VALUE per name, each its own
# argv word. A name that is unset (possible only through PWT_FORWARD_ENV, since the
# default list is sourced just below) or whose value is EMPTY is skipped, never
# forwarded as empty — `-e NAME=` would CLEAR a secret the window would otherwise have
# inherited, turning a machine that merely lacks one export into a broken window.
#
# Never forwarded: TERM (tmux requires screen/tmux, see tmux(1)), TMUX (the socket of
# the pane the user is in, not of the window being made), TMUX_PANE (same, and the
# new pane has its own), PWD/OLDPWD (tmux sets them per pane), HOME, and PATH —
# tmux.conf seeds the server's PATH with the mise shims, so the caller's copy is the
# one entry here that is routinely WORSE than what the window would inherit.
function __pwt_forward_env --description 'tmux -e argv carrying the secrets env'
    set -l names (__pwt_forward_names); or return 0
    # PWT_FORWARD_ENV is an explicit name list, so those names keep the caller's
    # values; the default list is read out of the file (see the note above).
    set -q PWT_FORWARD_ENV; or __pwt_source_secrets
    for name in $names
        test -n "$name"; or continue
        contains -- $name TERM TMUX TMUX_PANE PWD OLDPWD HOME PATH; and continue
        set -q $name; or continue
        # A multi-element value would otherwise become several argv words and spill
        # its tail onto tmux's command line.
        set -l value (string join ' ' -- $$name)
        test -n "$value"; or continue
        # `printf '%s\n'` and NOT `printf -- '-e…'`: fish's printf builtin consumes
        # `--` as the FORMAT string and prints it, so the flag would silently
        # announce itself and never reach tmux.
        printf '%s\n' '-e' "$name=$value"
    end
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
    set -l wid (__pwt_workstream_window "$sid" "$dir")
    # The PATH fallback is for worktrees only, where the directory IS the workstream
    # and a window sitting in it is the workstream window (it still catches windows
    # opened before pwt wrote the marker). For an in-place workstream the directory
    # is shared, so a pi window found there may belong to a DIFFERENT in-place
    # workstream: falling back would land the new label in that window and it would
    # never exist as a workstream at all — silently, since the jump succeeds. So
    # in-place is identity or nothing.
    if test -z "$wid"; and test "$argv[4]" != identity-only
        # A resurrect restore brings a worktree window back as a bare shell: its saved
        # command is empty (a pwt pane's pid IS pi, and the save strategy reads the
        # pid's CHILDREN), @pwt_* options are not saved, and the `π -` title is
        # overwritten by the shell. Identity and the pi-title fallback therefore BOTH
        # miss, and re-running pwt would spawn a second pi on the same transcript and
        # orphan the restored pane. Adopt it first — and only then trust the pi title,
        # which is a prefix a shell can carry: a spoofed one must not win over a pane
        # that is demonstrably an idle shell (comm is a shell, no children).
        set -l cands (__pwt_revive_panes "$dir")
        set -l ncand (count $cands)
        if test $ncand -gt 1
            # Two idle panes on one worktree could be two pis on one --session-id, and
            # picking one would silently clobber the other's transcript. Refuse and
            # name them; the explicit repair is `pwt revive <dir>`.
            echo "pwt: $dir has $ncand idle panes — refusing to pick one" >&2
            for cand in $cands
                echo "     "(string replace -r '\|.*' '' -- $cand) >&2
            end
            echo "     repair explicitly: pwt revive $dir" >&2
            return 1
        else if test $ncand -eq 1
            __pwt_revive "$dir" 0 >/dev/null 2>&1
            and set wid (__pwt_workstream_window "$sid" "$dir")
        end
    end
    # The pi-title fallback runs BEFORE the self-pane refusal below: an unmarked pi
    # started by hand in this worktree is reached by its cwd, and a bare shell pwt
    # happens to be typed into must not steal that jump.
    if test -z "$wid"; and test "$argv[4]" != identity-only
        set wid (__pwt_window_for "$dir" pi-only)
    end
    if test -n "$wid"
        # A window that landed elsewhere (its project session did not exist yet) moves
        # home the next time you go to it — placement is maintained, not one-shot.
        set -l home (__pwt_main_root "$dir" 2>/dev/null)
        test -n "$home"; and __pwt_snap_home "$wid" "$home"
        # Say so: `pwt foo` that creates nothing looks like it failed.
        __pwt_jump_to "$wid"
        or begin; echo "pwt: could not select window $wid for $label" >&2; return 1; end
        echo "pwt: jumped to the open window for $label"
        return 0
    end
    # Nothing to jump to, and the pane pwt was typed into is ITSELF a bare shell at this
    # worktree root. It is excluded from the candidates (respawning the pane pwt runs in
    # would kill pwt mid-command) so there is nothing to adopt — and opening a window
    # HERE would be the very duplicate/orphan this feature exists to end. Refuse, and
    # name the two paths that do work.
    if test "$argv[4]" != identity-only; and __pwt_revive_self "$dir"
        echo "pwt: this pane is a bare shell for '$label' — run pwt from another pane, or C-w then enter" >&2
        return 1
    end
    # -P -F yields the pane we just made, so marking and tapping it need no racy
    # search (pi has not set its window title yet at this point).
    __pwt_need_pi; or return 1
    # The secrets env goes to THIS window only: -e creates no server-wide state, so a
    # stale value can never be inherited by a window pwt did not open.
    set -l envargs (__pwt_forward_env)
    # Where it opens: the session that owns the repo's MAIN checkout (see
    # __pwt_parent_session), so a workstream lands beside the project it belongs to
    # instead of in whichever session happened to be on screen. `here` resolves the
    # same way — its dir IS the root — and an unresolvable root means the caller's.
    set -l sess
    set -l root (__pwt_main_root "$dir" 2>/dev/null)
    test -n "$root"; and set sess (__pwt_parent_session "$root")
    set -l pane
    if test -n "$sess"
        # 2>/dev/null: the session can be gone by now, and the retry below is the
        # answer — its stderr would only announce a failure already handled.
        set pane (command tmux new-window -P -F '#{pane_id}' -t "$sess:" -n "$label" -c "$dir" $envargs pi --session-id "$sid" 2>/dev/null)
    end
    if test -z "$pane"
        # Before falling back, rule out the one bad outcome: a window for this sid that
        # EXISTS but whose id we lost. Spawning again would put a SECOND pi on the same
        # --session-id, and the two would clobber one transcript — the hazard this
        # whole function is built around. Not behaviourally covered: reproducing it
        # needs a tmux shim that creates the window and prints nothing, and a shim is
        # likelier to be wrong than this race is to happen.
        set -l made (__pwt_workstream_window "$sid" "$dir")
        if test -n "$made"
            __pwt_jump_to "$made" 2>/dev/null
            echo "pwt: the window for $label already exists — jumped to it" >&2
            return 0
        end
        # No project session, or it vanished between the listing and this command:
        # open in the CALLER's session rather than leave a fresh worktree windowless.
        set pane (command tmux new-window -P -F '#{pane_id}' -n "$label" -c "$dir" $envargs pi --session-id "$sid")
        or return 1
    end
    # NOT select-window: that only moves within the CURRENT session, and this window
    # may have just been opened in another one — the same reason __pwt_jump_to exists.
    __pwt_jump_to "$pane" 2>/dev/null
    __pwt_mark "$pane" "$sid" "$label" "$dir"
    or begin
        echo "pwt: the window for '$label' died at birth — is pi runnable there?" >&2
        echo "     nothing is open; run the same pwt command again once pi resolves" >&2
        return 1
    end
    __pwt_tap "$pane"
end

# The ignored entries of a worktree, relative, one per line. `--ignored` collapses a
# fully-ignored directory into ONE entry, which is what makes parking them a rename
# instead of a walk. Trailing slashes are stripped: `mv dir/ dest/` needs dest to
# exist, while `mv dir dest` does not.
function __pwt_ignored --description 'ignored paths in <dir>, relative'
    for line in (command git -C "$argv[1]" status --porcelain --ignored 2>/dev/null)
        string match -q '!! *' -- $line; or continue
        string replace -r '/+$' '' -- (string sub -s 4 -- $line)
    end
end

# Move <paths...> out of <dir> into <dest>, preserving their relative layout. Returns
# 1 if ANY of them could not be moved, so the caller aborts before deleting the tree.
# A rename on one filesystem, so a node_modules costs nothing.
function __pwt_park --description 'move ignored paths out of <dir> into <dest>'
    set -l dir $argv[1]
    set -l dest $argv[2]
    set -l failed 0
    for rel in $argv[3..-1]
        set -l src "$dir/$rel"
        set -l dst "$dest/$rel"
        command mkdir -p (command dirname -- "$dst") 2>/dev/null; or set failed 1
        command mv -- "$src" "$dst" 2>/dev/null; or set failed 1
    end
    return $failed
end

# `pwt ls --all` — the DORMANT listing. `pwt ls` is the panel's own rows (live
# worktrees + open windows); that surface goes blank the moment a workstream is
# torn down, so the remains — a kept unmerged branch, a pwt stash, a parked
# `pwt-removed/` dir — have no listing at all. This is that listing: read-only git
# (no tmux, no mutation), because the whole point is to work AFTER the live surfaces
# have let go, from a plain terminal.
#
# Deliberately a separate flag and never wired into pwt-pick: a dormant row is not a
# jump target, and the panel's contract is actionable rows only (docs/PWT.md).
#
# Repos are found by their `.git` DIRECTORY, not their worktrees: a dormant repo may
# have no `__worktrees/` left, and a worktree's `.git` is a file whose common dir is
# the repo that will be reported anyway. node_modules/target/.venv are pruned so a
# vendored package's own `.git` cannot masquerade as a repo.
function __pwt_ls_all --description 'list dormant pwt state under $PWT_SRC'
    set -l src "$HOME/src"
    if set -q PWT_SRC; and test -n "$PWT_SRC"
        set src "$PWT_SRC"
    end
    test -d "$src"; or begin
        echo "pwt: no such source root: $src" >&2
        return 1
    end
    set -l roots
    for gitdir in (command find "$src" -maxdepth 4 \( -name node_modules -o -name target -o -name .venv \) -prune -o -name .git -type d -print 2>/dev/null)
        set -a roots (command dirname -- "$gitdir")
    end
    set -l printed 0
    for root in $roots
        # The common dir, exactly as the info/exclude write resolves it: a worktree
        # reports its own path from --show-toplevel, but pwt-removed/ and the stash
        # list live on the MAIN repo. `git -C` so the rule is identical here.
        set -l common (command git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
        test -n "$common"; or continue
        # A branch checked out anywhere is not dormant — it is a tree you are in, and
        # pwt cannot check it out a second time. This is what keeps the repo's own
        # main branch (and worktrees outside __worktrees/) out of the listing.
        set -l checked
        for line in (command git -C "$root" worktree list --porcelain 2>/dev/null)
            if string match -q 'branch refs/heads/*' -- $line
                set -a checked (string replace 'branch refs/heads/' '' -- $line)
            end
        end
        set -l branches
        for b in (command git -C "$root" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)
            # A branch with a live worktree dir is a LIVE workstream, shown by plain
            # `pwt ls`; this verb is only the remains.
            test -d "$root/__worktrees/$b"; and continue
            contains -- $b $checked; and continue
            set -a branches "$b"
        end
        # -i because `pwt rm --stash` writes `pwt: removed <slug> <stamp>`; the shared
        # stash list is routinely congested, so the remains are named, not everything.
        set -l stashes (command git -C "$root" stash list 2>/dev/null | string match -i '*pwt*')
        set -l parked
        if test -d "$common/pwt-removed"
            set parked (command ls -1 "$common/pwt-removed" 2>/dev/null)
        end
        # A section is printed only when it has rows, and a repo with none of the
        # three is skipped entirely — otherwise the listing is mostly empty headers.
        if test (count $branches) -eq 0; and test (count $stashes) -eq 0; and test (count $parked) -eq 0
            continue
        end
        if test $printed -eq 0
            echo "pwt: dormant state under $src"
            set printed 1
        end
        echo ''
        echo (string replace "$src/" '' -- "$root")
        if test (count $branches) -gt 0
            echo '  branches with no worktree (pwt <slug> re-checks one out):'
            for b in $branches
                echo "    $b"
            end
        end
        if test (count $stashes) -gt 0
            echo '  pwt stashes:'
            for s in $stashes
                echo "    $s"
            end
        end
        if test (count $parked) -gt 0
            echo '  parked ignored files:'
            for p in $parked
                echo "    $p"
            end
        end
    end
    if test $printed -eq 0
        echo "pwt: no dormant state under $src"
    end
    return 0
end

function pwt --description 'pi git-worktree helper (tmux window + pinned session)'
    set -l cmd "$argv[1]"
    switch "$cmd"
        case rm remove
            # `--stash` is the panel's confirmed path: close the window that holds the
            # worktree, stash uncommitted work, park ignored files OUTSIDE the tree,
            # then remove. Everything it destroys is recoverable, and an unmerged
            # branch is still kept. Bare `rm` stays conservative for shell use.
            set -l rest $argv[2..-1]
            set -l stash_mode 0
            if test "$rest[1]" = --stash
                set stash_mode 1
                set -e rest[1]
            end
            set -l slug "$rest[1]"
            test -n "$slug"; or begin; echo "usage: pwt rm [--stash] <slug>" >&2; return 2; end
            __pwt_valid_slug "$slug"; or begin; echo "pwt: invalid slug '$slug'" >&2; return 2; end
            set -l root (__pwt_main_root); or return 1
            set -l wt "$root/__worktrees/$slug"
            test -d "$wt"; or begin; echo "pwt: no worktree at $wt" >&2; return 1; end
            # A worktree a window still holds is IN USE: removing it pulls the
            # directory out from under a running pi. Bare `rm` names what is open;
            # `--stash` closes it, which is the confirmed path.
            # in-tree, not exact: pi whose pane has cd'd into a subdirectory of the
            # worktree is just as much in the way, and deleting the tree under it
            # leaves that shell sitting in a directory that no longer exists.
            # Deliberately NOT gated on $TMUX: `pwt rm` run from a plain terminal
            # while pi works in tmux is exactly when this matters. With no
            # reachable server the lookup returns empty, which is correct.
            set -l live (__pwt_window_for "$wt" in-tree)
            if test -n "$live"; and test $stash_mode -eq 0
                echo "pwt: window $live still holds $wt" >&2
                echo "     close it first: tmux kill-window -t $live" >&2
                echo "     or let pwt close it and keep the work: pwt rm --stash $slug" >&2
                return 1
            end
            # `worktree remove` refuses only on TRACKED modifications; ignored files
            # (.env, .venv, node_modules) are deleted without a word. Those are exactly
            # the untracked-by-design files a worktree accumulates, so bare `rm`
            # refuses — naming `--stash` as the way out — while `--stash` preserves.
            set -l ignored (__pwt_ignored "$wt")
            set -l dirty (command git -C "$wt" status --porcelain 2>/dev/null | string match -rv '^!!')
            if test $stash_mode -eq 0; and test (count $dirty) -gt 0
                echo "pwt: $wt has uncommitted changes — refusing." >&2
                echo "     commit or stash them, or: pwt rm --stash $slug   (stashes, then removes)" >&2
                return 1
            end
            if test $stash_mode -eq 0; and test (count $ignored) -gt 0
                echo "pwt: $wt holds ignored files (.env/.venv/node_modules) — refusing." >&2
                echo "     Remove them yourself first, then re-run: pwt rm $slug" >&2
                echo "     or park them and keep the work: pwt rm --stash $slug" >&2
                return 1
            end
            set -l park ''
            if test $stash_mode -eq 1
                set -l stamp (command date -u +%Y%m%dT%H%M%SZ)
                # 1. Uncommitted work (tracked + untracked). A stash lives on the
                #    REPO's stash list, so it survives this worktree and its branch.
                if test (count $dirty) -gt 0
                    if not command git -C "$wt" stash push --include-untracked -q -m "pwt: removed $slug $stamp"
                        echo "pwt: could not stash changes in $wt — nothing was removed" >&2
                        return 1
                    end
                    echo "pwt: uncommitted changes stashed — recover with: git -C $root stash list"
                end
                # 2. Ignored files. Never deleted: moved under the git common dir, where
                #    nothing (git status, ripgrep, the panel) will see them.
                if test (count $ignored) -gt 0
                    set -l common (command git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
                    set park "$common/pwt-removed/$slug-$stamp"
                    if not __pwt_park "$wt" "$park" $ignored
                        echo "pwt: could not move ignored files aside — nothing was removed" >&2
                        echo "     they are still in $wt; fix permissions and retry" >&2
                        return 1
                    end
                    echo "pwt: moved "(count $ignored)" ignored entr(y|ies) to $park"
                end
                # 3. The window LAST: a popup waiting on this command can die with the
                #    window, and steps 1-2 are already complete by then. A window that
                #    vanished on its own is fine; one that refuses is not.
                if test -n "$live"
                    if not command tmux kill-window -t "$live" 2>/dev/null
                        # Stored first: `test -n (…empty…)` collapses to a lone `-n`,
                        # which is a non-empty STRING — so the vacuous form read "the
                        # window is already gone" as "could not close it" and refused
                        # the teardown this comment says is fine.
                        set -l still (command tmux display-message -p -t "$live" '#{window_id}' 2>/dev/null)
                        test -n "$still"
                        and begin
                            echo "pwt: could not close window $live — worktree left in place" >&2
                            return 1
                        end
                    end
                    echo "pwt: closed window $live"
                end
            end
            command git -C "$root" worktree remove "$wt"
            or begin
                echo "pwt: git could not remove $wt — the tree is still there" >&2
                test -n "$park"; and echo "     ignored files are parked at $park" >&2
                return 1
            end
            # A detached worktree (or one whose branch was already deleted) has nothing
            # to delete: that is finished, not failed — and `branch -d` would print a
            # "not found" error for it.
            command git -C "$root" show-ref --verify --quiet "refs/heads/$slug"; or return 0
            # branch -d refuses an unmerged branch — correctly: those commits exist
            # nowhere else. The tree is already gone by then, so a bare git hint
            # reads like pwt half-failed; name the follow-up instead. (Re-running
            # `pwt <slug>` WITHOUT a base ref checks that branch back out, so the
            # work is not lost — a deliberate resume, not a dead end.)
            command git -C "$root" branch -d "$slug"; and return 0
            echo "pwt: worktree removed; branch '$slug' kept (not fully merged)." >&2
            echo "     merge it, then: git -C '$root' branch -d '$slug'" >&2
            return 1
        case ls
            # Shell-side listing: which workstreams exist, in the panel's own order and
            # rendering. Delegated to pwt-pick's --list so the two cannot drift — a
            # second implementation is exactly the drift this file keeps catching.
            # Works outside tmux (every marker is then simply blank), and PWT_PICK is
            # overridable the way pwt-pick overrides PWT_REPO_LIST.
            #
            # `--all` adds the one thing those rows cannot show: the dormant remains a
            # teardown leaves behind (a kept branch, a pwt stash, a parked pwt-removed/
            # dir) vanish with the worktree and its window. A separate flag, never wired
            # into pwt-pick, because the panel's rows must stay jump targets.
            set -l args $argv[2..-1]
            if test "$args[1]" = --all
                __pwt_ls_all
                return $status
            end
            set -l picker ''
            set -q PWT_PICK; and set picker $PWT_PICK
            test -n "$picker"; or set picker "$HOME/bin/pwt-pick"
            test -x "$picker"; or begin
                echo "pwt: no picker at $picker" >&2
                return 1
            end
            command "$picker" --list
        case close
            # End a live workstream: kill the window whose pane is pi at <dir>. The
            # worktree case is `rm --stash`, which does this plus the tree. no-worktrees
            # because "the checkout" must not be answered by a pi in one of its own
            # worktrees — that one belongs to a different workstream.
            set -l dir "$argv[2]"
            test -n "$dir"; or begin; echo "usage: pwt close <dir>" >&2; return 2; end
            set -q TMUX; or begin; echo "pwt: not in tmux" >&2; return 1; end
            set -l wid (__pwt_window_for "$dir" pi-only in-tree no-worktrees)
            test -n "$wid"; or begin; echo "pwt: no pi window at $dir" >&2; return 1; end
            command tmux kill-window -t "$wid" 2>/dev/null
            or begin; echo "pwt: could not close window $wid" >&2; return 1; end
            echo "pwt: closed window $wid"
        case reload
            # Re-exec pi in an existing workstream window against the CURRENT secrets
            # file. A live process cannot be handed new env, so a reload IS a restart,
            # and re-exec'ing pi in the SAME pane is the only restart that keeps the
            # pane id, the window name and the @pwt_* markers, which is what makes it
            # the same workstream after. That re-exec lives in __pwt_respawn_pi.
            set -l rest $argv[2..-1]
            set -l force 0
            if test "$rest[1]" = --force
                set force 1
                set -e rest[1]
            end
            set -l dir "$rest[1]"
            test -n "$dir"; or begin; echo "usage: pwt reload [--force] <dir>" >&2; return 2; end
            set -q TMUX; or begin; echo "pwt: not in tmux" >&2; return 1; end
            # in-tree, like `close`: a pi whose pane has cd'd into a subdirectory of
            # the workstream is still that workstream's pi.
            set -l pane (__pwt_window_for "$dir" pi-only in-tree no-worktrees pane-id)
            test -n "$pane"; or begin; echo "pwt: no pi window at $dir" >&2; return 1; end
            # The pinned id is the whole reason a reload can resume the transcript, and
            # only a pwt window has one recorded. A foreign pi has no id to offer, so
            # say what the caller can do instead of guessing at "most recent session".
            set -l sid (command tmux display-message -p -t "$pane" '#{@pwt_sid}' 2>/dev/null)
            test -n "$sid"; or begin
                echo "pwt: that window records no pwt session id" >&2
                echo "     close it and re-run the pwt command: pwt close $dir" >&2
                return 1
            end
            set -l label (command tmux display-message -p -t "$pane" '#{@pwt_label}' 2>/dev/null)
            test -n "$label"; or set label (command basename -- "$dir")
            set -l home (command tmux display-message -p -t "$pane" '#{@pwt_dir}' 2>/dev/null)
            test -n "$home"; or set home "$dir"
            # Killing a mid-turn agent throws that turn away — the transcript resumes,
            # the work in flight does not. Require --force to say you know.
            set -l state (command tmux display-message -p -t "$pane" '#{@pi_state}' 2>/dev/null)
            if test "$state" = working; and test $force -eq 0
                echo "pwt: '$label' is working — a reload would drop the current turn" >&2
                echo "     wait for it, or: pwt reload --force $dir" >&2
                return 1
            end
            # A reload re-execs pi, so it needs what the spawn path needs: a pi that
            # resolves, or the pane exits and tmux takes the window down with it.
            __pwt_need_pi; or return 1
            set -l envargs (__pwt_forward_env)
            __pwt_respawn_pi "$pane" "$home" "$sid" $envargs
            or begin
                # The pane can die instead of exec'ing when pi does not resolve there;
                # say that plainly rather than the generic respawn wording.
                echo "pwt: could not reload '$label' — the window died on reload" >&2
                return 1
            end
            # Say which environment it got: with no readable secrets file nothing was
            # forwarded, and "reloaded" would then hide that the window is running on
            # whatever the tmux server was seeded with.
            if test (count $envargs) -gt 0
                echo "pwt: reloaded '$label' with the current environment"
            else
                echo "pwt: reloaded '$label' — no secrets were forwarded (nothing readable)"
            end
        case revive
            # Repair a window a tmux-resurrect restore left as a bare shell: the SAME
            # pane and window come back, with pi respawned into them. Identity is
            # recovered from the path (<root>/__worktrees/<slug>), because resurrect
            # saves none of the @pwt_* options and no command for a pane whose pid IS
            # pi. Bulk by design — one dir per restored window, as the post-restore
            # hook passes them — so it must never jump or snap a window.
            set -l rest $argv[2..-1]
            set -l dry 0
            if test "$rest[1]" = --dry-run
                set dry 1
                set -e rest[1]
            end
            test (count $rest) -gt 0; or begin
                echo "usage: pwt revive [--dry-run] <dir>…" >&2
                return 2
            end
            set -q TMUX; or begin; echo "pwt: not in tmux" >&2; return 1; end
            set -l rc 0
            for dir in $rest
                __pwt_revive "$dir" $dry
                or set rc 1
            end
            return $rc
        case help ''
            echo "Usage: pwt <slug> [base] | pwt <verb> …   (docs/PWT.md)"
            printf '  %-26s %s\n' 'pwt <slug> [base]' 'worktree + tmux window + pinned pi session'
            printf '  %-26s %s\n' 'pwt rm [--stash] <slug>' 'end it; --stash closes the window and keeps the work'
            printf '  %-26s %s\n' 'pwt close <dir>' 'end a live workstream: close its pi window'
            printf '  %-26s %s\n' 'pwt here <label>' 'a workstream in THIS checkout, no worktree'
            printf '  %-26s %s\n' 'pwt ls' 'list workstreams (the C-w panel rows, in order)'
            printf '  %-26s %s\n' 'pwt ls --all' 'also list dormant state: kept branches, stashes, parked files'
            printf '  %-26s %s\n' 'pwt jump <dir>' 'go to its pi window (moving a pwt window home)'
            printf '  %-26s %s\n' 'pwt reload [--force] <dir>' 'restart pi there with the current secrets env'
            printf '  %-26s %s\n' 'pwt revive [--dry-run] <dir>' 're-open pi in a worktree a tmux restore left bare'
            echo '  panel: tmux prefix then C-w'
        case jump
            # Used by the C-w panel for rows that are live pi sessions rather
            # than worktrees: there is nothing to create, only a window to find.
            set -l dir "$argv[2]"
            test -n "$dir"; or begin; echo "usage: pwt jump <dir>" >&2; return 2; end
            set -q TMUX; or begin; echo "pwt: not in tmux" >&2; return 1; end
            set -l pane (__pwt_window_for "$dir" pi-only pane-id)
            set -l wid (__pwt_window_for "$dir" pi-only)
            test -n "$wid"; or begin; echo "pwt: no pi window with cwd $dir" >&2; return 1; end
            # Where it belongs, if that is now known: a window that had to fall back to
            # the caller's session (no project session existed then) moves home the next
            # time you go to it. __pwt_snap_home checks @pwt_sid itself, so a hand-started
            # pi found by the path fallback above is never relocated.
            set -l home (__pwt_main_root "$dir" 2>/dev/null)
            test -n "$home"; and __pwt_snap_home "$wid" "$home"
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
                # Reuse needs no pi; only a NEW window does. Deciding before the
                # open also keeps the warning below off a workstream you already
                # own (that call jumps rather than opening).
                if test -z (__pwt_workstream_window "$sid" "$dir")
                    __pwt_need_pi; or return 1
                    # Two in-place workstreams share ONE working tree — the exact
                    # collision worktrees exist to prevent. This rung is still the
                    # right one for repos a worktree cannot serve (git-crypt fails
                    # at the smudge filter) and for per-path state (.env/.venv/
                    # direnv), so warn and let the user decide: refusing would
                    # delete the rung's reason to exist.
                    set -l squatter (__pwt_window_for "$dir" pi-only in-tree no-worktrees)
                    test -n "$squatter"; and echo "pwt: a pi is already open in this checkout — '$label' and it share one working tree, so parallel edits will collide" >&2
                end
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
            # No legitimate commit-ish starts with '-': passing one through lets git
            # parse it as an OPTION (`pwt foo --detach`), silently changing what the
            # worktree is based on.
            test -n "$base"; and string match -q -- '-*' "$base"; and begin
                echo "pwt: invalid base ref '$base'" >&2
                return 2
            end
            set -l root (__pwt_main_root); or return 1
            set -l wt "$root/__worktrees/$slug"
            set -l sid (basename $root)-$slug
            # Only a run that will SPAWN pi needs to find it: reusing an open window
            # must work on a machine with no pi (and never leaves an orphan worktree
            # behind a launch that cannot succeed). Ahead of the ignore write, so a
            # refused run changes nothing on disk.
            if set -q TMUX
                if test -z (__pwt_workstream_window "$sid" "$wt"); and test -z (__pwt_window_for "$wt" pi-only)
                    __pwt_need_pi; or return 1
                end
            end
            # __worktrees/ must be invisible to everything that is not pwt: git
            # reports it as an untracked directory, `git add -A` then stages a
            # mode-160000 gitlink for it (a worktree is an "embedded repository" to
            # git), and ripgrep/editor indexes walk every worktree copy. info/exclude
            # is per-clone and uncommitted, so it fixes all three without asking
            # every target repo to commit an ignore rule. Written before the
            # worktree-exists check, so a repo polluted by an older pwt repairs
            # itself on next use; never removed by `pwt rm` — the repo's other
            # worktrees still need it.
            set -l common (command git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
            if test -n "$common"
                set -l excl "$common/info/exclude"
                command mkdir -p "$common/info" 2>/dev/null
                if not command grep -qxF -- '__worktrees/' "$excl" 2>/dev/null
                    # Appending onto a last line that has no newline would MERGE with
                    # it — `node_modules/` becoming `node_modules/__worktrees/`, which
                    # un-ignores it. A command substitution strips trailing newlines,
                    # so a non-empty last BYTE means the file does not end with one.
                    if test -s "$excl"; and test -n (command tail -c 1 "$excl" 2>/dev/null)
                        printf '\n' >>"$excl" 2>/dev/null
                    end
                    # Warn, never abort: the worktree is the durable artifact and a
                    # read-only .git must not stop a workstream from starting.
                    if not printf '%s\n' '__worktrees/' >>"$excl" 2>/dev/null
                        echo "pwt: could not write $excl — git status will show __worktrees/" >&2
                    end
                end
            end
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
            if set -q TMUX
                __pwt_open_window "$wt" "$slug" "$sid"
            else
                echo "pwt: not in tmux — cd $wt && pi --session-id $sid"
            end
    end
end
