-- null-ls
local null_ls = require('null-ls')

local formatting = null_ls.builtins.formatting
local diagnostics = null_ls.builtins.diagnostics

null_ls.setup {
    debug = false,
    sources = {
        formatting.nixfmt,
        formatting.terraform_fmt,
        formatting.rubocop,
        formatting.black.with({ extra_args = { "--fast"} }),
        formatting.isort,
        formatting.jq,
        diagnostics.shellcheck,
        diagnostics.credo
    }
}

