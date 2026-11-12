-- Adapter registry and editor-owned entry points.
local M = {}
local adapters = {}
local config = {}

local function selected(name)
  if not name then return nil end
  local adapter = adapters[name]
  local operations = {}
  for _, operation in ipairs({ 'ask', 'edit', 'insert' }) do
    local callback = adapter.request
    operations[operation] = adapter.capabilities[operation] == true and type(callback) == 'function'
  end
  return { name = name, capabilities = vim.deepcopy(adapter.capabilities),
    implemented = operations, metadata = vim.deepcopy(adapter.metadata or {}) }
end

--- Register an integration descriptor without starting a process.
function M.register_adapter(name, adapter)
  assert(type(name) == 'string' and name:match('^[%w_-]+$'), '73: invalid adapter name')
  assert(type(adapter) == 'table', '73: adapter must be a table')
  assert(type(adapter.capabilities) == 'table', '73: adapter needs capabilities')
  assert(adapter.metadata == nil or type(adapter.metadata) == 'table', '73: adapter metadata must be a table')
  assert(adapters[name] == nil, '73: adapter already registered: ' .. name)
  adapters[name] = vim.deepcopy(adapter)
end

--- Select registered descriptors; omitted choices remain unconfigured.
function M.setup(opts)
  opts = opts or {}
  assert(type(opts) == 'table', '73: setup expects a table')
  for key, name in pairs(opts) do
    assert(key == 'harness' or key == 'auto_apply' or key == 'parallel', '73: unknown option: ' .. tostring(key))
    if key == 'auto_apply' or key == 'parallel' then
      assert(type(name) == 'boolean', '73: auto_apply must be boolean')
    else
    assert(type(name) == 'string' and adapters[name], '73: adapter not registered: ' .. tostring(name))
    local capabilities = adapters[name].capabilities
    assert(capabilities.ask == true or capabilities.edit == true or capabilities.insert == true,
      '73: adapter does not support questions or edits')
    end
  end
  config = vim.deepcopy(opts)
end

--- Return independent snapshots of the current configuration.
function M.status()
  local names = vim.tbl_keys(adapters)
  table.sort(names)
  return {
    phase = 'experimental-pi-adapter',
    harness = config.harness,
    auto_apply = config.auto_apply == true,
    selected = { harness = selected(config.harness) },
    adapters = names,
    requests_implemented = true,
    live_adapters_implemented = true,
    live_adapters_verified = false,
  }
end

--- Request a bounded replacement. With no explicit range, capture active visual selection.
function M.edit(instruction, opts)
  opts = vim.deepcopy(opts or {})
  if opts.parallel == nil then opts.parallel = config.parallel == true end
  if opts.auto_apply == nil then opts.auto_apply = config.auto_apply == true end
  return require('73.edit').start(adapters[config.harness], instruction, opts)
end

--- Ask about the active selection or cursor without changing source text.
function M.ask(instruction, opts)
  return require('73.request').start('ask', adapters[config.harness], instruction, opts)
end

--- Propose an insertion at the captured cursor position.
function M.insert(instruction, opts)
  opts = vim.deepcopy(opts or {})
  if opts.parallel == nil then opts.parallel = config.parallel == true end
  if opts.auto_apply == nil then opts.auto_apply = config.auto_apply == true end
  return require('73.request').start('insert', adapters[config.harness], instruction, opts)
end

function M.cancel_all() return require("73.request").cancel_all() end

function M.cancel()
  return require('73.request').cancel()
end

function M.request_status()
  return require('73.request').status()
end

function M.show()
  return require('73.request').show()
end

function M.toggle_auto_apply()
  config.auto_apply = not config.auto_apply
  return config.auto_apply
end

function M.select_provider(name)
  local descriptor = selected(name)
  assert(descriptor and (descriptor.implemented.ask or descriptor.implemented.edit or descriptor.implemented.insert),
    '73: provider has no request implementation: ' .. tostring(name))
  config.harness = name
  return name
end

function M.providers()
  local names = {}
  for name in pairs(adapters) do
    local item = selected(name)
    if item.implemented.ask or item.implemented.edit or item.implemented.insert then names[#names+1]=name end
  end
  table.sort(names)
  return names
end

return M
