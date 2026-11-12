local plugin = require('73')
local calls, messages = {}, {}
local original_notify = vim.notify
vim.notify = function(message) messages[#messages + 1] = message end
plugin.register_adapter('command_fixture', {
  capabilities = { ask = true, edit = true, insert = true },
  request = function(request, respond) calls[#calls + 1] = { request = request, respond = respond } end,
})
plugin.setup({ harness = 'command_fixture' })
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, true, { 'first', 'café', 'last' })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd('SeventyThreeAsk Explain this')
assert(calls[#calls].request.operation == 'ask')
assert(calls[#calls].request.instruction == 'Explain this')
assert(vim.deep_equal(calls[#calls].request.document.range, { start = { 1, 0 }, ['end'] = { 1, 0 } }))
plugin.cancel()
vim.cmd('1,2SeventyThreeAsk Explain these lines')
assert(vim.deep_equal(calls[#calls].request.document.range, { start = { 0, 0 }, ['end'] = { 2, 0 } }))
plugin.cancel()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd('SeventyThreeEdit Replace this line')
assert(calls[#calls].request.operation == 'edit')
assert(vim.deep_equal(calls[#calls].request.document.range, { start = { 1, 0 }, ['end'] = { 2, 0 } }))
plugin.cancel()
vim.cmd('2,3SeventyThreeEdit Replace the end')
assert(vim.deep_equal(calls[#calls].request.document.range, { start = { 1, 0 }, ['end'] = { 2, 4 } }))
plugin.cancel()
vim.api.nvim_win_set_cursor(0, { 2, 3 }) -- byte position before é
vim.cmd('SeventyThreeInsert A new comment')
assert(calls[#calls].request.operation == 'insert')
assert(vim.deep_equal(calls[#calls].request.document.range, { start = { 1, 3 }, ['end'] = { 1, 3 } }))
plugin.cancel()

-- Whole-line replacements preserve surrounding lines, including deletion at EOF.
local function complete_edit(instruction, replacement)
  vim.cmd(instruction)
  local call = calls[#calls]
  local doc = call.request.document
  assert(doc.selection == 'line')
  call.respond({ id = call.request.id, uri = doc.uri, revision = doc.revision,
    content_hash = doc.content_hash, range = doc.range, replacement = replacement })
  vim.wait(20, function() return false end)
  local preview = vim.api.nvim_get_current_buf()
  assert(vim.b[preview].seventythree_source == buf)
  local accept = vim.fn.maparg('a', 'n', false, true).callback
  accept()
  vim.api.nvim_set_current_buf(buf)
end
for _, replacement in ipairs({ 'changed', 'changed\n' }) do
  vim.api.nvim_buf_set_lines(buf, 0, -1, true, { 'first', 'café', 'last' })
  complete_edit('2SeventyThreeEdit Replace', replacement)
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, true), { 'first', 'changed', 'last' }))
  vim.cmd('undo')
  assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, true), { 'first', 'café', 'last' }))
end
complete_edit('3SeventyThreeEdit Delete', '')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, true), { 'first', 'café' }))
vim.cmd('undo')
vim.api.nvim_buf_set_lines(buf, 0, -1, true, { 'first', '' })
complete_edit('2SeventyThreeEdit Replace empty final line', 'end')
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, true), { 'first', 'end' }))
vim.api.nvim_buf_set_lines(buf, 0, -1, true, { 'first', 'café', 'last' })

-- A bar in an instruction is data, not another Ex command.
vim.g.seventythree_command_injection = false
vim.cmd('SeventyThreeAsk preserve | let g:seventythree_command_injection = v:true')
assert(vim.g.seventythree_command_injection == false)
assert(calls[#calls].request.instruction == 'preserve | let g:seventythree_command_injection = v:true')
plugin.cancel()

-- Prompt entry captures the Ex range before the input UI changes focus/cursor.
local original_input, prompt = vim.ui.input, nil
vim.ui.input = function(_, callback) prompt = callback end
vim.cmd('1,2SeventyThreeEdit')
assert(plugin.request_status().state == 'prompting')
vim.api.nvim_win_set_cursor(0, { 3, 0 })
prompt('Use this range')
vim.wait(20, function() return false end)
assert(vim.deep_equal(calls[#calls].request.document.range, { start = { 0, 0 }, ['end'] = { 2, 0 } }))
plugin.cancel()
vim.ui.input = original_input
plugin.setup({})
local count = #messages
vim.cmd('SeventyThreeAsk missing harness')
assert(#messages == count + 1 and messages[#messages]:find('no ask implementation'))
vim.notify = original_notify

-- Health distinguishes metadata registration from implemented callbacks without launching a process.
local health = {}
local original_health = {}
for _, method in ipairs({ 'start', 'ok', 'info', 'warn', 'error' }) do
  original_health[method] = vim.health[method]
  vim.health[method] = function(text) health[#health + 1] = { method = method, text = text } end
end
local function contains(level, fragment)
  for _, record in ipairs(health) do
    if record.method == level and record.text:find(fragment, 1, true) then return true end
  end
  return false
end
plugin.setup({ harness = 'fixture_harness' })
require('73.health').check()
assert(contains('warn', 'metadata only'))
plugin.setup({ harness = 'demo' })
require('73.health').check()
assert(contains('warn', 'fake development adapter'))
local missing = vim.fn.tempname() .. '/no-pi'
plugin.register_adapter('pi_missing_health', require('73.adapters.pi').new({ executable = missing }))
plugin.setup({ harness = 'pi_missing_health' })
local original_system = vim.system
vim.system = function() error('health checks must not execute providers') end
require('73.health').check()
vim.system = original_system
assert(contains('error', 'Pi executable not found: ' .. missing))
assert(contains('ok', 'local callbacks available for ask, edit, insert'))
local status = plugin.status()
assert(status.selected.harness.implemented.edit == true)
status.selected.harness.implemented.edit = false
status.selected.harness.metadata.executable = 'mutated'
assert(plugin.status().selected.harness.implemented.edit == true)
assert(plugin.status().selected.harness.metadata.executable == missing)
for method, callback in pairs(original_health) do vim.health[method] = callback end
plugin.setup({})
print('73 public command and health checks passed')
