//! `luastd_test` and the kotlinx.coroutines test ports.
//!
//! `luastd_test_spec.lua` tests the harness itself. Each file in
//! `tests/lua/kotlinx/` ports one kotlinx.coroutines 1.11.0 test class
//! (`<Class>.lua`, see AGENTS.md) and runs as its own test here, in a fresh
//! runtime, so `cargo test --test kotlinx WithTimeoutTest` runs one class.

mod common;

use luastd_runtime::Runtime;

fn runtime() -> Runtime {
    Runtime::builder().build().unwrap()
}

#[test]
fn luastd_test_spec() {
    common::run_spec(
        &runtime(),
        "luastd_test_spec.lua",
        include_str!("lua/luastd_test_spec.lua"),
    );
}

/// One `#[test]` per ported class, named after it.
macro_rules! kotlinx {
    ($($class:ident),* $(,)?) => {
        const CLASSES: &[&str] = &[$(stringify!($class)),*];
        $(
            #[test]
            #[allow(non_snake_case)]
            fn $class() {
                common::run_spec(
                    &runtime(),
                    concat!("kotlinx/", stringify!($class), ".lua"),
                    include_str!(concat!("lua/kotlinx/", stringify!($class), ".lua")),
                );
            }
        )*
    };
}

kotlinx! {
    WithTimeoutTest,
}

#[test]
fn every_port_is_listed() {
    let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/lua/kotlinx");
    let mut files: Vec<String> = std::fs::read_dir(dir)
        .map(|entries| {
            entries
                .filter_map(|entry| {
                    let name = entry.unwrap().file_name().into_string().unwrap();
                    name.strip_suffix(".lua").map(str::to_owned)
                })
                .collect()
        })
        .unwrap_or_default();
    files.sort();
    let mut listed: Vec<&str> = CLASSES.to_vec();
    listed.sort_unstable();
    assert_eq!(
        files, listed,
        "add new ports to `kotlinx!` in tests/kotlinx.rs"
    );
}
