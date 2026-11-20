-- Port of kotlinx.coroutines' SupervisorTest (see AGENTS.md, "Kotlin test
-- ports"). luastd's supervisor boundary is `async.supervisor_scope`; it has
-- no standalone SupervisorJob, Job parent, or start modes.
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

--- Kotlin's `try { ... } catch (e: ...)`: the error `fn` raised.
---@param fn fun()
---@return any
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err
end

-- kotlin: kotlinx-coroutines-core/common/test/SupervisorTest.kt@1.11.0
describe("SupervisorTest", function ()
    -- defer: no standalone `SupervisorJob()` or `joinAll`; launch failures are
    -- reported to the host's unhandled-failure handler instead.
    pending("testSupervisorJob")

    -- adapted: deferred failures are consumed with `try_await` so the test
    -- can assert both exceptions without a standalone exception handler.
    it(
        "testSupervisorScope",
        runtest(function (t)
            local first, second
            local value = async.supervisor_scope(function (scope)
                first = scope:async(function () error(luastd_test.TestException1()) end)
                second = scope:async(function () error(luastd_test.TestException2()) end)
                local ok1, err1 = async.try_await(first)
                local ok2, err2 = async.try_await(second)
                assert.is_false(ok1)
                assert.is_equal("TestException1", err1.kind)
                assert.is_false(ok2)
                assert.is_equal("TestException2", err2.kind)
                return "OK"
            end)
            assert.is_equal("OK", value)
            assert.is_true(first:is_cancelled())
            assert.is_true(second:is_cancelled())
            t:finish(1)
        end)
    )

    -- adapted: use a deferred failure and `try_await` to inspect the error;
    -- this keeps the sibling-isolation assertion inside the test.
    it(
        "testSupervisorScopeIsolation",
        runtest(function (t)
            local sibling_finished = false
            local failed
            async.supervisor_scope(function (scope)
                scope:launch(function ()
                    async.delay(20)
                    sibling_finished = true
                end)
                failed = scope:async(function ()
                    async.delay(5)
                    error(luastd_test.TestException2())
                end)
                local ok, err = async.try_await(failed)
                assert.is_false(ok)
                assert.is_equal("TestException2", err.kind)
                assert.is_true(scope:is_active())
                assert.is_true(not failed:is_active() and failed:is_completed() and failed:is_cancelled())
            end)
            assert.is_true(sibling_finished)
            t:finish(1)
        end)
    )

    it(
        "testThrowingSupervisorScope",
        runtest(function (t)
            local child
            local err = error_of(function ()
                async.supervisor_scope(function (scope)
                    child = scope:async(function ()
                        async.delay(1000)
                    end)
                    async.yield()
                    error(luastd_test.TestException2())
                end)
            end)
            assert.is_equal("TestException2", err.kind)
            assert.is_true(child:is_cancelled())
            t:finish(1)
        end)
    )

    -- adapted: cancel the parent job and check that cancellation reaches the
    -- supervisor's child cleanup; luastd has no CoroutineExceptionHandler.
    it(
        "testSupervisorScopeExternalCancellation",
        runtest(function (t)
            local child_finished = false
            local outer = async.launch(function ()
                async.supervisor_scope(function (scope)
                    scope:launch(function ()
                        async.finally(function ()
                            async.delay(1000)
                        end,
                            function ()
                                child_finished = true
                            end)
                    end)
                end)
            end)
            async.yield()
            outer:cancel()
            async.join(outer)
            assert.is_true(outer:is_cancelled())
            assert.is_true(child_finished)
            t:finish(1)
        end)
    )

    -- defer: a standalone `SupervisorJob()` parent and deferred parent links
    -- are not part of the current API.
    pending("testAsyncCancellation")

    -- defer: no standalone `Job()` parent or `SupervisorJob(parent)`.
    pending("testSupervisorWithParentCancelNormally")
    -- defer: no standalone `Job()` parent or `SupervisorJob(parent)`.
    pending("testSupervisorWithParentCancelException")

    -- adapted: luastd delivers cancellation at the next suspension and does
    -- not enter the body's later error path (ADR 0005).
    it(
        "testSupervisorScopeCancellationVsException",
        runtest(function (t)
            local after_scope = false
            local job = async.launch(function (self)
                async.supervisor_scope(function ()
                    self:cancel()
                    async.yield()
                    error(luastd_test.TestException1())
                end)
                after_scope = true
            end)
            async.join(job)
            assert.is_true(job:is_cancelled())
            assert.is_false(after_scope)
            t:finish(1)
        end)
    )

    -- defer: no standalone SupervisorJob or CoroutineExceptionHandler.
    pending("testSupervisorJobCancellationException")

    -- adapted: `async.finally` runs the cancelled child's cleanup, while the
    -- supervisor body error remains the one observed by its caller.
    it(
        "testSupervisorThrowsWithFailingChild",
        runtest(function (t)
            local cleanup_ran = false
            local err = error_of(function ()
                async.supervisor_scope(function (scope)
                    scope:launch(function ()
                        async.finally(function ()
                            async.delay(1000)
                        end,
                            function ()
                                cleanup_ran = true
                                error(luastd_test.TestException2())
                            end)
                    end)
                    async.yield()
                    error(luastd_test.TestException1())
                end)
            end)
            assert.is_equal("TestException1", err.kind)
            assert.is_true(cleanup_ran)
            t:finish(1)
        end)
    )

    -- adapted: this verifies the supervisor body error and child cancellation
    -- directly, while the other `testSupervisorThrows` form needs two
    -- unhandled launch failures and a custom exception handler.
    it(
        "testSupervisorThrows",
        runtest(function (t)
            local child
            local err = error_of(function ()
                async.supervisor_scope(function (scope)
                    child = scope:launch(function () async.delay(1000) end)
                    async.yield()
                    error(luastd_test.TestException1())
                end)
            end)
            assert.is_equal("TestException1", err.kind)
            assert.is_true(child:is_cancelled())
            t:finish(1)
        end)
    )
end)
