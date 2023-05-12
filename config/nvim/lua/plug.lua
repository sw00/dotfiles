--[[ plug.lua]]
local fn = vim.fn

-- [[ Bootstrap packer.nvim ]]
local install_path = fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'
if fn.empty(fn.glob(install_path)) > 0 then
    PACKER_BOOTSTRAP = fn.system({ 'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim',
        install_path })
end

return require('packer').startup(function(use)
    use 'wbthomason/packer.nvim'

    -- [[ Appearance ]]
    use { 'kyazdani42/nvim-web-devicons', as = 'devicons' }
    use 'NLKNguyen/papercolor-theme'
    use "SmiteshP/nvim-gps"
    use 'Yggdroot/indentLine'
    use { 'nvim-lualine/lualine.nvim', requires = 'devicons' }
    use { "folke/zen-mode.nvim",
        requires = 'folke/twilight.nvim',
        config = function()
            require("zen-mode").setup {
                plugins = {
                    twilight = { enabled = true },
                    tmux = { enabled = false },
                    alacritty = { enabled = false, font = "14" }
                }
            }
        end
    }

    -- [[ Editor ]]
    use { 'echasnovski/mini.nvim', branch = 'stable' }
    use 'nathom/filetype.nvim'

    -- [[ Navigation ]]
    use { 'kyazdani42/nvim-tree.lua', tag = 'nightly' }
    use { 'nvim-telescope/telescope.nvim',
        requires = {
            'nvim-lua/plenary.nvim',
            { 'devicons', opt = true },
        }
    }
    use 'simrat39/symbols-outline.nvim'
    use 'folke/trouble.nvim'

    -- [[ Version Control ]]
    use { 'tpope/vim-fugitive', 'tpope/vim-rhubarb', 'shumphrey/fugitive-gitlab.vim' }
    use { 'junegunn/gv.vim' }

    -- [[ Completion ]]
    use { 'williamboman/mason.nvim', run = ':MasonUpdate' }

    use { 'neovim/nvim-lspconfig',
        requires = { 'williamboman/mason.nvim', 'williamboman/mason-lspconfig' }
    }

    use 'simrat39/rust-tools.nvim'

    -- [[ Snippets ]]
    use 'dcampos/nvim-snippy'

    use { 'jose-elias-alvarez/null-ls.nvim', requires = 'nvim-lua/plenary.nvim' }

    -- [[ Syntax ]]
    use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }
    use 'LnL7/vim-nix'

    -- bootstrap packer
    if PACKER_BOOTSTRAP then
        require('packer').sync()
    end
end)
