-- [[scratch buffer]]
function NewScratch()
    vim.cmd('tabnew', false)
    vim.opt_local.buftype = 'nofile'
    vim.opt_local.bufhidden = 'hide'
    vim.opt_local.swapfile = nil
end
