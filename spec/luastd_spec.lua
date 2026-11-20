local luastd = require("luastd")

it("version is 0.0.1", function ()
    assert.is_equal("0.0.1", luastd.version)
end)
