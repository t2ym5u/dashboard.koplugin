-- widgets.lua -- the few building blocks the dashboard screens share: a tap
-- target, a bordered text card, a section header and the footer bar.
--
-- Everything is black on white with thick borders and no animation, sized
-- for a finger on an e-ink screen.

local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
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
    callback = nil,
}

function Tappable:init()
    local size = self[1]:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }
    self.ges_events = {
        TapDashTarget = {
            GestureRange:new{ ges = "tap", range = function() return self.dimen end },
        },
    }
end

function Tappable:onTapDashTarget()
    if self.callback then self.callback() end
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
