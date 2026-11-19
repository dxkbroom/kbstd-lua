local lmath = require("luastd.math")

---@param fn fun()
---@return string
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return tostring(err)
end

describe("luastd.math", function ()
    describe("add", function ()
        it("adds two integers", function ()
            assert.is_equal(5, lmath.add(2, 3))
            assert.is_equal(0, lmath.add(0, 0))
            assert.is_equal(-1, lmath.add(2, -3))
        end)

        it("accepts whole-number floats", function ()
            ---@diagnostic disable-next-line: param-type-mismatch
            assert.is_equal(5, lmath.add(2.0, 3))
        end)

        it("rejects non-integers", function ()
            assert.matches(
                "bad argument #1 'left' to 'add' (integer expected)",
                error_of(function ()
                    ---@diagnostic disable-next-line: param-type-mismatch
                    lmath.add("2", 3)
                end),
                1, true
            )
            assert.matches(
                "bad argument #2 'right' to 'add' (integer expected)",
                error_of(function ()
                    ---@diagnostic disable-next-line: param-type-mismatch
                    lmath.add(2, 1.5)
                end),
                1, true
            )
        end)
    end)
end)
