" syntax/lint check
let g:ale_rust_cargo_check_tests = 1
let g:ale_linters.rust = ['cargo', 'analyzer']
let g:ale_fixers.rust = ['rustfmt']

" completion
setl completeopt=menu,menuone,preview,noselect,
call deoplete#custom#source('omni', 'functions', {
      \ 'rust': ['v:vim.lsp.omnifunc']
      \})
call deoplete#custom#source('omni', 'input_patterns', {
      \ 'rust': ['[^. *\t]\.\w*', '[a-zA-Z_]\w*::', '[^.[:digit:] *\t]\%(\.\|\::\)\%(\h\w*\)\?']
      \})

nmap <buffer> <leader>t  :RustTest<CR>
nmap <buffer> <leader>T  :RustTest!<CR>

