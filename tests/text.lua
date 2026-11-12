local validate = require('73.text').validate
for _, value in ipairs({ '', 'ASCII\n\t', 'café', '茶', '😀', '\244\143\191\191' }) do
  assert(validate(value) == value)
end
local invalid = { '\0', '\128', '\192\175', '\226\130', '\237\160\128', '\244\144\128\128', '\255' }
for _, value in ipairs(invalid) do assert(not pcall(validate, value)) end
local plugin = require('73')
local response_callback, captured
plugin.register_adapter('invalid_text_fixture', {
  capabilities = { ask = true, edit = true },
  request = function(request, callback) captured, response_callback = request, callback end,
})
plugin.setup({ harness = 'invalid_text_fixture' })
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, true, { 'unchanged' })
local range = { start = { 0, 0 }, ['end'] = { 0, 1 } }
for _, operation in ipairs({ 'ask', 'edit' }) do
  for _, text in ipairs(invalid) do
    local handle = plugin[operation]('test', { range = range })
    local doc = captured.document
    local response = { id = captured.id, uri = doc.uri, revision = doc.revision,
      content_hash = doc.content_hash, range = doc.range }
    response[operation == 'ask' and 'answer' or 'replacement'] = text
    response_callback(response)
    vim.wait(10, function() return false end)
    assert(handle.status() == 'failed')
    assert(vim.api.nvim_get_current_buf() == buf)
    assert(vim.api.nvim_buf_get_lines(buf, 0, 1, true)[1] == 'unchanged')
  end
end
plugin.setup({})
print('73 response UTF-8 checks passed')
