-- games_screen.lua -- "Choose games": which games the dashboard grid shows,
-- and in what order.
--
-- A full-screen paged list of every installed game, grouped by category like
-- the grid (one plain list when the grid is not grouped) -- 80
-- checkboxes in KOReader's touch menu would be unusable. One row per game:
-- tap the row to show or hide the game; with the custom order active, the
-- arrow buttons move a shown game up or down among the shown games of its
-- group. Every change is saved at once; closing returns to the dashboard,
-- which then re-reads everything.

local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local Size            = require("ui/size")
local TextWidget      = require("ui/widget/textwidget")
local TitleBar        = require("ui/widget/titlebar")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local T               = require("ffi/util").template
local _               = require("i18n")

local Screen = Device.screen

local Layout, Widgets -- set by main.lua (setModules)

local SZ_ROW    = 20
local SZ_HEADER = 17

local ChooseGames = InputContainer:extend{
    dash     = nil,   -- Dashboard plugin instance
    on_close = nil,   -- called once closed
    page     = 1,
    covers_fullscreen = true,
}

function ChooseGames.setModules(layout, widgets)
    Layout, Widgets = layout, widgets
end

function ChooseGames:init()
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

function ChooseGames:rowHeight()
    return Screen:scaleBySize(42)
end

function ChooseGames:buildRow(w, g, sec_games)
    local dash   = self.dash
    local shown  = dash:isShown(g.id)
    local row_h  = self:rowHeight()
    local can_move = shown and dash:getSortMode() == "custom"
    local arrow_w = math.floor(row_h * 1.25)
    local arrows_w = can_move and (2 * arrow_w + 2 * Size.span.horizontal_small) or 0
    local box = math.floor(row_h * 0.55)
    local check_w = box + 2 * Size.padding.large
    local label_w = w - arrows_w - check_w

    -- A drawn check box rather than a glyph: same size whether ticked or not,
    -- and black on white either way (grey text for hidden games was too faint
    -- on e-ink).
    local f = Font:getFace("cfont", SZ_ROW)
    local inner = box - 2 * Size.border.thick
    local label = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = check_w, h = row_h },
            FrameContainer:new{
                bordersize = Size.border.thick,
                padding    = 0,
                CenterContainer:new{
                    dimen = Geom:new{ w = inner, h = inner },
                    TextWidget:new{ text = shown and "\u{2713}" or "",
                                    face = Font:getFace("cfont", SZ_ROW - 4), bold = true },
                },
            },
        },
        LeftContainer:new{
            dimen = Geom:new{ w = label_w, h = row_h },
            TextWidget:new{ text = g.label, face = f, bold = shown, max_width = label_w },
        },
    }
    local hg = HorizontalGroup:new{
        align = "center",
        Widgets.Tappable:new{ callback = function() self:toggle(g.id) end, label },
    }
    if can_move then
        -- No-op arrows (first/last shown game of the group) are disabled.
        local peers = {}
        for _i, o in ipairs(sec_games) do
            if dash:isShown(o.id) then peers[#peers + 1] = o.id end
        end
        local is_first, is_last = peers[1] == g.id, peers[#peers] == g.id
        local inner_h = row_h - 2 * (Size.padding.button + Size.border.button) - Size.padding.small
        local function arrow(text, delta, enabled)
            return Button:new{
                text = text, width = arrow_w, height = inner_h, enabled = enabled,
                bordersize = Size.border.button, radius = Size.radius.button,
                text_font_size = 16,
                callback = function() self:move(g.id, delta, sec_games) end,
            }
        end
        hg[#hg + 1] = HorizontalSpan:new{ width = Size.span.horizontal_small }
        hg[#hg + 1] = arrow("\u{25B2}", -1, not is_first)
        hg[#hg + 1] = HorizontalSpan:new{ width = Size.span.horizontal_small }
        hg[#hg + 1] = arrow("\u{25BC}", 1, not is_last)
    end
    return hg
end

function ChooseGames:header(w, label)
    return Widgets.header(w, label, SZ_HEADER)
end

function ChooseGames:buildLayout()
    local W, H = self.dimen.w, self.dimen.h
    local gutter = Size.padding.fullscreen
    local content_w = W - 2 * gutter
    local vgap = Size.padding.large

    local sections = self.dash:chooserSections()
    self.sections = sections

    local footer = Widgets.footer(content_w, {
        { text = "\u{25C0}", enabled_func = function() return self.page > 1 end,
          callback = function() self:onPrevPage() end },
        { text = _("Done"), callback = function() self:onClose() end },
        { text = "\u{25B6}", enabled_func = function() return self.page < (self.n_pages or 1) end,
          callback = function() self:onNextPage() end },
    })
    local n_shown, n_all = 0, 0
    for _i, s in ipairs(sections) do
        for _i, g in ipairs(s.games) do
            n_all = n_all + 1
            if self.dash:isShown(g.id) then n_shown = n_shown + 1 end
        end
    end
    local function titleBar(sub)
        return TitleBar:new{
            width = W, fullscreen = true,
            title = _("Choose games"),
            subtitle = sub,
            with_bottom_line = true,
            close_callback = function() self:onClose() end,
        }
    end
    local tb_h = titleBar(" "):getSize().h
    local hint = TextWidget:new{
        text = self.dash:getSortMode() == "custom"
            and _("Tap a game to show or hide it. Arrows change its place.")
            or _("Tap a game to show or hide it."),
        face = Font:getFace("cfont", 16), max_width = content_w,
    }
    local body_h = H - tb_h - footer:getSize().h - hint:getSize().h - 3 * vgap

    local grouped = sections[1] and sections[1].category ~= nil
    local header_h = grouped and self:header(content_w, "Ay"):getSize().h or 0
    local row_h = self:rowHeight() + Size.line.thin
    local secs = {}
    for i, s in ipairs(sections) do secs[i] = { count = #s.games } end
    local pages = Layout.paginate(secs, 1, body_h, body_h, header_h, row_h)
    self.n_pages = #pages
    self.page = Layout.clampPage(self.page, self.n_pages)

    local list = VerticalGroup:new{ align = "left" }
    for _i, b in ipairs(pages[self.page]) do
        local sec = sections[b.section]
        if sec.category then
            list[#list + 1] = self:header(content_w, self.dash:categoryLabel(sec.category))
        end
        for i = b.first, b.last do
            list[#list + 1] = self:buildRow(content_w, sec.games[i], sec.games)
            list[#list + 1] = LineWidget:new{
                dimen = Geom:new{ w = content_w, h = Size.line.thin },
                background = Blitbuffer.COLOR_LIGHT_GRAY,
            }
        end
    end

    local sub = T(_("%1 of %2 shown"), n_shown, n_all)
    if self.n_pages > 1 then
        sub = sub .. " · " .. T(_("Page %1 of %2"), self.page, self.n_pages)
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

function ChooseGames:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if self.layout then
        local lw = self.layout:getSize().w
        self.layout:paintTo(bb, x + math.floor((self.dimen.w - lw) / 2), y)
    end
end

function ChooseGames:refresh()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function ChooseGames:toggle(id)
    self.dash:toggleShown(id)
    self:refresh()
end

function ChooseGames:move(id, delta)
    self.dash:moveGame(id, delta)
    self:refresh()
end

function ChooseGames:onNextPage()
    if self.page < (self.n_pages or 1) then
        self.page = self.page + 1
        self:refresh()
    end
    return true
end

function ChooseGames:onPrevPage()
    if self.page > 1 then
        self.page = self.page - 1
        self:refresh()
    end
    return true
end

function ChooseGames:onSwipe(_arg, ges)
    if ges.direction == "west" then return self:onNextPage() end
    if ges.direction == "east" then return self:onPrevPage() end
end

function ChooseGames:onClose()
    UIManager:close(self, "ui")
    return true
end

function ChooseGames:onCloseWidget()
    if self.on_close then
        local cb = self.on_close
        self.on_close = nil
        cb()
    end
end

function ChooseGames:onScreenResize(dimen)
    self.dimen = Geom:new{ x = 0, y = 0, w = dimen and dimen.w or Screen:getWidth(),
                           h = dimen and dimen.h or Screen:getHeight() }
    self:refresh()
end

return ChooseGames
