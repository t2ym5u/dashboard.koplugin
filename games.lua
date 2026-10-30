-- games.lua -- game discovery, the "which games show" model and the grid order.
--
-- Ported from startmenu.koplugin/games.lua (isEnabled, toggled and sorted
-- unchanged; parseMeta fixed for long-bracket labels) and extended with what the dashboard grid needs:
-- daily-challenge support detection, last-played bookkeeping, custom order,
-- and grouping by category.
--
-- None of it needs KOReader: reading an id out of a _meta.lua is string
-- matching, and deciding whether a game shows is a three-way answer
-- (explicitly on, explicitly off, never touched) that is easy to collapse
-- into two by accident.

local Games = {}

-- Plugin IDs that are infrastructure, not games.
Games.NON_GAME_IDS = {
    startmenu     = true,
    pluginmanager = true,
    dashboard     = true,
    opdsdir       = true,
    _skeleton     = true,
}

-- Games shown by default when they are first discovered (startmenu's own
-- defaults). Main adds the most recently played games on top of these, see
-- Games.withRecent. Everything else a player installs starts hidden, so the
-- grid does not grow on its own.
Games.DEFAULT_ENABLED = {
    sudoku      = true,
    ["2048"]    = true,
    minesweeper = true,
    mastermind  = true,
}

-- Build { id, label } for one plugin. Returns nil for infrastructure.
--
-- `id` is the plugin directory's basename, and that is deliberate: this used
-- to read a `name` field out of the _meta.lua source, which none of these
-- plugins actually declares -- so the menu came up empty -- and which KOReader
-- 2026.03 (PR #15096) deprecated anyway, PluginLoader now overwriting it with
-- the directory name. `src` is the _meta.lua source, read only for the label.
-- The string literal at the start of `s`: "...", '...' or [[...]] / [==[...]==].
local function leadingString(s)
    local v = s:match('^"([^"\n]*)"') or s:match("^'([^'\n]*)'")
    if v then return v end
    local _eq, body = s:match("^%[(=*)%[(.-)%]%1%]")
    return body
end

function Games.parseMeta(src, id, non_game_ids)
    if type(id) ~= "string" or id == "" then return nil end
    if (non_game_ids or Games.NON_GAME_IDS)[id] then return nil end
    -- %f[%w] is a frontier pattern: it anchors to the start of the word, so
    -- `fullname =` is matched here and not some other key ending in "fullname".
    -- The value is a string literal, bare or wrapped in _(): fullname =
    -- _("Sokoban"), or _([[Sudoku]]) as the sudoku family writes it. startmenu
    -- skipped to the next double quote instead, which on those plugins was
    -- the one around `version` -- Sudoku was listed as "2.5.0".
    local fullname
    local rest = type(src) == "string" and src:match("%f[%w]fullname%s*=%s*(.*)")
    if rest then
        rest = rest:gsub("^_%s*%(%s*", "", 1)
        fullname = leadingString(rest)
    end
    return { id = id, label = (fullname and #fullname > 0) and fullname or id }
end

-- How a game offers today's puzzle, judged from its sources:
--   "plugin" -- the plugin has its own :showDailyChallenge() (sudoku, with a
--               separate save slot for the daily grid);
--   "screen" -- its screen wires game-common's ScreenBase:onDailyGame()
--               (the title-bar "Daily Challenge" entry), or overrides it;
--   nil      -- no daily mode. ScreenBase defines onDailyGame for every game,
--               but it only means something for a puzzle generated from
--               math.random, which is exactly the set that opted in.
function Games.dailyKind(main_src, screen_src)
    if type(main_src) == "string" and main_src:find(":showDailyChallenge%(") then
        return "plugin"
    end
    if type(screen_src) == "string"
        and (screen_src:find("makeDailyButtonConfig", 1, true)
             or screen_src:find(":onDailyGame%(")) then
        return "screen"
    end
    return nil
end

-- Does game `gid` belong in the grid?
-- `saved` is the persisted id -> boolean map, or nil when the player has never
-- opened the game list. A game absent from a saved map is one installed since
-- the last toggle, so it falls back to the default rather than to "off".
function Games.isEnabled(gid, saved, defaults)
    defaults = defaults or Games.DEFAULT_ENABLED
    if not saved or saved[gid] == nil then
        return defaults[gid] == true
    end
    return saved[gid] == true
end

-- The map to persist after toggling `gid`: every known game gets an explicit
-- entry, so a later change to the defaults cannot silently move a game the
-- player has already made a decision about.
function Games.toggled(games, gid, saved, defaults)
    local next_state = {}
    for _, g in ipairs(games) do
        next_state[g.id] = Games.isEnabled(g.id, saved, defaults)
    end
    next_state[gid] = not next_state[gid]
    return next_state
end

-- Sort by the label the player actually reads, not by id.
function Games.sorted(games)
    table.sort(games, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end)
    return games
end

-- ---------------------------------------------------------------------------
-- Defaults and migration
-- ---------------------------------------------------------------------------

-- The default shown set: `defaults` plus the `n` most recently played games.
-- `last_played` is id -> timestamp. Only consulted while the player has never
-- toggled anything (see isEnabled), so a game played for the first time then
-- appears on its own -- until the first toggle freezes the list.
function Games.withRecent(defaults, last_played, n)
    local out = {}
    for id, on in pairs(defaults or {}) do out[id] = on end
    local recent = {}
    for id, ts in pairs(last_played or {}) do
        if type(ts) == "number" then recent[#recent + 1] = { id = id, ts = ts } end
    end
    table.sort(recent, function(a, b)
        if a.ts ~= b.ts then return a.ts > b.ts end
        return a.id < b.id
    end)
    for i = 1, math.min(n or 0, #recent) do out[recent[i].id] = true end
    return out
end

-- One-time import of startmenu's game list (settings/startmenu.lua,
-- `enabled_games`, the same id -> boolean map with the same three-state
-- meaning). Returns the map dashboard should save, or nil to save nothing:
-- the dashboard's own choice always wins, and a startmenu that was never
-- configured has nothing to carry over.
function Games.migrateShown(dash_saved, startmenu_saved)
    if dash_saved ~= nil then return nil end
    if type(startmenu_saved) ~= "table" then return nil end
    local out, any = {}, false
    for id, on in pairs(startmenu_saved) do
        if type(id) == "string" and type(on) == "boolean" then
            out[id] = on
            any = true
        end
    end
    return any and out or nil
end

-- ---------------------------------------------------------------------------
-- Last played
-- ---------------------------------------------------------------------------

-- When was game `id` last played? The shared game_stats.lua row
-- (`stats[id].last_played`, written when a game screen closes) is the real
-- answer; the mtime of the game's own settings file is the fallback for a
-- game that predates StatsExporter or never closed cleanly.
function Games.lastPlayed(id, stats, mtimes)
    local rec = stats and stats[id]
    local ts = type(rec) == "table" and rec.last_played or nil
    local mt = mtimes and mtimes[id]
    if ts and mt then return math.max(ts, mt) end
    return ts or mt
end

-- The game for the "Resume" button: the installed game played most recently.
function Games.mostRecent(games, last_played)
    local best, best_ts
    for _, g in ipairs(games) do
        local ts = last_played[g.id]
        if ts and (not best_ts or ts > best_ts) then best, best_ts = g, ts end
    end
    return best, best_ts
end

-- ---------------------------------------------------------------------------
-- Order and grouping
-- ---------------------------------------------------------------------------

-- The full custom order: ids from `saved` that still exist, in that order,
-- then every other game by label. A stale id (an uninstalled game) is dropped
-- rather than kept as a hole.
function Games.orderIds(games, saved)
    local known, by_id = {}, {}
    for _, g in ipairs(games) do by_id[g.id] = g end
    local out = {}
    for _, id in ipairs(saved or {}) do
        if by_id[id] and not known[id] then
            known[id] = true
            out[#out + 1] = id
        end
    end
    local rest = {}
    for _, g in ipairs(games) do
        if not known[g.id] then rest[#rest + 1] = g end
    end
    Games.sorted(rest)
    for _, g in ipairs(rest) do out[#out + 1] = g.id end
    return out
end

-- Move `id` one step (delta = -1 up, +1 down) within `order`, skipping over
-- games for which `peer(other_id)` is false -- hidden games and, when the
-- grid is grouped, games of another category. Moving past the first or
-- last peer is a no-op. Returns a new list.
function Games.moved(order, id, delta, peer)
    local out = {}
    for i, v in ipairs(order) do out[i] = v end
    local pos
    for i, v in ipairs(out) do
        if v == id then pos = i break end
    end
    if not pos then return out end
    local j = pos + delta
    while out[j] ~= nil and not (peer == nil or peer(out[j])) do j = j + delta end
    if out[j] == nil then return out end
    out[pos], out[j] = out[j], out[pos]
    return out
end

-- Arrange the shown games into sections for the grid.
-- opts:
--   shown       fn(id) -> bool
--   mode        "custom" (by `order`) or "recent" (last played first, never
--               played ones after them in custom order)
--   order       full id list from orderIds
--   last_played id -> timestamp
--   grouped     true: one section per category, in category order
--   category_of fn(id) -> category id
--   rank        fn(category id) -> number
-- Returns { { category = <id or nil>, games = { game, ... } }, ... }; empty
-- sections are left out.
function Games.arrange(games, opts)
    local pos = {}
    for i, id in ipairs(opts.order or {}) do pos[id] = i end
    local lp = opts.last_played or {}
    local list = {}
    for _, g in ipairs(games) do
        if not opts.shown or opts.shown(g.id) then list[#list + 1] = g end
    end
    local big = #list + #(opts.order or {}) + 1
    local function custom_lt(a, b)
        local pa, pb = pos[a.id] or big, pos[b.id] or big
        if pa ~= pb then return pa < pb end
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end
    local lt = custom_lt
    if opts.mode == "recent" then
        lt = function(a, b)
            local ta, tb = lp[a.id], lp[b.id]
            if ta and tb and ta ~= tb then return ta > tb end
            if ta and not tb then return true end
            if tb and not ta then return false end
            return custom_lt(a, b)
        end
    end
    table.sort(list, lt)
    if not opts.grouped then
        if #list == 0 then return {} end
        return { { category = nil, games = list } }
    end
    local sections, by_cat = {}, {}
    for _, g in ipairs(list) do
        local c = opts.category_of(g.id)
        if not by_cat[c] then
            by_cat[c] = { category = c, games = {} }
            sections[#sections + 1] = by_cat[c]
        end
        local s = by_cat[c].games
        s[#s + 1] = g
    end
    table.sort(sections, function(a, b)
        local ra, rb = opts.rank(a.category), opts.rank(b.category)
        if ra ~= rb then return ra < rb end
        return a.category < b.category
    end)
    return sections
end

return Games
