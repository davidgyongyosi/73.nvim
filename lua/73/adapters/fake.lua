-- Explicitly opt-in development adapter. No processes, files, or provider calls.
local M = {}

function M.new(replacement, answer)
  assert(type(replacement) == 'string', '73: fake replacement must be a string')
  assert(answer == nil or type(answer) == 'string', '73: fake answer must be a string')
  return {
    metadata = { backend = 'fake', development_only = true },
    capabilities = { ask = true, edit = true, insert = true, cancel = true, unsaved_buffers = true },
    request = function(request, respond)
      local doc = request.document
      local response = { id = request.id, uri = doc.uri, revision = doc.revision,
        content_hash = doc.content_hash }
      if request.operation == 'ask' then
        response.answer = answer or 'Fake answer: no model was called.'
      else
        response.range, response.replacement = doc.range, replacement
      end
      respond(response)
      return function() end
    end,
  }
end

return M
