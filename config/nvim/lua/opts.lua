--[[ opts.lua ]]
local opt = vim.opt
local cmd = vim.api.nvim_command

-- [[ Context ]]
opt.number = true			    -- show line numbers
opt.relativenumber = true		-- show relative line numbers
opt.signcolumn = 'number'		-- use number column for signs
opt.cursorline = true			-- show cursor line
opt.mouse = 'a'	                -- capture mouse input

-- [[ Shell ]]
opt.shell = 'fish'              -- shell

-- [[ Code Folds ]]
opt.foldmethod = "indent"       -- folds defined by indentation

-- [[ Filetypes ]]
opt.encoding = 'utf-8'			-- string encoding
opt.fileencoding = 'utf-8'		-- file encoding

-- [[ Theme ]]
cmd('colo ' .. OPTIONS.theme)
opt.syntax = 'on'				-- enable syntax highlighting
opt.termguicolors = true		-- vim colors override terminal colors

-- [[ Search ]]
opt.ignorecase = true			-- ignore case in search terms
opt.smartcase = true			-- except for capitalised terms
opt.hlsearch = true			    -- highlight search terms in buffer
opt.incsearch = true			-- search terms in buffer as they are typed

-- [[ Whitespace ]]
opt.listchars = 'space:·,eol:¬,tab:▸~'	-- show whitespace chars
opt.expandtab = true			        -- use spaces instead of tabs
opt.shiftwidth = 4			            -- indent size is 4 chars
opt.softtabstop = 4			            -- replace tabs with this many spaces in insert mode
opt.tabstop = 4				            -- number of spaces tabs represent

-- [[ Splits ]]
opt.splitbelow = false			-- new hsplit to the top
opt.splitright = true			-- new vsplit to the right

-- [[ Completion ]]
opt.omnifunc = 'syntaxcomplete#Complete' -- vim's default omnifunc
opt.completeopt = 'menuone,noinsert,noselect'	-- show info for item even if only one

-- [[ Behaviour ]]
opt.autowrite = true			-- autosave buffers when losing focus
opt.hidden = true			-- keep unfocused buffers hidden (instead of unloading them)
opt.autoread = true			-- reload file if changed outside of vim
opt.visualbell = true			-- visualbell instead of beeping

-- [[ Backup/Swapfile ]]
opt.writebackup = true			-- make backup file before overwriting
opt.backupdir='~/.vim-tmp,~/.tmp,~/tmp,/var/tmp/,/tmp'
opt.directory='~/.vim-tmp,~/.tmp,~/tmp,/var/tmp/,/tmp'

-- [[ Clipboard ]]
opt.clipboard = 'unnamedplus'		-- always use clipboard (instead of vim registers)

