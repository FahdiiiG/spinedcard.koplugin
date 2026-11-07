--[[
Book card - the card itself.

  CardView.build(card, opts)   full-screen widget showing `card`
  CardView.Popup               tap-to-close wrapper, used by "Preview"

Layout (portrait; landscape uses the same scheme):

    +---------------------------------------+
    |                              [bat] 87%|   battery (optional), above
    | +-------------+                   ...%|   both the cover and the
    | |             |             12h 51 min |   statistics column
    | |    cover    |            Reading Time|   Progress, top of the
    | |  (framed,   |                  ...   |   statistics column,
    | |   rounded)  |             Sep 13     |   right-aligned; both the
    | +-------------+          Finished Date |   cover and the last stat
    | Title                                  |   row start/end level with
    | Author                                 |   each other
    | Series / #1                            |
    | flame 9 day streak . 3 week streak  moon Night Reader
    +---------------------------------------+

Everything is sized from the actual screen. The cover takes all the height
the text below it leaves, and the width up to the statistics column.

Colours: the card follows KOReader's night mode (black background, white
text) unless the "Background" setting forces light or dark. KOReader's night
mode inverts the whole panel, so a card painted "normally" already comes out
dark there; `flip` below is true only when the painted colours have to be
reversed to get the requested look.
]]--

local deps = ...
local Locale    = deps.Locale
local Prefs     = deps.Prefs
local PluginDir = deps.PluginUtil.dir
local Cache     = deps.Cache
local Colors    = deps.Colors
local Fonts     = deps.Fonts
local Wallpaper = deps.Wallpaper
local RealBook  = deps.RealBook

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local FrameContainer = require("ui/widget/container/framecontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local DoubleSpinWidget = require("ui/widget/doublespinwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local SortWidget = require("ui/widget/sortwidget")
local Size = require("ui/size")
local SpinWidget = require("ui/widget/spinwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local Screen = Device.screen

local StatCell      = deps.PluginUtil.load("widgets/statcell.lua")
local CoverFrame    = deps.PluginUtil.load("widgets/coverframe.lua")
local SvgIcon       = deps.PluginUtil.load("widgets/svgicon.lua")

local _  = Locale._
local N_ = Locale.N_

local M = {}

-- Settings.
M.SETTING_BATTERY     = "bookcard_show_battery"          -- default on
M.SETTING_STREAK      = "bookcard_show_streak"           -- default on
M.SETTING_READER_TYPE = "bookcard_show_reader_type"      -- default on
M.SETTING_PROGRESS_STRIP = "bookcard_show_progress_strip"  -- default on
M.SETTING_RATING      = "bookcard_show_rating"           -- default on
M.SETTING_REAL_BOOK   = "bookcard_real_book"             -- default on: cover drawn like a physical book (lib/realbook.lua)
M.SETTING_SPINE_TEXT  = "bookcard_spine_text"            -- "title" (default) | "author_title" | "title_author" | "filename"
M.SETTING_ROUNDED     = "bookcard_rounded_corners"       -- default on
M.SETTING_THEME       = "bookcard_theme"                 -- "auto" (default) | "light" | "dark"
M.SETTING_GAP         = "bookcard_cover_stats_gap"       -- "small" (default) | "large"
M.SETTING_COVER_SHADOW = "bookcard_cover_shadow"          -- default on
M.SETTING_COVER_BORDER = "bookcard_cover_border"          -- default on - thin frame round the cover
M.SETTING_DARK_BORDER  = "bookcard_cover_dark_border"     -- default on - near-black frame when the
                                                          -- card is dark (as in Reading insights)
M.SETTING_HIGHLIGHTS   = "bookcard_show_highlights"      -- default OFF
M.SETTING_QUOTE        = "bookcard_show_quote"           -- default OFF - a
                                                          -- random highlighted
                                                          -- quote under
                                                          -- title/author/series
M.SETTING_QUOTE_LINES  = "bookcard_quote_max_lines"      -- 1..10, default 2 - maximum
                                                          -- number of lines the quote
                                                          -- may take (it only uses as
                                                          -- many as the text needs)
M.QUOTE_LINES_DEFAULT  = 2
M.QUOTE_LINES_OPTIONS  = { 1, 2, 3, 4, 5 }      -- quick picks; "Custom" accepts 1..QUOTE_LINES_MAX
M.QUOTE_LINES_MAX      = 10

function M.getQuoteMaxLines()
    local n = tonumber(Prefs.read(M.SETTING_QUOTE_LINES, M.QUOTE_LINES_DEFAULT))
    n = n and math.floor(n) or M.QUOTE_LINES_DEFAULT
    if n < 1 then n = M.QUOTE_LINES_DEFAULT end
    if n > M.QUOTE_LINES_MAX then n = M.QUOTE_LINES_MAX end   -- 15, 17... -> 10
    return n
end

M.SETTING_GRID_COLUMNS = "bookcard_grid_columns"         -- 1..5, default 2 - how many statistics sit
                                                          -- side by side in the "centered" (vertical)
                                                          -- layout's grid
M.GRID_COLUMNS_DEFAULT = 2
M.GRID_COLUMNS_OPTIONS = { 1, 2, 3, 4, 5 }

function M.getGridColumns()
    local n = tonumber(Prefs.read(M.SETTING_GRID_COLUMNS, M.GRID_COLUMNS_DEFAULT))
    n = n and math.floor(n) or M.GRID_COLUMNS_DEFAULT
    if n < 1 or n > 5 then n = M.GRID_COLUMNS_DEFAULT end
    return n
end

M.SETTING_ORIENTATION  = "bookcard_orientation"          -- "default" (current behaviour) | "portrait" | "landscape"
M.SETTING_LAYOUT       = "bookcard_layout"               -- "side" (default: cover beside the
                                                          -- statistics column) | "centered" (cover
                                                          -- centered on its own, title/author/series/
                                                          -- quote below it, statistics in a 2-column
                                                          -- grid underneath that)
M.SETTING_BACKDROP_GROUPING = "bookcard_backdrop_grouping" -- "individual" | "grouped" (default) - only
                                                          -- matters with a wallpaper + text background
                                                          -- opacity > 0; see placeText()/flushGroup() below

-- Top/bottom/side padding (unscaled units, same convention as S() below -
-- see pad_top/pad_bottom/pad_x in M.build). User-configurable so content
-- can be pulled in from curved/notched screen edges where the corners
-- aren't fully visible; the defaults reproduce the previous fixed layout
-- (side padding, and top padding, were already 28/22 - only the bottom
-- default changes here, from 26 to 22, to match).
M.SETTING_MARGIN_TOP    = "bookcard_margin_top"
M.SETTING_MARGIN_BOTTOM = "bookcard_margin_bottom"
M.SETTING_MARGIN_SIDE   = "bookcard_margin_side"
M.DEFAULT_MARGIN_TOP    = 22
M.DEFAULT_MARGIN_BOTTOM = 22
M.DEFAULT_MARGIN_SIDE   = 28
M.MARGIN_MIN = 0
M.MARGIN_MAX = 160

-- Individual statistics-column rows, in the order they are drawn (all
-- default on, except SETTING_HIGHLIGHTS above, which stays off by default).
M.SETTING_STAT_PROGRESS      = "bookcard_stat_progress"
M.SETTING_STAT_PAGES         = "bookcard_stat_pages"
M.SETTING_STAT_READING_TIME  = "bookcard_stat_reading_time"
M.SETTING_STAT_TIME_LEFT     = "bookcard_stat_time_left"
M.SETTING_STAT_DAILY_AVG     = "bookcard_stat_daily_avg"
M.SETTING_STAT_DAILY_AVG_PAGES = "bookcard_stat_daily_avg_pages"  -- default OFF
M.SETTING_STAT_PAGES_PER_MIN = "bookcard_stat_pages_per_min"
M.SETTING_STAT_STARTED       = "bookcard_stat_started"
M.SETTING_STAT_FINISH        = "bookcard_stat_finish"
M.SETTING_STAT_TODAY_TIME    = "bookcard_stat_today_time"       -- default OFF
M.SETTING_STAT_ALL_BOOKS_TIME = "bookcard_stat_all_books_time"  -- default OFF
M.SETTING_STAT_CHAPTER_PAGES_LEFT = "bookcard_stat_chapter_pages_left"  -- default OFF
M.SETTING_STAT_CHAPTER_TIME_LEFT  = "bookcard_stat_chapter_time_left"  -- default OFF

M.SETTING_STAT_PAGES_TODAY     = "bookcard_stat_pages_today"      -- default OFF
M.SETTING_STAT_ALL_BOOKS_PAGES = "bookcard_stat_all_books_pages"  -- default OFF
M.SETTING_STAT_DAILY_GOAL      = "bookcard_stat_daily_goal"       -- default OFF
M.SETTING_STAT_WEEKLY_GOAL     = "bookcard_stat_weekly_goal"      -- default OFF

-- Daily / weekly reading-time goals, in minutes. These are deliberately the
-- very same G_reader_settings keys (and defaults) Reading Insights uses, so
-- changing a goal in either plugin changes it in both. When Reading
-- Insights isn't installed nothing is missing: the key is simply created
-- the first time a goal is set here (until then the default applies).
M.SETTING_DAILY_GOAL_MIN  = "reading_insights_daily_goal_min"
M.SETTING_WEEKLY_GOAL_MIN = "reading_insights_weekly_goal_min"
M.DEFAULT_DAILY_GOAL_MIN  = 30
M.DEFAULT_WEEKLY_GOAL_MIN = 300

local function readGoalMinutes(key, default)
    local v = tonumber(Prefs.read(key, default))
    if not v or v < 1 then return default end
    return math.floor(v)
end

function M.getDailyGoalMinutes()
    return readGoalMinutes(M.SETTING_DAILY_GOAL_MIN, M.DEFAULT_DAILY_GOAL_MIN)
end

function M.getWeeklyGoalMinutes()
    return readGoalMinutes(M.SETTING_WEEKLY_GOAL_MIN, M.DEFAULT_WEEKLY_GOAL_MIN)
end

-- Statistics rows that carry a thin separator line below them: a table
-- { [row id] = true }, set by long-pressing a row in the "Reorder" list.
-- The line's color is Colors role "separator" (default #888888).
M.SETTING_STAT_SEPARATORS = "bookcard_stat_separators"

-- The reader's chosen order for the statistics rows above (a list of the
-- `id`s used in STAT_DEFS below). Unset until the reader opens "Reorder"
-- for the first time; see M.getStatOrder().
M.SETTING_STAT_ORDER = "bookcard_stat_order"

local DASH = "\u{2013}"  -- en dash: "no value"

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------
local function S(n)
    return Screen:scaleBySize(n)
end

-- Font sizes are given in KOReader's unscaled units (Font:getFace scales).
local function face(name, size)
    return Font:getFace(name, math.max(6, math.floor(size)))
end

-- Painted colours for the requested look (see the header comment).
local function palette()
    local mode = Prefs.read(M.SETTING_THEME, "auto")
    local night = Screen.night_mode == true
    local dark = (mode == "dark") or (mode == "auto" and night)
    local flip = dark ~= night
    return {
        flip = flip,
        dark = dark,
        bg = flip and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        fg = flip and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
    }
end

local function icon(name, size, pal)
    local path = PluginDir .. "icons/" .. name .. ".svg"
    local ok, widget = pcall(function()
        return SvgIcon:new{ file = path, size = size, inverted = pal.flip }
    end)
    if ok then return widget end
    logger.warn("BookCard: icon failed:", name, widget)
    return nil
end

local READER_TYPES = {
    night     = { icon = "moon",    label = "Night Reader" },
    morning   = { icon = "sunrise", label = "Morning Reader" },
    afternoon = { icon = "sun",     label = "Afternoon Reader" },
    evening   = { icon = "sunset",  label = "Evening Reader" },
}

local function text(txt, text_face, color, max_width)
    return TextWidget:new{ text = txt, face = text_face, fgcolor = color, max_width = max_width }
end

-- Icon + text side by side, vertically centred on each other. The icon
-- itself always follows the theme (pal, for its night-mode inversion) -
-- only the text takes a custom `color` from the Colors menu.
local function iconLabel(icon_name, txt, text_face, icon_size, pal, color)
    local group = HorizontalGroup:new{ align = "center" }
    local ic = icon_name and icon(icon_name, icon_size, pal)
    if ic then
        table.insert(group, ic)
        table.insert(group, HorizontalSpan:new{ width = math.floor(icon_size * 0.35) })
    end
    table.insert(group, text(txt, text_face, color))
    return group
end

-- ---------------------------------------------------------------------------
-- Cover (framed, optionally rounded)
-- ---------------------------------------------------------------------------
-- Frame colour (taken over from Reading insights). On a dark card the frame
-- is near-black (~98% black on screen, like Bookshelf) instead of white, so a
-- dark cover keeps a faint frame rather than a bright one. In night mode the
-- framebuffer is inverted at refresh, so 0xFA is painted to be shown as 0x05;
-- when the card is only forced dark (no night mode) 0x05 is painted directly.
local function coverBorderColor(pal)
    if pal.dark and Prefs.readBool(M.SETTING_DARK_BORDER, true) then
        return Screen.night_mode and Blitbuffer.Color8(0xFA) or Blitbuffer.Color8(0x05)
    end
    return pal.fg
end

-- `max_w` x `max_h` is the box for the OUTER size (frame included).
-- Returns the widget and its outer width and height.
function M.getSpineTextMode()
    local m = Prefs.read(M.SETTING_SPINE_TEXT, "title")
    if m ~= "author_title" and m ~= "title_author" and m ~= "filename" then m = "title" end
    return m
end

-- Text running up the spine of the "real book" cover.
function M.spineText(card)
    local mode = M.getSpineTextMode()
    local title = (card.title and card.title ~= "") and card.title or nil
    local author = (card.authors and card.authors ~= "") and card.authors or nil
    local fname = card.file and card.file:match("([^/]+)$")
    fname = fname and fname:gsub("%.[^%.]+$", "") or nil
    if mode == "filename" then return fname or title or "" end
    if mode == "author_title" and author and title then return author .. " \u{2013} " .. title end
    if mode == "title_author" and author and title then return title .. " \u{2013} " .. author end
    return title or author or fname or ""
end

local function buildCover(card, max_w, max_h, pal, shadow_offset, restore)
    -- Frame thickness as in Reading insights: a 1 px line (or none).
    local border = Prefs.readBool(M.SETTING_COVER_BORDER, true) and 1 or 0
    local radius = Prefs.readBool(M.SETTING_ROUNDED, true) and S(4) or 0
    local box_w, box_h = max_w - 2 * border, max_h - 2 * border
    local soff = shadow_offset or 0

    local function framed(inner, inner_w, inner_h)
        local outer_w, outer_h = inner_w + 2 * border, inner_h + 2 * border
        return CoverFrame:new{
            inner  = inner,
            width  = outer_w, height = outer_h,
            border = border,  radius = radius,
            bg     = pal.bg,  fg     = coverBorderColor(pal),
            -- shadow awareness: BR corner restores shadow grey instead of bg
            shadow_color  = soff > 0 and Colors.getColor("shadow", CoverFrame.SHADOW_GRAY) or nil,
            shadow_offset = soff,
            -- over a wallpaper, cut corners reveal the picture instead of a
            -- flat bg square (see Wallpaper.restore)
            restore = restore,
        }, outer_w, outer_h
    end

    if card.has_cover ~= false and Cache.hasCover() then
        local ok, widget, w, h = pcall(function()
            local RenderImage = require("ui/renderimage")
            local bb = RenderImage:renderImageFile(Cache.coverPath(), false, nil, nil)
            if not bb then error("cover could not be decoded") end
            -- "Real book" look: spine with the book's name, page lines on top.
            if RealBook and Prefs.readBool(M.SETTING_REAL_BOOK, true) then
                local rb, rw, rh = RealBook.render(bb, max_w, max_h, {
                    name = M.spineText(card), pages = card.total_pages, bg = pal.bg,
                    progress = card.percent and (card.percent / 100) or nil,
                    finished = (card.status == "complete") or (card.finished == true),
                    night = Screen.night_mode == true, flip = pal.flip, dark = pal.dark,
                })
                if rb then
                    bb:free()
                    local rimg = ImageWidget:new{
                        image = rb, image_disposable = true,
                        width = rw, height = rh, scale_factor = 0,
                        -- "Follow night mode" on: the bitmap was painted for the
                        -- panel's own night inversion (cover pre-inverted), so the
                        -- widget must not invert it again; off: it does.
                        original_in_nightmode = not RealBook.followsNightMode(),
                    }
                    rimg:getSize()
                    return rimg, rw, rh
                end
            end
            local scale = math.min(box_w / bb:getWidth(), box_h / bb:getHeight())
            local iw = math.max(1, math.floor(bb:getWidth() * scale))
            local ih = math.max(1, math.floor(bb:getHeight() * scale))
            local img = ImageWidget:new{
                image = bb,
                image_disposable = true,
                width = iw,
                height = ih,
                scale_factor = 0,
            }
            img:getSize()
            return framed(img, iw, ih)
        end)
        if ok then return widget, w, h end
        logger.warn("BookCard: cover failed:", widget)
    end

    -- No cover: a plain 2:3 placeholder carrying the title.
    local ih = box_h
    local iw = math.floor(ih * 2 / 3)
    if iw > box_w then
        iw = box_w
        ih = math.floor(iw * 3 / 2)
    end
    local inner = FrameContainer:new{
        bordersize = 0, padding = 0, margin = 0,
        background = pal.bg,
        width = iw, height = ih,
        CenterContainer:new{
            dimen = Geom:new{ w = iw, h = ih },
            TextBoxWidget:new{
                text = card.title or "",
                face = face("NotoSans-Bold.ttf", 18),
                width = math.max(10, iw - S(24)),
                alignment = "center",
                fgcolor = pal.fg,
                bgcolor = pal.bg,
            },
        },
    }
    return framed(inner, iw, ih)
end

-- ---------------------------------------------------------------------------
-- The statistics column
--
-- Each entry is one possible row: `setting`/`default` is its on/off toggle
-- (Card elements > Statistics), `label()` names it in that menu, and
-- `build(card, ctx)` returns the {value, label} row to draw, or nil to skip
-- it (e.g. "Pages" needs current_page/total_pages to be known). The table's
-- own order is only the *default* order (and where a future row gets
-- appended); the order actually drawn is M.getStatOrder(), which the reader
-- can change from the "Reorder" entry at the top of that same menu.
-- ---------------------------------------------------------------------------
local STAT_DEFS = {
    {
        id = "progress", setting = M.SETTING_STAT_PROGRESS, default = true,
        label = function() return _("Progress") end,
        build = function(card, ctx)
            return { ctx.percent and (tostring(ctx.percent) .. "%") or DASH, _("Progress"), bar = ctx.percent }
        end,
    },
    {
        id = "pages", setting = M.SETTING_STAT_PAGES, default = true,
        label = function() return _("Pages") end,
        build = function(card, ctx)
            if not (card.current_page and card.total_pages) then return nil end
            return { string.format("%d / %d", card.current_page, card.total_pages), _("Pages") }
        end,
    },
    {
        id = "reading_time", setting = M.SETTING_STAT_READING_TIME, default = true,
        label = function() return _("Reading Time") end,
        build = function(card, ctx)
            return { ctx.dur(card.total_time), _("Reading Time") }
        end,
    },
    {
        id = "time_left", setting = M.SETTING_STAT_TIME_LEFT, default = true,
        label = function() return _("Time Left") end,
        build = function(card, ctx)
            return { card.finished and DASH or ctx.dur(card.time_left_secs), _("Time Left") }
        end,
    },
    {
        -- Off by default: pages left in the CURRENT chapter (not the whole
        -- book - see "pages"/"time_left" above for that). Needs a live
        -- document (ui.toc:getChapterPagesLeft) - see bookdata.lua's
        -- collectLive; nil (shown as DASH) when the card was rebuilt from
        -- the sidecar/statistics DB with no book open.
        id = "chapter_pages_left", setting = M.SETTING_STAT_CHAPTER_PAGES_LEFT, default = false,
        label = function() return _("Ch. Pages Left") end,
        build = function(card, ctx)
            local left = card.chapter_pages_left
            local left_txt = left and tostring(math.floor(left + 0.5)) or DASH
            return { left_txt, _("Ch. Pages Left") }
        end,
    },
    {
        -- Off by default: time left in the CURRENT chapter, same
        -- pages-left * avg_time formula as the whole-book "time_left" row.
        -- Same live-document caveat as chapter_pages_left above.
        id = "chapter_time_left", setting = M.SETTING_STAT_CHAPTER_TIME_LEFT, default = false,
        label = function() return _("Ch. Time Left") end,
        build = function(card, ctx)
            return { ctx.dur(card.chapter_time_left_secs), _("Ch. Time Left") }
        end,
    },
    {
        id = "daily_avg", setting = M.SETTING_STAT_DAILY_AVG, default = true,
        label = function() return _("Daily Avg") end,
        build = function(card, ctx)
            return { ctx.dur(card.daily_avg_secs), _("Daily Avg") }
        end,
    },
    {
        -- Same "Daily Avg" row, but in pages instead of time - off by
        -- default (same reasoning as Highlights: a second row for the same
        -- idea should be something the reader opts into, not something
        -- added for them).
        id = "daily_avg_pages", setting = M.SETTING_STAT_DAILY_AVG_PAGES, default = false,
        label = function() return _("Daily Avg (pages)") end,
        build = function(card, ctx)
            local pages_txt = DASH
            if card.daily_avg_pages then
                local n = math.floor(card.daily_avg_pages + 0.5)
                pages_txt = string.format(N_("%d page", "%d pages", n), n)
            end
            return { pages_txt, _("Daily Avg") }
        end,
    },
    {
        id = "pages_per_min", setting = M.SETTING_STAT_PAGES_PER_MIN, default = true,
        label = function() return _("Pages/Min") end,
        build = function(card, ctx)
            local ppm = card.pages_per_min
            local ppm_text = DASH
            if ppm then ppm_text = Locale.formatNumber(ppm, ppm >= 1 and 1 or 2) end
            return { ppm_text, _("Pages/Min") }
        end,
    },
    {
        -- "Started": 1 day ago reads as "Yesterday", 2+ as "N days ago".
        id = "started", setting = M.SETTING_STAT_STARTED, default = true,
        label = function() return _("Started") end,
        build = function(card, ctx)
            -- Label "Started", value = the date, e.g. "Sat, 07 Nov, 2026"
            -- (same format as the date at the top of the card).
            local started = card.started_ts and os.date("%a, %d %b, %Y", card.started_ts) or DASH
            return { started, _("Started") }
        end,
    },
    {
        id = "finish", setting = M.SETTING_STAT_FINISH, default = true,
        label = function() return _("Est. Finish") end,
        build = function(card, ctx)
            if card.finished then
                return { Locale.shortDate(card.finished_ts) or DASH, _("Finished Date") }
            end
            return { Locale.shortDate(card.est_finish_ts) or DASH, _("Est. Finish") }
        end,
    },
    {
        -- Off by default: how many highlights this book has.
        id = "highlights", setting = M.SETTING_HIGHLIGHTS, default = false,
        label = function() return _("Highlights") end,
        build = function(card, ctx)
            return { tostring(card.highlights_count or 0), _("Highlights") }
        end,
    },
    {
        -- Off by default: how much of THIS book was read today. The card
        -- caption is just "Read Today" (see all_books_time below); the
        -- longer "(This Book)" form is only used to tell the two rows
        -- apart in the Statistics settings menu.
        id = "today_time", setting = M.SETTING_STAT_TODAY_TIME, default = false,
        menu_label = function() return _("Read Today (This Book)") end,
        label = function() return _("Read Today") end,
        build = function(card, ctx)
            return { ctx.dur(card.today_time), _("Read Today") }
        end,
    },
    {
        -- Off by default: how much was read today across every book, not
        -- just this one. Displayed on the card as "Read Today" too (see
        -- today_time above); "(All Books)" only distinguishes it in the
        -- Statistics settings menu.
        id = "all_books_time", setting = M.SETTING_STAT_ALL_BOOKS_TIME, default = false,
        menu_label = function() return _("Read Today (All Books)") end,
        label = function() return _("Read Today") end,
        build = function(card, ctx)
            return { ctx.dur(card.all_books_time), _("Read Today") }
        end,
    },
    {
        -- Off by default: pages read today in THIS book (distinct pages).
        -- Same caption trick as the two "Read Today" rows above.
        id = "pages_today", setting = M.SETTING_STAT_PAGES_TODAY, default = false,
        menu_label = function() return _("Pages Read Today (This Book)") end,
        label = function() return _("Pages Read Today") end,
        build = function(card, ctx)
            local n = card.pages_today
            local txt = DASH
            if n then txt = string.format(N_("%d page", "%d pages", n), n) end
            return { txt, _("Pages Read Today") }
        end,
    },
    {
        -- Off by default: pages read today across every book.
        id = "all_books_pages", setting = M.SETTING_STAT_ALL_BOOKS_PAGES, default = false,
        menu_label = function() return _("Pages Read Today (All Books)") end,
        label = function() return _("Pages Read Today") end,
        build = function(card, ctx)
            local n = card.all_books_pages
            local txt = DASH
            if n then txt = string.format(N_("%d page", "%d pages", n), n) end
            return { txt, _("Pages Read Today") }
        end,
    },
    {
        -- Off by default: time read today (all books) against the daily
        -- goal, e.g. "12 min / 30 min", with a check mark once it is met.
        -- The goal itself is set in Card elements > Statistics (shared with
        -- Reading Insights, see M.SETTING_DAILY_GOAL_MIN).
        id = "daily_goal", setting = M.SETTING_STAT_DAILY_GOAL, default = false,
        label = function() return _("Daily Goal") end,
        build = function(card, ctx)
            return { ctx.goal(card.all_books_time, M.getDailyGoalMinutes()), _("Daily Goal") }
        end,
    },
    {
        -- Off by default: time read this calendar week (all books) against
        -- the weekly goal. The week starts on Reading Insights' week-start
        -- day (Monday unless it is set to Sunday there).
        id = "weekly_goal", setting = M.SETTING_STAT_WEEKLY_GOAL, default = false,
        label = function() return _("Weekly Goal") end,
        build = function(card, ctx)
            return { ctx.goal(card.week_time, M.getWeeklyGoalMinutes()), _("Weekly Goal") }
        end,
    },
}

local STAT_DEFS_BY_ID, DEFAULT_STAT_ORDER = {}, {}
for i = 1, #STAT_DEFS do
    STAT_DEFS_BY_ID[STAT_DEFS[i].id] = STAT_DEFS[i]
    DEFAULT_STAT_ORDER[i] = STAT_DEFS[i].id
end

--- The reader's chosen row order: a list of the `id`s above. Falls back to
--- DEFAULT_STAT_ORDER, and any id missing from a saved order (a new row
--- added by a later version of the plugin, or a stale/corrupt setting) is
--- appended at the end in its default position, so it isn't silently lost
--- and every id is always present exactly once.
function M.getStatOrder()
    local saved = Prefs.read(M.SETTING_STAT_ORDER, nil)
    local order, seen = {}, {}
    if type(saved) == "table" then
        for i = 1, #saved do
            local id = saved[i]
            if STAT_DEFS_BY_ID[id] and not seen[id] then
                order[#order + 1] = id
                seen[id] = true
            end
        end
    end
    for i = 1, #DEFAULT_STAT_ORDER do
        local id = DEFAULT_STAT_ORDER[i]
        if not seen[id] then
            order[#order + 1] = id
            seen[id] = true
        end
    end
    return order
end

--- Persists a new row order (see M.getStatOrder). Unknown ids and repeats
--- are dropped, matching the guards in the getter above.
function M.setStatOrder(order)
    local clean, seen = {}, {}
    for i = 1, #order do
        local id = order[i]
        if STAT_DEFS_BY_ID[id] and not seen[id] then
            clean[#clean + 1] = id
            seen[id] = true
        end
    end
    Prefs.save(M.SETTING_STAT_ORDER, clean)
end

--- Which statistics rows have a separator line below them: a set
--- { [id] = true }. Unknown ids / non-true values in the stored table are
--- ignored.
function M.getSeparators()
    local saved = Prefs.read(M.SETTING_STAT_SEPARATORS, nil)
    local set = {}
    if type(saved) == "table" then
        for id, on in pairs(saved) do
            if STAT_DEFS_BY_ID[id] and on == true then set[id] = true end
        end
    end
    return set
end

function M.hasSeparator(id)
    return M.getSeparators()[id] == true
end

function M.setSeparator(id, on)
    local set = M.getSeparators()
    set[id] = on and true or nil
    Prefs.save(M.SETTING_STAT_SEPARATORS, set)
end

-- Compact "12 min", "5h", "1h 30 min" (reuses the card's own duration
-- strings, but drops the "0 min" in "5h 0 min").
local function compactDuration(secs)
    local total_min = math.floor((tonumber(secs) or 0) / 60 + 0.5)
    local h, m = math.floor(total_min / 60), total_min % 60
    if h == 0 then return string.format(_("%d min"), m) end
    if m == 0 then return string.format(_("%dh"), h) end
    return string.format(_("%dh %d min"), h, m)
end

local function statRows(card)
    local ctx = {
        percent = card.percent,
        dur = function(secs) return Locale.formatDuration(secs) or DASH end,
        -- "<done> / <goal>" (+ a check mark once the goal is reached).
        goal = function(done_secs, goal_min)
            local done = tonumber(done_secs) or 0
            local goal = goal_min * 60
            local txt = compactDuration(done) .. " / " .. compactDuration(goal)
            if done >= goal then txt = txt .. " \u{2713}" end
            return txt
        end,
    }
    local rows = {}
    local order = M.getStatOrder()
    local separators = M.getSeparators()
    for i = 1, #order do
        local def = STAT_DEFS_BY_ID[order[i]]
        if Prefs.readBool(def.setting, def.default) then
            local row = def.build(card, ctx)
            if row then
                row.sep = separators[def.id] == true
                rows[#rows + 1] = row
            end
        end
    end
    return rows
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------
function M.build(card, opts)
    opts = opts or {}
    local W, H = Screen:getWidth(), Screen:getHeight()
    local dp = Screen:scaleBySize(100) / 100          -- px per KOReader unit
    local pal = palette()

    -- Wallpaper (optional): a picture behind the whole card, with a
    -- translucent backdrop panel behind each piece of text so it stays
    -- legible over it. Neither exists unless a picture is actually chosen -
    -- with none set, the card looks exactly as it did before this feature.
    Wallpaper.reroll()   -- "Random" mode: pick a fresh picture for this card
    local wallpaper_bg = Wallpaper.isActive()
        and Wallpaper.bg(W, H, Screen.night_mode and true or false)
        or nil
    local text_bg_opacity = Wallpaper.opacity()
    -- "individual": every line/row gets its own backdrop panel, exactly as
    -- before. "grouped" (default): five logical groups - battery, the
    -- statistics column, title+author+series, the streak, and the morning
    -- reader label - each get ONE panel sized to their own combined
    -- bounding box instead. Battery/streak/reader are already a single
    -- widget each, so this only actually changes the stats column and the
    -- title block (see the newGroup()/groupAdd()/flushGroup() helpers and
    -- their two call sites below).
    local backdrop_grouped = Prefs.read(M.SETTING_BACKDROP_GROUPING, "grouped") == "grouped"

    -- User-configurable (see M.SETTING_MARGIN_TOP/BOTTOM/SIDE): raising any
    -- of these pulls the content in from that edge, e.g. to shift it toward
    -- the middle of the screen on devices whose curved glass hides the very
    -- edge of the display.
    local pad_x = S(Prefs.read(M.SETTING_MARGIN_SIDE, M.DEFAULT_MARGIN_SIDE))
    local pad_top = S(Prefs.read(M.SETTING_MARGIN_TOP, M.DEFAULT_MARGIN_TOP))
    local pad_bottom = S(Prefs.read(M.SETTING_MARGIN_BOTTOM, M.DEFAULT_MARGIN_BOTTOM))
    -- Cover <-> statistics gap: user-configurable ("small" is the default).
    local col_gap = Prefs.read(M.SETTING_GAP, "small") == "large" and S(42) or S(22)

    local show_battery = Prefs.readBool(M.SETTING_BATTERY, true) and Device:hasBattery()
    local days = card.streak_days or 0
    local weeks = card.streak_weeks or 0
    local show_streak = Prefs.readBool(M.SETTING_STREAK, true) and (days > 0 or weeks > 0)
    local reader_type = Prefs.readBool(M.SETTING_READER_TYPE, true)
                        and card.hour_bucket and READER_TYPES[card.hour_bucket]

    local items = {}                                  -- OverlapGroup children
    local function place(widget, x, y)
        widget.overlap_offset = { x, y }
        items[#items + 1] = widget
        return widget
    end

    -- The picture, if any, goes in first so it sits behind everything else.
    if wallpaper_bg then place(wallpaper_bg, 0, 0) end

    -- Thin separator lines under statistics rows (long press in the
    -- "Reorder" list). Collected while the rows are laid out and placed
    -- afterwards (placeSeparators), so a backdrop panel can't end up on top
    -- of them. Each entry: { x =, y = (line centre), w = }.
    local sep_color = Colors.getColor("separator", Blitbuffer.COLOR_DARK_GRAY)
    local sep_thickness = math.max(1, S(1))
    local function placeSeparators(lines)
        for _i, l in ipairs(lines) do
            place(LineWidget:new{
                background = sep_color,
                dimen = Geom:new{ w = l.w, h = sep_thickness },
            }, l.x, l.y - math.floor(sep_thickness / 2))
        end
    end

    -- placeText(widget, x, y): like place(), but first drops a translucent
    -- panel (pal.bg tinted at text_bg_opacity) just behind the widget, sized
    -- to its own footprint plus a small margin - only when a wallpaper is
    -- actually showing and the opacity isn't "Off". Over a plain background
    -- this behaves exactly like place().
    local TEXT_BACKDROP_PAD_H, TEXT_BACKDROP_PAD_V = S(6), S(2)
    -- True only when a translucent backdrop panel is actually being drawn
    -- behind text (wallpaper up, opacity above "Off"). When it is, the
    -- panels behind the title block and the statistics column stick out
    -- past the text they wrap by this padding - so the cover, to look
    -- aligned with them, has to start where the PANELS start, not where
    -- the bare text would have. See cover_left/cover_top below.
    local backdrop_active = wallpaper_bg and text_bg_opacity > 0
    local function placeText(widget, x, y)
        if wallpaper_bg and text_bg_opacity > 0 then
            local size = widget:getSize()
            -- widget:getSize().w is the widget's full box width, which for
            -- a plain TextWidget is already its real text width - but for
            -- the (Mask-wrapped) title it is the whole column width
            -- regardless of how short the title is. When the widget can
            -- tell us its real content width (title only), use that
            -- instead, so its panel hugs the text just like every other
            -- row's does.
            local panel_w = (widget.contentWidth and widget:contentWidth()) or size.w
            local panel = Wallpaper.panel(panel_w + 2 * TEXT_BACKDROP_PAD_H, size.h + 2 * TEXT_BACKDROP_PAD_V,
                                          pal.bg, text_bg_opacity, S(3))
            if panel then place(panel, x - TEXT_BACKDROP_PAD_H, y - TEXT_BACKDROP_PAD_V) end
        end
        return place(widget, x, y)
    end

    -- Grouped-mode helpers: newGroup() collects members without placing
    -- them yet (their combined bounding box isn't known until the last one
    -- is added); flushGroup() then drops a single panel behind that box
    -- (same padding/opacity/radius as placeText()'s per-widget one) and
    -- only then places every member on top of it, in the order they were
    -- added. With no wallpaper, or opacity "Off", this is a no-op wrapper
    -- around plain place() - same as placeText() in that case. The panel's
    -- left/right edges normally come from the members' own bounding box
    -- (group.min_x/max_x); flushGroup's optional x_left/x_right let a
    -- caller override just those two - used by the centered layout below
    -- so every panel there (grouped OR one-per-row/line) always spans the
    -- cover's own width, not just however wide the text happens to be.
    local function newGroup()
        return { members = {} }
    end

    local function groupAdd(group, widget, x, y)
        local size = widget:getSize()
        local w = (widget.contentWidth and widget:contentWidth()) or size.w
        group.members[#group.members + 1] = { widget = widget, x = x, y = y }
        local x2, y2 = x + w, y + size.h
        group.min_x = group.min_x and math.min(group.min_x, x) or x
        group.min_y = group.min_y and math.min(group.min_y, y) or y
        group.max_x = group.max_x and math.max(group.max_x, x2) or x2
        group.max_y = group.max_y and math.max(group.max_y, y2) or y2
    end

    local function flushGroup(group, pad_h, pad_v, x_left, x_right)
        if #group.members == 0 then return end
        -- x_left/x_right (the centered layout's calls) override the panel's
        -- min_x/max_x, but pad_h is still added around them same as always -
        -- callers that want the finished panel to land on a specific outer
        -- edge (e.g. the cover's own edge) pass that edge already shrunk
        -- inward by pad_h, so this adds it back and lands exactly there.
        local min_x = x_left or group.min_x
        local max_x = x_right or group.max_x
        if wallpaper_bg and text_bg_opacity > 0 then
            local panel = Wallpaper.panel(max_x - min_x + 2 * pad_h,
                                           group.max_y - group.min_y + 2 * pad_v,
                                           pal.bg, text_bg_opacity, S(3))
            if panel then place(panel, min_x - pad_h, group.min_y - pad_v) end
        end
        for _i, m in ipairs(group.members) do place(m.widget, m.x, m.y) end
    end

    -- Top row: date on the left (e.g. "Sat, 07 Nov, 2026"), battery on the
    -- right as "80% <glyph>" (percentage first, KOReader's own battery glyph
    -- last - same symbol the stock footer/screensaver use). Both share the
    -- "battery" font and colour settings.
    local battery_h = 0
    local top_face = Fonts.getFace("battery", 14)
    local top_color = Colors.getColor("battery", pal.fg)
    local date_text = text(os.date("%a, %d %b, %Y"), top_face, top_color)
    battery_h = date_text:getSize().h
    placeText(date_text, pad_x, pad_top)
    if show_battery then
        local powerd = Device:getPowerDevice()
        local ok, capacity = pcall(function() return powerd:getCapacity() end)
        if ok and capacity then
            local batt_symbol = powerd:getBatterySymbol(
                powerd:isCharged(), powerd:isCharging(), capacity)
            local pct_text = text(capacity .. "% " .. batt_symbol, top_face, top_color)
            local size = pct_text:getSize()
            battery_h = math.max(battery_h, size.h)
            placeText(pct_text, W - pad_x - size.w, pad_top)
        end
    end

    -- Bottom row: streaks (left) and reader type (right) ----------------------
    local bottom_color = Colors.getColor("bottom", pal.fg)
    local bottom_face = Fonts.getFace("bottom", 14)
    local icon_size = S(22)
    local bottom_text_h = TextWidget:new{ text = "Ag", face = bottom_face }:getSize().h
    local line_h = math.max(icon_size, bottom_text_h)

    local reader_row
    if reader_type then
        reader_row = iconLabel(reader_type.icon, _(reader_type.label), bottom_face, icon_size, pal, bottom_color)
    end
    local reader_w = reader_row and reader_row:getSize().w or 0

    local streak_row, bottom_h = nil, 0
    if show_streak then
        local day_txt = days > 0
            and string.format(N_("%d day streak", "%d days streak", days), days) or nil
        local week_txt = weeks > 0
            and string.format(N_("%d week streak", "%d weeks streak", weeks), weeks) or nil
        local room = W - 2 * pad_x - reader_w - (reader_w > 0 and S(20) or 0)
        local joined = day_txt and week_txt and (day_txt .. "  \u{B7}  " .. week_txt) or day_txt or week_txt
        local one_line = iconLabel("flame", joined, bottom_face, icon_size, pal, bottom_color)
        if one_line:getSize().w <= room or not (day_txt and week_txt) then
            streak_row = one_line
            bottom_h = line_h
        else
            -- Too wide for one line: days on the first, weeks below.
            streak_row = VerticalGroup:new{
                align = "left",
                iconLabel("flame", day_txt, bottom_face, icon_size, pal, bottom_color),
                text(week_txt, bottom_face, bottom_color),
            }
            bottom_h = streak_row:getSize().h
        end
    end
    if reader_row then bottom_h = math.max(bottom_h, line_h) end
    local content_bottom = H - pad_bottom - bottom_h - (bottom_h > 0 and S(6) or 0)

    if streak_row then
        placeText(streak_row, pad_x, H - pad_bottom - bottom_h
            + math.floor((bottom_h - streak_row:getSize().h) / 2))
    end
    if reader_row then
        placeText(reader_row, W - pad_x - reader_w, H - pad_bottom - bottom_h
            + math.floor((bottom_h - reader_row:getSize().h) / 2))
    end

    -- Statistics column (right): fonts are sized from the space down to the
    -- bottom row, same as before; the vertical GAP between rows is decided
    -- later, once the cover's real height is known (see below), so the last
    -- row's bottom lines up with the bottom of the cover.
    local stats_top = pad_top + (battery_h > 0 and (battery_h + S(10)) or 0)
    local stats_h_for_fonts = content_bottom - stats_top
    local rows = statRows(card)
    -- Progress strip under the cover (side layout only), two lines (see below).
    -- Independent of the right-hand Progress / Pages stats - those stay in the
    -- column as they are. Turn the strip off under Card elements.
    local strip_on = Prefs.readBool(M.SETTING_PROGRESS_STRIP, true)
        and Prefs.read(M.SETTING_LAYOUT, "side") ~= "centered"
    -- Two-line strip: line 1 = pages read/total (left) for chapter | book,
    -- line 2 = progress bars. Chapter figures fall back to the book's when
    -- there is no chapter TOC data (or no live document).
    local strip_ch_txt, strip_bk_txt, strip_ch_pct
    local strip_bk_pct = card.percent or 0
    if strip_on then
        local function r(x) return math.floor((tonumber(x) or 0) + 0.5) end
        local bk_read, bk_total = card.current_page, card.total_pages
        if bk_read and bk_total then
            strip_bk_txt = string.format("%d/%d (%d)", r(bk_read), r(bk_total), math.max(0, r(bk_total) - r(bk_read)))
        else
            strip_bk_txt = DASH
        end
        local ch_read, ch_total = card.chapter_pages_read, card.chapter_pages_total
        if not (ch_read and ch_total) then ch_read, ch_total = bk_read, bk_total end
        if ch_read and ch_total then
            strip_ch_txt = string.format("%d/%d (%d)", r(ch_read), r(ch_total), math.max(0, r(ch_total) - r(ch_read)))
            strip_ch_pct = ch_total > 0 and math.floor(100 * r(ch_read) / r(ch_total) + 0.5) or 0
        else
            strip_ch_txt = DASH
            strip_ch_pct = card.percent or 0
        end
    end
    local budget = stats_h_for_fonts / math.max(1, #rows) / dp     -- units per row
    local value_size = math.min(22, budget * 0.42)
    local label_size = math.min(13, budget * 0.24)
    local value_face = Fonts.getFace("stat_value", value_size)
    local label_face = Fonts.getFace("stat_label", label_size)
    local stat_value_color = Colors.getColor("stat_value", pal.fg)
    local stat_label_color = Colors.getColor("stat_label", pal.fg)

    -- Strip under the cover: font = the bold stat-value font at 75% size
    -- (change 0.75 to make the text bigger/smaller), bar 10 units tall.
    -- The face is shrunk later, once the cover's width is known, if the
    -- page counts would not fit.
    local strip_size = Fonts.getUnitSize("stat_value")      -- shrinks to fit below
    local strip_face = Fonts.getFaceAt("stat_value", strip_size)
    local strip_bar_h = S(10)
    local strip_line_gap = 0
    local strip_h = 0
    if strip_ch_txt then
        local line_h = math.max(TextWidget:new{ text = "Ag", face = strip_face }:getSize().h, strip_bar_h)
        strip_h = 2 * line_h - math.floor(line_h * 0.2)   -- line 1 trimmed, see strip build
    end

    local right_w = 0
    for _idx, row in ipairs(rows) do
        right_w = math.max(right_w,
            TextWidget:new{ text = row[1], face = value_face }:getSize().w,
            TextWidget:new{ text = row[2], face = label_face }:getSize().w)
    end
    right_w = math.min(right_w + S(2), math.floor((W - 2 * pad_x) * 0.6))

    -- Left column: cover, then title / author / series --------------------------
    local left_w = W - 2 * pad_x - right_w - col_gap

    -- Title: bold, same size as the big stat values (e.g. the reading time).
    -- Author: regular weight (not italic by default), same size as the stat labels (e.g.
    -- "Reading Time"). Series: same size as the stat labels, but bold.
    local title_face = Fonts.getFace("title", value_size)
    local author_face = Fonts.getFace("author", label_size)
    local series_face = Fonts.getFace("series", label_size)
    local title_color = Colors.getColor("title", pal.fg)
    local author_color = Colors.getColor("author", pal.fg)
    local series_color = Colors.getColor("series", pal.fg)

    local title_line_h = math.floor((1 + 0.3) * title_face.size + 0.5)

    -- Quote characters (several common opening/closing pairs) that might
    -- already wrap a highlighted passage straight from the book - dialogue
    -- most often. Stripped before we add our own curly quotes below, so a
    -- highlight like `"Hello," she said.` doesn't come out double-quoted
    -- as `""Hello," she said.""`.
    local QUOTE_PAIRS = {
        { open = "\"",       close = "\"" },
        { open = "\u{201C}", close = "\u{201D}" }, -- “ ”
        { open = "\u{2018}", close = "\u{2019}" }, -- ‘ ’
        { open = "\u{201E}", close = "\u{201C}" }, -- „ “
        { open = "\u{201E}", close = "\"" },       -- „ "
        { open = "\u{00AB}", close = "\u{00BB}" }, -- « »
        { open = "\u{2039}", close = "\u{203A}" }, -- ‹ ›
    }
    local function stripOuterQuotes(s)
        for _, pair in ipairs(QUOTE_PAIRS) do
            local ol, cl = #pair.open, #pair.close
            if #s > ol + cl and s:sub(1, ol) == pair.open and s:sub(-cl) == pair.close then
                return s:sub(ol + 1, -cl - 1)
            end
        end
        return s
    end

    -- Whether one shared "grouped" backdrop panel sits behind the whole
    -- title/author/series/quote block (as opposed to: no backdrop at all,
    -- a transparent one, or separate "individual" per-line panels).
    local grouped_backdrop_showing = backdrop_active and backdrop_grouped

    -- Full width the quote is allowed to use when it's free to run past
    -- the cover: unlike title/author/series (kept aligned to the cover's
    -- own width via max_w below), the quote sits on its own row
    -- underneath the cover+stats band, so nothing stops it from reaching
    -- all the way out to the side margin - EXCEPT when one shared grouped
    -- backdrop panel is showing behind the whole text block, where the
    -- quote has to stay the same width as title/author/series so the
    -- panel's right edge doesn't jog outward just for the quote's line.
    -- No backdrop-padding subtraction here: the BARE text should reach
    -- exactly to W - pad_x, same as the statistics/reader-type rows do -
    -- if a per-line backdrop panel is showing, it's then free to overshoot
    -- the margin by TEXT_BACKDROP_PAD_H on its own, exactly like the
    -- statistics/reader panels already do (see placeText above).
    local quote_full_w = W - 2 * pad_x

    -- Builds the title/author/series/quote stack at a given width. Called
    -- twice below: once at left_w, purely to measure how tall the stack is
    -- (those heights don't actually depend on width - title/quote are
    -- height-capped with an ellipsis, author/series are always a single
    -- line - so this is safe to do before the cover's real on-screen width
    -- is known), and again once that width IS known, to rebuild the stack
    -- narrow enough that it never reaches further right than the cover
    -- does (see cover_reach_w below). The quote block uses quote_full_w
    -- (full margin-to-margin width) instead of max_w, unless a grouped
    -- backdrop is showing, or `clamp_quote` is passed true, in which case
    -- it matches max_w like the rest - the centered layout below always
    -- passes true, since there everything (cover, title, stats grid) shares
    -- the same left/right edges, and the quote running out to the full
    -- screen width would break that alignment.
    --
    -- Returns the block list and the index of the quote block within it
    -- (nil if there is no quote), so callers can single out the (larger)
    -- gap above the quote from the gaps between title/author/series.
    -- Icon + single line of text, shrinking the font (1 unit at a time, down
    -- to 3 - effectively no limit) until icon + text fit in max_w.
    local function fitIconLine(face_name, start_size, icon_name, txt, max_w, color)
        local size = start_size
        local face, ic, gap, tw
        while true do
            face = Fonts.getFaceAt(face_name, size)
            local isz = math.floor(face.size * 1.1)
            ic = icon(icon_name, isz, pal)
            gap = ic and math.floor(isz * 0.35) or 0
            local avail = max_w - (ic and (isz + gap) or 0)
            tw = TextWidget:new{ text = txt, face = face }
            if tw:getSize().w <= avail or size <= 3 then
                tw = text(txt, face, color, math.max(1, avail))
                break
            end
            size = size - 1
        end
        if not ic then return tw end
        local row = HorizontalGroup:new{ align = "center" }
        table.insert(row, ic)
        table.insert(row, HorizontalSpan:new{ width = gap })
        table.insert(row, tw)
        return row
    end

    local function buildTextBlocks(max_w, clamp_quote, full_width, quote_lines)
        local quote_max_w = (grouped_backdrop_showing or clamp_quote) and max_w or quote_full_w
        -- TextBoxWidget (needed here for wrapping across up to 2 lines,
        -- unlike the single-line TextWidget the rest of the card's text
        -- uses) always fills itself with bgcolor and blits the result as a
        -- SOLID block - it has no transparent mode. Over a plain background
        -- that solid fill in pal.bg is exactly right; over a wallpaper it
        -- would paint an opaque box that hides both the picture and the
        -- translucent panel placeText() puts behind it. So with a wallpaper
        -- up, build it in throwaway black-on-white "mask space" instead and
        -- let Wallpaper.mask() recolour just the glyphs, leaving the panel
        -- visible around them.
        local title_w = TextBoxWidget:new{
            text = card.title or "",
            face = title_face,
            width = max_w,
            height = (full_width and 2 or 4) * title_line_h,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            alignment = "left",
            justified = true,
            fgcolor = wallpaper_bg and Blitbuffer.COLOR_BLACK or title_color,
            bgcolor = wallpaper_bg and Blitbuffer.COLOR_WHITE or pal.bg,
        }
        title_w = Wallpaper.mask(wallpaper_bg ~= nil, title_w, title_color)
        local blocks = { title_w }
        if card.authors and card.authors ~= "" then
            -- Forced onto ONE line: the font shrinks until it fits.
            local author_row = fitIconLine("author", Fonts.getUnitSize("author"), "authors", card.authors, max_w, author_color)
            blocks[#blocks + 1] = author_row
        end
        if card.series and card.series ~= "" then
            local line = card.series
            if card.series_index then
                local idx_num = tonumber(card.series_index)
                local idx_txt
                if not idx_num then
                    idx_txt = tostring(card.series_index)
                elseif idx_num == math.floor(idx_num) then
                    idx_txt = string.format("%02d", idx_num)      -- 1    -> 01
                else
                    idx_txt = string.format("%05.2f", idx_num)    -- 0.7  -> 00.70
                end
                line = card.series .. " #" .. idx_txt
            end
            -- Forced onto ONE line: the font shrinks until it fits.
            blocks[#blocks + 1] = fitIconLine("series", Fonts.getUnitSize("series"), "series", line, max_w, series_color)
        end

        -- Highlighted quotes (opt-in: "Card elements > Highlighted quote").
        -- The quote area is exactly `quote_max_lines` lines tall (the layout
        -- reserves that much, no more). It is filled with as many COMPLETE
        -- quotes as fit: candidates are measured at the real width, then
        -- random combinations are tried and the one leaving the fewest empty
        -- lines wins. Only when not even one whole quote fits is a single
        -- quote shown, cut off with "..." on its last line. Several quotes
        -- never end in "...".
        local quote_idx = nil
        local quote_max_lines = quote_lines or M.getQuoteMaxLines()   -- 0 = leave the quote out
        if Prefs.readBool(M.SETTING_QUOTE, false) and quote_max_lines > 0 then
            local pool = {}      -- { text = "...", chap = "Name" | nil, ord = position in the book }
            -- What follows "Chapter:" on the chapter line. A real chapter name is
            -- shown as it is; a bare "Chapter 5" becomes just "5" (so the line
            -- reads "Chapter: 5", not "Chapter: Chapter 5"). Older cached cards
            -- may still hold "Chapter 07: Name" - that becomes "Name".
            local function chapterDisplayName(c)
                local n = c:gsub("^Chapter%s+%d+%s*[:%.%-]?%s*", "")
                if n == "" then n = c end
                n = n:gsub("^[Cc]hapter%s+", "")
                return n ~= "" and n or c
            end
            local src = type(card.quote_texts) == "table" and card.quote_texts or { card.quote_text }
            local chaps = type(card.quote_texts) == "table" and card.quote_chapters or nil
            local orders = type(card.quote_texts) == "table" and card.quote_orders or nil
            for i, t in ipairs(src) do
                if type(t) == "string" and t:match("%S") then
                    local c = chaps and chaps[i]
                    pool[#pool + 1] = {
                        text = "\u{201C}" .. stripOuterQuotes((t:gsub("%s+", " "))) .. "\u{201D}",
                        chap = (quote_max_lines >= 2 and type(c) == "string" and c ~= "")
                            and chapterDisplayName(c) or nil,   -- no room for it at 1 line
                        ord = tonumber(orders and orders[i]) or i,
                    }
                end
            end
            if #pool > 0 then
                local quote_face = Fonts.getFace("quote", label_size)
                local quote_color = Colors.getColor("quote", author_color)
                local quote_line_h = math.floor((1 + 0.3) * quote_face.size + 0.5)
                local quote_bar_w = S(2)
                local quote_gap_w = S(6)
                local text_w = quote_max_w - quote_bar_w - quote_gap_w
                local function newQuoteBox(txt, n_lines)
                    return TextBoxWidget:new{
                        text = txt,
                        face = quote_face,
                        width = text_w,
                        height = n_lines and (n_lines * quote_line_h) or nil,
                        height_adjust = n_lines and true or nil,
                        height_overflow_show_ellipsis = true,
                        alignment = "left",
                        justified = true,
                        fgcolor = wallpaper_bg and Blitbuffer.COLOR_BLACK or quote_color,
                        bgcolor = wallpaper_bg and Blitbuffer.COLOR_WHITE or pal.bg,
                    }
                end
                -- One quote = one "unit": the quote text with its chapter line
                -- right underneath, both beside ONE left bar. Units are stacked
                -- with a visible gap between them. All heights are measured in
                -- pixels: the quote box gives back the blank space under its last
                -- line (so the chapter line sits close to its quote), and the gap
                -- after the chapter line is what separates it from the next one.
                local qtrim = math.floor(quote_line_h * 0.2)
                local unit_gap = S(10)
                local area_h = quote_max_lines * quote_line_h
                local function newChapterLine(name)
                    local label = "Chapter: " .. name
                    local csize = Fonts.getUnitSize("quote")
                    local ctext
                    repeat
                        ctext = TextWidget:new{
                            text = label,
                            face = Fonts.getFaceByName("NotoSans-Italic.ttf", csize),
                            fgcolor = quote_color,
                        }
                        csize = csize - 1
                    until ctext:getSize().w <= text_w or csize < 6
                    -- A TextWidget clips what sticks out below its own box, which
                    -- cut the tail off the italic "p" of "Chapter". Same text, with
                    -- a taller box (the baseline stays where it was).
                    local face_used = ctext.face
                    ctext = TextWidget:new{
                        text = label,
                        face = face_used,
                        fgcolor = quote_color,
                        forced_height = ctext:getSize().h + S(3),
                    }
                    return VerticalGroup:new{
                        align = "left",
                        ctext,
                        LineWidget:new{
                            background = quote_color,
                            dimen = Geom:new{ w = math.min(ctext:getSize().w, text_w), h = math.max(1, S(1)) },
                        },
                    }
                end
                for _i, q in ipairs(pool) do
                    local w = newQuoteBox(q.text, nil)
                    q.lines = math.max(1, math.floor(w:getSize().h / quote_line_h + 0.5))
                    pcall(function() w:free() end)
                    q.chap_w = q.chap and newChapterLine(q.chap) or nil
                    q.trim = q.chap_w and qtrim or 0
                    q.h = q.lines * quote_line_h - q.trim + (q.chap_w and q.chap_w:getSize().h or 0)
                end
                -- Best combination out of a number of random orders: the one
                -- that leaves the least empty room in the quote area.
                local best, best_left = nil, math.huge
                local order = {}
                for i = 1, #pool do order[i] = i end
                for attempt = 1, 40 do
                    if attempt > 1 then
                        for i = #order, 2, -1 do
                            local j = math.random(i)
                            order[i], order[j] = order[j], order[i]
                        end
                    end
                    local used, chosen = 0, {}
                    for _k, idx in ipairs(order) do
                        local add = pool[idx].h + (#chosen > 0 and unit_gap or 0)
                        if used + add <= area_h then
                            chosen[#chosen + 1] = idx
                            used = used + add
                        end
                    end
                    local left = area_h - used
                    if #chosen > 0 and left < best_left then
                        best, best_left = chosen, left
                        if left < quote_line_h * 0.5 then break end
                    end
                end
                local truncated = false
                if not best then best, truncated = { 1 }, true end   -- every quote is too long: cut one
                Prefs.save("bookcard_last_quote", (card.quote_texts and card.quote_texts[1]) or card.quote_text)
                -- Show the chosen quotes in reading order: earlier pages first.
                table.sort(best, function(x, y) return pool[x].ord < pool[y].ord end)
                for k, idx in ipairs(best) do
                    local q = pool[idx]
                    local n = q.lines
                    if truncated then
                        local ch_h = q.chap_w and q.chap_w:getSize().h or 0
                        n = math.max(1, math.floor((area_h - ch_h + q.trim) / quote_line_h))
                    end
                    local quote_widget = newQuoteBox(q.text, n)
                    quote_widget = Wallpaper.mask(wallpaper_bg ~= nil, quote_widget, quote_color)
                    local qbox = quote_widget
                    if q.trim > 0 then
                        qbox = WidgetContainer:new{
                            dimen = Geom:new{ w = text_w, h = quote_widget:getSize().h - q.trim },
                            quote_widget,
                        }
                    end
                    local content = VerticalGroup:new{ align = "left", qbox }
                    if q.chap_w then table.insert(content, q.chap_w) end
                    -- The bar spans the quote AND its chapter line.
                    local row = HorizontalGroup:new{
                        align = "top",
                        LineWidget:new{
                            background = quote_color,
                            dimen = Geom:new{ w = quote_bar_w, h = math.max(1, content:getSize().h) },
                        },
                        HorizontalSpan:new{ width = quote_gap_w },
                        content,
                    }
                    if k < #best then
                        row = VerticalGroup:new{ align = "left", row, VerticalSpan:new{ width = unit_gap } }
                    end
                    blocks[#blocks + 1] = row
                    quote_idx = quote_idx or #blocks
                end
            end
        end
        return blocks, quote_idx
    end

    -- Which arrangement to draw: "side" (default, above) puts the cover
    -- next to a single statistics column. "centered" puts the cover on its
    -- own, centered, with title/author/series/quote directly below it and
    -- the statistics spread beneath that in a 2-column grid instead - see
    -- M.SETTING_LAYOUT ("Appearance" > "Layout").
    local layout_centered = Prefs.read(M.SETTING_LAYOUT, "side") == "centered"

    if layout_centered then
        -- -------------------------------------------------------------------
        -- Centered layout
        -- -------------------------------------------------------------------
        local available_w = W - 2 * pad_x
        local available_h = math.max(S(80), content_bottom - stats_top)

        -- Same three-case gap logic as the side layout above, kept local to
        -- this branch since it needs its own `individual_backdrop_showing`
        -- (the name is scoped to this `if`, so it doesn't clash with the
        -- side layout's copy in the `else` below).
        local individual_backdrop_showing = backdrop_active and not backdrop_grouped
        local header_gap_c, text_block_gap_c
        if individual_backdrop_showing then
            header_gap_c = S(8)
            text_block_gap_c = S(8)
        else
            local header_gap_base = math.floor(S(4) / 2)
            text_block_gap_c = math.max(3 * header_gap_base, 3 * TEXT_BACKDROP_PAD_V + S(4))
            header_gap_c = S(1)
        end
        local function gapBeforeC(i, quote_idx)
            if i <= 1 then return 0 end
            if quote_idx and i > quote_idx then return 0 end    -- quotes stack with no gap
            return (quote_idx and i == quote_idx) and text_block_gap_c or header_gap_c
        end

        -- Text block height doesn't depend on width (see buildTextBlocks),
        -- so measure it once, at the full available width, before the
        -- cover's own final width is known.
        local text_blocks_c, quote_index_c = buildTextBlocks(available_w, true)
        local text_h_c = 0
        for i, block in ipairs(text_blocks_c) do
            text_h_c = text_h_c + block:getSize().h + gapBeforeC(i, quote_index_c)
        end

        -- Statistics grid: N columns (setting, 1..5), as many rows as needed. Each cell is
        -- just "value line + label line" stacked, left-aligned - same
        -- metrics as the single-column layout's rows, without StatCell's
        -- right-alignment.
        local underline_h = math.max(1, S(1))
        local cell_h = TextWidget:new{ text = "Ag", face = value_face }:getSize().h
                     + TextWidget:new{ text = "Ag", face = label_face }:getSize().h
                     + underline_h
        local has_bar = false
        for _i, r in ipairs(rows) do if r.bar then has_bar = true end end
        if has_bar then cell_h = cell_h + StatCell.BAR_GAP() + StatCell.BAR_H() end
        local grid_row_gap = math.max(S(16), col_gap)
        local grid_cols = math.min(M.getGridColumns(), math.max(#rows, 1))
        local grid_rows_n = math.ceil(#rows / grid_cols)
        local grid_h = grid_rows_n > 0 and (grid_rows_n * cell_h + (grid_rows_n - 1) * grid_row_gap) or 0
        local gap1 = col_gap                              -- cover -> text
        local gap2 = grid_rows_n > 0 and col_gap or 0      -- text -> grid

        -- The cover gets whatever height is left once the text and the
        -- statistics grid have taken their share - same "leftover space"
        -- philosophy as the side layout's cover_max_h above.
        local show_cover_shadow_c = Prefs.readBool(M.SETTING_COVER_SHADOW, true)
        local shadow_off_c = show_cover_shadow_c and S(4) or 0
        local cover_max_h_c = math.max(S(120), available_h - text_h_c - grid_h - gap1 - gap2 - shadow_off_c)
        local cover_restore_c = wallpaper_bg and Wallpaper.restore or nil
        local cover_c, cover_w_c, cover_h_c = buildCover(
            card, available_w - shadow_off_c, cover_max_h_c, pal, shadow_off_c, cover_restore_c)

        -- Rebuild the text stack (and, further down, the grid) to the
        -- cover's own real on-screen width - its drop shadow included, when
        -- shown - so everything shares the same left/right edges and the
        -- whole assembly reads as one centered block, even when the cover
        -- itself ends up narrower than the full available width.
        local reach_w = cover_w_c + (show_cover_shadow_c and shadow_off_c or 0)
        local text_max_w_c = reach_w - (backdrop_active and 2 * TEXT_BACKDROP_PAD_H or 0)
        text_blocks_c, quote_index_c = buildTextBlocks(text_max_w_c, true)

        local cover_left_c = pad_x + math.floor((available_w - reach_w) / 2)
        local cover_top_c = stats_top
        -- The text (and stat cells) sit inset from the cover's edge by
        -- TEXT_BACKDROP_PAD_H - the same gap the side layout leaves between
        -- the text and its panel's edge - while the panel itself lands
        -- exactly on the cover's own edge, with no extra padding added on
        -- top of that. So it's the content that shifts inward here, not
        -- the panel that shifts outward (contrast the side layout below,
        -- where cover_left is pulled outward instead; there the panel
        -- already wraps the unmoved text with this same padding, so
        -- shifting the cover out is what lines the two up).
        local text_inset_c = backdrop_active and TEXT_BACKDROP_PAD_H or 0
        local text_left_c = cover_left_c + text_inset_c

        if show_cover_shadow_c then
            local radius = Prefs.readBool(M.SETTING_ROUNDED, true) and S(4) or 0
            local shadow = CoverFrame.Shadow:new{
                width = cover_w_c, height = cover_h_c,
                offset = shadow_off_c, radius = radius,
                bg = pal.bg, restore = cover_restore_c,
                color = Colors.getColor("shadow", CoverFrame.SHADOW_GRAY),
            }
            place(shadow, cover_left_c, cover_top_c)
        end
        place(cover_c, cover_left_c, cover_top_c)

        local y = cover_top_c + cover_h_c + (show_cover_shadow_c and shadow_off_c or 0) + gap1
        -- Backdrop panels in this layout always span the cover's own width
        -- (cover_left_c .. cover_left_c + reach_w), never just however wide
        -- the text/cells happen to be. flushGroup adds TEXT_BACKDROP_PAD_H
        -- back around whatever min_x/max_x it's given (see flushGroup
        -- above), so passing the cover's edges shrunk inward by that same
        -- padding here means the finished, padded panel lands exactly on
        -- the cover's real edges - not the cover's edges plus a further
        -- margin, and not flush against the text either. That holds
        -- whether the reader has "grouped" backdrops on (one panel for the
        -- whole title block, one for the whole grid) or off (one panel per
        -- line / per stat row instead of per member).
        local panel_left = cover_left_c + TEXT_BACKDROP_PAD_H
        local panel_right = cover_left_c + reach_w - TEXT_BACKDROP_PAD_H
        if backdrop_grouped then
            local title_group_c = newGroup()
            for i, block in ipairs(text_blocks_c) do
                if i > 1 then y = y + gapBeforeC(i, quote_index_c) end
                groupAdd(title_group_c, block, text_left_c, y)
                y = y + block:getSize().h
            end
            flushGroup(title_group_c, TEXT_BACKDROP_PAD_H, TEXT_BACKDROP_PAD_V, panel_left, panel_right)
        else
            for i, block in ipairs(text_blocks_c) do
                if i > 1 then y = y + gapBeforeC(i, quote_index_c) end
                local line_group = newGroup()
                groupAdd(line_group, block, text_left_c, y)
                flushGroup(line_group, TEXT_BACKDROP_PAD_H, TEXT_BACKDROP_PAD_V, panel_left, panel_right)
                y = y + block:getSize().h
            end
        end

        if #rows > 0 then
            local grid_top = y + gap2
            local grid_col_gap = grid_cols >= 4 and S(12) or S(24)
            -- Same inset width as the text above (text_max_w_c), so the
            -- grid's columns line up with the text's own left/right
            -- edges instead of reaching all the way to the cover's edge.
            local col_w = math.floor((text_max_w_c - (grid_cols - 1) * grid_col_gap) / grid_cols)
            local function statCellWidget(row)
                local label_w = TextWidget:new{ text = row[2], face = label_face, fgcolor = stat_label_color, max_width = col_w }
                local cell_group = VerticalGroup:new{
                    align = "left",
                    label_w,
                    LineWidget:new{
                        background = stat_label_color,
                        dimen = Geom:new{ w = label_w:getSize().w, h = underline_h },
                    },
                    TextWidget:new{ text = row[1], face = value_face, fgcolor = stat_value_color, max_width = col_w },
                }
                if row.bar then
                    table.insert(cell_group, VerticalSpan:new{ width = StatCell.BAR_GAP() })
                    table.insert(cell_group, StatCell.Bar:new{
                        width = col_w, height = StatCell.BAR_H(),
                        percent = row.bar, color = stat_value_color,
                    })
                end
                return cell_group
            end
            if backdrop_grouped then
                -- One panel behind the whole grid (all rows, all columns).
                local grid_group_c = newGroup()
                for idx, row in ipairs(rows) do
                    local r = math.floor((idx - 1) / grid_cols)
                    local c = (idx - 1) % grid_cols
                    local cx = text_left_c + c * (col_w + grid_col_gap)
                    local cy = grid_top + r * (cell_h + grid_row_gap)
                    groupAdd(grid_group_c, statCellWidget(row), cx, cy)
                end
                flushGroup(grid_group_c, TEXT_BACKDROP_PAD_H, TEXT_BACKDROP_PAD_V, panel_left, panel_right)
            else
                -- One panel per ROW (all columns together, cover-width
                -- wide) - a per-CELL panel would only be half that width,
                -- and two of them side by side would either overlap (if
                -- stretched) or leave a gap in the middle (if not).
                local idx = 1
                for r = 0, grid_rows_n - 1 do
                    local row_group = newGroup()
                    for c = 0, grid_cols - 1 do
                        if idx > #rows then break end
                        local cx = text_left_c + c * (col_w + grid_col_gap)
                        local cy = grid_top + r * (cell_h + grid_row_gap)
                        groupAdd(row_group, statCellWidget(rows[idx]), cx, cy)
                        idx = idx + 1
                    end
                    flushGroup(row_group, TEXT_BACKDROP_PAD_H, TEXT_BACKDROP_PAD_V, panel_left, panel_right)
                end
            end

            -- Separator below a cell: under that cell only (one column
            -- wide), centred in the gap before the next grid row; none
            -- for cells in the last grid row.
            local grid_sep_lines = {}
            for idx, row in ipairs(rows) do
                local r = math.floor((idx - 1) / grid_cols)
                local c = (idx - 1) % grid_cols
                if row.sep and r < grid_rows_n - 1 then
                    grid_sep_lines[#grid_sep_lines + 1] = {
                        x = text_left_c + c * (col_w + grid_col_gap),
                        y = grid_top + r * (cell_h + grid_row_gap) + cell_h + math.floor(grid_row_gap / 2),
                        w = col_w,
                    }
                end
            end
            placeSeparators(grid_sep_lines)
        end
    else
    -- First pass, at the full left-column width, just to measure the
    -- stack's height for the cover-sizing math below.
    -- The title / author / series / quote stack is one box spanning the
    -- whole card width, below the cover + progress strip (the stats column
    -- on the right ends level with the strip, so nothing sits beside it).
    local text_max_w = W - 2 * pad_x - (backdrop_active and 2 * TEXT_BACKDROP_PAD_H or 0)
    local text_blocks, quote_index = buildTextBlocks(text_max_w, false, true)

    -- Gap between title/author/series, and the (separate, larger) gap
    -- above the quote. The tiered spacing below - tight lines, quote held
    -- further apart - only makes sense when one shared backdrop panel sits
    -- behind the whole block ("grouped" mode): that's the only case where
    -- the panel's own edges don't already mark a boundary between lines,
    -- so the gaps are what has to carry the visual grouping. Without a
    -- backdrop at all, or with a separate panel behind each line
    -- ("individual" mode - each line already reads as its own boundary via
    -- its own panel), every gap is just S(4), flat.
    -- Three cases:
    --  1) individual per-line backdrop panels, non-transparent (backdrop
    --     active, NOT grouped): each line already has its own visible
    --     panel, so a flat, slightly larger fixed gap (S(8)) is used
    --     between every line, quote included.
    --  2) grouped backdrop (one shared panel behind the whole block): the
    --     panel's own edges don't mark a boundary between lines, so tiered
    --     spacing (tight header lines, quote held further apart) carries
    --     the visual grouping instead.
    --  3) no backdrop at all / transparent: same tiered spacing as (2), so
    --     a boxless/transparent card matches the grouped-backdrop card.
    local individual_backdrop_showing = backdrop_active and not backdrop_grouped
    local header_gap, text_block_gap
    if individual_backdrop_showing then
        header_gap = S(8)
        text_block_gap = S(8)
    else
        local header_gap_base = math.floor(S(4) / 2)
        -- Gap above the quote first (unchanged from before): 3 * header_gap_base,
        -- or - with 3 * TEXT_BACKDROP_PAD_V eaten by the panel reaching toward
        -- itself around the quote - whichever of the two is larger, so the
        -- panel never overlaps itself.
        if backdrop_active then
            text_block_gap = math.max(3 * header_gap_base, 3 * TEXT_BACKDROP_PAD_V + S(4))
        else
            text_block_gap = S(4)      -- no panel to keep apart: gap above the quote kept minimal
        end
        -- Gap between title/author/series - set directly in (unscaled)
        -- pixels here, rather than as a fraction of text_block_gap: that
        -- value is only ~6-15px to begin with, so dividing it by anything
        -- much above ~10 always floors to 0 - there's no finer step below
        -- that, a screen can't draw half a pixel. Change GROUPED_HEADER_GAP
        -- directly to whatever small value you want (0 = lines touch).
        local GROUPED_HEADER_GAP = 1
        header_gap = S(GROUPED_HEADER_GAP)
    end
    local function gapBefore(i)
        if i <= 1 then return 0 end
        if quote_index and i > quote_index then return 0 end     -- quotes stack with no gap
        return (quote_index and i == quote_index) and text_block_gap or header_gap
    end

    -- Height of title/author/series only: the quote is deliberately NOT
    -- counted, so it never changes the cover's size or the position of
    -- anything above it - it just fills whatever room is left underneath
    -- (and is cut down to fewer lines only if that room runs out).
    local text_h = 0
    for i, block in ipairs(text_blocks) do
        if not quote_index or i < quote_index then
            text_h = text_h + block:getSize().h + gapBefore(i)
        end
    end

    -- The cover starts level with the first statistic (Progress), not with
    -- the battery indicator above it - or, with a backdrop panel showing,
    -- level with the TOP of that first statistic's panel, which sits
    -- TEXT_BACKDROP_PAD_V above the text itself.
    local show_cover_shadow = Prefs.readBool(M.SETTING_COVER_SHADOW, true)
    -- Reserve space for the shadow offset so the cover doesn't overflow its column.
    local shadow_off = show_cover_shadow and S(4) or 0
    local cover_top = stats_top - (backdrop_active and TEXT_BACKDROP_PAD_V or 0)
    -- The reserved gap below the text stack is text_block_gap - the same
    -- gap used above the quote - so the cover simply gets whatever's left
    -- below the whole title/author/series/quote block. It shrinks on its
    -- own by however much text_h grows, whether that's from the quote
    -- being on or from a long-enough title/author wrapping onto extra
    -- lines.
    -- Room for a full quote is reserved up front (when "Show quote" is on):
    -- the configured maximum number of lines plus the gap above it. So the
    -- cover, strip, stats, rating and title block are sized to always leave
    -- that much space, whether or not this book has a quote or how long it is.
    local quote_reserve = 0
    if Prefs.readBool(M.SETTING_QUOTE, false) then
        local qface_r = Fonts.getFace("quote", label_size)
        local qlh_r = math.floor((1 + 0.3) * qface_r.size + 0.5)
        quote_reserve = M.getQuoteMaxLines() * qlh_r + text_block_gap
    end
    local cover_max_h = math.max(S(80), content_bottom - cover_top - text_h - (quote_reserve > 0 and 0 or text_block_gap) - shadow_off - quote_reserve
                                 - (strip_h > 0 and (strip_h + S(12)) or 0))
    local cover_restore = wallpaper_bg and Wallpaper.restore or nil
    local cover, cover_w, cover_h = buildCover(card, left_w - shadow_off, cover_max_h, pal, shadow_off, cover_restore)

    -- Progress strip, exactly as wide as the cover, two lines on one grid:
    --   chapter read/total (left) | book read/total (left)
    --   [chapter bar] chapter %   | [book bar] book %
    local strip
    if strip_h > 0 then
        local inset = backdrop_active and TEXT_BACKDROP_PAD_H or 0
        local strip_w = cover_w - 2 * inset            -- as wide as the cover
        local sep_w = S(20)
        local half_w = math.floor((strip_w - sep_w) / 2)
        -- Shrink the font until both page-count texts fit their half.
        local face, size = strip_face, strip_size
        while size > 4 do
            local wc = TextWidget:new{ text = strip_ch_txt, face = face }:getSize().w
            local wb = TextWidget:new{ text = strip_bk_txt, face = face }:getSize().w
            if math.max(wc, wb) <= half_w then break end
            size = size - 1
            face = Fonts.getFaceAt("stat_value", size)
        end
        local line_h = math.max(TextWidget:new{ text = "Ag", face = face }:getSize().h, strip_bar_h)
        -- Line 1 gets a shorter box than its text so the two lines sit close.
        local trim = math.floor(line_h * 0.2)
        local function half(widget, h)
            return LeftContainer:new{ dimen = Geom:new{ w = half_w, h = h or line_h }, widget }
        end
        local function sep(h)
            return CenterContainer:new{
                dimen = Geom:new{ w = sep_w, h = h or line_h },
                text("|", face, stat_value_color),
            }
        end
        local function barCell(pct, label)
            local g = HorizontalGroup:new{ align = "center" }
            local lw = label and text(label, face, stat_value_color) or nil
            local gap = lw and S(8) or 0
            table.insert(g, StatCell.Bar:new{
                width = math.max(S(20), half_w - (lw and lw:getSize().w or 0) - gap),
                height = strip_bar_h, percent = pct, color = stat_value_color,
            })
            if lw then
                table.insert(g, HorizontalSpan:new{ width = gap })
                table.insert(g, lw)
            end
            return g
        end
        local line1 = HorizontalGroup:new{ align = "center",
            half(text(strip_ch_txt, face, stat_value_color), line_h - trim), sep(line_h - trim),
            half(text(strip_bk_txt, face, stat_value_color), line_h - trim) }
        local line2 = HorizontalGroup:new{ align = "center",
            half(barCell(strip_ch_pct, tostring(strip_ch_pct) .. "%")), sep(),
            half(barCell(strip_bk_pct, tostring(strip_bk_pct) .. "%")) }
        strip = VerticalGroup:new{ align = "left", line1, VerticalSpan:new{ width = strip_line_gap }, line2 }
    end

    -- The statistics column spans exactly the height of cover + progress
    -- strip: top level with the cover, bottom level with the strip's bottom
    -- (or the cover's own bottom, drop shadow included, with no strip). If
    -- the rows don't fit at the nominal size, the stat fonts are shrunk step
    -- by step until they do; any slack is spread evenly between the rows.
    local cover_bottom = cover_top + cover_h + (show_cover_shadow and shadow_off or 0)
    local strip_y = cover_top + cover_h + shadow_off + S(4)
    local stats_bottom_target = cover_bottom - (backdrop_active and TEXT_BACKDROP_PAD_V or 0)
    local stats_h = math.max(0, stats_bottom_target - stats_top)

    local stat_value_size, stat_label_size = Fonts.getUnitSize("stat_value"), Fonts.getUnitSize("stat_label")
    local cells, cells_h
    local function buildCells()
        local vf = Fonts.getFaceAt("stat_value", stat_value_size)
        local lf = Fonts.getFaceAt("stat_label", stat_label_size)
        local w = 0
        for _idx, row in ipairs(rows) do
            w = math.max(w,
                TextWidget:new{ text = row[1], face = vf }:getSize().w,
                TextWidget:new{ text = row[2], face = lf }:getSize().w)
        end
        right_w = math.min(w + S(2), math.floor((W - 2 * pad_x) * 0.6))
        cells, cells_h = {}, 0
        for _idx, row in ipairs(rows) do
            local cell = StatCell:new{
                value = row[1], label = row[2], width = right_w,
                value_face = vf, label_face = lf,
                value_color = stat_value_color, label_color = stat_label_color,
                bar = row.bar, bar_color = stat_value_color,
            }
            cells[#cells + 1] = cell
            cells_h = cells_h + cell:getSize().h
        end
    end
    buildCells()
    local shrink_guard = 0
    while cells_h > stats_h and stat_value_size > 4 and shrink_guard < 60 do
        stat_value_size = math.max(4, stat_value_size * 0.95)
        stat_label_size = math.max(3, stat_label_size * 0.95)
        buildCells()
        shrink_guard = shrink_guard + 1
    end
    -- Column sits a short, fixed distance right of the cover (shadow
    -- included) instead of being pushed against the right margin.
    local stats_x = pad_x - (backdrop_active and TEXT_BACKDROP_PAD_H or 0) + cover_w
                    + (show_cover_shadow and shadow_off or 0) + S(16)
    stats_x = math.min(stats_x, W - pad_x - right_w)
    -- Rating: five star icons (filled = rating, outline = the rest; drawn as
    -- SVG icons so no font needs the star glyphs), in the same row as the
    -- progress strip below the cover, centred (horizontally and vertically) in the
    -- box right of the strip. No heading. Size follows the strip's
    -- height, capped so five stars always fit in the space right of the strip.
    local rating_cell
    if Prefs.readBool(M.SETTING_RATING, true) and Prefs.read(M.SETTING_LAYOUT, "side") ~= "centered" then
        local free_w = W - pad_x - (pad_x + cover_w + (show_cover_shadow and shadow_off or 0)) - S(8)
        -- Stars follow every text shrink: scaled by how far the stats column's
        -- fonts had to shrink (ratio < 1 when a tall quote area makes the cover
        -- smaller), and never taller than the strip as it is really drawn (its
        -- text shrinks with the cover's width).
        local star_size
        if strip and strip:getSize().h > 0 then
            local ratio = math.min(1, stat_value_size / math.max(1, Fonts.getUnitSize("stat_value")))
            star_size = math.min(math.floor(strip_h * 0.7 * ratio), math.floor(strip:getSize().h * 0.7))
        else
            star_size = S(math.floor(stat_value_size * 1.3))
        end
        star_size = math.max(8, math.min(star_size, math.floor(free_w / 5.5)))
        local stars = HorizontalGroup:new{ align = "center" }
        local r = math.max(0, math.min(5, math.floor((tonumber(card.rating) or 0) + 0.5)))
        for i = 1, 5 do
            local st = icon(i <= r and "star" or "star_outline", star_size, pal)
            if st then
                table.insert(stars, st)
                if i < 5 then table.insert(stars, HorizontalSpan:new{ width = math.floor(star_size * 0.1) }) end
            end
        end
        rating_cell = stars
    end
    local gap = 0
    local stat_y = stats_top
    if #cells > 1 then
        gap = math.max(0, math.floor((stats_h - cells_h) / (#cells - 1)))
    elseif #cells == 1 then
        -- Nothing to distribute a gap between, so center the single row.
        stat_y = stats_top + math.max(0, math.floor((stats_h - cells_h) / 2))
    end
    -- Placed one at a time (rather than as a single VerticalGroup) so a
    -- wallpaper backdrop panel can sit behind each row individually instead
    -- of one solid strip behind the whole column.
    local stats_group = backdrop_grouped and newGroup() or nil
    local side_sep_lines = {}
    for i, cell in ipairs(cells) do
        if i > 1 then stat_y = stat_y + gap end
        if stats_group then
            groupAdd(stats_group, cell, stats_x, stat_y)
        else
            placeText(cell, stats_x, stat_y)
        end
        stat_y = stat_y + cell:getSize().h
        -- Separator below this row: centred in the gap to the next one
        -- (nothing to separate from after the last row).
        if rows[i] and rows[i].sep and i < #cells then
            side_sep_lines[#side_sep_lines + 1] = {
                x = stats_x,
                y = stat_y + math.floor(gap / 2),
                w = right_w,
            }
        end
    end
    if stats_group then flushGroup(stats_group, TEXT_BACKDROP_PAD_H, TEXT_BACKDROP_PAD_V) end
    placeSeparators(side_sep_lines)

    -- Cover's left edge: level with pad_x normally, or with the title
    -- block's backdrop panel (which sticks out TEXT_BACKDROP_PAD_H further
    -- left than the text) when that panel is showing.
    local cover_left = pad_x - (backdrop_active and TEXT_BACKDROP_PAD_H or 0)

    -- Cover drop shadow (painted first so the cover sits on top).
    if show_cover_shadow then
        local radius = Prefs.readBool(M.SETTING_ROUNDED, true) and S(4) or 0
        local shadow = CoverFrame.Shadow:new{
            width  = cover_w,
            height = cover_h,
            offset = shadow_off,
            radius = radius,
            bg     = pal.bg,
            restore = cover_restore,
            color  = Colors.getColor("shadow", CoverFrame.SHADOW_GRAY),
        }
        place(shadow, cover_left, cover_top)
    end

    place(cover, cover_left, cover_top)

    -- (text_block_gap/gapBefore are computed earlier, alongside the quote,
    -- since the cover-sizing math above needs them too.) Title, author,
    -- series and the quote (if any) are all placed here from the same
    -- text_blocks list - one flowing block, sharing one backdrop panel in
    -- "grouped" mode.
    local y = cover_top + cover_h + S(20)
    if strip then
        placeText(strip, cover_left + (backdrop_active and TEXT_BACKDROP_PAD_H or 0), strip_y)
        y = strip_y + strip:getSize().h + S(4)
    end
    if rating_cell then
        local rh = rating_cell:getSize().h
        local sh = strip and strip:getSize().h or rh
        local ry = strip_y + math.floor((sh - rh) / 2)
        -- Rating box = the space right of the strip, up to the right margin.
        local box_x = pad_x + cover_w + (show_cover_shadow and shadow_off or 0)
        local box_w = W - pad_x - box_x
        placeText(rating_cell, box_x + math.floor((box_w - rating_cell:getSize().w) / 2), ry)
        y = math.max(y, ry + rh + S(4))
    end
    -- Fit the quote into the space below the header block: only if it would
    -- run past content_bottom is it rebuilt with fewer lines (never fewer than
    -- 1 - the quote is cut off with "...", not dropped).
    if quote_index then
        local header_bottom = y + text_h
        local qh = 0
        for qi = quote_index, #text_blocks do qh = qh + text_blocks[qi]:getSize().h end
        if header_bottom + text_block_gap + qh > content_bottom then
            local qface = Fonts.getFace("quote", label_size)
            local qlh = math.floor((1 + 0.3) * qface.size + 0.5)
            local fit = math.min(M.getQuoteMaxLines(),
                math.floor((content_bottom - header_bottom - text_block_gap) / qlh))
            text_blocks, quote_index = buildTextBlocks(text_max_w, false, true, math.max(1, fit))
        end
    end
    local title_group = backdrop_grouped and newGroup() or nil
    for i, block in ipairs(text_blocks) do
        if i > 1 then y = y + gapBefore(i) end
        if title_group then
            groupAdd(title_group, block, pad_x, y)
        else
            placeText(block, pad_x, y)
        end
        y = y + block:getSize().h
    end
    if title_group then flushGroup(title_group, TEXT_BACKDROP_PAD_H, TEXT_BACKDROP_PAD_V) end
    end

    local canvas = OverlapGroup:new{
        dimen = Geom:new{ w = W, h = H },
        allow_mirroring = false,
    }
    for _idx, w in ipairs(items) do table.insert(canvas, w) end

    return FrameContainer:new{
        background = pal.bg,
        bordersize = 0,
        padding = 0,
        margin = 0,
        width = W,
        height = H,
        canvas,
    }
end

-- ---------------------------------------------------------------------------
-- Tap-to-close popup (for "Preview")
-- ---------------------------------------------------------------------------
local Popup = InputContainer:extend{
    name = "BookCardPreview",
    card = nil,
    covers_fullscreen = true,
}

function Popup:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H }
    if Device:hasKeys() then
        self.key_events.AnyKeyPressed = { { Device.input.group.Any } }
    end
    if Device:isTouchDevice() then
        self.ges_events.Tap = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        }
    end
    self[1] = M.build(self.card)
end

function Popup:onShow()
    UIManager:setDirty(self, function() return "full", self.dimen end)
end

function Popup:onTap()
    UIManager:close(self)
    return true
end
Popup.onAnyKeyPressed = Popup.onTap

function Popup:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

M.Popup = Popup

-- ---------------------------------------------------------------------------
-- "Margins" submenu (top/bottom padding)
-- ---------------------------------------------------------------------------
local function marginSpinner(setting, default, title_text, touchmenu_instance)
    UIManager:show(SpinWidget:new{
        title_text    = title_text,
        value         = Prefs.read(setting, default),
        value_min     = M.MARGIN_MIN,
        value_max     = M.MARGIN_MAX,
        value_step    = 1,
        value_hold_step = 10,
        default_value = default,
        ok_text       = _("Set"),
        callback      = function(spin)
            Prefs.save(setting, spin.value)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

-- Returns the sub_item_table for the "Margins" menu entry. All three
-- values default to the previous fixed layout; raising any of them pulls
-- the content in from that edge (handy on curved-glass screens whose
-- edges aren't fully visible - raising top and bottom together shifts the
-- card toward the middle of the screen).
function M.buildMarginsMenu()
    return {
        {
            text_func = function()
                return _("Side padding") .. ": " .. Prefs.read(M.SETTING_MARGIN_SIDE, M.DEFAULT_MARGIN_SIDE)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                marginSpinner(M.SETTING_MARGIN_SIDE, M.DEFAULT_MARGIN_SIDE, _("Side padding"), touchmenu_instance)
            end,
        },
        {
            text_func = function()
                return _("Top padding") .. ": " .. Prefs.read(M.SETTING_MARGIN_TOP, M.DEFAULT_MARGIN_TOP)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                marginSpinner(M.SETTING_MARGIN_TOP, M.DEFAULT_MARGIN_TOP, _("Top padding"), touchmenu_instance)
            end,
        },
        {
            text_func = function()
                return _("Bottom padding") .. ": " .. Prefs.read(M.SETTING_MARGIN_BOTTOM, M.DEFAULT_MARGIN_BOTTOM)
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                marginSpinner(M.SETTING_MARGIN_BOTTOM, M.DEFAULT_MARGIN_BOTTOM, _("Bottom padding"), touchmenu_instance)
            end,
        },
    }
end

-- ---------------------------------------------------------------------------
-- "Statistics" submenu (entries at the end of the Card elements menu): "Configure statistics items",
-- then one on/off toggle per row, listed in the reader's current order.
-- ---------------------------------------------------------------------------
-- The Reorder list: KOReader's SortWidget, plus a full-width line along the
-- bottom edge of every row that has a separator (item.separator), drawn in
-- the separator color - a preview of what ends up on the card.
local StatSortWidget = SortWidget:extend{}

-- SortWidget puts a hamburger icon in the title bar that only offers A-Z /
-- Z-A sorting, which makes no sense for this list. The icon is created inside
-- SortWidget:init(), so TitleBar.new is wrapped for the duration of that call
-- to drop it (sort_disabled would also switch off drag-to-reorder).
function StatSortWidget:init()
    local TitleBar = require("ui/widget/titlebar")
    local own_new = rawget(TitleBar, "new")
    local orig_new = TitleBar.new
    TitleBar.new = function(cls, o)
        if o then o.left_icon = nil end
        return orig_new(cls, o)
    end
    local ok, err = pcall(SortWidget.init, self)
    TitleBar.new = own_new -- restore (nil if it was inherited)
    if not ok then error(err, 0) end
end

-- Also swallow the hardware "Menu" key, which opens the same sort dialog.
function StatSortWidget:onShowWidgetMenu()
    return true
end

function StatSortWidget:_populateItems()
    SortWidget._populateItems(self)
    local color = Colors.getColor("separator", Blitbuffer.COLOR_DARK_GRAY)
    local thickness = math.max(1, Size.line.medium)
    for _i, row in ipairs(self.main_content) do
        if row.item and row.item.separator then
            local paint = row.paintTo
            row.paintTo = function(widget, bb, x, y)
                paint(widget, bb, x, y)
                bb:paintRect(x, y + widget.dimen.h - thickness, widget.dimen.w, thickness, color)
            end
        end
    end
end

local function openStatOrderWidget(touchmenu_instance)
    local order = M.getStatOrder()
    local item_table = {}
    for i = 1, #order do
        local def = STAT_DEFS_BY_ID[order[i]]
        item_table[#item_table + 1] = {
            text = def.menu_label and def.menu_label() or def.label(),
            id = def.id,
            separator = M.hasSeparator(def.id),
            -- Checkbox on the left (SortWidget: tapping the checkmark calls
            -- item:callback()) = the same on/off toggle as in the menu.
            checked_func = function() return Prefs.readBool(def.setting, def.default) end,
            callback = function()
                Prefs.save(def.setting, not Prefs.readBool(def.setting, def.default))
            end,
            -- Long press adds / removes the separator line below this row.
            -- SortWidget calls this as item:hold_callback(refresh).
            hold_callback = function(item, refresh)
                local on = not M.hasSeparator(def.id)
                M.setSeparator(def.id, on)
                item.separator = on
                if refresh then refresh() end
            end,
        }
    end
    local sort_widget
    sort_widget = StatSortWidget:new{
        title = _("Configure statistics items"),
        item_table = item_table,
        callback = function()
            local new_order = {}
            for i = 1, #sort_widget.item_table do
                new_order[#new_order + 1] = sort_widget.item_table[i].id
            end
            M.setStatOrder(new_order)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    }
    UIManager:show(sort_widget)
end

-- Hours/minutes spinner for a goal (stored as total minutes, in the key
-- shared with Reading Insights - see M.SETTING_DAILY_GOAL_MIN).
local function goalSpinner(setting, current, default, max_hours, title_text, touchmenu_instance)
    UIManager:show(DoubleSpinWidget:new{
        title_text      = title_text,
        left_text       = _("Hours"),
        left_value      = math.floor(current / 60),
        left_min        = 0,
        left_max        = max_hours,
        left_step       = 1,
        left_hold_step  = 5,
        right_text      = _("Minutes"),
        right_value     = current % 60,
        right_min       = 0,
        right_max       = 59,
        right_step      = 1,
        right_hold_step = 5,
        default_values  = true,
        left_default    = math.floor(default / 60),
        right_default   = default % 60,
        default_text    = Locale.tpl(_("Default: {value}"), { value = compactDuration(default * 60) }),
        ok_always_enabled = true,
        callback = function(hours, minutes)
            local total = (tonumber(hours) or 0) * 60 + (tonumber(minutes) or 0)
            if total < 1 then total = 1 end
            Prefs.save(setting, total)
            if touchmenu_instance then touchmenu_instance:updateItems() end
        end,
    })
end

--- Returns the sub_item_table for the "Statistics" menu entry: drag-to-sort
--- for the row order, plus the existing per-row on/off toggles, now listed
--- in that same order so the menu always matches what's drawn on the card.
function M.buildStatisticsMenu()
    local items = {
        {
            text = _("Configure statistics items"),
            keep_menu_open = true,
            callback = function(touchmenu_instance) openStatOrderWidget(touchmenu_instance) end,
            separator = true,
        },
    }
    -- Goal values (shared with Reading Insights), grouped in their own
    -- sub-menu at the very end of the Statistics menu.
    items[#items + 1] = {
        text = _("Reading goal settings"),
        sub_item_table_func = function()
            return {
                {
                    text_func = function()
                        return _("Set daily goal") .. ": " .. compactDuration(M.getDailyGoalMinutes() * 60)
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        goalSpinner(M.SETTING_DAILY_GOAL_MIN, M.getDailyGoalMinutes(), M.DEFAULT_DAILY_GOAL_MIN,
                            23, _("Daily Goal"), touchmenu_instance)
                    end,
                },
                {
                    text_func = function()
                        return _("Set weekly goal") .. ": " .. compactDuration(M.getWeeklyGoalMinutes() * 60)
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        goalSpinner(M.SETTING_WEEKLY_GOAL_MIN, M.getWeeklyGoalMinutes(), M.DEFAULT_WEEKLY_GOAL_MIN,
                            99, _("Weekly Goal"), touchmenu_instance)
                    end,
                },
            }
        end,
    }
    return items
end

return M
