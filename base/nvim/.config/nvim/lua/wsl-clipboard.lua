-- Clipboard integration for WSL (Windows Subsystem for Linux).
-- Uses powershell.exe for paste (handles Windows-style \r\n line endings)
-- and clip.exe for copy.
--
-- Only loaded when WSL_DISTRO_NAME environment variable is set.

local ps_paste = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))'
vim.g.clipboard = {
    name          = 'WslClipboard',
    copy          = { ['+'] = 'clip.exe', ['*'] = 'clip.exe' },
    paste         = { ['+'] = ps_paste,   ['*'] = ps_paste   },
    cache_enabled = 0,
}
