" completion
setl completeopt=menu,menuone,preview,noselect,
call SuperTabSetDefaultCompletionType('<c-x><c-o>')

func! UseALE() " use ale for completions
  let s:ale_list_problems='ale#engine#GetLocList'
  set omnifunc=ale#completion#OmniFunc
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

nnoremap <buffer> <leader>t :RustTest<CR>
nnoremap <buffer> <leader>T :RustTest!<CR>

call UseALE()
" call UseLSP()
