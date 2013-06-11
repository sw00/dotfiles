" set colorscheme
colorscheme solarized

" tab completion
set omnifunc=pythoncomplete#Complete
set completeopt=menuone,longest,preview
let g:SuperTabDefaultCompletionType = "context"

" syntastic
let g:syntastic_python_checkers=['pylint', 'flake8']

" pyflakes-8
noremap <leader>8 :call Flake8()<CR>
let g:pyflakes_use_quickfix = 0
" autocmd BufWritePost *.py call Flake8()
