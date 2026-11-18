-- Small filesystem helpers for mise tasks (Lua 5.1-5.5, LuaJIT).
local M = {}

---Shell-quotes `s` for a POSIX shell.
---@param s string
---@return string
function M.shell_quote(s)
  return "'" .. (s:gsub("'", [['\'']])) .. "'"
end

---@param path string
---@return boolean
function M.is_absolute(path)
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

---Resolves `path` against `base` unless it is already absolute.
---@param base string
---@param path string
---@return string
function M.resolve(base, path)
  if M.is_absolute(path) then
    return path
  end
  return base .. "/" .. path
end

---Parent directory of `path` ("." when it has none).
---@param path string
---@return string
function M.dirname(path)
  local dir = path:match("^(.*)[/\\][^/\\]*$")
  if dir == nil then
    return "."
  elseif dir == "" then
    return "/"
  end
  return dir
end

---Creates `dir` and its parents (Lua has no mkdir of its own).
---@param dir string
function M.mkdir_p(dir)
  local ok = os.execute("mkdir -p " .. M.shell_quote(dir))
  if ok ~= true and ok ~= 0 then -- 5.1/LuaJIT return a status code, 5.2+ return true|nil
    error("mkdir -p failed: " .. dir, 2)
  end
end

---Writes `content` verbatim (binary mode, so always LF) to `path`.
---@param path string
---@param content string
function M.write_file(path, content)
  local f = assert(io.open(path, "wb"))
  assert(f:write(content))
  assert(f:close())
end

return M
