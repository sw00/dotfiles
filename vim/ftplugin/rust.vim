" completion
setl completeopt=menu,menuone,preview,noselect,
call SuperTabSetDefaultCompletionType('<c-x><c-o>')

func! UseALE() " use ale for completions
  let s:ale_list_problems = ale#engine#GetLocList
  setl omnifunc=ale#completion#OmniFunc
  call deoplete#custom#option('sources', {
        \ 'rust': ['buffer', 'ale']
        \})
  nnoremap <buffer> <silent> <c-]> :ALEGoToDefinition<CR>
  nnoremap <buffer> gd :ALEGoToDefinition -vsplit<CR>
  nnoremap <buffer> gD :ALEGoToTypeDefinition -tab<CR>
  nnoremap <buffer> gr  :ALEFindReferences -vsplit<CR>
  nnoremap <buffer> <silent> <F2> :ALERename<CR>
  nnoremap <buffer> <silent> K :ALEHover<CR>
  " nmap <leader>al :let b:t=ale#engine#GetLoclist(bufnr('%')) | call setqflist(b:t)<CR>
endf

func! UseLSP() " use LSP for completions
  call LSPEnable()
  let g:ale_disable_lsp = 1
  let g:ale_linters.rust = ['cargo']
  let g:diagnostic_enable_virtual_text = 0
  let g:diagnostic_enable_underline = 0
  let g:diagnostic_auto_popup_while_jump = 0
  let g:diagnostic_insert_delay = 1
  setl omnifunc=v:lua.vim.lsp.omnifunc
  call deoplete#custom#option('sources', {
        \ 'rust': ['buffer', 'omni']
        \})
" call deoplete#custom#source('omni', 'functions', {
"       \ 'rust': ['v:vim.lsp.omnifunc']
"       \})
" call deoplete#custom#source('omni', 'input_patterns', {
"       \ 'rust': ['[^. *\t]\.\w*', '[a-zA-Z_]\w*::', '[^.[:digit:] *\t]\%(\.\|\::\)\%(\h\w*\)\?']
"       \})
  call LSPSetMappings()
  nmap <buffer> <silent> an :NextDiagnosticCycle<CR>
  nmap <buffer> <silent> ap :PrevDiagnosticCycle<CR>
  nmap <buffer> <silent> al :OpenDiagnostic<CR>
endf

nnoremap <buffer> <leader>t :RustTest<CR>
nnoremap <buffer> <leader>T :RustTest!<CR>

call UseALE()
" call UseLSP()
