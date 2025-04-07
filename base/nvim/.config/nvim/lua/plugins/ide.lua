return {
    {
        'folke/which-key.nvim',
        event = 'VimEnter',
        config = function()
            require('which-key').setup()

            -- Document existing key chains
            require('which-key').register {
                { '<leader>c', group = '[C]ode' },
                { '<leader>c_', hidden = true },
                { '<leader>d', group = '[D]ocument' },
                { '<leader>d_', hidden = true },
                { '<leader>f', group = '[F]ind (Telescope)' },
                { '<leader>f_', hidden = true },
                { '<leader>h', group = 'Git [H]unk' },
                { '<leader>h_', hidden = true },
                { '<leader>l', group = '[L]SP' },
                { '<leader>l_', hidden = true },
                { '<leader>r', group = '[R]ename' },
                { '<leader>r_', hidden = true },
                { '<leader>v', group = '[V]irtualEnv Selector ' },
                { '<leader>v_', hidden = true },
                { '<leader>w', group = '[W]orkspace' },
                { '<leader>w_', hidden = true },
                { '<leader>x', group = '[X] Trouble' },
                { '<leader>x_', hidden = true },
            }
        end,
    },
    {
        'tpope/vim-fugitive',
        event = 'VimEnter',
        dependencies = { 'tpope/vim-rhubarb', 'shumphrey/fugitive-gitlab.vim' },
        keys = {
            { '<c-g>', '<cmd>Git<CR>', desc = 'Fugitive' },
        },
    },
    {
        'nvim-tree/nvim-tree.lua',
        opts = {},
        keys = {
            { '<c-n>', '<cmd>NvimTreeToggle<cr>', desc = 'NvimTree' },
            { '<F3>', '<cmd>NvimTreeFindFileToggle<cr>', desc = 'NvimTree FindFile' },
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
        'j-hui/fidget.nvim',
        opts = {
            integration = {
                ['nvim-tree'] = { enable = true },
            },
        },
    },
    {
        'akinsho/toggleterm.nvim',
        tag = 'v2.6.0',
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
        dependencies = { 'devicons' },
        config = function()
            require('trouble').setup {}

            vim.keymap.set('n', '<leader>xx', function()
                require('trouble').toggle()
            end)
            vim.keymap.set('n', '<leader>xw', function()
                require('trouble').toggle 'workspace_diagnostics'
            end)
            vim.keymap.set('n', '<leader>xd', function()
                require('trouble').toggle 'document_diagnostics'
            end)
            vim.keymap.set('n', '<leader>xq', function()
                require('trouble').toggle 'quickfix'
            end)
            vim.keymap.set('n', '<leader>xl', function()
                require('trouble').toggle 'loclist'
            end)
            vim.keymap.set('n', 'gR', function()
                require('trouble').toggle 'lsp_references'
            end)
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
    {
        'nvim-neotest/neotest',
        dependencies = {
            'nvim-lua/plenary.nvim',
            'antoinemadec/FixCursorHold.nvim',
            'nvim-neotest/neotest-python',
            'nvim-neotest/neotest-vim-test',
        },
    },
}
