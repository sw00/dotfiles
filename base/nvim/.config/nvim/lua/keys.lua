--[[ keys.lua]]
local map = vim.keymap.set

-- [[ QoL ]]
map('i', 'kj',       '<esc>',          { desc = 'Escape to normal mode' })
map('t', 'kj',       '<c-\\><c-n>',    { desc = 'Escape to normal mode (terminal)' })
map('t', '<esc><esc>','<c-\\><c-n>',   { desc = 'Escape to normal mode (terminal)' })
map('n', '<space><space>', '<cmd>nohlsearch<CR>', { desc = 'Clear search highlight' })

-- [[ Butter Fingers ]]
-- Map common capitalisation typos as Ex command aliases.
vim.cmd 'command! -bang Q   q<bang>'
vim.cmd 'command! -bang Wq  wq<bang>'
vim.cmd 'command! -bang WQ  wq<bang>'
vim.cmd 'command! -bang Xa  xa<bang>'

-- [[ Save ]]
map('n', '<F2>',    '<cmd>w<CR>', { desc = 'Save buffer' })
map('n', '<c-s>',   '<cmd>w<CR>', { desc = 'Save buffer' })
map('n', '<leader>s','<cmd>w<CR>', { desc = '[S]ave buffer' })

-- [[ Diagnostics ]]
-- ]d / [d / ]D / [D  — navigate diagnostics (owned by mini.bracketed)
map('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Show diagnostic [E]rror messages' })
map('n', '<leader>q', vim.diagnostic.setloclist,  { desc = 'Open diagnostic [Q]uickfix list' })

-- [[ Buffers ]]
map('n', '<leader>bd', function() require('mini.bufremove').delete()  end, { desc = '[B]uffer [D]elete (preserve layout)' })
map('n', '<leader>bw', function() require('mini.bufremove').wipeout() end, { desc = '[B]uffer [W]ipeout (preserve layout)' })
