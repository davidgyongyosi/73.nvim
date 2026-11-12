-- Compatibility entry point for the first editing slice.
local M = {}
function M.start(adapter, instruction, opts)
  return require('73.request').start('edit', adapter, instruction, opts)
end
return M
