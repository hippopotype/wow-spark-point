-- SparkPoint Settings Panel
-- Blizzard Settings Panel integration for addon configuration

local addonName, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry
local GetDBValue = addon.GetDBValue
local SetDBValue = addon.SetDBValue
local GetDBBool = addon.GetDBBool

--------------------------------------------------------------------------------
-- Settings Panel Setup
--------------------------------------------------------------------------------
local ADDON_TITLE = "Spark Point"

local function BuildSettingsPanel()
    -- Create main settings category
    local category, layout = Settings.RegisterVerticalLayoutCategory(ADDON_TITLE)
    addon.SettingsCategoryID = category and category.ID or nil

    -- Get the database table
    local DB = addon.DB

    ------------------------------------------------------------------------
    -- Helper function to create a checkbox
    ------------------------------------------------------------------------
    local function AddCheckbox(cat, dbKey, displayName, tooltip)
        local defaultValue = DB[dbKey]
        if defaultValue == nil then
            defaultValue = addon.DefaultValues and addon.DefaultValues[dbKey]
        end
        local setting = Settings.RegisterAddOnSetting(
            cat,
            addonName .. "_" .. dbKey,
            dbKey,
            DB,
            Settings.VarType.Boolean,
            displayName,
            defaultValue
        )
        setting:SetValueChangedCallback(function(_, value)
            SetDBValue(dbKey, value, true)
        end)
        Settings.CreateCheckbox(cat, setting, tooltip)
        return setting
    end

    ------------------------------------------------------------------------
    -- Helper function to create a slider
    ------------------------------------------------------------------------
    local function AddSlider(cat, dbKey, displayName, minVal, maxVal, step, tooltip)
        local defaultValue = DB[dbKey]
        if defaultValue == nil then
            defaultValue = addon.DefaultValues and addon.DefaultValues[dbKey]
        end
        local setting = Settings.RegisterAddOnSetting(
            cat,
            addonName .. "_" .. dbKey,
            dbKey,
            DB,
            Settings.VarType.Number,
            displayName,
            defaultValue
        )
        setting:SetValueChangedCallback(function(_, value)
            SetDBValue(dbKey, value, true)
        end)
        local options = Settings.CreateSliderOptions(minVal, maxVal, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(cat, setting, options, tooltip)
        return setting
    end

    ------------------------------------------------------------------------
    -- General Settings
    ------------------------------------------------------------------------
    AddCheckbox(category, "attachToMouse", L["Attach to Cursor"] or "Attach to Cursor",
        L["Attach to Cursor Tooltip"] or "When enabled, the ring follows your cursor.")

    AddSlider(category, "offset_x", L["Anchor Horizontal Offset"] or "Anchor Horizontal Offset", 0, 64, 1,
        L["Horizontal Offset Tooltip"] or "Horizontal offset from cursor position")

    AddSlider(category, "offset_y", L["Anchor Vertical Offset"] or "Anchor Vertical Offset", -64, 0, 1,
        L["Vertical Offset Tooltip"] or "Vertical offset from cursor position")

    ------------------------------------------------------------------------
    -- Module Toggles
    ------------------------------------------------------------------------
    local modules = addon.ControlCenter:GetModulesSorted()
    for _, moduleData in ipairs(modules) do
        local dbKey = moduleData.dbKey
        local defaultValue = DB[dbKey]
        if defaultValue == nil then
            defaultValue = addon.DefaultValues and addon.DefaultValues[dbKey]
        end
        local setting = Settings.RegisterAddOnSetting(
            category,
            addonName .. "_" .. dbKey,
            dbKey,
            DB,
            Settings.VarType.Boolean,
            moduleData.name,
            defaultValue
        )
        setting:SetValueChangedCallback(function(_, value)
            if value then
                addon.ControlCenter:EnableModule(dbKey)
            else
                addon.ControlCenter:DisableModule(dbKey)
            end
        end)
        Settings.CreateCheckbox(category, setting, moduleData.description)
    end

    ------------------------------------------------------------------------
    -- Cast Ring Settings Subcategory
    ------------------------------------------------------------------------
    local castCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Cast Ring"] or "Cast Ring")

    AddSlider(castCategory, "cast_radius", L["Cast Radius"] or "Cast Radius", 10, 128, 1,
        L["Radius Tooltip"] or "Size of the cast ring")

    AddSlider(castCategory, "cast_thickness", L["Cast Thickness"] or "Cast Thickness", 15, 35, 5,
        L["Thickness Tooltip"] or "Thickness of the ring")

    AddCheckbox(castCategory, "cast_sparkOnly", L["Cast Spark Only"] or "Cast Spark Only",
        L["Spark Only Tooltip"] or "Show only the spark without the ring")

    AddCheckbox(castCategory, "cast_reverseChanneling", L["Cast Reverse Channeling"] or "Cast Reverse Channeling",
        L["Reverse Channeling Tooltip"] or "Reverse the direction for channeled spells")

    AddCheckbox(castCategory, "cast_hideCastBar", L["Cast Hide Default Cast Bar"] or "Cast Hide Default Cast Bar",
        L["Hide Default Cast Bar Tooltip"] or "Hide the default Blizzard casting bar")

    AddCheckbox(castCategory, "cast_spellTextEnabled", L["Cast Show Spell Name"] or "Cast Show Spell Name",
        L["Show Spell Name Tooltip"] or "Display the spell name above the ring")

    AddSlider(castCategory, "cast_spellTextSize", L["Cast Spell Text Size"] or "Cast Spell Text Size", 8, 24, 1)

    ------------------------------------------------------------------------
    -- GCD Ring Settings Subcategory
    ------------------------------------------------------------------------
    local gcdCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["GCD Ring"] or "GCD Ring")

    AddSlider(gcdCategory, "gcd_radius", L["GCD Radius"] or "GCD Radius", 10, 128, 1)
    AddSlider(gcdCategory, "gcd_thickness", L["GCD Thickness"] or "GCD Thickness", 15, 35, 5)
    AddCheckbox(gcdCategory, "gcd_sparkOnly", L["GCD Spark Only"] or "GCD Spark Only")

    ------------------------------------------------------------------------
    -- Class Power Settings Subcategory
    ------------------------------------------------------------------------
    local cpCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Class Power"] or "Class Power")

    AddSlider(cpCategory, "classpower_fontSize", L["Class Power Font Size"] or "Class Power Font Size", 8, 32, 1)
    AddSlider(cpCategory, "classpower_offsetX", L["Class Power Horizontal Offset"] or "Class Power Horizontal Offset", -50, 50, 1)
    AddSlider(cpCategory, "classpower_offsetY", L["Class Power Vertical Offset"] or "Class Power Vertical Offset", -50, 50, 1)

    ------------------------------------------------------------------------
    -- Ring Settings Subcategory
    ------------------------------------------------------------------------
    local ringCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Ring"] or "Ring")

    AddSlider(ringCategory, "ring_width", L["Ring Size"] or "Ring Size", 20, 200, 1)
    AddCheckbox(ringCategory, "ring_rotate", L["Ring Rotate"] or "Ring Rotate",
        L["Rotate Tooltip"] or "Enable rotation animation")

    ------------------------------------------------------------------------
    -- Spell Icon Settings Subcategory
    ------------------------------------------------------------------------
    local iconCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Spell Icon"] or "Spell Icon")

    AddSlider(iconCategory, "spellicon_size", L["Spell Icon Size"] or "Spell Icon Size", 16, 64, 1)
    AddSlider(iconCategory, "spellicon_offsetX", L["Spell Icon Horizontal Offset"] or "Spell Icon Horizontal Offset", -100, 100, 1)
    AddSlider(iconCategory, "spellicon_offsetY", L["Spell Icon Vertical Offset"] or "Spell Icon Vertical Offset", -100, 100, 1)

    ------------------------------------------------------------------------
    -- Register main category
    ------------------------------------------------------------------------
    Settings.RegisterAddOnCategory(category)
end

--------------------------------------------------------------------------------
-- Initialize when addon loads
--------------------------------------------------------------------------------
CallbackRegistry:Register("ADDON_LOADED", function()
    -- Delay slightly to ensure all modules are registered and DB is loaded
    C_Timer.After(0.1, BuildSettingsPanel)
end)
