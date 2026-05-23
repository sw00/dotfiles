-- blink.cmp — fast (Rust fuzzy-match), VSCode-style autocomplete.
-- `version = '*'` downloads a prebuilt binary from GitHub releases; no Rust/Cargo needed.
-- Sources: LSP first, then path / snippets / buffer words as contextual fallback.
return {
    'saghen/blink.cmp',
    version = '*',
    dependencies = {
        -- Snippet library for 50+ languages (loads automatically)
        'rafamadriz/friendly-snippets',
    },
    opts = {
        keymap = {
            preset   = 'default', -- C-n/C-p navigation, C-space show, C-e hide, C-y accept
            ['<CR>']    = { 'accept', 'fallback' },
            ['<Tab>']   = { 'select_next',  'snippet_forward',  'fallback' },
            ['<S-Tab>'] = { 'select_prev',  'snippet_backward', 'fallback' },
            ['<C-l>']   = { 'snippet_forward',  'fallback' },
            ['<C-h>']   = { 'snippet_backward', 'fallback' },
            ['<C-b>']   = { 'scroll_documentation_up',   'fallback' },
            ['<C-f>']   = { 'scroll_documentation_down', 'fallback' },
        },

        appearance = {
            nerd_font_variant = 'mono',
        },

        sources = {
            -- LSP completions surface first; the rest fill in when no server is active
            -- or the word doesn't match an LSP result.
            default = { 'lsp', 'path', 'snippets', 'buffer', 'lazydev' },
            providers = {
                -- lazydev gives first-class Neovim-API completions in lua files
                lazydev = {
                    name         = 'LazyDev',
                    module       = 'lazydev.integrations.blink',
                    score_offset = 100, -- always surface above other sources
                },
                buffer = {
                    -- draw words from all visible buffers, not just the current one
                    opts = { get_bufnrs = function() return vim.api.nvim_list_bufs() end },
                },
            },
        },

        completion = {
            ghost_text   = { enabled = true }, -- inline preview (VSCode-style)
            documentation = {
                auto_show          = true,
                auto_show_delay_ms = 200,
            },
        },

        signature = { enabled = true }, -- function-signature pop-up while typing args
    },
}
