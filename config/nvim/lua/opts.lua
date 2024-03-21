--[[ opts.lua ]]
local opt = vim.opt

-- [[ Context ]]
opt.number = true      -- show line numbers
-- opt.relativenumber = true		-- show relative line numbers
opt.signcolumn = 'yes' -- keep signcolumn on
opt.cursorline = true  -- show cursor line
opt.mouse = 'a'        -- capture mouse input
opt.scrolloff = 10     -- lines above and below cursor
opt.showmode = false

-- [[ Shell ]]
opt.shell = 'fish' -- shell

-- [[ Code Folds ]]
opt.foldmethod = 'expr' -- folds defined by expression
opt.foldexpr = 'nvim_treesitter#foldexpr()'
opt.foldlevelstart = 5  -- only fold if level is higher than

-- [[ Filetypes ]]
opt.encoding = 'utf-8'     -- string encoding
opt.fileencoding = 'utf-8' -- file encoding

-- [[ Theme ]]
-- cmd('colo ' .. 'tomorrow_night_blue')
opt.syntax = 'on'        -- enable syntax highlighting
opt.termguicolors = true -- vim colors override terminal colors

-- [[ Search ]]
opt.ignorecase = true -- ignore case in search terms
opt.smartcase = true  -- except for capitalised terms
opt.hlsearch = true   -- highlight search terms in buffer
opt.incsearch = true  -- search terms in buffer as they are typed

-- [[ Whitespace ]]
opt.list = true -- show whitespace chars
opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' } -- show whitespace chars
opt.expandtab = true -- use spaces instead of tabs
opt.shiftwidth = 4 -- indent size is 4 chars
opt.softtabstop = 4 -- replace tabs with this many spaces in insert mode
opt.tabstop = 4 -- number of spaces tabs represent
opt.breakindent = true -- wrapped lines should continue from their original indent

-- [[ Splits ]]
opt.splitbelow = false -- new hsplit to the top
opt.splitright = true  -- new vsplit to the right

-- [[ Completion ]]
opt.omnifunc = 'syntaxcomplete#Complete'      -- vim's default omnifunc
opt.completeopt = 'menuone,noinsert,noselect' -- show info for item even if only one

-- [[ Behaviour ]]
opt.autowrite = true  -- autosave buffers when losing focus
opt.hidden = true     -- keep unfocused buffers hidden (instead of unloading them)
opt.autoread = true   -- reload file if changed outside of vim
opt.visualbell = true -- visualbell instead of beeping

-- [[ Backup/Swapfile ]]
opt.writebackup = true -- make backup file before overwriting
opt.undofile = true    -- save undo history
opt.backupdir = '~/.vim-tmp,~/.tmp,~/tmp,/var/tmp/,/tmp'
opt.directory = '~/.vim-tmp,~/.tmp,~/tmp,/var/tmp/,/tmp'
opt.undodir = '~/.vim-tmp,~/.tmp,~/tmp,/var/tmp/,/tmp'

-- [[ Clipboard ]]
opt.clipboard = 'unnamedplus' -- always use clipboard (instead of vim registers)

-- [[ Optimisations ]]
opt.updatetime = 250 -- write to swapfile to disk every 250ms
opt.timeoutlen = 700 -- timeout for a mapped sequence to take

-- disable inline diagnostic text
vim.diagnostic.config({ virtual_text = false })
