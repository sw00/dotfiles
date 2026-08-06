return {
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false, -- v1.0 does not support lazy-loading
    build = ':TSUpdate',
    config = function()
        -- v1.0 API: the top-level module exposes only setup()/indentexpr();
        -- install/update/uninstall moved to the nvim-treesitter.install
        -- submodule. Declare parsers via `ensure_install` (singular — NOT
        -- the old `ensure_installed`); config.setup runs the install
        -- asynchronously, so no vim.defer_fn / manual .install() needed.
        -- Compatibility shim: nvim-treesitter v1.0 removed/restructured
        -- modules that telescope.nvim previewers still depend on.
        --
        -- 1. nvim-treesitter.configs → renamed to nvim-treesitter.config
        --    (no is_enabled / get_module). Provide a stub.
        local configs_stub = {
            is_enabled = function()
                return true
            end,
            get_module = function(_)
                return { additional_vim_regex_highlighting = false }
            end,
        }
        package.loaded['nvim-treesitter.configs'] = configs_stub

        -- 2. nvim-treesitter.parsers → now a static parser-data table.
        --    Add the missing functions telescope expects.
        local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
        if ok then
            if not parsers.ft_to_lang then
                parsers.ft_to_lang = function(ft)
                    return ft
                end
            end
            if not parsers.get_parser then
                parsers.get_parser = function(bufnr, lang)
                    return vim.treesitter.get_parser(bufnr, lang)
                end
            end
        end

        require('nvim-treesitter').setup {
            ensure_install = {
                'bash', 'c', 'html', 'lua', 'markdown', 'vim', 'vimdoc',
                -- homelab / scripting
                'python', 'json', 'json5', 'yaml', 'toml', 'dockerfile',
                'hcl', -- Terraform / OpenTofu
            },
        }

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
