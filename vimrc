" because this is 2013
set nocompatible

" load pathogen modules
execute pathogen#infect()

" set colorscheme
colorscheme Tomorrow-Night-Eighties

" set line numbering
noremap <F2> :NumbersToggle<CR>
set number

" highlight line
set cursorline

" convenience mapping
map :Q<CR> :q<CR>

"clipboard support for osx
if has("macunix")
    set clipboard=unnamed
"    vmap <C-c> y:call system("pbcopy", getreg("\""))<CR>
"    imap <C-v> :call setreg("\"",system("pbpaste"))<CR>p
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

" maximise current window without closing others
map <F5> <C-W>_<C-W><Bar>

" cycle buffers like this
nnoremap <Tab> :bn<CR>
nnoremap <S-Tab> :bp<CR>

" kill buffers
nmap <C-b>q :BD<CR>
nmap <C-b>c :bd<CR>

"taglist
let Tlist_Use_Right_Window = 1
let Tlist_Ctags_Cmd='/usr/local/bin/ctags'
map <leader>t :TlistToggle<CR>

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

" nerdtree
map <leader>n :NERDTreeToggle<CR>
let NERDTreeIgnore=['\.pyc', '\~$', '\.swo$', '\.swp$', '\.git', '\.hg', '\.svn', '\.bzr', 'node_modules$']

" syntastic
let g:syntastic_mode_map = { 'mode': 'passive',
                           \ 'active_filetypes': ['python', 'javascript', 'coffeescript'],
                           \ 'passive_filetypes': ['puppet'] }
nmap <leader>a <Esc>:Ack!

" set the gui options and stuff
if has("gui_running")
    set guioptions=egma
    set guifont=Source\ Code\ Pro\ for\ Powerline
    colorscheme atom-dark
endif

" set .pp to ruby filetye for syntax highlighting
au BufNewFile,BufRead *.pp set filetype=ruby

" indentation rules for javascript
au BufNewFile,BufRead *.js set tabstop=2 softtabstop=4 shiftwidth=4 expandtab

" tell vim where to put its backup files
set backupdir=/private/tmp

" tell vim where to put swap files
set dir=/private/tmp
