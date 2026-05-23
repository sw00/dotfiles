return {
    { 'williamboman/mason.nvim', name = 'mason', build = ':MasonUpdate' },
    {
        'neovim/nvim-lspconfig',
        dependencies = {
            'mason',
            'williamboman/mason-lspconfig',
            'WhoIsSethDaniel/mason-tool-installer.nvim',
            { 'j-hui/fidget.nvim', opts = { integration = { ['nvim-tree'] = { enable = true } } } },
            { 'folke/lazydev.nvim', ft = 'lua', opts = {} },
        },
        config = function()
            -- define lsp attach function
            vim.api.nvim_create_autocmd('LspAttach', {
                group = vim.api.nvim_create_augroup('lsp-attach', { clear = true }),
                callback = function(event)
                    local map = function(keys, func, desc)
                        vim.keymap.set('n', keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
                    end

                    map('gd',         function() require('telescope.builtin').lsp_definitions() end,              '[G]oto [D]efinition')
                    map('gr',         function() require('telescope.builtin').lsp_references() end,               '[G]oto [R]eferences')
                    map('gI',         function() require('telescope.builtin').lsp_implementations() end,           '[G]oto [I]mplementation')
                    map('<leader>D',  function() require('telescope.builtin').lsp_type_definitions() end,          'Type [D]efinition')
                    map('<leader>ds', function() require('telescope.builtin').lsp_document_symbols() end,          '[D]ocument [S]ymbols')
                    map('<leader>ws', function() require('telescope.builtin').lsp_dynamic_workspace_symbols() end, '[W]orkspace [S]ymbols')
                    map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
                    map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')
                    map('K', vim.lsp.buf.hover, 'Hover Documentation')
                    map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

                    -- edit actions
                    map('<leader>lf', function()
                        vim.lsp.buf.format { async = true }
                    end, '[L]SP [F]ormat')

                    -- Highlight word under cursor; autocmds are grouped so they
                    -- can be cleanly removed when the LSP detaches or restarts.
                    local client = vim.lsp.get_client_by_id(event.data.client_id)
                    if client and client.server_capabilities.documentHighlightProvider then
                        local hi = vim.api.nvim_create_augroup('lsp-highlight', { clear = false })
                        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
                            buffer   = event.buf,
                            group    = hi,
                            callback = vim.lsp.buf.document_highlight,
                        })
                        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
                            buffer   = event.buf,
                            group    = hi,
                            callback = vim.lsp.buf.clear_references,
                        })
                        -- On detach (LSP restart etc.) clear highlights and drop the
                        -- autocmds so they don't accumulate across restarts.
                        vim.api.nvim_create_autocmd('LspDetach', {
                            buffer   = event.buf,
                            group    = hi,
                            callback = function()
                                vim.lsp.buf.clear_references()
                                vim.api.nvim_clear_autocmds { group = hi, buffer = event.buf }
                            end,
                        })
                    end
                end,
            })

            -- blink.cmp merges nvim default capabilities automatically
            local capabilities = require('blink.cmp').get_lsp_capabilities()

            local servers = {
                pyright = {},
                -- elixirls and rust_analyzer are commented out: neither runtime
                -- is in the global mise config, so Mason would install them on
                -- every machine unnecessarily.  Uncomment per-project via
                -- a local .nvim.lua or add the runtime to mise/config.toml.
                -- elixirls = {
                --     settings = {
                --         dialyzerEnabled = false,
                --         fetchDeps = false,
                --         enableTestLenses = true,
                --     },
                -- },
                -- rust_analyzer = {
                --     settings = {
                --         completion = {
                --             limit = 24,
                --             callable = { snippets = 'fill_arguments' },
                --         },
                --     },
                -- },
                lua_ls = {
                    settings = {
                        Lua = {
                            completion = {
                                callSnippet = 'Replace',
                            },
                            -- diagnostics = { disable = { 'missing-fields' } },
                        },
                    },
                },
            }

            require('mason').setup()
            local ensure_installed = vim.tbl_keys(servers or {})
            vim.list_extend(ensure_installed, {
                'stylua',          -- lua formatter
                'tree-sitter-cli', -- required by nvim-treesitter v1 to compile parsers
            })

            require('mason-tool-installer').setup { ensure_installed = ensure_installed }
            require('mason-lspconfig').setup {
                handlers = {
                    function(server_name)
                        local server = servers[server_name] or {}
                        -- This handles overriding only values explicitly passed
                        -- by the server configuration above. Useful when disabling
                        -- certain features of an LSP (for example, turning off formatting for tsserver)
                        server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
                        require('lspconfig')[server_name].setup(server)
                    end,
                },
            }
        end,
    },
}
