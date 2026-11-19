---@diagnostic disable: undefined-global
-- Project-local lazy.nvim spec (picked up automatically through `local_spec`;
-- Neovim asks once to trust this file via `vim.secure`).
--
-- Points emmylua_ls and luafmt at our emmylua-analyzer-rust fork build
-- (branch feat/builtin-busted) instead of the user-level Mason install.
-- TODO: drop this once the fork is consumed from a remote source (see mise.toml).
-- Rebuild the binaries with `mise run fork:build`.

local here = vim.fs.find(".lazy.lua", { upward = true, path = vim.uv.cwd() })[1]
local root = vim.fs.dirname(here)
local bin = vim.fs.normalize(root .. "/../emmylua-analyzer-rust/target/release")
local emmylua_ls = bin .. "/emmylua_ls"
local luafmt = bin .. "/luafmt"

if vim.fn.executable(emmylua_ls) == 1 then
    -- vim.lsp.config() overrides the runtime lsp/emmylua_ls.lua defaults; the
    -- user config still calls vim.lsp.enable("emmylua_ls") as usual.
    vim.lsp.config("emmylua_ls", { cmd = { emmylua_ls } })
else
    vim.notify(
        ("luastd: fork emmylua_ls not found at %s, using the default; run `mise run fork:build`"):format(emmylua_ls),
        vim.log.levels.WARN
    )
end

if vim.fn.executable(luafmt) == 1 then
    -- Runs after init, once the user config has set up conform.
    vim.schedule(function ()
        local ok, conform = pcall(require, "conform")
        if ok then
            conform.formatters.luafmt = vim.tbl_extend("force", conform.formatters.luafmt or {}, {
                command = luafmt,
            })
        end
    end)
end

-- rust-analyzer: check with one Lua version and the effect-module features, so
-- `#[cfg(feature = "env")]` code is analysed. No `vendored`: luastd_lua always
-- enables mlua's `module`, which conflicts with `vendored` in a workspace check.
-- Editor-only; `mise run build`/`test` pass their own features.
vim.lsp.config("rust_analyzer", {
    settings = {
        ["rust-analyzer"] = {
            cargo = {
                features = { "luastd_runtime/env", "luastd_runtime/luajit52" },
            },
        },
    },
})

-- luastd itself, for Neovim's LuaJIT: the user config installs it from the
-- remote (github.com/dxkbroom/kbstd-lua, now dxkbroom/luastd) as the lazy
-- plugin `kbstd-lua`. In this checkout, point that plugin at the checkout and
-- load `require("luastd")` / `require("luastd.<module>")` from the cdylib built
-- here. Build it with `mise run nvim:build` (luajit, not luajit52: Neovim's
-- LuaJIT has no 5.2 compat) and restart Neovim after a rebuild.
-- `:Luastd [module] [example]` lists and runs the examples in `.nvim/`.
---@type LazyPluginSpec
local Luastd = {
    url = "https://github.com/dxkbroom/kbstd-lua.git",
    name = "kbstd-lua",
    dir = root,
    build = function ()
        local result = vim.system({ "mise", "run", "nvim:build" }, { cwd = root, text = true }):wait()
        if result.code ~= 0 then
            error("luastd: mise run nvim:build failed\n" .. (result.stderr or ""))
        end
    end,
    config = function ()
        dofile(root .. "/.nvim/luastd.lua").setup({ root = root })
    end,
}

return { Luastd }
