---@meta luastd.env

--- Environment variables, checked against the host's `env` permission.
---
--- Reads see this runtime's overlay first, then the process environment.
--- `set` and `unset` only change the overlay: the process environment is
--- never modified.
---
--- The plain functions are async: when the host has not decided yet they wait
--- for its prompt. The `*_sync` variants never wait; an undecided permission
--- raises `PermissionDenied`. Errors are raised as `luastd.Error` tables.
---@class luastd.env
local env = {}

--- Read a variable.
---@async
---@param name string
---@return string? value `nil` when unset
function env.get(name) end

--- Check whether a variable is set.
---@async
---@param name string
---@return boolean
function env.has(name) end

--- Set a variable in this runtime's overlay.
---@async
---@param name  string
---@param value string
function env.set(name, value) end

--- Unset a variable in this runtime's overlay.
---@async
---@param name string
function env.unset(name) end

--- Every visible variable. Needs access to all variables.
---@async
---@return table<string, string>
function env.vars() end

--- `env.get` without prompting.
---@param name string
---@return string?
function env.get_sync(name) end

--- `env.has` without prompting.
---@param name string
---@return boolean
function env.has_sync(name) end

--- `env.set` without prompting.
---@param name  string
---@param value string
function env.set_sync(name, value) end

--- `env.unset` without prompting.
---@param name string
function env.unset_sync(name) end

--- `env.vars` without prompting.
---@return table<string, string>
function env.vars_sync() end

return env
