return {
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false, -- v1.0 does not support lazy-loading
    build = ':TSUpdate',
    config = function()
        -- v1.0 API: setup() only accepts install_dir
        require('nvim-treesitter').setup()

        -- Install parsers asynchronously so compilation never blocks startup.
        -- install() is a no-op for already-installed parsers.
        vim.defer_fn(function()
            require('nvim-treesitter').install({
                'bash', 'c', 'html', 'lua', 'markdown', 'vim', 'vimdoc',
                -- homelab / scripting
                'python', 'json', 'json5', 'yaml', 'toml', 'dockerfile',
                'hcl', -- Terraform / OpenTofu
            })
        end, 0)

        -- Highlighting is now a Neovim built-in; enable it per filetype.
        -- Uses a wildcard pattern to cover any filetype with a parser installed,
        -- rather than maintaining a hardcoded duplicate list.
        vim.api.nvim_create_autocmd('FileType', {
            callback = function()
                pcall(vim.treesitter.start)
            end,
        })

        -- Indentation (experimental)
        vim.api.nvim_create_autocmd('FileType', {
            callback = function()
                pcall(function()
                    vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
                end)
            end,
        })
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter-context',
    event = 'BufReadPost',
    opts = {
        enable = true,
        max_lines = 5,
        separator = '─',
    },
  },
}
