-- SparkPoint Bar Slots Module
-- Displays curved bar slots above and below the main cast ring.

local _, addon = ...
local L = addon.L
local API = addon.API
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local HUDLayers = addon.HUDLayers
local Visibility = addon.Visibility
local Transition = addon.Transition
local BarProviders = addon.BarProviders
local GetDBBool = addon.GetDBBool
local GetDBValue = addon.GetDBValue
local GetDBColorTable = addon.GetDBColorTable

local BAR_TEXTURE_WIDTH = 1024
local BAR_TEXTURE_HEIGHT = 512
local BAR_TEXTURE_ASPECT = BAR_TEXTURE_HEIGHT / BAR_TEXTURE_WIDTH
local EL = CreateFrame("Frame")

local BarSlots = {}
addon.Modules.BarSlotsObj = BarSlots

local isEnabled = false
local activeProviders = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function RoundToPixel(value)
	return math.floor((tonumber(value) or 0) + 0.5)
end

local function NormalizeProviderID(providerID)
	if type(providerID) ~= "string" then
		return nil
	end

	local normalized = string.upper(providerID)
	if normalized == "" or normalized == "NONE" then
		return nil
	end

	return normalized
end

--------------------------------------------------------------------------------
-- Slot Definitions
--------------------------------------------------------------------------------

local SLOT_DEFS = {
	{
		id = "top",
		prefix = "barslot_top",
		orientation = "HORIZONTAL",
		reverseFill = false,
		fillBase = "bar_fill_expanded_top",
		shellTexCoords = nil, -- identity, no transform needed
		positionFn = function(radius, screenW, screenH, offX, offY)
			local baseOffY = -25
			return RoundToPixel(offX), RoundToPixel(radius + screenH * 0.5 + baseOffY + offY)
		end,
		sizeFn = function(w, h)
			return w, h
		end,
	},
	{
		id = "bottom",
		prefix = "barslot_bottom",
		orientation = "HORIZONTAL",
		reverseFill = false,
		fillBase = "bar_fill_expanded_bottom",
		flipFillBoundsY = true,
		shellTexCoords = { 0, 1, 0, 0, 1, 1, 1, 0 }, -- flip Y
		positionFn = function(radius, screenW, screenH, offX, offY)
			local baseOffY = -25
			return RoundToPixel(offX), RoundToPixel(-(radius + screenH * 0.5 + baseOffY) + offY)
		end,
		sizeFn = function(w, h)
			return w, h
		end,
	},
}

-- Per-slot runtime state: { moduleFrame, widget, text, provider, providerID }
local slots = {}
for _, def in ipairs(SLOT_DEFS) do
	slots[def.id] = {}
end

--------------------------------------------------------------------------------
-- Per-slot key helpers
--------------------------------------------------------------------------------

local function SlotKey(def, suffix)
	return def.prefix .. "_" .. suffix
end

local function GetSlotValue(def, suffix)
	return GetDBValue(SlotKey(def, suffix))
end

local function GetSlotBool(def, suffix)
	return GetDBBool(SlotKey(def, suffix))
end

local function GetSlotColorTable(def, suffix)
	return GetDBColorTable(SlotKey(def, suffix))
end

--------------------------------------------------------------------------------
-- Frame level / strata
--------------------------------------------------------------------------------

local function GetResolvedFrameLevel(state)
	if state.moduleFrame and state.moduleFrame:GetParent() then
		local level = state.moduleFrame:GetParent():GetFrameLevel()
		if type(level) == "number" then
			return level
		end
	end
	return 20
end

local function ApplyFrameLevel(state)
	if not state.moduleFrame or not state.widget then
		return
	end

	local parent = state.moduleFrame:GetParent()
	if parent and parent.GetFrameStrata then
		local strata = parent:GetFrameStrata()
		state.moduleFrame:SetFrameStrata(strata)
		if state.widget.SetFrameStrata then
			state.widget:SetFrameStrata(strata)
		end
	end

	local frameLevel = GetResolvedFrameLevel(state)
	state.moduleFrame:SetFrameLevel(frameLevel)
	state.widget:SetFrameLevel(frameLevel)
end

--------------------------------------------------------------------------------
-- AnchorFrame management
--------------------------------------------------------------------------------

local function AnySlotShown()
	for _, def in ipairs(SLOT_DEFS) do
		local state = slots[def.id]
		if state.moduleFrame and state.moduleFrame:IsShown() then
			return true
		end
	end
	return false
end

local function ReleaseAnchorIfUnused()
	if not AnySlotShown() then
		AnchorFrame:Hide("barslots")
	end
end

--------------------------------------------------------------------------------
-- Show / Hide per slot
--------------------------------------------------------------------------------

local function ShowModuleFrame(state)
	if not state.moduleFrame then
		return
	end
	AnchorFrame:Show("barslots")
	if Transition and Transition.ShowFrame then
		Transition:ShowFrame(state.moduleFrame)
	else
		state.moduleFrame:SetAlpha(1)
		state.moduleFrame:Show()
	end
end

local function HideModuleFrame(state)
	if not state.moduleFrame then
		if state.widget then
			state.widget:Hide()
		end
		ReleaseAnchorIfUnused()
		return
	end
	if Transition and Transition.HideFrame then
		Transition:HideFrame(state.moduleFrame, {
			restoreAlpha = 1,
			onComplete = function()
				if state.widget then
					state.widget:Hide()
				end
				ReleaseAnchorIfUnused()
			end,
		})
	else
		if state.widget then
			state.widget:Hide()
		end
		state.moduleFrame:SetAlpha(1)
		state.moduleFrame:Hide()
		ReleaseAnchorIfUnused()
	end
end

--------------------------------------------------------------------------------
-- Provider assignment
--------------------------------------------------------------------------------

local function GetAssignedProviderID(def)
	local providerID = NormalizeProviderID(GetSlotValue(def, "provider"))
	if not providerID then
		return nil
	end
	if not BarProviders:Get(providerID) then
		return nil
	end
	return providerID
end

local function ApplyAssignments(def, state)
	state.provider = nil
	state.providerID = nil
	if not GetSlotBool(def, "enabled") then
		return
	end

	state.providerID = GetAssignedProviderID(def)
	if state.providerID then
		state.provider = BarProviders:Get(state.providerID)
	end
end

local function DisableInactiveProviders(requiredProviders)
	for providerID, provider in pairs(activeProviders) do
		if not requiredProviders[providerID] then
			if provider and provider.Disable then
				provider:Disable()
			end
			activeProviders[providerID] = nil
		end
	end
end

local function UpdateActiveProviders()
	local requiredProviders = {}

	if isEnabled then
		for _, def in ipairs(SLOT_DEFS) do
			local state = slots[def.id]
			if state.providerID and state.provider then
				requiredProviders[state.providerID] = state.provider
			end
		end
	end

	DisableInactiveProviders(requiredProviders)

	for providerID, provider in pairs(requiredProviders) do
		if not activeProviders[providerID] then
			if provider and provider.Enable then
				provider:Enable()
			end
			activeProviders[providerID] = provider
		end
	end
end

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------

local function IsModuleVisibleByRules(def)
	if not Visibility or not Visibility.ShouldShow then
		return true
	end
	return Visibility:ShouldShow(def.prefix)
end

--------------------------------------------------------------------------------
-- Color helpers
--------------------------------------------------------------------------------

local function GetConfiguredBarColor(def, result)
	local opacity = tonumber(GetSlotValue(def, "fillOpacity"))
	if opacity == nil then
		opacity = 1
	end
	if opacity < 0 then
		opacity = 0
	elseif opacity > 1 then
		opacity = 1
	end

	local source = tostring(GetSlotValue(def, "fillColorSource") or "CUSTOM")
	if source == "CLASS" then
		local r, g, b, a = API.GetPlayerClassColor()
		return { r = r, g = g, b = b, a = opacity }
	end
	if source == "PROVIDER" and result and result.barColor then
		return {
			r = result.barColor.r or 1,
			g = result.barColor.g or 1,
			b = result.barColor.b or 1,
			a = opacity,
		}
	end
	local color = GetSlotColorTable(def, "barColor") or { r = 1, g = 1, b = 1, a = 1 }
	return {
		r = color.r or 1,
		g = color.g or 1,
		b = color.b or 1,
		a = opacity,
	}
end

local function GetConfiguredBackgroundColor(def)
	local color = GetSlotColorTable(def, "backgroundColor") or { r = 1, g = 1, b = 1, a = 1 }
	local opacity = tonumber(GetSlotValue(def, "backgroundOpacity"))
	if opacity == nil then
		opacity = 0.8
	end
	return {
		r = color.r or 1,
		g = color.g or 1,
		b = color.b or 1,
		a = opacity,
	}
end

local function GetConfiguredFrameColor(def)
	local color = GetSlotColorTable(def, "frameColor") or { r = 1, g = 1, b = 1, a = 1 }
	local opacity = tonumber(GetSlotValue(def, "frameOpacity"))
	if opacity == nil then
		opacity = 1
	end
	return {
		r = color.r or 1,
		g = color.g or 1,
		b = color.b or 1,
		a = opacity,
	}
end

local function GetConfiguredTextColor(def, result)
	local opacity = tonumber(GetSlotValue(def, "textOpacity"))
	if opacity == nil then
		opacity = 1
	end
	if opacity < 0 then
		opacity = 0
	elseif opacity > 1 then
		opacity = 1
	end

	local source = tostring(GetSlotValue(def, "textColorSource") or "CUSTOM")
	if source == "CLASS" then
		local r, g, b = API.GetPlayerClassColor()
		return r, g, b, opacity
	end
	if source == "PROVIDER" and result and result.barColor then
		return result.barColor.r or 1, result.barColor.g or 1, result.barColor.b or 1, opacity
	end

	local color = GetSlotColorTable(def, "textColor") or { r = 1, g = 1, b = 1, a = 1 }
	return color.r or 1, color.g or 1, color.b or 1, opacity
end

--------------------------------------------------------------------------------
-- Text helpers
--------------------------------------------------------------------------------

local function GetFormattedText(def, state, result)
	if not result or result.current == nil or result.max == nil then
		return nil
	end

	local textData
	if state.provider and state.provider.GetTextDisplayData then
		textData = state.provider:GetTextDisplayData(result, tostring(GetSlotValue(def, "textNumberStyle") or "SHORT"))
	end
	if not textData then
		return nil
	end

	local mode = tostring(GetSlotValue(def, "textMode") or "CURRENT_PERCENT")
	local currentText = textData.current or "0"
	local maxText = textData.max or "0"
	local percentText = textData.percent or "0%"
	return API.ComposeBarTextDisplay(mode, currentText, maxText, percentText)
end

local function UpdateWidgetVisualOptions(def, state)
	if not state.widget then
		return
	end
	state.widget:SetBackgroundColor(GetConfiguredBackgroundColor(def))
	state.widget:SetFrameColor(GetConfiguredFrameColor(def))
end

local function ApplyTextOptions(def, state, result)
	if not state.text or not state.moduleFrame then
		return
	end

	local font = GetSlotValue(def, "textFont") or "Fonts\\FRIZQT__.TTF"
	local fontSize = tonumber(GetSlotValue(def, "textSize")) or 12
	local fontOutline = GetSlotValue(def, "textOutline") or "OUTLINE"
	state.text:SetFont(font, fontSize, fontOutline)

	local r, g, b, a = GetConfiguredTextColor(def, result)
	state.text:SetTextColor(r, g, b, a)

	local offsetX = tonumber(GetSlotValue(def, "textOffsetX")) or 0
	local offsetY = tonumber(GetSlotValue(def, "textOffsetY")) or 0
	state.text:ClearAllPoints()
	state.text:SetPoint("CENTER", state.moduleFrame, "CENTER", offsetX, offsetY)
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local function ApplySlotLayout(def, state)
	if not state.moduleFrame or not state.widget then
		return
	end

	ApplyFrameLevel(state)

	local radius = GetDBValue("cast_radius") or 40
	local scale = GetSlotValue(def, "scale") or 1
	local baseW = math.max(1, RoundToPixel((radius * 2) * scale))
	local baseH = math.max(1, RoundToPixel(baseW * BAR_TEXTURE_ASPECT))
	local screenW, screenH = def.sizeFn(baseW, baseH)
	local offsetX = RoundToPixel(GetSlotValue(def, "offsetX") or 0)
	local offsetY = RoundToPixel(GetSlotValue(def, "offsetY") or 0)

	local cx, cy = def.positionFn(radius, screenW, screenH, offsetX, offsetY)

	state.moduleFrame:ClearAllPoints()
	state.moduleFrame:SetPoint("CENTER", AnchorFrame:GetFrame(), "CENTER", cx, cy)
	state.moduleFrame:SetSize(screenW, screenH)
	state.moduleFrame:SetAlpha(1)

	state.widget:SetSize(screenW, screenH)
	UpdateWidgetVisualOptions(def, state)
	ApplyTextOptions(def, state)
end

function BarSlots:ApplyLayout()
	for _, def in ipairs(SLOT_DEFS) do
		ApplySlotLayout(def, slots[def.id])
	end
end

--------------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------------

local function RefreshBar(def, state)
	if not state.widget then
		return
	end

	if not isEnabled or not GetSlotBool(def, "enabled") or not state.provider or not IsModuleVisibleByRules(def) then
		HideModuleFrame(state)
		return
	end

	local result = state.provider:GetStatus()
	if not result or result.show == false or result.current == nil or result.max == nil then
		HideModuleFrame(state)
		return
	end

	state.widget:SetBarColor(GetConfiguredBarColor(def, result))
	UpdateWidgetVisualOptions(def, state)
	ApplyTextOptions(def, state, result)

	if state.text then
		if GetSlotBool(def, "textEnabled") then
			state.text:SetText(GetFormattedText(def, state, result) or "")
			state.text:Show()
		else
			state.text:Hide()
		end
	end

	if state.widget:SetValueRange(result.current, result.max) then
		ShowModuleFrame(state)
		state.widget:Show()
	else
		HideModuleFrame(state)
	end
end

local function RefreshAllSlots()
	for _, def in ipairs(SLOT_DEFS) do
		RefreshBar(def, slots[def.id])
	end
end

function BarSlots:UpdateVisibility()
	RefreshAllSlots()
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------

local function InitializeSlot(def, state)
	if state.moduleFrame then
		return
	end

	local anchor = AnchorFrame:GetFrame()
	local layerRoot = (HUDLayers and HUDLayers:GetLayerFrame(HUDLayers.Names.BAR_SLOTS)) or anchor
	state.moduleFrame = CreateFrame("Frame", nil, layerRoot)
	state.moduleFrame:Hide()

	state.widget = addon.BarSlotWidget:Create({
		parent = state.moduleFrame,
		width = 1,
		height = 1,
		orientation = def.orientation,
		reverseFill = def.reverseFill,
		flipFillBoundsY = def.flipFillBoundsY,
		shellTexCoords = def.shellTexCoords,
		backgroundBase = "bar_background",
		fillBase = def.fillBase or "bar_fill_expanded_top",
		frameBase = "bar_frame",
		barColor = GetSlotColorTable(def, "barColor"),
		backgroundColor = GetConfiguredBackgroundColor(def),
		frameColor = GetConfiguredFrameColor(def),
	})
	state.widget:AttachTo(state.moduleFrame)
	state.widget:GetFrame():SetAllPoints(state.moduleFrame)

	state.text = state.moduleFrame:CreateFontString(nil, "OVERLAY")
	state.text:Hide()

	ApplyFrameLevel(state)
	ApplySlotLayout(def, state)
end

function BarSlots:Initialize()
	for _, def in ipairs(SLOT_DEFS) do
		InitializeSlot(def, slots[def.id])
	end
end

--------------------------------------------------------------------------------
-- Enable / Disable
--------------------------------------------------------------------------------

local function EnableModule(enabled)
	isEnabled = enabled and true or false

	if enabled then
		BarSlots:Initialize()
		for _, def in ipairs(SLOT_DEFS) do
			ApplyAssignments(def, slots[def.id])
		end
		UpdateActiveProviders()
		BarSlots:ApplyLayout()
		EL:RegisterEvent("PLAYER_ENTERING_WORLD")
		EL:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		EL:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		EL:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
		EL:RegisterUnitEvent("UNIT_HEALTH", "player")
		EL:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
		EL:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
		EL:RegisterUnitEvent("UNIT_MAXPOWER", "player")
		RefreshAllSlots()
	else
		UpdateActiveProviders()
		for _, def in ipairs(SLOT_DEFS) do
			HideModuleFrame(slots[def.id])
		end
		EL:UnregisterAllEvents()
	end
end

--------------------------------------------------------------------------------
-- Event handlers
--------------------------------------------------------------------------------

function BarSlots:PLAYER_ENTERING_WORLD()
	RefreshAllSlots()
end

function BarSlots:PLAYER_SPECIALIZATION_CHANGED()
	RefreshAllSlots()
end

function BarSlots:UPDATE_SHAPESHIFT_FORM()
	RefreshAllSlots()
end

function BarSlots:UNIT_DISPLAYPOWER(event, unit)
	if unit ~= "player" then
		return
	end
	RefreshAllSlots()
end

function BarSlots:UNIT_HEALTH(event, unit)
	if unit ~= "player" then
		return
	end
	for _, def in ipairs(SLOT_DEFS) do
		local state = slots[def.id]
		if state.providerID == "HEALTH" then
			RefreshBar(def, state)
		end
	end
end

function BarSlots:UNIT_MAXHEALTH(event, unit)
	if unit ~= "player" then
		return
	end
	for _, def in ipairs(SLOT_DEFS) do
		local state = slots[def.id]
		if state.providerID == "HEALTH" then
			RefreshBar(def, state)
		end
	end
end

function BarSlots:UNIT_POWER_UPDATE(event, unit)
	if unit ~= "player" then
		return
	end
	for _, def in ipairs(SLOT_DEFS) do
		local state = slots[def.id]
		if state.providerID == "MANA" then
			RefreshBar(def, state)
		end
	end
end

function BarSlots:UNIT_MAXPOWER(event, unit)
	if unit ~= "player" then
		return
	end
	for _, def in ipairs(SLOT_DEFS) do
		local state = slots[def.id]
		if state.providerID == "MANA" then
			RefreshBar(def, state)
		end
	end
end

EL:SetScript("OnEvent", function(self, event, ...)
	if BarSlots[event] then
		BarSlots[event](BarSlots, event, ...)
	end
end)

--------------------------------------------------------------------------------
-- Setting callbacks (registered per slot)
--------------------------------------------------------------------------------

local LAYOUT_SUFFIXES = { "offsetX", "offsetY", "scale" }
local APPEARANCE_SUFFIXES = {
	"fillColorSource",
	"barColor",
	"fillOpacity",
	"backgroundColor",
	"backgroundOpacity",
	"frameColor",
	"frameOpacity",
	"textEnabled",
	"textMode",
	"textNumberStyle",
	"textColorSource",
	"textFont",
	"textSize",
	"textOutline",
	"textColor",
	"textOpacity",
	"textOffsetX",
	"textOffsetY",
}
local VISIBILITY_SUFFIXES = {
	"visibility",
	"visibilitySource",
	"hideOnUIHover",
	"hideInPetBattle",
	"hideInSpecialActionBarContext",
}

for _, def in ipairs(SLOT_DEFS) do
	local state = slots[def.id]

	-- Layout callbacks (also respond to shared cast_radius)
	for _, suffix in ipairs(LAYOUT_SUFFIXES) do
		CallbackRegistry:RegisterSettingCallback(SlotKey(def, suffix), function()
			ApplySlotLayout(def, state)
		end)
	end

	-- Appearance / text callbacks
	for _, suffix in ipairs(APPEARANCE_SUFFIXES) do
		CallbackRegistry:RegisterSettingCallback(SlotKey(def, suffix), function()
			ApplyTextOptions(def, state)
			UpdateWidgetVisualOptions(def, state)
			RefreshBar(def, state)
		end)
	end

	-- Provider changed
	CallbackRegistry:RegisterSettingCallback(SlotKey(def, "provider"), function()
		ApplyAssignments(def, state)
		UpdateActiveProviders()
		RefreshBar(def, state)
	end)

	-- Slot enabled changed
	CallbackRegistry:RegisterSettingCallback(SlotKey(def, "enabled"), function()
		ApplyAssignments(def, state)
		UpdateActiveProviders()
		RefreshBar(def, state)
	end)

	-- Visibility callbacks
	for _, suffix in ipairs(VISIBILITY_SUFFIXES) do
		CallbackRegistry:RegisterSettingCallback(SlotKey(def, suffix), function()
			RefreshBar(def, state)
		end)
	end
end

-- Shared layout keys that affect all slots
for _, key in ipairs({ "cast_radius", "moduleEnabled_Cast" }) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		BarSlots:ApplyLayout()
	end)
end

-- Global visibility keys that affect all slots
for _, key in ipairs({
	"visibility_mode",
	"visibility_hideOnUIHover",
	"visibility_hideInPetBattle",
	"visibility_hideInSpecialActionBarContext",
	"attachToMouse",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		BarSlots:UpdateVisibility()
	end)
end

CallbackRegistry:Register("VisibilityContextChanged", function()
	BarSlots:UpdateVisibility()
end, BarSlots)

CallbackRegistry:Register("HUDLayersChanged", function()
	for _, def in ipairs(SLOT_DEFS) do
		ApplyFrameLevel(slots[def.id])
	end
end, BarSlots)

--------------------------------------------------------------------------------
-- Module registration
--------------------------------------------------------------------------------

addon.ControlCenter:AddModule({
	name = L["Bar Slots"] or "Bar Slots",
	dbKey = "moduleEnabled_BarSlots",
	description = L["Bar Slots Description"] or "Displays curved bar slots above and below the cast ring",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 2,
})
