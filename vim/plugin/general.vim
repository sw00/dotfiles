" Appearance
set t_Co=256 
colorscheme PaperColor
set bg=dark

" Show whitespace chars
set listchars=space:·,eol:¬,tab:▸~

" relative numbering
set nu rnu

" highlight line
set cursorline
" hi cursorline term=bold cterm=bold ctermbg=235
" highlight Visual term=reverse cterm=reverse ctermbg=NONE

" highlight search term
set hlsearch

" speed up vim
set ttyfast
set lazyredraw
set synmaxcol=0

" Behaviour
set mouse=a " use mouse
set ignorecase smartcase
set autowrite
set hidden "allow switching buffers without saving
set autoread
set visualbell
set backupdir=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp
set directory=~/.vim-tmp,~/.tmp,~/tmp,/var/tmp,/tmp

" always try copy to CLIPBOARD
set clipboard=unnamedplus

" clipboard command
if !has("nvim") && !has("clipboard")
  if executable("clip.exe")
    let g:clipboard_copy_cmd = 'clip.exe'
    let g:clipboard_paste_cmd = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))'
  elseif has("mac")
    let g:clipboard_copy_cmd = 'pbcopy'
    let g:clipboard_paste_cmd = 'pbpaste'
  else
    let g:clipboard_copy_cmd = 'xsel -ib'
    let g:clipboard_paste_cmd = 'xsel -ob'
  endif
endif

" nerdtree
let NERDTreeIgnore=['\.pyc', '__pycache__', '\~$', '\.swo$', '\.swp$', '\.git', '\.hg', '\.svn', '\.bzr', 'node_modules$', 'target']

" search
if executable('rg')
  set grepprg='rg'
  let g:ackprg = 'rg --vimgrep --no-heading --smart-case --glob "!.git/**"'

  let g:rg_command = '
        \ rg --column --line-number --no-heading --fixed-strings --smart-case --no-ignore --hidden --follow --color "always"
        \ -g "*.{py,js,java,cs,clj,json,php,md,html,config,cpp,c,go,rb,conf,cfg}"
        \ -g "!*.{min.js,swp,o,zip,pyc}"
        \ -g "!{.git,node_modules,vendor,*__pycache__}/*,target" '
endif

" fzf.vim
let g:fzf_command_prefix = 'Fzf'

" = completions & linting =
autocmd InsertLeave,CompleteDone * if pumvisible() == 0 | pclose | endif " close info window

" SuperTab
" let g:SuperTabDefaultCompletionType = 'context'
" let g:SuperTabContextDefaultCompletionType = '<c-x><c-o>'
" let g:SuperTabContextTextOmniPrecedence = ['&omnifunc', '&completefunc']
let g:SuperTabClosePreviewOnPopupClose = 1

" ALE
let g:ale_lint_on_text_changed = 'never'
let g:ale_lint_on_insert_leave = 1
let g:ale_set_highlights = 0
let g:ale_set_balloons = 1
let g:ale_virtual_text_cursor = 1
let g:ale_disable_lsp = 0
let g:ale_fixers = {
      \ '*': ['remove_trailing_lines', 'trim_whitespace']
      \}

let g:ale_completion_enabled = 0
let g:ale_linters = {}
let g:ale_fixers = {}

" python
autocmd FileType python set noshowmode " make call signature visible
let g:jedi#completions_enabled = 1 " use deoplete-jedi
let g:deoplete#sources#jedi#ignore_errors = 1
let g:deoplete#sources#jedi#enable_typeinfo = 0
let g:jedi#use_splits_not_buffers = "right"
let g:jedi#show_call_signatures = 2
let g:jedi#show_call_signatures_delay = 0
let g:jedi#popup_complete_first = 1

" rust
let g:ale_linters.rust = ['cargo', 'analyzer']
let g:ale_fixers.rust = ['rustfmt']
let g:ale_rust_cargo_check_tests = 1
let g:ale_rust_cargo_use_clippy = 1

" ruby
let g:ale_linters.ruby = ['ruby', 'standardrb', 'solargraph']
let g:ale_fixers.ruby = ['standardrb']

" yaml
let g:ale_fixers.yaml = ['prettier']

