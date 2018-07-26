" Load plugins using vim-plug
call plug#begin()
" Essentials
Plug 'tpope/vim-sensible'
Plug 'tpope/vim-sleuth'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-commentary'
Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeToggle' }
Plug 'itchyny/lightline.vim'
Plug 'qpkorr/vim-bufkill'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' } | Plug 'junegunn/fzf.vim'
Plug 'mileszs/ack.vim'
Plug 'junegunn/goyo.vim'
Plug 'junegunn/limelight.vim'

" Completion
Plug 'ervandew/supertab'
Plug 'SirVer/ultisnips'
if has('nvim')
  Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
else
  Plug 'Shougo/deoplete.nvim'
  Plug 'roxma/nvim-yarp'
  Plug 'roxma/vim-hug-neovim-rpc'
endif

" IDE (multiline, lint, repl,...)
Plug 'AndrewRadev/splitjoin.vim'
Plug 'w0rp/ale'
Plug 'hkupty/iron.nvim', {'do': ':UpdateRemotePlugins'}

" Language support
Plug 'zchee/deoplete-jedi', { 'for': 'python'}
Plug 'szymonmaszke/vimpyter', { 'for': 'ipynb'}
Plug 'fatih/vim-go', { 'for': 'go' }
Plug 'lambdatoast/elm.vim', { 'for': 'elm' }
Plug 'elzr/vim-json', { 'for': 'json' }
Plug 'marijnh/tern_for_vim', { 'for': 'javascript' }
Plug 'lervag/vimtex', {'for': 'tex' }
Plug 'vim-pandoc/vim-pandoc', {'for': 'pandoc'}
Plug 'vim-pandoc/vim-pandoc-syntax', {'for': 'pandoc'}
Plug 'soli/prolog-vim', {'for': 'prolog'}
call plug#end()


" Appearance
colorscheme grb256
" enable true color if supported
if (has("termguicolors"))
  set termguicolors
endif

" relative numbering
set nu rnu

" highlight line
set cursorline

" highlight search term
set hlsearch

" speed up vim
set ttyfast
set lazyredraw
set synmaxcol=120

" Behaviour
set ignorecase smartcase
set autowrite
set hidden "allow switching buffers without saving
set autoread
set visualbell
set backupdir=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp
set directory=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp

" mappings
let mapleader=','
nnoremap <space> :nohlsearch<CR>

" nvim terminal escape seq
tnoremap kj <C-\><C-n>

" Switch between the last two files
nnoremap <leader><leader> <c-^>

" quick save
nnoremap <F2> :w<CR>

" convenience mappings
map :Q<CR> :q<CR>
map :Wq<CR> :wq<CR>
map :WQ<CR> :wq!<CR>

" easier mapping for navigating viewports
map <c-j> <c-w>j 
map <c-k> <c-w>k
map <c-l> <c-w>l
map <c-h> <c-w>h

" cycle buffers like this
nnoremap <Tab> :bn<CR>
nnoremap <S-Tab> :bp<CR>

" kill buffers
nmap <C-b>q :BD<CR>
nmap <C-b>c :bd<CR>

"clipboard support for osx
if has("macunix")
    set clipboard=unnamed
    vmap <C-c> y:call system("pbcopy", getreg("\""))<CR>
    imap <C-v> :call setreg("\"",system("pbpaste"))<CR>p
endif

" Plugins
" nerdtree
map <C-n> :NERDTreeToggle<CR>
nmap <F3><F3> :NERDTreeFind<CR>
let NERDTreeIgnore=['\.pyc', '__pycache__', '\~$', '\.swo$', '\.swp$', '\.git', '\.hg', '\.svn', '\.bzr', 'node_modules$']

" fzf.vim
let g:fzf_command_prefix = 'Fzf'
let g:fzf_launcher = "$HOME/.bin/fzf_iterm %s"
nnoremap <C-P><C-P> :FzfFiles<CR>
nnoremap <C-P>g :FzfGFiles<CR>
nnoremap <C-P>b :FzfBuffers<CR>
command! -bang -nargs=* Find call fzf#vim#grep(g:rg_command .shellescape(<q-args>), 1, <bang>0)

"supertab
let g:SuperTabDefaultCompletionType = "context"

" deoplete completion
let g:deoplete#enable_at_startup = 1

" " ALE
nnoremap <F8> <Plug>(ale_fix)
let g:ale_lint_on_text_changed = 'never'
let g:ale_fix_on_save = 1

" numbers
nnoremap <F3> :NumbersToggle<CR>
nnoremap <F4> :NumbersOnOff<CR>
let g:numbers_exclude = ['tagbar', 'nerdtree', 'Goyo']

"taglist
let Tlist_Use_Right_Window = 1
let Tlist_Ctags_Cmd='/usr/local/bin/ctags'
map <F7> :TlistToggle<CR>

" ackgrep etc.
nmap <leader>a <Esc>:Ack!

if executable('rg')
  set grepprg='rg'
  let g:ackprg='rg'
endif
let g:rg_command = '
      \ rg --column --line-number --no-heading --fixed-strings --ignore-case --no-ignore --hidden --follow --color "always"
      \ -g "*.{py,js,java,cs,clj,json,php,md,html,config,cpp,c,go,rb,conf,cfg}"
      \ -g "!*.{min.js,swp,o,zip}" 
      \ -g "!{.git,node_modules,vendor,*__pycache__}/*" '

" goyo & limelight
nmap <F12> :Goyo <bar> Limelight!!<CR>"
