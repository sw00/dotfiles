set smarttab foldmethod=indent
set textwidth=120 shiftwidth=2 tabstop=2 expandtab softtabstop=2 shiftround autoindent

" completion
setl completeopt=menu,menuone,preview,noselect,
set omnifunc=ale#completion#OmniFunc
call SuperTabSetDefaultCompletionType("<c-x><c-o>")

call deoplete#custom#option('sources', {
      \ 'ruby': ['buffer', 'ale', 'omni']
      \})

" call deoplete#custom#source('omni', 'functions', {
"       \ 'ruby': ['buffer', 'v:vim.lsp.omnifunc']
"       \})

" call deoplete#custom#source('omni', 'input_patterns', {
"       \ 'ruby': ['[^. *\t]\.\w*', '[a-zA-Z_]\w*::']
"       \})

