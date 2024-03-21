return {
    -- [[ Navigation ]]
     { 'nvim-telescope/telescope.nvim',
        tag = '0.1.4',
        dependencies = {
            'nvim-lua/plenary.nvim',
            { 'devicons', opt = true },
        }
    },
     'folke/trouble.nvim',

    -- [[ Version Control ]]
     { 'tpope/vim-fugitive', 'tpope/vim-rhubarb', 'shumphrey/fugitive-gitlab.vim' },
     { 'junegunn/gv.vim' },

    -- [[ Completion ]]
     { 'williamboman/mason.nvim', run = ':MasonUpdate' },



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
