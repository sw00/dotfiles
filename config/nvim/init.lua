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
require('mini.completion').setup {
    fallback_action = function()
        return '<C-n><C-p>'
    end
}
require('mini.comment').setup {}
require('mini.pairs').setup {}
require('mini.trailspace').setup {}

-- lsp
local servers = {'rust_analyzer', 'pyright', 'solargraph', 'elixirls'}
for _, lsp in pairs(servers) do

    require('lspconfig')[lsp].setup {
        on_attach = on_attach -- use on_attach defined in keys.lua
    }
end

-- treesitter
ts_langs = { 'python', 'ruby', 'rust', 'elixir' }
non_ts_langs = { 'bash', 'yaml' }

require('nvim-treesitter.configs').setup {
  ensure_installed = ts_langs,
  sync_install = true, -- install parsers synchronously for ensure_installed langs

  -- List of parsers to ignore installing (for "all")
  ignore_install = { "javascript" },

  highlight = {
    enable = true,
    disable = non_ts_langs,
    additional_vim_regex_highlighting = non_tslangs,
  },
}
