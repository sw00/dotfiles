" because this is 2013
set nocompatible

" load pathogen modules
execute pathogen#infect()

" set colorscheme
colorscheme grb256

" remap leader key
let mapleader=","

" set line numbering
noremap <F2> :NumbersToggle<CR>
set number

" Switch between the last two files
nnoremap <leader><leader> <c-^>

" highlight line
set cursorline

" speed up vim
set ttyfast
set lazyredraw
set synmaxcol=120

" highlight search term
set hlsearch
" only case-sensitive when search term contains uppercase
set ignorecase smartcase

" set swapfile and backupdir
set backupdir=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp
set directory=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp

"shell config
set shell=/usr/local/bin/zsh\ -l

" read file automatically when changed outside of vim
set autoread

" convenience mapping
map :Q<CR> :q<CR>

"clipboard support for osx
if has("macunix")
    set clipboard=unnamed
    vmap <C-c> y:call system("pbcopy", getreg("\""))<CR>
    imap <C-v> :call setreg("\"",system("pbpaste"))<CR>p
endif

" enable powerline fonts
let g:airline_powerline_fonts=1
" enable airline bufflist
let g:airline#extensions#tabline#enabled = 1

"supertab
let g:SuperTabDefaultCompletionType = "context"

" easier mapping for navigating viewports
map <c-j> <c-w>j 
map <c-k> <c-w>k
map <c-l> <c-w>l
map <c-h> <c-w>h

" allow switching buffers without saving
set hidden

" cycle buffers like this
nnoremap <Tab> :bn<CR>
nnoremap <S-Tab> :bp<CR>

" kill buffers
nmap <C-b>q :BD<CR>
nmap <C-b>c :bd<CR>

"rails vim
nmap <silent> <leader>t :TestNearest<CR>
nmap <silent> <leader>T :TestFile<CR>
nmap <silent> <leader>a :TestSuite<CR>
nmap <silent> <leader>l :TestLast<CR>
nmap <silent> <leader>g :TestVisit<CR>

"taglist
let Tlist_Use_Right_Window = 1
let Tlist_Ctags_Cmd='/usr/local/bin/ctags'
map <F2> :TlistToggle<CR>

" The Silver Searcher
if executable('ag')
  " Use ag over grep
  set grepprg=ag\ --nogroup\ --nocolor

  " Use ag in CtrlP for listing files. Lightning fast and respects .gitignore
  let g:ctrlp_user_command = 'ag %s -l --nocolor -g ""'

  " ag is fast enough that CtrlP doesn't need to cache
  let g:ctrlp_use_caching = 0

  " use ag with ack.vim
  let g:ackprg = 'ag --nogroup --nocolor --column'
endif

" ctrl-p
let g:ctrlp_custom_ignore = ['\v[\/](bower_components|node_modules|target|dist)']
nnoremap <C-P><C-P> :CtrlPBuffer<CR>

" nerdtree
map <F3> :NERDTreeFind<CR>
map <leader>N :NERDTreeToggle<CR>
let NERDTreeIgnore=['\.pyc', '\~$', '\.swo$', '\.swp$', '\.git', '\.hg', '\.svn', '\.bzr', 'node_modules$']

" syntastic
let g:syntastic_mode_map = { 'mode': 'passive',
                           \ 'active_filetypes': ['python', 'javascript', 'coffeescript'],
                           \ 'passive_filetypes': ['puppet'] }
nmap <leader>a <Esc>:Ack!

" set the gui options and stuff
if has("gui_running")
    set guioptions=egma
    set guifont=Source\ Code\ Pro\ Light\ for\ Powerline
    colorscheme atom-dark
endif

" set .pp to ruby filetye for syntax highlighting
au BufNewFile,BufRead *.pp set filetype=ruby

