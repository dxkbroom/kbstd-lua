-- luastd_test: kotlinx.coroutines-style ordered-execution tests for the
-- runtime specs, after `TestBase` in kotlinx.coroutines' `test-utils`
-- (`OrderedExecution`, `ErrorCatching`, `runTest`).
--
-- Test-only: `tests/common` loads this chunk with its Rust helpers and puts
-- the result in `package.loaded`, so specs `require("luastd_test")`. It is not
-- part of luastd.
--
-- ```lua
-- local luastd_test = require("luastd_test")
-- local runtest = luastd_test.runtest
--
-- it("testDispatch", runtest(function (t)
--     t:expect(1)
--     async.launch(function () t:expect(3) end)
--     t:expect(2)
--     async.yield()
--     t:finish(4)
-- end))
-- ```

-- Test bodies run inside the spec's coroutine, so they may suspend.
---@diagnostic disable: await-in-sync

---@class luastd_test.Native
---@field error         fun(kind: string, message?: string): luastd.Error
---@field set_unhandled fun(handler?: fun(err: any))

local native = ... --[[@as luastd_test.Native]]
local async = require("luastd.async")

---@diagnostic disable-next-line: undefined-global, deprecated
local unpack = table.unpack or unpack

local function pack(...)
    return { n = select("#", ...), ... }
end

--- `tostring`, but plain `{ kind = ... }` tables read as `kind: message`.
---@param value any
---@return string
local function show(value)
    if type(value) == "table" and getmetatable(value) == nil and value.kind ~= nil then
        return tostring(value.kind) .. ": " .. tostring(value.message)
    end
    return tostring(value)
end

--- The execution-order counter of one `runtest`: each action calls
--- `expect(n)` with the next number, the last one calls `finish(n)`.
---
--- Every failure is recorded before it is raised, so the test still fails
--- when the error is caught, or raised in a job nobody awaits (kotlinx's
--- `ErrorCatching`).
---@class luastd_test.OrderedExecution
---@field private _index    integer  actions so far
---@field private _finished boolean
---@field private _errors   string[] failures recorded so far
local OrderedExecution = {}
OrderedExecution.__index = OrderedExecution

---@return luastd_test.OrderedExecution
local function ordered_execution()
    return setmetatable({ _index = 0, _finished = false, _errors = {} }, OrderedExecution)
end

--- Record `message`, then raise it at the caller of the method that called
--- this.
---@param self    luastd_test.OrderedExecution
---@param message string
local function fail(self, message)
    table.insert(self._errors, message)
    error(message, 3)
end

--- Expect this action to be the `index`-th, counting from 1.
---@param index integer
function OrderedExecution:expect(index)
    if self._finished then
        fail(self, ("Expecting action index %d but it is actually finished"):format(index))
    end
    self._index = self._index + 1
    if index ~= self._index then
        fail(self, ("Expecting action index %d but it is actually %d"):format(index, self._index))
    end
end

--- Expect this action to be the last one, the `index`-th.
---@param index integer
function OrderedExecution:finish(index)
    if self._finished then
        fail(self, "Finished more than once")
    end
    self._finished = true
    local was = self._index + 1
    if index ~= was then
        fail(self, ("Finishing with action index %d but it is actually %d"):format(index, was))
    end
end

--- Fail: this line must never run.
function OrderedExecution:expect_unreached()
    local state
    if self._finished then
        state = "already finished"
    elseif self._index == 0 then
        state = "'expect' was not called yet"
    else
        state = "the last executed action was " .. self._index
    end
    fail(self, "Should not be reached, " .. state)
end

---@param self                   luastd_test.OrderedExecution
---@param allow_not_using_expect boolean
---@return string? failure
local function finish_failure(self, allow_not_using_expect)
    if self._finished or (allow_not_using_expect and self._index == 0) then
        return nil
    end
    return ("Expected `finish(%d)` to be called, but the test finished"):format(self._index + 1)
end

--- Fail unless `finish` was called. By default a test that never called
--- `expect` need not call `finish` either; pass `false` to require it.
--- `runtest` checks this when the body returns.
---@param allow_not_using_expect? boolean default `true`
function OrderedExecution:check_finish_call(allow_not_using_expect)
    local failure = finish_failure(self, allow_not_using_expect ~= false)
    if failure then
        fail(self, failure)
    end
end

--- Check `finish` was called, then start counting from 1 again; for tests
--- that loop over parameters.
function OrderedExecution:reset()
    self:check_finish_call()
    self._index, self._finished = 0, false
end

--- A failure `runtest` expects: a `luastd.Error` kind such as `"Timeout"`
--- (the canonical form), or a predicate for what a kind cannot say. Kinds also
--- match plain `{ kind = ... }` tables.
---@alias luastd_test.Matcher string | fun(err: any): boolean

---@class luastd_test.Options
--- The failure the body must end with, like kotlinx's `runTest(expected = ...)`.
---@field expected?  luastd_test.Matcher
--- Failures of `launch`ed jobs in supervisor scopes that nobody handles, in the
--- order they happen, like kotlinx's `runTest(unhandled = ...)`. Any other
--- unhandled failure fails the test.
---@field unhandled? luastd_test.Matcher[]
--- Milliseconds before the test fails as hung; default `DEFAULT_TIMEOUT`.
---@field timeout?   number

---@param matcher luastd_test.Matcher
---@param err     any
---@return boolean
local function matches(matcher, err)
    if type(matcher) == "function" then
        return matcher(err) == true
    end
    return type(err) == "table" and err.kind == matcher
end

local M = {}

--- Milliseconds a `runtest` body may take before it fails as hung.
M.DEFAULT_TIMEOUT = 10000

--- Wrap `body` as an `it` body, like kotlinx's `fun testX() = runTest { }`.
---
--- `body` runs in a fresh scope, as with `runBlocking`: `async.launch` inside
--- it starts children of that scope, a failing child fails the test, and the
--- test waits for every child. `t` checks the execution order. The test fails
--- when the body fails (unless `expected` matches), when it should have failed
--- and did not, on unexpected or missing unhandled failures, when `finish` was
--- not called after `expect`, on any recorded order failure, and after
--- `timeout` ms.
---
--- ```lua
--- local runtest = luastd_test.runtest
--- it("testSimple", runtest(function (t) ... end))
--- it("testTimeout", runtest({ expected = "Timeout" }, function (t) ... end))
--- ```
---
--- A local alias needs emmylua with #1443 (main-kbroom).
---@overload fun(body: async fun(t: luastd_test.OrderedExecution, scope: luastd.async.Scope)): fun()
---@param options luastd_test.Options
---@param body    async fun(t: luastd_test.OrderedExecution, scope: luastd.async.Scope)
---@return fun()
function M.runtest(options, body)
    if body == nil then
        local only = options --[[@as async fun(t: luastd_test.OrderedExecution, scope: luastd.async.Scope)]]
        body, options = only, {}
    end
    if type(body) ~= "function" then
        error("runtest: body must be a function", 2)
    end
    local timeout = options.timeout or M.DEFAULT_TIMEOUT
    local expected_unhandled = options.unhandled or {}
    return function ()
        local t = ordered_execution()
        local unhandled = {}
        native.set_unhandled(function (err) table.insert(unhandled, err) end)
        local result = pack(pcall(async.with_timeout, timeout, function (scope)
                return body(t, scope)
            end))
        native.set_unhandled(nil)
        local ok, err = result[1], result[2]

        -- Recorded order failures come first: they happened first. One that
        -- was raised straight out of the body is already `err`.
        local errors = {}
        for _, message in ipairs(t._errors) do
            if ok or type(err) ~= "string" or not err:find(message, 1, true) then
                table.insert(errors, message)
            end
        end
        local function report(value)
            table.insert(errors, value)
        end

        local hung = ("Timed out waiting for %s ms"):format(tostring(timeout))
        if not ok and type(err) == "table" and err.kind == "Timeout" and err.message == hung then
            report(("runtest: the test is still running after %s ms (raise `timeout` to wait longer)")
                    :format(tostring(timeout)))
        elseif options.expected ~= nil then
            if ok then
                report("Exception was expected but none produced")
            elseif not matches(options.expected, err) then
                report("Unexpected exception: " .. show(err))
            end
        elseif not ok then
            report(err)
        end
        for i, e in ipairs(unhandled) do
            if i > #expected_unhandled then
                report(("Too many unhandled exceptions %d, expected %d, got: %s")
                        :format(i, #expected_unhandled, show(e)))
            elseif not matches(expected_unhandled[i], e) then
                report("Unhandled exception was unexpected: " .. show(e))
            end
        end
        if #unhandled < #expected_unhandled then
            report(("Too few unhandled exceptions %d, expected %d"):format(#unhandled, #expected_unhandled))
        end
        if #errors == 0 then
            local failure = finish_failure(t, true)
            if failure then report(failure) end
        end

        if #errors == 1 then
            error(errors[1], 0)
        elseif #errors > 1 then
            local lines = {}
            for i, e in ipairs(errors) do
                lines[i] = show(e)
            end
            error(table.concat(lines, "\n  and: "), 0)
        end
        return unpack(result, 3, result.n)
    end
end

--- Suspend until cancelled, then run `on_cancellation`; kotlinx's `hang`.
---@async
---@param on_cancellation? fun()
function M.hang(on_cancellation)
    async.finally(function () async.delay(math.huge) end, on_cancellation or function () end)
end

--- kotlinx's `TestException`: a `luastd.Error` of that kind.
---@param message? string
---@return luastd.Error
function M.TestException(message)
    return native.error("TestException", message)
end

--- kotlinx's `TestException1`.
---@param message? string
---@return luastd.Error
function M.TestException1(message)
    return native.error("TestException1", message)
end

--- kotlinx's `TestException2`.
---@param message? string
---@return luastd.Error
function M.TestException2(message)
    return native.error("TestException2", message)
end

--- kotlinx's `TestException3`.
---@param message? string
---@return luastd.Error
function M.TestException3(message)
    return native.error("TestException3", message)
end

return M
