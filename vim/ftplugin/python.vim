" set colorscheme
let b:colors_name='solarized'
" tab completion
set omnifunc=pythoncomplete#Complete
set completeopt=menuone,longest
let g:SuperTabDefaultCompletionType = "context"

" syntastic
let g:syntastic_python_checkers=['pylint', 'flake8']

" pyflakes-8
noremap <leader>8 :call Flake8()<CR>
let g:pyflakes_use_quickfix = 0
" autocmd BufWritePost *.py call Flake8()

" Pytest stuff
nmap <silent><Leader>tf <Esc>:Pytest file<CR>
nmap <silent><Leader>tc <Esc>:Pytest class<CR>
nmap <silent><Leader>tm <Esc>:Pytest method<CR>
" cycle through test errors
nmap <silent><Leader>tn <Esc>:Pytest next<CR>
nmap <silent><Leader>tp <Esc>:Pytest previous<CR>
nmap <silent><Leader>te <Esc>:Pytest error<CR>
