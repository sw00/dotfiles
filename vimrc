" because this is 2013
set nocompatible

" buffer-specific colorschemes
if has('autocmd')
	" change colorscheme depending on current buffer
	" if desired, you may set a user-default colorscheme before this point,
	" otherwise we'll use the Vim default.
	" Variables used:
		" g:colors_name : current colorscheme at any moment
		" b:colors_name (if any): colorscheme to be used for the current buffer
		" s:colors_name : default colorscheme, to be used where b:colors_name hasn't been set
	if has('user_commands')
		" User commands defined:
			" ColorScheme <name>
				" set the colorscheme for the current buffer
			" ColorDefault <name>
				" change the default colorscheme
		command -nargs=1 -bar ColorScheme
			\ colorscheme <args>
			\ | let b:colors_name = g:colors_name
		command -nargs=1 -bar ColorDefault
			\ let s:colors_name = <q-args>
			\ | if !exists('b:colors_name')
				\ | colors <args>
			\ | endif
	endif
	if !exists('g:colors_name')
		let g:colors_name = 'github'
	endif
	let s:colors_name = g:colors_name
	au BufEnter *
		\ let s:new_colors = (exists('b:colors_name')?(b:colors_name):(s:colors_name))
		\ | if s:new_colors != g:colors_name
			\ | exe 'colors' s:new_colors
		\ | endif
endif

execute pathogen#infect()

" set filetype and indentation
syntax on
filetype plugin indent on

" set line numbering
set number 
noremap <F2> :set nonumber!<CR>

" set all tabs to be 4 spaces
set softtabstop=4
set shiftwidth=4
set smarttab
set expandtab

" backspace over indents in insert mode
set bs=indent

"a autindent and allow mouse everywhere
set autoindent
set mouse=a

" powerline
set laststatus=2
set rtp+=~/.vim/bundle/powerline/powerline/bindings/vim

" for python code folds
set foldmethod=indent
set foldlevel=99

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

map <leader>n :NERDTreeToggle<CR>
let NERDTreeIgnore=['\.pyc', '\~$', '\.swo$', '\.swp$', '\.git', '\.hg', '\.svn', '\.bzr']

let g:syntastic_mode_map = { 'mode': 'passive',
                           \ 'active_filetypes': ['python', 'javascript'],
                           \ 'passive_filetypes': ['puppet'] }
nmap <leader>a <Esc>:Ack!


" set the themes and stuff
if has("gui_running")
    set guifont=Source\ Code\ Pro\ for\ Powerline
    set background=light
    set guioptions-=L
    set guioptions-=r
    " ctrl-tab cycles current buffer
    let g:miniBufExplMapCTabSwitchBufs = 1 
    " fix path issue - gui vim doesn't load .zshrc
    let $PATH="/usr/local/bin:/usr/local/share/python:".$PATH
else
    set t_Co=256
endif

