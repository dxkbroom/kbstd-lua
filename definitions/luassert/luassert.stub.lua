---@meta luassert.stub

---@class luassert.stub.module
---@overload fun(object?: table, key?: any, ...: any): luassert.stub  same as stub.new
local stub = {}

---Replaces `object[key]` with a stub. Extra args are its return values; a single callable extra arg
---is invoked instead. With no args at all you get a blank stub on a throwaway table.
---@param object? table
---@param key? any
---@param ... any  return values, or one function to call
---@return luassert.stub
function stub.new(object, key, ...) end

return stub
