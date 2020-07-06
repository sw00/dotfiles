set smarttab foldmethod=indent
set textwidth=120 shiftwidth=2 tabstop=2 expandtab softtabstop=2 shiftround autoindent

" lint
let g:ale_linters.ruby = ['ruby', 'rubocop', 'standardrb']
let g:ale_fixers.ruby = ['standardrb']

" completion
setl completeopt=menu,menuone,preview,noselect,
call deoplete#custom#source('omni', 'functions', {
      \ 'ruby': ['v:vim.lsp.omnifunc']
      \})
call deoplete#custom#source('omni', 'input_patterns', {
      \ 'ruby': ['[a-zA-Z_]\w*[!?]?', '[a-zA-Z_]\w*::', '[^.[:digit:] *\t]\%(\.\|\::\)\%(\h\w*\)\?']
      \})
