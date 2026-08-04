local _dir         = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local _plugins_dir = _dir:match("^(.*)/[^/]+/$") or (_dir .. "..")

-- Add common/ (game-common copy) and ../game-common/ to the path.
package.path = _dir .. "common/?.lua;" .. package.path

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local DataStorage     = require("datastorage")
local LuaSettings     = require("luasettings")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local Menu            = require("ui/widget/menu")
local RightContainer  = require("ui/widget/container/rightcontainer")
local Screen          = Device.screen
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T               = require("ffi/util").template
local _               = require("i18n")

require("i18n").extend(lrequire("i18n_fr"))
local ok_se, StatsExporter = pcall(require, "stats_exporter")

local NON_GAME_IDS = {
    startmenu     = true,
    pluginmanager = true,
    dashboard     = true,
    _skeleton     = true,
    opdsdir       = true,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function get_lfs()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then ok, lfs = pcall(require, "lfs") end
    return ok and lfs or nil
end

local function reltime(ts)
    if not ts then return "?" end
    local d = os.time() - ts
    if d < 120        then return _("just now")
    elseif d < 3600   then return T(_("%1 min"), math.floor(d / 60))
    elseif d < 86400  then return T(_("%1 h"),   math.floor(d / 3600))
    elseif d < 604800 then return T(_("%1 d"),   math.floor(d / 86400))
    else                   return os.date(_.lang() == "fr" and "%d/%m/%Y" or "%Y-%m-%d", ts)
    end
end

local function fmt_seconds(secs)
    secs = math.floor(secs or 0)
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return string.format("%dh%02d", h, m) end
    return string.format("%dm", m)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Data collection
-- ─────────────────────────────────────────────────────────────────────────────

local function reading_data()
    local ok, RH = pcall(require, "readhistory")
    if not ok then return {}, 0 end
    if RH.reload then RH:reload() end
    local hist = RH.hist or {}

    local ok2, DS = pcall(require, "docsettings")
    local books = {}
    for i = 1, math.min(3, #hist) do
        local it = hist[i]
        local e = {
            title     = it.title or (it.file and it.file:match("([^/]+)$"):gsub("%.[^.]+$", "")) or "?",
            authors   = it.authors,
            last_read = it.time,
            file      = it.file,
            percent   = nil,
        }
        if ok2 and it.file then
            local ok3, ds = pcall(function() return DS:open(it.file) end)
            if ok3 and ds then
                e.percent = ds:readSetting("percent_finished")
            end
        end
        books[#books + 1] = e
    end
    return books, #hist
end

-- Returns: games (played, sorted most-recent first), n_inst, n_played,
-- installed (every non-excluded game plugin, played or not -- the pool the
-- homescreen "random suggestion" row draws from).
local function game_data()
    local lfs = get_lfs()
    if not lfs then return {}, 0, 0, {} end
    local sdir = DataStorage:getSettingsDir()
    local games, installed, n_inst, n_played = {}, {}, 0, 0
    local ok, iter, dobj = pcall(lfs.dir, _plugins_dir)
    if not ok then return {}, 0, 0, {} end
    for entry in iter, dobj do
        if entry:match("%.koplugin$") then
            local f = io.open(_plugins_dir .. "/" .. entry .. "/_meta.lua", "r")
            if f then
                local src      = f:read("*a"); f:close()
                local name     = src:match('name%s*=%s*"([^"]+)"')
                local fullname = src:match('fullname%s*=[^"]*"([^"]*)"')
                if name and not NON_GAME_IDS[name] then
                    n_inst = n_inst + 1
                    local disp = fullname or name
                    installed[#installed + 1] = { name = name, fullname = disp }
                    local mtime = lfs.attributes(sdir .. "/" .. name .. ".lua", "modification")
                    if mtime then
                        n_played = n_played + 1
                        games[#games + 1] = { name = name, fullname = disp, ts = mtime }
                    end
                end
            end
        end
    end
    table.sort(games, function(a, b) return a.ts > b.ts end)
    return games, n_inst, n_played, installed
end

-- Random pick from the full installed-games pool (played or not), re-rolled
-- on every call -- no de-dup against the "recent" list.
local function pick_random_game(installed)
    if not installed or #installed == 0 then return nil end
    return installed[math.random(#installed)]
end

local function stats_data()
    if not ok_se then return {} end
    local all = StatsExporter:readAll()
    local list = {}
    for name, d in pairs(all) do
        if type(d) == "table" and d.sessions then
            list[#list + 1] = {
                name        = name,
                sessions    = d.sessions or 0,
                last_played = d.last_played,
                time_played = d.time_played or 0,
            }
        end
    end
    table.sort(list, function(a, b) return a.sessions > b.sessions end)
    return list
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Simpleui homescreen module ("Games" row)
--
-- Optional: only registered (see Dashboard:init below) when
-- plugins/simpleui.koplugin is installed. Surfaces the same "recent games"
-- data as the Dashboard menu above, as a compact homescreen row.
-- ─────────────────────────────────────────────────────────────────────────────

local GAMES_ROW_H   = Screen:scaleBySize(40)
local GAMES_ROW_PAD = Screen:scaleBySize(10)

local function buildGameRow(w, label, subtitle, on_tap)
    local inner_w  = w - GAMES_ROW_PAD * 2
    local sub_tw   = TextWidget:new{
        text    = subtitle or "",
        face    = Font:getFace("cfont", 14),
        fgcolor = Blitbuffer.COLOR_DARK_GRAY,
    }
    local sub_w    = sub_tw:getSize().w
    local label_tw = TextWidget:new{
        text                   = label,
        face                   = Font:getFace("cfont", 18),
        fgcolor                = Blitbuffer.COLOR_BLACK,
        max_width              = inner_w - sub_w - GAMES_ROW_PAD,
        truncate_with_ellipsis = true,
    }
    local hg = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w - sub_w - GAMES_ROW_PAD, h = GAMES_ROW_H },
            label_tw,
        },
        HorizontalSpan:new{ width = GAMES_ROW_PAD },
        RightContainer:new{
            dimen = Geom:new{ w = sub_w, h = GAMES_ROW_H },
            sub_tw,
        },
    }

    local tappable = InputContainer:new{
        dimen   = Geom:new{ w = inner_w, h = GAMES_ROW_H },
        [1]     = hg,
        _on_tap = on_tap,
    }
    tappable.ges_events = {
        TapGamesRow = {
            GestureRange:new{ ges = "tap", range = function() return tappable.dimen end },
        },
    }
    function tappable:onTapGamesRow()
        if self._on_tap then self._on_tap() end
        return true
    end

    return FrameContainer:new{
        bordersize = 0, padding = GAMES_ROW_PAD, padding_top = 0, padding_bottom = 0,
        tappable,
    }
end

-- Builds the homescreen widget: up to 5 most-recently-played rows followed by
-- 1 random suggestion (re-rolled every call, drawn from every installed game
-- whether played or not). Returns nil when no games are installed, so the
-- module renders at zero height.
local function buildGamesRowWidget(plugin, w)
    local games, _n_inst, _n_played, installed = game_data()
    if #installed == 0 then return nil end

    local function launch(name)
        return function()
            local target = plugin.ui[name]
            if target and type(target.showGame) == "function" then
                target:showGame()
            end
        end
    end

    local vg = VerticalGroup:new{ align = "center" }
    for i = 1, math.min(5, #games) do
        local g = games[i]
        vg[#vg + 1] = buildGameRow(w, g.fullname, reltime(g.ts), launch(g.name))
    end

    local rnd = pick_random_game(installed)
    if rnd then
        vg[#vg + 1] = buildGameRow(w, rnd.fullname, _("Suggestion"), launch(rnd.name))
    end

    return vg
end

-- `plugin` is the live Dashboard instance, captured by closure so row taps
-- can reach `plugin.ui[name]:showGame()` -- mirrors the existing "Recent
-- games" menu callback below.
local function makeGamesRowModule(plugin)
    local M = {}
    M.id          = "dashboard_games_row"
    M.name        = _("Games (Dashboard)")
    M.label       = _("Games")
    M.enabled_key = "dashboard_games_row_enabled"
    M.default_on  = true

    function M.build(w, _ctx)
        return buildGamesRowWidget(plugin, w)
    end

    function M.getHeight(_ctx)
        local games, _n_inst, _n_played, installed = game_data()
        if #installed == 0 then return 0 end
        return (math.min(5, #games) + 1) * GAMES_ROW_H
    end

    return M
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Dashboard plugin
-- ─────────────────────────────────────────────────────────────────────────────

local Dashboard = WidgetContainer:extend{
    name        = "dashboard",
    is_doc_only = false,
}

function Dashboard:ensureSettings()
    if not self.settings then
        self.settings = LuaSettings:open(
            DataStorage:getSettingsDir() .. "/dashboard.lua"
        )
    end
end

function Dashboard:getSetting(key, default)
    self:ensureSettings()
    local v = self.settings:readSetting(key)
    if v == nil then return default end
    return v
end

function Dashboard:saveSetting(key, value)
    self:ensureSettings()
    self.settings:saveSetting(key, value)
    self.settings:flush()
end

function Dashboard:init()
    self:ensureSettings()
    self.ui.menu:registerToMainMenu(self)

    if not self.ui.document and self:getSetting("show_on_startup", false) then
        local delay = self:getSetting("startup_delay", 1.0)
        UIManager:scheduleIn(delay, function() self:show() end)
    end

    -- Register the "Games" row with simpleui's homescreen, if installed.
    -- Only from the FileManager-context instance: `self.ui.document` is only
    -- ever set in ReaderUI, and simpleui's homescreen only ever lives inside
    -- FileManager. Dashboard:init() also runs once per opened book (ReaderUI
    -- creates its own separate instance) -- if that instance also
    -- registered, it would race the FM instance for the single "dashboard_
    -- games_row" id (Registry.register replaces by id), leaving the row
    -- pointing at whichever instance happened to init last, with no benefit.
    --
    -- Deferred past the initial synchronous plugin-loading pass: at this
    -- point in :init(), simpleui.koplugin may not have added its own
    -- directory to package.path yet, so requiring its module registry here
    -- directly would be a coin flip depending on plugin load order.
    if not self.ui.document then
        local self_ref = self
        UIManager:scheduleIn(0, function()
            local ok, Registry = pcall(require, "desktop_modules/moduleregistry")
            if not (ok and Registry) then return end
            Registry.register(makeGamesRowModule(self_ref))
            -- FileManager may have already finished its own :init() and
            -- painted the homescreen before this scheduled callback ran, in
            -- which case the freshly-registered module wouldn't show up
            -- until the next unrelated repaint. Force one now if simpleui
            -- is actually the live homescreen.
            local sui = self_ref.ui.simpleui
            if sui and type(sui._rebuildAllNavbars) == "function" then
                pcall(function() sui:_rebuildAllNavbars() end)
            end
        end)
    end
end

function Dashboard:addToMainMenu(menu_items)
    local self_ref = self
    menu_items.dashboard = {
        text         = _("Dashboard"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text     = _("Open Dashboard"),
                callback = function() self_ref:show() end,
            },
            {
                text         = _("Show at startup"),
                checked_func = function()
                    return self_ref:getSetting("show_on_startup", false)
                end,
                callback     = function()
                    self_ref:saveSetting("show_on_startup",
                        not self_ref:getSetting("show_on_startup", false))
                end,
            },
            {
                text         = T(_("Startup delay: %1 s"), "0.5"),
                checked_func = function()
                    return self_ref:getSetting("startup_delay", 1.0) == 0.5
                end,
                enabled_func = function()
                    return self_ref:getSetting("show_on_startup", false)
                end,
                callback     = function() self_ref:saveSetting("startup_delay", 0.5) end,
            },
            {
                text         = T(_("Startup delay: %1 s"), "1"),
                checked_func = function()
                    return self_ref:getSetting("startup_delay", 1.0) == 1.0
                end,
                enabled_func = function()
                    return self_ref:getSetting("show_on_startup", false)
                end,
                callback     = function() self_ref:saveSetting("startup_delay", 1.0) end,
            },
            {
                text         = T(_("Startup delay: %1 s"), "2"),
                checked_func = function()
                    return self_ref:getSetting("startup_delay", 1.0) == 2.0
                end,
                enabled_func = function()
                    return self_ref:getSetting("show_on_startup", false)
                end,
                callback     = function() self_ref:saveSetting("startup_delay", 2.0) end,
            },
            {
                text         = _("Home button \xE2\x86\x92 Dashboard"),
                checked_func = function()
                    return self_ref:getSetting("home_opens_dashboard", false)
                end,
                callback     = function()
                    self_ref:saveSetting("home_opens_dashboard",
                        not self_ref:getSetting("home_opens_dashboard", false))
                end,
            },
        },
    }
end

function Dashboard:onHome()
    if self.ui.document and self:getSetting("home_opens_dashboard", false) then
        self:show()
        return true
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Menu item builders
-- ─────────────────────────────────────────────────────────────────────────────

local function section_header(title, mandatory)
    return {
        text      = "\xE2\x96\xB6 " .. title:upper(),
        mandatory = mandatory,
        bold      = true,
    }
end

function Dashboard:buildItems(books, n_books, games, n_inst, n_played)
    local self_ref = self
    local items    = {}
    local close_fn

    local function close_and(fn)
        return function()
            if close_fn then close_fn() end
            UIManager:scheduleIn(0.1, fn)
        end
    end

    -- ── Reading ──────────────────────────────────────────────────────────────
    items[#items+1] = section_header(_("Reading"), T(_("Books: %1"), n_books))

    if #books == 0 then
        items[#items+1] = { text = _("No reading history.") }
    else
        for i, b in ipairs(books) do
            local pct  = b.percent and (math.floor(b.percent * 100) .. "%") or nil
            local info = (pct or "") .. (b.last_read and ("  " .. reltime(b.last_read)) or "")
            local bfile = b.file
            local cb = bfile and close_and(function()
                local ReaderUI = require("apps/reader/readerui")
                ReaderUI:showReader(bfile)
            end) or nil
            items[#items+1] = {
                text      = b.title,
                mandatory = info ~= "" and info or nil,
                bold      = (i == 1),
                callback  = cb,
            }
            if b.authors and b.authors ~= "" then
                items[#items+1] = { text = "  " .. b.authors, callback = cb }
            end
        end
    end

    -- ── Recent games ─────────────────────────────────────────────────────────
    items[#items+1] = section_header(_("Recent games"),
        T(_("Plugins installed: %1 — played: %2"), n_inst, n_played))

    if #games == 0 then
        items[#items+1] = { text = _("No games played yet.") }
    else
        for i = 1, math.min(5, #games) do
            local g = games[i]
            items[#items+1] = {
                text      = g.fullname,
                mandatory = reltime(g.ts),
                callback  = close_and(function()
                    local plugin = self_ref.ui[g.name]
                    if plugin and type(plugin.showGame) == "function" then
                        plugin:showGame()
                    end
                end),
            }
        end
    end

    -- ── Play stats ───────────────────────────────────────────────────────────
    local stats = stats_data()
    items[#items+1] = section_header(_("Play stats"))
    if #stats == 0 then
        items[#items+1] = { text = _("No stats yet.") }
    else
        for i = 1, math.min(5, #stats) do
            local s = stats[i]
            local last = s.last_played and reltime(s.last_played) or "?"
            items[#items+1] = {
                text      = s.name,
                mandatory = T(_("%1 sessions · %2"), s.sessions, last),
            }
            if s.time_played and s.time_played > 60 then
                items[#items+1] = {
                    text = "  " .. T(_("Time: %1"), fmt_seconds(s.time_played)),
                }
            end
        end
    end

    -- ── Actions ──────────────────────────────────────────────────────────────
    if self_ref.ui.pluginmanager or self_ref.ui.document then
        items[#items+1] = section_header(_("Actions"))
        if self_ref.ui.pluginmanager then
            items[#items+1] = {
                text     = _("Update plugins"),
                callback = close_and(function()
                    self_ref.ui.pluginmanager:fetchManifest()
                end),
            }
        end
        if self_ref.ui.document then
            items[#items+1] = {
                text     = _("Library"),
                callback = close_and(function() self_ref.ui:onClose() end),
            }
        end
    end

    items[#items+1] = { text = "" }

    return items, function(fn) close_fn = fn end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Show
-- ─────────────────────────────────────────────────────────────────────────────

function Dashboard:show()
    local books, n_books          = reading_data()
    local games, n_inst, n_played = game_data()

    local items, set_close = self:buildItems(books, n_books, games, n_inst, n_played)

    local menu_widget = Menu:new{
        title         = _("Dashboard"),
        item_table    = items,
        is_borderless = true,
        is_popout     = false,
        width         = Screen:getWidth(),
        height        = Screen:getHeight(),
        onMenuHold    = function() end,
    }

    set_close(function() UIManager:close(menu_widget) end)

    function menu_widget:onMenuChoice(item)
        if item.callback then item.callback() end
    end

    UIManager:show(menu_widget)
end

return Dashboard
