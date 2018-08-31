" python code folding
set smarttab
set foldmethod=indent

" tabs & spaces
set textwidth=90  " lines longer than 79 columns will be broken
set shiftwidth=4  " operation >> indents 4 columns; << unindents 4 columns
set tabstop=4     " a hard TAB displays as 4 columns
set expandtab     " insert spaces when hitting TABs
set softtabstop=4 " insert/delete 4 spaces when hitting a TAB/BACKSPACE
set shiftround    " round indent to multiple of 'shiftwidth'
set autoindent    " align the new line indent with the previous line

"jedi global options
let g:jedi#completions_enabled = 0 "use completor for completions
let g:jedi#popup_on_dot = 0
let g:jedi#popup_select_first = 0
let g:jedi#completions_command = '' 
let g:jedi#max_doc_height = 15
let g:jedi#use_splits_not_buffers = 'winwidth'

" show call sigantures
set noshowmode
let g:jedi#show_call_signatures = 2
let g:jedi#show_call_signatures_delay = 0

" completion
let b:SuperTabContextDefaultCompletionType = '<C-x><C-u>'
let g:completor_python_binary = '/Users/sett/.pyenv/versions/3.6.5/bin/python'
let g:completor_auto_trigger = 0
inoremap <expr> <Tab> pumvisible() ? "<C-N>" : "<C-R>=completor#do('complete')<CR>"

" ALE
let b:ale_linters = ['flake8']
let b:ale_fixers = ['black', 'isort', 'remove_trailing_lines', 'trim_whitespace']

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
