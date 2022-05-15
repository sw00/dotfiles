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
nmap('<space><space>',':nohlsearch<CR>')		-- cancel search highlights
nmap('<leader><leader>', '<c-^>')	-- switch to previous buffer

-- [[ Meta ]]
nmap('<leader>R', ':source "&runtimepath"/init.lua<CR>') -- reload config

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
-- tab to cycle suggestions
vim.cmd([[inoremap <silent><expr> <Tab>
      \ pumvisible() ? "\<C-n>" : "\<TAB>"]]) 
vim.cmd([[inoremap <silent><expr> <S-Tab>
      \ pumvisible() ? "\<C-p>" : "\<S-TAB>"]])

-- [[ nvim-tree ]]
nmap('<c-n>', ':NvimTreeToggle<CR>')	-- toggle nvim-tree
nmap('<F3>', ':NvimTreeFindFileToggle<CR>')	-- toggle nvim-tree

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

-- [[ lspconfig ]]
local vimcmd = function(cmd)
    return '<cmd>' .. cmd .. '<CR>'
end
-- Diagnostics - see `:h vim.diagnostic.*`
nmap('<space>e', vimcmd('lua vim.diagnostic.open_float()'))
nmap('[d', vimcmd('lua vim.diagnostic.goto_prev()'))
nmap(']d', vimcmd('lua vim.diagnostic.goto_next()'))
nmap('<space>q', vimcmd('lua vim.diagnostic.setloclist()'))

-- on_attach will only map keys once language server attaches to current buffer
function on_attach(client, bufnr)
    -- vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
    -- Use MiniCompletion on LSP client attach (overrides omnifunc)
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.MiniCompletion.completefunc_lsp')

    -- define local fn nmapbuf for code dedup/readability
    local nmapbuf = function(shortcut, cmd)
        opts = { noremap = true, silent = false }
        vim.api.nvim_buf_set_keymap(bufnr, 'n', shortcut, vimcmd(cmd), opts)
    end

    -- Mappings - see `:h vim.lsp.*`
    nmapbuf('gD', 'lua vim.lsp.buf.declaration()')	                                -- goto declaration
    nmapbuf('gd', 'lua vim.lsp.buf.definition()')	                                -- goto definition
    nmapbuf('K', 'lua vim.lsp.buf.hover()')	                                        -- show docs
    nmapbuf('gi', 'lua vim.lsp.buf.implementation()')	                            -- goto implementation
    nmapbuf('<C-k>', 'lua vim.lsp.buf.signature_help()')	                        -- show signature
    nmapbuf('<space>wa>', 'lua vim.lsp.buf.add_workspace_folder()')   	            -- add workspace folder
    nmapbuf('<space>wr>', 'lua vim.lsp.buf.remove_workspace_folder()')	            -- remove workspace folder
    nmapbuf('<space>wl>', 'lua vim.inspect(vim.lsp.buf.list_workspace_folders())')	-- remove workspace folder
    nmapbuf('<space>D', 'lua vim.lsp.buf.type_definition()')	                    -- show type definition
    nmapbuf('<space>rn', 'lua vim.lsp.buf.rename()')	                            -- rename
    nmapbuf('<space>ca', 'lua vim.lsp.buf.code_action()')	                        -- code action
    nmapbuf('gr', 'lua vim.lsp.buf.references()')	                                -- list references (show usages)
    nmapbuf('<space>f', 'lua vim.lsp.buf.formatting()')	                            -- format code 
end

-- [[ zen mode ]]
nmap('<F12>', vimcmd('ZenMode'))

