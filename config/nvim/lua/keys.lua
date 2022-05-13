--[[ keys.lua]]
local map = vim.api.nvim_set_keymap

function map(mode, shortcut, command)
	vim.api.nvim_set_keymap(mode, shortcut, command, { noremap = true, silent = true })
end

function nmap(shortcut, command)
	map('n', shortcut, command)
end

function imap(shortcut, command)
	map('i', shortcut, command)
end

function vmap(shortcut, command)
	map('v', shortcut, command)
end

function tmap(shortcut, command)
	map('t', shortcut, command)
end

-- [[ QoL ]]
imap('kj','')				-- quick escape to normal mode from insert mode
tmap('kj','')				-- quick escape to normal mode from terminal mode
nmap('<space>',':nohlsearch<CR>')		-- cancel search highlights
nmap('<leader><leader>', '<c-^>')	-- switch to previous buffer

-- [[ Butter Fingers ]]
nmap(':Q<CR>', ':q<CR>') 
nmap(':Wq<CR>', ':wq<CR>') 
nmap(':WQ<CR>', ':wq!<CR>') 
nmap(':wQ<CR>', ':wq!<CR>') 
nmap(':X<CR>', ':x!<CR>') 

-- [[ Save ]]
nmap('<F2>', ':w<CR>')			-- quicksave
nmap('<c-s>', ':w<CR>')			-- save current buffer
nmap('<c-S>', ':w!<CR>')		-- force save current buffer

-- [[ Comments ]]
nmap('<c-/>', '<Plug>CommentaryLine')	-- comment out line
vmap('<c-/>', '<Plug>Commentary')	-- comment out selection

-- [[ Splits ]]
nmap('<c-j>', '<c-w>j')
nmap('<c-k>', '<c-w>k')
nmap('<c-h>', '<c-w>h')
nmap('<c-l>', '<c-w>l')

-- [[ Tabs ]]
nmap('<tab>', ':tabn<CR>')		    -- next tab
nmap('<S-tab>', ':tabp<CR>')		-- previous tab

-- [[ Completion ]]
imap('<c-space>', '<c-x><c-o>')		-- trigger omni-completion

-- [[ nvim-tree ]]
nmap('<c-n>', ':NvimTreeToggle<CR>')	-- toggle nvim-tree

-- [[ telescope ]]
nmap('<leader>ff', '<cmd>Telescope find_files<cr>')
nmap('<leader>fg', '<cmd>Telescope live_grep<cr>')
nmap('<leader>fb', '<cmd>Telescope buffers<cr>')
nmap('<leader>fh', '<cmd>Telescope help_tags<cr>')

