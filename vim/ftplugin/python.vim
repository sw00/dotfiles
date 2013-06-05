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

py << EOF
import os.path
import sys
import vim

if 'VIRTUAL_ENV' in os.environ:
    project_base_dir = os.environ['VIRTUAL_ENV']
    sys.path.insert(0, project_base_dir)
    activate_this = os.path.join(project_base_dir, 'bin/activate_this.py')
    execfile(activate_this, dict(__file__=activate_this))
EOF
