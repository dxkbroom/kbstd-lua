---
status: accepted
---

# Waiting is spelled async.await and async.join; try_await and try_scope recover

ADR 0007 kept `d:await()` and `job:join()` canonical, with `async.await(d)` and
`async.join(job)` as prefix forms. In practice recovering from a failure read as
`pcall(d.await, d)` and `pcall(async.scope, fn)`. The methods are removed:
`async.await(d)` and `async.join(job)` are the only way to wait, and two `try_*`
forms return failures instead of raising them. This is a breaking change.

- `async.try_await(d)` returns `true, values...` when `d` completed, or
  `false, err` where `err` is the job's `luastd.Error` or a `JobCancelled` error
  when `d` itself was cancelled.
- `async.try_scope(fn)` runs `fn` like `async.scope(fn)` and returns
  `true, values...`, or `false, err` when the body or one of its children
  failed. The failure stays inside, so the caller's scope is not cancelled.
- Neither catches cancellation of the caller (ADR 0005). Both raise it, as
  `async.await` does, even when the awaited job has already finished.
- There is no `try_join`: `async.join` never raises the job's failure, only the
  caller's cancellation, which a `try_*` form does not catch, so it would be a
  pure synonym.

## A failing child cancels its scope before try_await returns

In a non-supervisor scope, a child's failure cancels the scope that owns it, and
the caller's cancellation wins over the awaited result (as in Kotlin, where
the parent is already cancelled when its `catch` runs). So `try_await` on a
failing child of the caller's own scope raises the cancellation, and the
enclosing scope later raises the child's error; it does not return
`false, err`. To recover, give the child its own scope:

```lua
local ok, orders = async.try_scope(function () return api.orders(id) end)
if not ok then log(orders.kind) end -- `orders` is the error here
```

`try_await` returns the failure when the job's scope is not the caller's, such
as a child of a `supervisor_scope` or of another scope.

## Considered Options

- **Keep the methods next to `try_await`:** two spellings of the same wait
  again, and the method cannot be passed as a value.
- **`async.pawait` and `async.pscope`:** `p*` reads as `pcall`, which would
  suggest the cancellation is caught too; `try_*` already names this shape in
  `AGENTS.md`.
- **Let `try_await` recover a failing child of its own scope:** would need the
  child's failure to stop cancelling its parent, which breaks structured
  concurrency for every other child.

## Consequences

- Job, Deferred and Scope keep `cancel`, `is_active`, `is_cancelled`,
  `is_completed`, `on_cancel`, `launch` and `async` as methods; only the waits
  moved.
- `async.await`, `async.join`, `async.try_await` and `async.await_all` raise
  `InvalidArgument` for a value that is not a job (ADR 0007 follow-up 7).
