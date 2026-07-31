# tt.fish — TokenTelemetry on-demand control
#
# Usage: tt up | down | restart | logs | ps | status | update
#
# Requires: docker (colima on macOS, native on Linux/WSL)
# Compose config: ~/.config/tokentelemetry/compose.pi.yml
# Env file:       ~/.config/tokentelemetry/env.tt
# Data:           ~/.local/share/tokentelemetry/

function __tt_docker
    # On macOS, docker needs the colima socket.  Systemd/Linux uses the
    # default socket; WSL's docker CLI forwards to the Windows side.
    set -l docker_args
    if test (uname -s) = Darwin
        set -l sock "$HOME/.colima/default/docker.sock"
        if test -S "$sock"
            set docker_args -H "unix://$sock"
        else
            echo "tt: colima socket not found at $sock — is colima running?" >&2
            return 1
        end
    end
    command docker $docker_args $argv
end

function __tt_compose
    set -l config_dir "$HOME/.config/tokentelemetry"
    set -l compose_file "$config_dir/compose.pi.yml"
    set -l env_file "$config_dir/env.tt"

    if not test -f "$compose_file"
        echo "tt: compose file not found at $compose_file" >&2
        echo "    run: stow --target ~ base/tokentelemetry" >&2
        return 1
    end

    __tt_docker compose \
        --project-name tokentelemetry \
        --file "$compose_file" \
        --env-file "$env_file" \
        $argv
end

function __tt_ensure_data_dir
    set -l data_dir "$HOME/.local/share/tokentelemetry"
    if not test -d "$data_dir"
        echo "→ creating data directory: $data_dir"
        command mkdir -p "$data_dir"
    end
end

function __tt_ensure_images
    # Pull images if they aren't already present locally.
    set -l env_file "$HOME/.config/tokentelemetry/env.tt"
    if not test -f "$env_file"
        return 0
    end

    # Extract image references from env.tt (lines like TT_BACKEND_IMAGE=...)
    for line in (grep -E '^TT_(BACKEND|FRONTEND)_IMAGE=' "$env_file")
        set -l image (string split -m1 = -- "$line")[2]
        if test -n "$image"
            # Check if image exists locally
            if not __tt_docker image inspect "$image" >/dev/null 2>&1
                echo "→ pulling $image"
                __tt_docker pull "$image" || return 1
            end
        end
    end
end

function tt --description "TokenTelemetry on-demand control"
    set -l cmd "$argv[1]"

    switch "$cmd"
        case up
            __tt_ensure_data_dir
            __tt_ensure_images
            echo "→ starting TokenTelemetry…"
            __tt_compose up --detach --wait
            set -l fp $frontend_port
            test -z "$fp" && set fp 13000
            echo "✓ TokenTelemetry running → http://localhost:$fp"

        case down stop
            __tt_compose down
            echo "✓ TokenTelemetry stopped"

        case restart
            __tt_compose down
            __tt_compose up --detach --wait
            echo "✓ TokenTelemetry restarted"

        case logs
            __tt_compose logs --follow --tail=50 $argv[2..-1]

        case ps
            __tt_compose ps $argv[2..-1]

        case status
            if __tt_compose ps --format json 2>/dev/null | grep -q '"State":"running"'
                set -l fp (grep -E '^TT_FRONTEND_PORT=' "$HOME/.config/tokentelemetry/env.tt" | string split -m1 = | string trim)[2]
                test -z "$fp" && set fp 13000
                echo "● TokenTelemetry running → http://localhost:$fp"
                __tt_compose ps
            else
                echo "○ TokenTelemetry not running"
            end

        case update
            echo "→ pulling latest images…"
            set -l env_file "$HOME/.config/tokentelemetry/env.tt"
            set -l backend_image "ghcr.io/vasihemanth/tokentelemetry-backend:latest"
            set -l frontend_image "ghcr.io/vasihemanth/tokentelemetry-frontend:latest"

            __tt_docker pull "$backend_image" || return 1
            __tt_docker pull "$frontend_image" || return 1

            set -l backend_digest (__tt_docker image inspect "$backend_image" --format '{{index .RepoDigests 0}}' | string replace -r '.*@' '')
            set -l frontend_digest (__tt_docker image inspect "$frontend_image" --format '{{index .RepoDigests 0}}' | string replace -r '.*@' '')

            echo "→ recording new digests in env.tt"
            command sed -i '' -E "s/(TT_BACKEND_IMAGE=.*@)sha256:[0-9a-f]+/\1sha256:$backend_digest/" "$env_file"
            command sed -i '' -E "s/(TT_FRONTEND_IMAGE=.*@)sha256:[0-9a-f]+/\1sha256:$frontend_digest/" "$env_file"

            echo "✓ digests updated — commit env.tt to pin across machines"
            echo "→ recreating containers with new images…"
            __tt_compose down
            __tt_compose up --detach --wait
            echo "✓ TokenTelemetry updated and restarted"

        case help ''
            echo "Usage: tt up | down | restart | logs | ps | status | update"
            echo ""
            echo "  tt up       Start TokenTelemetry (pulls images if missing)"
            echo "  tt down     Stop and remove containers (data persists)"
            echo "  tt restart  Down then up"
            echo "  tt logs     Tail compose logs"
            echo "  tt ps       Show running services"
            echo "  tt status   Check if running + dashboard URL"
            echo "  tt update   Pull latest images, record digests, recreate containers"
            echo ""
            echo "Dashboard:  http://localhost:13000"
            echo "Config:     ~/.config/tokentelemetry/compose.pi.yml"
            echo "Data:       ~/.local/share/tokentelemetry/"

        case '*'
            echo "tt: unknown command '$cmd' — try: tt up | down | restart | logs | ps | status | update" >&2
            return 1
    end
end
