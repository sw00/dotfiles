vim.api.nvim_create_user_command('TrimWhitespace', function() require('mini.trailspace').trim() end, {})

vim.api.nvim_create_user_command('Scratch', function()
    vim.cmd 'new'
    vim.bo.buftype = 'nofile'
    vim.bo.bufhidden = 'wipe'
    vim.bo.swapfile = false
end, {})

-- Load project-local config from the current directory's .nvim.lua (if it exists).
-- Useful for per-project LSP overrides, formatter settings, etc.
-- This is called once at VimEnter, and can also be invoked manually.
function _G.load_project_config()
    local root = vim.fn.getcwd()
    local config_file = root .. '/.nvim.lua'
    if vim.fn.filereadable(config_file) == 1 then
        vim.cmd('luafile ' .. vim.fn.fnameescape(config_file))
    end
end

vim.api.nvim_create_autocmd('VimEnter', {
    desc = 'Load project-local .nvim.lua if present',
    callback = _G.load_project_config,
})

vim.api.nvim_create_user_command('LightModeToggle', function()
    if vim.o.background == 'dark' then
        vim.o.background = 'light'
        -- lazy-load papercolor-theme if not already loaded
        pcall(function() require('lazy').load { plugins = { 'papercolor-theme' } } end)
        vim.cmd.colorscheme 'PaperColor'
    else
        vim.o.background = 'dark'
        vim.cmd.colorscheme 'tomorrow_night_blue'
    end
end, {})
