local adapter = require('73.adapters.claude').new()
local original = vim.system
local callback, killed, argv
vim.system = function(args, opts, exit)
  argv=args
  assert(opts.stdin:find('unsaved',1,true))
  assert(vim.tbl_contains(args,'--tools') and vim.tbl_contains(args,''))
  assert(not vim.tbl_contains(args,'--dangerously-skip-permissions'))
  callback=function(payload)
    opts.stdout(nil,vim.json.encode({structured_output=payload}))
    exit({code=0})
  end
  return {kill=function() killed=true end}
end
local request={id='test',operation='edit',workspace_root=vim.fn.getcwd(),document={
 uri='test',text='unsaved',revision=1,content_hash='hash',range={start={0,0},['end']={0,1}}}}
local result, problem
adapter.request(request,function(value,err) result,problem=value,err end)
callback({replacement='changed'})
vim.wait(10,function() return false end)
assert(result and result.replacement=='changed' and result.id=='test',tostring(problem))
result=nil
local cancel=adapter.request(request,function() error('cancelled response') end)
cancel(); callback({replacement='late'})
vim.wait(10,function() return false end)
assert(killed)
adapter.request(request,function(value,err) result,problem=value,err end)
callback({answer='wrong operation'})
vim.wait(10,function() return false end)
assert(not result and problem)
vim.system=original
local plugin=require('73')
plugin.register_adapter('claude_fixture',adapter)
plugin.setup({harness='demo',auto_apply=true,parallel=true})
plugin.select_provider('claude_fixture')
assert(plugin.status().harness=='claude_fixture' and plugin.status().auto_apply)
assert(not pcall(plugin.select_provider,'missing'))
assert(plugin.status().harness=='claude_fixture')
plugin.setup({})
print('73 Claude and provider switching checks passed (fake transport)')
