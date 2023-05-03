--[[ plug.lua]]
local fn = vim.fn

-- [[ Bootstrap packer.nvim ]]
local install_path = fn.stdpath('data') .. '/site/pack/packer/start/packer.nvim'
if fn.empty(fn.glob(install_path)) > 0 then
    PACKER_BOOTSTRAP = fn.system({ 'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim',
        install_path })
end

-- run :PackerCompile whenever we update plug.lua
-- vim.cmd([[
--   augroup packer_user_config
--     autocmd!
--     autocmd BufWritePost plugins.lua source <afile> | PackerCompile
--   augroup end
-- ]])

-- [[ packer.nvim ]]
return require('packer').startup(function(use)
    use 'wbthomason/packer.nvim'

    -- [[ Appearance ]]
    use 'kyazdani42/nvim-web-devicons'
    use 'NLKNguyen/papercolor-theme'
    use "SmiteshP/nvim-gps"
    use 'Yggdroot/indentLine'
    use {
        'nvim-lualine/lualine.nvim', requires = {
            'kyazdani42/nvim-web-devicons', opt = true
        }
    }
    use {
        "folke/zen-mode.nvim",
        requires = { 'folke/twilight.nvim' },
        config = function()
            require("zen-mode").setup {
                plugins = {
                    twilight = { enabled = true }
                }
            }
        end
    }

    -- [[ Navigation ]]
    use { 'kyazdani42/nvim-tree.lua', tag = 'nightly' }
    use {
        'nvim-telescope/telescope.nvim',
        requires = { 'nvim-lua/plenary.nvim' }
    }
    use 'majutsushi/tagbar'
    use 'folke/trouble.nvim'

    -- [[ Version Control ]]
    use { 'tpope/vim-fugitive' }
    use { 'junegunn/gv.vim' }
    use 'tpope/vim-rhubarb'
    use 'shumphrey/fugitive-gitlab.vim'

    -- [[ Completion ]]
    use { 'neovim/nvim-lspconfig', 'williamboman/mason.nvim', 'williamboman/mason-lspconfig', 'hrsh7th/cmp-nvim-lsp', 'hrsh7th/nvim-cmp' }
    use { 'jose-elias-alvarez/null-ls.nvim', requires = 'nvim-lua/plenary.nvim' }
    use 'simrat39/rust-tools.nvim'

    -- [[ Syntax ]]
    use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }
    use 'nathom/filetype.nvim'
    use 'LnL7/vim-nix'

    -- [[ Editor ]]
    use 'tpope/vim-surround'
    use { 'echasnovski/mini.nvim', branch = 'stable' } -- github.com/echasnovski/mini.nvim

    -- bootstrap packer
    if PACKER_BOOTSTRAP then
        require('packer').sync()
    end
end)
