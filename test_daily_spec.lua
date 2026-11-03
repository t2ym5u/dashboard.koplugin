-- Which game is today's Daily Challenge. It must be the same game all day on
-- every device, change from one day to the next, and not depend on the order
-- the filesystem happens to list plugins in.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("Daily.dayNumber", function()
    local D
    setup(function() D = require("daily") end)

    it("goes up by one per day, across month and year boundaries", function()
        local function dn(y, m, d) return D.dayNumber{ year = y, month = m, day = d } end
        assert.are.equal(1, dn(2026, 1, 1) - dn(2025, 12, 31))
        assert.are.equal(1, dn(2026, 3, 1) - dn(2026, 2, 28))
        assert.are.equal(1, dn(2024, 2, 29) - dn(2024, 2, 28))
        assert.are.equal(365, dn(2027, 1, 1) - dn(2026, 1, 1))
    end)

    it("ignores the time of day", function()
        assert.are.equal(D.dayNumber{ year = 2026, month = 10, day = 30, hour = 0 },
                         D.dayNumber{ year = 2026, month = 10, day = 30, hour = 23 })
    end)
end)

describe("Daily.candidates", function()
    local D
    local GAMES = {
        { id = "tents", daily = "screen" }, { id = "chess" },
        { id = "sudoku", daily = "plugin" }, { id = "kenken", daily = "screen" },
    }
    setup(function() D = require("daily") end)

    local function ids(list)
        local out = {}
        for _, g in ipairs(list) do out[#out + 1] = g.id end
        return out
    end

    it("draws from the shown daily-capable games, sorted by id", function()
        local shown = function(id) return id ~= "kenken" end
        assert.are.same({ "sudoku", "tents" }, ids(D.candidates(GAMES, shown)))
    end)

    it("falls back to every daily-capable game when none is shown", function()
        local shown = function(id) return id == "chess" end
        assert.are.same({ "kenken", "sudoku", "tents" }, ids(D.candidates(GAMES, shown)))
    end)

    it("draws from every daily-capable game while the player has not chosen the shown games", function()
        -- the default shown set (sudoku, 2048, minesweeper, mastermind) has
        -- only one daily game: it must not make the challenge sudoku every day
        local defaults = function(id) return id == "sudoku" or id == "chess" end
        assert.are.same({ "kenken", "sudoku", "tents" },
                        ids(D.candidates(GAMES, D.shownFilter(nil, defaults))))
    end)

    it("never overrides an explicit choice of shown games", function()
        local shown = function(id) return id == "sudoku" or id == "chess" end
        local saved = { sudoku = true, chess = true, kenken = false, tents = false }
        assert.are.same({ "sudoku" }, ids(D.candidates(GAMES, D.shownFilter(saved, shown))))
    end)

    it("the default pool visits every daily game before a repeat, same game all day", function()
        local games = {}
        for i = 1, 25 do games[i] = { id = string.format("g%02d", i), daily = "screen" } end
        games[26] = { id = "chess" }
        local pool = D.candidates(games, D.shownFilter(nil, function() return false end))
        assert.are.equal(25, #pool)
        local start = D.dayNumber{ year = 2026, month = 11, day = 3 }
        local seen = {}
        for day = start, start + 24 do
            local g = D.pick(pool, day, D.AUTO)
            assert.is_nil(seen[g.id], "repeat on day " .. day)
            seen[g.id] = true
            assert.are.equal(g, D.pick(D.candidates(games, nil), day, nil))
        end
    end)

    it("is empty when no installed game has a daily mode", function()
        assert.are.same({}, D.candidates({ { id = "chess" } }, function() return true end))
    end)
end)

describe("Daily.pick", function()
    local D
    local POOL = { { id = "a", daily = "screen" }, { id = "b", daily = "screen" },
                   { id = "c", daily = "screen" }, { id = "d", daily = "screen" } }
    setup(function() D = require("daily") end)

    it("is stable within a day", function()
        assert.are.equal(D.pick(POOL, 20000, "auto").id, D.pick(POOL, 20000, "auto").id)
    end)

    it("visits every game once before repeating", function()
        local seen = {}
        for day = 20000, 20003 do seen[D.pick(POOL, day, nil).id] = true end
        for _, g in ipairs(POOL) do assert.is_true(seen[g.id], g.id) end
    end)

    it("changes from one day to the next", function()
        assert.are_not.equal(D.pick(POOL, 20000).id, D.pick(POOL, 20001).id)
    end)

    it("honours a pinned game", function()
        assert.are.equal("c", D.pick(POOL, 20000, "c").id)
        -- pinned game outside the favourites pool, but installed
        local all = { { id = "z", daily = "screen" } }
        assert.are.equal("z", D.pick(POOL, 20000, "z", all).id)
    end)

    it("falls back to the rotation when the pinned game is gone", function()
        assert.is_not_nil(D.pick(POOL, 20000, "uninstalled"))
    end)

    it("returns nil for an empty pool", function()
        assert.is_nil(D.pick({}, 20000, "auto"))
    end)
end)

describe("Daily.isDone", function()
    local D
    setup(function() D = require("daily") end)

    it("is done only for the same day and the same game", function()
        local rec = { day = 20000, id = "tents" }
        assert.is_true(D.isDone(rec, 20000, "tents"))
        assert.is_false(D.isDone(rec, 20001, "tents"))
        assert.is_false(D.isDone(rec, 20000, "kenken"))
        assert.is_false(D.isDone(nil, 20000, "tents"))
    end)
end)
