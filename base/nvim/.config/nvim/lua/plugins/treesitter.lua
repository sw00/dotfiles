return {
    'nvim-treesitter/nvim-treesitter',
    lazy = false, -- v1.0 does not support lazy-loading
    build = ':TSUpdate',
    config = function()
        require('nvim-treesitter.configs').setup({
            ensure_installed = {
                'bash', 'c', 'html', 'lua', 'markdown', 'vim', 'vimdoc',
                -- homelab / scripting
                'python', 'json', 'json5', 'yaml', 'toml', 'dockerfile',
                'hcl', -- Terraform / OpenTofu
            },
            highlight = { enable = true },
            indent    = { enable = true },
        })
    end,
}
