return {
    { 'kyazdani42/nvim-web-devicons', name = 'devicons' },
    'NLKNguyen/papercolor-theme',
    {
        'folke/zen-mode.nvim',
        event = 'VeryLazy',
        dependencies = 'folke/twilight.nvim',
        keys = {
            { '<F12>', '<cmd>ZenMode<cr>', desc = 'Toggle Zen Mode' },
        },
        config = function()
            require('zen-mode').setup {
                plugins = {
                    twilight = { enabled = true },
                    tmux = { enabled = true },
                    alacritty = { enabled = true, font = '14' },
                },
            }
        end,
    },
    {
        'stevearc/dressing.nvim',
        opts = {
            input = {
                enabled = true,
            },
        },
    },
    {
        'lewis6991/gitsigns.nvim',
        opts = {
            signs = {
                add = { text = '+' },
                change = { text = '~' },
                delete = { text = '_' },
                topdelete = { text = '‾' },
                changedelete = { text = '~' },
            },
        },
    },
    -- highlight todo, notes in comments
    {
        'folke/todo-comments.nvim',
        event = 'VimEnter',
        dependencies = { 'nvim-lua/plenary.nvim' },
        opts = { signs = false },
    },
}
