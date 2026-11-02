-- all_games_screen.lua -- "All games": every installed game, one category at
-- a time.
--
--   title bar  (All games | category · page x/y | close)
--   categories: one big tile per category, with its game count
--   a category: its games as tiles, alphabetical, paged
--   footer: < | Categories | >
--
-- The dashboard grid only holds the games the player picked; this is where
-- the rest of a hundred-game install is browsed. Tap a game to play it, hold
-- it to add it to the dashboard grid or take it off (a ✓ marks the ones on
-- it). Two short levels rather than one long list: a page flip on e-ink
-- costs a full repaint, a category tap gets most games within one or two.

local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local Device          = require("device")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local TitleBar        = require("ui/widget/titlebar")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local T               = require("ffi/util").template
local _               = require("i18n")

local Screen = Device.screen

local Layout, Widgets -- set by main.lua (setModules)

local SZ_TILE = 20
local SZ_HINT = 16

local AllGames = InputContainer:extend{
    dash     = nil,   -- Dashboard plugin instance
    on_close = nil,   -- called once closed
    category = nil,   -- nil: the category tiles; else the category shown
    page     = 1,
    covers_fullscreen = true,
}

function AllGames.setModules(layout, widgets)
    Layout, Widgets = layout, widgets
end

function AllGames:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    if Device:hasKeys() then
        self.key_events = {
            Close    = { { Device.input.group.Back } },
            NextPage = { { Device.input.group.PgFwd } },
            PrevPage = { { Device.input.group.PgBack } },
        }
    end
    self.ges_events = {
        Swipe = { GestureRange:new{ ges = "swipe", range = function() return self.dimen end } },
    }
    self:buildLayout()
end

-- The section of the category shown, or nil (back to the category tiles when
-- it has gone, e.g. its last game was uninstalled).
function AllGames:currentSection()
    for _i, s in ipairs(self.sections) do
        if s.category == self.category then return s end
    end
end

function AllGames:metrics(w)
    local gap    = Size.span.horizontal_default
    -- Category names are long ("Casse-têtes classiques"): two columns for them.
    local cols   = self.category and Layout.columns(w + gap, Screen:scaleBySize(150) + gap, 2, 3) or 2
    local tile_w = math.floor((w - (cols - 1) * gap) / cols)
    local m = { gap = gap, cols = cols, tile_w = tile_w, label_h = Screen:scaleBySize(42) }
    local tile_h
    if self.category then
        tile_h = m.label_h + 2 * (Size.padding.button + Size.border.thick)
    else
        -- Category tiles are cards (a name over a count): as tall as one.
        local probe = self:categoryTile({ category = "other", games = {} }, m)
        tile_h = probe:getSize().h
        probe:free()
    end
    m.tile_h = tile_h
    m.row_h = tile_h + gap
    return m
end

function AllGames:categoryTile(sec, m)
    local cat = sec.category
    return Widgets.card(m.tile_w, m.tile_h, {
        { text = self.dash:categoryLabel(cat), size = SZ_TILE, bold = true },
        { text = T(_("%1 games"), #sec.games), size = SZ_HINT },
    }, function() self:openCategory(cat) end)
end

function AllGames:gameTile(g, m)
    local shown = self.dash:isShown(g.id)
    return Button:new{
        text           = shown and ("\u{2713} " .. g.label) or g.label,
        width          = m.tile_w,
        height         = m.label_h,
        bordersize     = Size.border.thick,
        radius         = Size.radius.button,
        padding_h      = Size.padding.default,
        text_font_size = SZ_TILE,
        callback       = function() self:launch(g) end,
        hold_callback  = function() self:toggleShown(g.id) end,
    }
end

-- Tiles `first`..`last`, each built by `build(i)`, `m.cols` per row.
function AllGames:grid(m, first, last, build)
    local vg = VerticalGroup:new{ align = "left" }
    local row
    for i = first, last do
        if (i - first) % m.cols == 0 then
            if row then
                vg[#vg + 1] = row
                vg[#vg + 1] = VerticalSpan:new{ width = m.gap }
            end
            row = HorizontalGroup:new{ align = "top" }
        else
            row[#row + 1] = HorizontalSpan:new{ width = m.gap }
        end
        row[#row + 1] = build(i)
    end
    if row then vg[#vg + 1] = row end
    return vg
end

function AllGames:buildLayout()
    local W, H = self.dimen.w, self.dimen.h
    local gutter = Size.padding.fullscreen
    local vgap = Size.padding.large
    local content_w = W - 2 * gutter

    self.sections = self.dash:allGamesSections()
    local sec = self.category and self:currentSection()
    if not sec then self.category = nil end

    local footer = Widgets.footer(content_w, {
        { text = "\u{25C0}", weight = 0.6, enabled_func = function() return self.page > 1 end,
          callback = function() self:onPrevPage() end },
        { text = self.category and _("Categories") or _("Close"),
          callback = function()
              if self.category then self:openCategory(nil) else self:onClose() end
          end },
        { text = "\u{25B6}", weight = 0.6,
          enabled_func = function() return self.page < (self.n_pages or 1) end,
          callback = function() self:onNextPage() end },
    })
    local function titleBar(sub)
        return TitleBar:new{
            width = W, fullscreen = true,
            title = _("All games"),
            subtitle = sub,
            with_bottom_line = true,
            close_callback = function() UIManager:close(self, "ui") end,
        }
    end
    local tb_h = titleBar(" "):getSize().h
    local hint = TextBoxWidget:new{
        text = self.category and _("Tap a game to play it, hold it to add it to the dashboard or remove it.")
            or _("Choose a category."),
        face = Font:getFace("cfont", SZ_HINT), width = content_w,
    }
    local body_h = H - tb_h - footer:getSize().h - hint:getSize().h - 3 * vgap

    local m = self:metrics(content_w)
    local n = sec and #sec.games or #self.sections
    local pages = Layout.paginate({ { count = n } }, m.cols, body_h, body_h, 0, m.row_h)
    self.n_pages = #pages
    self.page = Layout.clampPage(self.page, self.n_pages)

    local list
    local block = pages[self.page][1]
    if n == 0 then
        list = TextWidget:new{ text = _("No games installed."), face = Font:getFace("cfont", SZ_TILE) }
    elseif sec then
        list = self:grid(m, block.first, block.last,
            function(i) return self:gameTile(sec.games[i], m) end)
    else
        list = self:grid(m, block.first, block.last,
            function(i) return self:categoryTile(self.sections[i], m) end)
    end

    local sub = sec and self.dash:categoryLabel(sec.category) or nil
    if self.n_pages > 1 then
        local p = T(_("Page %1 of %2"), self.page, self.n_pages)
        sub = sub and (sub .. " · " .. p) or p
    end
    self.layout = VerticalGroup:new{
        align = "center",
        titleBar(sub),
        VerticalSpan:new{ width = vgap },
        LeftContainer:new{ dimen = Geom:new{ w = content_w, h = hint:getSize().h }, hint },
        VerticalSpan:new{ width = vgap },
        LeftContainer:new{ dimen = Geom:new{ w = content_w, h = list:getSize().h }, list },
        VerticalSpan:new{ width = math.max(0, body_h - list:getSize().h) + vgap },
        footer,
    }
    self[1] = self.layout
end

function AllGames:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if self.layout then
        local lw = self.layout:getSize().w
        self.layout:paintTo(bb, x + math.floor((self.dimen.w - lw) / 2), y)
    end
end

function AllGames:refresh()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function AllGames:openCategory(cat)
    self.category = cat
    self.page = 1
    self:refresh()
end

function AllGames:toggleShown(id)
    self.dash:toggleShown(id)
    self:refresh()
end

-- Closes this screen (and the dashboard under it), then plays.
function AllGames:launch(g)
    self.on_close = nil
    UIManager:close(self)
    self.dash:launchGame(g)
end

function AllGames:onNextPage()
    if self.page < (self.n_pages or 1) then
        self.page = self.page + 1
        self:refresh()
    end
    return true
end

function AllGames:onPrevPage()
    if self.page > 1 then
        self.page = self.page - 1
        self:refresh()
    end
    return true
end

function AllGames:onSwipe(_arg, ges)
    if ges.direction == "west" then return self:onNextPage() end
    if ges.direction == "east" then return self:onPrevPage() end
end

-- Back (and the footer button) goes up a level before it closes; the title
-- bar's close button closes at once.
function AllGames:onClose()
    if self.category then
        self:openCategory(nil)
        return true
    end
    UIManager:close(self, "ui")
    return true
end

function AllGames:onCloseWidget()
    if self.on_close then
        local cb = self.on_close
        self.on_close = nil
        cb()
    end
end

function AllGames:onScreenResize(dimen)
    self.dimen = Geom:new{ x = 0, y = 0, w = dimen and dimen.w or Screen:getWidth(),
                           h = dimen and dimen.h or Screen:getHeight() }
    self:refresh()
end

return AllGames
