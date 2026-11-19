-- The harness runs every `it` body inside the spec's coroutine, so they may
-- call `---@async` functions.
---@diagnostic disable: await-in-sync

local async = require("luastd.async")

---@param fn fun()
---@return any
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return err
end

describe("luastd.async", function ()
    describe("launch and async", function ()
        it("run concurrently and join", function ()
            local log = {}
            async.scope(function ()
                local a = async.launch(function ()
                    async.delay(20)
                    table.insert(log, "a")
                end)
                async.launch(function () table.insert(log, "b") end)
                a:join()
                table.insert(log, "joined")
            end)
            assert.are.same({ "b", "a", "joined" }, log)
        end)

        it("await returns every value", function ()
            local a, b = async.await(async.async(function ()
                    async.delay(5)
                    return 1, 2
                end))
            assert.is_equal(1, a)
            assert.is_equal(2, b)
        end)

        it("the await method returns the same values", function ()
            local deferred = async.async(function ()
                return "x", "y"
            end)
            local x, y = deferred:await()
            assert.is_equal("x", x)
            assert.is_equal("y", y)
        end)

        it("join waits without returning values", function ()
            local done = false
            local job = async.launch(function ()
                async.delay(5)
                done = true
            end)
            async.join(job)
            assert.is_true(done)
            assert.is_true(job:is_completed())
        end)

        it("await_all returns the first value of each, in argument order", function ()
            local slow = async.async(function ()
                async.delay(20)
                return "slow", "dropped"
            end)
            local fast = async.async(function () return "fast" end)
            local a, b = async.await_all(slow, fast)
            assert.is_equal("slow", a)
            assert.is_equal("fast", b)
            assert.is_nil(async.await_all())
        end)

        it("await_all raises the first failure it reaches", function ()
            local err = error_of(function ()
                async.supervisor_scope(function ()
                    local ok = async.async(function () return 1 end)
                    local bad = async.async(function () error({ kind = "Bad" }) end)
                    async.await_all(ok, bad)
                end)
            end)
            assert.is_equal("Bad", err.kind)
        end)

        it("pass the job's own scope to the body", function ()
            local inner_done = false
            async.scope(function ()
                async.launch(function (scope)
                    scope:launch(function ()
                        async.delay(5)
                        inner_done = true
                    end)
                end):join()
                -- join waits for the job's children too
                assert.is_true(inner_done)
            end)
        end)

        it("report state", function ()
            async.scope(function ()
                local job = async.launch(function () async.delay(1000) end)
                assert.is_true(job:is_active())
                job:cancel()
                job:join()
                assert.is_true(job:is_cancelled())
                assert.is_true(job:is_completed())
                assert.is_false(job:is_active())
            end)
        end)
    end)

    describe("scope", function ()
        it("waits for its children", function ()
            local done = 0
            async.scope(function ()
                for i = 1, 3 do
                    async.launch(function ()
                        async.delay(i * 5)
                        done = done + 1
                    end)
                end
            end)
            assert.is_equal(3, done)
        end)

        it("cancels siblings when a child fails and raises its error", function ()
            local sibling_finished = false
            local err = error_of(function ()
                async.scope(function ()
                    async.launch(function ()
                        async.delay(1000)
                        sibling_finished = true
                    end)
                    async.launch(function ()
                        async.delay(5)
                        error({ kind = "Boom", message = "boom" })
                    end)
                end)
            end)
            assert.is_equal("Boom", err.kind)
            assert.is_false(sibling_finished)
        end)

        it("cancels children when the body fails", function ()
            local child_finished = false
            local err = error_of(function ()
                async.scope(function ()
                    async.launch(function ()
                        async.delay(1000)
                        child_finished = true
                    end)
                    error("body failed", 0)
                end)
            end)
            assert.is_equal("body failed", err)
            assert.is_false(child_finished)
        end)

        it("returns the body's values", function ()
            assert.is_equal(42, async.scope(function () return 42 end))
        end)
    end)

    describe("supervisor_scope", function ()
        it("isolates failing children", function ()
            local sibling_finished = false
            local failed
            async.supervisor_scope(function ()
                async.launch(function ()
                    async.delay(20)
                    sibling_finished = true
                end)
                failed = async.async(function ()
                    async.delay(5)
                    error("child failed", 0)
                end)
            end)
            assert.is_true(sibling_finished)
            assert.is_equal("child failed", error_of(function () failed:await() end))
        end)

        it("still fails when its own body fails", function ()
            assert.is_equal(
                "body",
                error_of(function ()
                    async.supervisor_scope(function () error("body", 0) end)
                end)
            )
        end)
    end)

    describe("cancellation through pcall", function ()
        it("is not caught by pcall", function ()
            local after_pcall, caught = false, false
            async.scope(function ()
                local job = async.launch(function ()
                    local ok = pcall(async.delay, 1000)
                    caught = not ok
                    after_pcall = true
                end)
                async.delay(5)
                job:cancel()
                job:join()
                assert.is_true(job:is_cancelled())
            end)
            assert.is_false(caught)
            assert.is_false(after_pcall)
        end)

        it("is not caught by nested pcall", function ()
            local reached = false
            async.scope(function ()
                local job = async.launch(function ()
                    pcall(function ()
                        pcall(function () async.delay(1000) end)
                        reached = true
                    end)
                    reached = true
                end)
                async.delay(5)
                job:cancel()
            end)
            assert.is_false(reached)
        end)

        it("skips the xpcall handler", function ()
            local handled, reached = false, false
            async.scope(function ()
                local job = async.launch(function ()
                    xpcall(async.delay, function (e)
                        handled = true
                        return e
                    end, 1000
                    )
                    reached = true
                end)
                async.delay(5)
                job:cancel()
            end)
            assert.is_false(handled)
            assert.is_false(reached)
        end)

        it("leaves ordinary errors to pcall, tables intact", function ()
            assert.is_equal("Mine", error_of(function () error({ kind = "Mine" }) end).kind)
            local ok2, msg = xpcall(error, function (e) return "handled " .. e end, "x", 0)
            assert.is_false(ok2)
            assert.is_equal("handled x", msg)
        end)

        it("is recognisable", function ()
            async.scope(function ()
                local seen
                local job = async.launch(function ()
                    async.finally(function () async.delay(1000) end, function () end)
                end)
                async.delay(5)
                job:cancel()
                job:join()
                seen = job:is_cancelled()
                assert.is_true(seen)
            end)
            assert.is_false(async.is_cancellation("Cancelled"))
        end)
    end)

    describe("with_timeout", function ()
        it("returns the body's values in time", function ()
            assert.is_equal("fast", async.with_timeout(100, function () return "fast" end))
        end)

        it("raises a catchable Timeout and cancels the body", function ()
            local finished = false
            local err = error_of(function ()
                async.with_timeout(10, function ()
                    async.launch(function ()
                        async.delay(1000)
                        finished = true
                    end)
                    async.delay(1000)
                    finished = true
                end)
            end)
            assert.is_equal("Timeout", err.kind)
            assert.matches("10 ms", err.message, 1, true)
            assert.is_false(finished)
        end)

        it("cannot be swallowed by pcall inside the body", function ()
            local reached = false
            local err = error_of(function ()
                async.with_timeout(10, function ()
                    pcall(async.delay, 1000)
                    reached = true
                end)
            end)
            assert.is_equal("Timeout", err.kind)
            assert.is_false(reached)
        end)
    end)

    describe("finally and on_cancel", function ()
        it("finally runs cleanup on success, failure and cancellation", function ()
            local log = {}
            async.finally(function () end, function () table.insert(log, "ok") end)
            pcall(async.finally, function () error("x") end, function () table.insert(log, "err") end)
            async.scope(function ()
                local job = async.launch(function ()
                    async.finally(function () async.delay(1000) end, function ()
                        async.delay(5) -- cleanup may suspend: it is not cancellable
                        table.insert(log, "cancelled")
                    end)
                end)
                async.delay(5)
                job:cancel()
            end)
            assert.are.same({ "ok", "err", "cancelled" }, log)
        end)

        it("finally returns the body's values", function ()
            assert.is_equal(7, async.finally(function () return 7 end, function () end))
        end)

        it("on_cancel handlers run LIFO when the scope is cancelled", function ()
            local log = {}
            async.scope(function ()
                local job = async.launch(function (scope)
                    scope:on_cancel(function () table.insert(log, 1) end)
                    scope:on_cancel(function ()
                        async.delay(1)
                        table.insert(log, 2)
                    end)
                    async.delay(1000)
                end)
                async.delay(5)
                job:cancel()
            end)
            assert.are.same({ 2, 1 }, log)
        end)

        it("on_cancel handlers do not run on success", function ()
            local ran = false
            async.scope(function (scope)
                scope:on_cancel(function () ran = true end)
            end)
            assert.is_false(ran)
        end)
    end)

    describe("Deferred", function ()
        it("await on a cancelled job raises JobCancelled", function ()
            async.scope(function ()
                local deferred = async.async(function () async.delay(1000) end)
                deferred:cancel()
                assert.is_equal("JobCancelled", error_of(function () deferred:await() end).kind)
            end)
        end)
    end)

    describe("channel", function ()
        it("delivers buffered values in order and ends iteration on close", function ()
            local ch = async.channel(4)
            for i = 1, 3 do
                ch:send(i)
            end
            ch:close()
            local got = {}
            for v in ch:iter() do
                table.insert(got, v)
            end
            assert.are.same({ 1, 2, 3 }, got)
            assert.is_true(ch:is_closed())
        end)

        it("rendezvous send waits for a receiver", function ()
            local log = {}
            async.scope(function ()
                local ch = async.channel()
                async.launch(function ()
                    ch:send("x")
                    table.insert(log, "sent")
                end)
                async.delay(10)
                table.insert(log, "receiving")
                table.insert(log, ch:receive())
            end)
            assert.are.same({ "receiving", "x", "sent" }, log)
        end)

        it("streams between jobs", function ()
            local sum = 0
            async.scope(function ()
                ---@type luastd.async.Channel<integer>
                local ch = async.channel(1)
                async.launch(function ()
                    for i = 1, 10 do
                        ch:send(i)
                    end
                    ch:close()
                end)
                for v in ch:iter() do
                    sum = sum + v
                end
            end)
            assert.is_equal(55, sum)
        end)

        it("raises ChannelClosed and rejects nil", function ()
            local ch = async.channel(1)
            ch:close()
            assert.is_equal("ChannelClosed", error_of(function () ch:receive() end).kind)
            assert.is_equal("ChannelClosed", error_of(function () ch:send(1) end).kind)
            ---@diagnostic disable-next-line: param-type-mismatch
            assert.is_equal("InvalidArgument", error_of(function () async.channel(1):send(nil) end).kind)
        end)

        it("receive is a cancellation point", function ()
            async.scope(function ()
                local ch = async.channel()
                local job = async.launch(function () ch:receive() end)
                async.delay(5)
                job:cancel()
                job:join()
                assert.is_true(job:is_cancelled())
            end)
        end)

        it("debounce emits the last value after quiet and flushes on close", function ()
            local got = {}
            async.scope(function ()
                local ch = async.channel(8)
                local quiet = ch:debounce(20)
                async.launch(function ()
                    ch:send(1)
                    ch:send(2)
                    async.delay(50)
                    ch:send(3)
                    ch:send(4)
                    ch:close()
                end)
                for v in quiet:iter() do
                    table.insert(got, v)
                end
            end)
            assert.are.same({ 2, 4 }, got)
        end)
    end)

    describe("channel cancellation", function ()
        it("cancel stops a blocked sender quietly", function ()
            local sent_after = false
            local job
            async.scope(function ()
                local ch = async.channel()
                job = async.launch(function ()
                    ch:send(1) -- waits for a receiver that never comes
                    sent_after = true
                end)
                async.delay(5)
                ch:cancel()
            end) -- no error reaches the scope
            assert.is_false(sent_after)
            assert.is_true(job:is_cancelled())
        end)

        it("later sends on a cancelled channel cancel the sender", function ()
            local job
            async.scope(function ()
                local ch = async.channel(4)
                ch:cancel()
                job = async.launch(function () ch:send(1) end)
            end)
            assert.is_true(job:is_cancelled())
        end)

        it("cancel drops buffered values and ends iteration", function ()
            local ch = async.channel(4)
            ch:send(1)
            ch:send(2)
            ch:cancel()
            assert.is_true(ch:is_closed())
            local got = {}
            for v in ch:iter() do
                table.insert(got, v)
            end
            assert.are.same({}, got)
        end)
    end)

    describe("produce", function ()
        it("closes the channel when the producer ends", function ()
            local got = {}
            async.scope(function ()
                local ch = async.produce(function (out)
                    for i = 1, 3 do
                        out:send(i)
                    end
                end)
                for v in ch:iter() do
                    table.insert(got, v)
                end
            end)
            assert.are.same({ 1, 2, 3 }, got)
        end)

        it("passes the producer's scope and honours the capacity", function ()
            local sent = 0
            async.scope(function ()
                local ch = async.produce(function (out, scope)
                    assert.is_true(scope:is_active())
                    for i = 1, 3 do
                        out:send(i)
                        sent = i
                    end
                end, 2)
                async.delay(10)
                assert.is_equal(2, sent) -- third send waits for room
                ch:cancel()
            end)
        end)

        it("is cancelled when the consumer cancels", function ()
            local cleaned = false
            async.scope(function ()
                local ch = async.produce(function (out)
                    async.finally(function ()
                        local i = 0
                        while true do
                            i = i + 1
                            out:send(i)
                        end
                    end, function () cleaned = true end)
                end)
                assert.is_equal(1, ch:receive())
                ch:cancel()
            end)
            assert.is_true(cleaned)
        end)

        it("a failing producer fails the scope", function ()
            local err = error_of(function ()
                async.scope(function ()
                    local ch = async.produce(function (out)
                        out:send(1)
                        error({ kind = "ProducerFailed" })
                    end)
                    for _ in ch:iter() do end
                end)
            end)
            assert.is_equal("ProducerFailed", err.kind)
        end)
    end)

    describe("each", function ()
        local function endless()
            return async.produce(function (out)
                local i = 0
                while true do
                    i = i + 1
                    out:send(i)
                end
            end)
        end

        it("stops when fn returns false and cancels the producer (no hang)", function ()
            local got = {}
            -- A regression would hang the scope on the endless producer; the
            -- timeout turns that into a failure.
            async.with_timeout(1000, function ()
                async.scope(function ()
                    endless():each(function (v)
                        table.insert(got, v)
                        return v < 3
                    end)
                end)
            end)
            assert.are.same({ 1, 2, 3 }, got)
        end)

        it("cancels the channel when fn raises", function ()
            local ch
            local err = error_of(function ()
                async.with_timeout(1000, function ()
                    async.scope(function ()
                        ch = endless()
                        ch:each(function () error({ kind = "Stop" }) end)
                    end)
                end)
            end)
            assert.is_equal("Stop", err.kind)
            assert.is_true(ch:is_closed())
        end)

        it("cancels the channel when the consumer is cancelled", function ()
            local ch
            async.with_timeout(1000, function ()
                async.scope(function ()
                    ch = endless()
                    local consumer = async.launch(function ()
                        ch:each(function () async.delay(1) end)
                    end)
                    async.delay(10)
                    consumer:cancel()
                end)
            end)
            assert.is_true(ch:is_closed())
        end)

        it("runs to the end of a closed channel", function ()
            local ch, got = async.channel(3), {}
            for i = 1, 3 do
                ch:send(i)
            end
            ch:close()
            ch:each(function (v) table.insert(got, v) end)
            assert.are.same({ 1, 2, 3 }, got)
        end)

        it("iter with an early break needs cancel to release the producer", function ()
            async.with_timeout(1000, function ()
                async.scope(function ()
                    local ch = endless()
                    for v in ch:iter() do
                        if v == 2 then break end
                    end
                    ch:cancel() -- without this the scope would wait forever
                end)
            end)
        end)
    end)

    describe("debounce and throttle", function ()
        it("debounce runs only the last call", function ()
            local calls = {}
            async.scope(function ()
                local save = async.debounce(20, function (v) table.insert(calls, v) end)
                save(1)
                save(2)
                async.delay(5)
                save(3)
            end)
            assert.are.same({ 3 }, calls)
        end)

        it("throttle runs the leading call per window", function ()
            local calls = {}
            local hit = async.throttle(30, function (v) table.insert(calls, v) end)
            hit(1)
            hit(2)
            async.delay(40)
            hit(3)
            hit(4)
            assert.are.same({ 1, 3 }, calls)
        end)
    end)

    describe("context", function ()
        it("is_active is true outside cancellation", function ()
            assert.is_true(async.is_active())
        end)

        it("rejects bad arguments", function ()
            ---@diagnostic disable-next-line: param-type-mismatch
            assert.is_equal("InvalidArgument", error_of(function () async.launch(42) end).kind)
            assert.is_equal("InvalidArgument", error_of(function () async.delay(-1) end).kind)
        end)
    end)
end)
