" Load plugins using vim-plug
call plug#begin()
" Essentials
Plug 'tpope/vim-sensible'
Plug 'tpope/vim-sleuth'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-rhubarb'
Plug 'tpope/vim-surround'
Plug 'tpope/vim-commentary'
Plug 'gioele/vim-autoswap'
Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeToggle' }
Plug 'itchyny/lightline.vim'
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' } | Plug 'junegunn/fzf.vim'
Plug 'mileszs/ack.vim'
Plug 'junegunn/goyo.vim'
Plug 'junegunn/limelight.vim'
Plug 'weiss/textgenshi.vim'

" Completion
Plug 'ervandew/supertab'
Plug 'SirVer/ultisnips'
if has('nvim')
  Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
  Plug 'neovim/nvim-lsp'
else
  Plug 'Shougo/deoplete.nvim'
  Plug 'roxma/nvim-yarp'
  Plug 'roxma/vim-hug-neovim-rpc'
endif

" IDE (multiline, lint, repl,...)
Plug 'AndrewRadev/splitjoin.vim'
Plug 'majutsushi/tagbar'
Plug 'pechorin/any-jump.vim'
Plug 'w0rp/ale'
Plug 'hkupty/iron.nvim', {'do': ':UpdateRemotePlugins'}
Plug 'NLKNguyen/papercolor-theme'
Plug 'arcticicestudio/nord-vim'
Plug 'shumphrey/fugitive-gitlab.vim'


" Language support
Plug 'davidhalter/jedi-vim', { 'for': 'python' }
Plug 'deoplete-plugins/deoplete-jedi', { 'for': 'python' }
Plug 'alfredodeza/pytest.vim', {'for': 'python'}
Plug 'szymonmaszke/vimpyter', { 'for': 'ipynb'}
Plug 'fatih/vim-go', { 'for': 'go' }
Plug 'lambdatoast/elm.vim', { 'for': 'elm' }
Plug 'elzr/vim-json', { 'for': 'json' }
Plug 'marijnh/tern_for_vim', { 'for': 'javascript' }
Plug 'lervag/vimtex', {'for': 'tex' }
Plug 'vim-pandoc/vim-pandoc', {'for': 'pandoc'}
Plug 'vim-pandoc/vim-pandoc-syntax', {'for': 'pandoc'}
Plug 'soli/prolog-vim', {'for': 'prolog'}
Plug 'thanethomson/vim-jenkinsfile'
Plug 'rust-lang/rust.vim', {'for': 'rust' }
Plug 'vim-ruby/vim-ruby', {'for': 'ruby' }
call plug#end()


" Appearance
colorscheme PaperColor

" Show whitespace chars
set listchars=space:·,eol:¬,tab:▸~

" relative numbering
set nu rnu

" highlight line
set cursorline
hi cursorline term=bold cterm=bold ctermbg=235
highlight Visual term=reverse cterm=reverse ctermbg=NONE
set bg=light


" highlight search term
set hlsearch

" speed up vim
set ttyfast
set lazyredraw
set synmaxcol=0

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
imap kj <ESC>
nnoremap <space> :nohlsearch<CR>

" Switch between the last two files
nnoremap <leader><leader> <c-^>

" quick save
nnoremap <F2> :w<CR>

" always copy to CLIPBOARD too
set clipboard=unnamedplus

if has('nvim')
  " nvim terminal escape seq
  tnoremap kj <C-\><C-n>

else " not nvim
  func! GetSelectedText()
      normal gv"xy
      let result = getreg("x")
      return result
  endfunc

  " macos
  if has("macunix")
    vnoremap y y:call system("pbcopy", getreg("\""))<CR>
    nnoremap p :call setreg("\"", system("pbpaste"))<CR>p<Paste>
  endif

  " wsl
  if !has("clipboard") && executable("clip.exe")
      noremap <C-c> :call system('clip.exe', GetSelectedText())<CR>
      noremap <C-x> :call system('clip.exe', GetSelectedText())<CR>gvx
  endif
endif

" convenience mappings
map :Q<CR> :q<CR>
map :Wq<CR> :wq<CR>
map :WQ<CR> :wq!<CR>
map :X<CR> :x!<CR>
map <c-s> :w<CR>
map <c-S> :w!<CR>

" easier mapping for navigating viewports
map <c-j> <c-w>j 
map <c-k> <c-w>k
map <c-l> <c-w>l
map <c-h> <c-w>h

" cycle tabs like this
nnoremap <Tab> :tabn<CR>
nnoremap <S-Tab> :tabp<CR>

" Plugins
" nerdtree
map <C-n> :NERDTreeToggle<CR>
nmap <F3><F3> :NERDTreeFind<CR>
let NERDTreeIgnore=['\.pyc', '__pycache__', '\~$', '\.swo$', '\.swp$', '\.git', '\.hg', '\.svn', '\.bzr', 'node_modules$']

" rg/ack.vim
nmap <leader>a <Esc>:Ack!

if executable('rg')
  set grepprg='rg'
  let g:ackprg = 'rg --vimgrep --no-heading --smart-case --glob "!.git/**"'

  let g:rg_command = '
        \ rg --column --line-number --no-heading --fixed-strings --smart-case --no-ignore --hidden --follow --color "always"
        \ -g "*.{py,js,java,cs,clj,json,php,md,html,config,cpp,c,go,rb,conf,cfg}"
        \ -g "!*.{min.js,swp,o,zip,pyc}"
        \ -g "!{.git,node_modules,vendor,*__pycache__}/*" '
endif

" fzf.vim
let g:fzf_command_prefix = 'Fzf'
nnoremap <c-p><c-p> :FzfFiles<CR>
nnoremap <c-p>f :FzfFiles<CR>

nnoremap <c-p>b :FzfBuffers<CR>
nnoremap <c-p>t :FzfBTags<CR>
nnoremap <c-p>ta :FzfTags<CR>

if executable('rg')
  nnoremap <c-p>a :FzfRg expand("<cWORD>")<CR>
else
  nnoremap <c-p>a :FzfAg expand("<cWORD>")<CR>
endif
  
nnoremap <c-p>g :FzfGFiles<CR>
nnoremap <c-p>gs :FzfGFiles?<CR>
nnoremap <c-p>gc :FzfBCommits<CR>
nnoremap <c-p>gca :FzfCommits<CR>

" jedi-vim
let g:jedi#completions_enabled = 0 " defer to deoplete for completion

" deoplete
let g:deoplete#enable_at_startup = 1
autocmd InsertLeave,CompleteDone * if pumvisible() == 0 | pclose | endif

" SuperTab
let g:SuperTabDefaultCompletionType = "<c-x><c-o>"
let g:SuperTabContextTextOmniPrecedence = ['&omnifunc', '&completefunc']

" ALE
let g:ale_lint_on_text_changed = 'never'
let g:ale_lint_on_insert_leave = 1
let g:ale_set_highlights = 1
let g:ale_set_balloons = 1
let g:ale_completion_enabled = 0
let g:ale_disable_lsp = 1
let g:ale_fixers = {
      \ '*': ['remove_trailing_lines', 'trim_whitespace']
      \}

nmap <leader>l <Plug>(ale_fix)
nmap <F8> <Plug>(ale_fix)
nmap <S-F8> <Plug>(ale_toggle)
nmap an <Plug>(ale_next_wrap)
nmap ap <Plug>(ale_previous_wrap)

"tagbar
nmap <F7> :TagbarToggle<CR>

" goyo & limelight
nmap <F12> :Goyo <bar> Limelight!!<CR>"

" rust
let g:racer_experimental_completer = 1
let g:racer_insert_paren = 1
let g:rustfmt_autosave = 0

