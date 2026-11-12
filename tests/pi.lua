local pi = require('73.adapters.pi')
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local fixture = vim.fn.getcwd() .. '/tests/fixtures/pi.lua'
local pidfiles = {}
local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
local function adapter(scenario, options)
  local path = directory .. '/fake-pi-' .. scenario
  local pidfile = directory .. '/pid-' .. (#pidfiles + 1)
  pidfiles[#pidfiles + 1] = pidfile
  vim.fn.writefile({ '#!/bin/sh', 'exec ' .. quote(vim.v.progpath)
    .. ' --headless -u NONE -i NONE -l ' .. quote(fixture) .. ' ' .. quote(scenario)
    .. ' ' .. quote(pidfile) .. ' "$@"' }, path)
  assert(vim.uv.fs_chmod(path, 493))
  options = options or {}
  options.executable, options.shutdown_ms = path, 30
  options.timeout_ms = options.timeout_ms or 3000
  return pi.new(options)
end
local function request(operation)
  return { id = 'fixture-1', operation = operation or 'edit', workspace_root = directory,
    instruction = 'literal $(touch forbidden) `echo nope`\nnext line',
    document = { text = 'unsaved café\n', uri = 'untitled:test', revision = 7, content_hash = 'identity',
      range = { start = { 0, 0 }, ['end'] = { 0, 0 } } } }
end
local function run(scenario, operation, options)
  local count, response, problem = 0, nil, nil
  adapter(scenario, options).request(request(operation), function(value, err)
    count, response, problem = count + 1, value, err
  end)
  assert(vim.wait(5000, function() return count > 0 end, 5), 'no callback: ' .. scenario)
  vim.wait(80, function() return false end, 5)
  assert(count == 1, 'duplicate completion')
  return response, problem
end
for _, operation in ipairs({ 'ask', 'edit', 'insert' }) do
  local response, err = run('success', operation)
  assert(response, tostring(err))
  local field = operation == 'ask' and 'answer' or 'replacement'
  assert(response[field] == 'new café\nline\226\128\168separator')
  assert(response.id == 'fixture-1' and response.content_hash == 'identity')
  if operation ~= 'ask' then assert(vim.deep_equal(response.range, request().document.range)) end
end
assert(run('empty').replacement == '')
assert(run('retry').replacement == 'retry result')
for _, scenario in ipairs({ 'version', 'exit', 'malformed', 'truncated', 'identity', 'rejected', 'tool',
  'payload', 'provider', 'aborted', 'no_settle' }) do
  local response, err = run(scenario)
  assert(not response and type(err) == 'string', 'expected failure: ' .. scenario)
end
local response, err = run('limit', nil, { max_output_bytes = 2000 })
assert(not response and err:find('limit'))
response, err = run('hang', nil, { timeout_ms = 200 })
assert(not response and err:find('timed out'))
local tree_adapter = adapter('tree', { timeout_ms = 10000 })
local tree_callbacks = 0
local cancel_tree = tree_adapter.request(request(), function() tree_callbacks = tree_callbacks + 1 end)
local childfile = pidfiles[#pidfiles] .. '.child'
-- Wait for actual startup instead of racing a short deadline on slower editors/runners.
assert(vim.wait(8000, function() return vim.fn.filereadable(childfile) == 1 end, 10), 'child fixture did not start')
cancel_tree()
vim.wait(80, function() return false end)
assert(tree_callbacks == 0, 'cancelled process tree responded')
pidfiles[#pidfiles + 1] = childfile
local count = 0
local cancel = adapter('hang').request(request(), function() count = count + 1 end)
vim.wait(100, function() return false end)
cancel(); cancel()
vim.wait(100, function() return false end)
assert(count == 0, 'cancelled request delivered a callback')
local good_count = 0
local first = adapter('hang').request(request(), function() error('cancelled request responded') end)
adapter('success').request(request(), function(value, problem)
  assert(value, tostring(problem)); good_count = good_count + 1
end)
first()
assert(vim.wait(5000, function() return good_count == 1 end, 5))
vim.wait(80, function() return false end)
adapter('hang').request(request(), function() error('editor exit must not deliver a callback') end)
vim.wait(100, function() return false end)
vim.api.nvim_exec_autocmds('VimLeavePre', {})
vim.wait(80, function() return false end)
assert(not pcall(pi.new, { extra_args = { '--approve' } }))
assert(not pcall(pi.new, { model = '--tools' }))
assert(not pcall(pi.new, { timeout_ms = 0 }))
local missing
pi.new({ executable = directory .. '/missing' }).request(request(), function(_, problem) missing = problem end)
assert(missing and missing:find('could not start'))

-- Exercise the real transport through the editor-owned proposal/acceptance path.
local plugin = require('73')
plugin.register_adapter('pi_fixture', adapter('success'))
plugin.setup({ harness = 'pi_fixture' })
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, true, { 'unsaved café' })
local handle = plugin.insert(request().instruction)
assert(vim.wait(5000, function() return handle.status() ~= 'pending' end, 5))
local state, problem = handle.status()
assert(state == 'preview', tostring(problem))
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, true)[1] == 'unsaved café')
assert(handle.accept())
vim.api.nvim_set_current_buf(buf)
vim.cmd('undo')
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, true)[1] == 'unsaved café')
plugin.setup({})
assert(vim.fn.filereadable(directory .. '/forbidden') == 0)
for _, file in ipairs(pidfiles) do
  if vim.fn.filereadable(file) == 1 then
    local pid = tonumber(vim.fn.readfile(file)[1])
    assert(vim.wait(2000, function() return vim.uv.kill(pid, 0) == nil end, 10), 'fake process leaked: ' .. pid)
  end
end
vim.fn.delete(directory, 'rf')
print('73 Pi subprocess checks passed')
