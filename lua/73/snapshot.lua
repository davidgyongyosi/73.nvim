local M = {}

local function integer(n)
  return type(n) == 'number' and n >= 0 and n == math.floor(n)
end

function M.validate_range(lines, range)
  assert(type(range) == 'table', '73: missing range')
  for _, point in ipairs({ range.start or false, range['end'] or false }) do
    assert(type(point) == 'table' and integer(point[1]) and integer(point[2]), '73: invalid position')
    local line = lines[point[1] + 1]
    assert(line and point[2] <= #line, '73: position outside buffer')
    local byte = line:byte(point[2] + 1)
    assert(not byte or byte < 128 or byte >= 192, '73: position splits UTF-8 character')
  end
  local a, b = range.start, range['end']
  assert(a[1] < b[1] or (a[1] == b[1] and a[2] <= b[2]), '73: reversed range')
end

function M.visual(buf)
  assert(buf == vim.api.nvim_get_current_buf(), '73: visual selection must be in current buffer')
  local mode = vim.fn.mode()
  assert(mode == 'v' or mode == 'V', '73: use a character or line visual selection (blocks unsupported)')
  local anchor, cursor = vim.fn.getpos('v'), vim.api.nvim_win_get_cursor(0)
  local a, b = { anchor[2] - 1, anchor[3] - 1 }, { cursor[1] - 1, cursor[2] }
  if a[1] > b[1] or (a[1] == b[1] and a[2] > b[2]) then a, b = b, a end
  local linewise = mode == 'V' and { first = a[1], last = b[1] + 1 } or nil
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
  a[2], b[2] = math.min(a[2], #lines[a[1] + 1]), math.min(b[2], #lines[b[1] + 1])
  if mode == 'V' then
    a[2] = 0
    if b[1] + 1 < #lines then b = { b[1] + 1, 0 } else b[2] = #lines[b[1] + 1] end
  elseif vim.o.selection ~= 'exclusive' or vim.deep_equal(a, b) then
    local line = lines[b[1] + 1]
    if b[2] < #line then
      b[2] = b[2] + 1
      while b[2] < #line and line:byte(b[2] + 1) >= 128 and line:byte(b[2] + 1) < 192 do
        b[2] = b[2] + 1
      end
    end
  end
  return { start = a, ['end'] = b }, linewise
end

function M.capture(buf, range, linewise)
  assert(vim.api.nvim_buf_is_loaded(buf), '73: buffer is not loaded')
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
  M.validate_range(lines, range)
  if linewise then
    assert(type(linewise) == 'table' and integer(linewise.first) and integer(linewise.last)
      and linewise.first < linewise.last and linewise.last <= #lines, '73: invalid linewise bounds')
    local finish = linewise.last < #lines and { linewise.last, 0 } or { #lines - 1, #lines[#lines] }
    assert(vim.deep_equal(range, { start = { linewise.first, 0 }, ['end'] = finish }),
      '73: linewise bounds do not match range')
  end
  local name = vim.api.nvim_buf_get_name(buf)
  local text = table.concat(lines, '\n') .. (vim.bo[buf].endofline and '\n' or '')
  local cursor = vim.api.nvim_win_get_cursor(0)
  local directory = name ~= '' and vim.fn.fnamemodify(name, ':h') or vim.fn.getcwd()
  local marker = vim.fs.find({ '.git' }, { path = directory, upward = true })[1]
  return {
    buf = buf,
    name = name,
    lines = lines,
    linewise = vim.deepcopy(linewise),
    endofline = vim.bo[buf].endofline,
    workspace_root = marker and vim.fs.dirname(marker) or directory,
    document = {
      uri = name ~= '' and vim.uri_from_fname(name) or ('untitled:73/' .. buf),
      filetype = vim.bo[buf].filetype,
      revision = vim.api.nvim_buf_get_changedtick(buf),
      content_hash = vim.fn.sha256(text),
      text = text,
      range = vim.deepcopy(range),
      selection = linewise and 'line' or 'character',
      cursor = { cursor[1] - 1, cursor[2] },
    },
  }
end

function M.fresh(snapshot)
  local buf = snapshot.buf
  return vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
    and vim.api.nvim_buf_get_name(buf) == snapshot.name
    and vim.api.nvim_buf_get_changedtick(buf) == snapshot.document.revision
    and vim.bo[buf].endofline == snapshot.endofline
    and vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, true), snapshot.lines)
end

return M
