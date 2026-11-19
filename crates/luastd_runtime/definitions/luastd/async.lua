---@meta luastd.async

--- Structured concurrency, after kotlinx.coroutines.
---
--- Every coroutine runs inside a scope. A scope completes only when its
--- children have, and cancelling it cancels them. Jobs launched outside any
--- scope belong to the implicit root scope of `Runtime::run`, which is a
--- supervisor and waits for them before `run` returns.
---
--- Cancellation is cooperative: it is delivered at suspension points
--- (`delay`, `join`, `await`, `send`, `receive`, permission prompts, ...) as an
--- error that the runtime's `pcall` and `xpcall` rethrow instead of catching
--- (ADR 0005). Use `async.finally` or `scope:on_cancel` for cleanup.
---@class luastd.async
local async = {}

--- Error raised by `with_timeout` when the time runs out; catchable.
---@class luastd.TimeoutError: luastd.Error
---@field kind "Timeout"

--- Error raised by `Deferred:await` when the job was cancelled; catchable.
---@class luastd.JobCancelledError: luastd.Error
---@field kind "JobCancelled"

--- Error raised by `Channel:send` on a closed channel, and by
--- `Channel:receive` on a closed, empty one.
---@class luastd.ChannelClosedError: luastd.Error
---@field kind "ChannelClosed"

--- A structured-concurrency boundary; passed to scope and job bodies.
---@class luastd.async.Scope
local Scope = {}

--- Launch a child job in this scope, whichever coroutine calls it.
---@param body fun(scope: luastd.async.Scope)
---@return luastd.async.Job
function Scope:launch(body) end

--- Start a child job in this scope that produces values.
---@generic T...
---@param body fun(scope: luastd.async.Scope): T...
---@return luastd.async.Deferred<T...>
function Scope:async(body) end

--- Cancel this scope and its children.
function Scope:cancel() end

--- Whether this scope is neither completed nor cancelled.
---@return boolean
function Scope:is_active() end

--- Whether this scope was cancelled.
---@return boolean
function Scope:is_cancelled() end

--- Whether this scope and its children have finished.
---@return boolean
function Scope:is_completed() end

--- Run `handler` when this scope ends without completing normally (cancelled,
--- timed out or failed). Handlers run last-registered first, cannot be
--- cancelled, and their errors are ignored.
---@param handler fun()
function Scope:on_cancel(handler) end

--- A handle to a launched coroutine; also the scope its body receives.
---@class luastd.async.Job: luastd.async.Scope
local Job = {}

--- Wait until the job and its children have finished, however they ended.
---@async
function Job:join() end

--- A job that produces the values `T...`, the body's return values; `await`
--- returns them all.
---@class luastd.async.Deferred<T...>: luastd.async.Job
local Deferred = {}

--- Wait for the value. Re-raises the job's error; raises `JobCancelled` when
--- the job was cancelled.
---@async
---@return T...
function Deferred:await() end

--- Launch `body` as a child of the current scope.
---
--- In a non-supervisor scope, a failure cancels the scope and its other
--- children. In a supervisor scope, an unhandled failure is reported on stderr.
---@param body fun(scope: luastd.async.Scope)
---@return luastd.async.Job
function async.launch(body) end

--- Start `body` as a child of the current scope; collect it with `await`.
---@generic T...
---@param body fun(scope: luastd.async.Scope): T...
---@return luastd.async.Deferred<T...>
function async.async(body) end

--- Prefix form of `job:join()`.
---@async
---@param job luastd.async.Job
function async.join(job) end

--- Prefix form of `deferred:await()`: every value the body returned.
---@async
---@generic T...
---@param deferred luastd.async.Deferred<T...>
---@return T...
function async.await(deferred) end

--- Await each deferred in argument order and return the first value of each,
--- so there is one result per argument even when a body returns several.
--- Raises the first failure reached in that order.
---@async
---@param ... luastd.async.Deferred
---@return any ...
function async.await_all(...) end

--- Run `body` in a new scope and wait for its children. A failing child
--- cancels the scope; its error is raised here. Returns the body's values.
---@async
---@generic T...
---@param body fun(scope: luastd.async.Scope): T...
---@return T...
function async.scope(body) end

--- Like `scope`, but children fail independently of each other and the scope.
---@async
---@generic T...
---@param body fun(scope: luastd.async.Scope): T...
---@return T...
function async.supervisor_scope(body) end

--- Run `body` in a scope that is cancelled after `ms` milliseconds; raises
--- `Timeout` (a catchable `luastd.Error`) when it is.
---@async
---@generic T...
---@param ms   number
---@param body fun(scope: luastd.async.Scope): T...
---@return T...
function async.with_timeout(ms, body) end

--- Suspend for `ms` milliseconds.
---@async
---@param ms number
function async.delay(ms) end

--- Let other coroutines run; a cancellation point.
---@async
function async.yield() end

--- Whether the current coroutine's scope has not been cancelled.
---@return boolean
function async.is_active() end

--- The current scope (the root scope outside any job or scope).
---@return luastd.async.Scope
function async.current() end

--- Whether `err` is the cancellation error.
---@param err any
---@return boolean
function async.is_cancellation(err) end

--- Run `body`, then `cleanup` however `body` ended, including cancellation.
--- `cleanup` cannot be cancelled. Errors from `body` win over `cleanup`'s.
---@async
---@generic T...
---@param body    fun(): T...
---@param cleanup fun()
---@return T...
function async.finally(body, cleanup) end

--- A channel between coroutines carrying values of type `T`; `send` and
--- `receive` suspend. Plain `luastd.async.Channel` carries anything; annotate
--- the element type where it helps:
---
--- ```lua
--- ---@type luastd.async.Channel<string>
--- local lines = async.channel(16)
--- ```
---
--- Element types are not checked at runtime.
---@class luastd.async.Channel<T = any>
local Channel = {}

--- A channel with room for `cap` values (default 0: each `send` waits for a
--- `receive`).
---@param cap? integer
---@return luastd.async.Channel
function async.channel(cap) end

--- Send a non-nil value, waiting for room. On a cancelled channel the sending
--- coroutine is cancelled quietly: its scope sees no error.
---@async
---@param value T
function Channel:send(value) end

--- Receive the next value, waiting for one. Values sent before `close` are
--- still delivered.
---@async
---@return T
function Channel:receive() end

--- Close the channel; waiting receivers see the end of the stream.
function Channel:close() end

--- Close the channel, drop buffered values, and cancel pending and future
--- senders, including the producer job of a `produce` channel. Call it when a
--- consumer stops early.
function Channel:cancel() end

--- Whether `close` or `cancel` has been called.
---@return boolean
function Channel:is_closed() end

--- Iterate values until the channel is closed and drained.
---
--- Leaving the loop early (`break`, `return`, an error) does **not** cancel
--- the producer: it waits on its next `send`, and its scope waits for it. Use
--- `each`, or call `cancel` after the loop.
---@async
---@return fun(): T?
function Channel:iter() end

--- Call `fn` with each value until the channel is closed and drained, or `fn`
--- returns `false`. However it ends, including an error or cancellation, the
--- channel is cancelled, so its producer stops.
---@async
---@param fn fun(value: T): boolean?
function Channel:each(fn) end

--- A channel that emits a value once `ms` milliseconds pass without a newer
--- one, and the last value when this channel closes. Runs a job in the
--- current scope until this channel closes.
---@param ms number
---@return luastd.async.Channel<T>
function Channel:debounce(ms) end

--- Run `body` as a producer job in the current scope and return its channel.
--- The channel is closed when `body` ends, and the producer is cancelled when
--- the consumer calls `cancel` (or `each` ends).
---@generic T
---@param body async fun(channel: luastd.async.Channel<T>, scope: luastd.async.Scope)
---@param cap? integer
---@return luastd.async.Channel<T>
function async.produce(body, cap) end

--- Wrap `fn` so that only the last call in a burst runs, `ms` milliseconds
--- after it, as a job in the scope that created the wrapper. A call that has
--- already started is not cancelled.
---@generic F: function
---@param ms number
---@param fn F
---@return fun(...): luastd.async.Job
function async.debounce(ms, fn) end

--- Wrap `fn` so that it runs at most once per `ms` milliseconds; calls in
--- between are dropped (leading edge).
---@generic F: function
---@param ms number
---@param fn F
---@return F
function async.throttle(ms, fn) end

return async
