" because this is 2013
set nocompatible

" load pathogen modules
execute pathogen#infect()

" set colorscheme
colorscheme Tomorrow-Night

" set line numbering
set number 
noremap <F2> :NumbersToggle<CR>

"a autoindent and allow mouse everywhere
set mouse=a

"clipboard support for osx
if has("macunix")
    vmap <C-c> y:call system("pbcopy", getreg("\""))<CR>
    imap <C-v> :call setreg("\"",system("pbpaste"))<CR>p
endif

" enable powerline fonts
let g:airline_powerline_fonts=1

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


" set the gui options and stuff
if has("gui_running")
    set guioptions=egma
    set guifont=Source\ Code\ Pro\ for\ Powerline

    " ctrl-tab cycles current buffer
    let g:miniBufExplMapCTabSwitchBufs = 1 
    "yank to clipboard
    set clipboard+=unnamed
else
    set encoding=utf-8
    set t_Co=256
endif

