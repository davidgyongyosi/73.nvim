-- No network, credentials, user config, or external test dependencies.
vim.opt.swapfile = false
vim.opt.runtimepath:prepend(vim.fn.getcwd())
vim.cmd('runtime plugin/73.lua')
local plugin = require('73')
plugin.setup({})
assert(vim.fn.exists(':SeventyThreeInfo') == 2)
assert(plugin.status().requests_implemented == true)
assert(plugin.status().live_adapters_implemented == true)
assert(plugin.status().live_adapters_verified == false)
local fake = { capabilities = { ask = true } }
plugin.register_adapter('fixture_harness', fake)
fake.capabilities.ask = false
plugin.setup({ harness = 'fixture_harness' })
local snapshot = plugin.status()
assert(snapshot.harness == 'fixture_harness')
snapshot.adapters[1] = 'mutated'
assert(plugin.status().adapters[1] ~= 'mutated')
assert(not pcall(plugin.setup, { completion = 'removed' }))
assert(not pcall(plugin.setup, { completion_options = {} }))
assert(plugin.complete == nil and plugin.accept_completion == nil)
assert(not pcall(plugin.setup, { harness = 'missing' }))
assert(not pcall(plugin.register_adapter, 'fixture_harness', fake))
assert(not pcall(plugin.register_adapter, '../bad', fake))
assert(not pcall(plugin.setup, { unknown = 'fixture_harness' }))
plugin.setup({})
assert(plugin.status().harness == nil)
require('73.health').check()
local original_notify = vim.notify
-- Expected failure cases are asserted by dedicated UI tests, not printed as errors.
vim.notify = function() end
dofile('tests/text.lua')
dofile('tests/preview.lua')
dofile('tests/edit.lua')
dofile('tests/interactions.lua')
dofile('tests/pi.lua')
dofile('tests/progress.lua')
dofile('tests/focus.lua')
dofile('tests/commands.lua')
dofile('tests/auto-apply.lua')
dofile('tests/parallel.lua')
dofile('tests/claude.lua')
dofile('tests/live-setup.lua')
vim.notify = original_notify
assert(vim.v.errmsg == '', vim.v.errmsg)
print('73 smoke checks passed')
vim.cmd('qa!')
