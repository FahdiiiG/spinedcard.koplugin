--[[
Book card - one left-aligned "underlined label over big value" cell, as used in
the statistics column of the card.

  StatCell:new{
      value = "12h 51 min", label = "Reading Time",
      width = <px>,
      value_face = <face>, label_face = <face>,
      color = <text colour>,                     -- shared fallback for both
      value_color = <text colour>,                -- overrides `color` for the value
      label_color = <text colour>,                -- overrides `color` for the label
  }
]]--

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local LineWidget = require("ui/widget/linewidget")
local Screen = require("device").screen
local LeftContainer = require("ui/widget/container/leftcontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")


-- Thin outlined progress bar: 1 px frame, filled from the left. Only the frame
-- and the filled part are painted, so whatever is behind it stays visible.
local Bar = Widget:extend{
    width = 100,
    height = 8,
    percent = 0,        -- 0..100
    color = nil,        -- defaults to black
}

function Bar:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function Bar:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width, h = self.height }
    local color = self.color or Blitbuffer.COLOR_BLACK
    local b = math.max(1, Screen:scaleBySize(1))
    local w, h = self.width, self.height
    bb:paintRect(x, y, w, b, color)                 -- top
    bb:paintRect(x, y + h - b, w, b, color)         -- bottom
    bb:paintRect(x, y, b, h, color)                 -- left
    bb:paintRect(x + w - b, y, b, h, color)         -- right
    local pct = math.max(0, math.min(100, tonumber(self.percent) or 0))
    local inset = 2 * b                              -- frame + 1 frame-width gap
    local fill_w = math.floor((w - 2 * inset) * pct / 100)
    if fill_w > 0 then
        bb:paintRect(x + inset, y + inset, fill_w, h - 2 * inset, color)
    end
end

local StatCell = LeftContainer:extend{
    value = "",
    label = "",
    width = 100,
    value_face = nil,
    label_face = nil,
    color = nil,        -- shared text colour fallback, defaults to black
    value_color = nil,
    label_color = nil,
    bar = nil,          -- progress 0..100: draws a bar under the value
    bar_color = nil,
}

function StatCell:init()
    -- Label on top (underlined), value underneath, no extra gap between them.
    local label = TextWidget:new{
        text = self.label,
        face = self.label_face,
        max_width = self.width,
        fgcolor = self.label_color or self.color or Blitbuffer.COLOR_BLACK,
    }
    local underline = LineWidget:new{
        background = self.label_color or self.color or Blitbuffer.COLOR_BLACK,
        dimen = Geom:new{ w = label:getSize().w, h = math.max(1, Screen:scaleBySize(1)) },
    }
    local group = VerticalGroup:new{
        align = "left",
        label,
        underline,
        TextWidget:new{
            text = self.value,
            face = self.value_face,
            max_width = self.width,
            fgcolor = self.value_color or self.color or Blitbuffer.COLOR_BLACK,
        },
    }
    if self.bar then
        table.insert(group, VerticalSpan:new{ width = StatCell.BAR_GAP() })
        table.insert(group, Bar:new{
            width = self.width,
            height = StatCell.BAR_H(),
            percent = self.bar,
            color = self.bar_color or self.value_color or self.color,
        })
    end
    self.dimen = Geom:new{ w = self.width, h = group:getSize().h }
    self[1] = group
end

-- Shared sizes, so card_view can reserve the same height in the grid layout.
function StatCell.BAR_H() return math.max(6, Screen:scaleBySize(6)) end
function StatCell.BAR_GAP() return Screen:scaleBySize(2) end
StatCell.Bar = Bar

return StatCell
