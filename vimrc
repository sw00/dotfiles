" because this is 2013
set nocompatible

" load pathogen modules
execute pathogen#infect()

" set colorscheme
colorscheme solarized
set background=light

" set filetype and indentation
syntax on
filetype plugin indent on

" set line numbering
set number 
noremap <F2> :set nonumber!<CR>

" set all tabs to be 4 spaces
set softtabstop=4
set shiftwidth=4
set smarttab
set expandtab

" backspace over indents in insert mode
set bs=indent

"a autoindent and allow mouse everywhere
set autoindent
set mouse=a

" powerline
set laststatus=2
set rtp+=~/.vim/bundle/powerline/powerline/bindings/vim

" for python code folds
set foldmethod=indent
set foldlevel=99

"supertab
let g:SuperTabDefaultCompletionType = "context"

" easier mapping for minibufferexplorer plugin
map <c-j> <c-w>j 
map <c-k> <c-w>k
map <c-l> <c-w>l
map <c-h> <c-w>h
" use above bindings to navigate windows
let g:miniBufExplMapWindowNavVim = 1 
" fixes losing syntax bug
let g:miniBufExplForceSyntaxEnable = 1

"taglist
let Tlist_Use_Right_Window = 1
let Tlist_Ctags_Cmd='/usr/local/bin/ctags'
map <leader>t :TlistToggle<CR>

"map <leader>td <Plug>TaskList

"map <leader>u :GundoToggle<CR>

map <leader>N :NERDTreeToggle<CR>
let NERDTreeIgnore=['\.pyc', '\~$', '\.swo$', '\.swp$', '\.git', '\.hg', '\.svn', '\.bzr']

let g:syntastic_mode_map = { 'mode': 'passive',
                           \ 'active_filetypes': ['python', 'javascript'],
                           \ 'passive_filetypes': ['puppet'] }
nmap <leader>a <Esc>:Ack!


" set the themes and stuff
if has("gui_running")
    set guifont=Source\ Code\ Pro\ for\ Powerline
    set background=light
    set guioptions-=r
    set guioptions-=L
    set guioptions-=T
    " ctrl-tab cycles current buffer
    let g:miniBufExplMapCTabSwitchBufs = 1 
    " fix path issue - gui vim doesn't load .zshrc
    let $PATH="/usr/local/bin:/usr/local/share/python:".$PATH
    "yank to clipboard
    set clipboard+=unnamed
else
    set t_Co=256
endif

