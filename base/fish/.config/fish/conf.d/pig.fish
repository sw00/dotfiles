# Make PiG share pi's state dir (~/.pi/agent + the project's .pi/).
#
# `1` is the ONLY enabling value — anything else (0, true, "", unset) leaves PiG
# on its own ~/.pig/agent, with a separate trust store, separate auth and
# separate sessions. This is the whole no-lock-in mechanism: with it set, `pi`
# and `pig` read the same settings, auth and sessions, so rollback is one
# symlink flip (`pi-use pi`) and there is no migration either way. ~/.pig stays
# what it is — PiG's SDK/Piglet cache — and is never stowed or merged.
#
# It lives here, in the shell, and NEVER in ~/.pi/agent/settings.json: settings
# travel with the shared dir, so a setting there would follow the rollback
# binary too, and `pi` would be the one carrying a PiG-only key. As a conf.d
# file it applies to every interactive fish on every platform, is visible to
# `git` in this repo, and rolls back by deleting one line.
set -gx PIG_USE_PI_DIRS 1
