let g:language_client_log_level = 'debug'

func! LSPEnable() abort
  lua << EOF
    local nvim_lsp = require'nvim_lsp'
    local on_attach = function(client)
      require'diagnostic'.on_attach()
    end

    do
      local method = 'textDocument/publishDiagnostics'
      local default_callback = vim.lsp.callbacks[method]
      vim.lsp.callbacks[method] = function(err, method, result, client_id)
        default_callback(err, method, result, client_id)
        if result and result.diagnostics then
          for _, v in ipairs(result.diagnostics) do
            v.uri = v.uri or result.uri
          end
          vim.lsp.util.set_qflist(result.diagnostics)
        end
      end
    end

    nvim_lsp.solargraph.setup{}
    nvim_lsp.rust_analyzer.setup{}
EOF
endf

function! LSPRename()
  let b:newName = input('Enter new name: ', expand('<cword>'))
  echom "b:newName = " . b:newName
  lua vim.lsp.buf.rename(vim.b.newName)
endfunction

function! LSPSetMappings()
    nnoremap <silent> gd    <cmd>lua vim.lsp.buf.declaration()<CR>
    nnoremap <silent> <c-]> <cmd>lua vim.lsp.buf.definition()<CR>
    nnoremap <silent> K     <cmd>lua vim.lsp.buf.hover()<CR>
    nnoremap <silent> gD    <cmd>lua vim.lsp.buf.implementation()<CR>
    nnoremap <silent> <leader><C-k> <cmd>lua vim.lsp.buf.signature_help()<CR>
    nnoremap <silent> 1gD   <cmd>lua vim.lsp.buf.type_definition()<CR>
    nnoremap <silent> gr    <cmd>lua vim.lsp.buf.references()<CR>
    nnoremap <silent> g0    <cmd>lua vim.lsp.buf.document_symbol()<CR>
    nnoremap <silent> gW    <cmd>lua vim.lsp.buf.workspace_symbol()<CR>
    nnoremap <silent> <buffer> <F2> :call LSPRename()<CR>
    nnoremap <silent> ld    <cmd>lua vim.lsp.util.show_line_diagnostics()<CR>
    nnoremap <silent> ls    <cmd>let &l:statusline = '%#MyStatuslineLSP#LSP '.LspStatus()<CR>
endfunction

