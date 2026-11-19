-- `luastd.Error` from Lua (ADR 0006). tests/errors.rs installs two Rust
-- helpers: `raise()` raises a `LuaError` (kind "Boom" with code, retry, path
-- and an "Inner" cause), and `call(f)` calls `f` from a Rust frame.

local raise = rawget(_G, "raise") --[[@as fun()]]
local call = rawget(_G, "call") --[[@as fun(f: fun())]]

---@param fn fun()
---@return any
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err
end

describe("luastd.Error", function ()
    describe("from Rust", function ()
        it("is a table with kind, message and context fields", function ()
            local err = error_of(raise) --[[@as luastd.Error]]
            assert.is_equal("table", type(err))
            assert.is_equal("Boom", err.kind)
            assert.is_equal("it broke", err.message)
            assert.is_equal(42, err.code)
            assert.is_true(err.retry)
            assert.is_equal("/tmp/x", err.path)
        end)

        it("carries its cause as another luastd.Error", function ()
            local err = error_of(raise) --[[@as luastd.Error]]
            local cause = err.cause --[[@as luastd.Error]]
            assert.is_equal("Inner", cause.kind)
            assert.is_equal("the reason", cause.message)
            assert.is_equal(2, cause.depth)
            assert.is_nil(cause.cause)
            assert.is_true(getmetatable(err) == getmetatable(cause))
        end)

        it("renders as kind: message", function ()
            local err = error_of(raise)
            assert.is_equal("Boom: it broke", tostring(err))
            assert.is_equal("Inner: the reason", tostring(err.cause))
        end)

        it("is a fresh table per raise", function ()
            assert.is_false(rawequal(error_of(raise), error_of(raise)))
        end)
    end)

    describe("through Rust frames", function ()
        it("keeps its identity and Lua-added fields", function ()
            local original = error_of(raise)
            original.note = "added in Lua"
            local again = error_of(function () call(function () error(original) end) end)
            assert.is_true(rawequal(original, again))
            assert.is_equal("added in Lua", again.note)
        end)

        it("reaches an xpcall handler as the same table", function ()
            local original = error_of(raise)
            local seen
            local ok = xpcall(function ()
                call(function () error(original) end)
            end,
                function (e)
                    seen = e
                    return e
                end)
            assert.is_false(ok)
            assert.is_true(rawequal(original, seen))
        end)

        it("can be caught, inspected and rethrown in Lua", function ()
            local rethrown = error_of(function ()
                local ok, err = pcall(raise)
                assert.is_false(ok)
                if err.kind == "Boom" then
                    error(err)
                end
            end)
            assert.is_equal("Boom: it broke", tostring(rethrown))
        end)
    end)

    describe("other error values", function ()
        it("leaves plain tables alone", function ()
            local err = error_of(function () error({ kind = "Mine", code = 1 }) end)
            assert.is_equal("Mine", err.kind)
            assert.is_nil(getmetatable(err))
        end)

        it("still adds a position to string errors", function ()
            assert.matches("luastd_error_spec.lua:%d+: boom$", error_of(function () error("boom") end))
            assert.is_equal("bare", error_of(function () error("bare", 0) end))
        end)
    end)
end)
