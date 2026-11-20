---@diagnostic disable: undefined-global
-- Neovim dev helpers for this checkout, loaded by `.lazy.lua`:
--
-- - a `require` searcher that resolves `luastd` and `luastd.<module>` from the
--   cdylib built here for Neovim's LuaJIT (`mise run nvim:build`), instead of
--   any copy installed from the remote;
-- - `:Luastd [module] [example]`, which lists and runs the examples in
--   `.nvim/examples.lua`.

local M = {}

local function lib_path(root)
    local ext = vim.fn.has("mac") == 1 and "dylib" or "so"
    return root .. "/target/nvim/release/libluastd_lua." .. ext
end

local HINT = "run `mise run nvim:build` (or `:Lazy build luastd`), then restart Neovim"

--- Resolve `luastd` and `luastd.*` from this checkout's cdylib. Each module has
--- its own `luaopen_luastd[_<module>]` entry point in the same library.
---@param lib string
local function install_searcher(lib)
    local loaders = package.loaders or package.searchers
    table.insert(loaders, 2, function (name)
        if name ~= "luastd" and not name:match("^luastd%.") then
            return nil
        end
        if not vim.uv.fs_stat(lib) then
            return ("\n\tno local luastd build at %s; %s"):format(lib, HINT)
        end
        local open, err = package.loadlib(lib, "luaopen_" .. name:gsub("%.", "_"))
        return open or ("\n\t" .. tostring(err))
    end)
end

---@param examples table[]
---@param module   string
local function find_module(examples, module)
    for _, entry in ipairs(examples) do
        if entry.module == module then
            return entry
        end
    end
end

---@param entry table
---@param name  string
local function find_example(entry, name)
    for _, example in ipairs(entry.examples) do
        if example.name == name then
            return example
        end
    end
end

---@param chunks [string, string?][]
local function echo(chunks)
    vim.api.nvim_echo(chunks, true, {})
end

local function list(examples, only)
    local chunks = {}
    for _, entry in ipairs(examples) do
        if not only or entry.module == only then
            chunks[#chunks + 1] = { entry.title .. "\n", "Title" }
            for _, example in ipairs(entry.examples) do
                chunks[#chunks + 1] = { ("  %-12s"):format(example.name), "Identifier" }
                chunks[#chunks + 1] = { example.desc .. "\n" }
            end
        end
    end
    chunks[#chunks + 1] = { "Run one with :Luastd <module> <example>", "Comment" }
    echo(chunks)
end

--- Run an example with a `print` that collects its output, and echo the source
--- followed by the output (also kept in `:messages`).
local function run(entry, example)
    local out = {}
    local env = setmetatable({
        print = function (...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[i] = tostring((select(i, ...)))
            end
            out[#out + 1] = table.concat(parts, "\t")
        end
    }, { __index = _G })
    local chunk, err = loadstring(example.code, ("=%s/%s"):format(entry.module, example.name))
    local ok = chunk ~= nil
    if chunk then
        ok, err = pcall(setfenv(chunk, env))
    end
    local chunks = {
        { ("-- %s %s: %s\n"):format(entry.title, example.name, example.desc), "Title" },
        { vim.trim(example.code) .. "\n", "Comment" }
    }
    for _, line in ipairs(out) do
        chunks[#chunks + 1] = { "=> " .. line .. "\n" }
    end
    if not ok then
        chunks[#chunks + 1] = { "error: " .. tostring(err) .. "\n", "ErrorMsg" }
    end
    echo(chunks)
    return ok
end

---@param opts { root: string }
function M.setup(opts)
    -- once per session: `dofile` returns a fresh module each time
    if vim.g.luastd_dev_root then
        return
    end
    local root = opts.root
    vim.g.luastd_dev_root = root
    local lib = lib_path(root)
    install_searcher(lib)
    if not vim.uv.fs_stat(lib) then
        vim.schedule(function ()
            vim.notify(("luastd: no local build at %s; %s"):format(lib, HINT), vim.log.levels.WARN)
        end)
    end

    local examples = dofile(root .. "/.nvim/examples.lua")

    vim.api.nvim_create_user_command(
        "Luastd",
        function (cmd)
            local module, name = cmd.fargs[1], cmd.fargs[2]
            if not module then
                return list(examples)
            end
            local entry = find_module(examples, module)
            if not entry then
                return vim.notify("luastd: unknown module " .. module, vim.log.levels.ERROR)
            end
            if not name then
                return list(examples, module)
            end
            local example = find_example(entry, name)
            if not example then
                return vim.notify(("luastd: %s has no example %s"):format(module, name), vim.log.levels.ERROR)
            end
            run(entry, example)
        end,
        {
            nargs = "*",
            desc = "List or run luastd examples against the local build",
            complete = function (arg_lead, line)
                local args = vim.split(vim.trim(line), "%s+")
                -- args[1] is the command; completing the last word when it is partial
                local index = #args - (arg_lead == "" and 0 or 1)
                local items = {}
                if index == 1 then
                    for _, entry in ipairs(examples) do
                        items[#items + 1] = entry.module
                    end
                elseif index == 2 then
                    local entry = find_module(examples, args[2])
                    for _, example in ipairs(entry and entry.examples or {}) do
                        items[#items + 1] = example.name
                    end
                end
                return vim.tbl_filter(function (item)
                    return vim.startswith(item, arg_lead)
                end, items)
            end
        }
    )
end

M.run = run
M.find_module = find_module
M.find_example = find_example

return M
