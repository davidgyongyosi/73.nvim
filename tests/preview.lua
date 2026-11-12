local preview = require('73.preview')
local source = vim.api.nvim_get_current_buf()
local tick = vim.api.nvim_buf_get_changedtick(source)
for _, case in ipairs({
  { 'old\n', 'new\n', '-old', '+new' },
  { '', 'inserted', '+inserted' },
  { 'deleted', '', '-deleted' },
  { 'café\n', '茶\n', '-café', '+茶' },
  { 'same', 'same', '(No text changes)' },
}) do
  local view = preview.open(case[1], case[2], function() end, function() end)
  local lines = vim.api.nvim_buf_get_lines(view.buf, 0, -1, true)
  for i = 3, #case do assert(vim.tbl_contains(lines, case[i]), vim.inspect(lines)) end
  assert(vim.bo[view.buf].filetype == 'diff' and not vim.bo[view.buf].modifiable)
  preview.close(view)
end
assert(vim.api.nvim_buf_get_changedtick(source) == tick)
print('73 unified preview checks passed')
