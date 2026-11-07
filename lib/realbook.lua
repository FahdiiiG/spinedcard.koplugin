--[[
"Real book" cover: draws the cover like a physical book - a dark spine with
the book's name running up it (slightly sheared, with angled ends), a stack
of page edges along the top (more lines for a longer book), a black outline
with rounded right corners and, optionally, a ribbon bookmark that tracks
the reading progress along the page stack.

Derived from two KOReader user patches, redrawn once into a bitmap for the
card instead of onto a file-browser grid:
  * 2-real-books.lua by ReaLx3m (AGPL-3.0)
      https://github.com/ReaLx3m/KOReader-AI-Slop-User-Patches
      spine, sheared label, page-line stack, rounded corners, options
  * 2-bookshelf-progress-bookmark.lua by 3lementa1 (GPL-3.0)
      https://github.com/3lementa1/KOReader-Progress-Bookmarks
      the progress ribbon
The cover edge, the 12-tier page stack, night-mode handling and the dark-card
spine are additions made for this plugin.

  M.render(cover_bb, box_w, box_h, opts) -> bitmap, w, h   (or nil on failure)
      cover_bb   decoded cover image (any Blitbuffer)
      box_w/h    the largest outer size the finished book may take
      opts.name       text for the spine
      opts.pages      page count (nil = 4 page lines)
      opts.progress   0..1 reading progress (nil = never opened)
      opts.finished   true when the book is complete
      opts.bg         colour the bitmap is cleared to (the card background)
  M.buildMenu(ctx) -> menu item table ("Real book cover" submenu)
      ctx.enabled_key / ctx.text_key / ctx.getTextMode : owned by card_view

Settings are stored as "bookcard_rb_<name>" (see DEFAULTS).
]]

local deps = ...
local Prefs  = deps.Prefs
local Locale = deps.Locale
local _ = Locale._

local Blitbuffer      = require("ffi/blitbuffer")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local TextWidget      = require("ui/widget/textwidget")
local CenterContainer = require("ui/widget/container/centercontainer")

local floor, max, min = math.floor, math.max, math.min

local M = {}

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
local DEFAULTS = {
    -- spine
    spine_width_pct = 100,         -- 100..200
    font_face       = "NotoSerifBI",
    font_size       = 16,          -- 10..24 (units)
    text_shear      = 30,          -- 0..100 ("text lean")
    alpha           = 80,          -- 0..100 label opacity
    dark_mode       = true,        -- (light card) white text on a black spine
    dark_spine      = 20,          -- (dark card) spine brightness %, 0..60: dark grey
    dark_text       = 88,          -- (dark card) spine text brightness %, 40..100: off-white
    direction_down  = false,       -- text reads top-to-bottom
    -- cover shape
    cover_scale_pct = 100,         -- 50..100
    aspect_enabled  = false,
    aspect_w        = 2,
    aspect_h        = 3,
    -- page lines
    page_thickness  = 2,
    page_spacing    = 1,
    line_len_pct    = 102,         -- 10..150 (% of cover width)
    line_color      = "GRAY_9",
    -- Page stack: 2..MAX_TIER lines; tier N covers books up to page_range_N
    -- pages, the last tier everything above (sized for books up to ~25000 pages).
    lines_enabled_2 = true, lines_enabled_3 = true, lines_enabled_4 = true,
    lines_enabled_5 = true, lines_enabled_6 = true, lines_enabled_7 = true,
    lines_enabled_8 = true, lines_enabled_9 = true, lines_enabled_10 = true,
    lines_enabled_11 = true, lines_enabled_12 = true,
    page_range_2 = 100, page_range_3 = 200, page_range_4 = 350, page_range_5 = 500,
    page_range_6 = 700, page_range_7 = 1000, page_range_8 = 2000, page_range_9 = 4000,
    page_range_10 = 7000, page_range_11 = 12000,
    night_follow    = true,        -- invert with night mode (cover stays natural)
    -- cover edge: the board edge along the top, right and bottom of the cover
    edge_style      = "thick",     -- "off" | "thin" (= page line) | "thick" (= 2 x page line)
    edge_light      = 20,          -- (light card) edge brightness %, 0..60, AS DISPLAYED
    edge_dark       = 45,          -- (dark card) edge brightness %, 20..80, AS DISPLAYED
    -- progress bookmark
    bm_enabled      = true,
    bm_tracking     = "both",      -- "both" | "horizontal" | "vertical"
    bm_size         = "thick",     -- "thin" | "medium" | "thick" | "custom"
    bm_custom       = 14,          -- custom ribbon width, % of the cover width (2..40)
    bm_length       = "short",     -- "short" | "medium" | "long"
    bm_color        = "default",   -- "default" | "lighter" | "darker"
    bm_details      = true,        -- edge highlights
    bm_finished     = "start_half",-- "remove" | "start" | "start_half" | "keep_end" | "keep_end_half"
    bm_unopened     = "off",       -- "off" | "half" | "show"
}

local PREFIX = "bookcard_rb_"

function M.get(key)
    local v = Prefs.read(PREFIX .. key, nil)
    if v == nil then return DEFAULTS[key] end
    return v
end

function M.set(key, value)
    Prefs.save(PREFIX .. key, value)
end

local get, set = M.get, M.set

-- Font faces offered for the spine text (as in the original patch).
local MAX_TIER = 12

local FONT_FACES = {
    { key = "NotoSerifI",   label = "Noto Serif Italic",       file = "NotoSerif-Italic.ttf" },
    { key = "NotoSerifBI",  label = "Noto Serif Bold Italic",  file = "NotoSerif-BoldItalic.ttf" },
    { key = "NotoSerif",    label = "Noto Serif Regular",      file = "NotoSerif-Regular.ttf" },
    { key = "NotoSerifB",   label = "Noto Serif Bold",         file = "NotoSerif-Bold.ttf" },
    { key = "NotoSansI",    label = "Noto Sans Italic",        file = "NotoSans-Italic.ttf" },
    { key = "NotoSansBI",   label = "Noto Sans Bold Italic",   file = "NotoSans-BoldItalic.ttf" },
    { key = "NotoSans",     label = "Noto Sans Regular",       file = "NotoSans-Regular.ttf" },
    { key = "NotoSansB",    label = "Noto Sans Bold",          file = "NotoSans-Bold.ttf" },
    { key = "FreeSerif",    label = "Free Serif",              file = "freefont/FreeSerif.ttf" },
    { key = "FreeSans",     label = "Free Sans",               file = "freefont/FreeSans.ttf" },
    { key = "DroidMono",    label = "Droid Sans Mono",         file = "droid/DroidSansMono.ttf" },
    { key = "NaskhArabic",  label = "Noto Naskh Arabic",       file = "NotoNaskhArabic-Regular.ttf" },
    { key = "NaskhArabicB", label = "Noto Naskh Arabic Bold",  file = "NotoNaskhArabic-Bold.ttf" },
    { key = "ArabicUI",     label = "Noto Sans Arabic UI",     file = "NotoSansArabicUI-Regular.ttf" },
    { key = "ArabicUIB",    label = "Noto Sans Arabic UI Bold",file = "NotoSansArabicUI-Bold.ttf" },
    { key = "BengaliUI",    label = "Noto Sans Bengali UI",    file = "NotoSansBengaliUI-Regular.ttf" },
    { key = "BengaliUIB",   label = "Noto Sans Bengali UI Bold", file = "NotoSansBengaliUI-Bold.ttf" },
    { key = "CJK",          label = "Noto Sans CJK SC",        file = "NotoSansCJKsc-Regular.otf" },
    { key = "DevanagariUI", label = "Noto Sans Devanagari UI", file = "NotoSansDevanagariUI-Regular.ttf" },
    { key = "DevanagariUIB",label = "Noto Sans Devanagari UI Bold", file = "NotoSansDevanagariUI-Bold.ttf" },
    { key = "Symbols",      label = "Symbols",                 file = "symbols.ttf" },
}

-- Night mode / forced dark theme. See render(): with FLIP set, every colour
-- drawn onto the bitmap is inverted (the card paints "reversed" for a forced
-- theme), exactly like the card's own text and icons.
local FLIP = false
local function col(c)
    if not FLIP then return c end
    if c.invert then return c:invert() end
    return Blitbuffer.Color8(0xFF - (c.a or 0))
end
local function C(name) return col(Blitbuffer["COLOR_" .. name]) end

local function fontFile()
    local k = get("font_face")
    for _i, f in ipairs(FONT_FACES) do
        if f.key == k then return f.file end
    end
    return "NotoSerif-BoldItalic.ttf"
end

local LINE_COLORS = {
    { key = "GRAY_1",     label = "Gray 1 (darkest)", color = function() return Blitbuffer.COLOR_GRAY_1 end },
    { key = "GRAY_2",     label = "Gray 2",           color = function() return Blitbuffer.COLOR_GRAY_2 end },
    { key = "GRAY_3",     label = "Gray 3",           color = function() return Blitbuffer.COLOR_GRAY_3 end },
    { key = "GRAY_4",     label = "Gray 4",           color = function() return Blitbuffer.COLOR_GRAY_4 end },
    { key = "GRAY_5",     label = "Gray 5",           color = function() return Blitbuffer.COLOR_GRAY_5 end },
    { key = "GRAY_6",     label = "Gray 6",           color = function() return Blitbuffer.COLOR_GRAY_6 end },
    { key = "GRAY_7",     label = "Gray 7",           color = function() return Blitbuffer.COLOR_GRAY_7 end },
    { key = "DARK_GRAY",  label = "Dark gray",        color = function() return Blitbuffer.COLOR_DARK_GRAY end },
    { key = "GRAY_9",     label = "Gray 9 (default)", color = function() return Blitbuffer.COLOR_GRAY_9 end },
    { key = "GRAY",       label = "Gray (mid)",       color = function() return Blitbuffer.COLOR_GRAY end },
    { key = "LIGHT_GRAY", label = "Light gray",       color = function() return Blitbuffer.COLOR_LIGHT_GRAY end },
}

local function lineColor()
    local k = get("line_color")
    for _i, e in ipairs(LINE_COLORS) do
        if e.key == k then return e.color() end
    end
    return Blitbuffer.COLOR_GRAY_9
end

-- Page count -> number of page lines (tiers as in the original patch).
local function numLines(pages)
    if not pages then return 4 end
    local n = MAX_TIER
    for tier = 2, MAX_TIER - 1 do
        if get("lines_enabled_" .. tier) ~= false and pages <= get("page_range_" .. tier) then
            n = tier
            break
        end
    end
    while n > 2 and get("lines_enabled_" .. n) == false do n = n - 1 end
    return n
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
local function paintRoundedLine(bb, x, y, len, thick, color)
    if len <= 0 or thick <= 0 then return end
    local r = floor(thick / 2)
    local body_len = len - 2 * r
    if body_len > 0 then bb:paintRect(x + r, y, body_len, thick, color) end
    for dr = -r, r do
        local half_chord = floor(math.sqrt(max(0, r * r - dr * dr)) + 0.5)
        if half_chord > 0 then
            local cy = y + r + dr
            bb:paintRect(x + r - half_chord, cy, half_chord, 1, color)
            bb:paintRect(x + len - r, cy, half_chord, 1, color)
        end
    end
end

-- Spine width: tall enough for one line of the label font, at most 15% of the
-- box, then multiplied by the "spine width" setting.
local function spineWidth(box_w)
    local tw = TextWidget:new{ text = "A", face = Font:getFace("cfont", get("font_size")) }
    local font_h = tw:getSize().h
    tw:free()
    local max_w = floor((font_h + 2 * 2) * 0.75)
    local base = min(max_w, floor(box_w * 0.15))
    return max(4, floor(base * get("spine_width_pct") / 100))
end

-- Progress ribbon, ported from the Bookshelf progress-bookmark patch: hangs
-- over the cover from the page stack, at a height along the stack and a
-- position along the page that follow the reading progress.
local function paintBookmark(bb, x, y, w, h, progress, half, spine_w, num_lines,
                             page_thick, page_gap, label_x, label_y, cut_h_top)
    local tracking = get("bm_tracking")
    progress = max(0, min(1, progress or 0))

    local size = get("bm_size")
    local thickness = size == "custom" and (get("bm_custom") * 10)
        or ({ thin = 85, medium = 100, thick = 135 })[size] or 135
    local ribbon_w = max(2, floor(w * thickness / 1000 + 0.5))
    local ribbon_h = max(6, floor(h * 0.28))
    local length = ({ short = 65, medium = 100, long = 135 })[get("bm_length")] or 65
    ribbon_h = max(3, floor(ribbon_h * (length / 100) * (half and 0.5 or 1) + 0.5))

    local cname = get("bm_color")
    local ribbon_color = cname == "lighter" and C("GRAY_4")
        or cname == "darker" and C("GRAY_1")
        or C("GRAY_2")
    local outer_dark, outer_light = C("GRAY_7"), C("GRAY_1")
    local inner_light, inner_dark = C("GRAY_3"), C("GRAY_5")
    local details = get("bm_details") ~= false

    local line_step = page_thick + page_gap
    local top_page = y - page_gap - page_thick
    local bottom_page = top_page - (num_lines - 1) * line_step
    local by = floor(tracking ~= "horizontal"
        and (top_page - progress * (top_page - bottom_page)) or top_page)
    by = by + floor(page_thick / 2)

    local left, right
    if tracking == "both" then
        local row_in_cut = by - label_y
        local trim = 0
        if row_in_cut >= 0 and row_in_cut < cut_h_top then
            trim = floor(((cut_h_top - row_in_cut) / cut_h_top) ^ 0.6 * spine_w)
        end
        left = label_x + spine_w - trim + 4
        right = x + w - 2
    else
        left = x + floor(w * 0.04)
        right = x + w - (tracking == "horizontal" and 0 or 2)
    end
    local eased = 1 - (1 - progress) * (1 - progress)

    local notch_depth = max(1, floor(ribbon_w / 2))
    local hinge_size = 2
    local max_shift = floor(w * 0.06)
    local bx
    if tracking == "vertical" then
        bx = left
    else
        local end_clearance = floor((ribbon_w + 1) / 2) + 1
        local first_x = left + end_clearance
        local last_x = right - ribbon_w - max_shift - end_clearance
        bx = first_x + floor(eased * max(0, last_x - first_x))
    end
    local drop_x = bx

    for i = 0, ribbon_h do
        local ry = by + i
        local rx
        if ry < y - hinge_size then
            local t = max(0, min(1, (ry - by) / max(1, h * 0.20)))
            rx = bx + floor(t ^ 0.25 * max_shift)
            drop_x = rx
        else
            rx = drop_x
        end

        if i >= ribbon_h - notch_depth then
            local offset = ribbon_h - i
            for px = 0, ribbon_w - 1 do
                if px < offset or px > ribbon_w - 1 - offset then
                    local draw_x = rx + px
                    bb:paintRect(draw_x, ry, 1, 1, ribbon_color)
                    if details and px == 0 then bb:paintRect(draw_x, ry, 1, 1, C("GRAY_5")) end
                    if details and px == ribbon_w - 1 then bb:paintRect(draw_x, ry, 1, 1, C("GRAY_6")) end
                    if details and (px == offset - 1 or px == ribbon_w - offset) then
                        bb:paintRect(draw_x, ry, 1, 1, C("WHITE"))
                    end
                    if details and (px == offset or px == ribbon_w - 1 - offset) then
                        bb:paintRect(draw_x, ry, 1, 1, C("GRAY_6"))
                    end
                end
            end
        else
            bb:paintRect(rx, ry, ribbon_w, 1, ribbon_color)
            if details then
                bb:paintRect(rx, ry, 1, 1, C("GRAY_5"))
                bb:paintRect(rx + ribbon_w - 1, ry, 1, 1, C("GRAY_6"))
            end
        end

        if details then
            bb:paintRect(rx - 1, ry, 1, 1, outer_dark)
            bb:paintRect(rx + ribbon_w, ry, 1, 1, outer_light)
            if ribbon_w > 2 then
                bb:paintRect(rx + 1, ry, 1, 1, inner_light)
                bb:paintRect(rx + ribbon_w - 2, ry, 1, 1, inner_dark)
            end
        end
    end
end

-- Where the ribbon sits for this book, or nil for "no ribbon".
local function bookmarkState(opts)
    if get("bm_enabled") == false then return nil end
    local pct = opts.progress
    local finished = opts.finished and true or false
    local unopened = not finished and (pct == nil or pct <= 0)
    local fmode, umode = get("bm_finished"), get("bm_unopened")
    if finished and fmode == "remove" then return nil end
    if unopened and umode == "off" then return nil end
    if finished then
        pct = (fmode == "start" or fmode == "start_half") and 0 or 1
    end
    local half = (unopened and umode == "half")
        or (finished and (fmode == "start_half" or fmode == "keep_end_half"))
    return pct or 0, half
end

local function render(cover_bb, box_w, box_h, opts)
    local name = opts.name
    -- Night mode: with "follow" on, the bitmap is painted like the rest of the
    -- card (the panel inverts it at refresh; a forced light/dark theme flips
    -- the colours here) and only the cover is pre-inverted so it stays
    -- natural. With "follow" off the caller's ImageWidget pre-inverts the
    -- whole bitmap in night mode instead, so it always looks as drawn.
    local follow = get("night_follow") ~= false
    FLIP = follow and opts.flip == true
    local night = opts.night == true
    local num_lines = numLines(opts.pages)
    local strip_w = spineWidth(box_w)
    local page_thick, page_gap = get("page_thickness"), get("page_spacing")
    local line_step = page_thick + page_gap
    local l_total = num_lines * line_step

    -- Room for the cover image beside the spine / under the page lines.
    local avail_w = box_w - strip_w - 1
    local avail_h = box_h - l_total
    if avail_w < 8 or avail_h < 8 then return nil end
    local img_w, img_h
    if get("aspect_enabled") then
        -- Stretch to the chosen ratio, as large as fits.
        local rw, rh = max(1, get("aspect_w")), max(1, get("aspect_h"))
        img_h = floor(avail_w * rh / rw)
        if img_h <= avail_h then
            img_w = avail_w
        else
            img_h = avail_h
            img_w = max(1, floor(avail_h * rw / rh))
        end
    else
        local scale = min(avail_w / cover_bb:getWidth(), avail_h / cover_bb:getHeight())
        img_w = floor(cover_bb:getWidth() * scale)
        img_h = floor(cover_bb:getHeight() * scale)
    end
    local pct = get("cover_scale_pct") / 100
    local cover_w = max(1, floor(img_w * pct))
    local cover_h = max(1, floor(img_h * pct))

    local total_w = strip_w + cover_w
    local total_h = l_total + cover_h
    local cover_x, cover_y = strip_w, l_total

    local ok_dev, Device = pcall(require, "device")
    local bb_type = (ok_dev and Device.screen and Device.screen.bb and Device.screen.bb:getType())
        or Blitbuffer.TYPE_BB8
    -- Background of the bitmap = the card's displayed background.
    local bg = opts.bg or Blitbuffer.COLOR_WHITE
    if not follow and night then
        bg = bg.invert and bg:invert() or Blitbuffer.Color8(0xFF - (bg.a or 0))
    end
    local bb = Blitbuffer.new(total_w, total_h, bb_type)
    bb:paintRect(0, 0, total_w, total_h, bg)

    local scaled = cover_bb:scale(cover_w, cover_h)
    if follow and night then scaled:invert() end   -- shown natural after the panel inverts
    bb:blitFrom(scaled, cover_x, cover_y, 0, 0, cover_w, cover_h)
    scaled:free()

    -- Cover edge: a board edge along the top, right and bottom of the cover
    -- (none on the left, the spine is there), with rounded right corners.
    -- Painted in a GREY whose DISPLAYED brightness is the setting, so it is
    -- never a hard black line on a light card nor a white one in night mode
    -- (the panel inverts the whole bitmap in night mode, so the painted tone
    -- is the complement there). "off" paints no edge but keeps the rounded
    -- corners.
    do
        local style = get("edge_style")
        local ot = style == "off" and 0 or (style == "thin" and page_thick or page_thick * 2)
        local base = max(ot, page_thick)
        local r = max(base, min(base * 4, floor(min(cover_w, cover_h) / 4)))
        local r_inner = max(0, r - ot)
        local cx = cover_x + cover_w - r
        local cy_tr = cover_y + r
        local cy_br = cover_y + cover_h - 1 - r
        local right_edge = cover_x + cover_w - 1
        local bottom_edge = cover_y + cover_h - 1

        local edge_color
        if ot > 0 then
            local shown = (opts.dark == true and follow) and get("edge_dark") or get("edge_light")
            local v = floor(shown / 100 * 255 + 0.5)
            if follow and night then v = 255 - v end
            edge_color = Blitbuffer.Color8(v)
            bb:paintRect(cover_x, cover_y, cx - cover_x, ot, edge_color)
            bb:paintRect(cover_x, bottom_edge - ot + 1, cx - cover_x, ot, edge_color)
            if cy_br >= cy_tr then
                bb:paintRect(right_edge - ot + 1, cy_tr, ot, cy_br - cy_tr + 1, edge_color)
            end
        end
        for dy = 0, r do
            local outer_dx = floor(math.sqrt(max(0, r * r - dy * dy)) + 0.5)
            local inner_dx = r_inner > 0
                and floor(math.sqrt(max(0, r_inner * r_inner - dy * dy)) + 0.5) or 0
            outer_dx = min(outer_dx, right_edge - cx)
            local ring_start = cx + inner_dx
            local ring_end = cx + outer_dx
            local ring_len = ring_end - ring_start + 1
            local erase_start = ring_end + 1
            local erase_len = right_edge - erase_start + 1
            local row_tr = cy_tr - dy
            if edge_color and ring_len > 0 then bb:paintRect(ring_start, row_tr, ring_len, 1, edge_color) end
            if erase_len > 0 then bb:paintRect(erase_start, row_tr, erase_len, 1, bg) end
            if dy > 0 then
                local row_br = cy_br + dy
                if edge_color and ring_len > 0 then bb:paintRect(ring_start, row_br, ring_len, 1, edge_color) end
                if erase_len > 0 then bb:paintRect(erase_start, row_br, erase_len, 1, bg) end
            end
        end
    end

    -- Spine + page lines.
    local label_x, label_y = 0, 0
    local label_h = cover_h + l_total
    local cut_h_bot = floor(strip_w * 0.5774)   -- tan(30 deg)
    local cut_h_top = l_total

    if name and name ~= "" then
        local pad = 2
        local text_max_w = label_h - cut_h_top - cut_h_bot - 2 * pad
        local dark = get("dark_mode") ~= false
        local down = get("direction_down") == true
        -- On a dark card (night mode / forced dark) the spine is dark GREY with
        -- off-white text instead of the day look inverted, so it still reads as
        -- different from the light card and is soft on e-ink. The values are the
        -- DISPLAYED brightness; with night mode the panel inverts, so what is
        -- painted is their complement.
        local show_dark = follow and opts.dark == true
        local function painted(v) return night and (255 - v) or v end
        local spine_tone = dark and 0 or 255
        local text_color
        if show_dark then
            spine_tone = painted(floor(get("dark_spine") / 100 * 255 + 0.5))
            text_color = Blitbuffer.Color8(painted(floor(get("dark_text") / 100 * 255 + 0.5)))
        else
            if FLIP then spine_tone = 255 - spine_tone end
            text_color = dark and C("WHITE") or C("BLACK")
        end
        local text_widget = TextWidget:new{
            text = name,
            face = Font:getFace(fontFile(), get("font_size")),
            fgcolor = text_color,
            max_width = max(1, text_max_w),
            truncate_with_ellipsis = false,
        }
        local angle = down and 270 or 90
        local img_angle = down and 90 or 270
        -- The cover's own left strip, stretched to the label length and
        -- rotated, tints the spine.
        local tmp = Blitbuffer.new(label_h, strip_w, bb_type)
        local src = Blitbuffer.new(strip_w, cover_h, bb_type)
        src:blitFrom(bb, 0, 0, cover_x, cover_y, strip_w, cover_h)
        local stretched = src:scale(strip_w, label_h)
        src:free()
        local src_rot = stretched:rotatedCopy(img_angle)
        stretched:free()
        tmp:blitFrom(src_rot, 0, 0, 0, 0, label_h, strip_w)
        src_rot:free()

        local tone = spine_tone
        tmp:blendRectRGB32(0, 0, label_h, strip_w,
            Blitbuffer.ColorRGB32(tone, tone, tone, floor(get("alpha") / 100 * 255)))

        local text_only = CenterContainer:new{
            dimen = Geom:new{ w = label_h, h = strip_w },
            text_widget,
        }
        text_only:paintTo(tmp, 0, 0)
        text_only:free()

        -- Lean the text for the "seen from the side" look.
        local shear = -(get("text_shear") / 100)
        local sheared = Blitbuffer.new(label_h, strip_w, bb_type)
        for row = 0, strip_w - 1 do
            local offset = floor((row - strip_w / 2) * shear)
            local sx = max(0, -offset)
            local dx = max(0, offset)
            local w = label_h - math.abs(offset)
            if w > 0 then sheared:blitFrom(tmp, dx, row, sx, row, w, 1) end
        end
        tmp:free()
        tmp = sheared

        local rotated = tmp:rotatedCopy(angle)
        tmp:free()

        local bgstrip = Blitbuffer.new(strip_w, label_h, bb_type)
        bgstrip:blitFrom(bb, 0, 0, label_x, label_y, strip_w, label_h)
        bb:blitFrom(rotated, label_x, label_y, 0, 0, strip_w, label_h)
        rotated:free()

        -- Angled top (restore what was behind) and bottom (clear) ends.
        for row = 0, max(cut_h_top, cut_h_bot) - 1 do
            local brow = label_h - row
            if row < cut_h_top then
                local t = (cut_h_top - row) / cut_h_top
                local trim = floor(t ^ 0.6 * strip_w)
                if trim > 0 then
                    bb:blitFrom(bgstrip, label_x + strip_w - trim, label_y + row,
                        strip_w - trim, row, trim, 1)
                end
            end
            if row < cut_h_bot then
                local t = (cut_h_bot - row) / cut_h_bot
                local trim = floor((1 - (1 - t) ^ 0.6) * strip_w)
                if trim > 0 then bb:paintRect(label_x, label_y + brow, trim, 1, bg) end
            end
        end
        bgstrip:free()
    end

    -- Page lines above the cover.
    do
        local color = lineColor()
        local fixed_len = max(1, floor(cover_w * get("line_len_pct") / 100))
        for i = 1, num_lines do
            local by = cover_y - page_thick - page_gap - (i - 1) * line_step
            local row_in_cut = by - label_y
            local line_start
            if row_in_cut >= 0 and row_in_cut < cut_h_top then
                local t = (cut_h_top - row_in_cut) / cut_h_top
                line_start = label_x + strip_w - floor(t ^ 0.6 * strip_w)
            else
                line_start = label_x + strip_w
            end
            local this_len = (i == num_lines) and (fixed_len + 1) or fixed_len
            local draw_len = min(this_len, cover_x + cover_w - line_start)
            local c = (i == num_lines) and C("GRAY_2") or col(color)
            if draw_len > 0 then paintRoundedLine(bb, line_start, by, draw_len, page_thick, c) end
        end
    end

    -- Progress bookmark, over everything.
    local bm_pct, bm_half = bookmarkState(opts)
    if bm_pct then
        paintBookmark(bb, cover_x, cover_y, cover_w, cover_h, bm_pct, bm_half, strip_w,
            num_lines, page_thick, page_gap, label_x, label_y, cut_h_top)
    end

    return bb, total_w, total_h
end

function M.followsNightMode() return get("night_follow") ~= false end

function M.render(cover_bb, box_w, box_h, opts)
    local ok, bb, w, h = pcall(render, cover_bb, box_w, box_h, opts or {})
    FLIP = false
    if ok and bb then return bb, w, h end
    require("logger").warn("BookCard: real-book cover failed:", bb)
    return nil
end

-- ---------------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------------
function M.buildMenu(ctx)
    local function spin(label_fmt, title, key, vmin, vmax, vstep, suffix)
        return {
            text_func = function() return string.format(label_fmt, get(key)) end,
            keep_menu_open = true,
            callback = function(tmi)
                local SpinWidget = require("ui/widget/spinwidget")
                require("ui/uimanager"):show(SpinWidget:new{
                    title_text = title,
                    value = get(key), value_min = vmin, value_max = vmax, value_step = vstep, value_hold_step = (vmax > 1000) and 500 or nil,
                    default_value = DEFAULTS[key],
                    keep_shown_on_apply = true,
                    value_text_func = suffix and function(v) return v .. suffix end or nil,
                    callback = function(s)
                        set(key, s.value)
                        if tmi then tmi:updateItems() end
                    end,
                })
            end,
        }
    end

    local function radio(label, key, value)
        return {
            text = label, radio = true, keep_menu_open = true,
            checked_func = function() return get(key) == value end,
            callback = function() set(key, value) end,
        }
    end

    local function toggle(label, key)
        return {
            text = label, keep_menu_open = true,
            checked_func = function() return get(key) ~= false and get(key) ~= nil end,
            callback = function() set(key, not (get(key) ~= false and get(key) ~= nil)) end,
        }
    end

    local function textModeItem(label, mode)
        return {
            text = label, radio = true, keep_menu_open = true,
            checked_func = function() return ctx.getTextMode() == mode end,
            callback = function() Prefs.save(ctx.text_key, mode) end,
        }
    end

    local face_items = {}
    for _i, f in ipairs(FONT_FACES) do
        face_items[#face_items + 1] = radio(f.label, "font_face", f.key)
    end

    local color_items = {}
    for _i, c in ipairs(LINE_COLORS) do
        color_items[#color_items + 1] = radio(c.label, "line_color", c.key)
    end

    -- Page-line tiers: which tiers exist, and the page count each covers.
    local tier_items = {}
    for n = 2, MAX_TIER do
        tier_items[#tier_items + 1] = {
            text = string.format(_("%d lines"), n),
            keep_menu_open = true,
            enabled_func = function() return n ~= 2 end,   -- 2 lines is the always-on floor
            checked_func = function() return get("lines_enabled_" .. n) ~= false end,
            callback = function() set("lines_enabled_" .. n, get("lines_enabled_" .. n) == false) end,
        }
    end
    local range_items = {}
    for n = 2, MAX_TIER - 1 do
        range_items[#range_items + 1] = spin(
            string.format(_("%d lines up to %%d pages"), n),
            string.format(_("Up to how many pages: %d lines"), n),
            "page_range_" .. n, 10, 25000, 50)
    end

    local ratio_presets = {
        { "2:3", 2, 3 }, { "3:4", 3, 4 }, { "9:16", 9, 16 }, { "1:1", 1, 1 }, { "3:2", 3, 2 },
    }
    local ratio_items = {
        toggle(_("Force aspect ratio"), "aspect_enabled"),
    }
    for _i, p in ipairs(ratio_presets) do
        ratio_items[#ratio_items + 1] = {
            text = p[1], radio = true, keep_menu_open = true,
            checked_func = function() return get("aspect_w") == p[2] and get("aspect_h") == p[3] end,
            callback = function() set("aspect_w", p[2]); set("aspect_h", p[3]) end,
        }
    end
    ratio_items[#ratio_items + 1] = spin(_("Ratio width: %d"), _("Ratio width"), "aspect_w", 1, 20, 1)
    ratio_items[#ratio_items + 1] = spin(_("Ratio height: %d"), _("Ratio height"), "aspect_h", 1, 20, 1)

    return {
        text_func = function()
            return Prefs.readBool(ctx.enabled_key, true) and _("Real book cover: on") or _("Real book cover: off")
        end,
        sub_item_table = {
            {
                text = _("Real book cover"),
                keep_menu_open = true,
                checked_func = function() return Prefs.readBool(ctx.enabled_key, true) end,
                callback = function() Prefs.save(ctx.enabled_key, not Prefs.readBool(ctx.enabled_key, true)) end,
                separator = true,
            },
            {
                text = _("Follow night mode"),
                keep_menu_open = true,
                checked_func = function() return get("night_follow") ~= false end,
                callback = function() set("night_follow", get("night_follow") == false) end,
                separator = true,
            },
            {
                text = _("Spine"),
                sub_item_table = {
                    spin(_("Spine width: %d%%"), _("Spine width"), "spine_width_pct", 100, 200, 5, "%"),
                    {
                        text = _("Spine text"),
                        sub_item_table = {
                            textModeItem(_("Title"), "title"),
                            textModeItem(_("Author - Title"), "author_title"),
                            textModeItem(_("Title - Author"), "title_author"),
                            textModeItem(_("File name"), "filename"),
                        },
                    },
                    { text = _("Font face"), sub_item_table = face_items },
                    spin(_("Font size: %d"), _("Font size"), "font_size", 10, 24, 1),
                    spin(_("Text lean: %d%%"), _("Text lean"), "text_shear", 0, 100, 5, "%"),
                    spin(_("Label opacity: %d%%"), _("Label opacity"), "alpha", 0, 100, 5, "%"),
                    spin(_("Dark card: spine brightness %d%%"), _("Spine brightness on a dark card"), "dark_spine", 0, 60, 5, "%"),
                    spin(_("Dark card: text brightness %d%%"), _("Spine text brightness on a dark card"), "dark_text", 40, 100, 5, "%"),
                    {
                        text_func = function()
                            return get("dark_mode") ~= false and _("Text style: white on black")
                                or _("Text style: black on white")
                        end,
                        keep_menu_open = true,
                        callback = function(tmi)
                            set("dark_mode", not (get("dark_mode") ~= false))
                            if tmi then tmi:updateItems() end
                        end,
                    },
                    {
                        text_func = function()
                            return get("direction_down") == true and _("Text direction: down")
                                or _("Text direction: up")
                        end,
                        keep_menu_open = true,
                        callback = function(tmi)
                            set("direction_down", not (get("direction_down") == true))
                            if tmi then tmi:updateItems() end
                        end,
                    },
                },
            },
            {
                text = _("Cover shape"),
                sub_item_table = {
                    spin(_("Cover size: %d%%"), _("Cover size"), "cover_scale_pct", 50, 100, 5, "%"),
                    { text = _("Aspect ratio"), sub_item_table = ratio_items },
                    {
                        text = _("Cover edge"),
                        sub_item_table = {
                            radio(_("Off (rounded corners only)"), "edge_style", "off"),
                            radio(_("Thin (as thick as a page line)"), "edge_style", "thin"),
                            radio(_("Thick (twice a page line)"), "edge_style", "thick"),
                            spin(_("Light card: edge brightness %d%%"), _("Edge brightness on a light card"), "edge_light", 0, 60, 5, "%"),
                            spin(_("Dark card: edge brightness %d%%"), _("Edge brightness on a dark card"), "edge_dark", 20, 80, 5, "%"),
                        },
                    },
                },
            },
            {
                text = _("Page lines"),
                sub_item_table = {
                    spin(_("Line thickness: %d px"), _("Line thickness"), "page_thickness", 1, 5, 1),
                    spin(_("Line spacing: %d px"), _("Line spacing"), "page_spacing", 0, 5, 1),
                    spin(_("Line length: %d%% of cover width"), _("Line length"), "line_len_pct", 10, 150, 5, "%"),
                    { text = _("Line color"), sub_item_table = color_items },
                    { text = _("Show line tiers"), sub_item_table = tier_items },
                    { text = _("Pages per tier"), sub_item_table = range_items },
                },
            },
            {
                text = _("Progress bookmark"),
                sub_item_table = {
                    toggle(_("Show progress bookmark"), "bm_enabled"),
                    {
                        text = _("Tracking"),
                        sub_item_table = {
                            radio(_("Along the page and up the stack"), "bm_tracking", "both"),
                            radio(_("Along the page only"), "bm_tracking", "horizontal"),
                            radio(_("Up the stack only"), "bm_tracking", "vertical"),
                        },
                    },
                    {
                        text = _("Thickness"),
                        sub_item_table = {
                            radio(_("Thin"), "bm_size", "thin"),
                            radio(_("Medium"), "bm_size", "medium"),
                            radio(_("Thick"), "bm_size", "thick"),
                            radio(_("Custom"), "bm_size", "custom"),
                            spin(_("Custom width: %d%% of cover"), _("Custom ribbon width"), "bm_custom", 2, 40, 1, "%"),
                        },
                    },
                    {
                        text = _("Length"),
                        sub_item_table = {
                            radio(_("Short"), "bm_length", "short"),
                            radio(_("Medium"), "bm_length", "medium"),
                            radio(_("Long"), "bm_length", "long"),
                        },
                    },
                    {
                        text = _("Color"),
                        sub_item_table = {
                            radio(_("Default"), "bm_color", "default"),
                            radio(_("Lighter"), "bm_color", "lighter"),
                            radio(_("Darker"), "bm_color", "darker"),
                        },
                    },
                    toggle(_("Edge highlights"), "bm_details"),
                    {
                        text = _("Finished books"),
                        sub_item_table = {
                            radio(_("Half bookmark at the start"), "bm_finished", "start_half"),
                            radio(_("Full bookmark at the start"), "bm_finished", "start"),
                            radio(_("Full bookmark at the end"), "bm_finished", "keep_end"),
                            radio(_("Half bookmark at the end"), "bm_finished", "keep_end_half"),
                            radio(_("No bookmark"), "bm_finished", "remove"),
                        },
                    },
                    {
                        text = _("Unopened books"),
                        sub_item_table = {
                            radio(_("No bookmark"), "bm_unopened", "off"),
                            radio(_("Half bookmark"), "bm_unopened", "half"),
                            radio(_("Full bookmark"), "bm_unopened", "show"),
                        },
                    },
                },
            },
        },
    }
end

return M
