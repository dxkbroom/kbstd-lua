//! A minimal host: build a runtime with only the floor, run a chunk on the
//! executor, and publish annotations for an editor.
//!
//! ```sh
//! cargo run -p luastd_runtime --example hello --features luajit52,vendored -- [OUT_DIR]
//! ```

use std::path::PathBuf;
use std::time::Duration;

use luastd_runtime::Runtime;
use luastd_runtime::annotations;
use luastd_runtime::mlua;

fn main() -> mlua::Result<()> {
    let out = std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| std::env::temp_dir().join("luastd-hello"));

    let rt = Runtime::builder().build()?;
    let greeting: String = rt.run(async |lua| {
        // The host loop would `select!` here; a timer stands in for it.
        tokio::time::sleep(Duration::from_millis(10)).await;
        lua.load(
            r#"
            local path = require("luastd.path")
            local formatx = require("luastd.formatx")
            local semver = require("luastd.semver")
            assert(io == nil and os.execute == nil, "sandbox leaked")
            return formatx.format("hello from {} on {} (5.2 compat: {}, stub: {})",
                semver.parse(require("luastd").version),
                _VERSION,
                table.pack ~= nil,
                path.new("library") / "luastd" / "path.lua")
            "#,
        )
        .set_name("=hello")
        .eval_async()
        .await
    })?;
    println!("{greeting}");

    let library = out.join("library");
    let written = annotations::write(&library).map_err(mlua::Error::external)?;
    annotations::merge_emmyrc(out.join(".emmyrc.json"), &library).map_err(mlua::Error::external)?;
    println!(
        "wrote {} stubs and .emmyrc.json under {}",
        written.len(),
        out.display()
    );
    Ok(())
}
