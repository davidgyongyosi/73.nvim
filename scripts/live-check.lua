-- Interactive, opt-in live acceptance workspace. Never loaded by smoke tests.
-- Run from the repository: nvim -u NONE -i NONE -c "lua dofile('scripts/live-check.lua')"
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd('runtime plugin/73.lua')
vim.opt.swapfile = false
local root = vim.fn.tempname()
vim.fn.mkdir(root, 'p')
local file = root .. '/sample.lua'
local disk = { 'local marker = "disk-73"', '', 'local function add(a, b)', '  return a + b', 'end' }
vim.fn.writefile(disk, file)
vim.api.nvim_set_current_dir(root)
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_name(buf, file)
local unsaved = vim.deepcopy(disk)
unsaved[1] = 'local marker = "unsaved-73"'
vim.api.nvim_buf_set_lines(buf, 0, -1, true, unsaved)
vim.bo[buf].filetype = 'lua'
local plugin = require('73')
plugin.register_adapter('pi_live_check', require('73.adapters.pi').new({ model = vim.env.SEVENTYTHREE_MODEL }))
plugin.setup({ harness = 'pi_live_check' })
for _, action in ipairs({ { 'n', 'a', 'ask' }, { 'x', 'e', 'edit' }, { 'n', 'i', 'insert' } }) do
  vim.keymap.set(action[1], '<leader>7' .. action[2], function()
    local ok, problem = pcall(plugin[action[3]])
    if not ok then vim.notify(tostring(problem), vim.log.levels.WARN) end
  end, { buffer = buf, desc = '73 live check: ' .. action[3] })
end
vim.api.nvim_create_user_command('SeventyThreeCheckDisk', function()
  assert(vim.deep_equal(vim.fn.readfile(file), disk), '73 live check: fixture on disk changed')
  vim.notify('73 live check: disk fixture is unchanged', vim.log.levels.INFO)
end, {})
vim.notify('73 live check: temporary workspace ' .. root
  .. '\nNo model request sent. Use <leader>7a (Ask), visual <leader>7e (Edit), <leader>7i (Insert).'
  .. '\nRequests use existing Pi authentication. See docs/LIVE_CHECK.md.', vim.log.levels.INFO)
