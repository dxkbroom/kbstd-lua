-- Port of kotlinx.coroutines' FailedJobTest (see AGENTS.md, "Kotlin test
-- ports"). Failures of launched jobs are reported through `runtest`'s
-- unhandled-failure option; waiting uses `async.join`.
---@diagnostic disable: await-in-sync

local async = require("luastd.async")
local luastd_test = require("luastd_test")
local runtest = luastd_test.runtest

-- kotlin: kotlinx-coroutines-core/common/test/FailedJobTest.kt@1.11.0
describe("FailedJobTest", function ()
    it(
        "testCancelledJob",
        runtest(function (t)
            t:expect(1)
            local job = async.launch(function ()
                t:expect_unreached()
            end)
            t:expect(2)
            job:cancel()
            async.join(job)
            t:finish(3)
            assert.is_true(job:is_completed())
            assert.is_false(job:is_active())
            assert.is_true(job:is_cancelled())
        end)
    )

    it(
        "testFailedJob",
        runtest({ unhandled = { "TestException" } }, function (t)
            t:expect(1)
            async.supervisor_scope(function (scope)
                local job = scope:launch(function ()
                    t:expect(3)
                    error(luastd_test.TestException())
                end)
                t:expect(2)
                async.join(job)
                t:finish(4)
                assert.is_true(job:is_completed())
                assert.is_false(job:is_active())
                assert.is_true(job:is_cancelled())
            end)
        end)
    )

    it(
        "testFailedChildJob",
        runtest({ unhandled = { "TestException" } }, function (t)
            t:expect(1)
            async.supervisor_scope(function (scope)
                local job = scope:launch(function (parent)
                    t:expect(3)
                    parent:launch(function ()
                        error(luastd_test.TestException())
                    end)
                end)
                t:expect(2)
                async.join(job)
                t:finish(4)
                assert.is_true(job:is_completed())
                assert.is_false(job:is_active())
                assert.is_true(job:is_cancelled())
            end)
        end)
    )
end)
