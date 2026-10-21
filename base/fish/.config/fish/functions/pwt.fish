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
function __pwt_jump_to --description 'select <window id>, moving session if needed'
    set -l wid $argv[1]
    set -l target (command tmux display-message -p -t "$wid" '#{session_name}' 2>/dev/null)
    set -l current (command tmux display-message -p '#{session_name}' 2>/dev/null)
    if test -n "$target"; and test "$target" != "$current"
        command tmux switch-client -t "$target" 2>/dev/null
    end
    command tmux select-window -t "$wid"
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
    __pwt_need_pi; or return 1
    # The secrets env goes to THIS window only: -e creates no server-wide state, so a
    # stale value can never be inherited by a window pwt did not open.
    set -l envargs (__pwt_forward_env)
    set -l pane (command tmux new-window -P -F '#{pane_id}' -n "$label" -c "$dir" $envargs pi --session-id "$sid")
    or return 1
    command tmux select-window -t "$pane" 2>/dev/null
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
            # file. A live process cannot be handed new env, so a reload IS a restart;
            # respawn-pane is the only restart that keeps the pane id, the window name
            # and the @pwt_* markers, which is what makes it the same workstream after.
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
            command tmux respawn-pane -k -t "$pane" -c "$home" $envargs pi --session-id "$sid"
            or begin; echo "pwt: could not respawn the window for '$label'" >&2; return 1; end
            # A respawn whose command cannot exec takes the pane down instead of
            # failing — the same trap __pwt_mark guards against at open time. The
            # result must be STORED first: `test -n (cmd)` with an empty output
            # collapses to a lone `-n`, which is a non-empty string and therefore
            # true — a check that can never fail. pane_dead too, because with
            # remain-on-exit a corpse keeps answering with a pane id.
            set -l alive (command tmux display-message -p -t "$pane" '#{pane_id}' 2>/dev/null)
            set -l dead (command tmux display-message -p -t "$pane" '#{pane_dead}' 2>/dev/null)
            test -n "$alive"; and test "$dead" != 1
            or begin; echo "pwt: the window died on reload — is pi runnable there?" >&2; return 1; end
            # The dead run's state must not outlive it: the panel would keep showing
            # 'working' (or an alert) for a process that no longer exists.
            command tmux set-window-option -t "$pane" -u @pi_state 2>/dev/null
            command tmux set-window-option -t "$pane" -u @pi_alert 2>/dev/null
            # Belt and braces: the pipe-pane job survives a respawn (it follows the
            # pane, not the process) and a plain pipe-pane — never -o — replaces the
            # pipe with the identical command rather than detaching it.
            __pwt_tap "$pane"
            # Say which environment it got: with no readable secrets file nothing was
            # forwarded, and "reloaded" would then hide that the window is running on
            # whatever the tmux server was seeded with.
            if test (count $envargs) -gt 0
                echo "pwt: reloaded '$label' with the current environment"
            else
                echo "pwt: reloaded '$label' — no secrets were forwarded (nothing readable)"
            end
        case help ''
            echo "Usage: pwt <slug> [base] | pwt <verb> …   (docs/PWT.md)"
            printf '  %-26s %s\n' 'pwt <slug> [base]' 'worktree + tmux window + pinned pi session'
            printf '  %-26s %s\n' 'pwt rm [--stash] <slug>' 'end it; --stash closes the window and keeps the work'
            printf '  %-26s %s\n' 'pwt close <dir>' 'end a live workstream: close its pi window'
            printf '  %-26s %s\n' 'pwt here <label>' 'a workstream in THIS checkout, no worktree'
            printf '  %-26s %s\n' 'pwt ls' 'list workstreams (the C-w panel rows, in order)'
            printf '  %-26s %s\n' 'pwt jump <dir>' 'go to the pi window whose cwd is <dir>'
            printf '  %-26s %s\n' 'pwt reload [--force] <dir>' 'restart pi there with the current secrets env'
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
