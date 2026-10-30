-- home_screen.lua -- the full-screen dashboard.
--
--   title bar  (menu | Dashboard [page x/y] | close)
--   Continue reading: <book>            -- hidden when there is no last book
--   Resume: <game>   |  Daily Challenge -- each hidden when it has nothing
--   game grid, by category, paged
--   footer: < | Statistics | Choose games | >
--
-- Landscape moves the cards into a left column and gives the grid the rest.
-- E-ink first: no animation, black on white, thick borders, every target at
-- least a finger wide; a page flip rebuilds the widgets and repaints once.
--
-- The screen owns no data: `dash` (the Dashboard plugin instance) builds the
-- model on every rebuild (dash:buildModel()) and performs every action.

local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local ButtonDialog    = require("ui/widget/buttondialog")
local Device          = require("device")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local ProgressWidget  = require("ui/widget/progresswidget")
local Size            = require("ui/size")
local TitleBar        = require("ui/widget/titlebar")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local T               = require("ffi/util").template
local _               = require("i18n")

local Screen = Device.screen

-- Loaded through main.lua's lrequire-style loader so these resolve to this
-- plugin's copies; passed in by main.lua.
local Layout, Format, Widgets
local makeCard

-- ---------------------------------------------------------------------------
-- HomeScreen
-- ---------------------------------------------------------------------------

local HomeScreen = InputContainer:extend{
    dash  = nil,  -- Dashboard plugin instance
    page  = 1,
    covers_fullscreen = true,
}

-- Font sizes (Font:getFace scales them by the screen DPI).
local SZ_CAPTION = 16
local SZ_TITLE   = 23
local SZ_DETAIL  = 17
local SZ_TILE    = 20
local SZ_HEADER  = 17

function HomeScreen.setModules(layout, format, widgets)
    Layout, Format, Widgets = layout, format, widgets
    makeCard = widgets.card
end

function HomeScreen:init()
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
    self:rebuild()
end

function HomeScreen:rebuild()
    self.model = self.dash:buildModel()
    self:buildLayout()
end

function HomeScreen:isLandscape()
    return self.dimen.w > self.dimen.h
end

-- ---------------------------------------------------------------------------
-- Cards
-- ---------------------------------------------------------------------------

function HomeScreen:bookCard(w, h)
    local b = self.model.book
    local detail = {}
    if b.authors and b.authors ~= "" then detail[#detail + 1] = b.authors end
    if b.percent then detail[#detail + 1] = math.floor(b.percent * 100 + 0.5) .. "\u{202F}%" end
    local lines = {
        { text = _("Continue reading"), size = SZ_CAPTION },
        { text = b.title, size = SZ_TITLE, bold = true, max_lines = 2 },
    }
    if #detail > 0 then
        lines[#lines + 1] = { text = table.concat(detail, " · "), size = SZ_DETAIL }
    end
    if b.percent then
        lines[#lines + 1] = { widget = function(iw)
            return ProgressWidget:new{
                width = iw, height = Screen:scaleBySize(7),
                percentage = b.percent, margin_h = 0, margin_v = 0,
                radius = 0, bordersize = Size.border.thin,
                fillcolor = Blitbuffer.COLOR_BLACK,
            }
        end }
    end
    return makeCard(w, h, lines, function() self.dash:openBook(b.file) end)
end

function HomeScreen:resumeCard(w, h)
    local r = self.model.resume
    return makeCard(w, h, {
        { text = _("Resume"), size = SZ_CAPTION },
        { text = r.game.label, size = SZ_TITLE, bold = true, max_lines = 2 },
        { text = T(_("Last played: %1"), Format.reltime(r.ts)), size = SZ_DETAIL },
    }, function() self.dash:launchGame(r.game) end)
end

function HomeScreen:dailyCard(w, h)
    local d = self.model.daily
    return makeCard(w, h, {
        { text = _("Daily Challenge"), size = SZ_CAPTION },
        { text = d.game.label, size = SZ_TITLE, bold = true, max_lines = 2 },
        { text = d.done and ("\u{2713} " .. _("Started today")) or _("New puzzle today"),
          size = SZ_DETAIL, bold = d.done },
    }, function() self.dash:launchDaily(d.game, d.done) end)
end

-- Cards for the top of page 1 (portrait) or the side column (landscape),
-- in display order, built at width `w`. Each card is as tall as its text;
-- the two half-width portrait cards share the taller one's height.
function HomeScreen:buildCards(w, landscape)
    local gap = Size.span.horizontal_default
    local cards = {}
    local m = self.model
    if m.book then
        cards[#cards + 1] = self:bookCard(w)
    end
    if landscape then
        if m.resume then cards[#cards + 1] = self:resumeCard(w) end
        if m.daily then cards[#cards + 1] = self:dailyCard(w) end
    else
        if m.resume and m.daily then
            local half = math.floor((w - gap) / 2)
            local h = math.max(self:resumeCard(half):getSize().h, self:dailyCard(half):getSize().h)
            cards[#cards + 1] = HorizontalGroup:new{
                align = "top",
                self:resumeCard(half, h),
                HorizontalSpan:new{ width = w - 2 * half },
                self:dailyCard(half, h),
            }
        elseif m.resume then
            cards[#cards + 1] = self:resumeCard(w)
        elseif m.daily then
            cards[#cards + 1] = self:dailyCard(w)
        end
    end
    return cards
end

-- ---------------------------------------------------------------------------
-- Grid
-- ---------------------------------------------------------------------------

function HomeScreen:gridMetrics(w)
    local gap    = Size.span.horizontal_default
    local cols   = Layout.columns(w + gap, Screen:scaleBySize(150) + gap, 2, 3)
    local tile_w = math.floor((w - (cols - 1) * gap) / cols)
    local label_h = Screen:scaleBySize(42)
    local tile_h = label_h + 2 * (Size.padding.button + Size.border.thick)
    local header_h = Widgets.header(w, "Ay", SZ_HEADER):getSize().h
    return {
        gap = gap, cols = cols, tile_w = tile_w, label_h = label_h,
        row_h = tile_h + gap, header_h = self.model.grouped and header_h or 0,
    }
end

function HomeScreen:sectionHeader(w, label)
    return Widgets.header(w, label, SZ_HEADER)
end

function HomeScreen:tile(g, gm)
    return Button:new{
        text           = g.label,
        width          = gm.tile_w,
        height         = gm.label_h,
        bordersize     = Size.border.thick,
        radius         = Size.radius.button,
        padding_h      = Size.padding.default,
        text_font_size = SZ_TILE,
        callback       = function() self.dash:launchGame(g) end,
    }
end

-- The grid blocks of one page.
function HomeScreen:buildGridPage(w, gm, blocks)
    local vg = VerticalGroup:new{ align = "left" }
    local sections = self.model.sections
    for _i, b in ipairs(blocks) do
        local sec = sections[b.section]
        if sec.category then
            vg[#vg + 1] = self:sectionHeader(w, self.dash:categoryLabel(sec.category))
        end
        local row
        for i = b.first, b.last do
            local col = (i - b.first) % gm.cols
            if col == 0 then
                if row then
                    vg[#vg + 1] = row
                    vg[#vg + 1] = VerticalSpan:new{ width = gm.gap }
                end
                row = HorizontalGroup:new{ align = "top" }
            else
                row[#row + 1] = HorizontalSpan:new{ width = gm.gap }
            end
            row[#row + 1] = self:tile(sec.games[i], gm)
        end
        if row then
            vg[#vg + 1] = row
            vg[#vg + 1] = VerticalSpan:new{ width = gm.gap }
        end
    end
    return vg
end

-- Shown in place of the grid when the player shows no game at all.
function HomeScreen:emptyGrid(w)
    return makeCard(w, Screen:scaleBySize(90), {
        { text = _("No games on the dashboard yet."), size = SZ_DETAIL, bold = true },
        { text = _("Tap here to choose which games to show."), size = SZ_DETAIL, max_lines = 2 },
    }, function() self.dash:showChooseGames(self) end)
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function HomeScreen:menuButtons()
    local items = self.dash:homeMenuItems(self)
    if #items == 0 then return nil end
    return function()
        local dlg
        local buttons = {}
        for _i, it in ipairs(items) do
            local cb = it.callback
            buttons[#buttons + 1] = {{ text = it.text, callback = function()
                UIManager:close(dlg)
                cb()
            end }}
        end
        dlg = ButtonDialog:new{ title = _("Dashboard"), buttons = buttons }
        UIManager:show(dlg)
    end
end

function HomeScreen:buildLayout()
    local W, H = self.dimen.w, self.dimen.h
    local landscape = self:isLandscape()
    local gutter = Size.padding.fullscreen
    local vgap = Size.padding.large
    local content_w = W - 2 * gutter

    -- Footer first: everything else is sized from the room it leaves.
    local footer = Widgets.footer(content_w, {
        { text = "\u{25C0}", weight = 0.6, enabled_func = function() return self.page > 1 end,
          callback = function() self:onPrevPage() end },
        { text = _("Statistics"), callback = function() self.dash:showStats(self) end },
        { text = _("Choose games"), callback = function() self.dash:showChooseGames(self) end },
        { text = "\u{25B6}", weight = 0.6,
          enabled_func = function() return self.page < (self.n_pages or 1) end,
          callback = function() self:onNextPage() end },
    })
    local footer_h = footer:getSize().h

    -- The title bar's height does not depend on the page count text, so a
    -- provisional one is enough to measure.
    local open_menu = self:menuButtons()
    local function titleBar(subtitle)
        return TitleBar:new{
            width            = W,
            fullscreen       = true,
            title            = _("Dashboard"),
            subtitle         = subtitle,
            with_bottom_line = true,
            left_icon        = open_menu and "appbar.menu" or nil,
            left_icon_tap_callback = open_menu,
            close_callback   = function() self:onClose() end,
        }
    end
    local tb_h = titleBar(" "):getSize().h
    local body_h = H - tb_h - footer_h - 2 * vgap

    -- Cards and grid geometry.
    local cards, grid_w, first_avail, avail
    if landscape then
        local side_w = math.floor(content_w * 0.36)
        grid_w = content_w - side_w - gutter
        cards = self:buildCards(side_w, true)
        self._side_w = side_w
        first_avail, avail = body_h, body_h
    else
        grid_w = content_w
        cards = self:buildCards(content_w, false)
        local used = 0
        for _i, c in ipairs(cards) do used = used + c:getSize().h + vgap end
        first_avail, avail = body_h - used, body_h
    end
    local gm = self:gridMetrics(grid_w)
    local secs = {}
    for i, s in ipairs(self.model.sections) do secs[i] = { count = #s.games } end
    local pages = Layout.paginate(secs, gm.cols, first_avail, avail, gm.header_h, gm.row_h)
    -- A first page with no grid on it is still a page: the cards are on it.
    self.n_pages = #pages
    self.page = Layout.clampPage(self.page, self.n_pages)

    local grid
    if #self.model.sections == 0 then
        grid = self:emptyGrid(grid_w)
    else
        grid = self:buildGridPage(grid_w, gm, pages[self.page])
    end

    local body
    if landscape then
        local side = VerticalGroup:new{ align = "left" }
        for i, c in ipairs(cards) do
            if i > 1 then side[#side + 1] = VerticalSpan:new{ width = vgap } end
            side[#side + 1] = c
        end
        body = HorizontalGroup:new{
            align = "top",
            side,
            HorizontalSpan:new{ width = gutter },
            grid,
        }
    else
        body = VerticalGroup:new{ align = "left" }
        if self.page == 1 then
            for _i, c in ipairs(cards) do
                body[#body + 1] = c
                body[#body + 1] = VerticalSpan:new{ width = vgap }
            end
        end
        body[#body + 1] = grid
    end

    -- The page line only when there are pages; the room it frees on a
    -- single page goes to the filler, so the footer stays at the bottom.
    local subtitle = self.n_pages > 1 and T(_("Page %1 of %2"), self.page, self.n_pages) or nil
    local title_bar = titleBar(subtitle)
    local filler = math.max(0, H - title_bar:getSize().h - footer_h - 2 * vgap - body:getSize().h)
    self.layout = VerticalGroup:new{
        align = "center",
        title_bar,
        VerticalSpan:new{ width = vgap },
        LeftContainer:new{
            dimen = Geom:new{ w = content_w, h = body:getSize().h },
            body,
        },
        VerticalSpan:new{ width = filler + vgap },
        footer,
    }
    self[1] = self.layout
end

function HomeScreen:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if self.layout then
        local lw = self.layout:getSize().w
        self.layout:paintTo(bb, x + math.floor((self.dimen.w - lw) / 2), y)
    end
end

function HomeScreen:refresh()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- Re-read everything (after choosing games, or coming back from a sub-screen).
function HomeScreen:reload()
    self.model = self.dash:buildModel()
    self:refresh()
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

function HomeScreen:onNextPage()
    if self.page < (self.n_pages or 1) then
        self.page = self.page + 1
        self:refresh()
    end
    return true
end

function HomeScreen:onPrevPage()
    if self.page > 1 then
        self.page = self.page - 1
        self:refresh()
    end
    return true
end

function HomeScreen:onSwipe(_arg, ges)
    if ges.direction == "west" then return self:onNextPage() end
    if ges.direction == "east" then return self:onPrevPage() end
end

function HomeScreen:onClose()
    UIManager:close(self, "flashui")
    return true
end

function HomeScreen:onCloseWidget()
    if self.dash then self.dash:onHomeClosed(self) end
end

-- Rotation: rebuild for the new size.
function HomeScreen:onScreenResize(dimen)
    self.dimen = Geom:new{ x = 0, y = 0, w = dimen and dimen.w or Screen:getWidth(),
                           h = dimen and dimen.h or Screen:getHeight() }
    self:refresh()
end

return HomeScreen
