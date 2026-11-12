-- Buffer-local status survives completion without retaining prompts or snapshots.
local M = {}
local namespace = vim.api.nvim_create_namespace('73-progress')
local latest = {}

function M.update(buf, id, operation, state, message, row)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  latest[buf] = { id = id, operation = operation, state = state, message = message }
  if not vim.api.nvim_buf_is_loaded(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, namespace, 0, -1)
  if state == 'pending' or state == 'prompting' or state == 'ready' then
    row = math.min(row, vim.api.nvim_buf_line_count(buf) - 1)
    local label = state == 'pending' and 'working' or 'waiting for instruction'
    if state == 'ready' then label = 'result ready' end
    local command = state == 'ready' and ':SeventyThreeShow' or ':SeventyThreeCancel'
    local mark = vim.api.nvim_buf_set_extmark(buf, namespace, row, 0, {
      virt_text = { { '73 ' .. operation .. ': ' .. label .. '  (' .. command .. ')', 'Comment' } },
      virt_text_pos = 'eol',
    })
    if state == 'pending' then
      local token, started, frame = latest[buf], vim.uv.hrtime(), 0
      local function tick()
        if latest[buf] ~= token or not vim.api.nvim_buf_is_loaded(buf) then return end
        frame = frame + 1
        local symbols = { '|', '/', '-', '\\' }
        local seconds = math.floor((vim.uv.hrtime() - started) / 1e9)
        local line = math.min(row, vim.api.nvim_buf_line_count(buf) - 1)
        pcall(vim.api.nvim_buf_set_extmark, buf, namespace, line, 0, {
          id = mark, virt_text_pos = 'eol',
          virt_text = { { ('73 %s %s working %ds (:SeventyThreeCancel)'):format(
            operation, symbols[frame % #symbols + 1], seconds), 'DiagnosticInfo' } },
        })
        vim.defer_fn(tick, 150)
      end
      vim.defer_fn(tick, 150)
    end
  end
  if state == 'failed' then
    local summary = tostring(message):gsub('^.-:%d+: ', ''):gsub('^73: ', ''):gsub('[\r\n]', ' ')
    pcall(vim.notify, ('73 %s failed: %s'):format(operation, summary:sub(1, 500)), vim.log.levels.WARN,
      { title = '73' })
  end
end

function M.status(buf)
  return latest[buf] and vim.deepcopy(latest[buf]) or nil
end

vim.api.nvim_create_autocmd('BufWipeout', { callback = function(event) latest[event.buf] = nil end })
return M
