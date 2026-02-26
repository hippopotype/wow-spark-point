-- SparkPoint Settings Panel
-- Blizzard Settings Panel integration for addon configuration

local addonName, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry
local GetDBValue = addon.GetDBValue
local SetDBValue = addon.SetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor
local GetProfileMode = addon.GetProfileMode
local GetActiveProfileMode = addon.GetActiveProfileMode

--------------------------------------------------------------------------------
-- Settings Panel Setup
--------------------------------------------------------------------------------
local ADDON_TITLE = "Spark Point"
local PROFILE_MODE_CONFIRM_POPUP = "SPARKPOINT_CONFIRM_PROFILE_MODE_CHANGE"
local PROFILE_COPY_CONFIRM_POPUP = "SPARKPOINT_CONFIRM_PROFILE_COPY"

local function BuildSettingsPanel()
	-- Create main settings category
	local category, layout = Settings.RegisterVerticalLayoutCategory(ADDON_TITLE)
	addon.SettingsCategoryID = category and category.ID or nil

	-- Get the database table
	local DB = addon.DB
	local RootDB = addon.DBRoot or {}

	------------------------------------------------------------------------
	-- Helper function to create a checkbox
	------------------------------------------------------------------------
	local function AddCheckbox(cat, dbKey, displayName, tooltip)
		local defaultValue = DB[dbKey]
		if defaultValue == nil then
			defaultValue = addon.DefaultValues and addon.DefaultValues[dbKey]
		end
		local setting = Settings.RegisterAddOnSetting(cat, addonName .. "_" .. dbKey, dbKey, DB, Settings.VarType.Boolean, displayName, defaultValue)
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
		local setting = Settings.RegisterAddOnSetting(cat, addonName .. "_" .. dbKey, dbKey, DB, Settings.VarType.Number, displayName, defaultValue)
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
		local setting = Settings.RegisterAddOnSetting(cat, addonName .. "_" .. dbKey, dbKey, DB, Settings.VarType.String, displayName, defaultValue)
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

	local visibilityRuleOptions = {
		{ key = "ALWAYS", label = L["Visibility Always"] or "Always" },
		{ key = "IN_COMBAT", label = L["Visibility In Combat"] or "In Combat" },
		{ key = "OUT_OF_COMBAT", label = L["Visibility Out of Combat"] or "Out of Combat" },
		{ key = "HAS_TARGET", label = L["Visibility Has Target"] or "Has Target" },
		{ key = "CASTING", label = L["Visibility While Casting"] or "While Casting" },
		{ key = "IN_PARTY", label = L["Visibility In Party"] or "In Party" },
		{ key = "IN_RAID", label = L["Visibility In Raid"] or "In Raid" },
		{ key = "IN_INSTANCE", label = L["Visibility In Instanced Content"] or "In Instanced Content" },
	}
	local visibilitySourceOptions = {
		{ value = "INHERIT", label = L["Visibility Inherit"] or "Inherit" },
		{ value = "CUSTOM", label = L["Visibility Custom"] or "Custom" },
	}
	local visibilityRuleProxy = {}

	local function NormalizeVisibilityRuleSelection(value, fallbackAlwaysWhenMissing)
		local out = {}
		local hasStoredTable = type(value) == "table"
		if hasStoredTable then
			for _, option in ipairs(visibilityRuleOptions) do
				if value[option.key] == true then
					out[option.key] = true
				end
			end
		end

		-- "ALWAYS" is exclusive: if any conditional rule is enabled, drop ALWAYS.
		if out.ALWAYS then
			for _, option in ipairs(visibilityRuleOptions) do
				if option.key ~= "ALWAYS" and out[option.key] then
					out.ALWAYS = nil
					break
				end
			end
		end

		if fallbackAlwaysWhenMissing and not hasStoredTable and not next(out) then
			out.ALWAYS = true
		end

		return out
	end

	local function GetNormalizedVisibilityRules(dbKey)
		local value = DB[dbKey]
		local isTable = type(value) == "table"
		if not isTable then
			value = addon.DefaultValues and addon.DefaultValues[dbKey]
		end
		return NormalizeVisibilityRuleSelection(value, not isTable)
	end

	local function GetDefaultVisibilityRules(dbKey)
		local defaults = addon.DefaultValues and addon.DefaultValues[dbKey]
		local out = NormalizeVisibilityRuleSelection(defaults, false)
		if not next(out) then
			out.ALWAYS = true
		end
		return out
	end

	local function AddVisibilityRuleGroup(parentCategory, dbKey, title, tooltip)
		local groupCategory = title and Settings.RegisterVerticalLayoutSubcategory(parentCategory, title) or parentCategory
		local controls = {}
		local settings = {}
		local settingsByRuleKey = {}
		local suppressRuleCallbacks = false
		for _, option in ipairs(visibilityRuleOptions) do
			local proxyKey = dbKey .. "__" .. option.key
			local currentRules = GetNormalizedVisibilityRules(dbKey)
			local defaultRules = GetDefaultVisibilityRules(dbKey)
			visibilityRuleProxy[proxyKey] = currentRules[option.key] == true

			local setting = Settings.RegisterAddOnSetting(
				groupCategory,
				addonName .. "_" .. proxyKey,
				proxyKey,
				visibilityRuleProxy,
				Settings.VarType.Boolean,
				option.label,
				defaultRules[option.key] == true
			)
			setting:SetValueChangedCallback(function(_, value)
				if suppressRuleCallbacks then
					return
				end

				visibilityRuleProxy[proxyKey] = value and true or false

				local nextRules = GetNormalizedVisibilityRules(dbKey)
				if value then
					nextRules[option.key] = true
				else
					nextRules[option.key] = nil
				end

				-- Enforce exclusive "ALWAYS" behavior in the UI and persisted DB.
				if option.key == "ALWAYS" and value then
					for _, other in ipairs(visibilityRuleOptions) do
						if other.key ~= "ALWAYS" then
							nextRules[other.key] = nil
						end
					end
				elseif option.key ~= "ALWAYS" and value then
					nextRules.ALWAYS = nil
				end

				nextRules = NormalizeVisibilityRuleSelection(nextRules, false)
				for _, syncOption in ipairs(visibilityRuleOptions) do
					local syncProxyKey = dbKey .. "__" .. syncOption.key
					local isChecked = nextRules[syncOption.key] == true
					visibilityRuleProxy[syncProxyKey] = isChecked
				end

				suppressRuleCallbacks = true
				for _, syncOption in ipairs(visibilityRuleOptions) do
					local peerSetting = settingsByRuleKey[syncOption.key]
					if peerSetting and peerSetting.SetValue then
						peerSetting:SetValue(visibilityRuleProxy[dbKey .. "__" .. syncOption.key] == true)
					end
				end
				suppressRuleCallbacks = false

				SetDBValue(dbKey, nextRules, true)
			end)
			settings[#settings + 1] = setting
			settingsByRuleKey[option.key] = setting
			controls[#controls + 1] = Settings.CreateCheckbox(
				groupCategory,
				setting,
				tooltip or (L["Visibility Multi Select Tooltip"] or "Select one or more rules. The element shows when any selected rule is true.")
			)
		end
		return {
			category = groupCategory,
			controls = controls,
			settings = settings,
		}
	end

	------------------------------------------------------------------------
	-- General Settings
	------------------------------------------------------------------------
	AddCheckbox(category, "attachToMouse", L["Attach to Cursor"] or "Attach to Cursor", L["Attach to Cursor Tooltip"] or "When enabled, the ring follows your cursor.")
	AddCheckbox(
		category,
		"showMinimapButton",
		L["Show Minimap Button"] or "Show Minimap Button",
		L["Show Minimap Button Tooltip"] or "Show a Spark Point minimap button that opens settings."
	)
	AddCheckbox(
		category,
		"fadeMinimapButtonWhenNotHovered",
		L["Fade Minimap Button"] or "Fade Minimap Button",
		L["Fade Minimap Button Tooltip"] or "Fade the Spark Point minimap button when your cursor is not over the minimap."
	)
	AddSlider(
		category,
		"minimapButtonFadeOpacity",
		L["Minimap Button Fade Opacity"] or "Minimap Button Fade Opacity",
		0,
		1,
		0.05,
		L["Minimap Button Fade Opacity Tooltip"] or "Opacity used when the minimap button is faded."
	)

	AddSlider(
		category,
		"offset_x",
		L["Anchor Horizontal Offset"] or "Anchor Horizontal Offset",
		0,
		256,
		1,
		L["Horizontal Offset Tooltip"] or "Horizontal offset from cursor position"
	)

	AddSlider(category, "offset_y", L["Anchor Vertical Offset"] or "Anchor Vertical Offset", -256, 0, 1, L["Vertical Offset Tooltip"] or "Vertical offset from cursor position")

	local profilesCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Profiles"] or "Profiles")
	do
		local suppressProfileModeCallback = false
		local suppressProfileCopyCallback = false
		local function GetModeLabel(mode)
			if mode == "CLASS" then
				return L["Profile Mode Class"] or "Class Specific"
			end
			return L["Profile Mode Global"] or "Global"
		end

		if StaticPopupDialogs and not StaticPopupDialogs[PROFILE_MODE_CONFIRM_POPUP] then
			StaticPopupDialogs[PROFILE_MODE_CONFIRM_POPUP] = {
				text = L["Profile Mode Change Confirm"] or "Changing profile mode will reload the interface. Continue?",
				button1 = ACCEPT,
				button2 = CANCEL,
				OnAccept = function(self, data)
					if not data then
						return
					end
					if addon.SetProfileMode then
						addon.SetProfileMode(data.newMode, true)
					end
				end,
				OnCancel = function(self, data)
					if not data then
						return
					end
					if addon.DBRoot then
						addon.DBRoot.profileMode = data.oldMode
					end
					if data.setting and data.setting.SetValue then
						suppressProfileModeCallback = true
						data.setting:SetValue(data.oldMode)
						suppressProfileModeCallback = false
					end
				end,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = STATICPOPUP_NUMDIALOGS,
			}
		end

		if StaticPopupDialogs and not StaticPopupDialogs[PROFILE_COPY_CONFIRM_POPUP] then
			StaticPopupDialogs[PROFILE_COPY_CONFIRM_POPUP] = {
				text = L["Profile Copy Confirm"] or "Copy settings from %s to %s? This will overwrite the current profile settings.",
				button1 = ACCEPT,
				button2 = CANCEL,
				OnAccept = function(self, data)
					if not data then
						return
					end
					if addon.CopyProfileFrom then
						addon.CopyProfileFrom(data.sourceKey, true)
					end
					if addon.DBRoot then
						addon.DBRoot.profileCopySource = "NONE"
					end
					if data.setting and data.setting.SetValue then
						suppressProfileCopyCallback = true
						data.setting:SetValue("NONE")
						suppressProfileCopyCallback = false
					end
				end,
				OnCancel = function(self, data)
					if not data then
						return
					end
					if addon.DBRoot then
						addon.DBRoot.profileCopySource = "NONE"
					end
					if data.setting and data.setting.SetValue then
						suppressProfileCopyCallback = true
						data.setting:SetValue("NONE")
						suppressProfileCopyCallback = false
					end
				end,
				timeout = 0,
				whileDead = true,
				hideOnEscape = true,
				preferredIndex = STATICPOPUP_NUMDIALOGS,
			}
		end

		local defaultValue = (addon.RootDefaultValues and addon.RootDefaultValues.profileMode) or "GLOBAL"
		local setting = Settings.RegisterAddOnSetting(
			profilesCategory,
			addonName .. "_profileMode",
			"profileMode",
			RootDB,
			Settings.VarType.String,
			L["Profile Mode"] or "Profile Mode",
			defaultValue
		)
		setting:SetValueChangedCallback(function(_, value)
			if suppressProfileModeCallback then
				return
			end
			if addon.SetProfileMode then
				local oldMode = GetActiveProfileMode and GetActiveProfileMode() or (GetProfileMode and GetProfileMode()) or "GLOBAL"
				local newMode = value
				if oldMode == newMode then
					return
				end

				if StaticPopup_Show then
					StaticPopup_Show(PROFILE_MODE_CONFIRM_POPUP, GetModeLabel(newMode), nil, {
						oldMode = oldMode,
						newMode = newMode,
						setting = setting,
					})
				else
					addon.SetProfileMode(newMode, true)
				end
			end
		end)
		Settings.CreateDropdown(profilesCategory, setting, function()
			local container = Settings.CreateControlTextContainer()
			container:Add("GLOBAL", L["Profile Mode Global"] or "Global")
			container:Add("CLASS", L["Profile Mode Class"] or "Class Specific")
			return container:GetData()
		end, L["Profile Mode Tooltip"] or "Changing this reloads the UI.")

		local copySetting = Settings.RegisterAddOnSetting(
			profilesCategory,
			addonName .. "_profileCopySource",
			"profileCopySource",
			RootDB,
			Settings.VarType.String,
			L["Copy Settings From"] or "Copy Settings From",
			(addon.RootDefaultValues and addon.RootDefaultValues.profileCopySource) or "NONE"
		)
		copySetting:SetValueChangedCallback(function(_, value)
			if suppressProfileCopyCallback then
				return
			end
			local sourceKey = value
			if not sourceKey or sourceKey == "NONE" then
				return
			end

			local sourceLabel = addon.GetProfileDisplayName and addon.GetProfileDisplayName(sourceKey) or tostring(sourceKey)
			local targetLabel = addon.GetProfileDisplayName and addon.GetProfileDisplayName(addon.GetProfileKey and addon.GetProfileKey() or "GLOBAL") or "Current Profile"

			if StaticPopup_Show then
				StaticPopup_Show(PROFILE_COPY_CONFIRM_POPUP, sourceLabel, targetLabel, {
					sourceKey = sourceKey,
					setting = copySetting,
				})
			else
				if addon.CopyProfileFrom then
					addon.CopyProfileFrom(sourceKey, true)
				end
				if addon.DBRoot then
					addon.DBRoot.profileCopySource = "NONE"
				end
				suppressProfileCopyCallback = true
				copySetting:SetValue("NONE")
				suppressProfileCopyCallback = false
			end
		end)
		Settings.CreateDropdown(profilesCategory, copySetting, function()
			local container = Settings.CreateControlTextContainer()
			container:Add("NONE", L["Copy Profile Select"] or "Select Profile...")
			if addon.GetAvailableProfileSources then
				for _, entry in ipairs(addon.GetAvailableProfileSources()) do
					container:Add(entry.key, entry.label)
				end
			end
			return container:GetData()
		end, L["Copy Settings From Tooltip"] or "Copy settings from another existing profile into the current profile")
	end

	local visibilityCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Visibility"] or "Visibility")
	AddVisibilityRuleGroup(visibilityCategory, "visibility_mode", nil, L["Addon Visibility Tooltip"] or "Default visibility rule used by modules set to inherit")

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
		local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. dbKey, dbKey, DB, Settings.VarType.Boolean, moduleData.name, defaultValue)
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

	AddSlider(castCategory, "cast_radius", L["Cast Radius"] or "Cast Radius", 16, 64, 1, L["Radius Tooltip"] or "Size of the cast ring")

	AddCheckbox(
		castCategory,
		"cast_reverseChanneling",
		L["Cast Reverse Channeling"] or "Cast Reverse Channeling",
		L["Reverse Channeling Tooltip"] or "Reverse the direction for channeled spells"
	)
	local castVisibilityCategory = Settings.RegisterVerticalLayoutSubcategory(castCategory, L["Visibility"] or "Visibility")
	AddDropdown(
		castVisibilityCategory,
		"cast_visibilitySource",
		L["Visibility Source"] or "Visibility Source",
		visibilitySourceOptions,
		L["Visibility Source Tooltip"] or "Choose whether this module inherits the global visibility setting or uses its own visibility"
	)
	AddVisibilityRuleGroup(castVisibilityCategory, "cast_visibility", nil, L["Cast Ring Visibility Tooltip"] or "When to show the cast ring shell")

	AddColor(castCategory, "cast_barColor", L["Cast Bar Color"] or "Cast Bar Color")
	AddCheckbox(
		castCategory,
		"cast_useClassColor",
		L["Cast Use Class Color"] or "Cast Use Class Color",
		L["Cast Use Class Color Tooltip"] or "Override cast colors with your class color"
	)
	AddSlider(
		castCategory,
		"cast_backgroundOpacity",
		L["Cast Background Opacity"] or "Cast Background Opacity",
		0,
		1,
		0.05,
		L["Cast Background Opacity Tooltip"] or "Opacity of the cast ring background"
	)
	AddSlider(castCategory, "cast_frameOpacity", L["Cast Frame Opacity"] or "Cast Frame Opacity", 0, 1, 0.05, L["Cast Frame Opacity Tooltip"] or "Opacity of the cast ring frame")
	AddSlider(castCategory, "cast_glowOpacity", L["Cast Glow Opacity"] or "Cast Glow Opacity", 0, 1, 0.05, L["Cast Glow Opacity Tooltip"] or "Opacity of the cast glow overlay")
	AddColor(castCategory, "cast_sparkColor", L["Cast Spark Color"] or "Cast Spark Color")
	AddColor(castCategory, "cast_latencyColor", L["Cast Latency Color"] or "Cast Latency Color")

	AddCheckbox(castCategory, "cast_spellTextEnabled", L["Cast Show Spell Name"] or "Cast Show Spell Name", L["Show Spell Name Tooltip"] or "Display the spell name above the ring")
	AddColor(castCategory, "cast_spellTextColor", L["Cast Spell Text Color"] or "Cast Spell Text Color")
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

	------------------------------------------------------------------------
	-- Inner Ring Slots Settings Subcategory
	------------------------------------------------------------------------
	local slotsCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Inner Ring Slots"] or "Inner Ring Slots")

	local slotProviderOptions = addon.SlotProviders:GetDropdownOptions()

	for i = 1, 3 do
		local prefix = "slot" .. i
		AddDropdown(
			slotsCategory,
			prefix .. "_provider",
			(L["Slot Source"] or "Slot") .. " " .. i .. " " .. (L["Source"] or "Source"),
			slotProviderOptions,
			(L["Slot Source Tooltip"] or "Choose what to display in inner ring slot") .. " " .. i
		)
		AddColor(slotsCategory, prefix .. "_barColor", (L["Slot"] or "Slot") .. " " .. i .. " " .. (L["Bar Color"] or "Bar Color"))
		AddCheckbox(
			slotsCategory,
			prefix .. "_useClassColor",
			(L["Slot"] or "Slot") .. " " .. i .. " " .. (L["Use Class Color"] or "Use Class Color"),
			(L["Slot Use Class Color Tooltip"] or "Override slot bar color with your class color")
		)
		AddSlider(
			slotsCategory,
			prefix .. "_backgroundOpacity",
			(L["Slot"] or "Slot") .. " " .. i .. " " .. (L["Background Opacity"] or "Background Opacity"),
			0,
			1,
			0.05,
			(L["Slot Background Opacity Tooltip"] or "Opacity of the slot background ring")
		)
	end

	------------------------------------------------------------------------
	-- Class Resource Settings Subcategory
	------------------------------------------------------------------------
	local cpCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Class Resource"] or "Class Resource")

	AddDropdown(cpCategory, "classresource_mode", L["Class Resource Mode"] or "Class Resource Mode", {
		{ value = "TEXT", label = L["Class Resource Mode Text"] or "Text" },
		{ value = "PIPS", label = L["Class Resource Mode Pips"] or "Pips" },
	}, L["Class Resource Mode Tooltip"] or "Switch between text and pips class resource display")

	local classResourceVisibilityCategory = Settings.RegisterVerticalLayoutSubcategory(cpCategory, L["Visibility"] or "Visibility")
	AddDropdown(
		classResourceVisibilityCategory,
		"classresource_visibilitySource",
		L["Visibility Source"] or "Visibility Source",
		visibilitySourceOptions,
		L["Visibility Source Tooltip"] or "Choose whether this module inherits the global visibility setting or uses its own visibility"
	)
	AddVisibilityRuleGroup(classResourceVisibilityCategory, "classresource_visibility", nil, L["Class Resource Visibility Tooltip"] or "When to show class resource")

	local cpTextCategory = Settings.RegisterVerticalLayoutSubcategory(cpCategory, L["Class Resource Text Mode"] or "Text Mode")
	AddSlider(cpTextCategory, "classresource_fontSize", L["Class Resource Font Size"] or "Class Resource Font Size", 8, 48, 1)
	AddSlider(cpTextCategory, "classresource_textOffsetX", L["Class Resource Text Horizontal Offset"] or "Class Resource Text Horizontal Offset", -300, 300, 1)
	AddSlider(cpTextCategory, "classresource_textOffsetY", L["Class Resource Text Vertical Offset"] or "Class Resource Text Vertical Offset", -300, 300, 1)
	AddDropdown(cpTextCategory, "classresource_font", L["Class Resource Font"] or "Class Resource Font", {
		{ value = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata" },
		{ value = "Fonts\\ARIALN.TTF", label = "Arial Narrow" },
		{ value = "Fonts\\MORPHEUS.ttf", label = "Morpheus" },
		{ value = "Fonts\\SKURRI.TTF", label = "Skurri" },
	})
	AddDropdown(cpTextCategory, "classresource_fontOutline", L["Class Resource Font Outline"] or "Class Resource Font Outline", {
		{ value = "", label = "None" },
		{ value = "OUTLINE", label = "Outline" },
		{ value = "THICKOUTLINE", label = "Thick Outline" },
		{ value = "MONOCHROME", label = "Monochrome" },
		{ value = "MONOCHROME,OUTLINE", label = "Mono + Outline" },
		{ value = "MONOCHROME,THICKOUTLINE", label = "Mono + Thick Outline" },
	})
	AddColor(cpTextCategory, "classresource_fontColor", L["Class Resource Font Color"] or "Class Resource Font Color")
	AddCheckbox(
		cpTextCategory,
		"classresource_useClassColor",
		L["Class Resource Use Class Color"] or "Class Resource Use Class Color",
		L["Class Resource Use Class Color Tooltip"] or "Override class resource text color with your class color"
	)

	local cpPipsCategory = Settings.RegisterVerticalLayoutSubcategory(cpCategory, L["Class Resource Pips Mode"] or "Pips Mode")
	AddSlider(
		cpPipsCategory,
		"classresource_scale",
		L["Class Resource Scale"] or "Class Resource Scale",
		0.5,
		2,
		0.05,
		L["Class Resource Scale Tooltip"] or "Scale for the Blizzard class-resource frame"
	)
	AddSlider(
		cpPipsCategory,
		"classresource_opacity",
		L["Class Resource Opacity"] or "Class Resource Opacity",
		0,
		1,
		0.05,
		L["Class Resource Opacity Tooltip"] or "Opacity for the class-resource copy frame"
	)
	AddColor(
		cpPipsCategory,
		"classresource_fillColor",
		L["Class Resource Fill Color"] or "Class Resource Fill Color",
		L["Class Resource Fill Color Tooltip"] or "Color for active class resource pips"
	)
	AddCheckbox(
		cpPipsCategory,
		"classresource_fillUseClassColor",
		L["Class Resource Use Class Color"] or "Class Resource Use Class Color",
		L["Class Resource Use Class Color Tooltip"] or "Override class resource pip fill color with your class color"
	)
	AddSlider(cpPipsCategory, "classresource_offsetX", L["Class Resource Horizontal Offset"] or "Class Resource Horizontal Offset", -300, 300, 1)
	AddSlider(cpPipsCategory, "classresource_offsetY", L["Class Resource Vertical Offset"] or "Class Resource Vertical Offset", -300, 300, 1)

	------------------------------------------------------------------------
	-- Ring Settings Subcategory
	------------------------------------------------------------------------
	local ringCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Decorative Ring"] or "Decorative Ring")
	local ringModule = addon.Modules and addon.Modules.RingObj
	local ringTextureOptions = (ringModule and ringModule.TEXTURE_OPTIONS)
		or {
			{ value = "decorative_ring_1", label = "Decorative Ring 1" },
			{ value = "decorative_ring_2", label = "Decorative Ring 2" },
		}

	AddSlider(ringCategory, "ring_width", L["Decorative Ring Size"] or "Decorative Ring Size", 20, 200, 1)
	AddCheckbox(ringCategory, "ring_rotate", L["Decorative Ring Rotate"] or "Decorative Ring Rotate", L["Rotate Tooltip"] or "Enable rotation animation")
	local ringVisibilityCategory = Settings.RegisterVerticalLayoutSubcategory(ringCategory, L["Visibility"] or "Visibility")
	AddDropdown(
		ringVisibilityCategory,
		"ring_visibilitySource",
		L["Visibility Source"] or "Visibility Source",
		visibilitySourceOptions,
		L["Visibility Source Tooltip"] or "Choose whether this module inherits the global visibility setting or uses its own visibility"
	)
	AddVisibilityRuleGroup(ringVisibilityCategory, "ring_visibility", nil, L["Decorative Ring Visibility Tooltip"] or "When to show the decorative ring")
	AddDropdown(ringCategory, "ring_texture", L["Decorative Ring Texture"] or "Decorative Ring Texture", ringTextureOptions)
	AddColor(ringCategory, "ring_color", L["Decorative Ring Color"] or "Decorative Ring Color")
	AddCheckbox(
		ringCategory,
		"ring_useClassColor",
		L["Decorative Ring Use Class Color"] or "Decorative Ring Use Class Color",
		L["Decorative Ring Use Class Color Tooltip"] or "Override ring color with your class color"
	)
	AddSlider(
		ringCategory,
		"ring_classColorAlpha",
		L["Decorative Ring Class Color Opacity"] or "Decorative Ring Class Color Opacity",
		0,
		1,
		0.05,
		L["Decorative Ring Class Color Opacity Tooltip"] or "Opacity for class color override",
		function(value)
			return string.format("%.2f", value or 0)
		end
	)

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
