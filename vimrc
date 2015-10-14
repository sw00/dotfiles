" because this is 2013
set nocompatible

" load pathogen modules
execute pathogen#infect()

" set colorscheme
colorscheme hybrid

" set line numbering
noremap <F2> :NumbersToggle<CR>
set number

" convenience mapping
map :Q<CR> :q<CR>

"clipboard support for osx
set clipboard=unnamed
if has("macunix")
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

" cycle buffers like this
noremap <c-w>] :bn<CR>
noremap <c-w>[ :bp<CR>

" overload my bufunload, etc..
nmap <leader>bd :MBEbd<CR>
nmap <leader>bw :MBEbw<CR>
nmap <leader>bun :MBEbun<CR>

"taglist
let Tlist_Use_Right_Window = 1
let Tlist_Ctags_Cmd='/usr/local/bin/ctags'
map <leader>t :TlistToggle<CR>

map <leader>N :NERDTreeToggle<CR>
let NERDTreeIgnore=['\.pyc', '\~$', '\.swo$', '\.swp$', '\.git', '\.hg', '\.svn', '\.bzr']

let g:syntastic_mode_map = { 'mode': 'passive',
                           \ 'active_filetypes': ['python', 'javascript', 'coffeescript'],
                           \ 'passive_filetypes': ['puppet'] }
nmap <leader>a <Esc>:Ack!

" set the gui options and stuff
if has("gui_running")
    set guioptions=egma
    set guifont=Source\ Code\ Pro\ for\ Powerline
endif

" set .pp to ruby filetye for syntax highlighting
au BufNewFile,BufRead *.pp set filetype=ruby

" tell vim where to put its backup files
set backupdir=/private/tmp

" tell vim where to put swap files
set dir=/private/tmp
