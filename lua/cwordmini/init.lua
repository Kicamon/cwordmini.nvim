local api, ffi, expand = vim.api, require('ffi'), vim.fn.expand
local ns = api.nvim_create_namespace('CursorWord')
local set_decoration_provider = api.nvim_set_decoration_provider
local cache = {}
ffi.cdef([[
  typedef int32_t linenr_T;
  char *ml_get(linenr_T lnum);
]])
local ml_get = ffi.C.ml_get

local function find_occurrences(str, pattern)
  local startPos = 1
  local pattern_len = #pattern
  local utf8_positions = vim.str_utf_pos(str)

  return function()
    while startPos <= #str do
      local foundPos = str:find(pattern, startPos)
      if not foundPos then
        return nil
      end
      local before_char = str:sub(foundPos - 1, foundPos - 1)
      local after_char = str:sub(foundPos + pattern_len, foundPos + pattern_len)
      startPos = foundPos + 1
      if
        (before_char == '' or before_char:match('[^%w_]'))
        and (after_char == '' or after_char:match('[^%w_]'))
      then
        return utf8_positions[foundPos] - 1 -- Return byte position as screen column (Lua indexing starts from 1)
      end
    end
  end
end

return {
  setup = function(opt)
    opt = opt or {}
    local exclude = { 'dashboard', 'lazy', 'help', 'nofile', 'terminal', 'prompt' }
    vim.list_extend(exclude, opt.exclude or {})
    set_decoration_provider(ns, {
      on_win = function(_, winid, bufnr)
        if
          bufnr ~= api.nvim_get_current_buf()
          or vim.iter(exclude):find(function(v)
            return v == vim.bo[bufnr].ft or v == vim.bo[bufnr].buftype
          end)
          or api.nvim_get_mode().mode:find('i')
        then
          return false
        end
        cache.cword = expand('<cword>')
        local cursor_pos = api.nvim_win_get_cursor(winid)
        if
          not cache.cword:find('[%w%z\192-\255]')
          or not ffi
            .string(ml_get(cursor_pos[1]))
            :sub(cursor_pos[2] + 1, cursor_pos[2] + 1)
            :match('[%w_]')
        then
          cache.cword = nil
          return false
        end
        api.nvim_win_set_hl_ns(winid, ns)
        cache.len = api.nvim_strwidth(cache.cword)
      end,
      on_line = function(_, _, bufnr, row)
        for spos in find_occurrences(ffi.string(ml_get(row + 1)), cache.cword) do
          api.nvim_buf_set_extmark(bufnr, ns, row, spos, {
            end_col = spos + cache.len,
            end_row = row,
            hl_group = 'CursorWord',
            ephemeral = true,
          })
        end
      end,
    })
  end,
}
