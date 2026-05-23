# WSL-specific Fish configuration
# Sourced automatically by Fish via conf.d on all platforms;
# guards below ensure it only takes effect on WSL.

string match -qi '*microsoft*' (uname -r 2>/dev/null); or return

# Resolve %LOCALAPPDATA% to a WSL path once at startup so the codium
# function below can locate VSCodium.exe without calling cmd.exe each time.
if command -q cmd.exe; and not set -q WIN_LOCALAPPDATA
    set -gx WIN_LOCALAPPDATA \
        (wslpath (cmd.exe /c 'echo %LOCALAPPDATA%' 2>/dev/null | string trim))
end

# Clipboard: bridge to the Windows clipboard
function pbcopy
    clip.exe
end

function pbpaste
    powershell.exe -Command \
        '[Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))'
end

# Open files and URLs with the Windows desktop (requires wslu)
function opn
    if command -q wslview
        wslview $argv
    else
        explorer.exe $argv
    end
end

# Open a folder in the Windows VSCodium app via the Remote WSL extension.
#
# Two cases:
#   1. Inside VSCodium's integrated terminal: VSCODE_IPC_HOOK_CLI is set by
#      the server process.  Delegate straight to the remote-cli binary so it
#      can forward the command to the running host window (existing behaviour).
#   2. Any other terminal (e.g. Alacritty): launch VSCodium.exe directly with
#      a vscode-remote://wsl+<distro>/<path> folder URI so the Remote WSL
#      extension mounts the Linux filesystem as the workspace root.
function codium --description 'Open VSCodium (WSL → Windows via Remote WSL URI)'
    if set -q VSCODE_IPC_HOOK_CLI
        command codium $argv
        return
    end

    # Locate VSCodium.exe — user install wins over system-wide install.
    set -l _exe
    for _c in \
        "$WIN_LOCALAPPDATA/Programs/VSCodium/VSCodium.exe" \
        "/mnt/c/Program Files/VSCodium/VSCodium.exe"
        if test -f "$_c"
            set _exe "$_c"
            break
        end
    end
    if test -z "$_exe"
        echo "codium: VSCodium.exe not found" >&2
        return 1
    end

    # Partition arguments: flags (start with -) vs path targets (everything else).
    set -l _flags
    set -l _uris
    for _a in $argv
        if string match -q -- '-*' "$_a"
            set -a _flags "$_a"
        else if test -e "$_a"
            set -a _uris --folder-uri \
                "vscode-remote://wsl+$WSL_DISTRO_NAME"(realpath -- "$_a")
        else
            # Non-path, non-flag (e.g. an extension ID) — pass straight through.
            set -a _flags "$_a"
        end
    end

    # No path arguments supplied → open the current directory.
    if test (count $_uris) -eq 0
        set _uris --folder-uri \
            "vscode-remote://wsl+$WSL_DISTRO_NAME"(realpath .)
    end

    "$_exe" $_flags $_uris &
    disown
end

# Quick PowerShell shorthand
abbr --add --global psh 'powershell.exe -Command'
