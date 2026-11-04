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
    bookdrop      = true,
    quickcalc     = true,
    converter     = true,
    stopwatch     = true,
    almanac       = true,
    reference     = true,
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

-- dailyKind() needs a game's main.lua and screen.lua, about 2 MB of Lua
-- across the fleet: reading all of it on every launch took most of a second
-- on a Kobo. The answer only changes when one of those files does, so it is
-- cached, keyed on the game's version and both files' modification time and
-- size (a stat, no read). `meta_src` is the _meta.lua already read for the
-- label; `main_attr` / `screen_attr` are lfs.attributes() tables or nil.
function Games.dailyCacheKey(meta_src, main_attr, screen_attr)
    local version = type(meta_src) == "string"
        and meta_src:match("%f[%w]version%s*=%s*[\"']([^\"'\n]*)[\"']") or "?"
    local function stamp(a)
        if type(a) ~= "table" then return "-" end
        return tostring(a.modification) .. ":" .. tostring(a.size)
    end
    return version .. "|" .. stamp(main_attr) .. "|" .. stamp(screen_attr)
end

-- Does the game also have a mode for several players (game-common 1.10.0+
-- PluginBase.party_mode, listed under Tools -> Games as "<game> · multiplayer")?
-- Judged from its main.lua, where the plugin class declares it.
function Games.partyMode(main_src)
    return type(main_src) == "string"
        and main_src:find("%f[%w_]party_mode%s*=%s*true") ~= nil
end

-- What the scan learns from a game's sources -- its daily kind and whether
-- it has a party mode -- from `cache` (id -> { key, daily, party }), or calls
-- compute() (-> daily kind or nil, party boolean) and records the answer.
-- Returns daily (or nil), party (boolean) and whether the cache changed.
-- Absent answers are stored as false, so that an entry written before a
-- field existed (1.6.0 cached no `party`) is recognised as stale.
function Games.cachedInfo(cache, id, key, compute)
    local e = cache[id]
    if type(e) == "table" and e.key == key and e.party ~= nil then
        return e.daily or nil, e.party == true, false
    end
    local kind, party = compute()
    cache[id] = { key = key, daily = kind or false, party = party == true }
    return kind or nil, party == true, true
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
-- Sort key: lower case with the accents of Latin letters dropped, so that
-- "Échecs" sorts among the e's rather than after z.
local FOLD = {}
for plain, accented in pairs({
    a = "àáâãäåÀÁÂÃÄÅ", c = "çÇ", e = "èéêëÈÉÊË", i = "ìíîïÌÍÎÏ", n = "ñÑ",
    o = "òóôõöÒÓÔÕÖ", u = "ùúûüÙÚÛÜ", y = "ýÿÝ",
}) do
    for ch in accented:gmatch("[\xC0-\xDF][\x80-\xBF]") do FOLD[ch] = plain end
end

function Games.sortKey(label)
    return (label:gsub("[\xC0-\xDF][\x80-\xBF]", FOLD)):lower()
end

-- Alphabetical by label (sortKey), then by id.
local function label_lt(a, b)
    local ka, kb = Games.sortKey(a.label), Games.sortKey(b.label)
    if ka ~= kb then return ka < kb end
    return a.id < b.id
end

function Games.sorted(games)
    table.sort(games, label_lt)
    return games
end

-- ---------------------------------------------------------------------------
-- Defaults and migration
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Multiplayer tiles
-- ---------------------------------------------------------------------------

-- A game with a party mode gets a second tile, "<game> · multiplayer", that
-- opens that mode directly. Its id is the game's id plus this suffix -- the
-- same id game-common's Tools -> Games menu gives that entry.
Games.PARTY_SUFFIX = ":party"

function Games.isPartyId(id)
    return type(id) == "string"
        and id:sub(-#Games.PARTY_SUFFIX) == Games.PARTY_SUFFIX
end

-- A multiplayer tile's label from the translated "%1 · multiplayer" `fmt`:
-- the spaces of the mode's part are made non-breaking, so a tile too narrow
-- for one line breaks before " · à plusieurs" rather than inside it
-- ("Chiffres et Lettres" / "· à plusieurs", not "... · à" / "plusieurs").
function Games.partyLabel(fmt, name)
    local pre, post = fmt:match("^(.-)%%1(.*)$")
    if not pre then return fmt end
    local lead, rest = post:match("^(%s*)(.*)$")
    rest = rest:gsub(" ", "\u{00A0}")
    return pre .. name .. lead .. rest
end

-- The mode part of `fmt` on its own: "· à plusieurs" for "%1 · à plusieurs"
-- -- the second line of a two-line multiplayer tile.
function Games.partyModeText(fmt)
    local pre, post = fmt:match("^(.-)%%1(.*)$")
    if not pre then return fmt end
    return ((pre .. " " .. post):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s%s+", " "))
end

-- Everything the grid can show: each game (as its solo tile, `mode` "solo"
-- when it also has a party mode, nil otherwise -- older games' showGame()
-- takes no mode) plus a party tile for each game whose `party` is set:
--   { id = "<id>:party", base_id = <id>, label = partyLabel(fmt, name),
--     name = <game label>, mode_text = partyModeText(fmt),
--     category = "party", mode = "party", party_tile = true }
-- `fmt` is the translated "%1 · multiplayer". Sorted by label, so a party
-- tile falls next to its game.
function Games.withPartyTiles(games, fmt)
    local out = {}
    for _, g in ipairs(games) do
        g.mode = g.party and "solo" or nil
        out[#out + 1] = g
        if g.party then
            out[#out + 1] = {
                id         = g.id .. Games.PARTY_SUFFIX,
                base_id    = g.id,
                label      = Games.partyLabel(fmt, g.label),
                name       = g.label,
                mode_text  = Games.partyModeText(fmt),
                category   = "party",
                mode       = "party",
                party_tile = true,
            }
        end
    end
    return Games.sorted(out)
end

-- The default shown set: `defaults` plus the `n` most recently played games.
-- `last_played` is id -> timestamp. Only consulted while the player has never
-- toggled anything (see isEnabled), so a game played for the first time then
-- appears on its own -- until the first toggle freezes the list.
function Games.withRecent(defaults, last_played, n)
    local out = {}
    for id, on in pairs(defaults or {}) do out[id] = on end
    local recent = {}
    for id, ts in pairs(last_played or {}) do
        -- A multiplayer tile is never added on its own: the player picks it.
        if type(ts) == "number" and not Games.isPartyId(id) then
            recent[#recent + 1] = { id = id, ts = ts }
        end
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

-- When was each tile last played, `tiles` from withPartyTiles? A game
-- without a party mode: lastPlayed(). One with a party mode has two tiles
-- that must not mirror each other, so they read the per-mode timestamps
-- game-common's PluginBase writes in the same row:
--   party tile  last_party_played;
--   solo tile   last_solo_played, else last_played when it is later than
--               last_party_played (a session after the last party one was a
--               solo one -- or the game predates per-mode timestamps); the
--               settings file's mtime only when the game has no stats row,
--               since both modes touch that file.
function Games.tilesLastPlayed(tiles, stats, mtimes)
    local map = {}
    for _, t in ipairs(tiles) do
        local base = t.base_id or t.id
        local rec = stats and stats[base]
        rec = type(rec) == "table" and rec or nil
        local party_ts = rec and tonumber(rec.last_party_played) or nil
        if t.party_tile then
            map[t.id] = party_ts
        elseif t.party then
            if not rec then
                map[t.id] = mtimes and mtimes[base]
            else
                local solo = tonumber(rec.last_solo_played)
                local any = tonumber(rec.last_played)
                if not solo and any and (not party_ts or any > party_ts) then
                    solo = any
                end
                map[t.id] = solo
            end
        else
            map[t.id] = Games.lastPlayed(t.id, stats, mtimes)
        end
    end
    return map
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
        return label_lt(a, b)
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
