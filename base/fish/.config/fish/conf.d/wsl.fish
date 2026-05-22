# WSL-specific Fish configuration
# Sourced automatically by Fish via conf.d on all platforms;
# guards below ensure it only takes effect on WSL.

string match -qi '*microsoft*' (uname -r 2>/dev/null); or return

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

# Quick PowerShell shorthand
abbr --add --global psh 'powershell.exe -Command'
