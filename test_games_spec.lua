-- Whether a game appears on the dashboard is a three-way answer -- the
-- player turned it on, the player turned it off, or the player has never seen
-- it -- and the third case is the one that quietly collapses into "off".
--
-- The parseMeta / isEnabled / toggled / sorted blocks are ported verbatim
-- from startmenu.koplugin/test_games_spec.lua along with the code they test.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.path = DIR .. "?.lua;" .. package.path

describe("Games.parseMeta", function()
    local Games

    setup(function()
        Games = require("games")
    end)

    it("takes the id from the directory, not from the _meta.lua source", function()
        -- KOReader 2026.03 (PR #15096) made the directory name the plugin id
        -- and deprecated _meta.lua's `name`. A stale `name` in the source must
        -- not win over the directory it was found in.
        local g = Games.parseMeta([[
            return {
                name = "killer_sudoku",
                fullname = _("Killer Sudoku"),
            }
        ]], "sudokukiller")
        assert.are.equal("sudokukiller", g.id)
        assert.are.equal("Killer Sudoku", g.label)
    end)

    it("reads the label out of a _meta.lua", function()
        local g = Games.parseMeta([[
            return {
                fullname = _("Sokoban"),
                description = _("Push the crates onto the targets."),
            }
        ]], "sokoban")
        assert.are.equal("sokoban", g.id)
        assert.are.equal("Sokoban", g.label)
    end)

    it("reads a fullname that is a plain string, not a _() call", function()
        local g = Games.parseMeta('return { fullname = "Tower of Hanoi" }', "hanoi")
        assert.are.equal("Tower of Hanoi", g.label)
    end)

    it("reads a long-bracket label, not the next quoted string", function()
        -- The sudoku family writes _([[Sudoku]]); a pattern that skips to
        -- the next double quote picks up version = "2.5.0" instead.
        local g = Games.parseMeta([=[
            return {
                fullname = _([[Sudoku]]),
                version = "2.5.0",
            }
        ]=], "sudoku")
        assert.are.equal("Sudoku", g.label)
        g = Games.parseMeta('return { fullname = _([==[Killer Sudoku]==]), version = "1" }', "k")
        assert.are.equal("Killer Sudoku", g.label)
    end)

    it("reads a single-quoted label", function()
        assert.are.equal("Hanoi", Games.parseMeta("return { fullname = _('Hanoi') }", "h").label)
    end)

    it("does not take a later key's value when fullname is not a literal", function()
        local g = Games.parseMeta('return { fullname = NAME, version = "2.5.0" }', "x")
        assert.are.equal("x", g.label)
    end)

    it("falls back to the id when there is no fullname", function()
        local g = Games.parseMeta('return { description = _("x") }', "hanoi")
        assert.are.equal("hanoi", g.label)
    end)

    it("falls back to the id rather than showing a blank row", function()
        local g = Games.parseMeta('return { fullname = _("") }', "hanoi")
        assert.are.equal("hanoi", g.label)
    end)

    it("still labels a game whose _meta.lua is unreadable", function()
        -- The directory alone is enough to launch it; only the label is lost.
        local g = Games.parseMeta(nil, "hanoi")
        assert.are.equal("hanoi", g.id)
        assert.are.equal("hanoi", g.label)
    end)

    it("ignores infrastructure plugins", function()
        assert.is_nil(Games.parseMeta('return { fullname = "Start Menu" }', "startmenu"))
        assert.is_nil(Games.parseMeta("", "pluginmanager"))
        assert.is_nil(Games.parseMeta("", "dashboard"))
        assert.is_nil(Games.parseMeta("", "opdsdir"))
        assert.is_nil(Games.parseMeta("", "_skeleton"))
    end)

    it("ignores a directory with no usable id", function()
        assert.is_nil(Games.parseMeta('return { fullname = "x" }', nil))
        assert.is_nil(Games.parseMeta('return { fullname = "x" }', ""))
    end)

    it("takes the ids of the real plugins as written", function()
        -- 2048's id is numeric-looking and quoted as a key elsewhere; make sure
        -- nothing along the way turns it into a number or drops it.
        local g = Games.parseMeta('return { fullname = _("2048") }', "2048")
        assert.are.equal("2048", g.id)
        assert.are.equal("string", type(g.id))
    end)
end)

describe("Games.isEnabled", function()
    local Games
    local DEFAULTS = { sudoku = true, ["2048"] = true }

    setup(function()
        Games = require("games")
    end)

    it("shows only the default games before the player has touched anything", function()
        assert.is_true(Games.isEnabled("sudoku", nil, DEFAULTS))
        assert.is_false(Games.isEnabled("hanoi", nil, DEFAULTS))
    end)

    it("obeys an explicit choice, in both directions", function()
        local saved = { sudoku = false, hanoi = true }
        assert.is_false(Games.isEnabled("sudoku", saved, DEFAULTS))
        assert.is_true(Games.isEnabled("hanoi", saved, DEFAULTS))
    end)

    it("falls back to the default for a game installed since the last toggle", function()
        -- The saved map only lists games that existed when it was written; a
        -- newly installed one must not be read as "the player said no".
        local saved = { hanoi = true }
        assert.is_true(Games.isEnabled("sudoku", saved, DEFAULTS))
        assert.is_false(Games.isEnabled("sokoban", saved, DEFAULTS))
    end)

    it("treats an empty saved map as no choice made", function()
        assert.is_true(Games.isEnabled("sudoku", {}, DEFAULTS))
    end)
end)

describe("Games.toggled", function()
    local Games
    local DEFAULTS = { sudoku = true }
    local GAMES = { { id = "sudoku" }, { id = "hanoi" }, { id = "sokoban" } }

    setup(function()
        Games = require("games")
    end)

    it("flips the game asked for and leaves the others alone", function()
        local out = Games.toggled(GAMES, "hanoi", nil, DEFAULTS)
        assert.is_true(out.hanoi)
        assert.is_true(out.sudoku)
        assert.is_false(out.sokoban)
    end)

    it("turns a default-on game off", function()
        local out = Games.toggled(GAMES, "sudoku", nil, DEFAULTS)
        assert.is_false(out.sudoku)
    end)

    it("writes an explicit entry for every known game", function()
        -- Otherwise a later change to DEFAULT_ENABLED would move a game the
        -- player had already decided about.
        local out = Games.toggled(GAMES, "hanoi", nil, DEFAULTS)
        for _, g in ipairs(GAMES) do
            assert.are.equal("boolean", type(out[g.id]), g.id .. " left implicit")
        end
    end)

    it("round-trips: toggling twice returns to the starting state", function()
        local once  = Games.toggled(GAMES, "sudoku", nil, DEFAULTS)
        local twice = Games.toggled(GAMES, "sudoku", once, DEFAULTS)
        for _, g in ipairs(GAMES) do
            assert.are.equal(Games.isEnabled(g.id, nil, DEFAULTS), twice[g.id],
                g.id .. " did not come back")
        end
    end)

    it("keeps a game the player enabled even when it is not in the defaults", function()
        local saved = { sokoban = true }
        local out = Games.toggled(GAMES, "hanoi", saved, DEFAULTS)
        assert.is_true(out.sokoban)
    end)
end)

describe("Games.sorted", function()
    local Games

    setup(function()
        Games = require("games")
    end)

    it("orders by the label the player reads, not by id", function()
        local out = Games.sorted({
            { id = "zzz", label = "Anagram" },
            { id = "aaa", label = "Sokoban" },
            { id = "mmm", label = "Hanoi" },
        })
        assert.are.equal("Anagram", out[1].label)
        assert.are.equal("Hanoi",   out[2].label)
        assert.are.equal("Sokoban", out[3].label)
    end)
end)

describe("Games.dailyKind", function()
    local Games
    setup(function() Games = require("games") end)

    it("recognises a plugin with its own daily slot (sudoku)", function()
        assert.are.equal("plugin", Games.dailyKind(
            "function Sudoku:showDailyChallenge()\nend", ""))
    end)

    it("recognises a screen that wires the shared Daily Challenge entry", function()
        assert.are.equal("screen", Games.dailyKind("", "self:makeDailyButtonConfig(),"))
        assert.are.equal("screen", Games.dailyKind("", "function X:onDailyGame()\nend"))
    end)

    it("says nothing for a game without a daily mode", function()
        assert.is_nil(Games.dailyKind("return P", "function X:onNewGame() end"))
        assert.is_nil(Games.dailyKind(nil, nil))
    end)
end)

describe("Games.withRecent", function()
    local Games
    setup(function() Games = require("games") end)

    it("adds the n most recently played games to the defaults", function()
        local out = Games.withRecent({ sudoku = true },
            { hanoi = 30, sokoban = 20, wordle = 10 }, 2)
        assert.is_true(out.sudoku)
        assert.is_true(out.hanoi)
        assert.is_true(out.sokoban)
        assert.is_nil(out.wordle)
    end)

    it("does not modify the defaults table it is given", function()
        local d = { sudoku = true }
        Games.withRecent(d, { hanoi = 1 }, 3)
        assert.is_nil(d.hanoi)
    end)

    it("copes with no play history", function()
        local out = Games.withRecent({ sudoku = true }, nil, 5)
        assert.is_true(out.sudoku)
    end)
end)

describe("Games.migrateShown", function()
    local Games
    setup(function() Games = require("games") end)

    it("imports startmenu's map when dashboard has none", function()
        local out = Games.migrateShown(nil, { hanoi = true, sudoku = false })
        assert.are.same({ hanoi = true, sudoku = false }, out)
    end)

    it("never overrides a choice made in dashboard", function()
        assert.is_nil(Games.migrateShown({ wordle = true }, { hanoi = true }))
    end)

    it("imports nothing from a startmenu that was never configured", function()
        assert.is_nil(Games.migrateShown(nil, nil))
        assert.is_nil(Games.migrateShown(nil, {}))
    end)

    it("drops malformed entries", function()
        local out = Games.migrateShown(nil, { hanoi = true, [3] = true, x = "yes" })
        assert.are.same({ hanoi = true }, out)
    end)

    it("keeps startmenu's three-state meaning once imported", function()
        -- A game startmenu never listed is still "not decided": the default
        -- applies to it, exactly as it did in startmenu.
        local out = Games.migrateShown(nil, { hanoi = true })
        assert.is_true(Games.isEnabled("sudoku", out, { sudoku = true }))
        assert.is_true(Games.isEnabled("hanoi", out, { sudoku = true }))
        assert.is_false(Games.isEnabled("wordle", out, { sudoku = true }))
    end)
end)

describe("Games.lastPlayed / mostRecent", function()
    local Games
    setup(function() Games = require("games") end)

    it("prefers the later of the stats row and the settings mtime", function()
        assert.are.equal(50, Games.lastPlayed("a", { a = { last_played = 50 } }, { a = 40 }))
        assert.are.equal(60, Games.lastPlayed("a", { a = { last_played = 50 } }, { a = 60 }))
    end)

    it("falls back to whichever source exists", function()
        assert.are.equal(40, Games.lastPlayed("a", {}, { a = 40 }))
        assert.are.equal(50, Games.lastPlayed("a", { a = { last_played = 50 } }, nil))
        assert.is_nil(Games.lastPlayed("a", nil, nil))
    end)

    it("ignores a stats row that is not a table", function()
        assert.is_nil(Games.lastPlayed("a", { a = 7 }, {}))
    end)

    it("picks the installed game played most recently", function()
        local games = { { id = "a" }, { id = "b" }, { id = "c" } }
        local g, ts = Games.mostRecent(games, { a = 10, b = 30, gone = 99 })
        assert.are.equal("b", g.id)
        assert.are.equal(30, ts)
    end)

    it("returns nothing when no installed game was ever played", function()
        assert.is_nil(Games.mostRecent({ { id = "a" } }, { gone = 1 }))
    end)
end)

describe("Games.orderIds", function()
    local Games
    local GAMES = {
        { id = "c", label = "Charlie" }, { id = "a", label = "Alpha" },
        { id = "b", label = "Bravo" },
    }
    setup(function() Games = require("games") end)

    it("defaults to label order", function()
        assert.are.same({ "a", "b", "c" }, Games.orderIds(GAMES, nil))
    end)

    it("keeps the saved order, then appends new games by label", function()
        assert.are.same({ "c", "a", "b" }, Games.orderIds(GAMES, { "c" }))
    end)

    it("drops uninstalled and duplicated ids", function()
        assert.are.same({ "b", "a", "c" }, Games.orderIds(GAMES, { "gone", "b", "b", "a" }))
    end)
end)

describe("Games.moved", function()
    local Games
    setup(function() Games = require("games") end)

    it("swaps with the neighbour", function()
        assert.are.same({ "b", "a", "c" }, Games.moved({ "a", "b", "c" }, "b", -1))
        assert.are.same({ "a", "c", "b" }, Games.moved({ "a", "b", "c" }, "b", 1))
    end)

    it("is a no-op at either end", function()
        assert.are.same({ "a", "b" }, Games.moved({ "a", "b" }, "a", -1))
        assert.are.same({ "a", "b" }, Games.moved({ "a", "b" }, "b", 1))
    end)

    it("jumps over games that are not peers (hidden, other category)", function()
        local peer = function(id) return id ~= "x" end
        assert.are.same({ "c", "x", "a" }, Games.moved({ "a", "x", "c" }, "c", -1, peer))
    end)

    it("is a no-op when the only games beyond are not peers", function()
        local peer = function(id) return id == "a" end
        assert.are.same({ "a", "x" }, Games.moved({ "a", "x" }, "a", 1, peer))
    end)

    it("does not modify its input", function()
        local order = { "a", "b" }
        Games.moved(order, "b", -1)
        assert.are.same({ "a", "b" }, order)
    end)

    it("ignores an unknown id", function()
        assert.are.same({ "a", "b" }, Games.moved({ "a", "b" }, "z", -1))
    end)
end)

describe("Games.arrange", function()
    local Games, Categories
    local GAMES = {
        { id = "sudoku", label = "Sudoku" },
        { id = "hanoi",  label = "Tower of Hanoi" },
        { id = "2048",   label = "2048" },
        { id = "wordle", label = "Wordle" },
        { id = "newgame", label = "Brand New" },
    }
    setup(function()
        Games = require("games")
        Categories = require("categories")
    end)

    local function opts(extra)
        local o = {
            shown = function(id) return id ~= "wordle" end,
            mode = "custom",
            order = { "hanoi", "2048", "sudoku", "wordle", "newgame" },
            last_played = {},
            grouped = true,
            category_of = Categories.of,
            rank = Categories.rank,
        }
        for k, v in pairs(extra or {}) do o[k] = v end
        return o
    end

    local function ids(section)
        local out = {}
        for _, g in ipairs(section.games) do out[#out + 1] = g.id end
        return out
    end

    it("groups by category in category order, unknown games last", function()
        local s = Games.arrange(GAMES, opts())
        assert.are.equal(3, #s)
        assert.are.equal("sudoku", s[1].category)
        assert.are.equal("classic", s[2].category)
        assert.are.equal("other", s[3].category)
        assert.are.same({ "hanoi", "2048" }, ids(s[2]))
    end)

    it("leaves hidden games out", function()
        for _, sec in ipairs(Games.arrange(GAMES, opts())) do
            for _, g in ipairs(sec.games) do assert.are_not.equal("wordle", g.id) end
        end
    end)

    it("puts everything in one section when not grouped", function()
        local s = Games.arrange(GAMES, opts{ grouped = false })
        assert.are.equal(1, #s)
        assert.is_nil(s[1].category)
        assert.are.same({ "hanoi", "2048", "sudoku", "newgame" }, ids(s[1]))
    end)

    it("sorts by last played, never-played games after in custom order", function()
        local s = Games.arrange(GAMES, opts{
            grouped = false, mode = "recent",
            last_played = { sudoku = 10, newgame = 20 },
        })
        assert.are.same({ "newgame", "sudoku", "hanoi", "2048" }, ids(s[1]))
    end)

    it("returns no section at all when nothing is shown", function()
        assert.are.same({}, Games.arrange(GAMES, opts{ shown = function() return false end }))
        assert.are.same({}, Games.arrange(GAMES, opts{ grouped = false,
            shown = function() return false end }))
    end)
end)
