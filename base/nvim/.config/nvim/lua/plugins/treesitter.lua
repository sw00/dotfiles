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
        -- Compatibility shim: nvim-treesitter v1.0 turned the parsers module
        -- into a mostly-static data table, but some plugins still call the old
        -- helper functions that were removed. Patch them in if missing.
        local ok, parsers = pcall(require, 'nvim-treesitter.parsers')
        if ok then
            if not parsers.ft_to_lang then
                parsers.ft_to_lang = function(ft)
                    return vim.treesitter.language.get_lang(ft) or ft
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
                -- NOTE: c, lua, markdown, vim, vimdoc are NOT listed here.
                -- Neovim 0.12 bundles built-in parsers for them (lib/nvim/parser)
                -- whose grammars match the bundled runtime highlight queries.
                -- Installing nvim-treesitter's vendored copies shadows the
                -- built-ins with older grammars that mismatch those queries
                -- (e.g. lua's `operator:` field), so vim.treesitter.start throws
                -- and highlighting silently never attaches.
                -- homelab / scripting
                'bash', 'html', 'python', 'json', 'json5', 'yaml', 'toml',
                'dockerfile', 'hcl', -- Terraform / OpenTofu
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
