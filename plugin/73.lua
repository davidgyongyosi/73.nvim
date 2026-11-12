if vim.g.loaded_73 then
  return
end
vim.g.loaded_73 = true
require('73.commands').register()
vim.api.nvim_create_user_command('SeventyThreeInfo', function()
  vim.notify(vim.inspect(require('73').status()), vim.log.levels.INFO, { title = '73' })
end, { desc = 'Show 73 implementation status and configured adapters' })

vim.api.nvim_create_user_command('SeventyThreeCancel', function()
  if not require('73').cancel() then
    vim.notify('73: no active request in this buffer', vim.log.levels.INFO)
  end
end, { desc = 'Cancel the current buffer request or close its preview' })

vim.api.nvim_create_user_command('SeventyThreeStatus', function()
  local status = require('73').request_status()
  local text = status and ('73 ' .. status.operation .. ': ' .. status.state) or '73: no request in this buffer'
  if status and status.message then text = text .. '\n' .. status.message end
  vim.notify(text, vim.log.levels.INFO, { title = '73' })
end, { desc = 'Show the current buffer’s latest request status and error' })

vim.api.nvim_create_user_command('SeventyThreeShow', function()
  local ok, reason = require('73').show()
  if not ok then vim.notify(reason, vim.log.levels.INFO, { title = '73' }) end
end, { desc = 'Open the current buffer’s ready answer or proposal' })


vim.api.nvim_create_user_command('SeventyThreeAutoApply', function()
  local enabled = require('73').toggle_auto_apply()
  vim.notify('73 auto apply: ' .. (enabled and 'on' or 'off'), vim.log.levels.INFO)
end, { desc = 'Toggle automatic acceptance for future edit requests' })

vim.api.nvim_create_user_command('SeventyThreeCancelAll', function() require('73').cancel_all() end,
  { desc = 'Cancel every outstanding 73 request' })

vim.api.nvim_create_user_command('SeventyThreeProvider', function(command)
  local plugin = require('73')
  local function select(name)
    if not name then return end
    local ok, problem = pcall(plugin.select_provider, name)
    vim.notify(ok and ('73 provider: ' .. name) or tostring(problem), ok and vim.log.levels.INFO or vim.log.levels.WARN)
  end
  if command.args ~= '' then select(command.args)
  else vim.ui.select(plugin.providers(), {prompt='73 provider'}, select) end
end, { nargs='?', complete=function() return require('73').providers() end, desc='Switch 73 provider for future requests' })
