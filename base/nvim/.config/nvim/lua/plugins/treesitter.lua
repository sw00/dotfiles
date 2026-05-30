return {
    'nvim-treesitter/nvim-treesitter',
    lazy = false, -- v1.0 does not support lazy-loading
    build = ':TSUpdate',
    config = function()
        -- v1.0 API: setup() only accepts install_dir
        require('nvim-treesitter').setup()

        -- Install parsers (no-op if already installed)
        require('nvim-treesitter').install({
            'bash', 'c', 'html', 'lua', 'markdown', 'vim', 'vimdoc',
            -- homelab / scripting
            'python', 'json', 'json5', 'yaml', 'toml', 'dockerfile',
            'hcl', -- Terraform / OpenTofu
        })

        -- Highlighting is now a Neovim built-in; enable it per filetype
        vim.api.nvim_create_autocmd('FileType', {
            pattern = {
                'bash', 'c', 'html', 'lua', 'markdown', 'vim',
                'python', 'json', 'yaml', 'toml', 'dockerfile', 'hcl',
            },
            callback = function() vim.treesitter.start() end,
        })

        -- Indentation (experimental)
        vim.api.nvim_create_autocmd('FileType', {
            pattern = {
                'bash', 'c', 'html', 'lua', 'markdown', 'vim',
                'python', 'json', 'yaml', 'toml', 'dockerfile', 'hcl',
            },
            callback = function()
                vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
            end,
        })
    end,
}
