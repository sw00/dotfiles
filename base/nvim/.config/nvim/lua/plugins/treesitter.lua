return {
    'nvim-treesitter/nvim-treesitter',
    lazy = false, -- v1.0 does not support lazy-loading
    build = ':TSUpdate',
    config = function()
        -- Install parsers (no-op if already installed)
        require('nvim-treesitter').install({
            'bash', 'c', 'html', 'lua', 'markdown', 'vim', 'vimdoc',
            -- homelab / scripting
            'python', 'json', 'json5', 'yaml', 'toml', 'dockerfile',
            'hcl', -- Terraform / OpenTofu
        })

        -- Enable treesitter highlighting via Neovim's built-in API
        -- (replaces the old highlight.enable option)
        vim.api.nvim_create_autocmd('FileType', {
            desc = 'Start treesitter highlighting',
            callback = function()
                pcall(vim.treesitter.start)
            end,
        })

        -- Enable treesitter-based indentation
        -- (replaces the old indent.enable option; still experimental)
        vim.api.nvim_create_autocmd('FileType', {
            desc = 'Enable treesitter indentation',
            pattern = {
                'bash', 'c', 'html', 'lua', 'python',
                'json', 'yaml', 'toml', 'dockerfile',
            },
            callback = function()
                vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            end,
        })
    end,
}
