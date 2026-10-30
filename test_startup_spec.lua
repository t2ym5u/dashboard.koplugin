-- When the dashboard opens on its own. The trap is "at launch only":
-- FileManager is rebuilt every time a book closes, so a check made per plugin
-- instance would fire again after every book.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("Startup.shouldShow", function()
    local S
    setup(function() S = require("startup") end)

    it("never shows over an open book", function()
        for _, mode in ipairs({ "launch", "filemanager", "never" }) do
            assert.is_false(S.shouldShow(mode, true, true), mode)
        end
    end)

    it("at launch: only for the first instance of the run", function()
        assert.is_true(S.shouldShow("launch", false, true))
        -- the file browser rebuilt after closing a book
        assert.is_false(S.shouldShow("launch", false, false))
    end)

    it("every file browser: also after closing a book", function()
        assert.is_true(S.shouldShow("filemanager", false, true))
        assert.is_true(S.shouldShow("filemanager", false, false))
    end)

    it("never: never", function()
        assert.is_false(S.shouldShow("never", false, true))
    end)

    it("treats an unknown mode as the default", function()
        assert.is_true(S.shouldShow("bogus", false, true))
        assert.is_false(S.shouldShow("bogus", false, false))
    end)
end)

describe("Startup.resolveMode", function()
    local S
    setup(function() S = require("startup") end)

    it("keeps a mode that is already set", function()
        assert.are.equal("filemanager", S.resolveMode("filemanager", false, { enabled = false }))
        assert.are.equal("never", S.resolveMode("never", true, nil))
    end)

    it("defaults to launch on a fresh install", function()
        assert.are.equal("launch", S.resolveMode(nil, nil, nil))
    end)

    it("carries the old 'Show at startup' toggle over", function()
        assert.are.equal("launch", S.resolveMode(nil, true, nil))
        assert.are.equal("never", S.resolveMode(nil, false, nil))
    end)

    it("keeps a startup screen for a startmenu user", function()
        assert.are.equal("launch", S.resolveMode(nil, nil, { enabled = true }))
        -- startmenu's `enabled` defaulted to true when never written
        assert.are.equal("launch", S.resolveMode(nil, false, { enabled_games = {} }))
    end)

    it("respects startmenu switched off, unless dashboard's own was on", function()
        assert.are.equal("never", S.resolveMode(nil, nil, { enabled = false }))
        assert.are.equal("never", S.resolveMode(nil, false, { enabled = false }))
        assert.are.equal("launch", S.resolveMode(nil, true, { enabled = false }))
    end)

    it("ignores an invalid saved mode", function()
        assert.are.equal("launch", S.resolveMode("sometimes", nil, nil))
    end)
end)
