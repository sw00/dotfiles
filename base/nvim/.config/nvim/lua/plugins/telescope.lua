return {
    {
        'nvim-telescope/telescope.nvim',
        event = 'VimEnter',
        dependencies = {
            'nvim-lua/plenary.nvim',
            { 'devicons', enabled = vim.g.have_nerd_font },
            {
                'nvim-telescope/telescope-fzf-native.nvim',
                build = 'make',
                cond = function()
                    return vim.fn.executable 'make' == 1
                end,
            },
        },
        config = function()
            require('telescope').setup {
                defaults = {
                    -- ripgrep: include hidden files, skip .git internals
                    vimgrep_arguments = {
                        'rg', '--color=never', '--no-heading', '--with-filename',
                        '--line-number', '--column', '--smart-case',
                        '--hidden', '--glob', '!**/.git/*',
                    },
                    path_display = { 'truncate' },
                    layout_config = { prompt_position = 'top' },
                    sorting_strategy = 'ascending',
                    -- Treesitter-based preview highlighting is now properly supported
                    -- on telescope's master branch with nvim-treesitter v1.0.
                },
                pickers = {
                    find_files = {
                        hidden = true,
                        file_ignore_patterns = { '%.git/', 'node_modules/', '%.cache/' },
                    },
                },
                extensions = {},
            }

            pcall(require('telescope').load_extensions, 'fzf')

            local builtin = require 'telescope.builtin'

            vim.keymap.set('n', '<leader>fh', builtin.help_tags, { desc = '[F]ind [H]elp' })
            vim.keymap.set('n', '<leader>fk', builtin.keymaps, { desc = '[F]ind [K]eymaps' })
            vim.keymap.set('n', '<leader>ff', builtin.find_files, { desc = '[F]ind [F]iles' })
            vim.keymap.set('n', '<leader>fF', function()
                builtin.find_files { no_ignore = false, hidden = true }
            end, { desc = '[F]ind all [F]iles (hidden,ignored)' })
            vim.keymap.set('n', '<leader>ft', builtin.builtin, { desc = '[F]ind [S]elect Telescope' })
            vim.keymap.set('n', '<leader>fw', builtin.grep_string, { desc = '[F]ind current [W]ord' })
            vim.keymap.set('n', '<leader>fg', builtin.live_grep, { desc = '[F]ind by [G]rep' })
            vim.keymap.set('n', '<leader>fd', builtin.diagnostics, { desc = '[F]ind [D]iagnostics' })
            vim.keymap.set('n', '<leader>fr', builtin.resume, { desc = '[F]ind [R]esume' })
            vim.keymap.set('n', '<leader>f.', builtin.oldfiles, { desc = '[F]ind Recent Files ("." for repeat)' })
            vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })

            vim.keymap.set('n', '<C-p>', builtin.commands, { desc = 'User commands' })

            vim.keymap.set('n', '<leader>/', function()
                -- You can pass additional configuration to Telescope to change the theme, layout, etc.
                builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
                    winblend = 10,
                    previewer = false,
                })
            end, { desc = '[/] Fuzzily search in current buffer' })

            vim.keymap.set('n', '<leader>f/', function()
                builtin.live_grep {
                    grep_open_files = true,
                    prompt_title = 'Live Grep in Open Files',
                }
            end, { desc = '[F]ind [/] in Open Files' })

            vim.keymap.set('n', '<leader>fn', function()
                builtin.find_files { cwd = vim.fn.stdpath 'config' }
            end, { desc = '[F]ind [N]eovim files' })
        end,
    },
}
