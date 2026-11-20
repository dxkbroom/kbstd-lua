-- luastd_test itself: ordered execution, expected and unhandled failures,
-- the hang timeout and test errors. Run by tests/kotlinx.rs.
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local hang = luastd_test.hang

--- Run a `runtest` and return the message it failed with.
---@param options luastd_test.Options | fun(t: luastd_test.OrderedExecution)
---@param body?   fun(t: luastd_test.OrderedExecution)
---@return string
local function failure_of(options, body)
    local test
    if body then
        local with = options --[[@as luastd_test.Options]]
        test = luastd_test.runtest(with, body)
    else
        local only = options --[[@as fun(t: luastd_test.OrderedExecution)]]
        test = luastd_test.runtest(only)
    end
    local ok, err = pcall(test)
    assert.is_false(ok)
    return tostring(err)
end

---@param text   string
---@param needle string
local function contains(text, needle)
    assert.matches(needle, text, 1, true)
end

describe("luastd.test", function ()
    describe("OrderedExecution", function ()
        it(
            "passes when every action comes in order",
            luastd_test.runtest(function (t)
                t:expect(1)
                async.launch(function ()
                    t:expect(3)
                    async.yield()
                    t:expect(5)
                end)
                t:expect(2)
                async.yield()
                t:expect(4)
                async.yield()
                t:finish(6)
            end)
        )

        it("fails on a wrong index", function ()
            local err = failure_of(function (t)
                t:expect(1)
                t:expect(3)
            end)
            contains(err, "Expecting action index 3 but it is actually 2")
            contains(err, "luastd_test_spec.lua:") -- raised at the caller
        end)

        it("fails when finish is missing after expect", function ()
            contains(
                failure_of(function (t) t:expect(1) end), "Expected `finish(2)` to be called, but the test finished"
            )
        end)

        it("allows no finish when expect was never called", luastd_test.runtest(function () end))

        it("fails on finishing twice and on expect after finish", function ()
            contains(failure_of(function (t)
                    t:finish(1)
                    t:finish(2)
                end), "Finished more than once")
            contains(failure_of(function (t)
                    t:finish(1)
                    t:expect(2)
                end), "Expecting action index 2 but it is actually finished")
        end)

        it("fails on a wrong finish index", function ()
            contains(failure_of(function (t) t:finish(2) end), "Finishing with action index 2 but it is actually 1")
        end)

        it("describes where expect_unreached was reached", function ()
            contains(failure_of(function (t) t:expect_unreached() end), "'expect' was not called yet")
            contains(failure_of(function (t)
                    t:expect(1)
                    t:expect_unreached()
                end), "the last executed action was 1")
            contains(failure_of(function (t)
                    t:finish(1)
                    t:expect_unreached()
                end), "already finished")
        end)

        it("records failures that the body catches", function ()
            local err = failure_of(function (t)
                t:expect(1)
                pcall(t.expect, t, 5)
                t:finish(3)
            end)
            contains(err, "Expecting action index 5 but it is actually 2")
        end)

        it("check_finish_call can require finish", function ()
            contains(failure_of(function (t) t:check_finish_call(false) end), "Expected `finish(1)`")
        end)

        it(
            "reset starts counting again",
            luastd_test.runtest(function (t)
                for _ = 1, 2 do
                    t:reset()
                    t:expect(1)
                    t:finish(2)
                end
            end)
        )
    end)

    describe("runtest", function ()
        it("fails with the body's error", function ()
            contains(failure_of(function () error({ kind = "Boom", message = "x" }) end), "table:")
            contains(failure_of(function () error("plain", 0) end), "plain")
        end)

        it("fails when a launched child fails, like runBlocking", function ()
            contains(failure_of(function ()
                    async.launch(function () error("child failed", 0) end)
                end), "child failed")
        end)

        it("waits for children", function ()
            local done = false
            luastd_test.runtest(function ()
                async.launch(function ()
                    async.delay(5)
                    done = true
                end)
            end)()
            assert.is_true(done)
        end)

        it(
            "passes the body's scope",
            luastd_test.runtest(function (_, scope)
                assert.is_true(scope:is_active())
            end)
        )

        describe("expected", function ()
            it(
                "matches a kind",
                luastd_test.runtest({ expected = "TestException" }, function ()
                    error(luastd_test.TestException())
                end)
            )

            it(
                "matches a predicate",
                luastd_test.runtest({
                    expected = function (e) return e.kind == "Timeout" and e.message == "Timed out immediately" end
                },
                    function ()
                        async.with_timeout(0, function () end)
                    end)
            )

            it("fails when nothing is raised", function ()
                contains(
                    failure_of({ expected = "Timeout" }, function () end), "Exception was expected but none produced"
                )
            end)

            it("fails on another error", function ()
                contains(
                    failure_of({ expected = "Timeout" }, function () error(luastd_test.TestException1("x")) end),
                    "Unexpected exception: TestException1: x"
                )
            end)
        end)

        describe("unhandled", function ()
            local function failing_children(...)
                local kinds = { ... }
                return function ()
                    async.supervisor_scope(function ()
                        for _, kind in ipairs(kinds) do
                            async.launch(function () error({ kind = kind, message = "m" }) end)
                            async.yield()
                        end
                    end)
                end
            end

            it(
                "passes when they match in order",
                luastd_test.runtest(
                    { unhandled = { "TestException2", "TestException1" } },
                    failing_children("TestException2", "TestException1")
                )
            )

            it("fails on too many", function ()
                contains(failure_of(failing_children("A")), "Too many unhandled exceptions 1, expected 0, got: A: m")
            end)

            it("fails on too few", function ()
                contains(
                    failure_of({ unhandled = { "A", "B" } }, failing_children("A")),
                    "Too few unhandled exceptions 1, expected 2"
                )
            end)

            it("fails on an unexpected one", function ()
                contains(
                    failure_of({ unhandled = { "A" } }, failing_children("B")),
                    "Unhandled exception was unexpected: B: m"
                )
            end)

            it(
                "ignores cancelled children",
                luastd_test.runtest(function ()
                    async.supervisor_scope(function ()
                        async.launch(function () async.delay(1000) end):cancel()
                    end)
                end)
            )
        end)

        it("fails a hung test after its timeout", function ()
            contains(failure_of({ timeout = 20 }, function () hang() end), "still running after 20 ms")
        end)

        it("does not mistake the body's own Timeout for hanging", function ()
            contains(failure_of({ timeout = 1000 }, function ()
                    async.with_timeout(10, function () hang() end)
                end), "Timed out waiting for 10 ms")
        end)
    end)

    describe("helpers", function ()
        it(
            "hang runs its handler when cancelled",
            luastd_test.runtest(function (t)
                local job = async.launch(function ()
                    t:expect(2)
                    hang(function () t:expect(4) end)
                end)
                t:expect(1)
                async.yield()
                t:expect(3)
                job:cancel()
                job:join()
                t:finish(5)
            end)
        )

        it("test exceptions are luastd.Error values", function ()
            local e = luastd_test.TestException("boom")
            assert.is_equal("TestException", e.kind)
            assert.is_equal("TestException: boom", tostring(e))
            local _, timeout = pcall(async.with_timeout, 0, function () end)
            assert.is_true(getmetatable(e) == getmetatable(timeout))
            for i, make in ipairs(
                { luastd_test.TestException1, luastd_test.TestException2, luastd_test.TestException3 }
            ) do
                assert.is_equal("TestException" .. i, make().kind)
            end
        end)
    end)
end)
