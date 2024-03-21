local ts_langs = { 'python', 'ruby', 'rust', 'elixir', 'lua' }
local non_ts_langs = { 'bash', 'yaml', 'json', 'vimdoc' }

return {
    'nvim-treesitter/nvim-treesitter',
    build = 'TSUpdate',
    opts = {
        ensure_installed = ts_langs,
        sync_install = true, -- install parsers synchronously for ensure_installed langs
        indent = { enable = true },

        -- List of parsers to ignore installing (for "all")
        ignore_install = { "javascript" },

        highlight = {
            enable = true,
            disable = non_ts_langs,
            additional_vim_regex_highlighting = non_ts_langs,
        },

        incremental_selection = {
            enable = true,
            keymaps = {
                init_selection = '<leader>s',
                node_incremental = '<leader>s',
                scope_incremental = '<c-space>',
                scope_decremental = '<c-backspace'
            }
        },
    }
}
