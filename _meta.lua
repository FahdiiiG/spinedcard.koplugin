local _ = require("gettext")

-- One-line plugin-manager description, picked per UI language. Deliberately
-- NOT run through gettext: the plugin manager reads _meta.lua before the
-- plugin's own locale/*.po files are loaded.
local DESCRIPTIONS = {
    en = "Spined Card is a sleep screen for KOReader that shows a reading summary card with a real-book cover (spine, page stack, progress ribbon), progress strip, star rating and highlighted quotes. A fork of Book card.",
}

local function pickDescription()
    local lang = "en"
    if G_reader_settings and G_reader_settings.readSetting then
        lang = G_reader_settings:readSetting("language") or "en"
    end
    local base = tostring(lang):match("^([a-z][a-z])") or "en"
    return DESCRIPTIONS[base] or DESCRIPTIONS.en
end

return {
    -- Keep `name`: some KOReader releases key the plugin-manager
    -- enable/disable toggle off what they find here.
    name = "spinedcard",
    fullname = _("Spined Card"),
    description = pickDescription(),
    version = "1.0.1",
}
