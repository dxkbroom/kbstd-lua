//! `luastd.async`: structured concurrency in a runtime (ADR 0003, 0005).

mod common;

use luastd_runtime::mlua::{Function, Lua, Result};
use luastd_runtime::{Runtime, cancel_jobs};

fn runtime() -> Runtime {
    Runtime::builder().build().unwrap()
}

#[test]
fn async_spec() {
    common::run_spec(
        &runtime(),
        "luastd_async_spec.lua",
        include_str!("lua/luastd_async_spec.lua"),
    );
}

#[test]
fn run_waits_for_jobs_launched_by_the_main_chunk() {
    let rt = runtime();
    rt.run(async |lua| {
        lua.load(
            r#"
            local async = require("luastd.async")
            async.launch(function () async.delay(20); done = true end)
            "#,
        )
        .exec_async()
        .await
    })
    .unwrap();
    assert!(rt.lua().globals().get::<bool>("done").unwrap());
}

#[test]
fn root_jobs_fail_independently() {
    let rt = runtime();
    rt.run(async |lua| {
        lua.load(
            r#"
            local async = require("luastd.async")
            async.launch(function () async.delay(5); error("lone failure") end)
            async.launch(function () async.delay(20); survived = true end)
            "#,
        )
        .exec_async()
        .await
    })
    .unwrap();
    assert!(rt.lua().globals().get::<bool>("survived").unwrap());
}

#[test]
fn cancel_jobs_stops_background_work() {
    let rt = runtime();
    let ticks: i64 = rt
        .run(async |lua: Lua| -> Result<i64> {
            lua.load(
                r#"
                local async = require("luastd.async")
                ticks = 0
                async.launch(function ()
                    async.finally(function ()
                        while true do async.delay(1); ticks = ticks + 1 end
                    end, function () stopped = true end)
                end)
                "#,
            )
            .exec_async()
            .await?;
            tokio::time::sleep(std::time::Duration::from_millis(20)).await;
            cancel_jobs(&lua);
            lua.globals().get("ticks")
        })
        .unwrap();
    assert!(ticks > 0);
    assert!(rt.lua().globals().get::<bool>("stopped").unwrap());
}

#[test]
fn a_failing_main_cancels_launched_jobs() {
    let rt = runtime();
    let result: Result<()> = rt.run(async |lua| {
        lua.load(
            r#"
            local async = require("luastd.async")
            async.launch(function ()
                async.finally(function () async.delay(60000) end, function () cleaned = true end)
            end)
            async.delay(5) -- let the job start; an unstarted job never runs its body
            error("main failed")
            "#,
        )
        .exec_async()
        .await
    });
    assert!(result.unwrap_err().to_string().contains("main failed"));
    assert!(rt.lua().globals().get::<bool>("cleaned").unwrap());
}

#[test]
fn launching_needs_run() {
    let rt = runtime();
    let error = rt
        .lua()
        .load(r#"require("luastd.async").launch(function () end)"#)
        .exec()
        .unwrap_err();
    assert!(error.to_string().contains("Runtime::run"), "{error}");
}

#[test]
fn pcall_is_replaced_but_still_catches_errors() {
    let rt = runtime();
    let (ok, kind): (bool, String) = rt
        .lua()
        .load(r#"local ok, e = pcall(error, { kind = "K" }); return ok, e.kind"#)
        .eval()
        .unwrap();
    assert!(!ok);
    assert_eq!(kind, "K");
    // The replacement is a Lua function, not the C builtin.
    let pcall: Function = rt.lua().globals().get("pcall").unwrap();
    assert!(pcall.info().what != "C");
}

#[test]
fn cancellation_survives_a_rust_frame() {
    let rt = runtime();
    let call = rt
        .lua()
        .create_async_function(|_, f: Function| async move { f.call_async::<()>(()).await })
        .unwrap();
    rt.lua().globals().set("call", call).unwrap();
    let (reached, cancelled): (bool, bool) = rt
        .run(async |lua| {
            lua.load(
                r#"
                local async = require("luastd.async")
                local reached = false
                local job = async.launch(function ()
                    -- `call` is Rust: the cancellation crosses it twice.
                    pcall(call, function () async.delay(1000) end)
                    reached = true
                end)
                async.delay(5)
                job:cancel()
                job:join()
                return reached, job:is_cancelled()
                "#,
            )
            .eval_async()
            .await
        })
        .unwrap();
    assert!(!reached, "pcall swallowed a cancellation that crossed Rust");
    assert!(cancelled);
}
