-- https://github.com/chriskempson/base16/blob/master/styling.md
local palette = {
    base00 = '#002451', -- default bg
    base01 = '#081c3c', -- lighter bg (line numbers, folds, status bars)
    base02 = '#29293a', -- selection bg
    base03 = '#3779b7', -- comments, highlights, invisibles
    base04 = '#f1f1fe', -- dark fg (status bars)
    base05 = '#aaffff', -- default fg (caret, delimiters, operators)
    base06 = '#ffffff', -- light fg
    base07 = '#1e304e', -- light bg
    base08 = '#f1ffff', -- variables, tags, link text, diff deleted
    base09 = '#f78d84', -- int, bool, consts, link url
    base0A = '#fdeea1', -- classes, markup bold
    base0B = '#d3f1a6', -- strings, inherited classes, diff inserted
    base0C = '#f89c9b', -- support, regex, escape chars, quotes
    base0D = '#bfdaf6', -- funcs, methods, attribute ids, headings
    base0E = '#e8bbff', -- keywords, selector, italic, diff changed
    base0F = '#00a5c5', -- deprecated, open/close embedded language tags
}

require('mini.base16').setup {
    palette = palette,
    use_cterm = true,
}

vim.api.nvim_set_hl(0, 'WinSeparator', { fg = palette.base03, bg = palette.base00 })

vim.g.colors_name = 'tomorrow_night_blue'
