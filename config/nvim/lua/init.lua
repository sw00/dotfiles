-- REMAP LEADER KEY
vim.g.mapleader = ","
vim.g.localleader = "\\"

local packer_path = vim.fn.stdpath('config') .. '/packer.nvim/lua'
vim.o.packpath = vim.o.packpath .. ',' .. packer_path

local vimcmd = function(cmd)
    return '<cmd>' .. cmd .. '<CR>'
end

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
require('mason').setup()
require('mason-lspconfig').setup({
    ensure_installed = { 'lua_ls', 'pyright', 'rust_analyzer', 'elixirls', 'ruby_ls' }
})

local lsp_capabilities = require('cmp_nvim_lsp').default_capabilities()
local lsp_attach = function(client, bufnr)
    -- vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.vim.lsp.omnifunc')
    -- Use MiniCompletion on LSP client attach (overrides omnifunc)
    vim.api.nvim_buf_set_option(bufnr, 'omnifunc', 'v:lua.MiniCompletion.completefunc_lsp')

    -- define local fn nmapbuf for code dedup/readability
    local nmapbuf = function(shortcut, cmd)
        local opts = { noremap = true, silent = false }
        vim.api.nvim_buf_set_keymap(bufnr, 'n', shortcut, vimcmd(cmd), opts)
    end

    -- Mappings - see `:h vim.lsp.*`
    nmapbuf('gD', 'lua vim.lsp.buf.declaration()') -- goto declaration
    nmapbuf('gd', 'lua vim.lsp.buf.definition()') -- goto definition
    nmapbuf('K', 'lua vim.lsp.buf.hover()') -- show docs
    nmapbuf('gi', 'lua vim.lsp.buf.implementation()') -- goto implementation
    nmapbuf('<C-k>', 'lua vim.lsp.buf.signature_help()') -- show signature
    nmapbuf('<space>wa>', 'lua vim.lsp.buf.add_workspace_folder()') -- add workspace folder
    nmapbuf('<space>wr>', 'lua vim.lsp.buf.remove_workspace_folder()') -- remove workspace folder
    nmapbuf('<space>wl>', 'lua vim.inspect(vim.lsp.buf.list_workspace_folders())') -- remove workspace folder
    nmapbuf('<space>D', 'lua vim.lsp.buf.type_definition()') -- show type definition
    nmapbuf('<space>rn', 'lua vim.lsp.buf.rename()') -- rename
    nmapbuf('<space>ca', 'lua vim.lsp.buf.code_action()') -- code action
    nmapbuf('gr', 'lua vim.lsp.buf.references()') -- list references (show usages)
end

local lspconfig = require('lspconfig')
require('mason-lspconfig').setup_handlers({
    function(server_name)
        lspconfig[server_name].setup({
            on_attach = lsp_attach,
            capabilities = lsp_capabilities,
        })
    end
})


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

