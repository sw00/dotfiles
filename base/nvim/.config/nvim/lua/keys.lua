--[[ keys.lua]]
local function map(mode, shortcut, command)
    vim.api.nvim_set_keymap(mode, shortcut, command, { noremap = true, silent = true })
end

local function nmap(shortcut, command)
    map('n', shortcut, command)
end

local function imap(shortcut, command)
    map('i', shortcut, command)
end

local function vmap(shortcut, command)
    map('v', shortcut, command)
end

local function tmap(shortcut, command)
    map('t', shortcut, command)
end

local vimcmd = function(cmd)
    return '<cmd>' .. cmd .. '<CR>'
end

-- [[ QoL ]]
imap('kj', '<esc>') -- quick escape to normal mode from insert mode
tmap('kj', '<c-\\><c-n>') -- quick escape to normal mode from terminal mode
tmap('<esc><esc>', '<c-\\><c-n>') -- quick escape to normal mode from terminal mode
nmap('<space><space>', ':nohlsearch<CR>') -- cancel search highlights

-- [[ Butter Fingers ]]
-- Map common capitalisation typos as Ex command aliases.
-- (Normal-mode maps for ':Q<CR>' never fire because ':' enters cmdline mode.)
vim.cmd 'command! -bang Q   q<bang>'
vim.cmd 'command! -bang Wq  wq<bang>'
vim.cmd 'command! -bang WQ  wq<bang>'
vim.cmd 'command! -bang Xa  xa<bang>'

-- [[ Save ]]
nmap('<F2>', ':w<CR>') -- quicksave
nmap('<c-s>', ':w<CR>') -- save current buffer

-- [[ Splits ]]
nmap('<c-j>', '<c-w>j')
nmap('<c-k>', '<c-w>k')
nmap('<c-h>', '<c-w>h')
nmap('<c-l>', '<c-w>l')

-- [[ diagnostics ]]
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Show diagnostic [E]rror messages' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })
