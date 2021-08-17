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

" Completion
if has('nvim')
  Plug 'neoclide/coc.nvim', {'branch': 'release'}
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
Plug 'NLKNguyen/papercolor-theme'
Plug 'arcticicestudio/nord-vim'
Plug 'shumphrey/fugitive-gitlab.vim'
Plug 'nvim-lua/diagnostic-nvim'
Plug 'skbolton/embark'

" Language support
Plug 'fatih/vim-go', { 'for': 'go' }
Plug 'lambdatoast/elm.vim', { 'for': 'elm' }
Plug 'elzr/vim-json', { 'for': 'json' }
Plug 'lervag/vimtex', {'for': 'tex' }
Plug 'vim-pandoc/vim-pandoc', {'for': 'pandoc'}
Plug 'vim-pandoc/vim-pandoc-syntax', {'for': 'pandoc'}
Plug 'soli/prolog-vim', {'for': 'prolog'}
Plug 'rust-lang/rust.vim', {'for': 'rust' }
Plug 'vim-ruby/vim-ruby', {'for': 'ruby' }
Plug 'jvirtanen/vim-hcl', {'for': 'hcl' }
Plug 'elixir-editors/vim-elixir', {'for': 'elixir'}
Plug 'elixir-lsp/coc-elixir', {'do': 'yarn install && yarn prepack'}
call plug#end()

