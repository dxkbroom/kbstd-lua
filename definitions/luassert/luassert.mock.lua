---@meta luassert.mock

---@class luassert.mock.module
---@overload fun(object: table, dostub?: boolean, func?: function): table  same as mock.new
local mock = {}

---Walks `object` (recursively) and replaces every function with a spy, or a stub when `dostub`
---is true (`func` becomes the stubs' implementation). Mutates and returns `object`.
---@generic T
---@param object T
---@param dostub? boolean
---@param func? function
---@return T
function mock.new(object, dostub, func) end

---Calls `clear()` on every spy/stub inside `object`.
---@generic T
---@param object T
---@return T
function mock.clear(object) end

---Calls `revert()` on every spy/stub inside `object`, restoring the originals.
---@generic T
---@param object T
---@return T
function mock.revert(object) end

return mock
