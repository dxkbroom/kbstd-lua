local path = require("kbstd.path")

describe("kbstd.path", function ()
    describe("new", function ()
        it("defaults to the empty path", function ()
            local value = path.new()
            assert.is_equal(tostring(value), "")
            assert.is_true(value:is_relative())
            assert.is_false(value:is_absolute())
            assert.is_false(value:has_root())
        end)

        it("keeps the path text verbatim", function ()
            assert.is_equal(tostring(path.new("a//b/./c/")), "a//b/./c/")
        end)

        it("joins every argument", function ()
            assert.is_equal(tostring(path.new("a", "b", "c")), "a/b/c")
            assert.is_equal(tostring(path.new("a", path.new("b"), "c")), "a/b/c")
        end)

        it("lets a later absolute path win", function ()
            assert.is_equal(tostring(path.new("a", "/b", "c")), "/b/c")
        end)

        it("ignores empty arguments", function ()
            assert.is_equal(tostring(path.new("a", "", "b")), "a/b")
            assert.is_equal(tostring(path.new("", "a")), "a")
            assert.is_equal(tostring(path.new(path.new(""))), "")
        end)

        it("rejects non-string arguments", function ()
            assert.has_error(function ()
                ---@diagnostic disable-next-line: param-type-mismatch
                path.new(42)
            end, nil, "bad argument #1 to 'new' (string or Path expected)")

            assert.has_error(function ()
                ---@diagnostic disable-next-line: param-type-mismatch
                path.new("a", 42)
            end, nil, "bad argument #2 to 'new' (string or Path expected)")
        end)

        it("rejects invalid UTF-8", function ()
            assert.has_error(function ()
                path.new(string.char(0xff))
            end, nil, "bad argument #1 to 'new' (UTF-8 string expected)")
        end)

        it("accepts explicit nil as no argument", function ()
            assert.is_equal(tostring(path.new(nil)), "")
        end)
    end)

    it("absolute and relative paths are distinguished", function ()
        local absolute = path.new("/a/b")
        assert.is_true(absolute:is_absolute())
        assert.is_false(absolute:is_relative())
        assert.is_true(absolute:has_root())

        local relative = path.new("a/b")
        assert.is_false(relative:is_absolute())
        assert.is_true(relative:is_relative())
        assert.is_false(relative:has_root())
    end)

    it("the root path is absolute and parentless", function ()
        local root = path.new("/")
        assert.is_true(root:is_absolute())
        assert.is_true(root:has_root())
        assert.is_nil(root:parent())
        assert.is_nil(root:file_name())
    end)

    describe("parent", function ()
        it("returns the containing path", function ()
            assert.is_equal(tostring(path.new("a/b/c"):parent()), "a/b")
            assert.is_equal(tostring(path.new("a"):parent()), "")
            assert.is_nil(path.new(""):parent())
        end)

        it("handles absolute and trailing-separator paths", function ()
            assert.is_equal(tostring(path.new("/a"):parent()), "/")
            assert.is_equal(tostring(path.new("a/"):parent()), "")
            assert.is_equal(tostring(path.new("."):parent()), "")
        end)
    end)

    describe("ancestors", function ()
        it("walks up to the empty path", function ()
            local ancestors = path.new("a/b/c"):ancestors()
            assert.is_equal(#ancestors, 4)
            assert.is_equal(tostring(ancestors[1]), "a/b/c")
            assert.is_equal(tostring(ancestors[2]), "a/b")
            assert.is_equal(tostring(ancestors[3]), "a")
            assert.is_equal(tostring(ancestors[4]), "")
        end)

        it("stops at the root for absolute paths", function ()
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
        end)
    end)

    it("file_name returns the final component only", function ()
        assert.is_equal(path.new("/a/b.tar.gz"):file_name(), "b.tar.gz")
        assert.is_equal(path.new("a/b/"):file_name(), "b")
        assert.is_nil(path.new("."):file_name())
        assert.is_nil(path.new(".."):file_name())
    end)

    it("file_stem drops the final extension", function ()
        assert.is_equal(path.new("a/b.tar.gz"):file_stem(), "b.tar")
        assert.is_equal(path.new("a/b"):file_stem(), "b")
        assert.is_equal(path.new("a/b."):file_stem(), "b")
        assert.is_equal(path.new("a/.hidden"):file_stem(), ".hidden")
        assert.is_nil(path.new("/"):file_stem())
    end)

    it("extension returns the text after the final dot", function ()
        assert.is_equal(path.new("a/b.tar.gz"):extension(), "gz")
        assert.is_equal(path.new("a/b."):extension(), "")
        assert.is_nil(path.new("a/b"):extension())
        assert.is_nil(path.new("a/.hidden"):extension())
    end)

    describe("join", function ()
        it("appends a relative path", function ()
            assert.is_equal(tostring(path.new("a"):join("b/c")), "a/b/c")
            assert.is_equal(tostring(path.new("a"):join("b"):join("c")), "a/b/c")
        end)

        it("accepts several arguments", function ()
            assert.is_equal(tostring(path.new("a"):join("b", "c")), "a/b/c")
            assert.is_equal(tostring(path.new("a"):join(path.new("b"), "c")), "a/b/c")
        end)

        it("ignores nil and empty arguments", function ()
            assert.is_equal(tostring(path.new("a"):join("")), "a")
            assert.is_equal(tostring(path.new("a"):join(nil, "", path.new(""))), "a")
        end)

        it("requires at least one argument", function ()
            assert.has_error(function ()
                path.new("a"):join()
            end, nil, "string or Path expected")
        end)

        it("rejects non-path arguments", function ()
            assert.has_error(function ()
                ---@diagnostic disable-next-line: param-type-mismatch
                path.new("a"):join("b", 42)
            end, nil, "string or Path expected")
        end)

        it("replaces the path with an absolute argument", function ()
            assert.is_equal(tostring(path.new("a/b"):join("/c")), "/c")
        end)

        it("accepts another path", function ()
            assert.is_equal(tostring(path.new("a"):join(path.new("b/c"))), "a/b/c")
        end)
    end)

    describe("division", function ()
        it("joins paths python style", function ()
            assert.is_equal(tostring(path.new() / "a"), "a")
            assert.is_equal(tostring(path.new("a") / "b"), "a/b")
            assert.is_equal(tostring(path.new("a") / "b/c"), "a/b/c")
            assert.is_equal(tostring(path.new("a") / path.new("b")), "a/b")
        end)

        it("chains left to right", function ()
            assert.is_equal(tostring(path.new() / "a" / "b" / "c"), "a/b/c")
        end)

        it("lets an absolute path win", function ()
            assert.is_equal(tostring(path.new("a") / "/b"), "/b")
            assert.is_equal(tostring(path.new("a") / path.new("/b")), "/b")
            assert.is_equal(tostring(path.new("a") / "/b" / "c"), "/b/c")
        end)

        it("ignores empty operands", function ()
            assert.is_equal(tostring(path.new("a") / ""), "a")
            assert.is_equal(tostring(path.new("a") / path.new("")), "a")
        end)

        it("stays lexical", function ()
            assert.is_equal(tostring(path.new("/a") / "../b"), "/a/../b")
        end)

        it("rejects non-path operands", function ()
            assert.has_error(function ()
                local _ = path.new("a") / 42
            end)
        end)
    end)

    describe("with_file_name", function ()
        it("replaces the final component", function ()
            assert.is_equal(tostring(path.new("a/b.tar"):with_file_name("c.txt")), "a/c.txt")
            assert.is_equal(tostring(path.new("/"):with_file_name("c")), "/c")
        end)

        it("accepts a nested name", function ()
            assert.is_equal(tostring(path.new("a/b"):with_file_name("c/d")), "a/c/d")
        end)
    end)

    describe("with_extension", function ()
        it("replaces an existing extension", function ()
            assert.is_equal(tostring(path.new("a/b.tar.gz"):with_extension("txt")), "a/b.tar.txt")
            assert.is_equal(tostring(path.new("a/b"):with_extension("txt")), "a/b.txt")
            assert.is_equal(tostring(path.new(".hidden"):with_extension("txt")), ".hidden.txt")
        end)

        it("removes an extension when empty", function ()
            assert.is_equal(tostring(path.new("a/b.tar.gz"):with_extension("")), "a/b.tar")
            assert.is_equal(tostring(path.new("a/b"):with_extension("")), "a/b")
        end)

        it("is fail fast for separators", function ()
            assert.has_error(function ()
                path.new("a/b"):with_extension("x/y")
            end, nil, "extension cannot contain path separators")
        end)
    end)

    describe("with_added_extension", function ()
        it("keeps the existing extension", function ()
            assert.is_equal(tostring(path.new("a/b"):with_added_extension("txt")), "a/b.txt")
            assert.is_equal(tostring(path.new("a/b.tar"):with_added_extension("gz")), "a/b.tar.gz")
            assert.is_equal(tostring(path.new(".hidden"):with_added_extension("txt")), ".hidden.txt")
        end)

        it("is fail fast for separators", function ()
            assert.has_error(function ()
                path.new("a/b"):with_added_extension("x/y")
            end, nil, "extension cannot contain path separators")
        end)

        it("does nothing when empty", function ()
            assert.is_equal(tostring(path.new("a/b.tar"):with_added_extension("")), "a/b.tar")
        end)
    end)

    it("starts_with compares whole components", function ()
        assert.is_true(path.new("a/b/c"):starts_with("a"))
        assert.is_true(path.new("a/b/c"):starts_with("a/b"))
        assert.is_false(path.new("a/bc"):starts_with("a/b"))
        assert.is_false(path.new("a/b"):starts_with("/a"))
    end)

    it("ends_with compares whole components", function ()
        assert.is_true(path.new("a/b/c"):ends_with("b/c"))
        assert.is_true(path.new("a/b/c"):ends_with("c"))
        assert.is_false(path.new("a/bc"):ends_with("b/c"))
    end)

    describe("strip_prefix", function ()
        it("removes a component prefix", function ()
            assert.is_equal(tostring(path.new("a/b/c"):strip_prefix("a")), "b/c")
            assert.is_equal(tostring(path.new("a/b"):strip_prefix("a/b")), "")
        end)

        it("is fail fast", function ()
            assert.has_error(function ()
                path.new("a/b"):strip_prefix("c")
            end, nil, "prefix not found")
        end)
    end)

    it("empty prefixes match every path", function ()
        assert.is_true(path.new("a/b"):starts_with(""))
        assert.is_true(path.new("a/b"):ends_with(""))
        assert.is_equal(tostring(path.new("a/b"):strip_prefix("")), "a/b")
    end)

    describe("components", function ()
        it("reports component kinds", function ()
            assert.is_same(path.new("/a/./b/../c"):components(), {
                { kind = "root", value = "/" },
                { kind = "normal", value = "a" },
                { kind = "normal", value = "b" },
                { kind = "parentdir", value = ".." },
                { kind = "normal", value = "c" }
            })
        end)

        it("normalizes interior curdir markers", function ()
            assert.is_same(path.new("a/./b"):components(), {
                { kind = "normal", value = "a" },
                { kind = "normal", value = "b" }
            })
        end)

        it("normalizes repeated and trailing separators", function ()
            assert.is_same(path.new("a//b/"):components(), {
                { kind = "normal", value = "a" },
                { kind = "normal", value = "b" }
            })
        end)

        it("is empty for the empty path", function ()
            assert.is_same(path.new(""):components(), {})
        end)

        it("reports curdir and parentdir", function ()
            assert.is_same(path.new("."):components(), { { kind = "curdir", value = "." } })
            assert.is_same(path.new(".."):components(), { { kind = "parentdir", value = ".." } })
            assert.is_same(path.new("./a"):components(), {
                { kind = "curdir", value = "." },
                { kind = "normal", value = "a" }
            })
        end)
    end)

    it("equality compares components", function ()
        assert.is_true(path.new("a/b") == path.new("a//b/"))
        assert.is_false(path.new("./a") == path.new("a"))
        assert.is_false(path.new("a") == "a")
    end)

    it("ordering compares components", function ()
        local first = path.new("a/b")
        local second = path.new("a/c")

        assert.is_true(first < second)
        assert.is_true(first <= second)
        assert.is_true(second > first)
        assert.is_false(second < first)
    end)

    describe("module", function ()
        it("join concatenates every argument", function ()
            assert.is_equal(path.join("a", "b", "c"), "a/b/c")
            assert.is_equal(path.join("a/b", "c/d"), "a/b/c/d")
            assert.is_equal(path.join("a"), "a")
        end)

        it("join accepts paths", function ()
            assert.is_equal(path.join("a", path.new("b/c")), "a/b/c")
        end)

        it("join ignores nil and empty arguments", function ()
            assert.is_equal(path.join("a", "", "b"), "a/b")
            assert.is_equal(path.join("", "a"), "a")
            assert.is_equal(path.join("a", nil, path.new("")), "a")
        end)

        it("join lets a later absolute path win", function ()
            assert.is_equal(path.join("a", "/b", "c"), "/b/c")
            assert.is_equal(path.join("/a", "b", "/c"), "/c")
        end)

        it("join requires at least one argument", function ()
            assert.has_error(function ()
                path.join()
            end, nil, "bad argument #1 to 'join' (string or Path expected)")
        end)

        it("join rejects non-string arguments", function ()
            assert.has_error(function ()
                ---@diagnostic disable-next-line: param-type-mismatch
                path.join("a", 42)
            end, nil, "bad argument #2 to 'join' (string or Path expected)")
        end)

        it("has no Path class table", function ()
            assert.is_nil(rawget(path, "Path"))
        end)
    end)
end)
