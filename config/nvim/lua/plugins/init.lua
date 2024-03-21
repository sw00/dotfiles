return {
    -- [[ Appearance ]]
     { 'kyazdani42/nvim-web-devicons', name = 'devicons' },
     'NLKNguyen/papercolor-theme',
     {
        "SmiteshP/nvim-navic",
        dependencies = "neovim/nvim-lspconfig"
    },
     'Yggdroot/indentLine',
     { 'nvim-lualine/lualine.nvim', dependencies = 'devicons' },
     { "folke/zen-mode.nvim",
        dependencies = 'folke/twilight.nvim',
        config = function()
            require("zen-mode").setup {
                plugins = {
                    twilight = { enabled = true },
                    tmux = { enabled = false },
                    alacritty = { enabled = false, font = "14" }
                }
            }
        end
    },
     'stevearc/dressing.nvim',

    -- [[ Editor ]]
     { 'echasnovski/mini.nvim', branch = 'stable' },
     { "akinsho/toggleterm.nvim", tag = 'v2.6.0' },

    -- [[ Navigation ]]
     { 'nvim-tree/nvim-tree.lua', tag = 'v1.1' },
     { 'nvim-telescope/telescope.nvim',
        tag = '0.1.4',
        dependencies = {
            'nvim-lua/plenary.nvim',
            { 'devicons', opt = true },
        }
    },
     'simrat39/symbols-outline.nvim',
     'folke/trouble.nvim',

    -- [[ Version Control ]]
     { 'tpope/vim-fugitive', 'tpope/vim-rhubarb', 'shumphrey/fugitive-gitlab.vim' },
     { 'junegunn/gv.vim' },

    -- [[ Completion ]]
     { 'williamboman/mason.nvim', run = ':MasonUpdate' },
     { 'j-hui/fidget.nvim', tag = 'v1.4.0' },

     { 'neovim/nvim-lspconfig',
        dependencies = { 'williamboman/mason.nvim', 'williamboman/mason-lspconfig' }
    },

     'simrat39/rust-tools.nvim',

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

    -- [[ Snippets ]]
     'dcampos/nvim-snippy',

     { 'jose-elias-alvarez/null-ls.nvim', dependencies = 'nvim-lua/plenary.nvim' },

    -- [[ Syntax ]]
     'LnL7/vim-nix'
}
