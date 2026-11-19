---
status: accepted
---

# luastd_runtime owns a current-thread tokio runtime and a LocalSet

Effect modules need timers, a process reactor and non-blocking IO, and mlua's
async support needs a local executor because `Lua` is not `Send` (ADR 0002). So
`luastd_runtime` owns a tokio current-thread runtime plus a `LocalSet`, and the
host's own main loop runs as one more local task on it:
`rt.run(async |lua| { ... })`. The main chunk runs in an implicit root scope, so
`async.launch` works at the top level without ceremony.

## Considered Options

- **Host brings its own executor:** maximum flexibility, but every host would
  rewire the `LocalSet`, the root scope, timers and cancellation itself, and get
  it subtly wrong. A lower-level drive API can be added later without breaking
  `run`.
- **No tokio (smol or a hand-rolled executor):** lighter, but we would still need
  a reactor for timers and child processes, and deno_permissions' ecosystem and
  ratatui/crossterm's `EventStream` already sit on tokio.

## Consequences

- An interactive host (for example `tinyvi`) puts its event loop inside `run`
  as a `tokio::select!` over input, redraw ticks and messages from Lua; plugin
  coroutines run between iterations on the same thread.
- A host that already runs a multi-thread tokio runtime gives luastd its own
  thread and talks to it over channels.
- Blocking work (`*_sync`, CPU-heavy calls) uses `spawn_blocking` and hands the
  result back to the Lua thread.
