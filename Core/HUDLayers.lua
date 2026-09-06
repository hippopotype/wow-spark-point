-- SparkPoint HUD Layers
-- Centralized addon-scoped layer roots under the shared anchor frame.

local _, addon = ...
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local GetDBValue = addon.GetDBValue
local UIParent = UIParent

local HUDLayers = {}
addon.HUDLayers = HUDLayers

local layerRoots = {}

HUDLayers.Names = {
	CAST_SHADOW = "CAST_SHADOW",
	DECORATIVE_RING = "DECORATIVE_RING",
	CAST_FEEDBACK = "CAST_FEEDBACK",
	BAR_SLOTS = "BAR_SLOTS",
	CAST_BASE = "CAST_BASE",
	CLASS_RESOURCE = "CLASS_RESOURCE",
	COOLDOWN_MANAGER = "COOLDOWN_MANAGER",
	ASSISTED_HIGHLIGHT = "ASSISTED_HIGHLIGHT",
}

local LAYER_ORDER = {
	HUDLayers.Names.CAST_SHADOW,
	HUDLayers.Names.DECORATIVE_RING,
	HUDLayers.Names.CAST_FEEDBACK,
	HUDLayers.Names.BAR_SLOTS,
	HUDLayers.Names.CAST_BASE,
	HUDLayers.Names.CLASS_RESOURCE,
	HUDLayers.Names.COOLDOWN_MANAGER,
	HUDLayers.Names.ASSISTED_HIGHLIGHT,
}

local LAYER_LEVELS = {
	[HUDLayers.Names.CAST_SHADOW] = 5,
	[HUDLayers.Names.DECORATIVE_RING] = 10,
	[HUDLayers.Names.CAST_FEEDBACK] = 15,
	[HUDLayers.Names.BAR_SLOTS] = 20,
	[HUDLayers.Names.CAST_BASE] = 30,
	[HUDLayers.Names.CLASS_RESOURCE] = 40,
	[HUDLayers.Names.COOLDOWN_MANAGER] = 45,
	[HUDLayers.Names.ASSISTED_HIGHLIGHT] = 50,
}

local function GetRootStrata()
	local strata = tostring(GetDBValue("hud_frameStrata") or "HIGH")
	if strata == "" then
		return "HIGH"
	end
	return strata
end

local function ApplyRootStrata()
	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	local strata = GetRootStrata()
	anchor:SetFrameStrata(strata)

	for _, name in ipairs(LAYER_ORDER) do
		local frame = layerRoots[name]
		if frame then
			frame:SetFrameStrata(strata)
		end
	end

	CallbackRegistry:Trigger("HUDLayersChanged", strata)
end

local function EnsureLayerRoots()
	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	for _, name in ipairs(LAYER_ORDER) do
		if not layerRoots[name] then
			local frame = CreateFrame("Frame", nil, UIParent)
			frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
			frame:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
			frame:SetFrameLevel(LAYER_LEVELS[name] or 0)
			layerRoots[name] = frame
		end
	end

	ApplyRootStrata()
end

function HUDLayers:GetLayerLevel(name)
	return LAYER_LEVELS[name]
end

function HUDLayers:GetLayerFrame(name)
	EnsureLayerRoots()
	return layerRoots[name]
end

CallbackRegistry:Register("ADDON_LOADED", function()
	EnsureLayerRoots()
end)

CallbackRegistry:RegisterSettingCallback("hud_frameStrata", function()
	ApplyRootStrata()
end)
