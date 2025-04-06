vim.api.nvim_create_user_command('TrimWhitespace', 'lua MiniTrailspace.trim()', {})

vim.api.nvim_create_user_command('Scratch', function()
    vim.cmd('vsplit', false)
    vim.opt_local.buftype = 'nofile'
    vim.opt_local.bufhidden = 'hide'
    vim.opt_local.swapfile = nil
end, {})

vim.api.nvim_create_user_command('LightModeToggle', function()
    if vim.o.background == 'dark' then
        vim.o.background = 'light'
        vim.cmd.colorscheme 'PaperColor'
    else
        vim.o.background = 'dark'
        vim.cmd.colorscheme 'tomorrow_night_blue'
    end
end, {})
