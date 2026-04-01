-- SparkPoint PerformanceStats Module
-- Shows SparkPoint addon memory and CPU usage near the HUD anchor.

local addonName, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local HUDLayers = addon.HUDLayers
local Visibility = addon.Visibility
local Transition = addon.Transition
local GetDBValue = addon.GetDBValue
local GetDBColor = addon.GetDBColor

local PerformanceStats = {}
addon.Modules.PerformanceStatsObj = PerformanceStats

local moduleFrame
local statsText
local isEnabled = false
local cpuElapsed = 0
local memoryElapsed = 0
local cachedMemoryText = "0KB"
local cachedCPUText = nil

local CPU_UPDATE_INTERVAL = 0.5
local MEMORY_UPDATE_INTERVAL = 10.0
local MODULE_PREFIX = "performancestats"
local DEFAULT_FONT = "Fonts\\ARIALN.TTF"

local function ApplyLayering()
	if not moduleFrame then
		return
	end

	local parent = moduleFrame:GetParent()
	if not parent then
		return
	end

	if parent.GetFrameStrata then
		moduleFrame:SetFrameStrata(parent:GetFrameStrata())
	end
	moduleFrame:SetFrameLevel(parent:GetFrameLevel() or 0)
end

local function FormatMemoryText(valueKB)
	if type(valueKB) ~= "number" or valueKB < 0 then
		return "n/a"
	end

	if valueKB >= 1024 then
		return string.format("%.1fMB", valueKB / 1024)
	end

	return string.format("%.0fKB", valueKB)
end

local function FormatCPUText(valueMs)
	if type(valueMs) ~= "number" or valueMs < 0 then
		return nil
	end

	if valueMs >= 10 then
		return string.format("%.1fms", valueMs)
	elseif valueMs >= 1 then
		return string.format("%.2fms", valueMs)
	end

	return string.format("%.3fms", valueMs)
end

local function FormatCPUPercent(value)
	if type(value) ~= "number" or value < 0 then
		return nil
	end

	local percent = value * 100
	if percent >= 10 then
		return string.format("%.0f%%", percent)
	elseif percent >= 1 then
		return string.format("%.1f%%", percent)
	elseif percent >= 0.1 then
		return string.format("%.2f%%", percent)
	end

	return "0%"
end

local function RefreshDisplayText()
	if not statsText then
		return
	end

	local parts = {
		"SP",
		cachedMemoryText or "n/a",
	}

	if cachedCPUText and cachedCPUText ~= "" then
		parts[#parts + 1] = cachedCPUText
	end

	statsText:SetText(table.concat(parts, " "))
end

local function RefreshMemorySample()
	if UpdateAddOnMemoryUsage then
		UpdateAddOnMemoryUsage()
	end

	local usage = GetAddOnMemoryUsage and GetAddOnMemoryUsage(addonName)
	cachedMemoryText = FormatMemoryText(usage)
end

local function RefreshCPUSample()
	if not (C_AddOnProfiler and C_AddOnProfiler.IsEnabled and C_AddOnProfiler.GetAddOnMetric) then
		cachedCPUText = nil
		return
	end

	if not C_AddOnProfiler.IsEnabled() then
		cachedCPUText = nil
		return
	end

	local metric = Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric.RecentAverageTime
	if not metric then
		cachedCPUText = nil
		return
	end

	local addonValue = C_AddOnProfiler.GetAddOnMetric(addonName, metric)
	local cpuParts = {}
	local cpuMsText = FormatCPUText(addonValue)
	if cpuMsText then
		cpuParts[#cpuParts + 1] = cpuMsText
	end

	if C_AddOnProfiler.GetApplicationMetric and C_AddOnProfiler.GetOverallMetric then
		local appValue = C_AddOnProfiler.GetApplicationMetric(metric)
		local overallValue = C_AddOnProfiler.GetOverallMetric(metric)
		local relativeTotal = appValue - overallValue + addonValue
		if relativeTotal > 0 then
			local cpuPercentText = FormatCPUPercent(addonValue / relativeTotal)
			if cpuPercentText then
				cpuParts[#cpuParts + 1] = cpuPercentText
			end
		end
	end

	cachedCPUText = #cpuParts > 0 and table.concat(cpuParts, " ") or nil
end

local function RefreshSamples(forceMemory, forceCPU)
	if forceMemory then
		RefreshMemorySample()
	end

	if forceCPU then
		RefreshCPUSample()
	end

	RefreshDisplayText()
end

local function OnUpdate(_, elapsed)
	local shouldRefreshMemory = false
	local shouldRefreshCPU = false

	cpuElapsed = cpuElapsed + (elapsed or 0)
	memoryElapsed = memoryElapsed + (elapsed or 0)

	if cpuElapsed >= CPU_UPDATE_INTERVAL then
		cpuElapsed = cpuElapsed - CPU_UPDATE_INTERVAL
		shouldRefreshCPU = true
	end

	if memoryElapsed >= MEMORY_UPDATE_INTERVAL then
		memoryElapsed = memoryElapsed - MEMORY_UPDATE_INTERVAL
		shouldRefreshMemory = true
	end

	if shouldRefreshMemory or shouldRefreshCPU then
		RefreshSamples(shouldRefreshMemory, shouldRefreshCPU)
	end
end

local function OnShow()
	cpuElapsed = 0
	memoryElapsed = 0
	RefreshSamples(true, true)
	moduleFrame:SetScript("OnUpdate", OnUpdate)
end

local function OnHide()
	moduleFrame:SetScript("OnUpdate", nil)
end

local function ShowModuleFrame()
	if not moduleFrame then
		return
	end

	AnchorFrame:Show(MODULE_PREFIX)
	if Transition and Transition.ShowFrame then
		Transition:ShowFrame(moduleFrame)
	else
		moduleFrame:Show()
	end
end

local function HideModuleFrame()
	if not moduleFrame then
		AnchorFrame:Hide(MODULE_PREFIX)
		return
	end

	local function ReleaseAnchor()
		if not moduleFrame:IsShown() then
			AnchorFrame:Hide(MODULE_PREFIX)
		end
	end

	if Transition and Transition.HideFrame then
		Transition:HideFrame(moduleFrame, { onComplete = ReleaseAnchor })
	else
		moduleFrame:Hide()
		ReleaseAnchor()
	end
end

function PerformanceStats:ApplyLayout()
	if not (moduleFrame and AnchorFrame:GetFrame()) then
		return
	end

	moduleFrame:ClearAllPoints()
	moduleFrame:SetPoint("CENTER", AnchorFrame:GetFrame(), "CENTER", GetDBValue("performancestats_offsetX") or 0, GetDBValue("performancestats_offsetY") or 0)
end

function PerformanceStats:ApplyOptions()
	if not statsText then
		return
	end

	local font = GetDBValue("performancestats_font") or DEFAULT_FONT
	local size = GetDBValue("performancestats_size") or 11
	local outline = GetDBValue("performancestats_outline") or "OUTLINE"
	local r, g, b, a = GetDBColor("performancestats_color")

	statsText:SetFont(font, size, outline)
	statsText:SetTextColor(r, g, b, a)
	RefreshDisplayText()
end

function PerformanceStats:UpdateVisibility()
	if not moduleFrame then
		return
	end

	if not isEnabled then
		HideModuleFrame()
		return
	end

	if Visibility and not Visibility:ShouldShow(MODULE_PREFIX) then
		HideModuleFrame()
		return
	end

	ShowModuleFrame()
end

function PerformanceStats:Initialize()
	if moduleFrame then
		return
	end

	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	local layerRoot = (HUDLayers and HUDLayers:GetLayerFrame(HUDLayers.Names.ASSISTED_HIGHLIGHT)) or anchor
	moduleFrame = CreateFrame("Frame", nil, layerRoot)
	moduleFrame:SetSize(1, 1)
	moduleFrame:Hide()
	moduleFrame:SetScript("OnShow", OnShow)
	moduleFrame:SetScript("OnHide", OnHide)
	ApplyLayering()

	statsText = moduleFrame:CreateFontString(nil, "OVERLAY")
	statsText:SetPoint("CENTER")
	statsText:SetJustifyH("LEFT")
	statsText:SetFont(DEFAULT_FONT, 11, "OUTLINE")
	statsText:SetText("")

	self:ApplyLayout()
	self:ApplyOptions()
end

local function EnableModule(enabled)
	isEnabled = enabled and true or false

	if enabled then
		PerformanceStats:Initialize()
		PerformanceStats:ApplyLayout()
		PerformanceStats:ApplyOptions()
		PerformanceStats:UpdateVisibility()
	else
		HideModuleFrame()
	end
end

for _, key in ipairs({
	"performancestats_offsetX",
	"performancestats_offsetY",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		PerformanceStats:ApplyLayout()
	end)
end

for _, key in ipairs({
	"performancestats_font",
	"performancestats_outline",
	"performancestats_size",
	"performancestats_color",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		PerformanceStats:ApplyOptions()
	end)
end

for _, key in ipairs({
	"visibility_mode",
	"visibility_hideOnUIHover",
	"visibility_hideInPetBattle",
	"visibility_hideInSpecialActionBarContext",
	"performancestats_visibilitySource",
	"performancestats_visibility",
	"performancestats_hideOnUIHover",
	"performancestats_hideInPetBattle",
	"performancestats_hideInSpecialActionBarContext",
	"attachToMouse",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		PerformanceStats:UpdateVisibility()
	end)
end

CallbackRegistry:Register("VisibilityContextChanged", function()
	PerformanceStats:UpdateVisibility()
end, PerformanceStats)

CallbackRegistry:Register("HUDLayersChanged", function()
	ApplyLayering()
end, PerformanceStats)

addon.ControlCenter:AddModule({
	name = L["Performance Stats"] or "Performance Stats",
	dbKey = "moduleEnabled_PerformanceStats",
	description = L["Performance Stats Description"] or "Shows SparkPoint addon memory and CPU usage near the cursor",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 7,
})
