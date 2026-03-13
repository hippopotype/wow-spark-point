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
local ADDON_TITLE = "SparkPoint"
local PROFILE_MODE_CONFIRM_POPUP = "SPARKPOINT_CONFIRM_PROFILE_MODE_CHANGE"
local PROFILE_COPY_CONFIRM_POPUP = "SPARKPOINT_CONFIRM_PROFILE_COPY"

local NEW_SETTINGS = {
	spellicon_showTriggeredInstantCasts = true,
	spellicon_failedCastStyle = true,
	spellicon_showCooldownBlocked = true,
	spellicon_cooldownBlockedUseClassColor = true,
}

local function ApplyNewFeatureBadge(initializer, isNew)
	if not initializer or not isNew or initializer._sparkPointNewFeatureWrapped then
		return nil
	end
	initializer._sparkPointNewFeatureWrapped = true

	local originalInitFrame = initializer.InitFrame
	function initializer:InitFrame(frame)
		if originalInitFrame then
			originalInitFrame(self, frame)
		end

		if not frame then
			return
		end

		local badge = frame.NewFeature
		if not badge then
			local anchor = frame.Text or frame.Label or (frame.Button and frame.Button.Text) or (frame.GetFontString and frame:GetFontString())
			if not anchor then
				return
			end

			badge = CreateFrame("Frame", nil, frame, "NewFeatureLabelTemplate")
			frame.NewFeature = badge
			badge:SetScale(0.8)
			badge:SetFrameStrata("HIGH")
			badge:SetFrameLevel((frame:GetFrameLevel() or 0) + 5)
			badge:ClearAllPoints()
			badge:SetPoint("BOTTOMRIGHT", anchor, "LEFT", 16, -10)
		end

		badge:SetShown(true)
	end

	return initializer
end

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
		local initializer = Settings.CreateCheckbox(cat, setting, tooltip)
		ApplyNewFeatureBadge(initializer, NEW_SETTINGS[dbKey] == true)
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
		local initializer = Settings.CreateDropdown(cat, setting, GetOptions, tooltip)
		ApplyNewFeatureBadge(initializer, NEW_SETTINGS[dbKey] == true)
		return setting
	end

	------------------------------------------------------------------------
	-- Helper function to create a color picker (ColorOverride row)
	------------------------------------------------------------------------
	local function AddColor(cat, dbKey, displayName, tooltip, hasOpacity, isNew)
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
			isNew = isNew == true,
		})
		Settings.RegisterInitializer(cat, initializer)
		return initializer
	end

	local function AddInfoText(cat, text)
		local initializer = Settings.CreateElementInitializer("SparkPointSettingsListSectionHintTemplate", { name = text })
		Settings.RegisterInitializer(cat, initializer)
		return initializer
	end

	local function IsAssistedCVarEnabled()
		if GetCVarBool then
			return GetCVarBool("assistedCombatHighlight") == true
		end
		if C_CVar and C_CVar.GetCVar then
			return C_CVar.GetCVar("assistedCombatHighlight") == "1"
		end
		if GetCVar then
			return GetCVar("assistedCombatHighlight") == "1"
		end
		return false
	end

	local visibilityRuleOptions = {
		{ key = "ALWAYS", label = L["Visibility Always"] or "Always" },
		{ key = "IN_COMBAT", label = L["Visibility In Combat"] or "In Combat" },
		{ key = "OUT_OF_COMBAT", label = L["Visibility Out of Combat"] or "Out of Combat" },
		{ key = "HAS_TARGET", label = L["Visibility Has Target"] or "Has Target" },
		{ key = "TARGET_HOSTILE", label = L["Visibility Target Hostile"] or "Hostile / Unfriendly", indent = 1 },
		{ key = "TARGET_NEUTRAL", label = L["Visibility Target Neutral"] or "Neutral", indent = 1 },
		{ key = "TARGET_FRIENDLY", label = L["Visibility Target Friendly"] or "Friendly", indent = 1 },
		{ key = "CASTING", label = L["Visibility While Casting"] or "While Casting" },
		{ key = "AFTER_INSTANT_CAST", label = L["Visibility After Instant Cast"] or "After Instant Cast" },
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
				((option.indent and option.indent > 0) and (string.rep("  ", option.indent) .. option.label) or option.label),
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
		L["Show Minimap Button Tooltip"] or "Show a SparkPoint minimap button that opens settings."
	)
	AddCheckbox(
		category,
		"fadeMinimapButtonWhenNotHovered",
		L["Fade Minimap Button"] or "Fade Minimap Button",
		L["Fade Minimap Button Tooltip"] or "Fade the SparkPoint minimap button when your cursor is not over the minimap."
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
	AddCheckbox(
		visibilityCategory,
		"visibility_hideOnUIHover",
		L["Hide While Hovering UI"] or "Hide While Hovering UI",
		L["Hide While Hovering UI Tooltip"] or "Hide SparkPoint while cursor is over clickable UI frames. Keeps SparkPoint visible primarily for world targeting."
	)

	local transitionCategory = Settings.RegisterVerticalLayoutSubcategory(visibilityCategory, L["Transition"] or "Transition")
	AddCheckbox(
		transitionCategory,
		"transition_enabled",
		L["Transition Enabled"] or "Enable Transition",
		L["Transition Enabled Tooltip"] or "Enable subtle HUD fade and micro-interaction transitions."
	)
	AddSlider(
		transitionCategory,
		"transition_inDurationMs",
		L["Transition In Duration"] or "Fade In Duration",
		0,
		500,
		10,
		L["Transition In Duration Tooltip"] or "Duration for HUD fade in.",
		function(value)
			return string.format("%d ms", math.floor((value or 0) + 0.5))
		end
	)
	AddSlider(
		transitionCategory,
		"transition_outDurationMs",
		L["Transition Out Duration"] or "Fade Out Duration",
		0,
		500,
		10,
		L["Transition Out Duration Tooltip"] or "Duration for HUD fade out.",
		function(value)
			return string.format("%d ms", math.floor((value or 0) + 0.5))
		end
	)
	AddDropdown(transitionCategory, "transition_easing", L["Transition Easing"] or "Easing", {
		{ value = "outSine", label = L["Transition Easing OutSine"] or "Out Sine (Smooth)" },
		{ value = "outQuad", label = L["Transition Easing OutQuad"] or "Out Quad" },
		{ value = "linear", label = L["Transition Easing Linear"] or "Linear" },
	}, L["Transition Easing Tooltip"] or "Easing curve used by HUD transitions.")
	AddSlider(
		transitionCategory,
		"transition_hysteresisShowMs",
		L["Transition Show Hysteresis"] or "Show Hysteresis",
		0,
		400,
		10,
		L["Transition Show Hysteresis Tooltip"] or "Delay before showing after a visibility condition becomes true.",
		function(value)
			return string.format("%d ms", math.floor((value or 0) + 0.5))
		end
	)
	AddSlider(
		transitionCategory,
		"transition_hysteresisHideMs",
		L["Transition Hide Hysteresis"] or "Hide Hysteresis",
		0,
		400,
		10,
		L["Transition Hide Hysteresis Tooltip"] or "Delay before hiding after a visibility condition becomes false.",
		function(value)
			return string.format("%d ms", math.floor((value or 0) + 0.5))
		end
	)
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
	AddDropdown(castCategory, "cast_displayMode", L["Cast Progress Display"] or "Cast Progress Display", {
		{ value = "ALL", label = L["Cast Progress Display All"] or "All Casts" },
		{ value = "NON_CHANNEL", label = L["Cast Progress Display Normal"] or "Normal Casts Only" },
		{ value = "CHANNEL", label = L["Cast Progress Display Channelled"] or "Channelled Spells Only" },
	}, L["Cast Progress Display Tooltip"] or "Choose which cast types animate the progress fill. This does not change overall SparkPoint visibility.")
	local castVisibilityCategory = Settings.RegisterVerticalLayoutSubcategory(castCategory, L["Visibility"] or "Visibility")
	AddDropdown(
		castVisibilityCategory,
		"cast_visibilitySource",
		L["Visibility Source"] or "Visibility Source",
		visibilitySourceOptions,
		L["Visibility Source Tooltip"] or "Choose whether this module inherits the global visibility setting or uses its own visibility"
	)
	AddVisibilityRuleGroup(castVisibilityCategory, "cast_visibility", nil, L["Cast Ring Visibility Tooltip"] or "When to show the cast ring shell")
	AddCheckbox(
		castVisibilityCategory,
		"cast_hideOnUIHover",
		L["Hide While Hovering UI"] or "Hide While Hovering UI",
		L["Hide While Hovering UI Tooltip"] or "Hide SparkPoint while cursor is over clickable UI frames. Keeps SparkPoint visible primarily for world targeting."
	)

	AddDropdown(castCategory, "cast_fillColorSource", L["Cast Fill Color Source"] or "Cast Fill Color Source", {
		{ value = "SINGLE", label = L["Cast Fill Color Source Single"] or "Single Color" },
		{ value = "SPLIT", label = L["Cast Fill Color Source Split"] or "Separate Normal / Channelled Colors" },
		{ value = "CLASS", label = L["Cast Fill Color Source Class"] or "Class Color" },
	}, L["Cast Fill Color Source Tooltip"] or "Choose how the main cast ring fill color is selected")
	AddColor(
		castCategory,
		"cast_barColor",
		L["Primary Cast Color"] or "Primary Cast Color",
		L["Primary Cast Color Tooltip"] or "Used for all casts in Single Color mode, or normal non-channelled casts in Separate mode"
	)
	AddColor(
		castCategory,
		"cast_channelBarColor",
		L["Channelled Cast Color"] or "Channelled Cast Color",
		L["Channelled Cast Color Tooltip"] or "Color used for the cast ring fill while channeling"
	)
	AddColor(
		castCategory,
		"cast_backgroundColor",
		L["Background Color"] or "Background Color",
		L["Cast Background Color Tooltip"] or "Tint color for the cast ring background texture.",
		false
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
	local castClickFeedbackCategory = Settings.RegisterVerticalLayoutSubcategory(castCategory, L["Click Feedback"] or "Click Feedback")
	AddCheckbox(
		castClickFeedbackCategory,
		"cast_clickFeedbackEnabled",
		L["Click Feedback Enabled"] or "Enable Click Feedback",
		L["Click Feedback Enabled Tooltip"] or "Show a ring highlight while mouse buttons are held"
	)
	AddCheckbox(
		castClickFeedbackCategory,
		"cast_clickFeedbackLeft",
		L["Click Feedback Left"] or "Left Click",
		L["Click Feedback Left Tooltip"] or "Trigger click feedback while holding left mouse button"
	)
	AddCheckbox(
		castClickFeedbackCategory,
		"cast_clickFeedbackRight",
		L["Click Feedback Right"] or "Right Click",
		L["Click Feedback Right Tooltip"] or "Trigger click feedback while holding right mouse button (camera turn)"
	)
	AddSlider(
		castClickFeedbackCategory,
		"cast_clickFeedbackOpacity",
		L["Click Feedback Opacity"] or "Click Feedback Class Color Opacity",
		0,
		1,
		0.05,
		L["Click Feedback Opacity Tooltip"] or "Opacity of the click feedback ring"
	)
	AddCheckbox(
		castClickFeedbackCategory,
		"cast_clickFeedbackUseClassColor",
		L["Click Feedback Use Class Color"] or "Click Feedback Use Class Color",
		L["Click Feedback Use Class Color Tooltip"] or "Use your class color for the click feedback ring"
	)
	AddColor(
		castClickFeedbackCategory,
		"cast_clickFeedbackLeftColor",
		L["Click Feedback Left Color"] or "Left Click Color",
		L["Click Feedback Left Color Tooltip"] or "Color for left-click feedback when class color is disabled"
	)
	AddColor(
		castClickFeedbackCategory,
		"cast_clickFeedbackRightColor",
		L["Click Feedback Right Color"] or "Right Click Color",
		L["Click Feedback Right Color Tooltip"] or "Color for right-click feedback when class color is disabled"
	)
	AddCheckbox(
		castCategory,
		"cast_sparkUseClassColor",
		L["Cast Spark Use Class Color"] or "Spark Uses Class Color",
		L["Cast Spark Use Class Color Tooltip"] or "Use your class color for the cast spark instead of the custom spark color"
	)
	AddColor(castCategory, "cast_sparkColor", L["Cast Spark Color"] or "Cast Spark Color")
	AddColor(castCategory, "cast_latencyColor", L["Cast Latency Color"] or "Cast Latency Color")

	AddCheckbox(castCategory, "cast_spellTextEnabled", L["Cast Show Spell Name"] or "Cast Show Spell Name", L["Show Spell Name Tooltip"] or "Display the spell name above the ring")
	AddCheckbox(
		castCategory,
		"cast_spellTextUseClassColor",
		L["Cast Spell Text Use Class Color"] or "Spell Text Uses Class Color",
		L["Cast Spell Text Use Class Color Tooltip"] or "Use your class color for spell text instead of the custom text color"
	)
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

	AddSlider(castCategory, "cast_spellTextOffsetX", L["Cast Spell Text Offset X"] or "Cast Spell Text Offset X", -240, 240, 1)
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
		AddColor(
			slotsCategory,
			prefix .. "_backgroundColor",
			(L["Slot"] or "Slot") .. " " .. i .. " " .. (L["Background Color"] or "Background Color"),
			(L["Slot Background Color Tooltip"] or "Tint color for the slot background ring texture."),
			false
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
	AddCheckbox(
		classResourceVisibilityCategory,
		"classresource_hideOnUIHover",
		L["Hide While Hovering UI"] or "Hide While Hovering UI",
		L["Hide While Hovering UI Tooltip"] or "Hide SparkPoint while cursor is over clickable UI frames. Keeps SparkPoint visible primarily for world targeting."
	)

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
	AddColor(
		cpPipsCategory,
		"classresource_backgroundColor",
		L["Background Color"] or "Background Color",
		L["Class Resource Background Color Tooltip"] or "Tint multiplier for the class resource pip background texture.",
		false
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
	AddCheckbox(
		ringVisibilityCategory,
		"ring_hideOnUIHover",
		L["Hide While Hovering UI"] or "Hide While Hovering UI",
		L["Hide While Hovering UI Tooltip"] or "Hide SparkPoint while cursor is over clickable UI frames. Keeps SparkPoint visible primarily for world targeting."
	)
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
	AddColor(
		iconCategory,
		"spellicon_castProgressSwipeColor",
		L["Cast Progress Swipe Color"] or "Cast Progress Swipe Color",
		L["Cast Progress Swipe Color Tooltip"] or "Tint color and opacity of the spell icon cast progress swipe"
	)
	AddCheckbox(
		iconCategory,
		"spellicon_showInstantCasts",
		L["Show On Instant Casts"] or "Show On Instant Casts",
		L["Show On Instant Casts Tooltip"] or "Render the spell icon briefly for instant abilities you directly trigger"
	)
	AddCheckbox(
		iconCategory,
		"spellicon_showTriggeredInstantCasts",
		L["Show Triggered Instant Casts"] or "Show Triggered Instant Casts",
		L["Show Triggered Instant Casts Tooltip"] or "Also render instant spells triggered automatically after your action, such as procs or follow-up effects"
	)
	AddDropdown(iconCategory, "spellicon_failedCastStyle", L["Failed Cast Style"] or "Failed Cast Style", {
		{ value = "HIDE", label = L["Failed Cast Style Hide"] or "Hide" },
		{ value = "ERROR_ICON", label = L["Failed Cast Style Error Icon"] or "Error Icon" },
	}, L["Failed Cast Style Tooltip"] or "Choose how Spell Icon reacts when a cast attempt fails for a reason other than cooldown")
	AddCheckbox(
		iconCategory,
		"spellicon_showCooldownBlocked",
		L["Show Cooldown Blocked Presses"] or "Show Readable Cooldown",
		L["Show Cooldown Blocked Presses Tooltip"] or "Show the spell icon with remaining cooldown only when Blizzard exposes readable cooldown data for the pressed ability"
	)
	AddCheckbox(
		iconCategory,
		"spellicon_cooldownBlockedUseClassColor",
		L["Readable Cooldown Use Class Color"] or "Use Class Color",
		L["Readable Cooldown Use Class Color Tooltip"] or "Override readable cooldown swipe color with your class color while keeping the configured opacity"
	)
	AddColor(
		iconCategory,
		"spellicon_cooldownBlockedSwipeColor",
		L["Readable Cooldown Swipe Color"] or "Readable Cooldown Swipe Color",
		L["Readable Cooldown Swipe Color Tooltip"] or "Tint color and opacity of the readable cooldown swipe shown after a blocked press",
		nil,
		true
	)

	------------------------------------------------------------------------
	-- Assisted Highlight Settings Subcategory
	------------------------------------------------------------------------
	local assistedCategory = Settings.RegisterVerticalLayoutSubcategory(category, L["Assisted Highlight"] or "Assisted Highlight")

	if not IsAssistedCVarEnabled() then
		AddInfoText(
			assistedCategory,
			L["Assisted Highlight CVar Disabled"] or "Blizzard Assisted Highlight is currently disabled. Enable it in Blizzard settings to show suggestions."
		)
	end

	local assistedVisibilityCategory = Settings.RegisterVerticalLayoutSubcategory(assistedCategory, L["Visibility"] or "Visibility")
	AddDropdown(
		assistedVisibilityCategory,
		"assistedhighlight_visibilitySource",
		L["Visibility Source"] or "Visibility Source",
		visibilitySourceOptions,
		L["Visibility Source Tooltip"] or "Choose whether this module inherits the global visibility setting or uses its own visibility"
	)
	AddVisibilityRuleGroup(
		assistedVisibilityCategory,
		"assistedhighlight_visibility",
		nil,
		L["Assisted Highlight Visibility Tooltip"] or "When to show the assisted highlight icon"
	)
	AddCheckbox(
		assistedVisibilityCategory,
		"assistedhighlight_hideOnUIHover",
		L["Hide While Hovering UI"] or "Hide While Hovering UI",
		L["Hide While Hovering UI Tooltip"] or "Hide SparkPoint while cursor is over clickable UI frames. Keeps SparkPoint visible primarily for world targeting."
	)

	AddSlider(assistedCategory, "assistedhighlight_size", L["Assisted Highlight Size"] or "Assisted Highlight Size", 16, 64, 1)
	AddSlider(assistedCategory, "assistedhighlight_offsetX", L["Assisted Highlight Horizontal Offset"] or "Assisted Highlight Horizontal Offset", -100, 100, 1)
	AddSlider(assistedCategory, "assistedhighlight_offsetY", L["Assisted Highlight Vertical Offset"] or "Assisted Highlight Vertical Offset", -100, 100, 1)
	AddSlider(
		assistedCategory,
		"assistedhighlight_iconOpacity",
		L["Assisted Highlight Icon Opacity"] or "Assisted Highlight Icon Opacity",
		0,
		1,
		0.05,
		L["Assisted Highlight Icon Opacity Tooltip"] or "Opacity of the assisted highlight spell icon"
	)
	AddCheckbox(
		assistedCategory,
		"assistedhighlight_glowEnabled",
		L["Assisted Highlight Glow"] or "Assisted Highlight Glow",
		L["Assisted Highlight Glow Tooltip"] or "Show a blue glow around the suggested spell icon"
	)
	AddColor(
		assistedCategory,
		"assistedhighlight_glowColor",
		L["Assisted Highlight Glow Color"] or "Assisted Highlight Glow Color",
		L["Assisted Highlight Glow Color Tooltip"] or "Color and alpha for the assisted highlight glow layer"
	)
	AddCheckbox(
		assistedCategory,
		"assistedhighlight_glowTransitionEnabled",
		L["Assisted Highlight Glow Transition Enabled"] or "Enable Glow Transition",
		L["Assisted Highlight Glow Transition Enabled Tooltip"] or "Enable glow breathing micro-interaction on assisted highlight."
	)
	AddSlider(
		assistedCategory,
		"assistedhighlight_glowTransitionSpeed",
		L["Assisted Highlight Glow Transition Speed"] or "Glow Transition Speed",
		0.2,
		2.5,
		0.05,
		L["Assisted Highlight Glow Transition Speed Tooltip"] or "Speed multiplier for glow animation cycles."
	)
	AddSlider(
		assistedCategory,
		"assistedhighlight_glowTransitionStrength",
		L["Assisted Highlight Glow Transition Strength"] or "Glow Transition Strength",
		0,
		1.0,
		0.01,
		L["Assisted Highlight Glow Transition Strength Tooltip"] or "Additional intensity boost near glow peak."
	)
	AddCheckbox(
		assistedCategory,
		"assistedhighlight_keybindEnabled",
		L["Assisted Highlight Keybind Text"] or "Assisted Highlight Keybind Text",
		L["Assisted Highlight Keybind Text Tooltip"] or "Show the keybind for the suggested spell when available"
	)
	AddDropdown(assistedCategory, "assistedhighlight_keybindFormat", L["Assisted Highlight Keybind Format"] or "Assisted Highlight Keybind Format", {
		{ value = "COMPACT", label = L["Assisted Highlight Keybind Compact"] or "Compact" },
		{ value = "FULL", label = L["Assisted Highlight Keybind Full"] or "Full" },
	}, L["Assisted Highlight Keybind Format Tooltip"] or "Choose compact or full keybind text style")
	AddDropdown(assistedCategory, "assistedhighlight_keybindFont", L["Assisted Highlight Keybind Font"] or "Assisted Highlight Keybind Font", {
		{ value = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata" },
		{ value = "Fonts\\ARIALN.TTF", label = "Arial Narrow" },
		{ value = "Fonts\\MORPHEUS.ttf", label = "Morpheus" },
		{ value = "Fonts\\SKURRI.TTF", label = "Skurri" },
	})
	AddDropdown(assistedCategory, "assistedhighlight_keybindFontOutline", L["Assisted Highlight Keybind Font Outline"] or "Assisted Highlight Keybind Font Outline", {
		{ value = "", label = "None" },
		{ value = "OUTLINE", label = "Outline" },
		{ value = "THICKOUTLINE", label = "Thick Outline" },
		{ value = "MONOCHROME", label = "Monochrome" },
		{ value = "MONOCHROME,OUTLINE", label = "Mono + Outline" },
		{ value = "MONOCHROME,THICKOUTLINE", label = "Mono + Thick Outline" },
	})
	AddSlider(assistedCategory, "assistedhighlight_keybindFontSize", L["Assisted Highlight Keybind Font Size"] or "Assisted Highlight Keybind Font Size", 8, 48, 1)
	AddSlider(
		assistedCategory,
		"assistedhighlight_keybindOpacity",
		L["Assisted Highlight Keybind Opacity"] or "Assisted Highlight Keybind Opacity",
		0,
		1,
		0.05,
		L["Assisted Highlight Keybind Opacity Tooltip"] or "Opacity multiplier for assisted highlight keybind text"
	)
	AddSlider(
		assistedCategory,
		"assistedhighlight_keybindOffsetX",
		L["Assisted Highlight Keybind Horizontal Offset"] or "Assisted Highlight Keybind Horizontal Offset",
		-150,
		150,
		1
	)
	AddSlider(assistedCategory, "assistedhighlight_keybindOffsetY", L["Assisted Highlight Keybind Vertical Offset"] or "Assisted Highlight Keybind Vertical Offset", -150, 150, 1)
	AddColor(
		assistedCategory,
		"assistedhighlight_keybindColor",
		L["Assisted Highlight Keybind Color"] or "Assisted Highlight Keybind Color",
		L["Assisted Highlight Keybind Color Tooltip"] or "Color and alpha for assisted highlight keybind text"
	)

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
