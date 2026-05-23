return {
    {
        'echasnovski/mini.nvim',
        priority = 1000,
        branch = 'stable',
        config = function()
            -- ── Editing ──────────────────────────────────────────────────────────

            require('mini.pairs').setup {}
            require('mini.surround').setup {}

            -- gS on any bracket-delimited expression to toggle split / join
            require('mini.splitjoin').setup {}

            -- Extended a/i text objects. Builtins added on top of Vim defaults:
            --   aa / ia  — function argument (also works across lines)
            --   ab / ib  — any balanced bracket ()  []  {}
            --   af / if  — function call
            --   aq / iq  — any quote  "  '  `
            --   at / it  — HTML / XML tag
            --   a? / i?  — prompted delimiter (type it at the prompt)
            require('mini.ai').setup { n_lines = 500 }

            -- Move lines (Normal) or selections (Visual) with <M-hjkl>
            require('mini.move').setup {}

            -- ── Buffers ──────────────────────────────────────────────────────────

            require('mini.bufremove').setup {}

            -- Bracket-pair navigation.  Gives ]b/[b, ]c/[c, ]d/[d, ]t/[t, etc.
            -- undo disabled — it would remap u / <C-r> which we don't want.
            require('mini.bracketed').setup {
                undo = { suffix = '' },
            }

            -- ── Visual ───────────────────────────────────────────────────────────

            require('mini.trailspace').setup {}
            -- Auto-strip trailing whitespace and trailing blank lines on every save.
            vim.api.nvim_create_autocmd('BufWritePre', {
                desc = 'Trim trailing whitespace and blank lines (mini.trailspace)',
                callback = function()
                    if vim.bo.modifiable and not vim.bo.readonly then
                        require('mini.trailspace').trim()
                        require('mini.trailspace').trim_last_lines()
                    end
                end,
            })

            -- Vertical line that tracks the indent scope of the current block.
            require('mini.indentscope').setup {
                symbol = '╎',
                draw   = {
                    delay     = 50,
                    animation = require('mini.indentscope').gen_animation.none(),
                },
            }
            -- Disable in UI / non-code buffers where it just adds noise.
            vim.api.nvim_create_autocmd('FileType', {
                desc    = 'Disable mini.indentscope in UI buffers',
                pattern = {
                    'NvimTree', 'help', 'toggleterm', 'trouble',
                    'lazy', 'mason', 'gitcommit', 'TelescopePrompt',
                },
                callback = function() vim.b.miniindentscope_disable = true end,
            })

            -- ── Status / Tab lines ───────────────────────────────────────────────

            local statusline = require 'mini.statusline'
            statusline.setup { use_icons = true }
            ---@diagnostic disable-next-line: duplicate-set-field
            statusline.section_location = function()
                return '%2l:%-2v'
            end
            vim.api.nvim_create_autocmd('FileType', {
                pattern  = 'NvimTree',
                callback = function() vim.b.ministatusline_disable = true end,
            })

            require('mini.tabline').setup { tabpage_section = 'none' }
            vim.api.nvim_create_autocmd('FileType', {
                pattern  = { 'gitcommit', 'fugitive' },
                callback = function() vim.b.minitabline_disable = true end,
            })

            -- ── Theme ────────────────────────────────────────────────────────────

            vim.cmd.colorscheme(vim.g.colorscheme)
        end,
    },
}
