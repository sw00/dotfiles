return {
    {
        'echasnovski/mini.nvim',
        priority = 1000,
        branch = 'stable',
        config = function()
            require('mini.pairs').setup {}
            require('mini.trailspace').setup {}
            require('mini.surround').setup {}
            require('mini.bufremove').setup {}
            require('mini.bracketed').setup {}

            local statusline = require 'mini.statusline'
            statusline.setup { use_icons = true }
            ---@diagnostic disable-next-line: duplicate-set-field
            statusline.section_location = function()
                return '%2l:%-2v'
            end
            vim.api.nvim_create_autocmd('BufEnter', {
                pattern = 'NvimTree*',
                command = 'let ministatusline_disable=v:true',
            })

            require('mini.tabline').setup {
                tabpage_section = 'none',
            }
            vim.cmd [[ au FileType * if index(['gitcommit','fugitive'], &ft) >= 0 | let b:minitabline_disable=v:true | endif ]]
        end,
    },
}
