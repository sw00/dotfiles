" completion
setl completeopt=menu,menuone,preview,noselect,
setl omnifunc=v:lua.vim.lsp.omnifunc
call SuperTabSetDefaultCompletionType('<c-x><c-o>')

call deoplete#custom#option('sources', {
      \ 'rust': ['buffer', 'ale', 'omni']
      \})

" call deoplete#custom#source('omni', 'functions', {
"       \ 'rust': ['v:vim.lsp.omnifunc']
"       \})

" call deoplete#custom#source('omni', 'input_patterns', {
"       \ 'rust': ['[^. *\t]\.\w*', '[a-zA-Z_]\w*::', '[^.[:digit:] *\t]\%(\.\|\::\)\%(\h\w*\)\?']
"       \})

nmap <buffer> <leader>t  :RustTest<CR>
nmap <buffer> <leader>T  :RustTest!<CR>
nmap <buffer> <leader>r  :ALEFindReferences -vsplit<CR>
