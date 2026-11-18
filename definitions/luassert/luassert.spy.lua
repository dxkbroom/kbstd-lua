---@meta luassert.spy

---@class luassert.spy.module
---@overload fun(callback?: function): luassert.spy  same as spy.new
local spy = {}

---Wraps `callback` (default: a no-op) in a callable spy that records calls and return values.
---@param callback? function|table  function or callable table
---@return luassert.spy
function spy.new(callback) end

---Replaces `target_table[target_key]` with a spy around it; `revert()` puts the original back.
---@param target_table table
---@param target_key any
---@return luassert.spy
function spy.on(target_table, target_key) end

---@param object any
---@return boolean
function spy.is_spy(object) end

return spy
