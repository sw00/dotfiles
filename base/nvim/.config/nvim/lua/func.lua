vim.api.nvim_create_user_command('TrimWhitespace', function() require('mini.trailspace').trim() end, {})

vim.api.nvim_create_user_command('Scratch', function()
    vim.cmd 'new'
    vim.bo.buftype = 'nofile'
    vim.bo.bufhidden = 'wipe'
    vim.bo.swapfile = false
end, {})

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
