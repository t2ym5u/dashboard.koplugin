-- widgets.lua -- the few building blocks the dashboard screens share: a tap
-- target, a bordered text card, a section header and the footer bar.
--
-- Everything is black on white with thick borders and no animation, sized
-- for a finger on an e-ink screen.

local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer  = require("ui/widget/container/inputcontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local LineWidget      = require("ui/widget/linewidget")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")

local Widgets = {}

function Widgets.face(size)
    return Font:getFace("cfont", size)
end

-- Height of one line of text at `size`.
function Widgets.lineHeight(size, bold)
    local tw = TextWidget:new{ text = "Ay", face = Widgets.face(size), bold = bold }
    local h = tw:getSize().h
    tw:free()
    return h
end

-- An invisible tap target around any widget.
local Tappable = InputContainer:extend{
    callback      = nil,
    hold_callback = nil,
}

function Tappable:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    self.ges_events = {
        TapDashTarget = {
            GestureRange:new{ ges = "tap", range = function() return self.dimen end },
        },
    }
    if self.hold_callback then
        self.ges_events.HoldDashTarget = {
            GestureRange:new{ ges = "hold", range = function() return self.dimen end },
        }
    end
end

function Tappable:onTapDashTarget()
    if self.callback then self.callback() end
    return true
end

function Tappable:onHoldDashTarget()
    if self.hold_callback then self.hold_callback() end
    return true
end

Widgets.Tappable = Tappable

-- A bordered card of text lines, `w` wide and at least `min_h` tall (its
-- content's own height when nil), content left-aligned and vertically
-- centred. lines: { text=, size=, bold=, max_lines= } or { widget = fn(inner_w) }.
function Widgets.card(w, min_h, lines, callback)
    local bw  = Size.border.thick
    local pad = Size.padding.large
    local inner_w = w - 2 * (bw + pad)
    local vg = VerticalGroup:new{ align = "left" }
    for i, ln in ipairs(lines) do
        if i > 1 then vg[#vg + 1] = VerticalSpan:new{ width = Size.span.vertical_large } end
        if ln.widget then
            vg[#vg + 1] = ln.widget(inner_w)
        elseif (ln.max_lines or 1) > 1 then
            local tb = TextBoxWidget:new{
                text = ln.text, face = Widgets.face(ln.size), bold = ln.bold, width = inner_w,
            }
            if #tb.vertical_string_list > ln.max_lines then
                local line_h = tb.line_height_px
                tb:free()
                tb = TextBoxWidget:new{
                    text   = ln.text,
                    face   = Widgets.face(ln.size),
                    bold   = ln.bold,
                    width  = inner_w,
                    height = ln.max_lines * line_h,
                    height_overflow_show_ellipsis = true,
                }
            end
            vg[#vg + 1] = tb
        else
            vg[#vg + 1] = TextWidget:new{
                text      = ln.text,
                face      = Widgets.face(ln.size),
                bold      = ln.bold,
                max_width = inner_w,
            }
        end
    end
    local inner_h = math.max(vg:getSize().h, (min_h or 0) - 2 * (bw + pad))
    local frame = FrameContainer:new{
        bordersize = bw,
        radius     = Size.radius.window,
        padding    = pad,
        background = Blitbuffer.COLOR_WHITE,
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            vg,
        },
    }
    if not callback then return frame end
    return Tappable:new{ callback = callback, frame }
end

-- A game tile with two centred lines, drawn like the Button tiles beside it
-- (same outer size, border and radius): `line1` bold, `line2` regular and a
-- little smaller. For a multiplayer tile -- the game's name, then
-- "· à plusieurs" -- which as one Button label wrapped inside the name and
-- lost the mode to the ellipsis. Each line shrinks (the name down to 7
-- points less) before it is truncated.
--   o = { w =, label_h =, line1 =, line2 =, size =, callback =, hold_callback = }
function Widgets.twoLineTile(o)
    local bw = Size.border.thick
    local pad_v = Size.padding.button
    local inner_w = o.w - 2 * (bw + Size.padding.default)
    local inner_h = o.label_h + 2 * pad_v
    -- A TextWidget's box is the font's full line height (about 1.4 em),
    -- room two lines in a Button-sized tile do not have: each line here gets
    -- a 1.15 em box instead, its baseline moved up by half the difference,
    -- as tight as a Button's own two-line TextBoxWidget (line_height = 0).
    local function line(text, sz, bold, max_width)
        local tw = TextWidget:new{ text = text, face = Widgets.face(sz), bold = bold,
                                   max_width = max_width }
        local full = tw:getSize().h
        local h = math.ceil(tw.face.size * 1.15)
        if h < full then
            local base = tw:getBaseline()
            tw:free()
            tw = TextWidget:new{ text = text, face = Widgets.face(sz), bold = bold,
                                 max_width = max_width, forced_height = h,
                                 forced_baseline = base - math.floor((full - h) / 2) }
        end
        return tw
    end
    -- The largest size (down to 6 points less) at which `text` fits the
    -- width; truncated at the smallest one otherwise.
    local function fit(text, size, bold, min_size)
        for sz = size, min_size + 1, -1 do
            local tw = line(text, sz, bold)
            if tw:getSize().w <= inner_w then return tw, sz end
            tw:free()
        end
        return line(text, min_size, bold, inner_w), min_size
    end
    -- The second line stays smaller than the first, even when a long name
    -- had to shrink.
    local l1, l2
    for sz = o.size, o.size - 6, -1 do
        if l1 then l1:free(); l2:free() end
        local s1
        l1, s1 = fit(o.line1, sz, true, o.size - 7)
        l2 = fit(o.line2, math.min(sz - 3, s1 - 2), false, o.size - 9)
        if l1:getSize().h + l2:getSize().h <= inner_h - 2 * Size.padding.small then break end
    end
    local frame = FrameContainer:new{
        bordersize = bw,
        radius     = Size.radius.button,
        padding    = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = o.w - 2 * bw, h = inner_h },
            VerticalGroup:new{ align = "center", l1, l2 },
        },
    }
    return Tappable:new{ callback = o.callback, hold_callback = o.hold_callback, frame }
end

-- A category header: bold label over a rule.
function Widgets.header(w, label, size)
    return VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = Size.padding.large },
        TextWidget:new{ text = label, face = Widgets.face(size), bold = true, max_width = w },
        VerticalSpan:new{ width = Size.span.vertical_large },
        LineWidget:new{ dimen = Geom:new{ w = w, h = Size.line.medium } },
        VerticalSpan:new{ width = Size.span.vertical_large },
    }
end

-- The bottom bar: a rule, then a row of borderless buttons split by thin
-- separators. specs: { { text=, weight=, callback=, enabled_func= }, ... };
-- widths are proportional to `weight` (default 1), so the page arrows can be
-- narrower than the labelled buttons.
function Widgets.footer(w, specs)
    local total = 0
    for _i, s in ipairs(specs) do total = total + (s.weight or 1) end
    local sep_w = Size.line.medium
    local avail = w - sep_w * (#specs - 1)
    local btn_h = Widgets.lineHeight(20, true) + 2 * Size.padding.large
    local row = HorizontalGroup:new{ align = "center" }
    local used = 0
    for i, s in ipairs(specs) do
        local bw = i == #specs and (avail - used) or math.floor(avail * (s.weight or 1) / total)
        used = used + bw
        if i > 1 then
            row[#row + 1] = LineWidget:new{
                dimen = Geom:new{ w = sep_w, h = math.floor(btn_h * 0.6) },
                background = Blitbuffer.COLOR_DARK_GRAY,
            }
        end
        row[#row + 1] = Button:new{
            text           = s.text,
            width          = bw,
            height         = btn_h - 2 * Size.padding.button,
            bordersize     = 0,
            text_font_size = 20,
            enabled_func   = s.enabled_func,
            callback       = s.callback,
        }
    end
    return VerticalGroup:new{
        align = "center",
        LineWidget:new{ dimen = Geom:new{ w = w, h = Size.line.thick } },
        row,
    }
end

return Widgets
