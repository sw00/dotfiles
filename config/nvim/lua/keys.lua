--[[ keys.lua]]
local map = vim.api.nvim_set_keymap

function map(mode, shortcut, command)
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
nmap(':Q<CR>', ':q<CR>')
nmap(':Wq<CR>', ':wq<CR>')
nmap(':WQ<CR>', ':wq!<CR>')
nmap(':wQ<CR>', ':wq!<CR>')
nmap(':X<CR>', ':x!<CR>')

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

-- [[ zen mode ]]
nmap('<F12>', vimcmd 'ZenMode')
