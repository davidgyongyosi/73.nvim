local plugin = require('73')
local calls, notifications, cancelled = {}, {}, 0
local previous_notify = vim.notify
vim.notify = function(message, level) notifications[#notifications + 1] = { message = message, level = level } end
plugin.register_adapter('progress_fixture', {
  capabilities = { ask = true, insert = true },
  request = function(request, respond)
    calls[#calls + 1] = { request = request, respond = respond }
    return function() cancelled = cancelled + 1 end
  end,
})
plugin.setup({ harness = 'progress_fixture' })
local ns = vim.api.nvim_get_namespaces()['73-progress']
local function buffer()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, { 'unchanged' })
  return buf
end
local function marks(buf) return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) end
local function drain() vim.wait(20, function() return false end) end
local function reply(call)
  local doc = call.request.document
  call.respond({ id = call.request.id, uri = doc.uri, revision = doc.revision,
    content_hash = doc.content_hash, answer = 'An answer' })
  drain()
end
local buf = buffer()
local tick = vim.api.nvim_buf_get_changedtick(buf)
local handle = plugin.ask('test')
assert(plugin.request_status().state == 'pending')
assert(#marks(buf) == 1)
assert(vim.api.nvim_buf_get_changedtick(buf) == tick, 'progress mutated source')
local copied = plugin.request_status()
copied.state = 'corrupt'
assert(plugin.request_status().state == 'pending')
vim.cmd('SeventyThreeStatus')
assert(notifications[#notifications].message == '73 ask: pending')
vim.cmd('SeventyThreeCancel')
assert(handle.status() == 'cancelled' and cancelled == 1)
assert(#marks(buf) == 0)
local count = #notifications
reply(calls[#calls])
assert(#notifications == count and plugin.request_status().state == 'cancelled')

-- Errors are visible once, and the detailed status survives completion.
handle = plugin.ask('fail')
local call = calls[#calls]
call.respond(nil, 'backend unavailable')
drain()
assert(handle.status() == 'failed' and #marks(buf) == 0)
assert(notifications[#notifications].message == '73 ask failed: backend unavailable')
assert(notifications[#notifications].level == vim.log.levels.WARN)
count = #notifications
call.respond(nil, 'duplicate')
drain()
assert(#notifications == count)
assert(plugin.request_status().message == 'backend unavailable')

-- Preview commands resolve back to the source buffer.
handle = plugin.ask('answer')
reply(calls[#calls])
assert(vim.api.nvim_get_current_buf() ~= buf)
assert(plugin.request_status().state == 'answered')
assert(#marks(buf) == 0)
vim.cmd('SeventyThreeCancel')
assert(handle.status() == 'cancelled')

-- One buffer's cancellation cannot affect another; old callbacks do not replace newer status.
vim.api.nvim_set_current_buf(buf)
handle = plugin.ask('old')
local old = calls[#calls]
local newer = plugin.ask('new')
local other = buffer()
local other_handle = plugin.ask('other')
vim.cmd('SeventyThreeCancel')
assert(other_handle.status() == 'cancelled' and newer.status() == 'pending')
reply(old)
vim.api.nvim_set_current_buf(buf)
assert(plugin.request_status().id ~= old.request.id)
assert(plugin.request_status().state == 'pending')
newer.cancel()

-- Unloading immediately stops work, even when no response ever arrives.
buf = buffer()
handle = plugin.ask('unload')
local prior_cancelled = cancelled
vim.api.nvim_buf_delete(buf, { force = true })
assert(handle.status() == 'cancelled' and cancelled == prior_cancelled + 1)
assert(require('73.progress').status(buf) == nil)

-- Prompt progress is visible, source-neutral, and cancellable.
buf = buffer()
local input, callback = vim.ui.input, nil
vim.ui.input = function(_, cb) callback = cb end
handle = plugin.insert()
assert(plugin.request_status().state == 'prompting' and #marks(buf) == 1)
vim.cmd('SeventyThreeCancel')
local call_count = #calls
callback('too late')
drain()
assert(#calls == call_count and #marks(buf) == 0)
vim.ui.input = input
vim.notify = previous_notify
plugin.setup({})
print('73 progress and cancellation checks passed')
