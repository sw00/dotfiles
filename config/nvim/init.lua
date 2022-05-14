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
require('lualine').setup {
    options = { theme = 'papercolor_dark' }
}

-- editor plugins (github.com/echasnovski/mini.nvim)
require('mini.completion').setup {}
require('mini.surround').setup {}  
require('mini.comment').setup {}   
require('mini.pairs').setup {}

-- lsp
local servers = {'rust_analyzer', 'pyright', 'solargraph', 'sumneko_lua', 'elixirls'}
for _, lsp in pairs(servers) do

    require('lspconfig')[lsp].setup {
        on_attach = on_attach -- use on_attach defined in keys.lua
    }
end

-- treesitter
ts_langs = { 'python', 'ruby', 'rust', 'elixir' }
non_ts_langs = { 'bash', 'json', 'yaml' }

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

