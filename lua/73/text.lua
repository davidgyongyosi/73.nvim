local M = {}

function M.validate(text)
  assert(type(text) == "string" and not text:find("\0", 1, true), "73: invalid response text")
  local i = 1
  while i <= #text do
    local b = text:byte(i)
    local size = b < 128 and 1 or b >= 194 and b <= 223 and 2
      or b >= 224 and b <= 239 and 3 or b >= 240 and b <= 244 and 4
    assert(size and i + size - 1 <= #text, '73: invalid response UTF-8')
    for j = i + 1, i + size - 1 do
      local c = text:byte(j)
      assert(c >= 128 and c <= 191, '73: invalid response UTF-8')
    end
    local c = text:byte(i + 1)
    assert(not (b == 224 and c < 160 or b == 237 and c >= 160
      or b == 240 and c < 144 or b == 244 and c >= 144), '73: invalid response UTF-8')
    i = i + size
  end
  return text
end

return M
