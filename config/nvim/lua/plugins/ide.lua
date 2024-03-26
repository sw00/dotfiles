return {
    {
        'folke/which-key.nvim',
        event = 'VimEnter',
        config = function()
            require('which-key').setup()

            -- Document existing key chains
            require('which-key').register {
                ['<leader>c'] = { name = '[C]ode', _ = 'which_key_ignore' },
                ['<leader>d'] = { name = '[D]ocument', _ = 'which_key_ignore' },
                ['<leader>f'] = { name = '[F]ind (Telescope)', _ = 'which_key_ignore' },
                ['<leader>h'] = { name = 'Git [H]unk', _ = 'which_key_ignore' },
                ['<leader>l'] = { name = '[L]SP', _ = 'which_key_ignore' },
                ['<leader>r'] = { name = '[R]ename', _ = 'which_key_ignore' },
                ['<leader>v'] = { name = '[V]irtualEnv Selector ', _ = 'which_key_ignore' },
                ['<leader>w'] = { name = '[W]orkspace', _ = 'which_key_ignore' },
                ['<leader>x'] = { name = '[X] Trouble', _ = 'which_key_ignore' },
            }
        end,
    },
    {
        'tpope/vim-fugitive',
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
