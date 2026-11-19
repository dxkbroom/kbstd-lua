//! Runs `tests/lua/*_spec.lua` inside a runtime with the busted-shaped harness.

#![allow(dead_code)]

use luastd_runtime::Runtime;
use luastd_runtime::mlua::{Function, Result};

const HARNESS: &str = include_str!("../lua/harness.lua");

/// Run one spec file on `rt`; panics with every failing test.
pub fn run_spec(rt: &Runtime, name: &str, source: &str) -> usize {
    let (passed, failures): (usize, Vec<String>) = rt
        .run(async |lua| -> Result<(usize, Vec<String>)> {
            let run: Function = lua.load(HARNESS).set_name("=harness").eval()?;
            lua.load(source)
                .set_name(format!("@tests/lua/{name}"))
                .exec_async()
                .await?;
            run.call_async(()).await
        })
        .unwrap_or_else(|error| panic!("{name}: {error}"));
    assert!(failures.is_empty(), "{name}:\n{}", failures.join("\n"));
    assert!(passed > 0, "{name}: no tests ran");
    passed
}
