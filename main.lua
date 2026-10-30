local _dir         = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local _plugins_dir = _dir:match("^(.*)/[^/]+/$") or (_dir .. "..")

-- Add common/ (game-common copy) to the path.
package.path = _dir .. "common/?.lua;" .. package.path

-- This plugin's own modules are loaded by path, not by name: names like
-- "games" or "layout" are shared by every plugin in package.loaded.
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
local InfoMessage     = require("ui/widget/infomessage")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local Menu            = require("ui/widget/menu")
local RightContainer  = require("ui/widget/container/rightcontainer")
local Screen          = Device.screen
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T               = require("ffi/util").template
local _               = require("i18n")

require("i18n").extend(lrequire("i18n_fr"))
local ok_se, StatsExporter = pcall(require, "stats_exporter")

local Categories  = lrequire("categories")
local Daily       = lrequire("daily")
local Format      = lrequire("format")
local Games       = lrequire("games")
local Layout      = lrequire("layout")
local Startup     = lrequire("startup")
local Widgets     = lrequire("widgets")
local HomeScreen  = lrequire("home_screen")
local ChooseGames = lrequire("games_screen")
HomeScreen.setModules(Layout, Format, Widgets)
ChooseGames.setModules(Layout, Widgets)

local reltime     = Format.reltime
local fmt_seconds = Format.fmt_seconds

-- How many recently played games join Games.DEFAULT_ENABLED in the default
-- shown set (before the player has chosen anything).
local RECENT_DEFAULTS = 6

-- ─────────────────────────────────────────────────────────────────────────────
-- Per-process state
--
-- PluginLoader:loadPlugins() dofile()s this file once per KOReader process
-- and caches the module, while a new Dashboard instance is built for every
-- FileManager (rebuilt each time a book closes) and every ReaderUI. These
-- locals therefore live for the whole run, across all instances.
-- ─────────────────────────────────────────────────────────────────────────────

-- Has any Dashboard instance been initialised yet in this run? The first one
-- is "the launch"; see Startup.shouldShow.
local instance_seen = false

-- Installed games, scanned once per run: installing or removing a plugin
-- needs a restart to take effect anyway.
local scanned_games

-- ─────────────────────────────────────────────────────────────────────────────
-- Data collection
-- ─────────────────────────────────────────────────────────────────────────────

local function get_lfs()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then ok, lfs = pcall(require, "lfs") end
    return ok and lfs or nil
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local src = f:read("*a")
    f:close()
    return src
end

-- Every installed game of this fleet, as { id, label, category, daily },
-- sorted by label. Ported from startmenu's scan.
local function scan_games()
    if scanned_games then return scanned_games end
    local games = {}
    local lfs = get_lfs()
    local ok, iter, dobj
    if lfs then ok, iter, dobj = pcall(lfs.dir, _plugins_dir) end
    if ok and iter then
        for entry in iter, dobj do
            if entry:match("%.koplugin$") then
                local pdir = _plugins_dir .. "/" .. entry
                -- The plugin id is the directory basename: KOReader 2026.03
                -- (PR #15096) made it the only plugin id there is.
                local id = entry:gsub("%.koplugin$", "")
                -- Shipping a common/ dir (game-common or sudoku-common) is
                -- what tells this fleet apart from KOReader's own plugins,
                -- none of which have one. checkers is the single game with
                -- no shared library of its own.
                local is_ours = id == "checkers"
                    or lfs.attributes(pdir .. "/common", "mode") == "directory"
                local meta = is_ours and read_file(pdir .. "/_meta.lua")
                local g = meta and Games.parseMeta(meta, id)
                if g then
                    -- Each game's own i18n_fr.lua has extended the shared
                    -- table with its name by now (the scan is lazy, long
                    -- after every plugin's main.lua ran).
                    g.label = _(g.label)
                    g.category = Categories.of(id)
                    g.daily = Games.dailyKind(read_file(pdir .. "/main.lua"),
                                              read_file(pdir .. "/screen.lua"))
                    games[#games + 1] = g
                end
            end
        end
    end
    scanned_games = Games.sorted(games)
    return scanned_games
end

-- id -> last played timestamp, for every installed game ever played.
local function last_played_map(games)
    local stats = ok_se and StatsExporter:readAll() or {}
    local mtimes = {}
    local lfs = get_lfs()
    if lfs then
        local sdir = DataStorage:getSettingsDir()
        for _i, g in ipairs(games) do
            mtimes[g.id] = lfs.attributes(sdir .. "/" .. g.id .. ".lua", "modification")
        end
    end
    local map = {}
    for _i, g in ipairs(games) do
        map[g.id] = Games.lastPlayed(g.id, stats, mtimes)
    end
    return map
end

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

-- Played games (most recent first) and the installed pool, in the shape the
-- statistics page and the simpleui row have always used.
local function game_data()
    local installed_games = scan_games()
    local lp = last_played_map(installed_games)
    local games, installed = {}, {}
    for _i, g in ipairs(installed_games) do
        installed[#installed + 1] = { name = g.id, fullname = g.label }
        if lp[g.id] then
            games[#games + 1] = { name = g.id, fullname = g.label, ts = lp[g.id] }
        end
    end
    table.sort(games, function(a, b) return a.ts > b.ts end)
    return games, #installed, #games, installed
end

local function stats_data()
    if not ok_se then return {} end
    local all = StatsExporter:readAll()
    local label = {}
    for _i, g in ipairs(scan_games()) do label[g.id] = g.label end
    local list = {}
    for name, d in pairs(all) do
        if type(d) == "table" and d.sessions then
            list[#list + 1] = {
                name        = label[name] or name,
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
-- data as the dashboard, as a compact homescreen row.
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

-- Up to 5 most-recently-played rows followed by 1 random suggestion
-- (re-rolled every call, drawn from every installed game whether played or
-- not). Returns nil when no games are installed, so the module renders at
-- zero height.
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

    local rnd = installed[math.random(#installed)]
    vg[#vg + 1] = buildGameRow(w, rnd.fullname, _("Suggestion"), launch(rnd.name))

    return vg
end

-- `plugin` is the live Dashboard instance, captured by closure so row taps
-- can reach `plugin.ui[name]:showGame()`.
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
    -- settings_file must be a field, not a local. KOReader's PluginLoader
    -- reads instance.settings_file to decide whether to offer "Delete plugin
    -- settings", and removes the file itself (2026.07, PR #15240). Compute
    -- the path inline and the option never appears at all, leaving the file
    -- behind when the plugin is deleted.
    if not self.settings_file then
        self.settings_file = DataStorage:getSettingsDir() .. "/dashboard.lua"
    end
    if not self.settings then
        self.settings = LuaSettings:open(self.settings_file)
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

-- startmenu.koplugin's settings (settings/startmenu.lua), or nil when the
-- file does not exist -- startmenu only wrote it once something was toggled.
local function read_startmenu_settings()
    local lfs = get_lfs()
    local path = DataStorage:getSettingsDir() .. "/startmenu.lua"
    if not lfs or lfs.attributes(path, "mode") ~= "file" then return nil end
    local ok, s = pcall(LuaSettings.open, LuaSettings, path)
    return ok and s and s.data or nil
end

-- One-time settings migration (settings_version 2, the home-screen release):
--   * show_on_startup (bool) becomes startup_mode (launch/filemanager/never),
--     also honouring startmenu's `enabled` -- see Startup.resolveMode;
--   * startmenu's `enabled_games` becomes shown_games, unless dashboard
--     already has its own list.
-- startmenu's file is only read, never modified or deleted.
function Dashboard:migrateSettings()
    if self:getSetting("settings_version", 1) >= 2 then return end
    local sm = read_startmenu_settings()
    self.settings:saveSetting("startup_mode", Startup.resolveMode(
        self.settings:readSetting("startup_mode"),
        self.settings:readSetting("show_on_startup"),
        sm))
    self.settings:delSetting("show_on_startup")
    local shown = Games.migrateShown(self.settings:readSetting("shown_games"),
                                     sm and sm.enabled_games)
    if shown then self.settings:saveSetting("shown_games", shown) end
    self.settings:saveSetting("settings_version", 2)
    self.settings:flush()
end

function Dashboard:getStartupMode()
    local m = self:getSetting("startup_mode", Startup.DEFAULT)
    return Startup.isValid(m) and m or Startup.DEFAULT
end

function Dashboard:init()
    self:ensureSettings()
    self:migrateSettings()
    self.ui.menu:registerToMainMenu(self)

    local first_in_run = not instance_seen
    instance_seen = true
    if Startup.shouldShow(self:getStartupMode(), self.ui.document ~= nil, first_in_run) then
        local delay = self:getSetting("startup_delay", 1.0)
        UIManager:scheduleIn(delay, function()
            -- In the meantime a book may have been opened (this FileManager is
            -- then gone) -- the dashboard must never pop up over a book.
            local FM  = package.loaded["apps/filemanager/filemanager"]
            local RUI = package.loaded["apps/reader/readerui"]
            if RUI and RUI.instance then return end
            if FM and FM.instance and FM.instance ~= self.ui then return end
            self:show()
        end)
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

-- KOReader >= 2026.07 (PluginLoader, PR #15240): close our screens before the
-- plugin directory is deleted.
function Dashboard:stopPlugin()
    if self._home then UIManager:close(self._home) end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Game selection model
-- ─────────────────────────────────────────────────────────────────────────────

function Dashboard:categoryLabel(cat)
    return _(Categories.LABELS[cat] or Categories.LABELS.other)
end

function Dashboard:getSortMode()
    local m = self:getSetting("sort_mode", "custom")
    return m == "recent" and "recent" or "custom"
end

function Dashboard:isGrouped()
    return self:getSetting("group_by_category", true) ~= false
end

-- The defaults a never-configured player sees: startmenu's four plus the
-- most recently played games. Cached per show (see buildModel).
function Dashboard:shownDefaults()
    if not self._defaults then
        self._last_played = self._last_played or last_played_map(scan_games())
        self._defaults = Games.withRecent(Games.DEFAULT_ENABLED, self._last_played, RECENT_DEFAULTS)
    end
    return self._defaults
end

function Dashboard:isShown(id)
    return Games.isEnabled(id, self:getSetting("shown_games", nil), self:shownDefaults())
end

function Dashboard:toggleShown(id)
    self:saveSetting("shown_games", Games.toggled(scan_games(), id,
        self:getSetting("shown_games", nil), self:shownDefaults()))
end

-- Move a shown game one place within its group (custom order only).
function Dashboard:moveGame(id, delta)
    local games = scan_games()
    local order = Games.orderIds(games, self:getSetting("game_order", nil))
    local grouped = self:isGrouped()
    local cat = Categories.of(id)
    local peer = function(other)
        return self:isShown(other) and (not grouped or Categories.of(other) == cat)
    end
    self:saveSetting("game_order", Games.moved(order, id, delta, peer))
end

function Dashboard:arrangeOpts(shown)
    local games = scan_games()
    return {
        shown       = shown,
        mode        = self:getSortMode(),
        order       = Games.orderIds(games, self:getSetting("game_order", nil)),
        last_played = self._last_played or {},
        grouped     = self:isGrouped(),
        category_of = Categories.of,
        rank        = Categories.rank,
    }
end

-- Sections for the "Choose games" list: every installed game, in the same
-- grouping and custom order as the grid, so the arrows move what you see.
function Dashboard:chooserSections()
    local opts = self:arrangeOpts(nil)
    opts.mode = "custom"
    return Games.arrange(scan_games(), opts)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Home screen model and actions
-- ─────────────────────────────────────────────────────────────────────────────

-- The last book (G_reader_settings "lastfile", as FileManager's "Open last
-- document" uses it), or nil when there is none or it no longer exists.
function Dashboard:lastBook()
    local file = G_reader_settings and G_reader_settings:readSetting("lastfile")
    local lfs = get_lfs()
    if not file or not lfs or lfs.attributes(file, "mode") ~= "file" then return nil end
    local b = { file = file }
    local doc_settings
    if self.ui.document and self.ui.document.file == file then
        -- The open book's settings live in memory until it closes.
        doc_settings = self.ui.doc_settings
    else
        local ok, DS = pcall(require, "docsettings")
        if ok then
            local ok2, ds = pcall(function() return DS:open(file) end)
            if ok2 then doc_settings = ds end
        end
    end
    if doc_settings then
        local props = doc_settings:readSetting("doc_props") or {}
        b.title   = props.title
        b.authors = props.authors and props.authors:gsub("\n", ", ") or nil
        b.percent = doc_settings:readSetting("percent_finished")
    end
    if not b.title or b.title == "" then
        b.title = file:match("([^/]+)$"):gsub("%.[^.]+$", "")
    end
    return b
end

function Dashboard:buildModel()
    self._defaults, self._last_played = nil, nil
    local games = scan_games()
    self._last_played = last_played_map(games)
    local shown = function(id) return self:isShown(id) end

    local model = {
        book     = self:lastBook(),
        grouped  = self:isGrouped(),
        sections = Games.arrange(games, self:arrangeOpts(shown)),
    }

    local rg, rts = Games.mostRecent(games, self._last_played)
    if rg then model.resume = { game = rg, ts = rts } end

    local day = Daily.dayNumber(os.date("*t"))
    local dg = Daily.pick(Daily.candidates(games, shown), day,
                          self:getSetting("daily_game", Daily.AUTO), games)
    if dg then
        model.daily = { game = dg, done = Daily.isDone(self:getSetting("daily_done"), day, dg.id) }
    end
    return model
end

function Dashboard:show()
    if self._home then return end
    self._home = HomeScreen:new{ dash = self }
    UIManager:show(self._home, "full")
end

function Dashboard:onHomeClosed(home)
    if self._home == home then self._home = nil end
end

function Dashboard:closeHome()
    if self._home then UIManager:close(self._home) end
end

-- Items of the title bar's menu (left icon).
function Dashboard:homeMenuItems(_home)
    local items = {}
    if self.ui.pluginmanager then
        items[#items + 1] = { text = _("Update plugins"), callback = function()
            self:closeHome()
            UIManager:nextTick(function() self.ui.pluginmanager:fetchManifest() end)
        end }
    end
    if self.ui.document then
        items[#items + 1] = { text = _("Library"), callback = function()
            self:closeHome()
            UIManager:nextTick(function() self.ui:onClose() end)
        end }
    end
    return items
end

function Dashboard:openBook(file)
    self:closeHome()
    if self.ui.document and self.ui.document.file == file then return end
    UIManager:nextTick(function()
        local ok, util = pcall(require, "apps/filemanager/filemanagerutil")
        if ok and util.openFile then
            util.openFile(self.ui, file, nil, true)
        else
            require("apps/reader/readerui"):showReader(file)
        end
    end)
end

-- self.ui[id] is the plugin instance registered under its directory name --
-- the stable id. plugin.name itself is rewritten to reader<id>/filemanager<id>
-- by registerModule, so it is never used to find a game.
function Dashboard:gamePlugin(g)
    local plugin = self.ui[g.id]
    if plugin and type(plugin.showGame) == "function" then return plugin end
    UIManager:show(InfoMessage:new{
        text    = T(_("%1 is not installed or not active."), g.label),
        timeout = 3,
    })
end

function Dashboard:launchGame(g)
    self:closeHome()
    UIManager:nextTick(function()
        local plugin = self:gamePlugin(g)
        if plugin then plugin:showGame() end
    end)
end

-- Today's challenge. Recorded as launched first, so the check mark is there
-- next time even if the game is closed straight away.
--   "plugin" kind (sudoku): its own showDailyChallenge(), which keeps a
--      separate save slot and resumes today's grid by itself;
--   "screen" kind: open the game normally, then ScreenBase:onDailyGame() on
--      the screen PluginBase:showGame() just stored in plugin.screen.
-- Already launched today: just open the game, so the progress made on
-- today's puzzle is not thrown away by generating it again.
function Dashboard:launchDaily(g, done)
    self:closeHome()
    self:saveSetting("daily_done", { day = Daily.dayNumber(os.date("*t")), id = g.id })
    UIManager:nextTick(function()
        local plugin = self:gamePlugin(g)
        if not plugin then return end
        if g.daily == "plugin" and type(plugin.showDailyChallenge) == "function" then
            plugin:showDailyChallenge()
            return
        end
        plugin:showGame()
        if done then return end
        local screen = plugin.screen
        if screen and type(screen.onDailyGame) == "function" then
            screen:onDailyGame()
        else
            -- A game that does not keep its screen in plugin.screen: leave the
            -- player one tap away instead of failing.
            UIManager:show(InfoMessage:new{
                text = _("Open the game menu and choose Daily Challenge."),
                timeout = 4,
            })
        end
    end)
end

function Dashboard:showChooseGames(home)
    UIManager:show(ChooseGames:new{
        dash = self,
        on_close = function()
            if home and self._home == home then home:reload() end
        end,
    }, "full")
end

function Dashboard:onHome()
    if self.ui.document and self:getSetting("home_opens_dashboard", false) then
        self:show()
        return true
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main menu (Tools → Dashboard)
-- ─────────────────────────────────────────────────────────────────────────────

local STARTUP_LABELS = {
    { mode = Startup.LAUNCH,      text = "At KOReader launch only" },
    { mode = Startup.FILEMANAGER, text = "Every time the file browser opens" },
    { mode = Startup.NEVER,       text = "Never" },
}

function Dashboard:addToMainMenu(menu_items)
    local self_ref = self

    local startup_sub = {}
    for _i, s in ipairs(STARTUP_LABELS) do
        local mode = s.mode
        startup_sub[#startup_sub + 1] = {
            text         = _(s.text),
            radio        = true,
            checked_func = function() return self_ref:getStartupMode() == mode end,
            callback     = function() self_ref:saveSetting("startup_mode", mode) end,
        }
    end
    startup_sub[#startup_sub].separator = true
    for _i, d in ipairs({ 0.5, 1.0, 2.0 }) do
        startup_sub[#startup_sub + 1] = {
            text         = T(_("Startup delay: %1 s"), d == 0.5 and "0.5" or tostring(math.floor(d))),
            radio        = true,
            checked_func = function() return self_ref:getSetting("startup_delay", 1.0) == d end,
            enabled_func = function() return self_ref:getStartupMode() ~= Startup.NEVER end,
            callback     = function() self_ref:saveSetting("startup_delay", d) end,
        }
    end

    local function daily_sub()
        local sub = {
            {
                text         = _("Automatic (a different game every day)"),
                radio        = true,
                checked_func = function()
                    return self_ref:getSetting("daily_game", Daily.AUTO) == Daily.AUTO
                end,
                callback     = function() self_ref:saveSetting("daily_game", Daily.AUTO) end,
                separator    = true,
            },
        }
        for _i, g in ipairs(scan_games()) do
            if g.daily then
                local gid = g.id
                sub[#sub + 1] = {
                    text         = g.label,
                    radio        = true,
                    checked_func = function() return self_ref:getSetting("daily_game") == gid end,
                    callback     = function() self_ref:saveSetting("daily_game", gid) end,
                }
            end
        end
        return sub
    end

    menu_items.dashboard = {
        text         = _("Dashboard"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text     = _("Open Dashboard"),
                callback = function() self_ref:show() end,
            },
            {
                text_func = function()
                    for _i, s in ipairs(STARTUP_LABELS) do
                        if s.mode == self_ref:getStartupMode() then
                            return T(_("Show automatically: %1"), _(s.text))
                        end
                    end
                end,
                sub_item_table = startup_sub,
            },
            {
                text     = _("Choose games"),
                callback = function() self_ref:showChooseGames(nil) end,
            },
            {
                text = _("Game order"),
                sub_item_table = {
                    {
                        text         = _("Custom order (Choose games)"),
                        radio        = true,
                        checked_func = function() return self_ref:getSortMode() == "custom" end,
                        callback     = function() self_ref:saveSetting("sort_mode", "custom") end,
                    },
                    {
                        text         = _("Last played first"),
                        radio        = true,
                        checked_func = function() return self_ref:getSortMode() == "recent" end,
                        callback     = function() self_ref:saveSetting("sort_mode", "recent") end,
                        separator    = true,
                    },
                    {
                        text         = _("Group by category"),
                        checked_func = function() return self_ref:isGrouped() end,
                        callback     = function()
                            self_ref:saveSetting("group_by_category", not self_ref:isGrouped())
                        end,
                    },
                },
            },
            {
                text = _("Daily Challenge game"),
                sub_item_table_func = daily_sub,
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Statistics page (the former dashboard list)
-- ─────────────────────────────────────────────────────────────────────────────

local function section_header(title, mandatory)
    return {
        text      = "\xE2\x96\xB6 " .. title:upper(),
        mandatory = mandatory,
        bold      = true,
    }
end

-- `close_all` closes the statistics page and the home screen under it.
function Dashboard:buildStatsItems(books, n_books, games, n_inst, n_played, close_all)
    local self_ref = self
    local items    = {}

    local function close_and(fn)
        return function()
            close_all()
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
            local cb = bfile and function()
                close_all()
                self_ref:openBook(bfile)
            end or nil
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
                callback  = function()
                    close_all()
                    self_ref:launchGame({ id = g.name, label = g.fullname })
                end,
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

    return items
end

function Dashboard:showStats(_home)
    local books, n_books          = reading_data()
    local games, n_inst, n_played = game_data()

    local menu_widget
    local items = self:buildStatsItems(books, n_books, games, n_inst, n_played, function()
        if menu_widget then UIManager:close(menu_widget) end
        self:closeHome()
    end)

    menu_widget = Menu:new{
        title         = _("Statistics"),
        item_table    = items,
        is_borderless = true,
        is_popout     = false,
        width         = Screen:getWidth(),
        height        = Screen:getHeight(),
        onMenuHold    = function() end,
    }

    function menu_widget:onMenuChoice(item)
        if item.callback then item.callback() end
    end

    UIManager:show(menu_widget)
end

return Dashboard
