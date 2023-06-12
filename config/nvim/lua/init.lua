-- REMAP LEADER KEY
vim.g.mapleader = ","
vim.g.localleader = "\\"

local packer_path = vim.fn.stdpath('config') .. '/packer.nvim/lua'
vim.o.packpath = vim.o.packpath .. ',' .. packer_path

-- IMPORTS
require('vars') -- Variables
require('opts') -- Options
require('keys') -- Keymaps
require('plug') -- Plugins
require('func') -- Functions

-- PLUGINS
require('nvim-tree').setup{}
require('lualine').setup {
    options = { theme = 'nord' },
    sections = {
        lualine_c = {
            'filename',
            'navic'
        }
    }
}
require'fidget'.setup {}

-- editor plugins
require'mini.comment'.setup {}
require'mini.pairs'.setup {}
require'mini.trailspace'.setup {}
require'mini.surround'.setup {}
require'mini.bufremove'.setup {}
require'mini.bracketed'.setup {}

-- tabline
require('mini.tabline').setup {
	tabpage_section = 'none'
}
vim.cmd("au FileType * if index(['gitcommit','fugitive'], &ft) >= 0 | let b:minitabline_disable=v:true | endif")

-- completion
require('settings.completion')
require('settings.snippy')
require('settings.null-ls')

-- tags
require'symbols-outline'.setup()

-- diagnostics
vim.diagnostic.config { virtual_text = false, underline = true }

-- treesitter
local ts_langs = { 'python', 'ruby', 'rust', 'elixir', 'lua' }
local non_ts_langs = { 'bash', 'yaml', 'json' }

require('nvim-treesitter.configs').setup {
    ensure_installed = ts_langs,
    sync_install = true, -- install parsers synchronously for ensure_installed langs
    indent = { enable = true },

    -- List of parsers to ignore installing (for "all")
    ignore_install = { "javascript" },

    highlight = {
        enable = true,
        disable = non_ts_langs,
        additional_vim_regex_highlighting = non_ts_langs,
    },

    incremental_selection = {
        enable = true,
        keymaps = {
            init_selection = '<leader>s',
            node_incremental = '<leader>s',
            scope_incremental = '<c-space>',
            scope_decremental = '<c-backspace'
        }
    },

}

-- codeolding

-- terminal
require("toggleterm").setup {
    open_mapping = [[<c-\>]],
    shell = "fish",
    direction = 'float',
    float_opts = {
        border = 'rounded'
    }
}
vim.api.nvim_set_keymap('n', '<c-~>', '<cmd>ToggleTerm<cr>', { noremap = true, silent = true })
vim.cmd('au TermOpen * setlocal nonumber norelativenumber')
