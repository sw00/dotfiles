# Autoloaded helper for work-status/build work-login. One function per file —
# see __work_aws_sso_profile.fish for why.

function __work_fly_targets --description 'Fly targets that are not local-only (from ~/.flyrc)'
    # Target names are the 2-space-indented keys under `targets:`; their fields
    # (api, team, token) sit deeper. Only that exact indent matches, so the
    # nested keys stay out.
    #
    # Targets pointing at localhost are skipped: they are a local dev Concourse,
    # never a work target, and trying to `login` to one would fail on every run
    # and leave a permanent false alarm in `work-status`.
    awk '
        function flush() {
            if (name != "" && api != "" && api !~ /localhost|127[.]0[.]0[.]1/)
                print name
        }
        /^targets:/          { intgt = 1; next }
        intgt && /^[^ \t]/     { intgt = 0 }
        intgt && /^  [^ \t]/   { flush(); name = $0; sub(/^[ \t]+/, "", name); sub(/:.*$/, "", name); api = ""; next }
        intgt && /^[ \t]+api:/ { api = $2 }
        END                  { flush() }
    ' "$HOME/.flyrc" 2>/dev/null
end
