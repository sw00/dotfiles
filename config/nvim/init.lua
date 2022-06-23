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
require('mini.completion').setup {
    lsp_completion = {source_func = 'omnifunc', auto_setup = false},
    fallback_action = function()
        return '<C-X><C-I>'
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

require('lspconfig').sumneko_lua.setup {
    cmd = {'/home/sett/.local/share/nvim/lsp_servers/sumneko_lua/extension/server/bin/lua-language-server'},
    on_attach = on_attach
}

-- null-ls
local null_ls = require('null-ls')
null_ls.setup {
    sources = {
        null_ls.builtins.formatting.terraform_fmt,
        null_ls.builtins.formatting.rubocop,
        null_ls.builtins.formatting.black,
        null_ls.builtins.formatting.isort,
        null_ls.builtins.formatting.jq,
        null_ls.builtins.diagnostics.vale,
        null_ls.builtins.diagnostics.credo
    }
}

-- treesitter
ts_langs = { 'python', 'ruby', 'rust', 'elixir', 'lua' }
non_ts_langs = { 'bash', 'yaml', 'json' }

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

