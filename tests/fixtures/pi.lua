-- Fake executable: no model, credentials, network, or source-file access.
local scenario = arg[1]
if scenario == 'child' then
  vim.fn.writefile({ tostring(vim.fn.getpid()) }, arg[2])
  while true do vim.uv.sleep(100) end
end
for _, value in ipairs(arg) do
  if value == '--version' then
    io.write(scenario == 'version' and '9.9.9\n' or '1.5.0\n')
    io.flush()
    vim.cmd('qa!')
    return
  end
end
vim.fn.writefile({ tostring(vim.fn.getpid()) }, arg[2])
local seen = {}
for _, value in ipairs(arg) do seen[value] = true end
for _, flag in ipairs({ '--no-tools', '--no-extensions', '--no-mcp', '--no-session', '--no-approve', '--offline',
  '--no-context-files', '--no-skills', '--no-themes', '--no-prompt-templates', '--system-prompt' }) do
  assert(seen[flag], 'missing restriction: ' .. flag)
end
local prompt = vim.json.decode(io.read('*l'))
assert(prompt.type == 'prompt')
local request = vim.json.decode(prompt.message)
assert(request.document.text == 'unsaved café\n')
assert(request.instruction == 'literal $(touch forbidden) `echo nope`\nnext line')
local function emit(event)
  local text = vim.json.encode(event) .. '\r\n'
  -- Deliberately break frames and UTF-8 strings into tiny byte chunks.
  for i = 1, #text, 3 do io.write(text:sub(i, i + 2)); io.flush() end
end
if scenario == 'tree' then
  local child = vim.uv.spawn(vim.v.progpath, {
    args = { '--headless', '-u', 'NONE', '-i', 'NONE', '-l', arg[0], 'child', arg[2] .. '.child' },
    detached = false,
  }, function() end)
  assert(child)
  while true do vim.uv.sleep(100) end
elseif scenario == 'hang' then
  while true do vim.uv.sleep(100) end
elseif scenario == 'exit' then
  vim.cmd('qa!'); return
elseif scenario == 'malformed' then
  io.write('not json\n'); io.flush()
elseif scenario == 'truncated' then
  io.write('{"type":'); io.flush(); vim.cmd('qa!'); return
elseif scenario == 'limit' then
  io.write(string.rep('x', 10000)); io.flush()
else
  emit({ type = 'response', command = 'prompt', id = scenario == 'identity' and 'wrong' or prompt.id,
    success = scenario ~= 'rejected', error = 'fixture rejection', data = { disposition = 'started' } })
  emit({ type = 'agent_start' })
  if scenario == 'tool' then emit({ type = 'tool_execution_start' }) end
  local field = request.operation == 'ask' and 'answer' or 'replacement'
  local payload = { [field] = scenario == 'empty' and '' or 'new café\nline\226\128\168separator' }
  if scenario == 'payload' then payload.extra = 'bad' end
  local message = { role = 'assistant', stopReason = scenario == 'provider' and 'error' or 'stop',
    content = { { type = 'text', text = vim.json.encode(payload) } } }
  emit({ type = 'message_end', message = message })
  emit({ type = 'agent_end', willRetry = scenario == 'retry' })
  if scenario == 'retry' then
    emit({ type = 'agent_start' })
    message.content[1].text = vim.json.encode({ [field] = 'retry result' })
    emit({ type = 'message_end', message = message })
  end
  if scenario == 'no_settle' then vim.cmd('qa!'); return end
  emit({ type = 'agent_settled', aborted = scenario == 'aborted' })
end
-- Ignore shutdown to exercise bounded process-group cleanup.
while true do vim.uv.sleep(100) end
