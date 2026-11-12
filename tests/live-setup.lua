-- Verify the manual demo's setup only, with its adapter replaced before loading.
local pi = require('73.adapters.pi')
local original_new, starts = pi.new, 0
pi.new = function()
  return { capabilities = { ask = true, edit = true, insert = true }, request = function()
    starts = starts + 1
    error('live setup must not start a request')
  end }
end
local cwd = vim.fn.getcwd()
dofile('scripts/live-check.lua')
local temporary = vim.fn.getcwd()
local buf = vim.api.nvim_get_current_buf()
assert(temporary ~= cwd)
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, true)[1] == 'local marker = "unsaved-73"')
assert(vim.fn.readfile(temporary .. '/sample.lua')[1] == 'local marker = "disk-73"')
assert(vim.fn.exists(':SeventyThreeCheckDisk') == 2)
vim.cmd('SeventyThreeCheckDisk')
assert(starts == 0, 'setup sent a request')
pi.new = original_new
require('73').setup({})
vim.api.nvim_buf_delete(buf, { force = true })
vim.api.nvim_del_user_command('SeventyThreeCheckDisk')
vim.api.nvim_set_current_dir(cwd)
vim.fn.delete(temporary, 'rf')
print('73 live-demo setup checks passed (fake adapter only)')
