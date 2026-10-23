# git-prune-merged — list (and, with --apply, delete) local branches already
# merged into the base branch.
#
# Why this exists: `git branch --merged` is the safe signal and `[gone]` is the
# trap. A branch whose upstream is gone is usually an abandoned PR — its commits
# are NOT in the base — so a [gone]-driven prune throws away unmerged work. The
# only gate here is merge state: if git says the branch is merged into the base,
# its work is already there. A branch checked out in this checkout or in any
# linked worktree cannot be deleted without dropping a working tree, so it is
# excluded rather than forced.
#
# Why dry-run by default: deletion is not really reversible (reflog only, and
# only until gc), so `--apply` is an explicit opt-in. The plan is the useful half.
#
# Colourless and non-interactive by design: this is a building block meant to be
# wired into a workflow later, so it never prompts and its output is pipeable.
#
# Usage: git-prune-merged [--fetch] [--apply]
#   --fetch   run `git fetch --prune` first (explicit: it hits the network)
#   --apply   actually delete the listed branches with `git branch -d`
function git-prune-merged --description 'List merged local branches (dry-run; --apply to delete)'

    set -l do_fetch 0
    set -l do_apply 0
    for arg in $argv
        switch $arg
            case --fetch
                set do_fetch 1
            case --apply
                set do_apply 1
            case -h --help
                echo 'usage: git-prune-merged [--fetch] [--apply]'
                return 0
            case '*'
                echo "git-prune-merged: unknown argument: $arg" >&2
                return 2
        end
    end

    if not command git rev-parse --is-inside-work-tree >/dev/null 2>&1
        echo 'git-prune-merged: not inside a git repository' >&2
        return 1
    end

    # Explicit and opt-in: it is a network round-trip, so never do it implicitly.
    if test $do_fetch -eq 1
        if not command git fetch --prune
            echo 'git-prune-merged: git fetch --prune failed' >&2
            return 1
        end
    end

    set -l base (__git_prune_base)
    if test -z "$base"
        echo 'git-prune-merged: no base branch (looked for origin/HEAD, origin/main, origin/master, main, master)' >&2
        return 1
    end

    # Branches that must survive even when merged: the one we stand on, anything
    # a linked worktree holds, and the long-lived names.
    set -l protected main master develop HEAD
    set -l current (command git symbolic-ref --short HEAD 2>/dev/null)
    test -n "$current"; and set -a protected $current
    for line in (command git worktree list --porcelain 2>/dev/null)
        if string match -q 'branch refs/heads/*' -- $line
            set -a protected (string replace 'branch refs/heads/' '' -- $line)
        end
    end

    # Gate on --merged ONLY. A [gone] upstream is never consulted: it says the
    # PR was closed, not that the work landed.
    set -l doomed
    for b in (command git branch --merged "$base" --format='%(refname:short)' 2>/dev/null)
        contains -- $b $protected; and continue
        set -a doomed $b
    end

    if test (count $doomed) -eq 0
        echo "git-prune-merged: no merged branch to delete (base: $base)"
        return 0
    end

    if test $do_apply -eq 0
        echo "git-prune-merged: merged into $base — would delete:"
        for b in $doomed
            echo "  $b"
        end
        echo 'git-prune-merged: dry-run — re-run with --apply to delete'
        return 0
    end

    for b in $doomed
        # -d, never -D: --merged already proved the work is in the base, so a
        # refusal here means something is off and forcing would lose commits.
        if command git branch -d "$b" >/dev/null
            echo "git-prune-merged: deleted $b"
        else
            echo "git-prune-merged: refused to delete $b (not merged after all?)" >&2
        end
    end
end

# __git_prune_base — the remote HEAD, then the conventional names.
function __git_prune_base
    set -l head (command git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
    test -n "$head"; and echo $head; and return 0
    for cand in origin/main origin/master main master
        if command git rev-parse --verify --quiet "$cand^{commit}" >/dev/null 2>&1
            echo $cand
            return 0
        end
    end
    return 1
end
