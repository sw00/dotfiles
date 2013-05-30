set nocompatible

" filetype checking off so we can load pathogen
filetype on
filetype off

call pathogen#runtime_append_all_bundles()
call pathogen#helptags()

" set filetype and indentation
filetype on
syntax on
filetype plugin indent on

" set all tabs to be 4 spaces
set softtabstop=4
set shiftwidth=4
set expandtab

"a autindent and allow mouse everywhere
set autoindent
set mouse=a


" for python code folds
set foldmethod=indent
set foldlevel=99

" easier mapping for minibufferexplorer plugin
map <c-j> <c-w>j 
map <c-k> <c-w>k
map <c-l> <c-w>l
map <c-h> <c-w>h
let g:miniBufExplMapWindowNavVim = 1 
let g:miniBufExplMapCTabSwitchBufs = 1 

"map <leader>td <Plug>TaskList

"map <leader>u :GundoToggle<CR>

" pyflakes-8
let g:pyflakes_use_quickfix = 0
let g:pep8_map='<leader>8'
autocmd BufWritePost *.py call Flake8()

au FileType python set omnifunc=pythoncomplete#Complete
let g:SuperTabDefaultCompletionType = "context"

set completeopt=menuone,longest,preview

map <leader>n :NERDTreeToggle<CR>

map <leader>j :RopeGotoDefinition<CR>
map <leader>r :RopeRename<CR>

nmap <leader>a <Esc>:Ack!

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


set number 
	noremap <F2> :set nonumber!<CR>


"autocmd BufEnter * lcd %:p:h

" set the themes and stuff
if has("gui_running")
	set guifont=SourceCodePro
	set background=dark
    colorscheme solarized
else
	set t_Co=256
    colorscheme github 
endif

" backspace over everything in insert mode
set bs=indent

" CPAN JSON tidier
map <leader>jt  <Esc>:%!json_xs -f json -t json-pretty<CR>
" change filetype automatically
au BufRead,BufNewFile *.json set filetype=json
au BufRead,BufNewFile *.py set filetype=python


