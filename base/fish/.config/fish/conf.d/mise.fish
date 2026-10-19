# Switch off Homebrew's mise vendor drop-in.
#
# /opt/homebrew/share/fish/vendor_conf.d/mise-activate.fish ships with the brew
# mise formula and runs `mise activate fish` — DYNAMIC mode — on every shell,
# unless MISE_FISH_AUTO_ACTIVATE=0. That duplicates config.fish's deliberate
# --shims activation and defeats its whole point: dynamic mode prepends one
# directory per active tool (~46 of them on this machine), pays the ~76ms
# hook-env scan on every shell, and pins `latest` globally instead of leaving
# version selection to the shims.
#
# This has to be a conf.d file rather than a line in config.fish: fish sources
# conf.d/ BEFORE the vendor drop-in and config.fish only after it, so setting it
# in config.fish would be one shell too late. Verified by counting PATH entries
# with and without it (64 -> 16).
#
# Harmless on Linux/WSL, where no such drop-in exists.
set -gx MISE_FISH_AUTO_ACTIVATE 0
