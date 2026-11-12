local plugin = require('73')
local calls = {}
plugin.register_adapter('focus_fixture', {
  capabilities = { ask = true, insert = true },
  request = function(request, respond)
    calls[#calls + 1] = { request = request, respond = respond }
  end,
})
plugin.setup({ harness = 'focus_fixture' })
local function buffer()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, { 'source', 'second' })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  return buf
end
local function response(call)
  local doc = call.request.document
  local value = { id = call.request.id, uri = doc.uri, revision = doc.revision,
    content_hash = doc.content_hash }
  if call.request.operation == 'ask' then value.answer = 'answer'
  else value.replacement, value.range = 'inserted', doc.range end
  return value
end
local function reply(call)
  call.respond(response(call))
  vim.wait(20, function() return false end)
end
local first = buffer()
local old = plugin.ask('first')
local old_call = calls[#calls]
local second = buffer()
local newer = plugin.ask('second')
reply(calls[#calls])
local window, preview_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
assert(newer.status() == 'answered')
reply(old_call)
assert(old.status() == 'ready')
assert(vim.api.nvim_get_current_win() == window and vim.api.nvim_get_current_buf() == preview_buf)
assert(not old.show(), 'old handle must not steal another preview')
newer.close()
vim.api.nvim_set_current_buf(first)
vim.cmd('SeventyThreeShow')
assert(old.status() == 'answered')
assert(plugin.request_status().state == 'answered')
old.close()

-- Moving to another window showing the same source also defers focus.
first = buffer()
old = plugin.insert('insert')
old_call = calls[#calls]
vim.cmd('vsplit')
window = vim.api.nvim_get_current_win()
reply(old_call)
assert(old.status() == 'ready' and vim.api.nvim_get_current_win() == window)
assert(not old.accept(), 'deferred result cannot skip preview')
assert(plugin.show())
assert(old.status() == 'preview')
assert(old.accept())
vim.api.nvim_set_current_win(window)
vim.cmd('undo')
assert(vim.api.nvim_buf_get_lines(first, 0, 1, true)[1] == 'source')
vim.cmd('close')

-- Stale results are rejected again when explicitly opened.
first = buffer()
old = plugin.insert('later')
old_call = calls[#calls]
vim.api.nvim_win_set_cursor(0, { 2, 0 })
reply(old_call)
assert(old.status() == 'ready')
vim.api.nvim_buf_set_text(first, 1, 0, 1, 0, { 'changed' })
assert(not plugin.show())
assert(old.status() == 'failed')

-- Returning to the original buffer does not let an older request override newer work.
first = buffer()
old = plugin.ask('older')
old_call = calls[#calls]
second = buffer()
newer = plugin.ask('newer')
vim.api.nvim_set_current_buf(first)
reply(old_call)
assert(old.status() == 'ready' and vim.api.nvim_get_current_buf() == first)
old.cancel(); newer.cancel()

-- A cancelled ready result cannot reopen; replacement requests own the status.
first = buffer()
old = plugin.ask('cancel ready')
old_call = calls[#calls]
vim.api.nvim_win_set_cursor(0, { 2, 0 })
reply(old_call)
assert(old.status() == 'ready')
newer = plugin.ask('replacement')
assert(old.status() == 'cancelled' and not old.show())
assert(plugin.request_status().state == 'pending')
newer.cancel()

-- Simulate Neovim's mode query; headless input exhaustion exits real insert mode.
first = buffer()
old = plugin.ask('typing')
old_call = calls[#calls]
local original_mode = vim.fn.mode
vim.fn.mode = function() return 'i' end
reply(old_call)
assert(old.status() == 'ready' and vim.api.nvim_get_current_buf() == first)
assert(not plugin.show(), 'show must not enter a float from insert mode')
vim.fn.mode = original_mode
assert(plugin.show())
old.close()

-- Failed window creation must release the scratch buffer and ready request.
first = buffer()
old = plugin.ask('broken view')
old_call = calls[#calls]
vim.api.nvim_win_set_cursor(0, { 2, 0 })
reply(old_call)
local original_open = vim.api.nvim_open_win
local before = vim.api.nvim_list_bufs()
vim.api.nvim_open_win = function() error('fixture window failure') end
assert(not plugin.show())
vim.api.nvim_open_win = original_open
assert(old.status() == 'failed')
assert(vim.deep_equal(before, vim.api.nvim_list_bufs()), 'failed preview leaked a buffer')
assert(not plugin.show())
plugin.setup({})
print('73 deferred-preview focus checks passed')
