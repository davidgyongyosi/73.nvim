local snapshot = require('73.snapshot')
local preview = require('73.preview')
local progress = require('73.progress')
local M = {}
local next_id = 0
local active = {}
local running = {}

local function source_buffer()
  local buf = vim.api.nvim_get_current_buf()
  return vim.b[buf].seventythree_source or buf
end

function M.status()
  return progress.status(source_buffer())
end

function M.cancel()
  local handle = active[source_buffer()]
  return handle and handle.cancel() or false
end

function M.cancel_all()
  local handles = {}
  for _, group in pairs(running) do for handle in pairs(group) do handles[#handles + 1] = handle end end
  for _, handle in ipairs(handles) do handle.cancel() end
  return #handles
end

function M.show()
  local handle = active[source_buffer()]
  if not handle then return false, '73: no result to show in this buffer' end
  return handle.show()
end

function M.start(operation, adapter, instruction, opts)
  opts = opts or {}
  assert(opts.auto_apply == nil or type(opts.auto_apply) == 'boolean', '73: auto_apply must be boolean')
  assert(opts.parallel == nil or type(opts.parallel) == 'boolean', '73: parallel must be boolean')
  assert(operation == 'ask' or operation == 'edit' or operation == 'insert', '73: invalid operation')
  assert(instruction == nil or (type(instruction) == 'string' and instruction:match('%S')),
    '73: instruction is required')
  assert(adapter and adapter.capabilities[operation] == true and type(adapter.request) == 'function',
    '73: selected harness has no ' .. operation .. ' implementation')
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  assert(buf == vim.api.nvim_get_current_buf(), '73: edits must originate in the current buffer')
  local range = opts.range
  local linewise = opts.linewise
  if not range then
    local mode = vim.fn.mode()
    if operation == 'edit' or (operation == 'ask' and (mode == 'v' or mode == 'V' or mode == '\22')) then
      range, linewise = snapshot.visual(buf)
    else
      local cursor = vim.api.nvim_win_get_cursor(0)
      local point = { cursor[1] - 1, cursor[2] }
      range = { start = point, ['end'] = vim.deepcopy(point) }
    end
  end
  local origin_window = vim.api.nvim_get_current_win()
  assert(operation ~= 'insert' or not linewise, '73: insertion cannot use a linewise range')
  local captured = snapshot.capture(buf, range, linewise)
  if operation == 'insert' then
    assert(vim.deep_equal(range.start, range['end']), '73: insertion requires an empty range')
  end
  if vim.fn.mode() == 'v' or vim.fn.mode() == 'V' then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
  end
  if active[buf] and not opts.parallel then
    for handle in pairs(running[buf] or {}) do handle.cancel() end
  end
  next_id = next_id + 1
  local request = {
    protocol = '73/0', id = tostring(next_id), operation = operation, instruction = instruction,
    document = vim.deepcopy(captured.document), workspace_root = captured.workspace_root, context = {},
  }
  local state, message, proposal, view, cancel_transport = instruction and 'pending' or 'prompting', nil, nil, nil, nil
  local handle = {}
  local cleanup_id
  local function report()
    progress.update(buf, request.id, operation, state, message, captured.document.cursor[1])
  end
  handle.report = report
  local function finish(status, err)
    state, message = status, err
    if running[buf] then running[buf][handle] = nil end
    if active[buf] == handle then active[buf] = next(running[buf] or {}) end
    local old_view = view
    view = nil
    preview.close(old_view)
    if cleanup_id then pcall(vim.api.nvim_del_autocmd, cleanup_id); cleanup_id = nil end
    report()
    if active[buf] and active[buf] ~= handle then active[buf].report() end
  end
  function handle.status() return state, message end
  function handle.cancel()
    if state ~= 'prompting' and state ~= 'pending' and state ~= 'preview' and state ~= 'answered' and state ~= 'ready' then return false end
    finish('cancelled')
    if cancel_transport then pcall(cancel_transport) end
    return true
  end
  handle.reject = handle.cancel
  function handle.close()
    if state ~= 'answered' then return handle.cancel() end
    finish('closed')
    return true
  end
  function handle.accept()
    if state ~= 'preview' and not (state == 'ready' and opts.auto_apply and operation ~= 'ask') then
      return false, '73: no proposal ready'
    end
    if not snapshot.fresh(captured) then
      finish('failed', '73: buffer changed; request a new proposal')
      return false, message
    end
    if not vim.bo[buf].modifiable then
      finish('failed', '73: buffer is not modifiable')
      return false, message
    end
    local before = captured
    local range = captured.document.range
    local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
      -- Close the previous undo block without clearing its history.
      vim.cmd('let &l:undolevels = &l:undolevels')
      local replacement = vim.split(proposal.replacement, '\n', { plain = true })
      if captured.linewise then
        -- A final LF terminates the last supplied line; it does not add a blank line.
        if replacement[#replacement] == '' then table.remove(replacement) end
        vim.api.nvim_buf_set_lines(buf, captured.linewise.first, captured.linewise.last, true, replacement)
      else
        vim.api.nvim_buf_set_text(buf, range.start[1], range.start[2], range['end'][1], range['end'][2], replacement)
      end
    end)
    if ok then
      for other in pairs(running[buf] or {}) do
        if other ~= handle then other.rebase(before) end
      end
    end
    finish(ok and 'accepted' or 'failed', not ok and tostring(err) or nil)
    return ok, message
  end
  function handle.show()
    if source_buffer() ~= buf or vim.fn.mode(1) ~= 'n' then
      return false, '73: return to the source buffer in normal mode to view this result'
    end
    if view and not view.closed and vim.api.nvim_win_is_valid(view.win) then
      vim.api.nvim_set_current_win(view.win)
      return true
    end
    if state ~= 'ready' then return false, '73: no result ready' end
    if not snapshot.fresh(captured) then
      finish('failed', '73: buffer changed; request a new result')
      return false, message
    end
    local opened, result
    if operation == 'ask' then
      state = 'answered'
      opened, result = pcall(preview.answer, proposal.answer, handle.close)
    else
      state = 'preview'
      local range = captured.document.range
      local before = table.concat(vim.api.nvim_buf_get_text(buf, range.start[1], range.start[2],
        range['end'][1], range['end'][2], {}), '\n')
      opened, result = pcall(preview.open, before, proposal.replacement, handle.accept, handle.reject)
    end
    if opened then
      view = result
      vim.b[view.buf].seventythree_source = buf
      report()
      return true
    end
    finish('failed', tostring(result))
    return false, message
  end
  function handle.rebase(before)
    if not vim.deep_equal(captured.lines, before.lines)
      or captured.document.revision ~= before.document.revision then
      handle.cancel(); return
    end
    local old = table.concat(before.lines, '\n')
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
    local new = table.concat(lines, '\n')
    local first, tail = 0, 0
    while first < #old and first < #new and old:byte(first + 1) == new:byte(first + 1) do first = first + 1 end
    while tail < #old - first and tail < #new - first
      and old:byte(#old - tail) == new:byte(#new - tail) do tail = tail + 1 end
    local function offset(point)
      local result = point[2]
      for i = 1, point[1] do result = result + #before.lines[i] + 1 end
      return result
    end
    local range = captured.document.range
    local a, b = offset(range.start), offset(range['end'])
    local delta = #new - #old
    local shifted = false
    if a >= #old - tail then a, b, shifted = a + delta, b + delta, true
    elseif b > first then handle.cancel(); return end
    local function point(value)
      for i, line in ipairs(lines) do
        if value <= #line then return { i - 1, value } end
        value = value - #line - 1
      end
      return { #lines - 1, #lines[#lines] }
    end
    local updated = { start = point(a), ['end'] = point(b) }
    local linewise = vim.deepcopy(captured.linewise)
    if linewise and shifted then
      local rows = #lines - #before.lines
      linewise.first, linewise.last = linewise.first + rows, linewise.last + rows
    end
    local ok, result = pcall(snapshot.capture, buf, updated, linewise)
    if ok then captured = result else handle.cancel() end
  end
  running[buf] = running[buf] or {}
  running[buf][handle] = true
  active[buf] = handle
  cleanup_id = vim.api.nvim_create_autocmd('BufUnload', { buffer = buf, once = true, callback = function()
    handle.cancel()
  end })
  report()
  local delivered = false
  local function respond(response, err)
    -- Marshal callbacks out of fast events, and never expose mutable editor state to an adapter.
    if delivered or state ~= 'pending' then return end
    delivered = true
    local copy = type(response) == 'table' and vim.deepcopy(response) or response
    vim.schedule(function()
      if state ~= 'pending' then return end
      if err then finish('failed', tostring(err)); return end
      local ok, validation = pcall(function()
        assert(snapshot.fresh(captured), '73: stale snapshot')
        assert(type(copy) == 'table', '73: malformed proposal')
        assert(copy.id == request.id and copy.uri == request.document.uri
          and copy.revision == request.document.revision
          and copy.content_hash == request.document.content_hash, '73: proposal identity mismatch')
        if operation == 'ask' then
          assert(type(copy.answer) == 'string' and not copy.answer:find('\0', 1, true), '73: invalid answer')
          require('73.text').validate(copy.answer)
          assert(copy.replacement == nil, '73: questions cannot return edits')
          return
        end
        snapshot.validate_range(vim.split(request.document.text, '\n', { plain = true }), copy.range)
        assert(vim.deep_equal(copy.range, request.document.range), '73: proposal exceeds requested selection')
        assert(type(copy.replacement) == 'string' and not copy.replacement:find('\0', 1, true),
          '73: invalid replacement text')
        require('73.text').validate(copy.replacement)
      end)
      if not ok then finish('failed', tostring(validation)); return end
      proposal, state = copy, 'ready'
      report()
      if opts.auto_apply and operation ~= 'ask' then handle.accept(); return end
      local cursor = vim.api.nvim_win_get_cursor(0)
      if tonumber(request.id) == next_id and vim.api.nvim_get_current_win() == origin_window
        and vim.api.nvim_get_current_buf() == buf and vim.fn.mode(1) == 'n'
        and cursor[1] - 1 == captured.document.cursor[1] and cursor[2] == captured.document.cursor[2] then
        handle.show()
      end
    end)
  end
  local function dispatch(text)
    if state ~= 'pending' and state ~= 'prompting' then return end
    if text == nil or not text:match('%S') then handle.cancel(); return end
    if not snapshot.fresh(captured) then finish('failed', '73: stale snapshot'); return end
    request.instruction, state = text, 'pending'
    report()
    local ok, result = pcall(adapter.request, vim.deepcopy(request), respond)
    if not ok then
      finish('failed', tostring(result))
    elseif type(result) == 'function' then
      cancel_transport = result
      if state == 'cancelled' then pcall(cancel_transport) end
    end
  end
  if instruction then
    dispatch(instruction)
  else
    local ok, err = pcall(vim.ui.input, { prompt = '73 ' .. operation .. ': ' }, function(text)
      -- UI providers may invoke their callback from a fast event.
      vim.schedule(function()
        if state == 'prompting' then dispatch(text) end
      end)
    end)
    if not ok then finish('failed', tostring(err)) end
  end
  return handle
end

return M
