--[[ opts.lua ]]
local opt = vim.opt

-- Prepend Mason's bin dir to PATH so subprocesses (e.g. tree-sitter build
-- invoked by nvim-treesitter) can find Mason-installed tools.
vim.env.PATH = vim.fn.stdpath 'data' .. '/mason/bin:' .. vim.env.PATH

-- [[ Context ]]
opt.number = true -- show line numbers
opt.relativenumber = true -- show relative line numbers

-- Switch to absolute line numbers in insert mode (best of both worlds)
local function update_relativenumber()
    if vim.fn.mode():match('^[iR]') then
        vim.opt.relativenumber = false
    else
        vim.opt.relativenumber = true
    end
end
vim.api.nvim_create_autocmd({ 'InsertEnter', 'InsertLeave' }, {
    desc = 'Toggle relative line numbers on InsertEnter/Leave',
    callback = update_relativenumber,
})
-- Also refresh when switching buffers or regaining focus (some tmux scenarios)
vim.api.nvim_create_autocmd({ 'BufEnter', 'FocusGained' }, {
    desc = 'Refresh relative number state on buffer enter / focus',
    callback = function()
        -- defer so mode() reflects the current state
        vim.defer_fn(update_relativenumber, 10)
    end,
})

opt.signcolumn = 'yes' -- keep signcolumn on
opt.cursorline = true -- show cursor line
opt.mouse = 'a' -- capture mouse input
opt.scrolloff = 10 -- lines above and below cursor
opt.showmode = false

-- [[ Shell ]]
-- Use fish if available; fall back to whatever $SHELL resolves to.
if vim.fn.executable 'fish' == 1 then
    opt.shell = 'fish'
end

-- [[ Code Folds ]]
opt.foldmethod = 'expr' -- folds defined by expression
opt.foldexpr = 'v:lua.vim.treesitter.foldexpr()'
opt.foldlevelstart = 5 -- only fold if level is higher than

-- [[ Filetypes ]]
opt.encoding = 'utf-8' -- string encoding
opt.fileencoding = 'utf-8' -- file encoding

-- [[ Theme ]]
vim.g.colorscheme = 'tomorrow_night_blue'
vim.o.background = 'dark'
opt.termguicolors = true -- vim colors override terminal colors

-- [[ Search ]]
opt.ignorecase = true -- ignore case in search terms
opt.smartcase = true -- except for capitalised terms
opt.hlsearch = true -- highlight search terms in buffer
opt.incsearch = true -- search terms in buffer as they are typed

-- [[ Whitespace ]]
opt.list = true -- show whitespace chars
opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' } -- show whitespace chars
opt.breakindent = true -- wrapped lines should continue from their original indent

-- [[ Splits ]]
opt.splitbelow = false -- new hsplit to the top
opt.splitright = true -- new vsplit to the right

-- [[ Completion ]]
opt.omnifunc = 'syntaxcomplete#Complete' -- vim's default omnifunc
opt.completeopt = 'menuone,noinsert,noselect' -- show info for item even if only one

-- [[ Behaviour ]]
opt.autowrite = true -- autosave buffers when losing focus
opt.hidden = true -- keep unfocused buffers hidden (instead of unloading them)
opt.autoread = true -- reload file if changed outside of vim
opt.visualbell = true -- visualbell instead of beeping

-- [[ Backup/Swapfile ]]
opt.writebackup = true -- make backup file before overwriting
opt.undofile    = true -- persist undo history across sessions
-- Store all transient files under stdpath('state') (~/.local/state/nvim)
-- rather than the old vim-style ~/.vim-tmp dirs which rarely exist.
local _state = vim.fn.stdpath 'state'
for _, sub in ipairs { 'backup', 'swap', 'undo' } do
    vim.fn.mkdir(_state .. '/' .. sub, 'p')
end
opt.backupdir = { _state .. '/backup//', '.' }
opt.directory = { _state .. '/swap//',   '.' }
opt.undodir   = { _state .. '/undo//',   '.' }

-- [[ Clipboard ]]
opt.clipboard = 'unnamedplus' -- always use clipboard (instead of vim registers)

-- [[ Optimisations ]]
opt.updatetime = 250 -- write to swapfile to disk every 250ms
opt.timeoutlen = 700 -- timeout for a mapped sequence to take

-- Diagnostic presentation: signs with nerd-font icons; no inline virtual text (too noisy).
vim.diagnostic.config {
    virtual_text = false,
    signs = {
        text = {
            [vim.diagnostic.severity.ERROR] = ' ',
            [vim.diagnostic.severity.WARN]  = ' ',
            [vim.diagnostic.severity.INFO]  = ' ',
            [vim.diagnostic.severity.HINT]  = '󰌵 ',
        },
    },
    float = {
        border = 'rounded',
        source = true, -- show which LSP reported the diagnostic
    },
    underline    = true,
    update_in_insert = false, -- don't flash diagnostics while typing
}
