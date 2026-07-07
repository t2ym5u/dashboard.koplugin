local _dir         = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local _plugins_dir = _dir:match("^(.*)/[^/]+/$") or (_dir .. "..")

local ButtonDialog    = require("ui/widget/buttondialog")
local DataStorage     = require("datastorage")
local LuaSettings     = require("luasettings")
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _               = require("gettext")

-- Plugin IDs qui ne sont pas des jeux (exclus des stats de jeux)
local NON_GAME_IDS = {
    startmenu     = true,
    pluginmanager = true,
    dashboard     = true,
    _skeleton     = true,
    opdsdir       = true,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Fonctions utilitaires
-- ─────────────────────────────────────────────────────────────────────────────

local function get_lfs()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then ok, lfs = pcall(require, "lfs") end
    return ok and lfs or nil
end

local function reltime(ts)
    if not ts then return "?" end
    local d = os.time() - ts
    if d < 120        then return "à l'instant"
    elseif d < 3600   then return math.floor(d / 60) .. " min"
    elseif d < 86400  then return math.floor(d / 3600) .. "h"
    elseif d < 604800 then return math.floor(d / 86400) .. "j"
    else                   return os.date("%d/%m/%Y", ts)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Collecte des données
-- ─────────────────────────────────────────────────────────────────────────────

-- Retourne { books = [{title, authors, percent, last_read},...], n_total }
-- Les 3 livres les plus récents depuis ReadHistory + leur progression.
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

-- Retourne { games = [{fullname, ts},...], n_installed, n_played }
-- Scanne les plugins installés et trie par date de dernier fichier de sauvegarde.
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
                        games[#games + 1] = { fullname = fullname or name, ts = mtime }
                    end
                end
            end
        end
    end
    table.sort(games, function(a, b) return a.ts > b.ts end)
    return games, n_inst, n_played
end

-- ─────────────────────────────────────────────────────────────────────────────
-- SECTIONS — modifiez librement : ajoutez, supprimez, réordonnez.
--
-- Chaque section : { titre = string, render = function(data) → string }
-- `data` contient : books, n_books, games, n_inst, n_played
-- ─────────────────────────────────────────────────────────────────────────────

local SECTIONS = {

    -- ── Livre en cours ───────────────────────────────────────────────────────
    {
        titre  = "Lecture",
        render = function(d)
            if #d.books == 0 then return "Aucun historique de lecture." end
            local b = d.books[1]
            local lines = {}
            -- Titre + progression
            if b.percent then
                lines[#lines + 1] = b.title
                    .. "  \u{2014}  "
                    .. math.floor(b.percent * 100) .. "%"
            else
                lines[#lines + 1] = b.title
            end
            -- Auteur
            if b.authors and b.authors ~= "" then
                lines[#lines + 1] = b.authors
            end
            -- Date de dernière lecture
            if b.last_read then
                lines[#lines + 1] = "Repris " .. reltime(b.last_read)
            end
            -- Livres récents supplémentaires (2 et 3)
            for i = 2, #d.books do
                local bi = d.books[i]
                local pi = bi.percent
                    and ("  " .. math.floor(bi.percent * 100) .. "%") or ""
                lines[#lines + 1] = ""
                lines[#lines + 1] = bi.title .. pi
                if bi.last_read then
                    lines[#lines + 1] = "  " .. reltime(bi.last_read)
                end
            end
            return table.concat(lines, "\n")
        end,
    },

    -- ── Derniers jeux ────────────────────────────────────────────────────────
    {
        titre  = "Derniers jeux",
        render = function(d)
            if #d.games == 0 then return "Aucun jeu joué pour l'instant." end
            local lines = {}
            for i = 1, math.min(5, #d.games) do
                local g = d.games[i]
                lines[#lines + 1] = g.fullname .. "  \u{2014}  " .. reltime(g.ts)
            end
            return table.concat(lines, "\n")
        end,
    },

    -- ── Statistiques ─────────────────────────────────────────────────────────
    {
        titre  = "Statistiques",
        render = function(d)
            local lines = {
                "Livres dans l'historique : " .. d.n_books,
                "Jeux installés : "            .. d.n_inst,
                "Jeux joués au moins une fois : " .. d.n_played,
            }
            return table.concat(lines, "\n")
        end,
    },

}

-- ─────────────────────────────────────────────────────────────────────────────
-- Construction du texte affiché
-- ─────────────────────────────────────────────────────────────────────────────

local function build_content(data)
    local parts = {}
    for i, sec in ipairs(SECTIONS) do
        if i > 1 then parts[#parts + 1] = "" end
        parts[#parts + 1] = "\u{25B6} " .. sec.titre:upper()
        local body = sec.render(data)
        if body and body ~= "" then
            parts[#parts + 1] = body
        end
    end
    return table.concat(parts, "\n")
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Plugin Dashboard
-- ─────────────────────────────────────────────────────────────────────────────

local Dashboard = WidgetContainer:extend{
    name        = "dashboard",
    is_doc_only = false,
}

-- ── Persistance des préférences ──────────────────────────────────────────────

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

-- ── Cycle de vie ─────────────────────────────────────────────────────────────

function Dashboard:init()
    self:ensureSettings()
    self.ui.menu:registerToMainMenu(self)

    -- Affichage automatique au démarrage (FileManager seulement, pas en lecture)
    if not self.ui.document and self:getSetting("show_on_startup", false) then
        local delay = self:getSetting("startup_delay", 1.0)
        UIManager:scheduleIn(delay, function()
            self:show()
        end)
    end
end

-- ── Menu principal ────────────────────────────────────────────────────────────

function Dashboard:addToMainMenu(menu_items)
    menu_items.dashboard = {
        text         = _("Dashboard"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text     = _("Ouvrir le Dashboard"),
                callback = function() self:show() end,
            },
            -- ── Démarrage automatique ──────────────────────────────────────
            {
                text         = _("Afficher au démarrage"),
                checked_func = function()
                    return self:getSetting("show_on_startup", false)
                end,
                callback     = function()
                    self:saveSetting("show_on_startup",
                        not self:getSetting("show_on_startup", false))
                end,
            },
            {
                text         = _("Délai au démarrage : 0.5 s"),
                checked_func = function()
                    return self:getSetting("startup_delay", 1.0) == 0.5
                end,
                enabled_func = function()
                    return self:getSetting("show_on_startup", false)
                end,
                callback     = function() self:saveSetting("startup_delay", 0.5) end,
            },
            {
                text         = _("Délai au démarrage : 1 s"),
                checked_func = function()
                    return self:getSetting("startup_delay", 1.0) == 1.0
                end,
                enabled_func = function()
                    return self:getSetting("show_on_startup", false)
                end,
                callback     = function() self:saveSetting("startup_delay", 1.0) end,
            },
            {
                text         = _("Délai au démarrage : 2 s"),
                checked_func = function()
                    return self:getSetting("startup_delay", 1.0) == 2.0
                end,
                enabled_func = function()
                    return self:getSetting("show_on_startup", false)
                end,
                callback     = function() self:saveSetting("startup_delay", 2.0) end,
            },
            -- ── Bouton Home ────────────────────────────────────────────────
            {
                text         = _("Bouton Home → Dashboard"),
                checked_func = function()
                    return self:getSetting("home_opens_dashboard", false)
                end,
                callback     = function()
                    self:saveSetting("home_opens_dashboard",
                        not self:getSetting("home_opens_dashboard", false))
                end,
            },
        },
    }
end

-- ── Interception du bouton Home (lecteur) ────────────────────────────────────
-- KOReader dispatch onHome à tous les composants enregistrés.
-- Retourner true consomme l'événement et empêche le retour à la bibliothèque.

function Dashboard:onHome()
    if self.ui.document and self:getSetting("home_opens_dashboard", false) then
        self:show()
        return true
    end
end

function Dashboard:show()
    local books, n_books         = reading_data()
    local games, n_inst, n_played = game_data()
    local data = {
        books    = books,
        n_books  = n_books,
        games    = games,
        n_inst   = n_inst,
        n_played = n_played,
    }

    local content  = build_content(data)
    local self_ref = self
    local dlg

    -- Rangée de boutons : MAJ plugins (si disponible) + Bibliothèque (si lecteur) + Fermer
    local btn_row = {}
    if self.ui.pluginmanager then
        btn_row[#btn_row + 1] = {
            text     = _("MAJ plugins"),
            callback = function()
                UIManager:close(dlg)
                UIManager:scheduleIn(0.1, function()
                    self_ref.ui.pluginmanager:fetchManifest()
                end)
            end,
        }
    end
    -- En contexte lecteur : bouton pour retourner à la bibliothèque
    if self.ui.document then
        btn_row[#btn_row + 1] = {
            text     = _("Bibliothèque"),
            callback = function()
                UIManager:close(dlg)
                self_ref.ui:onClose()
            end,
        }
    end
    btn_row[#btn_row + 1] = {
        text     = _("Fermer"),
        callback = function() UIManager:close(dlg) end,
    }

    dlg = ButtonDialog:new{
        title   = content,
        buttons = { btn_row },
    }
    UIManager:show(dlg)
end

return Dashboard
