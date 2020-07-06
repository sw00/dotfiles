" use ALE to complete (integrates better with LSP)
let g:ale_rust_cargo_check_tests = 1
let g:ale_linters = {'rust': ['rls']}
let b:ale_fixers = {
\   '*': ['remove_trailing_lines', 'trim_whitespace'],
\   'rust': ['rustfmt'],
\}

" key bindingshttps://github.com/racer-rust/racer#configuration
nmap <buffer> gd         <Plug>(rust-def)
nmap <buffer> gs         <Plug>(rust-def-split)
nmap <buffer> gx         <Plug>(rust-def-vertical)
nmap <buffer> gt         <Plug>(rust-def-tab)
nmap <buffer> <leader>gd <Plug>(rust-doc)
nmap <buffer> K          <Plug>(rust-doc)
nmap <buffer> <leader>gD <Plug>(rust-doc-tab)
nmap <buffer> <leader>t  :RustTest<CR>
nmap <buffer> <leader>T  :RustTest!<CR>

