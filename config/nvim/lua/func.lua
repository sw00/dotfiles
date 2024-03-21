-- [[scratch buffer]]
local mkScratch= function()
    -- vim.cmd('tabnew', false)
    vim.opt_local.buftype = 'nofile'
    vim.opt_local.bufhidden = 'hide'
    vim.opt_local.swapfile = nil
end

vim.api.nvim_set_keymap('n', '<leader>S', '<cmd>lua _G.mkScratch()<cr>', { noremap = true, silent = true})

vim.api.nvim_create_user_command('TrimWhitespace', 'lua MiniTrailspace.trim()', {})
vim.api.nvim_create_user_command('NewScratchBuffer', mkScratch, {})
