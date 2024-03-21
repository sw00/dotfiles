return {
    -- [[ Testing ]]
     { 'vim-test/vim-test', config = function()
        vim.cmd([[ let test#strategy='toggleterm' ]])
    end },
     {
        "nvim-neotest/neotest",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "antoinemadec/FixCursorHold.nvim",
            "nvim-neotest/neotest-python",
            "nvim-neotest/neotest-vim-test"
        }
    },

    -- [[ Syntax ]]
     'LnL7/vim-nix'
}
