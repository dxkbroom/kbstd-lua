---@diagnostic disable: undefined-global
-- neo-tree source `luastd`: one node per module with its implementation,
-- definition and spec. Files that do not exist yet are dimmed; opening one
-- offers to create it. Registered from `.lazy.lua` as `luastd_dev.neotree`.

local project = require("luastd_dev.project")
local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")
local highlights = require("neo-tree.ui.highlights")
local cc = require("neo-tree.sources.common.commands")
local common_components = require("neo-tree.sources.common.components")
local utils = require("neo-tree.utils")

local NAME = "luastd"

local M = { name = NAME, display_name = " 󰢱 luastd " }

local function module_id(name)
    return "luastd-module:" .. name
end

local function items()
    local list = {}
    for _, module in ipairs(project.modules()) do
        local children = {}
        local present = 0
        for _, f in ipairs(module.files) do
            present = present + (f.exists and 1 or 0)
            children[#children + 1] = {
                id = f.path,
                name = vim.fn.fnamemodify(f.path, ":t"),
                path = f.path,
                type = "file",
                extra = { file = f, role = f.role, missing = not f.exists }
            }
        end
        list[#list + 1] = {
            id = module_id(module.name),
            name = module.name,
            path = project.root,
            type = "directory",
            loaded = true,
            children = children,
            extra = { module = module, present = present, total = #module.files }
        }
    end
    return list
end

---@param state          table
---@param path           string?
---@param path_to_reveal string?
---@param callback       function?
function M.navigate(state, path, path_to_reveal, callback)
    state.path = project.root
    local list = items()
    local expand = {}
    if not state.luastd_expanded_once then
        -- every module open the first time; later renders keep the user's folds
        state.luastd_expanded_once = true
        expand = vim.tbl_map(function (item) return item.id end, list)
    end
    if path_to_reveal then
        for _, item in ipairs(list) do
            for _, child in ipairs(item.children) do
                if child.id == path_to_reveal then
                    expand[#expand + 1] = item.id
                end
            end
        end
    end
    state.default_expanded_nodes = expand
    renderer.show_nodes(list, state)
    state.default_expanded_nodes = nil
    if path_to_reveal and state.tree and state.tree:get_node(path_to_reveal) then
        renderer.focus_node(state, path_to_reveal)
    end
    if callback then
        vim.schedule(callback)
    end
end

---@param config        table
---@param global_config table
function M.setup(config, global_config) end

-- Components ---------------------------------------------------------------

local components = vim.tbl_extend("force", {}, common_components)

--- File name, dimmed when the file does not exist yet.
components.luastd_name = function (config, node, state)
    local missing = node.extra and node.extra.missing
    return {
        text = node.name,
        highlight = missing and highlights.DIM_TEXT
            or (node.type == "directory" and highlights.DIRECTORY_NAME or highlights.FILE_NAME)
    }
end

--- `implementation` / `definition` / `spec` after a file, or `n/3` after a module.
components.luastd_info = function (config, node, state)
    local extra = node.extra or {}
    local text
    if node.type == "directory" then
        text = ("%s  %d/%d"):format(extra.module.crate, extra.present, extra.total)
    else
        text = project.ROLE_LABEL[extra.role] .. (extra.missing and " (missing)" or "")
    end
    return { text = "  " .. text, highlight = highlights.DIM_TEXT }
end

M.components = components

-- Commands -----------------------------------------------------------------

local commands = {}
local refresh = utils.wrap(manager.refresh, NAME)
commands.refresh = refresh

--- Open a file node with `opener`, offering to create it first when missing.
local function open_with(opener)
    return function (state)
        local node = state.tree:get_node()
        local f = node and node.extra and node.extra.file
        if f and not f.exists then
            return project.create(f, function ()
                refresh(state)
                opener(state)
            end)
        end
        opener(state)
    end
end

commands.open = open_with(function (state) cc.open(state) end)
commands.open_split = open_with(function (state) cc.open_split(state) end)
commands.open_vsplit = open_with(function (state) cc.open_vsplit(state) end)
commands.open_tabnew = open_with(function (state) cc.open_tabnew(state) end)

--- Open the module under the cursor (or the file's module) in the 3-window layout.
commands.luastd_layout = function (state)
    local node = state.tree:get_node()
    if not node then
        return
    end
    if node.type ~= "directory" then
        node = state.tree:get_node(node:get_parent_id())
    end
    project.layout(node.extra.module)
end

cc._add_common_commands(commands)
M.commands = commands

M.default_config = {
    renderers = {
        directory = {
            { "indent" },
            { "icon" },
            { "luastd_name" },
            { "luastd_info" }
        },
        file = {
            { "indent" },
            { "icon" },
            { "luastd_name" },
            { "luastd_info" }
        }
    },
    window = {
        mappings = {
            ["v"] = "luastd_layout",
            ["R"] = "refresh"
        }
    }
}

return M
