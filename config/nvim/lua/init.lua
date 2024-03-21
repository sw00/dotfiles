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

-- IMPORTS
require('vars') -- Variables
require('opts') -- Options
require('keys') -- Keymaps
require('func') -- Functions

-- add plugins
require('lazy').setup('plugins')


-- PLUGINS
-- completion
require('settings.null-ls')

-- tags
require 'symbols-outline'.setup()

-- diagnostics
vim.diagnostic.config { virtual_text = false, underline = true }

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
