--[[ plug.lua]]
local fn = vim.fn

-- [[ Bootstrap packer.nvim ]]
local install_path = fn.stdpath('data')..'/site/pack/packer/start/packer.nvim'
if fn.empty(fn.glob(install_path)) > 0 then
  packer_bootstrap = fn.system({'git', 'clone', '--depth', '1', 'https://github.com/wbthomason/packer.nvim', install_path})
end

-- run :PackerCompile whenever we update plug.lua
vim.cmd([[
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost plugins.lua source <afile> | PackerCompile
  augroup end
]])

-- [[ packer.nvim ]]
return require('packer').startup(function(use)
    use 'wbthomason/packer.nvim'

    -- [[ Appearance ]] 
    use 'NLKNguyen/papercolor-theme'
    use { 'Yggdroot/indentLine' } 
    use {
        'nvim-lualine/lualine.nvim', requires = {
            'kyazdani42/nvim-web-devicons', opt = true
        } 
    }

    -- [[ Navigation ]]
    use { 
        'kyazdani42/nvim-tree.lua', requires = 'kyazdani42/nvim-web-devicons', tag = 'nightly' 
    }
    use {
        'nvim-telescope/telescope.nvim',
        requires = { {'nvim-lua/plenary.nvim'} }
    }
    use { 'majutsushi/tagbar' }
    use {
        "SmiteshP/nvim-gps",
        requires = "nvim-treesitter/nvim-treesitter"
    }

    -- [[ Version Control ]]
    use { 'tpope/vim-fugitive' }
    use { 'junegunn/gv.vim' }
    use 'tpope/vim-rhubarb'
    use 'shumphrey/fugitive-gitlab.vim'

    -- [[ Completion ]]
    use {
        'neovim/nvim-lspconfig', requires = { 'williamboman/nvim-lsp-installer' }
    }

    -- [[ Syntax ]]
    use { 'nvim-treesitter/nvim-treesitter', run = ':TSUpdate' }


    -- [[ Editor ]]
    use 'tpope/vim-surround'
    use { 'echasnovski/mini.nvim', branch = 'stable' } -- github.com/echasnovski/mini.nvim

    -- bootstrap packer
    if packer_bootstrap then
        require('packer').sync()
    end
end)
