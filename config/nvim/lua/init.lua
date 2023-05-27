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
local gps = require('nvim-gps')
gps.setup { depth = 4 }
require('lualine').setup {
    options = { theme = 'nord' },
    sections = {
        lualine_c = {
            'filename',
            { gps.get_location, cond = gps.is_available },
        }
    }
}

-- editor plugins
require('mini.comment').setup {}
require('mini.pairs').setup {}
require('mini.trailspace').setup {}
require('mini.surround').setup {}
require('mini.tabline').setup {}

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

  -- List of parsers to ignore installing (for "all")
  ignore_install = { "javascript" },

  highlight = {
    enable = true,
    disable = non_ts_langs,
    additional_vim_regex_highlighting = non_ts_langs,
  },
}

