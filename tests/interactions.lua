local plugin = require('73')
local calls = {}
plugin.register_adapter('interactions', {
  capabilities = { ask = true, insert = true, edit = true },
  request = function(request, respond)
    calls[#calls + 1] = { request = request, respond = respond }
    return function() end
  end,
})
plugin.setup({ harness = 'interactions' })
local function buffer()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, { 'aéb', 'unsaved' })
  vim.api.nvim_win_set_cursor(0, { 1, 1 })
  return buf
end
local function drain() vim.wait(20, function() return false end) end
local function reply(value, call)
  call = call or calls[#calls]
  local doc = call.request.document
  local response = { id = call.request.id, uri = doc.uri, revision = doc.revision,
    content_hash = doc.content_hash, range = vim.deepcopy(doc.range) }
  if call.request.operation == 'ask' then response.answer = value else response.replacement = value end
  call.respond(response)
  drain()
end
local buf = buffer()
local tick = vim.api.nvim_buf_get_changedtick(buf)
local handle = plugin.ask('Explain this')
assert(calls[#calls].request.operation == 'ask')
assert(calls[#calls].request.document.text == 'aéb\nunsaved\n')
reply('An explanation\nwith two lines')
assert(handle.status() == 'answered')
assert(not handle.accept())
assert(vim.api.nvim_buf_get_changedtick(buf) == tick)
local answer_buf = vim.api.nvim_get_current_buf()
assert(not vim.bo[answer_buf].modifiable)
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(answer_buf, 'n')) do assert(mapping.lhs ~= 'a') end
assert(handle.close())
assert(handle.status() == 'closed')
assert(not vim.api.nvim_buf_is_valid(answer_buf))

buf = buffer()
handle = plugin.insert('Insert a guard')
local call = calls[#calls]
assert(call.request.operation == 'insert')
assert(vim.deep_equal(call.request.document.range, { start = { 0, 1 }, ['end'] = { 0, 1 } }))
vim.api.nvim_win_set_cursor(0, { 2, 0 }) -- movement must not retarget insertion
reply('X\nY')
assert(handle.status() == 'ready', 'cursor movement must defer preview focus')
assert(handle.show())
assert(handle.accept())
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, true), { 'aX', 'Yéb', 'unsaved' }))
vim.api.nvim_set_current_buf(buf)
vim.cmd('undo')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, true), { 'aéb', 'unsaved' }))
assert(not pcall(plugin.insert, 'bad', { range = { start = { 0, 0 }, ['end'] = { 0, 1 } } }))

-- Both operations reject stale and cancelled responses without opening a view.
for _, operation in ipairs({ 'ask', 'insert' }) do
  for _, cancel in ipairs({ false, true }) do
    buf = buffer()
    handle = plugin[operation]('test')
    if cancel then handle.cancel() else vim.api.nvim_buf_set_text(buf, 1, 0, 1, 0, { 'new ' }) end
    reply('late')
    assert(handle.status() == (cancel and 'cancelled' or 'failed'))
    assert(vim.api.nvim_get_current_buf() == buf)
  end
end
buf = buffer()
handle = plugin.ask('bad answer')
reply({ 'not text' })
assert(handle.status() == 'failed')
handle = plugin.ask('old question')
local old_call = calls[#calls]
local newer = plugin.insert('new insertion')
assert(handle.status() == 'cancelled')
reply('old answer', old_call)
reply('new text')
assert(newer.status() == 'preview')
newer.reject()

-- UI input callbacks may be delayed, cancelled, or repeated.
local original_input, input_callback = vim.ui.input, nil
vim.ui.input = function(_, callback) input_callback = callback end
buf = buffer()
handle = plugin.insert()
assert(handle.status() == 'prompting')
local count = #calls
vim.api.nvim_win_set_cursor(0, { 2, 0 })
input_callback('Describe insertion')
input_callback('duplicate')
drain()
assert(#calls == count + 1)
assert(calls[#calls].request.instruction == 'Describe insertion')
assert(vim.deep_equal(calls[#calls].request.document.range.start, { 0, 1 }))
reply('inserted')
handle.reject()
for _, action in ipairs({ 'dismiss', 'change', 'cancel', 'switch' }) do
  buf = buffer()
  handle = plugin.ask()
  local callback = input_callback
  count = #calls
  if action == 'change' then vim.api.nvim_buf_set_text(buf, 0, 0, 0, 0, { 'changed' }) end
  if action == 'cancel' then handle.cancel() end
  if action == 'switch' then buffer() end
  if action == 'dismiss' then callback(nil) else callback('question') end
  drain()
  if action == 'switch' then
    assert(#calls == count + 1)
    assert(calls[#calls].request.document.text == 'aéb\nunsaved\n')
    handle.cancel()
  else
    assert(#calls == count)
    assert(handle.status() == (action == 'change' and 'failed' or 'cancelled'))
  end
end
vim.ui.input = original_input

-- Selection questions preserve Unicode byte bounds through a delayed prompt.
vim.ui.input = function(_, callback) input_callback = callback end
buf = buffer()
vim.api.nvim_feedkeys('gg0vl', 'nx', false)
handle = plugin.ask()
input_callback('Explain selection')
drain()
assert(vim.deep_equal(calls[#calls].request.document.range, { start = { 0, 0 }, ['end'] = { 0, 3 } }))
reply('Selection answer')
assert(handle.status() == 'answered')
handle.close()
vim.ui.input = original_input

-- A malicious/mistaken editing response to Ask is never applied or displayed.
buf = buffer()
handle = plugin.ask('question')
call = calls[#calls]
local doc = call.request.document
call.respond({ id = call.request.id, uri = doc.uri, revision = doc.revision,
  content_hash = doc.content_hash, answer = 'answer', replacement = 'unexpected edit' })
drain()
assert(handle.status() == 'failed')
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, true)[1] == 'aéb')

-- Capabilities are operation-specific, even with a request implementation.
plugin.register_adapter('ask_only', { capabilities = { ask = true }, request = function() end })
plugin.setup({ harness = 'ask_only' })
assert(not pcall(plugin.insert, 'unsupported'))
plugin.setup({ harness = 'demo' })
buf = buffer()
handle = plugin.ask('fake')
drain()
assert(handle.status() == 'answered')
handle.close()
plugin.setup({})
print('73 question and insertion checks passed')
