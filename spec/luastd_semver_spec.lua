local semver = require("luastd.semver")

---@param fn fun()
---@return string
local function error_of(fn)
    local ok, err = pcall(fn)
    assert.is_false(ok)
    return tostring(err)
end

describe("luastd.semver", function ()
    describe("new", function ()
        it("defaults to 0.0.0", function ()
            local version = semver.new()
            assert.is_equal(0, version.major)
            assert.is_equal(0, version.minor)
            assert.is_equal(0, version.patch)
            assert.is_equal("", version.pre)
            assert.is_equal("", version.build)
            assert.is_equal("0.0.0", tostring(version))
        end)

        it("accepts core components", function ()
            local version = semver.new(1, 2, 3)
            assert.is_equal(1, version.major)
            assert.is_equal(2, version.minor)
            assert.is_equal(3, version.patch)
        end)

        it("accepts prerelease and build metadata", function ()
            local version = semver.new(1, 2, 3, "alpha.1", "build.5")
            assert.is_equal("alpha.1", version.pre)
            assert.is_equal("build.5", version.build)
            assert.is_equal("1.2.3-alpha.1+build.5", tostring(version))
        end)

        it("rejects an invalid prerelease", function ()
            assert.matches("invalid prerelease", error_of(function () semver.new(1, 2, 3, "not valid") end), 1, true)
        end)
    end)

    describe("default", function ()
        it("returns 0.0.0", function ()
            assert.is_equal("0.0.0", tostring(semver.default()))
        end)
    end)

    describe("parse", function ()
        it("reads every field", function ()
            local version = semver.parse("1.2.3-alpha.1+build.5")
            assert.is_equal(1, version.major)
            assert.is_equal(2, version.minor)
            assert.is_equal(3, version.patch)
            assert.is_equal("alpha.1", version.pre)
            assert.is_equal("build.5", version.build)
        end)

        it("raises on an invalid version", function ()
            assert.matches("invalid semantic version", error_of(function () semver.parse("1.2") end), 1, true)
        end)

        it("rejects non-string input", function ()
            assert.matches(
                "bad argument #1 'version' to 'parse' (string expected)",
                error_of(function ()
                    ---@diagnostic disable-next-line: param-type-mismatch
                    semver.parse(1)
                end),
                1, true
            )
        end)
    end)

    describe("valid", function ()
        it("checks without raising", function ()
            assert.is_true(semver.valid("1.2.3"))
            assert.is_true(semver.valid("1.2.3-alpha.1+build.5"))
            assert.is_false(semver.valid("1.2"))
            assert.is_false(semver.valid("v1.2.3"))
        end)
    end)

    describe("Version", function ()
        it("compares with == ignoring build metadata", function ()
            assert.is_true(semver.parse("1.2.3") == semver.parse("1.2.3"))
            assert.is_false(semver.parse("1.2.3") == semver.parse("1.2.4"))
            assert.is_true(semver.parse("1.2.3+build.1") == semver.parse("1.2.3+build.2"))
        end)

        it("orders by semver precedence", function ()
            local alpha = semver.parse("1.2.3-alpha")
            local release = semver.parse("1.2.3")
            assert.is_true(alpha < release)
            assert.is_true(alpha <= release)
            assert.is_true(release > alpha)
            assert.is_false(release < alpha)
        end)

        it("cmp returns -1, 0 or 1", function ()
            local alpha = semver.parse("1.2.3-alpha")
            local release = semver.parse("1.2.3")
            assert.is_equal(-1, alpha:cmp(release))
            assert.is_equal(1, release:cmp(alpha))
            assert.is_equal(0, release:cmp(semver.new(1, 2, 3)))
        end)

        it("satisfies a requirement", function ()
            assert.is_true(semver.parse("1.9.9"):satisfies("^1.2.3"))
            assert.is_false(semver.parse("2.0.0"):satisfies("^1.2.3"))
            assert.matches(
                "invalid requirement",
                error_of(function ()
                    semver
                        .parse("1.2.3")
                        :satisfies("not a requirement")
                end),
                1, true
            )
        end)

        it("has no class table on the module", function ()
            assert.is_nil(rawget(semver, "Version"))
        end)
    end)
end)
