return {
    { 'nvim-tree/nvim-web-devicons', name = 'devicons' },
    { 'NLKNguyen/papercolor-theme', lazy = true },
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
        -- Nicer vim.ui.input (floating prompt) and vim.ui.select (pick list).
        -- Replaces telescope-ui-select; dressing handles both in one place.
        'stevearc/dressing.nvim',
        event = 'VeryLazy',
        opts = {
            input  = { enabled = true },
            select = { enabled = true, backend = { 'telescope', 'builtin' } },
        },
    },
    -- highlight todo, notes in comments
    {
        'folke/todo-comments.nvim',
        event = 'BufReadPost',
        dependencies = { 'nvim-lua/plenary.nvim' },
        opts = { signs = false },
    },
}
