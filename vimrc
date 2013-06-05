" because this is 2013
set nocompatible

execute pathogen#infect()

" set filetype and indentation
syntax on
filetype plugin indent on

" set all tabs to be 4 spaces
set softtabstop=4
set shiftwidth=4
set smarttab
set expandtab

" backspace over indents in insert mode
set bs=indent

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
" use above bindings to navigate windows
let g:miniBufExplMapWindowNavVim = 1 
" fixes losing syntax bug
let g:miniBufExplForceSyntaxEnable = 1

" powerline
set rtp+=~/dotfiles/vim/bundle/powerline/bindings/vim

"taglist
let Tlist_Use_Right_Window = 1
let Tlist_Ctags_Cmd='/usr/local/bin/ctags'
map <leader>t :TlistToggle<CR>

"map <leader>td <Plug>TaskList

"map <leader>u :GundoToggle<CR>

map <leader>n :NERDTreeToggle<CR>

map <leader>j :RopeGotoDefinition<CR>
map <leader>r :RopeRename<CR>

nmap <leader>a <Esc>:Ack!

set number 
noremap <F2> :set nonumber!<CR>

" set the themes and stuff
if has("gui_running")
    set guifont=Source\ Code\ Pro
    set background=light
    set guioptions-=r
    set guioptions-=L
    set guioptions-=T
    colorscheme solarized
    " ctrl-tab cycles current buffer
    let g:miniBufExplMapCTabSwitchBufs = 1 
    " fix path issue - gui vim doesn't load .zshrc
    let $PATH="/usr/local/bin:/usr/local/share/python:".$PATH
    lcd ~
else
    set t_Co=256
    colorscheme github 
endif

