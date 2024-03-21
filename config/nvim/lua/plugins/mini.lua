return {
    {
        'echasnovski/mini.nvim',
        branch = 'stable',
        config = function()
            require 'mini.comment'.setup {}
            require 'mini.pairs'.setup {}
            require 'mini.trailspace'.setup {}
            require 'mini.surround'.setup {}
            require 'mini.bufremove'.setup {}
            require 'mini.bracketed'.setup {}

            require('mini.tabline').setup {
                tabpage_section = 'none'
            }
            vim.cmd(
                [[ au FileType * if index(['gitcommit','fugitive'], &ft) >= 0 | let b:minitabline_disable=v:true | endif ]])

        end
    },
}
