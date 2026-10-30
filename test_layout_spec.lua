-- Cutting the game grid into pages: every game on exactly one page, in order,
-- no page taller than the room it has.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("Layout.columns", function()
    local L
    setup(function() L = require("layout") end)

    it("fits as many minimum-width tiles as it can, within bounds", function()
        assert.are.equal(3, L.columns(1000, 300, 2, 3))
        assert.are.equal(2, L.columns(500, 300, 2, 3))
        assert.are.equal(3, L.columns(5000, 300, 2, 3))
    end)
end)

describe("Layout.paginate", function()
    local L
    setup(function() L = require("layout") end)

    -- Every game index of every section appears exactly once, in order.
    local function check_cover(sections, pages)
        local next_idx = {}
        for _, page in ipairs(pages) do
            for _, b in ipairs(page) do
                local want = next_idx[b.section] or 1
                assert.are.equal(want, b.first)
                assert.is_true(b.last >= b.first)
                next_idx[b.section] = b.last + 1
            end
        end
        for si, s in ipairs(sections) do
            if s.count > 0 then assert.are.equal(s.count + 1, next_idx[si]) end
        end
    end

    local function height(page, cols, header_h, row_h)
        local h = 0
        for _, b in ipairs(page) do
            h = h + header_h + math.ceil((b.last - b.first + 1) / cols) * row_h
        end
        return h
    end

    it("puts everything on one page when it fits", function()
        local pages = L.paginate({ { count = 5 }, { count = 2 } }, 3, 1000, 1000, 50, 100)
        assert.are.equal(1, #pages)
        assert.are.equal(2, #pages[1])
    end)

    it("splits a section between rows and repeats it on the next page", function()
        local secs = { { count = 12 } }
        local pages = L.paginate(secs, 3, 260, 400, 50, 100)
        -- page 1: header + 2 rows (6 games); page 2: header + 2 rows
        assert.are.equal(2, #pages)
        assert.are.same({ section = 1, first = 1, last = 6 }, pages[1][1])
        assert.are.same({ section = 1, first = 7, last = 12 }, pages[2][1])
        check_cover(secs, pages)
    end)

    it("never overfills a page", function()
        local secs = { { count = 7 }, { count = 1 }, { count = 11 }, { count = 4 } }
        local pages = L.paginate(secs, 2, 333, 777, 40, 90)
        check_cover(secs, pages)
        for i, p in ipairs(pages) do
            assert.is_true(height(p, 2, 40, 90) <= (i == 1 and 333 or 777), "page " .. i)
        end
    end)

    it("leaves page 1 empty when the cards take all its room", function()
        local secs = { { count = 3 } }
        local pages = L.paginate(secs, 3, 10, 500, 50, 100)
        assert.are.equal(2, #pages)
        assert.are.equal(0, #pages[1])
        check_cover(secs, pages)
    end)

    it("still makes progress on a screen too small for one row", function()
        local secs = { { count = 4 } }
        local pages = L.paginate(secs, 2, 10, 10, 50, 100)
        check_cover(secs, pages)
    end)

    it("returns one empty page when there is nothing to show", function()
        assert.are.same({ {} }, L.paginate({}, 3, 100, 100, 10, 10))
    end)
end)

describe("Layout.clampPage", function()
    local L
    setup(function() L = require("layout") end)
    it("clamps", function()
        assert.are.equal(1, L.clampPage(0, 3))
        assert.are.equal(3, L.clampPage(9, 3))
        assert.are.equal(1, L.clampPage(2, 0))
    end)
end)
