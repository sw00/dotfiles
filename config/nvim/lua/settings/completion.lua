-- [[Completion]]
require('mini.completion').setup {
    fallback_action = '<C-x><C-o>',
    mappings = {
        force_twostep = '<C-Space>',
        force_fallback = '<A-Space>'
    },
}

-- keymap
-- tab key is mapped in `settings/snippy.lua`
local keys = {
    ['cr']        = vim.api.nvim_replace_termcodes('<CR>', true, true, true),
    ['ctrl-y']    = vim.api.nvim_replace_termcodes('<C-y>', true, true, true),
    ['ctrl-y_cr'] = vim.api.nvim_replace_termcodes('<C-y><CR>', true, true, true),
}

_G.cr_action = function()
    if vim.fn.pumvisible() ~= 0 then
        local item_selected = vim.fn.complete_info()['selected'] ~= -1
        return item_selected and keys['ctrl-y'] or keys['ctrl-y_cr']
    else
        return keys['cr']
    end
end

vim.api.nvim_set_keymap('i', '<CR>', 'v:lua._G.cr_action()', { noremap = true, expr = true })

local vimcmd = function(cmd)
    return '<cmd>' .. cmd .. '<CR>'
end

function on_attach_lsp(client, bufnr)
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

-- [[LSP]]
local mason_lspconfig = require'mason-lspconfig'
local lspconfig = require'lspconfig'

require('mason').setup {
    ui = {
        icons = {
            package_installed = "✓",
            package_pending = "➜",
            package_uninstalled = "✗"
        }
    }
}

mason_lspconfig.setup({
    ensure_installed = { 'lua_ls', 'pyright', 'rust_analyzer', 'elixirls', 'ruby_ls' }, -- definitely install these
    automatic_installation = true, -- install any additional servers with lspconfig setup defined
})

-- mason handlers
local default_handler = function(server_name)
    require('lspconfig')[server_name].setup {
        on_attach = on_attach_lsp
    }
end

local lua_handler = function()
    lspconfig.lua_ls.setup {
        on_attach = on_attach_lsp,
        settings = {
            Lua = {
                diagnostics = {
                    globals = { 'vim' }
                }
            }
        }
    }
end

local rust_handler = function()
    local rt = require("rust-tools")
    rt.setup {
        tools = {
            inlay_hints = { only_current_line = true },
            hover_actions = { auto_focus = true }
        },
        server = {
            standalone = false,
            on_attach = function(client, bufnr)
                on_attach_lsp(client, bufnr)
                -- Hover actions
                vim.keymap.set("n", "<Leader>a", rt.hover_actions.hover_actions, { buffer = bufnr })
                -- Code action groups
                vim.keymap.set("n", "<Leader>c", rt.code_action_group.code_action_group, { buffer = bufnr })
            end,
            settings = {
                ['rust-analyzer'] = {
                    completion = {
                        limit = 24, -- only return 2 dozen suggestions
                        callable = {
                            -- snippets = 'add_parentheses' -- don't autofill args
                            snippets = 'fill_arguments'
                        }
                    }
                }
            },
        }
    }
end

mason_lspconfig.setup_handlers({
    default_handler,
    ["lua_ls"] = lua_handler,
    ["rust_analyzer"] = rust_handler,
})

-- disable for these
local disabled_filetypes = {'gitcommit'}

vim.api.nvim_create_autocmd("FileType", {
    pattern = disabled_filetypes,
    callback = function()
        vim.b.minicompletion_disable = true
    end
})

