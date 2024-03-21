return {
    { 'kyazdani42/nvim-web-devicons', name = 'devicons' },
    'NLKNguyen/papercolor-theme',
    {
        "SmiteshP/nvim-navic",
        name = 'nvim-navic',
        dependencies = "neovim/nvim-lspconfig"
    },
    'Yggdroot/indentLine',
    {
        'nvim-lualine/lualine.nvim',
        dependencies = 'devicons',
        opts = {
            options = { theme = 'nord' },
            sections = {
                lualine_c = {
                    'filename',
                    'navic'
                }
            }
        }
    },
    {
        "folke/zen-mode.nvim",
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
    {
        'stevearc/dressing.nvim',
        opts = {
            input = {
                enabled = true
            }

        }
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
    { 'folke/todo-comments.nvim',     event = 'VimEnter', dependencies = { 'nvim-lua/plenary.nvim' }, opts = { signs = false } },
}
