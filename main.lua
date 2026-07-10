local _dir         = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local _plugins_dir = _dir:match("^(.*)/[^/]+/$") or (_dir .. "..")

-- Add common/ (game-common copy) and ../game-common/ to the path.
package.path = _dir .. "common/?.lua;" .. package.path

local DataStorage     = require("datastorage")
local LuaSettings     = require("luasettings")
local Device          = require("device")
local Menu            = require("ui/widget/menu")
local Screen          = Device.screen
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T               = require("ffi/util").template
local _               = require("i18n")
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

local function game_data()
    local lfs = get_lfs()
    if not lfs then return {}, 0, 0 end
    local sdir = DataStorage:getSettingsDir()
    local games, n_inst, n_played = {}, 0, 0
    local ok, iter, dobj = pcall(lfs.dir, _plugins_dir)
    if not ok then return {}, 0, 0 end
    for entry in iter, dobj do
        if entry:match("%.koplugin$") then
            local f = io.open(_plugins_dir .. "/" .. entry .. "/_meta.lua", "r")
            if f then
                local src      = f:read("*a"); f:close()
                local name     = src:match('name%s*=%s*"([^"]+)"')
                local fullname = src:match('fullname%s*=[^"]*"([^"]*)"')
                if name and not NON_GAME_IDS[name] then
                    n_inst = n_inst + 1
                    local mtime = lfs.attributes(sdir .. "/" .. name .. ".lua", "modification")
                    if mtime then
                        n_played = n_played + 1
                        games[#games + 1] = { name = name, fullname = fullname or name, ts = mtime }
                    end
                end
            end
        end
    end
    table.sort(games, function(a, b) return a.ts > b.ts end)
    return games, n_inst, n_played
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
