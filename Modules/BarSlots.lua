-- SparkPoint Bar Slots Module
-- Displays curved horizontal top bar slots above the main cast ring.

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
local MODULE_PREFIX = "barslots"
local BAR_BASE_OFFSET_Y = -25
local SLOT_ID = "top"
local SLOT_KEY_PREFIX = "barslot_" .. SLOT_ID .. "_"
local EL = CreateFrame("Frame")

local BarSlots = {}
addon.Modules.BarSlotsObj = BarSlots

local isEnabled = false
local moduleFrame
local widget
local text
local assignedProvider
local assignedProviderID = "NONE"

local function SlotKey(suffix)
	return SLOT_KEY_PREFIX .. suffix
end

local function GetSlotValue(suffix)
	return GetDBValue(SlotKey(suffix))
end

local function GetSlotBool(suffix)
	return GetDBBool(SlotKey(suffix))
end

local function GetSlotColorTable(suffix)
	return GetDBColorTable(SlotKey(suffix))
end

local function RoundToPixel(value)
	return math.floor((tonumber(value) or 0) + 0.5)
end

local function GetResolvedFrameLevel()
	if moduleFrame and moduleFrame:GetParent() then
		local level = moduleFrame:GetParent():GetFrameLevel()
		if type(level) == "number" then
			return level
		end
	end
	return 20
end

local function ApplyFrameLevel()
	if not moduleFrame or not widget then
		return
	end

	local parent = moduleFrame:GetParent()
	if parent and parent.GetFrameStrata then
		local strata = parent:GetFrameStrata()
		moduleFrame:SetFrameStrata(strata)
		if widget.SetFrameStrata then
			widget:SetFrameStrata(strata)
		end
	end

	local frameLevel = GetResolvedFrameLevel()
	moduleFrame:SetFrameLevel(frameLevel)
	widget:SetFrameLevel(frameLevel)
end

local function ReleaseAnchorIfUnused()
	if moduleFrame and not moduleFrame:IsShown() then
		AnchorFrame:Hide("barslots")
	end
end

local function ShowModuleFrame()
	if not moduleFrame then
		return
	end
	AnchorFrame:Show("barslots")
	if Transition and Transition.ShowFrame then
		Transition:ShowFrame(moduleFrame)
	else
		moduleFrame:SetAlpha(1)
		moduleFrame:Show()
	end
end

local function HideModuleFrame()
	if not moduleFrame then
		if widget then
			widget:Hide()
		end
		ReleaseAnchorIfUnused()
		return
	end
	if Transition and Transition.HideFrame then
		Transition:HideFrame(moduleFrame, {
			restoreAlpha = 1,
			onComplete = function()
				if widget then
					widget:Hide()
				end
				ReleaseAnchorIfUnused()
			end,
		})
	else
		if widget then
			widget:Hide()
		end
		moduleFrame:SetAlpha(1)
		moduleFrame:Hide()
		ReleaseAnchorIfUnused()
	end
end

local function NormalizeProviderID(providerID)
	if type(providerID) ~= "string" or providerID == "" then
		return "NONE"
	end
	return providerID
end

local function IsModuleVisibleByRules()
	if not Visibility or not Visibility.ShouldShow then
		return true
	end
	return Visibility:ShouldShow(MODULE_PREFIX)
end

local function GetConfiguredBarColor(result)
	local opacity = tonumber(GetSlotValue("fillOpacity"))
	if opacity == nil then
		opacity = 1
	end
	if opacity < 0 then
		opacity = 0
	elseif opacity > 1 then
		opacity = 1
	end

	local source = tostring(GetSlotValue("fillColorSource") or "CUSTOM")
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
	local color = GetSlotColorTable("barColor") or { r = 1, g = 1, b = 1, a = 1 }
	return {
		r = color.r or 1,
		g = color.g or 1,
		b = color.b or 1,
		a = opacity,
	}
end

local function GetConfiguredBackgroundColor()
	local color = GetSlotColorTable("backgroundColor") or { r = 1, g = 1, b = 1, a = 1 }
	local opacity = tonumber(GetSlotValue("backgroundOpacity"))
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

local function GetConfiguredFrameColor()
	local color = GetSlotColorTable("frameColor") or { r = 1, g = 1, b = 1, a = 1 }
	local opacity = tonumber(GetSlotValue("frameOpacity"))
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

local function GetFormattedText(result)
	if not result or result.current == nil or result.max == nil then
		return nil
	end

	local textData
	if assignedProvider and assignedProvider.GetTextDisplayData then
		textData = assignedProvider:GetTextDisplayData(result, tostring(GetSlotValue("textNumberStyle") or "SHORT"))
	end
	if not textData then
		return nil
	end

	local mode = tostring(GetSlotValue("textMode") or "CURRENT_PERCENT")
	local currentText = textData.current or "0"
	local maxText = textData.max or "0"
	local percentText = textData.percent or "0%"
	return API.ComposeBarTextDisplay(mode, currentText, maxText, percentText)
end

local function UpdateWidgetVisualOptions()
	if not widget then
		return
	end
	widget:SetBackgroundColor(GetConfiguredBackgroundColor())
	widget:SetFrameColor(GetConfiguredFrameColor())
end

local function GetConfiguredTextColor(result)
	local opacity = tonumber(GetSlotValue("textOpacity"))
	if opacity == nil then
		opacity = 1
	end
	if opacity < 0 then
		opacity = 0
	elseif opacity > 1 then
		opacity = 1
	end

	local source = tostring(GetSlotValue("textColorSource") or "CUSTOM")
	if source == "CLASS" then
		local r, g, b = API.GetPlayerClassColor()
		return r, g, b, opacity
	end
	if source == "PROVIDER" and result and result.barColor then
		return result.barColor.r or 1, result.barColor.g or 1, result.barColor.b or 1, opacity
	end

	local color = GetSlotColorTable("textColor") or { r = 1, g = 1, b = 1, a = 1 }
	return color.r or 1, color.g or 1, color.b or 1, opacity
end

local function ApplyTextOptions(result)
	if not text or not moduleFrame then
		return
	end

	local font = GetSlotValue("textFont") or "Fonts\\FRIZQT__.TTF"
	local fontSize = tonumber(GetSlotValue("textSize")) or 12
	local fontOutline = GetSlotValue("textOutline") or "OUTLINE"
	text:SetFont(font, fontSize, fontOutline)

	local r, g, b, a = GetConfiguredTextColor(result)
	text:SetTextColor(r, g, b, a)

	local offsetX = tonumber(GetSlotValue("textOffsetX")) or 0
	local offsetY = tonumber(GetSlotValue("textOffsetY")) or 0
	text:ClearAllPoints()
	text:SetPoint("CENTER", moduleFrame, "CENTER", offsetX, offsetY)
end

local function ApplyAssignments()
	if assignedProvider and assignedProvider.Disable then
		assignedProvider:Disable()
	end

	assignedProvider = nil
	assignedProviderID = NormalizeProviderID(GetSlotValue("provider"))
	if assignedProviderID ~= "NONE" then
		assignedProvider = BarProviders:Get(assignedProviderID)
	end

	if isEnabled and assignedProvider and assignedProvider.Enable then
		assignedProvider:Enable()
	end
end

function BarSlots:ApplyLayout()
	if not moduleFrame or not widget then
		return
	end

	ApplyFrameLevel()

	local radius = GetDBValue("cast_radius") or 40
	local scale = GetSlotValue("scale") or 1
	local width = math.max(1, RoundToPixel((radius * 2) * scale))
	local height = math.max(1, RoundToPixel(width * BAR_TEXTURE_ASPECT))
	local offsetX = RoundToPixel(GetSlotValue("offsetX") or 0)
	local offsetY = RoundToPixel(GetSlotValue("offsetY") or 0)
	local centerY = RoundToPixel(radius + (height * 0.5) + BAR_BASE_OFFSET_Y + offsetY)

	moduleFrame:ClearAllPoints()
	moduleFrame:SetPoint("CENTER", AnchorFrame:GetFrame(), "CENTER", offsetX, centerY)
	moduleFrame:SetSize(width, height)
	moduleFrame:SetAlpha(1)

	widget:SetSize(width, height)
	UpdateWidgetVisualOptions()
	ApplyTextOptions()
end

local function RefreshBar()
	if not widget then
		return
	end

	if not isEnabled or not assignedProvider or not IsModuleVisibleByRules() then
		HideModuleFrame()
		return
	end

	local result = assignedProvider:GetStatus()
	if not result or result.show == false or result.current == nil or result.max == nil then
		HideModuleFrame()
		return
	end

	widget:SetBarColor(GetConfiguredBarColor(result))
	UpdateWidgetVisualOptions()
	ApplyTextOptions(result)

	if text then
		if GetSlotBool("textEnabled") then
			text:SetText(GetFormattedText(result) or "")
			text:Show()
		else
			text:Hide()
		end
	end

	if widget:SetValueRange(result.current, result.max) then
		ShowModuleFrame()
		widget:Show()
	else
		HideModuleFrame()
	end
end

function BarSlots:UpdateVisibility()
	RefreshBar()
end

function BarSlots:Initialize()
	if moduleFrame then
		return
	end

	local anchor = AnchorFrame:GetFrame()
	local layerRoot = (HUDLayers and HUDLayers:GetLayerFrame(HUDLayers.Names.BAR_SLOTS)) or anchor
	moduleFrame = CreateFrame("Frame", nil, layerRoot)
	moduleFrame:Hide()

	widget = addon.BarSlotWidget:Create({
		parent = moduleFrame,
		width = 1,
		height = 1,
		backgroundBase = "bar_background",
		fillBase = "bar_fill_expanded",
		frameBase = "bar_frame",
		barColor = GetSlotColorTable("barColor"),
		backgroundColor = GetConfiguredBackgroundColor(),
		frameColor = GetConfiguredFrameColor(),
	})
	widget:AttachTo(moduleFrame)
	widget:GetFrame():SetAllPoints(moduleFrame)

	text = moduleFrame:CreateFontString(nil, "OVERLAY")
	text:Hide()

	ApplyFrameLevel()

	self:ApplyLayout()
end

local function EnableModule(enabled)
	isEnabled = enabled and true or false

	if enabled then
		if not moduleFrame then
			BarSlots:Initialize()
		end
		ApplyAssignments()
		BarSlots:ApplyLayout()
		EL:RegisterEvent("PLAYER_ENTERING_WORLD")
		EL:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		EL:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		EL:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
		EL:RegisterUnitEvent("UNIT_HEALTH", "player")
		EL:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
		EL:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
		EL:RegisterUnitEvent("UNIT_MAXPOWER", "player")
		RefreshBar()
	else
		if assignedProvider and assignedProvider.Disable then
			assignedProvider:Disable()
		end
		EL:UnregisterAllEvents()
		HideModuleFrame()
	end
end

function BarSlots:PLAYER_ENTERING_WORLD()
	RefreshBar()
end

function BarSlots:PLAYER_SPECIALIZATION_CHANGED()
	RefreshBar()
end

function BarSlots:UPDATE_SHAPESHIFT_FORM()
	RefreshBar()
end

function BarSlots:UNIT_DISPLAYPOWER(event, unit)
	if unit ~= "player" then
		return
	end
	RefreshBar()
end

function BarSlots:UNIT_HEALTH(event, unit)
	if unit ~= "player" then
		return
	end
	if assignedProviderID == "HEALTH" then
		RefreshBar()
	end
end

function BarSlots:UNIT_MAXHEALTH(event, unit)
	if unit ~= "player" then
		return
	end
	if assignedProviderID == "HEALTH" then
		RefreshBar()
	end
end

function BarSlots:UNIT_POWER_UPDATE(event, unit)
	if unit ~= "player" then
		return
	end
	if assignedProviderID == "MANA" then
		RefreshBar()
	end
end

function BarSlots:UNIT_MAXPOWER(event, unit)
	if unit ~= "player" then
		return
	end
	if assignedProviderID == "MANA" then
		RefreshBar()
	end
end

for _, key in ipairs({
	"cast_radius",
	"moduleEnabled_Cast",
	SlotKey("offsetX"),
	SlotKey("offsetY"),
	SlotKey("scale"),
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		BarSlots:ApplyLayout()
	end)
end

for _, key in ipairs({
	SlotKey("fillColorSource"),
	SlotKey("barColor"),
	SlotKey("fillOpacity"),
	SlotKey("backgroundColor"),
	SlotKey("backgroundOpacity"),
	SlotKey("frameColor"),
	SlotKey("frameOpacity"),
	SlotKey("textEnabled"),
	SlotKey("textMode"),
	SlotKey("textNumberStyle"),
	SlotKey("textColorSource"),
	SlotKey("textFont"),
	SlotKey("textSize"),
	SlotKey("textOutline"),
	SlotKey("textColor"),
	SlotKey("textOpacity"),
	SlotKey("textOffsetX"),
	SlotKey("textOffsetY"),
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ApplyTextOptions()
		UpdateWidgetVisualOptions()
		RefreshBar()
	end)
end

CallbackRegistry:RegisterSettingCallback(SlotKey("provider"), function()
	ApplyAssignments()
	RefreshBar()
end)

for _, key in ipairs({
	"barslots_visibility",
	"barslots_visibilitySource",
	"visibility_mode",
	"visibility_hideOnUIHover",
	"barslots_hideOnUIHover",
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
	ApplyFrameLevel()
end, BarSlots)

EL:SetScript("OnEvent", function(self, event, ...)
	if BarSlots[event] then
		BarSlots[event](BarSlots, event, ...)
	end
end)

addon.ControlCenter:AddModule({
	name = L["Bar Slots"] or "Bar Slots",
	dbKey = "moduleEnabled_BarSlots",
	description = L["Bar Slots Description"] or "Displays curved top bar slots above the cast ring",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 2,
})
