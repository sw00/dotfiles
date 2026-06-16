return {
    {
        'folke/which-key.nvim',
        event = 'VimEnter',
        config = function()
            require('which-key').setup()

            -- Document existing key chains
            require('which-key').add {
                { '<leader>b', group = '[B]uffer' },
                { '<leader>c', group = '[C]ode' },
                { '<leader>d', group = '[D]ocument' },
                { '<leader>f', group = '[F]ind (Telescope)' },
                { '<leader>g', group = '[G]it (fugitive)' },
                { '<leader>h', group = 'Git [H]unk (gitsigns)' },
                { '<leader>l', group = '[L]SP' },
                -- <leader>q intentionally omitted: already mapped for diagnostic setloclist
                { '<leader>r', group = '[R]ename' },
                { '<leader>s', group = '[S]ave' },
                { '<leader>t', group = '[T]est / [T]oggle' },
                { '<leader>v', group = '[V]irtualEnv' },
                { '<leader>w', group = '[W]orkspace' },
                { '<leader>x', group = '[X] Trouble' },
            }
        end,
    },
    {
        'tpope/vim-fugitive',
        dependencies = { 'tpope/vim-rhubarb', 'shumphrey/fugitive-gitlab.vim' },
        keys = {
            { '<c-g>', '<cmd>Git<CR>', desc = 'Fugitive summary' },
            { '<leader>gs', '<cmd>Git<CR>', desc = '[G]it [S]tatus' },
            { '<leader>gc', '<cmd>Git commit<CR>', desc = '[G]it [C]ommit' },
            { '<leader>gp', '<cmd>Git push<CR>', desc = '[G]it [P]ush' },
            { '<leader>gP', '<cmd>Git pull<CR>', desc = '[G]it [P]ull' },
            { '<leader>gl', '<cmd>Git log<CR>', desc = '[G]it [L]og' },
            { '<leader>gd', '<cmd>Gvdiffsplit<CR>', desc = '[G]it [D]iff (vertical)' },
            { '<leader>gb', '<cmd>Git blame<CR>', desc = '[G]it [B]lame' },
        },
    },
    {
        'christoomey/vim-tmux-navigator',
        event = 'VimEnter',
        cmd = {
            'TmuxNavigateLeft', 'TmuxNavigateDown', 'TmuxNavigateUp',
            'TmuxNavigateRight', 'TmuxNavigatePrevious',
        },
        keys = {
            { '<c-h>', '<cmd>TmuxNavigateLeft<cr>' },
            { '<c-j>', '<cmd>TmuxNavigateDown<cr>' },
            { '<c-k>', '<cmd>TmuxNavigateUp<cr>' },
            { '<c-l>', '<cmd>TmuxNavigateRight<cr>' },
            -- <C-\> omitted intentionally: toggleterm owns that binding.
            -- To navigate to the previous pane, use tmux's native C-a C-a
            -- (prefix + prefix → last-window).
        },
    },
    {
        'folke/persistence.nvim',
        event = 'BufReadPre',
        opts = {
            options = { 'buffers', 'curdir', 'tabpages', 'winsize', 'winpos' },
        },
        keys = {
            { '<leader>qs', function() require('persistence').load() end,        desc = '[Q]uick [S]ession: restore' },
            { '<leader>qS', function() require('persistence').select() end,      desc = '[Q]uick [S]ession: select' },
            { '<leader>ql', function() require('persistence').load { last = true } end, desc = '[Q]uick [L]ast: restore last session' },
            { '<leader>qd', function() require('persistence').stop() end,        desc = '[Q]uick [D]iscard: stop saving session' },
        },
    },
    {
        'nvim-tree/nvim-tree.lua',
        keys = {
            { '<c-n>', '<cmd>NvimTreeToggle<cr>',         desc = 'NvimTree' },
            { '<F3>',  '<cmd>NvimTreeFindFileToggle<cr>', desc = 'NvimTree FindFile' },
        },
        opts = {
            view = { width = 35 },
            renderer = {
                group_empty = true, -- collapse single-child dirs
                icons = {
                    git_placement         = 'signcolumn',
                    diagnostics_placement = 'signcolumn',
                },
            },
            git = {
                enable = true,
                ignore = false, -- show git-ignored files (dimmed)
            },
            diagnostics = {
                enable       = true,
                show_on_dirs = true,
                icons = {
                    hint    = '󰌵',
                    info    = '',
                    warning = '',
                    error   = '',
                },
            },
            filters = { dotfiles = false }, -- show dotfiles
        },
    },
    {
        'hedyhli/outline.nvim',
        lazy = true,
        cmd = { 'Outline', 'OutlineOpen' },
        keys = {
            { '<F8>', '<cmd>Outline<cr>', desc = 'Toggle outline' },
        },
        opts = {},
    },

    {
        'akinsho/toggleterm.nvim',
        cmd  = { 'ToggleTerm', 'ToggleTermToggleAll', 'TermExec' },
        keys = { { [[<c-\>]], desc = 'Toggle terminal', mode = { 'n', 't' } } },
        opts = {
            open_mapping = [[<c-\>]],
            direction = 'float',
            shell = vim.o.shell,
            float_opts = {
                border = 'rounded',
            },
        },
    },
    {
        'folke/trouble.nvim',
        cmd          = { 'Trouble' },
        dependencies = { 'devicons' },
        config = function()
            require('trouble').setup {}

            -- trouble v3 API: mode strings changed in v3
            vim.keymap.set('n', '<leader>xx', function()
                require('trouble').toggle()
            end, { desc = 'Trouble: toggle last' })
            vim.keymap.set('n', '<leader>xw', function()
                require('trouble').toggle 'diagnostics'
            end, { desc = 'Trouble: workspace diagnostics' })
            vim.keymap.set('n', '<leader>xd', function()
                require('trouble').toggle { mode = 'diagnostics', filter = { buf = 0 } }
            end, { desc = 'Trouble: document diagnostics' })
            vim.keymap.set('n', '<leader>xq', function()
                require('trouble').toggle 'quickfix'
            end, { desc = 'Trouble: quickfix' })
            vim.keymap.set('n', '<leader>xl', function()
                require('trouble').toggle 'loclist'
            end, { desc = 'Trouble: loclist' })
            vim.keymap.set('n', 'gR', function()
                require('trouble').toggle 'lsp_references'
            end, { desc = 'Trouble: LSP references' })
        end,
    },
    {
        'vim-test/vim-test',
        keys = {
            { '<leader>tt', '<cmd>TestNearest<cr>', desc = 'vim-test: [T]est [T]his' },
            { '<leader>tf', '<cmd>TestFile<cr>', desc = '[T]est [F]ile' },
            { '<leader>ta', '<cmd>TestSuite<cr>', desc = '[T]est [S]uite' },
            { '<leader>tl', '<cmd>TestLast<cr>', desc = '[T]est [L]ast' },
            { '<leader>tg', '<cmd>TestVisit<cr>', desc = '[T]est [G]o to last run test' },
        },
        config = function()
            vim.cmd [[ let test#strategy='toggleterm' ]]
        end,
    },
    -- neotest: add here with adapters when vim-test is retired, e.g.:
    -- { 'nvim-neotest/neotest', dependencies = { 'nvim-neotest/neotest-python' },
    --   opts = { adapters = { require('neotest-python') } } }
}
