-- SparkPoint Bar Slots Module
-- Displays curved horizontal top bar slots above the main cast ring.

local _, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local Visibility = addon.Visibility
local Transition = addon.Transition
local BarProviders = addon.BarProviders
local GetDBValue = addon.GetDBValue
local GetDBColorTable = addon.GetDBColorTable

local BAR_TEXTURE_WIDTH = 1024
local BAR_TEXTURE_HEIGHT = 400
local BAR_TEXTURE_ASPECT = BAR_TEXTURE_HEIGHT / BAR_TEXTURE_WIDTH
local MODULE_PREFIX = "barslots"
local BAR_BASE_OFFSET_Y = -20
local EL = CreateFrame("Frame")

local BarSlots = {}
addon.Modules.BarSlotsObj = BarSlots

local isEnabled = false
local moduleFrame
local widget
local assignedProvider
local assignedProviderID = "NONE"

local function GetResolvedFrameLevel()
	local castObj = addon.Modules and addon.Modules.CastObj
	if castObj and castObj.GetBarSlotFrameLevel then
		local level = castObj:GetBarSlotFrameLevel()
		if type(level) == "number" then
			return level
		end
	end
	return 9
end

local function ApplyFrameLevel()
	if not moduleFrame or not widget then
		return
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
		ReleaseAnchorIfUnused()
		return
	end
	if Transition and Transition.HideFrame then
		Transition:HideFrame(moduleFrame, { restoreAlpha = 1, onComplete = ReleaseAnchorIfUnused })
	else
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
	return GetDBColorTable("barslot1_barColor")
end

local function UpdateWidgetVisualOptions()
	if not widget then
		return
	end
	widget:SetBackgroundColor(GetDBColorTable("barslot1_backgroundColor"))
	widget:SetFrameColor(GetDBColorTable("barslot1_frameColor"))
end

local function ApplyAssignments()
	if assignedProvider and assignedProvider.Disable then
		assignedProvider:Disable()
	end

	assignedProvider = nil
	assignedProviderID = NormalizeProviderID(GetDBValue("barslot1_provider"))
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
	local scale = GetDBValue("barslot1_scale") or 1
	local width = math.max(1, (radius * 2) * scale)
	local height = math.max(1, width * BAR_TEXTURE_ASPECT)
	local offsetX = GetDBValue("barslot1_offsetX") or 0
	local offsetY = GetDBValue("barslot1_offsetY") or 0
	local centerY = radius + (height * 0.5) + BAR_BASE_OFFSET_Y + offsetY

	moduleFrame:ClearAllPoints()
	moduleFrame:SetPoint("CENTER", AnchorFrame:GetFrame(), "CENTER", offsetX, centerY)
	moduleFrame:SetSize(width, height)

	widget:SetSize(width, height)
	UpdateWidgetVisualOptions()
end

local function RefreshBar()
	if not widget then
		return
	end

	if not isEnabled or not assignedProvider or not IsModuleVisibleByRules() then
		widget:Hide()
		HideModuleFrame()
		return
	end

	local result = assignedProvider:GetStatus()
	if not result or result.show == false or result.current == nil or result.max == nil then
		widget:Hide()
		HideModuleFrame()
		return
	end

	widget:SetBarColor(GetConfiguredBarColor(result))
	UpdateWidgetVisualOptions()

	if widget:SetValueRange(result.current, result.max) then
		ShowModuleFrame()
		widget:Show()
	else
		widget:Hide()
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
	moduleFrame = CreateFrame("Frame", nil, anchor)
	moduleFrame:Hide()

	widget = addon.BarSlotWidget:Create({
		parent = moduleFrame,
		width = 1,
		height = 1,
		backgroundBase = "bar_background",
		fillBase = "bar_fill",
		frameBase = "bar_frame",
		barColor = GetDBColorTable("barslot1_barColor"),
		backgroundColor = GetDBColorTable("barslot1_backgroundColor"),
		frameColor = GetDBColorTable("barslot1_frameColor"),
	})
	widget:AttachTo(moduleFrame)
	widget:GetFrame():SetAllPoints(moduleFrame)
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
	"barslot1_offsetX",
	"barslot1_offsetY",
	"barslot1_scale",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		BarSlots:ApplyLayout()
	end)
end

for _, key in ipairs({
	"barslot1_barColor",
	"barslot1_backgroundColor",
	"barslot1_frameColor",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		UpdateWidgetVisualOptions()
		RefreshBar()
	end)
end

CallbackRegistry:RegisterSettingCallback("barslot1_provider", function()
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
