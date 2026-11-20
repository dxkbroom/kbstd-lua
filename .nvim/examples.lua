-- Examples for `:Luastd <module> <example>`: one list per pure (floor)
-- module. `code` runs with a `print` that collects its output.
return {
    {
        module = "luastd",
        title = 'require("luastd")',
        examples = {
            {
                name = "version",
                desc = "the loaded build's version",
                code = [[
local luastd = require("luastd")
print("luastd " .. luastd.version)
]]
            },
            {
                name = "modules",
                desc = "every pure module resolves from the local build",
                code = [[
for _, name in ipairs({ "luastd", "luastd.path", "luastd.semver", "luastd.formatx" }) do
    local ok, mod = pcall(require, name)
    print(name, ok and type(mod) or ("failed: " .. tostring(mod)))
end
]]
            }
        }
    },
    {
        module = "path",
        title = 'require("luastd.path")',
        examples = {
            {
                name = "join",
                desc = "build paths with new, / and join; an absolute part replaces the rest",
                code = [[
local path = require("luastd.path")
local src = path.new("/home/user/project") / "src" / "main.rs"
print(tostring(src))
print(path.join("project", "src", "lib.rs"))
print(path.join("project", "/etc", "hosts"))
]]
            },
            {
                name = "parts",
                desc = "split a path lexically: parent, name, stem, extension, components",
                code = [[
local path = require("luastd.path")
local p = path.new("/home/user/project/src/main.rs")
print(tostring(p:parent()), p:file_name(), p:file_stem(), p:extension())
print(tostring(p:with_extension("lua")), tostring(p:strip_prefix("/home/user")))
local kinds = {}
for _, c in ipairs(p:components()) do
    kinds[#kinds + 1] = c.kind .. "=" .. c.value
end
print(table.concat(kinds, " "))
]]
            }
        }
    },
    {
        module = "semver",
        title = 'require("luastd.semver")',
        examples = {
            {
                name = "parse",
                desc = "parse a version and read its fields; valid never raises",
                code = [[
local semver = require("luastd.semver")
local v = semver.parse("1.4.2-beta.1+build.7")
print(v.major, v.minor, v.patch, v.pre, v.build)
print(semver.valid("1.2.3"), semver.valid("1.2"))
]]
            },
            {
                name = "compare",
                desc = "order versions and check requirements",
                code = [[
local semver = require("luastd.semver")
local beta, release = semver.parse("1.4.2-beta.1"), semver.new(1, 4, 2)
print(beta < release, beta:cmp(release), release:cmp(beta))
print(release:satisfies("^1.4"), release:satisfies(">=1.0, <1.4"))
]]
            }
        }
    },
    {
        module = "formatx",
        title = 'require("luastd.formatx")',
        examples = {
            {
                name = "format",
                desc = "one-shot std::fmt-style formatting: positional, named, width, precision",
                code = [[
local formatx = require("luastd.formatx")
print(formatx.format("{} has {n} items, total {:>8.2}", "cart", 3.14159, { n = 3 }))
print(formatx.format("[{name:<8}] [{name:>8}] {:?}", "x", { name = "luastd" }))
print(formatx.formatl("hello {who}{missing}!", { who = "world" }))
]]
            },
            {
                name = "template",
                desc = "parse once with new, inspect placeholders, render strict",
                code = [[
local formatx = require("luastd.formatx")
local t = formatx.new("{greeting}, {name}! You are #{0}.")
print(t:contains("name"), table.concat(t:placeholders(), ", "))
print(t:render(1, { greeting = "Hi", name = "Gerson" }))
local ok, err = pcall(t.render, t, 1, { greeting = "Hi" })
print(ok, (tostring(err):match("[^\n]*")))
]]
            }
        }
    }
}
