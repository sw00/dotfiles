let mapleader=',' " remap leader key
inoremap kj <ESC> " quick escape to normal mode 
tnoremap kj <C-\><C-n> " nvim terminal escape seq
nnoremap <space> :nohlsearch<CR> " cancel highlight for search
nnoremap <leader><leader> <c-^> " switch between previous buffer

" copy/paste
if !has("clipboard") " vim not compiled with +clipboard support
    vmap y y:call system(g:clipboard_copy_cmd, getreg("\""))<CR>
    nmap p :call setreg("\"", system(g:clipboard_paste_cmd))<CR>p<Paste>
endif

func! SelectLineAndYank()
  normal gv"xy
  let result = getreg("x")
  return result
endf

nmap <C-c> :call system(g:clipboard_copy_cmd, SelectLineAndYank())<CR> " shift-c to copy line
nmap <C-x> :call system(g:clipboard_copy_cmd, SelectLineAndYank())<CR>gvx " shift-x to cut line

" quick save
nnoremap <F2> :w<CR>
noremap <c-s> :w<CR>
noremap <c-S> :w!<CR>

" comments
nmap <leader>/ <Plug>CommentaryLine
vmap <leader>/ <Plug>Commentary

" convenience mappings
noremap :Q<CR> :q<CR>
noremap :Wq<CR> :wq<CR>
noremap :WQ<CR> :wq!<CR>
noremap :wQ<CR> :wq!<CR>
noremap :X<CR> :x!<CR>

" easier mapping for navigating viewports
noremap <c-j> <c-w>j 
noremap <c-k> <c-w>k
noremap <c-l> <c-w>l
noremap <c-h> <c-w>h

" cycle tabs like this
nnoremap <Tab> :tabn<CR>
nnoremap <S-Tab> :tabp<CR>

" fzf
nnoremap <c-p><c-p> :FzfFiles<CR>
nnoremap <c-p>f :FzfFiles<CR>
nnoremap <c-p>b :FzfBuffers<CR>
nnoremap <c-p>t :FzfBTags<CR>
nnoremap <c-p>ta :FzfTags<CR>
nnoremap <c-p>g :FzfGFiles<CR>
nnoremap <c-p>gs :FzfGFiles?<CR>
nnoremap <c-p>gc :FzfBCommits<CR>
nnoremap <c-p>gh :FzfCommits<CR>
nnoremap <c-p>a :FzfAckShortcut<CR>
if executable('rg')
  nmap <c-p>a :FzfRg expand("<cword>")<CR>
else
  nmap <c-p>a :FzfAg expand("<cword>")<CR>
endif

" nerdtree
map <C-n> :NERDTreeToggle<CR>
nmap <F3><F3> :NERDTreeFind<CR>

" completions, lint & static analysis
inoremap <c-space> <c-x><c-o>
nmap <leader>l <Plug>(ale_fix)
nmap <F8> <Plug>(ale_fix)
nmap <S-F8> <Plug>(ale_toggle)
nmap an <Plug>(ale_next_wrap)
nmap ap <Plug>(ale_previous_wrap)

"tagbar
nmap <F7> :TagbarToggle<CR>

" rg/ack.vim
nmap <leader>a <Esc>:Ack!

" goyo & limelight
nmap <F12> :Goyo <bar> Limelight!!<CR>

