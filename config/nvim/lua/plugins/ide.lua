return {
    {
        'nvim-tree/nvim-tree.lua',
        config = function()
            require('nvim-tree').setup {}
        end
    },
    'simrat39/symbols-outline.nvim',
    {
        'j-hui/fidget.nvim',
        opts = {

            integration = {
                ["nvim-tree"] = { enable = true }
            }
        }
    },
    {
        "akinsho/toggleterm.nvim",
        tag = 'v2.6.0',
        opts = {
            open_mapping = [[<c-\>]],
            direction = 'float',
            shell = vim.o.shell,
            float_opts = {
                border = 'rounded'
            }
        }
    },
}
