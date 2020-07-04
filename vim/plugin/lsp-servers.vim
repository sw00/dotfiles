" if has("nvim-0.5.0")
let g:language_client_log_level = 'debug'

lua << EOF
local nvim_lsp = require'nvim_lsp'
nvim_lsp.solargraph.setup{}
EOF

function! LSPRename()
    let s:newName = input('Enter new name: ', expand('<cword>'))
    echom "s:newName = " . s:newName
    lua vim.lsp.buf.rename(s:newName)
endfunction

function! LSPSetMappings()
    setlocal omnifunc=v:lua.vim.lsp.omnifunc
    nnoremap <silent> <buffer> gd    <cmd>lua vim.lsp.buf.declaration()<CR>
    nnoremap <silent> <buffer> <c-]> <cmd>lua vim.lsp.buf.definition()<CR>
    nnoremap <silent> <buffer> K     <cmd>lua vim.lsp.buf.hover()<CR>
    nnoremap <silent> <buffer> gD    <cmd>lua vim.lsp.buf.implementation()<CR>
    nnoremap <silent> <buffer> <c-k> <cmd>lua vim.lsp.buf.signature_help()<CR>
    nnoremap <silent> <buffer> 1gD   <cmd>lua vim.lsp.buf.type_definition()<CR>
    nnoremap <silent> <buffer> gr    <cmd>lua vim.lsp.buf.references()<CR>
    nnoremap <silent> <buffer> <F2> :call LSPRename()<CR>
endfunction

au FileType ruby :call LSPSetMappings()
" endif
