-- SparkPoint ClassResource Module
-- Controller for pluggable class-resource systems.

local _, addon = ...
local L = addon.L
local ClassResourceSystems = addon.ClassResourceSystems
local ResourceModel = addon.ResourceModel
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local HUDLayers = addon.HUDLayers
local Visibility = addon.Visibility
local Transition = addon.Transition
local GetDBValue = addon.GetDBValue

local EL = CreateFrame("Frame")

local ClassResource = {}
addon.Modules.ClassResourceObj = ClassResource

local isEnabled = false
local container = nil
local activeResource = nil
local activeSystem = nil
local activeSystemID = nil

local function CallMethod(obj, method, ...)
	if not obj then
		return false
	end

	local fn = obj[method]
	if type(fn) ~= "function" then
		return false
	end

	return pcall(fn, obj, ...)
end

local function CallPredicate(obj, method, ...)
	local ok, result = CallMethod(obj, method, ...)
	if not ok then
		return false
	end

	return result and true or false
end

local function EnsureContainer()
	if container then
		return
	end

	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	local layerRoot = (HUDLayers and HUDLayers:GetLayerFrame(HUDLayers.Names.CLASS_RESOURCE)) or anchor
	container = CreateFrame("Frame", nil, layerRoot)
	container:SetFrameLevel(layerRoot:GetFrameLevel() or 0)
	container:SetSize(1, 1)
	container:Hide()
end

local function ReleaseAnchorIfUnused()
	if not container or not container:IsShown() then
		AnchorFrame:Hide("classresource")
	end
end

local function ShowContainer()
	if not container then
		return
	end

	AnchorFrame:Show("classresource")
	local targetAlpha = 1
	local opacity = GetDBValue("classresource_opacity")
	if type(opacity) == "number" then
		targetAlpha = math.max(0, math.min(1, opacity))
	end

	if Transition and Transition.ShowFrame then
		Transition:ShowFrame(container, { toAlpha = targetAlpha })
	else
		container:SetAlpha(targetAlpha)
		container:Show()
	end
end

local function HideContainer()
	if not container then
		ReleaseAnchorIfUnused()
		return
	end

	local restoreAlpha = 1
	local opacity = GetDBValue("classresource_opacity")
	if type(opacity) == "number" then
		restoreAlpha = math.max(0, math.min(1, opacity))
	end

	if Transition and Transition.HideFrame then
		Transition:HideFrame(container, { restoreAlpha = restoreAlpha, onComplete = ReleaseAnchorIfUnused })
	else
		container:SetAlpha(restoreAlpha)
		container:Hide()
		ReleaseAnchorIfUnused()
	end
end

local function ShutdownActiveSystem()
	if activeSystem then
		CallMethod(activeSystem, "Shutdown")
	end

	activeSystem = nil
	activeSystemID = nil
end

local function EnsureActiveSystem(systemID)
	if activeSystem and activeSystemID == systemID then
		return activeSystem
	end

	ShutdownActiveSystem()
	if not systemID then
		return nil
	end

	local system = ClassResourceSystems and ClassResourceSystems:Create(systemID, { parentFrame = container })
	if not system then
		return nil
	end

	activeSystem = system
	activeSystemID = systemID
	CallMethod(activeSystem, "Initialize", container)
	return activeSystem
end

local function DetectActiveResource()
	return ResourceModel:GetCurrentClassResource("player")
end

local function ResolveRendererSystemID(resource)
	if not resource then
		return nil
	end

	local rendererMode = GetDBValue("classresource_rendererMode") or "CLASSIC"
	if rendererMode == "SIMPLE" and resource.simpleSupport ~= ResourceModel.SimpleSupport.NONE and resource.simpleSystemID then
		return resource.simpleSystemID
	end

	return resource.systemID
end

function ClassResource:ApplyLayout()
	local anchor = AnchorFrame:GetFrame()
	if not anchor or not container then
		return
	end

	local offsetX = GetDBValue("classresource_offsetX") or 0
	local offsetY = GetDBValue("classresource_offsetY") or 0
	local scale = GetDBValue("classresource_scale") or 1
	local opacity = GetDBValue("classresource_opacity")
	if opacity == nil then
		opacity = 1
	end

	container:ClearAllPoints()
	container:SetPoint("CENTER", anchor, "CENTER", offsetX, offsetY)
	container:SetScale(scale)
	container:SetAlpha(opacity)
	if container:GetParent() then
		container:SetFrameLevel(container:GetParent():GetFrameLevel() or 0)
	end

	CallMethod(activeSystem, "ApplyLayout")
end

function ClassResource:ApplyVisualOptions()
	CallMethod(activeSystem, "ApplyVisualOptions")
end

function ClassResource:UpdateVisibility()
	local shouldShow = isEnabled and activeResource and Visibility:ShouldShow("classresource")
	CallMethod(activeSystem, "SetVisible", shouldShow and true or false)

	if shouldShow then
		ShowContainer()
	else
		HideContainer()
	end
end

function ClassResource:Sync()
	if not isEnabled or not activeResource then
		return
	end

	CallMethod(activeSystem, "Sync")
end

function ClassResource:Refresh()
	if not isEnabled then
		return
	end

	EnsureContainer()

	local resource, resolved = DetectActiveResource()
	activeResource = resource

	if not resource then
		ShutdownActiveSystem()
		self:UpdateVisibility()
		return
	end

	local system = EnsureActiveSystem(ResolveRendererSystemID(resource))
	if not system then
		activeResource = nil
		self:UpdateVisibility()
		return
	end

	CallMethod(system, "SetResource", resource, resolved)
	self:ApplyLayout()
	self:ApplyVisualOptions()
	self:UpdateVisibility()
	self:Sync()
end

function ClassResource:PLAYER_ENTERING_WORLD()
	self:Refresh()
end

function ClassResource:PLAYER_SPECIALIZATION_CHANGED()
	self:Refresh()
end

function ClassResource:UPDATE_SHAPESHIFT_FORM()
	self:Refresh()
end

function ClassResource:UNIT_DISPLAYPOWER(event, unit)
	if unit == "player" then
		self:Refresh()
	end
end

function ClassResource:UNIT_POWER_UPDATE(event, unit, powerToken)
	if CallPredicate(activeSystem, "WantsEvent", event) then
		CallMethod(activeSystem, "HandleEvent", event, unit, powerToken)
	end
end

function ClassResource:UNIT_POWER_FREQUENT(event, unit, powerToken)
	if CallPredicate(activeSystem, "WantsEvent", event) then
		CallMethod(activeSystem, "HandleEvent", event, unit, powerToken)
	end
end

function ClassResource:UNIT_MAXPOWER(event, unit, powerToken)
	if CallPredicate(activeSystem, "WantsEvent", event) then
		CallMethod(activeSystem, "HandleEvent", event, unit, powerToken)
	end
end

function ClassResource:UNIT_AURA(event, unit)
	if CallPredicate(activeSystem, "WantsEvent", event) then
		CallMethod(activeSystem, "HandleEvent", event, unit)
	end
end

function ClassResource:UNIT_POWER_POINT_CHARGE(event, unit, powerToken)
	if CallPredicate(activeSystem, "WantsEvent", event) then
		CallMethod(activeSystem, "HandleEvent", event, unit, powerToken)
	end
end

function ClassResource:RUNE_POWER_UPDATE(event)
	if CallPredicate(activeSystem, "WantsEvent", event) then
		CallMethod(activeSystem, "HandleEvent", event)
	end
end

local function EnableModule(enabled)
	isEnabled = enabled and true or false

	if enabled then
		EL:RegisterEvent("PLAYER_ENTERING_WORLD")
		EL:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		EL:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		EL:RegisterEvent("RUNE_POWER_UPDATE")
		EL:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
		EL:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
		EL:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
		EL:RegisterUnitEvent("UNIT_MAXPOWER", "player")
		EL:RegisterUnitEvent("UNIT_AURA", "player")
		EL:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")

		ClassResource:Refresh()
	else
		EL:UnregisterAllEvents()
		ShutdownActiveSystem()
		activeResource = nil
		HideContainer()
	end
end

EL:SetScript("OnEvent", function(_, event, ...)
	if ClassResource[event] then
		ClassResource[event](ClassResource, event, ...)
	end
end)

for _, key in ipairs({
	"classresource_scale",
	"classresource_opacity",
	"classresource_offsetX",
	"classresource_offsetY",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ClassResource:ApplyLayout()
	end)
end

CallbackRegistry:RegisterSettingCallback("classresource_visibility", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("classresource_visibilitySource", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("visibility_mode", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("visibility_hideOnUIHover", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("classresource_hideOnUIHover", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("attachToMouse", function()
	ClassResource:UpdateVisibility()
end)

for _, key in ipairs({ "classresource_fillColor", "classresource_fillColorSource", "classresource_backgroundColor" }) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ClassResource:ApplyVisualOptions()
		ClassResource:Sync()
	end)
end

CallbackRegistry:RegisterSettingCallback("classresource_rendererMode", function()
	if isEnabled then
		ClassResource:Refresh()
	end
end)

CallbackRegistry:Register("VisibilityContextChanged", function()
	ClassResource:UpdateVisibility()
end, ClassResource)

addon.ControlCenter:AddModule({
	name = L["Class Resource"] or "Class Resource",
	dbKey = "moduleEnabled_ClassResource",
	description = L["Class Resource Description"] or "Displays class resources near the cursor",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 3,
})
