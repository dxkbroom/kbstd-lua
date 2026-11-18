-- The task environment mise provides (https://mise.jdx.dev/tasks/task-environment.html),
-- with fallbacks so a task can also run as a plain `lua` script.
local fs = require("fs")

local M = {}

---@class mise.Env
---@field project_root string  MISE_PROJECT_ROOT
---@field config_root string   MISE_CONFIG_ROOT
---@field task_file string     MISE_TASK_FILE
---@field task_dir string      MISE_TASK_DIR
---@field original_cwd string  MISE_ORIGINAL_CWD

---@alias mise.Getenv fun(name: string): string?

---Reads `name`, treating an empty value as unset.
---@param getenv mise.Getenv
---@param name string
---@return string?
local function env(getenv, name)
  local value = getenv(name)
  if value == nil or value == "" then
    return nil
  end
  return value
end

---Path of the Lua file that called `resolve` (nil when it wasn't loaded from a file).
---@return string?
local function caller_file()
  local info = debug.getinfo(3, "S")
  if info and info.source:sub(1, 1) == "@" then
    return info.source:sub(2)
  end
  return nil
end

---Resolves the mise task environment.
---Without mise, the project root is derived from the task file: <root>/xtasks/tasks/<group>/<task>.
---@param getenv? mise.Getenv  defaults to os.getenv
---@param task_file? string    defaults to MISE_TASK_FILE, then the calling file
---@return mise.Env
function M.resolve(getenv, task_file)
  getenv = getenv or os.getenv
  task_file = task_file or env(getenv, "MISE_TASK_FILE") or caller_file() or "."
  local task_dir = env(getenv, "MISE_TASK_DIR") or fs.dirname(task_file)
  local project_root = env(getenv, "MISE_PROJECT_ROOT")
    or env(getenv, "MISE_CONFIG_ROOT")
    or fs.dirname(fs.dirname(fs.dirname(task_dir))) -- render -> tasks -> xtasks -> root
  ---@type mise.Env
  local mise = {
    project_root = project_root,
    config_root = env(getenv, "MISE_CONFIG_ROOT") or project_root,
    task_file = task_file,
    task_dir = task_dir,
    original_cwd = env(getenv, "MISE_ORIGINAL_CWD") or env(getenv, "PWD") or ".",
  }
  return mise
end

return M
