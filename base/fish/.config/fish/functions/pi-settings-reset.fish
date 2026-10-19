# pi-settings-reset — reconcile session drift in pi's settings.json back to the
# tracked config.
#
# Why: pi persists runtime state (default model, theme, thinking level,
# lastChangelogVersion, package list) into ~/.pi/agent/settings.json, which this
# repo owns as a stowed symlink into base/pi/.pi/agent/settings.json. Every pi
# session therefore writes through the symlink into a TRACKED file, so a commit
# made while sessions are running sweeps up whatever the last session happened to
# select — and `check.sh` asserts on the live file (defaultModel, enabledModels,
# the no-kimi tombstone), so drift can also turn the suite red for a reason that
# has nothing to do with the change under review.
#
# What pi already handles: 1.3.0 takes a proper-lockfile lock and merges its
# writes per TOP-LEVEL key (dist/core/settings-manager.js, persistScopedSettings),
# so concurrent sessions do not lose each other's *unrelated* keys. What is left
# is file-vs-HEAD drift, which is what this reconciles. Nothing here fixes the
# narrower races upstream still has (two sessions writing the same key, the very
# first write to an absent file, and a non-atomic write that leaves an unparsable
# file for the next session) — see docs/GOTCHAS.md.
#
# Policy: the tracked file is authoritative for every key EXCEPT the two below,
# whose LIVE value is kept and reported (they mark deliberate acts, not drift):
#   lastChangelogVersion  — the repo records the upgrade marker on purpose
#   packages              — `pi install` / `pi remove` is a deliberate act;
#                           silently reverting it would undo it
# "Kept" means live is authoritative for that key in both directions: a live
# `packages` list replaces the tracked one, and its absence live (the last `pi
# remove`) removes it from the file too — so committing after that is what
# declares the removal.
# A key the tracked file does not declare is REMOVED from the live file: same
# rule read the other way. `--all` drops both exceptions (repo wins for
# everything), which matches a plain `git checkout --` of the tracked file.
# Drift that is only formatting — values identical, bytes different (a re-handed
# key order, a stray trailing newline) — counts as drift: the bytes go back to
# HEAD verbatim, so a clean revert really does leave `git status` clean.
#
# An unreadable live file (a torn pi write: invalid UTF-8, invalid JSON, or JSON
# that is not an object) is rebuilt from HEAD, but its bytes are archived to
# settings.json.unparsable-<stamp> in the agent dir first and the run exits 1:
# the live values of the kept keys cannot be read, so a `pi install` that was in
# that file is not silently lost, it is handed back.
#
# MANUAL ONLY, and deliberately not wired into pi: there is no cleaner and no
# scheduler. Reverting under a running session is safe but racy — the write is
# atomic, verified byte-for-byte against what it intended, and retried. A
# millisecond window remains: this does not take pi's lock, so (a) a write landing
# between our read and our replace is lost, and (b) a write that opened the old
# inode before the replace and flushes after it is invisible to the verification.
# Re-run and it is gone. Reverting does NOT retune an open pi session: pi reads
# settings at startup and keeps them in memory, so this is startup-default
# hygiene, not a live kill switch (a session that later writes its own modified
# key writes its own value back; re-run then).
#
# Usage: pi-settings-reset [-n|--dry-run] [--all]
#   default    revert drift, keep + report the two deliberate-act keys
#   -n         report the drift, touch nothing (exits 1 when it found any)
#   --all      revert every key, deliberate acts included
# Exit: 0 nothing owed, 1 drift found (dry run), a deliberate-act key or an
# unreadable file needs a human, or an error, 2 bad argument.

# The JSON work: read HEAD's copy from git, diff it against the live file per
# top-level key, write the reconciled result atomically. Kept as a helper with
# explicit paths so check.sh can exercise it against a throwaway git repo instead
# of the real settings file (<backup_dir> is where an unreadable file is archived).
function __pi_settings_reset_apply --argument-names repo rel all_flag dry_flag backup_dir
    # python3, for the same reason check.sh uses it: JSON round-tripping in pi's
    # exact on-disk format (2-space indent, insertion order, NO trailing newline —
    # a stray newline would make every revert a git modification) plus os.replace.
    set -l py 'import json, os, subprocess, sys, tempfile, time

repo, rel, all_flag, dry_flag, backup_dir = sys.argv[1:6]
tracked = os.path.join(repo, rel)
KEEP = () if all_flag == "1" else ("lastChangelogVersion", "packages")
MISSING = object()

def get(d, k):
    return d[k] if k in d else MISSING

def canon(v):
    # Serialisation identity, not ==: python says True == 1 and
    # {"k": 1} == {"k": True}, so a bool/int flip would read as "no drift".
    return "~absent" if v is MISSING else json.dumps(v, sort_keys=True)

def show(v):
    if v is MISSING:
        return "(absent)"
    s = json.dumps(v, ensure_ascii=False)
    return s if len(s) <= 72 else s[:69] + "..."

def read_bytes():
    with open(tracked, "rb") as f:
        return f.read()

try:
    head_raw = subprocess.run(["git", "-C", repo, "show", "HEAD:" + rel],
                              check=True, capture_output=True, text=True).stdout
except subprocess.CalledProcessError as exc:
    print("pi-settings-reset: git cannot read HEAD:" + rel + " ("
          + (exc.stderr or "").strip() + ")", file=sys.stderr)
    sys.exit(1)
head = json.loads(head_raw)

# plan() answers, for one snapshot of the live file: what the reconciled result
# is, whether that result is value-identical to HEAD, and what changed per key.
def plan(live):
    result = dict(head)
    reverted, removed, kept = [], [], []
    for k in list(head) + [k for k in live if k not in head]:
        if k in KEEP:
            if canon(get(live, k)) != canon(get(head, k)):
                kept.append(k)
            if k in live:
                result[k] = live[k]
            else:
                result.pop(k, None)
            continue
        if canon(get(live, k)) != canon(get(head, k)):
            (reverted if k in head else removed).append(k)
    return result, canon(result) == canon(head), reverted, removed, kept

def snapshot():
    # Each of these is a state a torn pi write can leave behind, and exactly what
    # this exists to repair: only HEAD has to parse.
    data = read_bytes()
    try:
        raw = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        return None, None, "not valid UTF-8 (" + str(exc) + ")"
    try:
        live = json.loads(raw)
    except json.JSONDecodeError as exc:
        return raw, None, "not valid JSON (" + str(exc).split(":")[0] + ")"
    if not isinstance(live, dict):
        return raw, None, "JSON but not an object"
    return raw, live, None

def evaluate():
    raw, live, broken = snapshot()
    if broken is not None:
        return raw, {}, broken, dict(head), True, [], [], [], False
    result, same, reverted, removed, kept = plan(live)
    cosmetic = not (reverted or removed or kept) and raw != head_raw
    return raw, live, broken, result, same, reverted, removed, kept, cosmetic

def report(live, reverted, removed, kept, cosmetic, broken, dry, backup):
    if broken is not None:
        print("  repair   " + rel + " is " + broken + " — "
              + ("would be rebuilt from HEAD" if dry else "rebuilt from HEAD"))
        if backup is not None:
            print("  archived " + backup + " (the live bytes; a kept key such as "
                  "packages could not be read, so HEAD value is in the file)")
        else:
            print("           kept keys could not be read; their HEAD values are in the file")
    for k in reverted:
        print("  reverted " + k.ljust(22) + " " + show(get(live, k)) + " -> " + show(get(head, k)))
    for k in removed:
        print("  removed  " + k.ljust(22) + " " + show(get(live, k)) + " (not declared in the tracked file)")
    for k in kept:
        print("  kept     " + k.ljust(22) + " " + show(get(live, k)) + " (commit it, or re-run with --all)")
    if cosmetic:
        print("  cosmetic " + rel + " is not byte-identical to HEAD (order/newline only)")

def output(same, result):
    return head_raw if same else json.dumps(result, indent=2, ensure_ascii=False)

raw, live, broken, result, same, reverted, removed, kept, cosmetic = evaluate()
if not (reverted or removed or kept or cosmetic or broken):
    print("pi-settings-reset: no session drift — " + rel + " matches HEAD")
    sys.exit(0)

if dry_flag == "1":
    report(live, reverted, removed, kept, cosmetic, broken, True, None)
    print("pi-settings-reset: --dry-run — " + rel + " left untouched")
    sys.exit(1)

backup = None
if broken is not None:
    os.makedirs(backup_dir, exist_ok=True)
    backup = os.path.join(backup_dir, "settings.json.unparsable-"
                          + time.strftime("%Y%m%dT%H%M%S", time.gmtime()))
    with open(backup, "wb") as f:
        f.write(read_bytes())

out = output(same, result)
mode = os.stat(tracked).st_mode & 0o7777
for attempt in range(3):
    # Sweep a temp left behind by a killed run. The threshold is far above the
    # millisecond window this file is open, so it cannot hit a live one.
    for stale in os.listdir(os.path.dirname(tracked)):
        if not stale.startswith(".pi-settings-reset."):
            continue
        path = os.path.join(os.path.dirname(tracked), stale)
        try:
            if time.time() - os.stat(path).st_mtime > 60:
                os.unlink(path)
        except OSError:
            pass
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(tracked), prefix=".pi-settings-reset.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(out)
        os.chmod(tmp, mode)          # mkstemp is 0600; keep the file its own mode
        os.replace(tmp, tracked)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    # Catches a write that completes after our replace (the kept keys are in the
    # comparison), so the common lost update shows up here. It cannot see a write
    # that opened the old inode before the replace — hence the header caveat.
    if read_bytes() == out.encode("utf-8"):
        break
    time.sleep(0.05)
    raw, live, broken, result, same, reverted, removed, kept, cosmetic = evaluate()
    if not (reverted or removed or kept or cosmetic or broken):
        break
    out = output(same, result)
else:
    print("pi-settings-reset: a pi session kept writing while this ran (3 attempts) — "
          "re-run once it has settled", file=sys.stderr)
    sys.exit(1)

report(live, reverted, removed, kept, cosmetic, broken, False, backup)
print("pi-settings-reset: " + rel
      + (" rebuilt from HEAD (live bytes archived)" if broken is not None else " reconciled to HEAD")
      + ("" if not kept else " (kept keys still differ — commit them)"))
sys.exit(1 if (kept or broken is not None) else 0)
'
    command python3 -c "$py" "$repo" "$rel" "$all_flag" "$dry_flag" "$backup_dir"
end

function pi-settings-reset --description 'Reconcile session drift in pi settings.json back to the tracked config'
    set -l dry 0
    set -l all 0
    for arg in $argv
        switch $arg
            case -n --dry-run
                set dry 1
            case --all
                set all 1
            case -h --help
                echo 'Usage: pi-settings-reset [-n|--dry-run] [--all]'
                return 0
            case '*'
                echo "pi-settings-reset: unknown argument: $arg" >&2
                return 2
        end
    end

    if not command -q python3
        echo 'pi-settings-reset: python3 not found (needed for the JSON merge)' >&2
        return 1
    end

    set -l repo "$HOME/dotfiles"
    set -l rel 'base/pi/.pi/agent/settings.json'
    set -l tracked "$repo/$rel"
    set -l agent_dir "$HOME/.pi/agent"
    set -l live "$agent_dir/settings.json"

    if not test -f "$live"
        echo "pi-settings-reset: no settings file at $live" >&2
        return 1
    end
    # Both sides are canonicalised before the comparison (the macOS /var ->
    # /private/var hop alone makes unequality trivial). Empty output means `path
    # resolve` is missing — a fish older than 3.5 — which must not masquerade as
    # "not stowed".
    set -l live_target (path resolve -- "$live")
    set -l tracked_target (path resolve -- "$tracked")
    if test -z "$live_target"; or test -z "$tracked_target"
        echo "pi-settings-reset: cannot canonicalise $live (needs fish >= 3.5 for \`path resolve\`)" >&2
        return 1
    end
    # The whole mechanism rests on the live file BEING the tracked file: while the
    # agent dir's settings.json is a stow symlink into this repo, a session's write
    # IS the repo's drift. If it is not stowed, the file pi mutates is host-local
    # and there is nothing here to reconcile — say so rather than writing the repo
    # copy over a file nothing reads.
    if test "$live_target" != "$tracked_target"
        echo "pi-settings-reset: $live is not stowed to $tracked" >&2
        echo '  nothing to reconcile — pi is writing host-local settings right now' >&2
        return 1
    end
    if not command -q git
        echo 'pi-settings-reset: git not found (HEAD is the baseline)' >&2
        return 1
    end
    if not command git -C "$repo" rev-parse --verify --quiet HEAD >/dev/null
        echo "pi-settings-reset: $repo has no HEAD commit to reconcile against" >&2
        return 1
    end

    # An unreadable live file is archived into the agent dir, never into the repo
    # (a stray untracked file under base/pi would be stowed and committed next).
    __pi_settings_reset_apply "$repo" "$rel" "$all" "$dry" "$agent_dir"
end
