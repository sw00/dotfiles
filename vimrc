" because this is 2013
set nocompatible

" Load plugins using vim-plug
call plug#begin()
Plug 'tpope/vim-sensible'
Plug 'tpope/vim-sleuth'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-commentary'
Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeToggle' }
Plug 'w0rp/ale'
Plug 'itchyny/lightline.vim'
Plug 'qpkorr/vim-bufkill'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' } | Plug 'junegunn/fzf.vim'
Plug 'mileszs/ack.vim'
Plug 'ervandew/supertab'
Plug 'myusuf3/numbers.vim'
Plug 'elzr/vim-json', { 'for': 'json' }
Plug 'davidhalter/jedi-vim',  { 'for': 'python' }
Plug 'marijnh/tern_for_vim', { 'for': 'javascript' }
Plug 'lambdatoast/elm.vim', { 'for': 'elm' }
Plug 'fatih/vim-go', { 'for': 'go' }
Plug 'AndrewRadev/splitjoin.vim', { 'for': 'go' }
Plug 'SirVer/ultisnips'
Plug 'lervag/vimtex', {'for': 'tex' }
Plug 'vim-pandoc/vim-pandoc', {'for': 'pandoc'}
Plug 'vim-pandoc/vim-pandoc-syntax', {'for': 'pandoc'}
Plug 'junegunn/goyo.vim'
Plug 'junegunn/limelight.vim'
Plug 'soli/prolog-vim'
call plug#end()

" set colorscheme
colorscheme grb256

" remap leader key
let mapleader=","

" quick save
nnoremap <F2> :w<CR>

" set line numbering
set number
nnoremap <F3> :NumbersToggle<CR>
nnoremap <F4> :NumbersOnOff<CR>

" Switch between the last two files
nnoremap <leader><leader> <c-^>

" highlight line
set cursorline

" speed up vim
set ttyfast
set lazyredraw
"set synmaxcol=120

" highlight search term
set hlsearch
" only case-sensitive when search term contains uppercase
set ignorecase smartcase

" autowrite file when :make is called
set autowrite

" set swapfile and backupdir
set backupdir=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp
set directory=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp

" read file automatically when changed outside of vim
set autoread

" disable bell
set visualbell

" convenience mapping
map :Q<CR> :q<CR>

"clipboard support for osx
if has("macunix")
    set clipboard=unnamed
    vmap <C-c> y:call system("pbcopy", getreg("\""))<CR>
    imap <C-v> :call setreg("\"",system("pbpaste"))<CR>p
endif

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

"taglist
let Tlist_Use_Right_Window = 1
let Tlist_Ctags_Cmd='/usr/local/bin/ctags'
map <F7> :TlistToggle<CR>

" The Silver Searcher
if executable('ag')
  " Use ag over grep
  set grepprg=ag\ --nogroup\ --nocolor

  " use ag with ack.vim
"  let g:ackprg = 'ag --nogroup --nocolor --column'
  let g:ackprg = 'ag --vimgrep'
endif

" ack.vim
nmap <leader>a <Esc>:Ack!

" fzf.vim
let g:fzf_command_prefix = 'Fzf'
let g:fzf_launcher = "$HOME/.bin/fzf_iterm %s"
nnoremap <C-P> :FzfFiles<CR>
nnoremap <C-P>g :FzfGFiles<CR>
nnoremap <C-P>b :FzfBuffers<CR>
nnoremap <C-P><C-P> :FzfBuffers<CR>

 let g:rg_command = '
   \ rg --column --line-number --no-heading --fixed-strings --ignore-case --no-ignore --hidden --follow --color "always"
   \ -g "*.{py,js,java,cs,clj,json,php,md,html,config,cpp,c,go,rb,conf,cfg}"
   \ -g "!*.{min.js,swp,o,zip}" 
   \ -g "!{.git,node_modules,vendor,*__pycache__}/*" '

 command! -bang -nargs=* Find call fzf#vim#grep(g:rg_command .shellescape(<q-args>), 1, <bang>0)

" goyo & limelight
autocmd! User GoyoEnter Limelight
autocmd! User GoyoLeave Limelight!
autocmd! User GoyoEnter set nonu nornu
autocmd! User GoyoLeave set nu rnu

" nerdtree
map <C-n> :NERDTreeToggle<CR>
nmap <F3><F3> :NERDTreeFind<CR>
let NERDTreeIgnore=['\.pyc', '__pycache__', '\~$', '\.swo$', '\.swp$', '\.git', '\.hg', '\.svn', '\.bzr', 'node_modules$']

" ALE
let g:ale_lint_on_text_changed = 'never'

" set the gui options and stuff
if has("gui_running")
    set guioptions=egma
    set guifont=Source\ Code\ Pro\ for\ Powerline
    colorscheme atom-dark
endif

" set .pp to ruby filetye for syntax highlighting
au BufNewFile,BufRead *.pp set filetype=ruby

" golang shortcuts
" run :GoBuild or :GoTestCompile based on the go file
function! s:build_go_files()
  let l:file = expand('%')
  if l:file =~# '^\f\+_test\.go$'
    call go#cmd#Test(0, 1)
  elseif l:file =~# '^\f\+\.go$'
    call go#cmd#Build(0)
  endif
endfunction

autocmd FileType go nmap <leader>b :<C-u>call <SID>build_go_files()<CR>
autocmd FileType go nmap <leader>r  <Plug>(go-run)
autocmd FileType go nmap <leader>t  <Plug>(go-test)
autocmd FileType go nmap <Leader>c <Plug>(go-coverage-toggle)
