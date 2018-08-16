set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath
let g:loaded_python_provider = 1
let g:python_host_prog = $HOME . '/.pyenv/versions/py2neovim/bin/python'
let g:python3_host_prog = $HOME . '/.pyenv/versions/3.6.5/bin/python'
source ~/.vimrc
