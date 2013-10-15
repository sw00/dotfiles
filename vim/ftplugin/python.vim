" python code folding
set smarttab
set foldmethod=indent

" tabs
set tabstop=4
set shiftwidth=4
set smartindent

"jedi global options
let g:jedi#use_tabs_not_buffers = 0

" syntastic
let g:syntastic_python_checkers=['flake8']

" pyflakes-8
noremap <leader>8 :Errors<CR>

" Pytest stuff
nmap <silent><Leader>tf <Esc>:Pytest file<CR>
nmap <silent><Leader>tc <Esc>:Pytest class<CR>
nmap <silent><Leader>tm <Esc>:Pytest method<CR>
" cycle through test errors
nmap <silent><Leader>tn <Esc>:Pytest next<CR>
nmap <silent><Leader>tp <Esc>:Pytest previous<CR>
nmap <silent><Leader>te <Esc>:Pytest error<CR>

" set to ignore some intermediary files
set wildignore+=*.pyc
