local M = {}

function M.close(view)
  if view and not view.closed and vim.api.nvim_buf_is_valid(view.buf) then
    vim.api.nvim_buf_delete(view.buf, { force = true })
  end
end

local function open(lines, accept, reject)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  local width = math.max(1, math.min(90, vim.o.columns - 4))
  local height = math.max(1, math.min(#lines, vim.o.lines - 6))
  local opened, win = pcall(vim.api.nvim_open_win, buf, true, {
    relative = 'editor', style = 'minimal', border = 'single', width = width, height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  })
  if not opened then
    vim.api.nvim_buf_delete(buf, { force = true })
    error(win)
  end
  if accept then vim.keymap.set('n', 'a', accept, { buffer = buf, nowait = true }) end
  for _, key in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', key, reject, { buffer = buf, nowait = true })
  end
  local view = { buf = buf, win = win }
  vim.api.nvim_create_autocmd('BufWipeout', { buffer = buf, once = true, callback = function()
    view.closed = true
    reject()
  end })
  return view
end

function M.open(before, replacement, accept, reject)
  local lines = { '73 replacement preview', 'a: accept    q / Esc: reject', '',
    '--- selected text', '+++ proposed replacement' }
  local diff = vim.diff(before, replacement, { result_type = 'unified', ctxlen = 3 })
  if diff == '' then
    lines[#lines + 1] = '(No text changes)'
  else
    vim.list_extend(lines, vim.split(diff:gsub('\n$', ''), '\n', { plain = true }))
  end
  local view = open(lines, accept, reject)
  vim.bo[view.buf].filetype = 'diff'
  return view
end

function M.answer(answer, close)
  local lines = { '73 answer', 'q / Esc: close', '' }
  vim.list_extend(lines, vim.split(answer, '\n', { plain = true }))
  return open(lines, nil, close)
end

return M
