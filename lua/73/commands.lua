local M = {}

-- Ex ranges are whole lines. Characterwise selections use the Lua visual API.
local function line_range(first, last)
  local count = vim.api.nvim_buf_line_count(0)
  assert(first >= 1 and last >= first and last <= count, '73: invalid line range')
  local finish = last < count and { last, 0 }
    or { last - 1, #vim.api.nvim_buf_get_lines(0, last - 1, last, true)[1] }
  return { start = { first - 1, 0 }, ['end'] = finish }
end

function M.register()
  for _, operation in ipairs({ 'ask', 'edit', 'insert' }) do
    local name = 'SeventyThree' .. operation:sub(1, 1):upper() .. operation:sub(2)
    local options = { nargs = '*', desc = '73 ' .. operation .. ' with an optional instruction' }
    if operation ~= 'insert' then options.range = true end
    vim.api.nvim_create_user_command(name, function(command)
      local ok, problem = pcall(function()
        local opts
        if operation == 'edit' or command.range > 0 then
          opts = { range = line_range(command.line1, command.line2),
            linewise = { first = command.line1 - 1, last = command.line2 } }
        end
        local instruction = command.args:match('%S') and command.args or nil
        return require('73')[operation](instruction, opts)
      end)
      if not ok then
        local message = tostring(problem):gsub('^.-:%d+: ', '')
        vim.notify(message, vim.log.levels.WARN, { title = '73' })
      end
    end, options)
  end
end

return M
