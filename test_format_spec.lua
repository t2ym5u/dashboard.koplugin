-- These two functions decide what every row of the dashboard says about when a
-- book or a game was last touched. They are pure arithmetic on a timestamp, so
-- the interesting part is the boundaries -- and a boundary is exactly the thing
-- that reads fine on screen while being one second wrong.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

package.preload["i18n"] = function()
    local i18n = setmetatable({}, { __call = function(_, s) return s end })
    i18n.lang = function() return "en" end
    return i18n
end
package.preload["ffi/util"] = function()
    return {
        template = function(fmt, ...)
            local args = { ... }
            return (fmt:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
        end,
    }
end
package.path = DIR .. "?.lua;" .. package.path

describe("Format.reltime", function()
    local Format
    local NOW = 1735689600  -- 2025-01-01 00:00:00 UTC, a fixed instant

    setup(function()
        Format = require("format")
    end)

    it("says '?' when there is no timestamp at all", function()
        assert.are.equal("?", Format.reltime(nil, NOW))
    end)

    it("says 'just now' for anything under two minutes", function()
        assert.are.equal("just now", Format.reltime(NOW, NOW))
        assert.are.equal("just now", Format.reltime(NOW - 119, NOW))
    end)

    it("switches to minutes at exactly two minutes", function()
        assert.are.equal("2 min", Format.reltime(NOW - 120, NOW))
        assert.are.equal("59 min", Format.reltime(NOW - 3599, NOW))
    end)

    it("switches to hours at exactly one hour", function()
        assert.are.equal("1 h", Format.reltime(NOW - 3600, NOW))
        assert.are.equal("23 h", Format.reltime(NOW - 86399, NOW))
    end)

    it("switches to days at exactly one day", function()
        assert.are.equal("1 d", Format.reltime(NOW - 86400, NOW))
        assert.are.equal("6 d", Format.reltime(NOW - 604799, NOW))
    end)

    it("falls back to a date at exactly one week", function()
        local out = Format.reltime(NOW - 604800, NOW)
        assert.is_nil(out:find("d$"), "still relative at one week: " .. out)
        assert.is_truthy(out:match("^%d%d%d%d%-%d%d%-%d%d$"), "not a date: " .. out)
    end)

    it("rounds down rather than up, so a row never claims more than elapsed", function()
        assert.are.equal("2 min", Format.reltime(NOW - 179, NOW))   -- 2 min 59 s
        assert.are.equal("1 h",   Format.reltime(NOW - 7199, NOW))  -- 1 h 59 min
    end)

    it("does not go backwards on a timestamp from the future", function()
        -- A device whose clock jumped, or a file synced from another machine.
        assert.are.equal("just now", Format.reltime(NOW + 3600, NOW))
    end)
end)

describe("Format.fmt_seconds", function()
    local Format

    setup(function()
        Format = require("format")
    end)

    it("reads minutes only under an hour", function()
        assert.are.equal("0m", Format.fmt_seconds(0))
        assert.are.equal("0m", Format.fmt_seconds(59))
        assert.are.equal("1m", Format.fmt_seconds(60))
        assert.are.equal("59m", Format.fmt_seconds(3599))
    end)

    it("pads the minutes once hours appear, so 2h5 never shows", function()
        assert.are.equal("1h00", Format.fmt_seconds(3600))
        assert.are.equal("1h05", Format.fmt_seconds(3900))
        assert.are.equal("2h30", Format.fmt_seconds(9000))
    end)

    it("treats a missing or fractional count as whole seconds", function()
        assert.are.equal("0m", Format.fmt_seconds(nil))
        assert.are.equal("1m", Format.fmt_seconds(60.9))
    end)
end)
