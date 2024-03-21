-- VIM STARTUP GLOBALS
-- vim.cmd([[let g:did_load_filetypes = 1]])     -- disable filetype.vim
-- vim.cmd([[let g:do_filetype_lua = 1]]) 	      -- enable filetype.lua

-- REMAP LEADER KEY
vim.g.mapleader = ","
vim.g.localleader = "\\"

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- add plugins
require('lazy').setup('plugins')

-- IMPORTS
require('vars') -- Variables
require('opts') -- Options
require('keys') -- Keymaps
require('func') -- Functions

-- PLUGINS
require('nvim-tree').setup {}
require('lualine').setup {
    options = { theme = 'nord' },
    sections = {
        lualine_c = {
            'filename',
            'navic'
        }
    }
}
require 'fidget'.setup {
    integration = {
        ["nvim-tree"] = { enable = true }
    }
}

-- editor plugins
require 'mini.comment'.setup {}
require 'mini.pairs'.setup {}
require 'mini.trailspace'.setup {}
require 'mini.surround'.setup {}
require 'mini.bufremove'.setup {}
require 'mini.bracketed'.setup {}

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
require 'symbols-outline'.setup()

-- diagnostics
vim.diagnostic.config { virtual_text = false, underline = true }

-- treesitter
local ts_langs = { 'python', 'ruby', 'rust', 'elixir', 'lua' }
local non_ts_langs = { 'bash', 'yaml', 'json', 'vimdoc' }

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

-- -- testing
-- require('neotest').setup {
--     consumers = {
--         require('neotest').output_panel
--     },
--     adapters = {
--         require('neotest-python'),
--         require('neotest-vim-test') {
--             ignore_filetypes = { "python" }
--         }
--     }
-- }

-- terminal
require("toggleterm").setup {
    open_mapping = [[<c-\>]],
    direction = 'float',
    shell = vim.o.shell,
    float_opts = {
        border = 'rounded'
    }
}
vim.api.nvim_set_keymap('n', '<c-~>', '<cmd>ToggleTerm<cr>', { noremap = true, silent = true })
vim.cmd('au TermOpen * setlocal nonumber norelativenumber')

local in_wsl = os.getenv("WSL_DISTRO_NAME") ~= nil

if in_wsl then
    vim.cmd([[
    let g:clipboard = {
                \   'name': 'WslClipboard',
                \   'copy': {
                \      '+': 'clip.exe',
                \      '*': 'clip.exe',
                \    },
                \   'paste': {
                \      '+': 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
                \      '*': 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
                \   },
                \   'cache_enabled': 0,
                \ }
]])
end
