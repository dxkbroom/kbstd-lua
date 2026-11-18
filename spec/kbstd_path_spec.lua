local path = require("kbstd.path")

it("new defaults to the empty path", function ()
    local value = path.new()
    assert.is_equal(tostring(value), "")
    assert.is_true(value:is_relative())
    assert.is_false(value:is_absolute())
    assert.is_false(value:has_root())
end)

local cases = {
    {
        name = "new keeps the path text verbatim",
        run = function ()
            assert.is_equal(tostring(path.new("a//b/./c/")), "a//b/./c/")
        end
    },
    {
        name = "new joins every argument",
        run = function ()
            assert.is_equal(tostring(path.new("a", "b", "c")), "a/b/c")
            assert.is_equal(tostring(path.new("a", path.new("b"), "c")), "a/b/c")
        end
    },
    {
        name = "new lets a later absolute path win",
        run = function ()
            assert.is_equal(tostring(path.new("a", "/b", "c")), "/b/c")
        end
    },
    {
        name = "new ignores empty arguments",
        run = function ()
            assert.is_equal(tostring(path.new("a", "", "b")), "a/b")
            assert.is_equal(tostring(path.new("", "a")), "a")
            assert.is_equal(tostring(path.new(path.new(""))), "")
        end
    },
    {
        name = "new rejects non-string arguments",
        run = function ()
            assert.has_error(function ()
                ---@diagnostic disable-next-line: param-type-mismatch
                path.new(42)
            end, nil, "bad argument #1 to 'new' (string or Path expected)")

            assert.has_error(function ()
                ---@diagnostic disable-next-line: param-type-mismatch
                path.new("a", 42)
            end, nil, "bad argument #2 to 'new' (string or Path expected)")
        end
    },
    {
        name = "new rejects invalid UTF-8",
        run = function ()
            assert.has_error(function ()
                path.new(string.char(0xff))
            end, nil, "bad argument #1 to 'new' (UTF-8 string expected)")
        end
    },
    {
        name = "new accepts explicit nil as no argument",
        run = function ()
            assert.is_equal(tostring(path.new(nil)), "")
        end
    },
    {
        name = "absolute and relative paths are distinguished",
        run = function ()
            local absolute = path.new("/a/b")
            assert.is_true(absolute:is_absolute())
            assert.is_false(absolute:is_relative())
            assert.is_true(absolute:has_root())

            local relative = path.new("a/b")
            assert.is_false(relative:is_absolute())
            assert.is_true(relative:is_relative())
            assert.is_false(relative:has_root())
        end
    },
    {
        name = "the root path is absolute and parentless",
        run = function ()
            local root = path.new("/")
            assert.is_true(root:is_absolute())
            assert.is_true(root:has_root())
            assert.is_nil(root:parent())
            assert.is_nil(root:file_name())
        end
    },
    {
        name = "parent returns the containing path",
        run = function ()
            assert.is_equal(tostring(path.new("a/b/c"):parent()), "a/b")
            assert.is_equal(tostring(path.new("a"):parent()), "")
            assert.is_nil(path.new(""):parent())
        end
    },
    {
        name = "parent handles absolute and trailing-separator paths",
        run = function ()
            assert.is_equal(tostring(path.new("/a"):parent()), "/")
            assert.is_equal(tostring(path.new("a/"):parent()), "")
            assert.is_equal(tostring(path.new("."):parent()), "")
        end
    },
    {
        name = "ancestors walks up to the empty path",
        run = function ()
            local ancestors = path.new("a/b/c"):ancestors()
            assert.is_equal(#ancestors, 4)
            assert.is_equal(tostring(ancestors[1]), "a/b/c")
            assert.is_equal(tostring(ancestors[2]), "a/b")
            assert.is_equal(tostring(ancestors[3]), "a")
            assert.is_equal(tostring(ancestors[4]), "")
        end
    },
    {
        name = "ancestors stops at the root for absolute paths",
        run = function ()
            local ancestors = path.new("/a/b"):ancestors()
            assert.is_equal(#ancestors, 3)
            assert.is_equal(tostring(ancestors[1]), "/a/b")
            assert.is_equal(tostring(ancestors[2]), "/a")
            assert.is_equal(tostring(ancestors[3]), "/")

            local root = path.new("/"):ancestors()
            assert.is_equal(#root, 1)
            assert.is_equal(tostring(root[1]), "/")

            local empty = path.new(""):ancestors()
            assert.is_equal(#empty, 1)
            assert.is_equal(tostring(empty[1]), "")
        end
    },
    {
        name = "file_name returns the final component only",
        run = function ()
            assert.is_equal(path.new("/a/b.tar.gz"):file_name(), "b.tar.gz")
            assert.is_equal(path.new("a/b/"):file_name(), "b")
            assert.is_nil(path.new("."):file_name())
            assert.is_nil(path.new(".."):file_name())
        end
    },
    {
        name = "file_stem drops the final extension",
        run = function ()
            assert.is_equal(path.new("a/b.tar.gz"):file_stem(), "b.tar")
            assert.is_equal(path.new("a/b"):file_stem(), "b")
            assert.is_equal(path.new("a/b."):file_stem(), "b")
            assert.is_equal(path.new("a/.hidden"):file_stem(), ".hidden")
            assert.is_nil(path.new("/"):file_stem())
        end
    },
    {
        name = "extension returns the text after the final dot",
        run = function ()
            assert.is_equal(path.new("a/b.tar.gz"):extension(), "gz")
            assert.is_equal(path.new("a/b."):extension(), "")
            assert.is_nil(path.new("a/b"):extension())
            assert.is_nil(path.new("a/.hidden"):extension())
        end
    },
    {
        name = "join appends a relative path",
        run = function ()
            assert.is_equal(tostring(path.new("a"):join("b/c")), "a/b/c")
            assert.is_equal(tostring(path.new("a"):join("b"):join("c")), "a/b/c")
        end
    },
    {
        name = "join accepts several arguments",
        run = function ()
            assert.is_equal(tostring(path.new("a"):join("b", "c")), "a/b/c")
            assert.is_equal(tostring(path.new("a"):join(path.new("b"), "c")), "a/b/c")
        end
    },
    {
        name = "join ignores nil and empty arguments",
        run = function ()
            assert.is_equal(tostring(path.new("a"):join("")), "a")
            assert.is_equal(tostring(path.new("a"):join(nil, "", path.new(""))), "a")
        end
    },
    {
        name = "join requires at least one argument",
        run = function ()
            assert.has_error(function ()
                path.new("a"):join()
            end, nil, "string or Path expected")
        end
    },
    {
        name = "join rejects non-path arguments",
        run = function ()
            assert.has_error(function ()
                ---@diagnostic disable-next-line: param-type-mismatch
                path.new("a"):join("b", 42)
            end, nil, "string or Path expected")
        end
    },
    {
        name = "join replaces the path with an absolute argument",
        run = function ()
            assert.is_equal(tostring(path.new("a/b"):join("/c")), "/c")
        end
    },
    {
        name = "join accepts another path",
        run = function ()
            assert.is_equal(tostring(path.new("a"):join(path.new("b/c"))), "a/b/c")
        end
    },
    {
        name = "division joins paths python style",
        run = function ()
            assert.is_equal(tostring(path.new() / "a"), "a")
            assert.is_equal(tostring(path.new("a") / "b"), "a/b")
            assert.is_equal(tostring(path.new("a") / "b/c"), "a/b/c")
            assert.is_equal(tostring(path.new("a") / path.new("b")), "a/b")
        end
    },
    {
        name = "division chains left to right",
        run = function ()
            assert.is_equal(tostring(path.new() / "a" / "b" / "c"), "a/b/c")
        end
    },
    {
        name = "division lets an absolute path win",
        run = function ()
            assert.is_equal(tostring(path.new("a") / "/b"), "/b")
            assert.is_equal(tostring(path.new("a") / path.new("/b")), "/b")
            assert.is_equal(tostring(path.new("a") / "/b" / "c"), "/b/c")
        end
    },
    {
        name = "division ignores empty operands",
        run = function ()
            assert.is_equal(tostring(path.new("a") / ""), "a")
            assert.is_equal(tostring(path.new("a") / path.new("")), "a")
        end
    },
    {
        name = "division stays lexical",
        run = function ()
            assert.is_equal(tostring(path.new("/a") / "../b"), "/a/../b")
        end
    },
    {
        name = "division rejects non-path operands",
        run = function ()
            assert.has_error(function ()
                local _ = path.new("a") / 42
            end)
        end
    },
    {
        name = "with_file_name replaces the final component",
        run = function ()
            assert.is_equal(tostring(path.new("a/b.tar"):with_file_name("c.txt")), "a/c.txt")
            assert.is_equal(tostring(path.new("/"):with_file_name("c")), "/c")
        end
    },
    {
        name = "with_file_name accepts a nested name",
        run = function ()
            assert.is_equal(tostring(path.new("a/b"):with_file_name("c/d")), "a/c/d")
        end
    },
    {
        name = "with_extension replaces an existing extension",
        run = function ()
            assert.is_equal(tostring(path.new("a/b.tar.gz"):with_extension("txt")), "a/b.tar.txt")
            assert.is_equal(tostring(path.new("a/b"):with_extension("txt")), "a/b.txt")
            assert.is_equal(tostring(path.new(".hidden"):with_extension("txt")), ".hidden.txt")
        end
    },
    {
        name = "with_extension removes an extension when empty",
        run = function ()
            assert.is_equal(tostring(path.new("a/b.tar.gz"):with_extension("")), "a/b.tar")
            assert.is_equal(tostring(path.new("a/b"):with_extension("")), "a/b")
        end
    },
    {
        name = "with_extension is fail fast for separators",
        run = function ()
            assert.has_error(function ()
                path.new("a/b"):with_extension("x/y")
            end, nil, "extension cannot contain path separators")
        end
    },
    {
        name = "with_added_extension keeps the existing extension",
        run = function ()
            assert.is_equal(tostring(path.new("a/b"):with_added_extension("txt")), "a/b.txt")
            assert.is_equal(tostring(path.new("a/b.tar"):with_added_extension("gz")), "a/b.tar.gz")
            assert.is_equal(tostring(path.new(".hidden"):with_added_extension("txt")), ".hidden.txt")
        end
    },
    {
        name = "with_added_extension is fail fast for separators",
        run = function ()
            assert.has_error(function ()
                path.new("a/b"):with_added_extension("x/y")
            end, nil, "extension cannot contain path separators")
        end
    },
    {
        name = "with_added_extension does nothing when empty",
        run = function ()
            assert.is_equal(tostring(path.new("a/b.tar"):with_added_extension("")), "a/b.tar")
        end
    },
    {
        name = "starts_with compares whole components",
        run = function ()
            assert.is_true(path.new("a/b/c"):starts_with("a"))
            assert.is_true(path.new("a/b/c"):starts_with("a/b"))
            assert.is_false(path.new("a/bc"):starts_with("a/b"))
            assert.is_false(path.new("a/b"):starts_with("/a"))
        end
    },
    {
        name = "ends_with compares whole components",
        run = function ()
            assert.is_true(path.new("a/b/c"):ends_with("b/c"))
            assert.is_true(path.new("a/b/c"):ends_with("c"))
            assert.is_false(path.new("a/bc"):ends_with("b/c"))
        end
    },
    {
        name = "strip_prefix removes a component prefix",
        run = function ()
            assert.is_equal(tostring(path.new("a/b/c"):strip_prefix("a")), "b/c")
            assert.is_equal(tostring(path.new("a/b"):strip_prefix("a/b")), "")
        end
    },
    {
        name = "empty prefixes match every path",
        run = function ()
            assert.is_true(path.new("a/b"):starts_with(""))
            assert.is_true(path.new("a/b"):ends_with(""))
            assert.is_equal(tostring(path.new("a/b"):strip_prefix("")), "a/b")
        end
    },
    {
        name = "strip_prefix is fail fast",
        run = function ()
            assert.has_error(function ()
                path.new("a/b"):strip_prefix("c")
            end, nil, "prefix not found")
        end
    },
    {
        name = "components reports component kinds",
        run = function ()
            assert.is_same(path.new("/a/./b/../c"):components(), {
                { kind = "root", value = "/" },
                { kind = "normal", value = "a" },
                { kind = "normal", value = "b" },
                { kind = "parentdir", value = ".." },
                { kind = "normal", value = "c" }
            })
        end
    },
    {
        name = "components normalizes interior curdir markers",
        run = function ()
            assert.is_same(path.new("a/./b"):components(), {
                { kind = "normal", value = "a" },
                { kind = "normal", value = "b" }
            })
        end
    },
    {
        name = "components normalizes repeated and trailing separators",
        run = function ()
            assert.is_same(path.new("a//b/"):components(), {
                { kind = "normal", value = "a" },
                { kind = "normal", value = "b" }
            })
        end
    },
    {
        name = "components is empty for the empty path",
        run = function ()
            assert.is_same(path.new(""):components(), {})
        end
    },
    {
        name = "components reports curdir and parentdir",
        run = function ()
            assert.is_same(path.new("."):components(), { { kind = "curdir", value = "." } })
            assert.is_same(path.new(".."):components(), { { kind = "parentdir", value = ".." } })
            assert.is_same(path.new("./a"):components(), {
                { kind = "curdir", value = "." },
                { kind = "normal", value = "a" }
            })
        end
    },
    {
        name = "equality compares components",
        run = function ()
            assert.is_true(path.new("a/b") == path.new("a//b/"))
            assert.is_false(path.new("./a") == path.new("a"))
            assert.is_false(path.new("a") == "a")
        end
    },
    {
        name = "ordering compares components",
        run = function ()
            local first = path.new("a/b")
            local second = path.new("a/c")

            assert.is_true(first < second)
            assert.is_true(first <= second)
            assert.is_true(second > first)
            assert.is_false(second < first)
        end
    },
    {
        name = "module join concatenates every argument",
        run = function ()
            assert.is_equal(path.join("a", "b", "c"), "a/b/c")
            assert.is_equal(path.join("a/b", "c/d"), "a/b/c/d")
            assert.is_equal(path.join("a"), "a")
        end
    },
    {
        name = "module join accepts paths",
        run = function ()
            assert.is_equal(path.join("a", path.new("b/c")), "a/b/c")
        end
    },
    {
        name = "module join ignores nil and empty arguments",
        run = function ()
            assert.is_equal(path.join("a", "", "b"), "a/b")
            assert.is_equal(path.join("", "a"), "a")
            assert.is_equal(path.join("a", nil, path.new("")), "a")
        end
    },
    {
        name = "module join lets a later absolute path win",
        run = function ()
            assert.is_equal(path.join("a", "/b", "c"), "/b/c")
            assert.is_equal(path.join("/a", "b", "/c"), "/c")
        end
    },
    {
        name = "module join requires at least one argument",
        run = function ()
            assert.has_error(function ()
                path.join()
            end, nil, "bad argument #1 to 'join' (string or Path expected)")
        end
    },
    {
        name = "module join rejects non-string arguments",
        run = function ()
            assert.has_error(function ()
                ---@diagnostic disable-next-line: param-type-mismatch
                path.join("a", 42)
            end, nil, "bad argument #2 to 'join' (string or Path expected)")
        end
    },
    {
        name = "module has no Path class table",
        run = function ()
            assert.is_nil(rawget(path, "Path"))
        end
    }
}

for _, case in pairs(cases) do
    it(case.name, case.run)
end
