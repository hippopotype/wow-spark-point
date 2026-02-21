-- SparkPoint Settings Panel
-- Blizzard Settings Panel integration for addon configuration

local addonName, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry
local GetDBValue = addon.GetDBValue
local SetDBValue = addon.SetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor

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
	local function GetStepPrecision(step)
		local stepString = tostring(step or 1)
		local dotPos = string.find(stepString, "%.")
		if not dotPos then
			return 0
		end
		return math.min(4, #stepString - dotPos)
	end

	local function QuantizeSliderValue(value, minVal, maxVal, step)
		if type(value) ~= "number" then
			return value
		end
		if type(step) ~= "number" or step <= 0 then
			return value
		end

		local snapped = minVal + math.floor(((value - minVal) / step) + 0.5) * step
		if type(minVal) == "number" then
			snapped = math.max(minVal, snapped)
		end
		if type(maxVal) == "number" then
			snapped = math.min(maxVal, snapped)
		end

		local precision = GetStepPrecision(step)
		local scale = 10 ^ precision
		return math.floor((snapped * scale) + 0.5) / scale
	end

	local function AddSlider(cat, dbKey, displayName, minVal, maxVal, step, tooltip, formatter)
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
			local snappedValue = QuantizeSliderValue(value, minVal, maxVal, step)
			SetDBValue(dbKey, snappedValue, true)
		end)
		local options = Settings.CreateSliderOptions(minVal, maxVal, step)
		if formatter then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
		else
			local precision = GetStepPrecision(step)
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
				local displayValue = QuantizeSliderValue(value or 0, minVal, maxVal, step)
				return string.format("%." .. precision .. "f", displayValue or 0)
			end)
		end
		Settings.CreateSlider(cat, setting, options, tooltip)
		return setting
	end

    ------------------------------------------------------------------------
    -- Helper function to create a dropdown
    ------------------------------------------------------------------------
    local function AddDropdown(cat, dbKey, displayName, options, tooltip)
        local defaultValue = DB[dbKey]
        if defaultValue == nil then
            defaultValue = addon.DefaultValues and addon.DefaultValues[dbKey]
        end
        local setting = Settings.RegisterAddOnSetting(
            cat,
            addonName .. "_" .. dbKey,
            dbKey,
            DB,
            Settings.VarType.String,
            displayName,
            defaultValue
        )
        setting:SetValueChangedCallback(function(_, value)
            SetDBValue(dbKey, value, true)
        end)
        local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            if options and options[1] then
                for _, entry in ipairs(options) do
                    container:Add(entry.value, entry.label)
                end
            else
                for value, label in pairs(options or {}) do
                    container:Add(value, label)
                end
            end
            return container:GetData()
        end
        Settings.CreateDropdown(cat, setting, GetOptions, tooltip)
        return setting
    end

    ------------------------------------------------------------------------
    -- Helper function to create a color picker (ColorOverride row)
    ------------------------------------------------------------------------
    local function AddColor(cat, dbKey, displayName, tooltip, hasOpacity)
        local initializer = Settings.CreateElementInitializer("SparkPointColorOverridesPanelNoHead", {
            categoryID = cat:GetID(),
            entries = { { key = dbKey, label = displayName, tooltip = tooltip } },
            getColor = function(key)
                local r, g, b, a = GetDBColor(key)
                return r, g, b, a
            end,
            setColor = function(key, r, g, b, a)
                addon.SetDBColor(key, r, g, b, a)
            end,
            getDefaultColor = function(key)
                local c = addon.DefaultValues and addon.DefaultValues[key]
                if c then
                    return c.r, c.g, c.b, c.a
                end
                return 1, 1, 1, 1
            end,
            hasOpacity = hasOpacity ~= false,
        })
        Settings.RegisterInitializer(cat, initializer)
        return initializer
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
    local function SetToggleEnabled(control, enabled)
        if control and control.Checkbox and control.Checkbox.SetEnabled then
            control.Checkbox:SetEnabled(enabled)
        elseif control and control.SetEnabled then
            control:SetEnabled(enabled)
        end
        if control and control.SetAlpha then
            control:SetAlpha(enabled and 1 or 0.5)
        end
    end

    local moduleControls = {}
    local moduleSettings = {}
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
            if dbKey == "moduleEnabled_SpellIcon" and value then
                if moduleSettings.moduleEnabled_Cast then
                    moduleSettings.moduleEnabled_Cast:SetValue(true)
                else
                    addon.ControlCenter:EnableModule("moduleEnabled_Cast")
                end
                SetToggleEnabled(moduleControls.moduleEnabled_Cast, false)
            end

            if value then
                addon.ControlCenter:EnableModule(dbKey)
            else
                addon.ControlCenter:DisableModule(dbKey)
            end

            if dbKey == "moduleEnabled_SpellIcon" and not value then
                SetToggleEnabled(moduleControls.moduleEnabled_Cast, true)
            end
        end)
        local control = Settings.CreateCheckbox(category, setting, moduleData.description)
        moduleControls[dbKey] = control
        moduleSettings[dbKey] = setting
    end

    if GetDBBool("moduleEnabled_SpellIcon") then
        if moduleSettings.moduleEnabled_Cast then
            moduleSettings.moduleEnabled_Cast:SetValue(true)
        else
            addon.ControlCenter:EnableModule("moduleEnabled_Cast")
        end
        SetToggleEnabled(moduleControls.moduleEnabled_Cast, false)
    end

    ------------------------------------------------------------------------
    -- Cast Ring Settings Subcategory
    ------------------------------------------------------------------------
    local castCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Cast Ring"] or "Cast Ring")

    AddSlider(castCategory, "cast_radius", L["Cast Radius"] or "Cast Radius", 16, 64, 1,
        L["Radius Tooltip"] or "Size of the cast ring")


    AddCheckbox(castCategory, "cast_reverseChanneling", L["Cast Reverse Channeling"] or "Cast Reverse Channeling",
        L["Reverse Channeling Tooltip"] or "Reverse the direction for channeled spells")

    AddCheckbox(castCategory, "cast_spellTextEnabled", L["Cast Show Spell Name"] or "Cast Show Spell Name",
        L["Show Spell Name Tooltip"] or "Display the spell name above the ring")

    AddSlider(castCategory, "cast_spellTextSize", L["Cast Spell Text Size"] or "Cast Spell Text Size", 8, 24, 1)

    AddDropdown(castCategory, "cast_spellTextFont", L["Cast Spell Text Font"] or "Cast Spell Text Font", {
        { value = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata" },
        { value = "Fonts\\ARIALN.TTF", label = "Arial Narrow" },
        { value = "Fonts\\MORPHEUS.ttf", label = "Morpheus" },
        { value = "Fonts\\SKURRI.TTF", label = "Skurri" },
    })

    AddDropdown(castCategory, "cast_spellTextOutline", L["Cast Spell Text Outline"] or "Cast Spell Text Outline", {
        { value = "", label = "None" },
        { value = "OUTLINE", label = "Outline" },
        { value = "THICKOUTLINE", label = "Thick Outline" },
        { value = "MONOCHROME", label = "Monochrome" },
        { value = "MONOCHROME,OUTLINE", label = "Mono + Outline" },
        { value = "MONOCHROME,THICKOUTLINE", label = "Mono + Thick Outline" },
    })

    AddSlider(castCategory, "cast_spellTextOffsetX", L["Cast Spell Text Offset X"] or "Cast Spell Text Offset X", -60, 60, 1)
    AddSlider(castCategory, "cast_spellTextOffsetY", L["Cast Spell Text Offset Y"] or "Cast Spell Text Offset Y", -240, 240, 1)

    AddColor(castCategory, "cast_barColor", L["Cast Bar Color"] or "Cast Bar Color")
    AddSlider(castCategory, "cast_backgroundOpacity", L["Cast Background Opacity"] or "Cast Background Opacity", 0, 1, 0.05,
        L["Cast Background Opacity Tooltip"] or "Opacity of the cast ring background")
    AddSlider(castCategory, "cast_frameOpacity", L["Cast Frame Opacity"] or "Cast Frame Opacity", 0, 1, 0.05,
        L["Cast Frame Opacity Tooltip"] or "Opacity of the cast ring frame")
    AddSlider(castCategory, "cast_glowOpacity", L["Cast Glow Opacity"] or "Cast Glow Opacity", 0, 1, 0.05,
        L["Cast Glow Opacity Tooltip"] or "Opacity of the cast glow overlay")
    AddColor(castCategory, "cast_sparkColor", L["Cast Spark Color"] or "Cast Spark Color")
    AddColor(castCategory, "cast_latencyColor", L["Cast Latency Color"] or "Cast Latency Color")
    AddColor(castCategory, "cast_spellTextColor", L["Cast Spell Text Color"] or "Cast Spell Text Color")
    AddCheckbox(castCategory, "cast_useClassColor", L["Cast Use Class Color"] or "Cast Use Class Color",
        L["Cast Use Class Color Tooltip"] or "Override cast colors with your class color")

    ------------------------------------------------------------------------
    -- Inner Ring Slots Settings Subcategory
    ------------------------------------------------------------------------
    local slotsCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Inner Ring Slots"] or "Inner Ring Slots")

    local slotProviderOptions = addon.SlotProviders:GetDropdownOptions()

    for i = 1, 3 do
        local prefix = "slot" .. i
        AddDropdown(slotsCategory, prefix .. "_provider",
            (L["Slot Source"] or "Slot") .. " " .. i .. " " .. (L["Source"] or "Source"),
            slotProviderOptions,
            (L["Slot Source Tooltip"] or "Choose what to display in inner ring slot") .. " " .. i)
        AddColor(slotsCategory, prefix .. "_barColor",
            (L["Slot"] or "Slot") .. " " .. i .. " " .. (L["Bar Color"] or "Bar Color"))
        AddCheckbox(slotsCategory, prefix .. "_useClassColor",
            (L["Slot"] or "Slot") .. " " .. i .. " " .. (L["Use Class Color"] or "Use Class Color"),
            (L["Slot Use Class Color Tooltip"] or "Override slot bar color with your class color"))
        AddSlider(slotsCategory, prefix .. "_backgroundOpacity",
            (L["Slot"] or "Slot") .. " " .. i .. " " .. (L["Background Opacity"] or "Background Opacity"),
            0, 1, 0.05,
            (L["Slot Background Opacity Tooltip"] or "Opacity of the slot background ring"))
    end

    ------------------------------------------------------------------------
    -- Class Resource Settings Subcategory
    ------------------------------------------------------------------------
    local cpCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Class Resource"] or "Class Resource")

    AddSlider(cpCategory, "classresource_fontSize", L["Class Resource Font Size"] or "Class Resource Font Size", 8, 32, 1)
    AddSlider(cpCategory, "classresource_offsetX", L["Class Resource Horizontal Offset"] or "Class Resource Horizontal Offset", -50, 50, 1)
    AddSlider(cpCategory, "classresource_offsetY", L["Class Resource Vertical Offset"] or "Class Resource Vertical Offset", -50, 50, 1)
    AddDropdown(cpCategory, "classresource_font", L["Class Resource Font"] or "Class Resource Font", {
        { value = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata" },
        { value = "Fonts\\ARIALN.TTF", label = "Arial Narrow" },
        { value = "Fonts\\MORPHEUS.ttf", label = "Morpheus" },
        { value = "Fonts\\SKURRI.TTF", label = "Skurri" },
    })
    AddDropdown(cpCategory, "classresource_fontOutline", L["Class Resource Font Outline"] or "Class Resource Font Outline", {
        { value = "", label = "None" },
        { value = "OUTLINE", label = "Outline" },
        { value = "THICKOUTLINE", label = "Thick Outline" },
        { value = "MONOCHROME", label = "Monochrome" },
        { value = "MONOCHROME,OUTLINE", label = "Mono + Outline" },
        { value = "MONOCHROME,THICKOUTLINE", label = "Mono + Thick Outline" },
    })
    AddColor(cpCategory, "classresource_fontColor", L["Class Resource Font Color"] or "Class Resource Font Color")
    AddDropdown(cpCategory, "classresource_visibility", L["Class Resource Visibility"] or "Class Resource Visibility", {
        { value = "ALWAYS", label = L["Visibility Always"] or "Always" },
        { value = "IN_COMBAT", label = L["Visibility In Combat"] or "In Combat" },
        { value = "OUT_OF_COMBAT", label = L["Visibility Out of Combat"] or "Out of Combat" },
        { value = "HAS_TARGET", label = L["Visibility Has Target"] or "Has Target" },
        { value = "CASTING", label = L["Visibility While Casting"] or "While Casting" },
    }, L["Class Resource Visibility Tooltip"] or "When to show class resource text")
    AddCheckbox(cpCategory, "classresource_useClassColor", L["Class Resource Use Class Color"] or "Class Resource Use Class Color",
        L["Class Resource Use Class Color Tooltip"] or "Override class resource text color with your class color")

    ------------------------------------------------------------------------
    -- Ring Settings Subcategory
    ------------------------------------------------------------------------
    local ringCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Decorative Ring"] or "Decorative Ring")

    AddSlider(ringCategory, "ring_width", L["Decorative Ring Size"] or "Decorative Ring Size", 20, 200, 1)
    AddCheckbox(ringCategory, "ring_rotate", L["Decorative Ring Rotate"] or "Decorative Ring Rotate",
        L["Rotate Tooltip"] or "Enable rotation animation")
    AddDropdown(ringCategory, "ring_texture", L["Decorative Ring Texture"] or "Decorative Ring Texture", {
        { value = "165624", label = "AuraRune 1" },
        { value = "165630", label = "AuraRune 1 Glow" },
        { value = "165635", label = "AuraRune 8" },
        { value = "165633", label = "AuraRune 5" },
        { value = "165634", label = "AuraRune 7" },
        { value = "165631", label = "AuraRune 9" },
        { value = "165638", label = "AuraRune A" },
        { value = "165639", label = "AuraRune B" },
        { value = "165640", label = "AuraRune C" },
        { value = "165623", label = "Halo" },
        { value = "165632", label = "Circle" },
        { value = "AuraSplit", label = "Aura Split" },
        { value = "AuraHalf", label = "Aura Half" },
    })
    AddColor(ringCategory, "ring_color", L["Decorative Ring Color"] or "Decorative Ring Color")
    AddCheckbox(ringCategory, "ring_useClassColor", L["Decorative Ring Use Class Color"] or "Decorative Ring Use Class Color",
        L["Decorative Ring Use Class Color Tooltip"] or "Override ring color with your class color")
    AddSlider(ringCategory, "ring_classColorAlpha", L["Decorative Ring Class Color Opacity"] or "Decorative Ring Class Color Opacity", 0, 1, 0.05,
        L["Decorative Ring Class Color Opacity Tooltip"] or "Opacity for class color override", function(value)
            return string.format("%.2f", value or 0)
        end)

    ------------------------------------------------------------------------
    -- Spell Icon Settings Subcategory
    ------------------------------------------------------------------------
    local iconCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Spell Icon"] or "Spell Icon")

    AddSlider(iconCategory, "spellicon_size", L["Spell Icon Size"] or "Spell Icon Size", 16, 64, 1)
    AddSlider(iconCategory, "spellicon_offsetX", L["Spell Icon Horizontal Offset"] or "Spell Icon Horizontal Offset", -100, 100, 1)
    AddSlider(iconCategory, "spellicon_offsetY", L["Spell Icon Vertical Offset"] or "Spell Icon Vertical Offset", -100, 100, 1)
    AddCheckbox(iconCategory, "spellicon_castProgressSwipe", L["Cast Progress Swipe"] or "Cast Progress Swipe")

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
