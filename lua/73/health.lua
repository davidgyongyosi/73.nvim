local M = {}

function M.check()
  vim.health.start('73')
  if vim.fn.has('nvim-0.10') == 1 then
    vim.health.ok('Neovim satisfies the minimum (0.10+)')
  else
    vim.health.error('Neovim 0.10+ is required')
  end
  local status = require('73').status()
  vim.health.info('Ask/Edit/Insert implemented; experimental Claude and Pi adapters tested offline')
  vim.health.info('Live inference is not verified; Pi adapter currently requires Unix')
  for _, slot in ipairs({ 'harness' }) do
    local descriptor = status.selected[slot]
    if not descriptor then
      vim.health.info('No ' .. slot .. ' configured')
    else
      local operations = { 'ask', 'edit', 'insert' }
      local available = {}
      for _, operation in ipairs(operations) do
        if descriptor.implemented[operation] then available[#available + 1] = operation end
      end
      if #available == 0 then
        vim.health.warn(descriptor.name .. ': metadata only; no usable ' .. slot .. ' callback')
      else
        vim.health.ok(descriptor.name .. ': local callbacks available for ' .. table.concat(available, ', '))
      end
      local metadata = descriptor.metadata
      if metadata.development_only then
        vim.health.warn(descriptor.name .. ': fake development adapter; suggestions are fixed text')
      end
      if metadata.backend == 'claude' then
        if vim.fn.executable(metadata.executable or 'claude') == 1 then
          vim.health.ok('Claude executable available; model: ' .. tostring(metadata.model))
        else vim.health.error('Claude executable not found') end
        vim.health.info('Claude authentication is reused; live inference not verified')
      elseif metadata.backend == 'pi' then
        if vim.fn.has('win32') == 1 then vim.health.error('Pi adapter requires Unix process groups') end
        if type(metadata.executable) == 'string' and vim.fn.executable(metadata.executable) == 1 then
          vim.health.ok('Pi executable found: ' .. metadata.executable)
        else
          vim.health.error('Pi executable not found: ' .. tostring(metadata.executable))
        end
        vim.health.info('Pi must report ' .. tostring(metadata.inspected_version or 'the inspected version')
          .. '; version is checked when requesting, not during health checks')
        vim.health.warn('Pi live inference and provider readiness have not been verified')

      end
    end
  end
end

return M
