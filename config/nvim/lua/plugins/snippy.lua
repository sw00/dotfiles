return {
    {
        'dcampos/nvim-snippy',
        config = function()
            require('snippy').setup {
                mappings = {
                    s = { -- when text is highlighted
                        ['<Tab>'] = 'expand_or_advance',
                        ['<S-Tab>'] = 'previous',
                    },
                    nx = {
                        ['<leader>x'] = 'cut_text'
                    }
                }
            }

            vim.api.nvim_create_autocmd("CompleteDone", { command = "lua require'snippy'.complete_done()" })

            -- tab autocompletes if popup menu visible
            vim.keymap.set('i', '<tab>', function()
                if vim.fn.pumvisible() then
                    return '<c-n>'
                else
                    return '<Plug>(snippy-expand-or-advance)'
                end
            end, { expr = true })

            vim.keymap.set('i', '<s-tab>', function()
                if vim.fn.pumvisible() then
                    return '<c-p>'
                else
                    return '<Plug>(snippy-previous)'
                end
            end, { expr = true })
        end
    }
}
