-- The category table is data; check it is well-formed and that every game in
-- this checkout has a shelf.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("Categories", function()
    local C
    setup(function() C = require("categories") end)

    it("labels every category it orders", function()
        for _, c in ipairs(C.ORDER) do assert.is_string(C.LABELS[c], c) end
    end)

    it("maps every id to a known category", function()
        for id, c in pairs(C.BY_ID) do assert.is_string(C.LABELS[c], id) end
    end)

    it("puts unknown games under Other, which sorts last", function()
        assert.are.equal("other", C.of("not-a-game"))
        for _, c in ipairs(C.ORDER) do
            assert.is_true(C.rank(c) <= C.rank("other"))
        end
    end)

    it("keeps 2048 as a string key", function()
        assert.are.equal("classic", C.of("2048"))
    end)
end)
