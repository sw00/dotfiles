set runtimepath^=~/.vim runtimepath+=~/.vim/after
let &packpath = &runtimepath
let g:loaded_python_provider = 1

if executable('asdf')
  let g:python_host_prog = expand('~/.asdf/shims/python2')
  let g:python3_host_prog = expand('~/.asdf/shims/python3')
endif

source ~/.vimrc
