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

    -- [[ Theme ]] 
    use 'NLKNguyen/papercolor-theme'

    -- [[ IDE ]]
    use { 
        'kyazdani42/nvim-tree.lua', requires = 'kyazdani42/nvim-web-devicons', tag = 'nightly' 
    }

    use {
        'nvim-lualine/lualine.nvim', requires = {
            'kyazdani42/nvim-web-devicons', opt = true
        } 
    }

    use {
        'nvim-telescope/telescope.nvim',
        requires = { {'nvim-lua/plenary.nvim'} }
    }

    use { 'tpope/vim-fugitive' }
    use { 'junegunn/gv.vim' }
    use { 'majutsushi/tagbar' }
    use { 'Yggdroot/indentLine' } 

    -- [[ Language Support ]]

    -- bootstrap packer
    if packer_bootstrap then
        require('packer').sync()
    end

end)
