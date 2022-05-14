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

-- lsp
local servers = {'rust_analyzer', 'pyright'}
for _, lsp in pairs(servers) do

    require('lspconfig')[lsp].setup {
        on_attach = on_attach -- use on_attach defined in keys.lua
    }
end
