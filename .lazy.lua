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

return {}
