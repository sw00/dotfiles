return {
    -- Tabstop, shiftwidth detection
    'tpope/vim-sleuth',
    -- Note: commenting is handled natively by Neovim 0.10+ (gc / gcc)
    { -- Autoformat
        'stevearc/conform.nvim',
        event = { 'BufReadPre', 'BufNewFile' },
        opts = {
            notify_on_error = false,
            format_on_save = function(bufnr)
                -- Disable LSP formatting for langs without well-defined style
                local disable_filetypes = { c = true, cpp = true }
                return {
                    timeout_ms = 500,
                    lsp_format = disable_filetypes[vim.bo[bufnr].filetype] and 'never' or 'fallback',
                }
            end,
            formatters_by_ft = {
                lua = { 'stylua' },
                python = { 'isort', 'black' },
                --
                -- You can use a sub-list to tell conform to run *until* a formatter
                -- is found.
                -- javascript = { { "prettierd", "prettier" } },
            },
        },
    },
    -- Git Signs & diff management
    {
        'lewis6991/gitsigns.nvim',
        event = 'BufReadPre',
        config = function()
            require('gitsigns').setup {
                signs = {
                    add          = { text = '▎' },
                    change       = { text = '▎' },
                    delete       = { text = '' },
                    topdelete    = { text = '' },
                    changedelete = { text = '▌' },
                    untracked    = { text = '▎' },
                },
                word_diff  = false, -- toggle per-buffer with <leader>tw
                current_line_blame_opts = {
                    virt_text     = true,
                    virt_text_pos = 'eol',
                    delay         = 600,
                },
                current_line_blame_formatter = '<author>, <author_time:%Y-%m-%d> · <summary>',
                on_attach = function(bufnr)
                    local gs = package.loaded.gitsigns

                    local function map(mode, l, r, opts)
                        opts = opts or {}
                        opts.buffer = bufnr
                        vim.keymap.set(mode, l, r, opts)
                    end

                    -- Navigation
                    map('n', ']h', function()
                        if vim.wo.diff then
                            return ']h'
                        end
                        vim.schedule(function()
                            gs.next_hunk()
                        end)
                        return '<Ignore>'
                    end, { expr = true })

                    map('n', '[h', function()
                        if vim.wo.diff then
                            return '[h'
                        end
                        vim.schedule(function()
                            gs.prev_hunk()
                        end)
                        return '<Ignore>'
                    end, { expr = true })

                    -- Actions
                    map('n', '<leader>hs', gs.stage_hunk, { desc = 'Stage hunk' })
                    map('n', '<leader>hr', gs.reset_hunk, { desc = 'Reset hunk' })
                    map('v', '<leader>hs', function()
                        gs.stage_hunk { vim.fn.line '.', vim.fn.line 'v' }
                    end, { desc = 'Stage hunk' })
                    map('v', '<leader>hr', function()
                        gs.reset_hunk { vim.fn.line '.', vim.fn.line 'v' }
                    end, { desc = 'Reset hunk' })
                    map('n', '<leader>hS', gs.stage_buffer, { desc = 'Stage buffer' })
                    map('n', '<leader>hu', gs.undo_stage_hunk, { desc = 'Undo stage hunk' })
                    map('n', '<leader>hR', gs.reset_buffer, { desc = 'Reset buffer' })
                    map('n', '<leader>hp', gs.preview_hunk, { desc = 'Preview hunk' })
                    map('n', '<leader>hb', function()
                        gs.blame_line { full = true }
                    end, { desc = 'Git blame line' })
                    map('n', '<leader>tb', gs.toggle_current_line_blame, { desc = 'Toggle current line blame' })
                    map('n', '<leader>hd', gs.diffthis, { desc = 'Diff this' })
                    map('n', '<leader>hD', function()
                        gs.diffthis '~'
                    end, { desc = 'Diff this' })
                    map('n', '<leader>td', gs.toggle_deleted,   { desc = 'Toggle deleted' })
                    map('n', '<leader>tw', gs.toggle_word_diff,  { desc = 'Toggle word diff' })

                    -- Text object
                    map({ 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>')
                end,
            }
        end,
    },
}
