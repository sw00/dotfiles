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
imap('kj', '') -- quick escape to normal mode from insert mode
tmap('kj', '') -- quick escape to normal mode from terminal mode
nmap('<space><space>', ':nohlsearch<CR>') -- cancel search highlights
nmap('<leader><leader>', '<c-^>') -- switch to previous buffer
nmap('<leader>ns', '<cmd>lua NewScratch()<cr>') -- open a scratch buffer

-- [[ Meta ]]
nmap('<leader>R', ':source $MYVIMRC<CR>') -- reload config

-- [[ Butter Fingers ]]
nmap(':Q<CR>', ':q<CR>')
nmap(':Wq<CR>', ':wq<CR>')
nmap(':WQ<CR>', ':wq!<CR>')
nmap(':wQ<CR>', ':wq!<CR>')
nmap(':X<CR>', ':x!<CR>')

-- [[ Save ]]
nmap('<F2>', ':w<CR>') -- quicksave
nmap('<c-s>', ':w<CR>') -- save current buffer
nmap('<c-S>', ':w!<CR>') -- force save current buffer

-- [[ Comments ]]
nmap('<c-/>', '<Plug>CommentaryLine') -- comment out line
vmap('<c-/>', '<Plug>Commentary') -- comment out selection

-- [[ Splits ]]
nmap('<c-j>', '<c-w>j')
nmap('<c-k>', '<c-w>k')
nmap('<c-h>', '<c-w>h')
nmap('<c-l>', '<c-w>l')

-- [[ Tabs ]]
nmap('<tab>', ':tabn<CR>') -- next tab
nmap('<S-tab>', ':tabp<CR>') -- previous tab

-- [[ nvim-tree ]]
nmap('<c-n>', ':NvimTreeToggle<CR>') -- toggle nvim-tree
nmap('<F3>', ':NvimTreeFindFileToggle<CR>') -- toggle nvim-tree

-- [[ telescope ]]
nmap('<leader>ff', '<cmd>Telescope find_files<cr>')
nmap('<leader>fg', '<cmd>Telescope live_grep<cr>')
nmap('<leader>fb', '<cmd>Telescope buffers<cr>')
nmap('<leader>fh', '<cmd>Telescope help_tags<cr>')
nmap('<leader>fr', '<cmd>Telescope lsp_references<cr>')
nmap('<leader>fi', '<cmd>Telescope lsp_implementations<cr>')
nmap('<leader>fd', '<cmd>Telescope lsp_definitions<cr>')

-- [[ version control ]]
nmap('<c-G>', [[:Git<CR>]])
nmap('<c-gl>', '[[:GV<CR>]]')

-- [[ tagbar ]]
nmap('<F8>', [[:TagbarToggle<CR>]])
nmap('<leader>gv', [[:GV<CR>]])

-- [[ trouble ]]
nmap('<leader>xx', vimcmd('TroubleToggle'))
nmap('<leader>xw', vimcmd('TroubleToggle workspace_diagnostics'))
nmap('<leader>xd', vimcmd('TroubleToggle document_diagnostics'))
nmap('<leader>xq', vimcmd('TroubleToggle quickfix'))
nmap('<leader>xl', vimcmd('TroubleToggle loclist'))
nmap('gR', vimcmd('TroubleToggle lsp_references'))

-- [[ lspconfig ]]
-- Diagnostics - see `:h vim.diagnostic.*`
nmap('<space>e', vimcmd('lua vim.diagnostic.open_float()'))
nmap('[d', vimcmd('lua vim.diagnostic.goto_prev()'))
nmap(']d', vimcmd('lua vim.diagnostic.goto_next()'))
nmap('<space>q', vimcmd('lua vim.diagnostic.setloclist()'))

-- [[formatting]]
nmap('<space>f', vimcmd('lua vim.lsp.buf.format { async = true }')) -- format code

-- [[ zen mode ]]
nmap('<F12>', vimcmd('ZenMode'))
