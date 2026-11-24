-- Which books the "Continue reading" cards show: the last one opened, then
-- the next books of the reading history still being read.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("Books", function()
    local B
    setup(function() B = require("books") end)

    -- Books on "disk": file -> { percent, status }; files not listed are gone.
    local function library(t)
        local reads = {}
        local function info(file)
            reads[#reads + 1] = file
            local b = t[file]
            if not b then return nil end
            return { file = file, title = file, percent = b.percent, status = b.status }
        end
        return info, reads
    end

    local function files(books)
        local out = {}
        for i, b in ipairs(books) do out[i] = b.file end
        return out
    end

    it("shows only the last book by default, whatever its state", function()
        local info = library{ a = { percent = 1, status = "complete" }, b = { percent = 0.4 } }
        assert.are.same({ "a" }, files(B.pick("a", { "a", "b" }, 1, info)))
    end)

    it("adds the next books in progress, in history order", function()
        local info = library{ a = { percent = 0.2 }, b = { percent = 0.5 }, c = { percent = 0.7 } }
        assert.are.same({ "a", "b", "c" }, files(B.pick("a", { "a", "b", "c" }, 3, info)))
        assert.are.same({ "a", "b" }, files(B.pick("a", { "a", "b", "c" }, 2, info)))
    end)

    it("skips finished, on-hold, unstarted and missing books", function()
        local info = library{
            a = { percent = 0.2 },
            done = { percent = 1 },
            marked = { percent = 0.6, status = "complete" },
            hold = { percent = 0.3, status = "abandoned" },
            new = { percent = 0 },
            unknown = {},
            b = { percent = 0.9, status = "reading" },
        }
        local hist = { "a", "done", "marked", "hold", "gone", "new", "unknown", "b" }
        assert.are.same({ "a", "b" }, files(B.pick("a", hist, 3, info)))
    end)

    it("does not show the last book twice", function()
        local info = library{ a = { percent = 0.2 }, b = { percent = 0.5 } }
        assert.are.same({ "a", "b" }, files(B.pick("a", { "b", "a" }, 3, info)))
    end)

    it("starts from the history when the last book is gone", function()
        local info = library{ b = { percent = 0.5 }, c = { percent = 0.7 } }
        assert.are.same({ "b", "c" }, files(B.pick("a", { "a", "b", "c" }, 2, info)))
        assert.are.same({ "b" }, files(B.pick(nil, { "b", "c" }, 1, info)))
    end)

    it("reads at most MAX_LOOKED history entries", function()
        local t, hist = { a = { percent = 0.2 } }, {}
        for i = 1, 30 do hist[i] = "x" .. i; t[hist[i]] = { percent = 1 } end
        hist[30] = "late"; t.late = { percent = 0.5 }
        local info, reads = library(t)
        assert.are.same({ "a" }, files(B.pick("a", hist, 3, info)))
        assert.are.equal(1 + B.MAX_LOOKED, #reads)
    end)

    it("keeps the setting to the offered choices", function()
        assert.are.equal(2, B.count(2))
        assert.are.equal(B.DEFAULT, B.count(nil))
        assert.are.equal(B.DEFAULT, B.count(7))
    end)
end)
