local plugin = require('73')
local snapshot = require('73.snapshot')
local calls, cancel_count = {}, 0
plugin.register_adapter('controlled', {
  capabilities = { edit = true },
  request = function(request, respond)
    calls[#calls + 1] = { request = request, respond = respond }
    return function() cancel_count = cancel_count + 1 end
  end,
})
plugin.setup({ harness = 'controlled' })

local function buffer(lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, lines or { 'before café after', 'second line' })
  return buf
end
local range = { start = { 0, 7 }, ['end'] = { 0, 12 } }
local function start(buf, selected)
  vim.api.nvim_set_current_buf(buf)
  local handle = plugin.edit('replace selection', { range = selected or range })
  return handle, calls[#calls]
end
local function proposal(call, replacement)
  local doc = call.request.document
  return { id = call.request.id, uri = doc.uri, revision = doc.revision,
    content_hash = doc.content_hash, range = vim.deepcopy(doc.range), replacement = replacement or 'tea' }
end
local function drain() vim.wait(20, function() return false end) end
local function respond(call, value) call.respond(value or proposal(call)); drain() end
local function expect(handle, state)
  local actual, err = handle.status()
  assert(actual == state, ('expected %s, got %s: %s'):format(state, actual, tostring(err)))
end

local buf = buffer()
local original = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
local handle, call = start(buf)
assert(call.request.document.text == 'before café after\nsecond line\n')
assert(call.request.document.revision == vim.api.nvim_buf_get_changedtick(buf))
assert(call.request.document.content_hash == vim.fn.sha256(call.request.document.text))
respond(call)
expect(handle, 'preview')
assert(vim.deep_equal(original, vim.api.nvim_buf_get_lines(buf, 0, -1, true)))
assert(vim.bo[vim.api.nvim_get_current_buf()].buftype == 'nofile')
assert(not vim.bo[vim.api.nvim_get_current_buf()].modifiable)
assert(handle.accept())
expect(handle, 'accepted')
assert(select(2, handle.status()) == nil, 'successful acceptance retained an error')
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, true)[1] == 'before tea after')
assert(vim.bo[buf].modified, 'accept must not save')
vim.api.nvim_set_current_buf(buf)
vim.cmd('undo')
assert(vim.deep_equal(original, vim.api.nvim_buf_get_lines(buf, 0, -1, true)), 'one undo restores source')
vim.cmd('redo')
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, true)[1] == 'before tea after')
assert(not handle.accept(), 'cannot apply twice')

-- Changes both before delivery and after preview invalidate the request.
for _, after_preview in ipairs({ false, true }) do
  buf = buffer()
  handle, call = start(buf)
  if after_preview then respond(call) end
  vim.api.nvim_buf_set_text(buf, 1, 0, 1, 0, { 'new ' })
  if after_preview then assert(not handle.accept()) else respond(call) end
  expect(handle, 'failed')
  assert(vim.api.nvim_buf_get_lines(buf, 0, 1, true)[1] == original[1])
end

-- Cancellation, duplicate callbacks, supersession, and rejection never apply source edits.
buf = buffer()
handle, call = start(buf)
local previous_count = cancel_count
assert(handle.cancel())
assert(not handle.cancel())
assert(cancel_count == previous_count + 1)
respond(call)
expect(handle, 'cancelled')
local old, old_call = start(buf)
handle, call = start(buf)
expect(old, 'cancelled')
respond(old_call)
respond(call)
call.respond(proposal(call, 'unexpected'))
drain()
expect(handle, 'preview')
assert(handle.reject())
assert(vim.deep_equal(original, vim.api.nvim_buf_get_lines(buf, 0, -1, true)))
handle, call = start(buf)
respond(call)
vim.api.nvim_buf_delete(vim.api.nvim_get_current_buf(), { force = true })
expect(handle, 'cancelled')

-- Malformed/foreign/out-of-bounds proposals cannot enter preview.
local corruptions = {
  function(p) p.id = 'wrong' end,
  function(p) p.uri = 'wrong' end,
  function(p) p.revision = -1 end,
  function(p) p.content_hash = 'wrong' end,
  function(p) p.range = nil end,
  function(p) p.range.start = nil end,
  function(p) p.range.start[2] = 11 end, -- inside é
  function(p) p.range['end'][1] = 99 end,
  function(p) p.range.start[2] = 0 end, -- valid but outside selection
  function(p) p.replacement = {} end,
  function(p) p.replacement = 'bad\0text' end,
}
for _, corrupt in ipairs(corruptions) do
  buf = buffer()
  handle, call = start(buf)
  local p = proposal(call)
  corrupt(p)
  respond(call, p)
  expect(handle, 'failed')
end
buf = buffer()
handle, call = start(buf)
respond(call, 'not a proposal')
expect(handle, 'failed')
handle, call = start(buf)
call.respond(nil, 'backend failed')
drain()
expect(handle, 'failed')

-- Unload and end-of-line option changes also invalidate captured content.
for _, invalidate in ipairs({
  function(b) vim.api.nvim_buf_delete(b, { force = true }) end,
  function(b) vim.bo[b].endofline = not vim.bo[b].endofline end,
  function(b) vim.api.nvim_buf_set_name(b, vim.fn.tempname()) end,
}) do
  buf = buffer()
  handle, call = start(buf)
  invalidate(buf)
  respond(call)
  expect(handle, vim.api.nvim_buf_is_loaded(buf) and 'failed' or 'cancelled')
end

-- Empty replacements and multiline insertions use exactly the requested byte range.
buf = buffer()
handle, call = start(buf)
respond(call, proposal(call, ''))
assert(handle.accept())
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, true)[1] == 'before  after')
buf = buffer({ 'ab' })
handle, call = start(buf, { start = { 0, 1 }, ['end'] = { 0, 1 } })
respond(call, proposal(call, 'X\nY'))
assert(handle.accept())
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, true), { 'aX', 'Yb' }))

-- Invalid ranges are rejected before dispatch.
buf = buffer()
local count = #calls
assert(not pcall(start, buf, { start = { 0, 11 }, ['end'] = { 0, 12 } }))
assert(not pcall(start, buf, { start = { 1, 0 }, ['end'] = { 0, 0 } }))
assert(#calls == count)

-- Visual selection conversion, including multibyte endpoints and reverse selection.
local function keys(text)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(text, true, false, true), 'nx', false)
end
buf = buffer({ 'aéb', 'last' })
vim.o.selection = 'inclusive'
keys('gg0vl')
assert(vim.deep_equal(snapshot.visual(buf), { start = { 0, 0 }, ['end'] = { 0, 3 } }))
keys('<Esc>gg0lvh')
assert(vim.deep_equal(snapshot.visual(buf), { start = { 0, 0 }, ['end'] = { 0, 3 } }))
vim.o.selection = 'exclusive'
keys('<Esc>gg0vl')
assert(vim.deep_equal(snapshot.visual(buf), { start = { 0, 0 }, ['end'] = { 0, 1 } }))
keys('<Esc>gg0lvh')
assert(vim.deep_equal(snapshot.visual(buf), { start = { 0, 0 }, ['end'] = { 0, 1 } }))
keys('<Esc>ggV')
assert(vim.deep_equal(snapshot.visual(buf), { start = { 0, 0 }, ['end'] = { 1, 0 } }))
keys('<Esc>GV')
assert(vim.deep_equal(snapshot.visual(buf), { start = { 1, 0 }, ['end'] = { 1, 4 } }))
keys('<Esc>gg<C-v>')
assert(not pcall(snapshot.visual, buf))
keys('<Esc>')
vim.o.selection = 'inclusive'

-- Visual-line replacement uses the same whole-line semantics as Ex commands.
keys('ggV')
handle = plugin.edit('replace whole line')
call = calls[#calls]
assert(call.request.document.selection == 'line')
respond(call, proposal(call, 'whole line'))
assert(handle.accept())
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, true), { 'whole line', 'last' }))
vim.api.nvim_set_current_buf(buf)
vim.cmd('undo')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, true), { 'aéb', 'last' }))
assert(not pcall(plugin.edit, 'bad bounds', {
  range = { start = { 0, 0 }, ['end'] = { 0, 1 } }, linewise = { first = 0, last = 1 },
}))

-- Capture before leaving visual mode; the request must retain the exact selection.
keys('gg0vl')
handle = plugin.edit('visual edit')
call = calls[#calls]
assert(vim.deep_equal(call.request.document.range, { start = { 0, 0 }, ['end'] = { 0, 3 } }))
assert(vim.fn.mode() == 'n')
respond(call)
assert(handle.accept())
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, true)[1] == 'teab')

-- Concurrent source buffers have independent lifecycles.
local first = buffer()
local first_handle, first_call = start(first)
local second = buffer()
local second_handle, second_call = start(second)
first_handle.cancel()
respond(first_call)
respond(second_call)
expect(first_handle, 'cancelled')
expect(second_handle, 'preview')
assert(second_handle.accept())
assert(vim.api.nvim_buf_get_lines(first, 0, 1, true)[1] == original[1])
assert(vim.api.nvim_buf_get_lines(second, 0, 1, true)[1] == 'before tea after')

-- No-op restoration still changes revision; read-only proposals fail on acceptance.
buf = buffer()
handle, call = start(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, true, { 'temporary' })
vim.api.nvim_buf_set_lines(buf, 0, -1, true, original)
respond(call)
expect(handle, 'failed')
handle, call = start(buf)
respond(call)
vim.bo[buf].modifiable = false
assert(not handle.accept())
expect(handle, 'failed')
vim.bo[buf].modifiable = true

-- Root and canonical content come from the originating document, not global cwd.
local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/.git', 'p')
vim.fn.mkdir(directory .. '/src', 'p')
buf = buffer({ 'unsaved' })
vim.api.nvim_buf_set_name(buf, directory .. '/src/example.ts')
vim.bo[buf].endofline = false
local captured = snapshot.capture(buf, { start = { 0, 0 }, ['end'] = { 0, 7 } })
assert(vim.uv.fs_realpath(captured.workspace_root) == vim.uv.fs_realpath(directory), captured.workspace_root)
assert(captured.document.text == 'unsaved')
assert(captured.document.content_hash == vim.fn.sha256('unsaved'))
assert(vim.fn.filereadable(directory .. '/src/example.ts') == 0)
vim.fn.delete(directory, 'rf')

-- A synchronous adapter exception is contained.
plugin.register_adapter('throws', { capabilities = { edit = true }, request = function() error('failure') end })
plugin.setup({ harness = 'throws' })
expect(plugin.edit('test', { range = { start = { 0, 0 }, ['end'] = { 0, 1 } } }), 'failed')
plugin.register_adapter('demo', require('73.adapters.fake').new('demo'))
plugin.setup({ harness = 'demo' })
handle = plugin.edit('test', { range = { start = { 0, 0 }, ['end'] = { 0, 1 } } })
drain()
expect(handle, 'preview')
handle.reject()
plugin.setup({})
print('73 safe editing checks passed')
