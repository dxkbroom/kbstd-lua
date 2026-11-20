local formatx = require("luastd.formatx")
local path = require("luastd.path")
local semver = require("luastd.semver")

---@param fn fun()
---@return string
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return tostring(err)
end

describe("luastd.formatx", function ()
    describe("format", function ()
        it("mixes positional and named arguments", function ()
            assert.is_equal(
                "Alice scored 95.7% in maths",
                formatx.format("{} scored {score:.1}% in {}", "Alice", "maths", { score = 95.678 })
            )
        end)

        it("accepts only named or only positional arguments", function ()
            assert.is_equal(
                "Alice has 42 items",
                formatx.format("{name} has {count} items", {
                    name = "Alice",
                    count = 42
                })
            )
            assert.is_equal("1 + 2 = 3", formatx.format("{} + {} = {}", 1, 2, 3))
        end)

        it("supports explicit positional indices", function ()
            assert.is_equal("b a", formatx.format("{1} {0}", "a", "b"))
        end)

        it("supports width, precision, alignment and escaped braces", function ()
            assert.is_equal("3.14", formatx.format("{:.2}", 3.14159))
            assert.is_equal("hi   ", formatx.format("{:5}", "hi"))
            assert.is_equal("hi---", formatx.format("{:-<5}", "hi"))
            assert.is_equal("{ok}", formatx.format("{{ok}}"))
        end)

        it("supports Debug and boolean Display", function ()
            assert.is_equal("\"hi\"", formatx.format("{:?}", "hi"))
            assert.is_equal("true", formatx.format("{}", true))
            assert.is_equal("false", formatx.format("{}", false))
        end)

        it("ignores unused extra arguments", function ()
            assert.is_equal("used", formatx.format("{}", "used", "ignored"))
            assert.is_equal("Alice", formatx.format("{name}", { name = "Alice", unused = 1 }))
        end)

        it("accepts tostringable userdata", function ()
            local root = path.new("/tmp/project")
            local version = semver.parse("1.2.3-alpha.1+build.5")
            assert.is_equal("/tmp/project @ 1.2.3-alpha.1+build.5", formatx.format("{} @ {}", root, version))
            assert.is_equal(
                "/tmp/project @ 1.2.3-alpha.1+build.5",
                formatx.format("{path} @ {version}", { path = root, version = version })
            )
        end)

        it("raises on missing arguments, bad templates and unsupported traits", function ()
            assert.matches("missing argument: `name`", error_of(function () formatx.format("{name}") end), 1, true)
            assert.matches("parse error at byte", error_of(function () formatx.format("{") end), 1, true)
            assert.matches(
                "unsupported format trait: `LowerHex`", error_of(function () formatx.format("{:x}", 255) end), 1, true
            )
        end)

        it("rejects bad argument types", function ()
            assert.matches(
                "bad argument #1 'template' to 'format' (string expected)",
                error_of(function ()
                    ---@diagnostic disable-next-line: param-type-mismatch
                    formatx.format(42, "x")
                end),
                1, true
            )
            assert.matches(
                "bad argument #2 '...' to 'format' (string, number, boolean, or tostringable expected)",
                error_of(function () formatx.format("{}", function () end) end), 1, true
            )
            assert.matches(
                "bad argument #2 '...' to 'format' (named arguments table expected)",
                error_of(function () formatx.format("{}", { [1] = "positional-looking" }) end), 1, true
            )
        end)
    end)

    describe("formatl", function ()
        it("replaces missing arguments with empty strings", function ()
            assert.is_equal("Hello !", formatx.formatl("{greeting} {name}!", { greeting = "Hello" }))
        end)

        it("still raises on malformed templates", function ()
            assert.matches("parse error at byte", error_of(function () formatx.formatl("{") end), 1, true)
        end)
    end)

    describe("new", function ()
        it("parses a reusable template", function ()
            local template = formatx.new("{name} has {n} items")
            assert.is_equal("{name} has {n} items", tostring(template))
            assert.is_true(template:contains("name"))
            assert.is_false(template:contains("missing"))
            assert.are.same({ "name", "n" }, template:placeholders())
        end)

        it("raises on malformed or non-string sources", function ()
            assert.matches("parse error at byte", error_of(function () formatx.new("{") end), 1, true)
            assert.matches(
                "bad argument #1 'source' to 'new' (string expected)",
                error_of(function ()
                    ---@diagnostic disable-next-line: param-type-mismatch
                    formatx.new(42)
                end),
                1, true
            )
        end)

        it("has no class table on the module", function ()
            assert.is_nil(rawget(formatx, "Template"))
        end)
    end)

    describe("Template", function ()
        it("renders named, positional and mixed arguments", function ()
            assert.is_equal("Alice has 3 items", formatx.new("{name} has {n} items"):render({ name = "Alice", n = 3 }))
            assert.is_equal("1 + 2 = 3", formatx.new("{} + {} = {}"):render(1, 2, 3))
            assert.is_equal(
                "Alice scored 95.7%",
                formatx.new("{} scored {score:.1}%"):render("Alice", {
                    score = 95.678
                })
            )
        end)

        it("render raises on missing arguments; render_lenient does not", function ()
            local template = formatx.new("{greeting} {name}!")
            assert.matches(
                "missing argument: `name`", error_of(function () template:render({ greeting = "Hello" }) end), 1, true
            )
            assert.is_equal("Hello !", template:render_lenient({ greeting = "Hello" }))
        end)

        it("placeholders omit positional slots", function ()
            assert.are.same({ "name" }, formatx.new("{} {name} {0}"):placeholders())
            assert.are.same({}, formatx.new("no placeholders"):placeholders())
        end)

        it("contains rejects non-string names", function ()
            local template = formatx.new("{name}")
            assert.matches(
                "bad argument #2 'name' to 'contains' (string expected)",
                error_of(function ()
                    ---@diagnostic disable-next-line: param-type-mismatch
                    template:contains(42)
                end),
                1, true
            )
        end)
    end)
end)
