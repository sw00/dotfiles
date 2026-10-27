# pi-settings-apply — apply the tracked pi settings TEMPLATE to the host-local
# live settings file.
#
# Two files, on purpose:
#   $DOTFILES/base/pi/.pi/agent/settings.desired.json  tracked, stowed, INTENT
#                                                      only, never read by pi
#   ~/.pi/agent/settings.json                          live, NOT stowed, NOT
#                                                      tracked, written by pi
# pi persists runtime state (default model, theme, thinking level,
# lastChangelogVersion, package list) into its settings file at startup and on
# every change. While that file was a stow SYMLINK into base/pi, every session
# wrote through the link into a TRACKED file: `git status` was dirty after any
# session, a commit made with a session running swept up whatever the last
# session happened to select, and two hosts pulling the same branch fought over
# the same bytes. So the live file is host-local now and only pi (plus this
# command) writes it; the repo tracks intent in the template instead.
#
# What wins, exactly:
#   - every top-level key the TEMPLATE declares wins over the live value;
#   - EXCEPT `packages`, where LIVE wins whenever live declares it — `pi install`
#     / `pi remove` is a deliberate act, and silently reverting it would undo it.
#     (When live does not declare it at all, the template value is used.)
#   - keys live-only (in live, absent from the template) are PRESERVED. That is
#     what keeps `lastChangelogVersion` and unpromoted session state safe without
#     a keep-list in this file. `--prune` drops them instead (exact
#     "host == intent") — use it to see what the template does not explain.
#   - a missing live file is created from the template (fresh host).
#   - an unparsable live file (invalid UTF-8, invalid JSON, or JSON that is not an
#     object — the states a torn non-atomic pi write leaves behind) is archived
#     byte-for-byte to settings.json.unparsable-<stamp> in the agent dir and then
#     rebuilt from the template; the run exits 1 because the old live values
#     cannot be read.
#
# Promote-back is editing the TEMPLATE and committing it: the merged result is
# re-serialised in pi's own on-disk format (2-space indent, insertion order from
# the template, no trailing newline), so the template is the only thing whose
# hand-formatting matters. `pi-settings-apply -n` names what differs and what is
# live-only — that is the promote worklist.
#
# MANUAL ONLY, and deliberately not wired into pi: pi reads settings at startup
# and keeps them in memory, so this is startup-default hygiene, not a live kill
# switch (a running session that later writes one of these keys writes its own
# value back; re-run then). The write is atomic (temp in the same dir + rename),
# byte-verified against what it intended, and retried a bounded number of times.
# Nothing here takes pi's lock, so the residual upstream races remain: (a) two
# sessions writing the SAME key are last-write-wins — unrelated keys are safe
# because pi merges per top-level key under its own lockfile; (b) the very first
# write to an absent file has no such merge; (c) a torn non-atomic write can leave
# an unparsable file, which this repairs but does not prevent. The verify step
# below catches a write that lands AFTER our replace (it re-reads and folds that
# value back in, then retries); it sees nothing that was already open on the old
# inode and flushes after the replace, and it says nothing about the window
# between our read and our replace — a write landing there is simply overwritten.
# Re-run once a session has settled.
#
# Usage: pi-settings-apply [-n|--dry-run] [--prune]
#   default    merge the template into the live file (live-only keys kept)
#   -n         report added/changed/removed keys, touch nothing
#              (exits 1 when anything would change, 0 when identical)
#   --prune    drop live-only keys (report them first with -n)
# Exit: 0 the live file matches the template, 1 drift (dry run), an unparsable
# file was rebuilt, or an error, 2 bad argument.

# The JSON work, kept as a helper with explicit paths so check.sh can exercise it
# against throwaway files instead of the real settings file. argv order:
# template, live, dry (1/0), prune (1/0). The agent dir for the archive is the
# live file's own directory.
function __pi_settings_apply --argument-names template_path live_path dry_flag prune_flag
    # python3 for the same reason check.sh uses it: JSON round-tripping in pi's
    # exact on-disk format (2-space indent, insertion order, NO trailing newline)
    # plus os.replace.
    set -l py 'import json, os, sys, tempfile, time

template_path, live_path, dry_flag, prune_flag = sys.argv[1:5]
live_dir = os.path.dirname(os.path.abspath(live_path))
DRY = dry_flag == "1"
PRUNE = prune_flag == "1"

def die(msg):
    print("pi-settings-apply: " + msg, file=sys.stderr)
    sys.exit(1)

def canon(v):
    # Serialisation identity, not ==: python says True == 1 and
    # {"k": 1} == {"k": True}, so a bool/int flip would read as "no drift".
    return json.dumps(v, sort_keys=True)

def show(v):
    s = json.dumps(v, ensure_ascii=False)
    return s if len(s) <= 72 else s[:69] + "..."

def load(path, what):
    # Returns (bytes, parsed object or None, why it is unusable or None). Only the
    # template has to parse; a broken live file is a state this repairs.
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError as exc:
        die("cannot read the " + what + " (" + path + "): " + str(exc.strerror))
    try:
        raw = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        return data, None, "not valid UTF-8 (" + str(exc).split(":")[0] + ")"
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError as exc:
        return data, None, "not valid JSON (line " + str(exc.lineno) + ", col " + str(exc.colno) + ")"
    if not isinstance(obj, dict):
        return data, None, "JSON but not an object"
    return data, obj, None

_, template, broken = load(template_path, "template")
if broken is not None:
    die("the template " + template_path + " is " + broken
        + " — fix it in the repo and re-run (the template is the intent, so it is never guessed at)")

def merge(live):
    merged = {}
    for k in template:
        if k == "packages" and k in live:
            merged[k] = live[k]        # deliberate act: pi install / pi remove
        else:
            merged[k] = template[k]
    if not PRUNE:
        for k in live:
            if k not in merged:
                merged[k] = live[k]
    return merged

def intended_bytes(live, is_broken):
    return json.dumps(merge({} if is_broken else live),
                      indent=2, ensure_ascii=False).encode("utf-8")

def deltas(live):
    added = [k for k in template if k not in live]
    changed = [k for k in template
               if k in live and k != "packages" and canon(live[k]) != canon(template[k])]
    live_only = [k for k in live if k not in template]
    return added, changed, (live_only if PRUNE else []), ([] if PRUNE else live_only)

# A stow symlink would put our write in the repo, which is the exact failure this
# command exists to end. Refuse to write through it; a dry run may still read it
# (that is the pre-migration state and the delta is worth seeing).
if os.path.islink(live_path):
    target = os.path.realpath(live_path)
    if not DRY:
        die(live_path + " is a symlink -> " + target
            + " — a stow link puts the write in the repo. Make it host-local first:"
            + " rm the link, copy the live bytes there, then stow --restow --no-folding -d base -t ~ pi")
    print("  note     " + live_path + " is a symlink -> " + target
          + " (apply would replace the link with a host-local file)")

fresh = not os.path.lexists(live_path)
if fresh:
    raw, live, broken = b"", {}, None
else:
    raw, live, broken = load(live_path, "live file")

intended = intended_bytes(live, broken is not None)
added, changed, removed, preserved = deltas({} if broken is not None else live)
same = broken is None and raw == intended

def archive_bytes(data):
    # Exclusive create with a microsecond stamp: a one-second stamp plus "wb"
    # would overwrite an archive made in the same second, losing bytes silently.
    stem = os.path.join(live_dir, "settings.json.unparsable-"
                        + time.strftime("%Y%m%dT%H%M%S", time.gmtime())
                        + "-" + str(int((time.time() % 1) * 1000000)).zfill(6))
    path = stem
    n = 2
    while True:
        try:
            with open(path, "xb") as f:
                f.write(data)
            return path
        except FileExistsError:
            path = stem + "-" + str(n)
            n += 1

def packages_note():
    # `packages` is live-wins, so a template edit never propagates by itself; say
    # so, or "-n is the promote worklist" would be false for the one key that
    # cannot be promoted by editing alone.
    if live is not None and "packages" in live and canon(live["packages"]) != canon(template["packages"]):
        print("  note     packages        live wins (a pi install/remove is deliberate); the template differs"
              " — run the install here or commit the template edit")
        return True
    return False

def report(dry, backup):
    if fresh:
        print("  create   " + live_path + " (no live file yet)")
    if broken is not None:
        print("  repair   " + live_path + " is " + broken + " — "
              + ("would be rebuilt from the template" if dry else "rebuilt from the template"))
        if backup is not None:
            print("  archived " + backup + " (the live bytes, so nothing is lost silently)")
    for k in added:
        print("  added    " + k.ljust(22) + " " + show(template[k]))
    for k in changed:
        print("  changed  " + k.ljust(22) + " " + show(live[k]) + " -> " + show(template[k]))
    for k in removed:
        print("  removed  " + k.ljust(22) + " " + show(live[k]) + " (not declared in the template)")
    if preserved:
        print("  preserved " + ", ".join(preserved)
              + " (live-only: promote by adding it to the template, or drop with --prune)")
    if broken is None and not (added or changed or removed) and not same:
        print("  cosmetic " + live_path + " is not byte-identical to the template (formatting only)")
    packages_note()

if same:
    pkg = packages_note()
    print("pi-settings-apply: no drift — " + live_path + " matches the template"
          + (" (except packages, see note)" if pkg else ""))
    sys.exit(0)

if DRY:
    report(True, None)
    print("pi-settings-apply: --dry-run — " + live_path + " left untouched")
    sys.exit(1)

os.makedirs(live_dir, exist_ok=True)

backup = None
if broken is not None:
    backup = archive_bytes(raw)

mode = os.stat(live_path if not fresh else template_path).st_mode & 0o7777
out = intended
torn_backup = None
for attempt in range(3):
    # Sweep a temp left behind by a killed run. The threshold is far above the
    # millisecond window this file is open, so it cannot hit a live one.
    for stale in os.listdir(live_dir):
        if not stale.startswith(".pi-settings-apply."):
            continue
        path = os.path.join(live_dir, stale)
        try:
            if time.time() - os.stat(path).st_mtime > 60:
                os.unlink(path)
        except OSError:
            pass
    fd, tmp = tempfile.mkstemp(dir=live_dir, prefix=".pi-settings-apply.")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(out)
        os.chmod(tmp, mode)          # mkstemp is 0600; keep the file its own mode
        os.replace(tmp, live_path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    # Catches a write that lands after our replace, so the common lost update is
    # folded back in and re-applied here. It cannot see a write that opened the
    # old inode before the replace — hence the header caveat.
    try:
        with open(live_path, "rb") as f:
            now = f.read()
    except OSError:
        now = b""
    if now == out:
        break
    time.sleep(0.05)
    raw2, live2, broken2 = load(live_path, "live file")
    if broken2 is not None:
        # A concurrent write tore the file during our retry. Rebuilding from the
        # template and reporting success would drop those bytes silently, so
        # archive them and make the run exit 1.
        torn_backup = archive_bytes(raw2)
        out = intended_bytes({}, True)
    else:
        out = intended_bytes(live2, False)
else:
    die("a pi session kept writing while this ran (3 attempts) — re-run once it has settled")

if torn_backup is not None:
    backup = torn_backup
report(False, backup)
print("pi-settings-apply: " + live_path
      + (" rebuilt from the template (live bytes archived)"
         if (broken is not None or torn_backup is not None)
         else " created from the template" if fresh
         else " updated from the template"))
sys.exit(1 if (broken is not None or torn_backup is not None) else 0)
'
    command python3 -c "$py" "$template_path" "$live_path" "$dry_flag" "$prune_flag"
end

function pi-settings-apply --description 'Apply the tracked pi settings template to the host-local live settings.json'
    set -l dry 0
    set -l prune 0
    for arg in $argv
        switch $arg
            case -n --dry-run
                set dry 1
            case --prune
                set prune 1
            case -h --help
                echo 'Usage: pi-settings-apply [-n|--dry-run] [--prune]'
                return 0
            case '*'
                echo "pi-settings-apply: unknown argument: $arg" >&2
                return 2
        end
    end

    if not command -q python3
        echo 'pi-settings-apply: python3 not found (needed for the JSON merge)' >&2
        return 1
    end

    set -l repo "$HOME/dotfiles"
    set -q DOTFILES; and test -n "$DOTFILES"; and set repo "$DOTFILES"
    set -l template "$repo/base/pi/.pi/agent/settings.desired.json"
    set -l live "$HOME/.pi/agent/settings.json"

    if not test -f "$template"
        echo "pi-settings-apply: no template at $template" >&2
        echo '  it ships in base/pi — run: stow --restow --no-folding -d base -t ~ pi' >&2
        return 1
    end

    __pi_settings_apply "$template" "$live" "$dry" "$prune"
end
