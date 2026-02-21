-- SparkPoint Database System
-- Centralized defaults and DialogueUI-style getters/setters

local addonName, addon = ...

local DB

--------------------------------------------------------------------------------
-- Default Values (all settings with their defaults)
--------------------------------------------------------------------------------
addon.DefaultValues = {
    -- Global/anchor settings
    attachToMouse = true,
    offset_x = 12,
    offset_y = -12,
    position_x = 400,
    position_y = 400,

    -- Module enable flags
    moduleEnabled_Cast = true,
    moduleEnabled_ClassResource = true,
    moduleEnabled_Ring = true,
    moduleEnabled_SpellIcon = true,

    -- Cast module settings
    cast_radius = 22,
    cast_thickness = 20,
    cast_barColor = {r = 1, g = 1, b = 1, a = 0.8},
    cast_backgroundOpacity = 0.8,
    cast_frameOpacity = 0.8,
    cast_glowOpacity = 0.8,
    cast_sparkColor = {r = 0.9, g = 0.8, b = 1, a = 1},
    cast_sparkScale = 0.5,
    cast_latencyColor = {r = 1, g = 0, b = 0, a = 1},

    cast_reverseChanneling = false,
    cast_useClassColor = false,
    cast_spellTextEnabled = false,
    cast_spellTextFont = "Fonts\\FRIZQT__.TTF",
    cast_spellTextSize = 12,
    cast_spellTextOutline = "",
    cast_spellTextColor = {r = 1, g = 1, b = 1, a = 0.8},
    cast_spellTextOffsetX = 0,
    cast_spellTextOffsetY = 0,

    -- GCD provider settings
    gcd_sparkColor = {r = 0.9, g = 0.8, b = 1, a = 1},
    gcd_useClassColor = false,

    -- Inner ring slot settings
    slot1_provider = "GCD",
    slot2_provider = "NONE",
    slot3_provider = "NONE",

    slot1_barColor = {r = 1, g = 1, b = 1, a = 0.8},
    slot1_useClassColor = false,
    slot1_backgroundOpacity = 0.8,
    slot2_barColor = {r = 1, g = 1, b = 1, a = 0.8},
    slot2_useClassColor = false,
    slot2_backgroundOpacity = 0.8,
    slot3_barColor = {r = 1, g = 1, b = 1, a = 0.8},
    slot3_useClassColor = false,
    slot3_backgroundOpacity = 0.8,

    -- ClassResource module settings
    classresource_font = "Fonts\\FRIZQT__.TTF",
    classresource_fontSize = 16,
    classresource_fontOutline = "",
    classresource_fontColor = {r = 1, g = 1, b = 1, a = 1},
    classresource_offsetX = 0,
    classresource_offsetY = 0,
    classresource_visibility = "ALWAYS",
    classresource_useClassColor = false,
    classresource_mode = "TEXT",

    -- ClassResource bars mode settings
    classresource_bars_width = 180,
    classresource_bars_height = 14,
    classresource_bars_spacing = 4,
    classresource_bars_offsetX = 0,
    classresource_bars_offsetY = 0,
    classresource_bars_showSecondary = true,
    classresource_bars_showText = true,
    classresource_bars_textStyle = "PERCENT",
    classresource_bars_font = "Fonts\\FRIZQT__.TTF",
    classresource_bars_fontSize = 11,
    classresource_bars_fontOutline = "",
    classresource_bars_barColor = {r = 0.25, g = 0.7, b = 1, a = 1},
    classresource_bars_backgroundColor = {r = 0, g = 0, b = 0, a = 0.45},
    classresource_bars_useClassColor = false,
    classresource_bars_usePowerColor = true,
    classresource_bars_texture = "AUTO",

    -- Ring module settings
    ring_texture = "165624",
    ring_color = {r = 0, g = 1, b = 0, a = 0.5},
    ring_width = 75,
    ring_rotate = true,
    ring_useClassColor = false,
    ring_classColorAlpha = 0.5,

    -- SpellIcon module settings (NEW)
    spellicon_size = 32,
    spellicon_offsetX = 0,
    spellicon_offsetY = -40,
    spellicon_castProgressSwipe = true,
}

--------------------------------------------------------------------------------
-- Database Loading
--------------------------------------------------------------------------------
function addon:LoadDatabase()
    SparkPointDB = SparkPointDB or {}
    DB = SparkPointDB
    addon.DB = DB

    -- Apply defaults for missing keys
    for dbKey, defaultValue in pairs(addon.DefaultValues) do
        if DB[dbKey] == nil then
            -- Deep copy tables
            if type(defaultValue) == "table" then
                DB[dbKey] = {}
                for k, v in pairs(defaultValue) do
                    DB[dbKey][k] = v
                end
            else
                DB[dbKey] = defaultValue
            end
        end
    end

    -- Trigger initial setting callbacks
    for dbKey, value in pairs(DB) do
        addon.CallbackRegistry:Trigger("SettingChanged." .. dbKey, value, false)
    end
end

--------------------------------------------------------------------------------
-- Database Access Functions (DialogueUI-style)
--------------------------------------------------------------------------------
function addon.GetDBValue(dbKey)
    return DB and DB[dbKey]
end

function addon.SetDBValue(dbKey, value, userInput)
    if DB then
        -- Deep copy tables
        if type(value) == "table" then
            DB[dbKey] = {}
            for k, v in pairs(value) do
                DB[dbKey][k] = v
            end
        else
            DB[dbKey] = value
        end
        addon.CallbackRegistry:Trigger("SettingChanged." .. dbKey, value, userInput)
    end
end

function addon.GetDBBool(dbKey)
    return DB and DB[dbKey] == true
end

function addon.FlipDBBool(dbKey)
    addon.SetDBValue(dbKey, not addon.GetDBBool(dbKey), true)
end

-- Color helpers
function addon.GetDBColor(dbKey)
    local c = DB and DB[dbKey]
    if c then
        return c.r or 1, c.g or 1, c.b or 1, c.a or 1
    end
    return 1, 1, 1, 1
end

function addon.SetDBColor(dbKey, r, g, b, a)
    addon.SetDBValue(dbKey, {r = r, g = g, b = b, a = a or 1}, true)
end

-- Get color as table
function addon.GetDBColorTable(dbKey)
    local c = DB and DB[dbKey]
    if c then
        return {r = c.r or 1, g = c.g or 1, b = c.b or 1, a = c.a or 1}
    end
    return {r = 1, g = 1, b = 1, a = 1}
end
