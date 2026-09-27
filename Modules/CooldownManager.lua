-- SparkPoint Cooldown Manager
--
-- Controller only. It resolves entries, picks a render mode per category and
-- routes events. It must never accumulate per-spell or per-category branches --
-- that is the mistake recorded in .skills/.private/class-resource.md.
--
-- Both styles show Blizzard's own viewer at the cursor. SPARKPOINT_STYLE is also
-- skinned to the SparkPoint icon look by Core/CooldownViewerSkin.lua. The SparkPoint
-- icon renderer (Modules/CooldownManagerRenderer.lua) is dormant: no mode routes to it.

local _, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local HUDLayers = addon.HUDLayers
local Visibility = addon.Visibility
local Data = addon.CooldownViewerData
local Anchor = addon.CooldownViewerAnchor
local Skin = addon.CooldownViewerSkin
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool

local CooldownManager = {}
addon.Modules.CooldownManagerObj = CooldownManager

local GROUPS = {
	{ key = "essential", category = 0 },
	{ key = "utility", category = 1 },
	{ key = "trackedbuff", category = 2 },
}

-- SparkPoint's CallbackRegistry has no unregister (Core/Initialization.lua exposes only
-- Register / RegisterSettingCallback / Trigger), so every callback this module installs is
-- permanent. Without an enabled flag a DISABLED module would still react to setting writes
-- and data events, re-attaching Blizzard's viewers and recreating widgets. moduleFrame is a
-- useless guard for this: it is created once and never nil'd. Modules/AssistedHighlight.lua
-- keeps the same flag for the same reason.
local moduleEnabled = false
local moduleFrame
-- The mode ApplyOptions applied per group ("OFF" when hidden). UpdateVisibility reads this.
local resolvedModeByGroup = {}
local structuralPending = false

local STRUCTURAL_DEBOUNCE = 0.2

-- Gap between the cast ring's outer edge and the first group, and between stacked
-- groups. cast_radius is the ring's OUTER radius (Cast.lua sizes the ring frame
-- texture radius * 2).
local GAP = 8

-- Per placement: how the first group in a slot hangs off the ring, and how each
-- following group chains to the previous one. {point, relativePoint, dx, dy}; dx/dy
-- are multiplied by the ring reach (first) or GAP (chain).
local SLOT_ANCHORS = {
	RIGHT = { first = { "LEFT", "CENTER", 1, 0 }, chain = { "TOPLEFT", "BOTTOMLEFT", 0, -1 } },
	LEFT = { first = { "RIGHT", "CENTER", -1, 0 }, chain = { "TOPRIGHT", "BOTTOMRIGHT", 0, -1 } },
	BELOW = { first = { "TOP", "CENTER", 0, -1 }, chain = { "TOP", "BOTTOM", 0, -1 } },
	ABOVE = { first = { "BOTTOM", "CENTER", 0, 1 }, chain = { "BOTTOM", "TOP", 0, 1 } },
}

local function GroupSetting(key, suffix)
	return GetDBValue("cooldownmanager_" .. key .. "_" .. suffix)
end

local VALID_PLACEMENT = { RIGHT = true, LEFT = true, BELOW = true, ABOVE = true }

local VALID_MODE = { SPARKPOINT_STYLE = true, BLIZZARD_STYLE = true }

-- No degradation (spec D10): with the Cooldown Manager off Blizzard builds no data
-- for either style; the settings page notice explains the requirement. No migration
-- of pre-skin values (never released): an unknown stored value resolves to OFF.
local function ResolveMode(group)
	local mode = tostring(GroupSetting(group.key, "mode") or "SPARKPOINT_STYLE")
	return VALID_MODE[mode] and mode or "OFF"
end

local function ResolvePlacement(group)
	local placement = tostring(GroupSetting(group.key, "placement") or "RIGHT")
	return VALID_PLACEMENT[placement] and placement or "RIGHT"
end

-- First group in a slot hangs off the ring; later ones chain to the previous group's
-- frame (our container, or a Blizzard viewer). No Blizzard geometry is ever read.
local function ComputeAnchor(group, placement, previous)
	local spec = SLOT_ANCHORS[placement]
	local nudgeX = tonumber(GroupSetting(group.key, "nudgeX")) or 0
	local nudgeY = tonumber(GroupSetting(group.key, "nudgeY")) or 0
	if previous then
		local c = spec.chain
		return c[1], previous, c[2], c[3] * GAP + nudgeX, c[4] * GAP + nudgeY
	end
	local reach = (tonumber(GetDBValue("cast_radius")) or 40) + GAP
	local f = spec.first
	return f[1], moduleFrame, f[2], f[3] * reach + nudgeX, f[4] * reach + nudgeY
end

function CooldownManager:ApplyOptions()
	if not moduleEnabled or not moduleFrame then
		return
	end
	local lastInSlot = {}
	-- GROUPS order is the stack order within a slot: Essential, Utility, Tracked Buffs.
	for _, group in ipairs(GROUPS) do
		local mode = ResolveMode(group)
		resolvedModeByGroup[group.key] = mode

		if mode == "OFF" then
			Skin:SetCategoryEnabled(group.category, false)
			Anchor:Detach(group.category)
		else
			local placement = ResolvePlacement(group)
			local point, relativeTo, relativePoint, x, y = ComputeAnchor(group, placement, lastInSlot[placement])
			Anchor:Attach(group.category, point, relativeTo, relativePoint, x, y)
			-- A missing viewer is treated as absent: the chain skips it.
			lastInSlot[placement] = Anchor:GetViewer(group.category) or lastInSlot[placement]
			Skin:SetCategoryEnabled(group.category, mode == "SPARKPOINT_STYLE")
		end
	end
	self:UpdateVisibility()
end

function CooldownManager:UpdateVisibility()
	if not moduleEnabled or not moduleFrame then
		return
	end
	local show = Visibility:ShouldShow("cooldownmanager")
	moduleFrame:SetShown(show)
	for _, group in ipairs(GROUPS) do
		if resolvedModeByGroup[group.key] ~= "OFF" then
			Anchor:SetVisible(group.category, show)
		end
	end
	if show then
		AnchorFrame:Show("cooldownmanager")
	else
		AnchorFrame:Hide("cooldownmanager")
	end
end

local function RequestStructuralRefresh()
	if structuralPending then
		return
	end
	structuralPending = true
	C_Timer.After(STRUCTURAL_DEBOUNCE, function()
		structuralPending = false
		-- Data:Refresh gates itself on combat and records a pending request; the
		-- PLAYER_REGEN_ENABLED registration below replays it.
		Data:Refresh()
	end)
end

function CooldownManager:Initialize()
	local layerRoot = HUDLayers:GetLayerFrame(HUDLayers.Names.COOLDOWN_MANAGER)
	if not layerRoot then
		return
	end

	moduleFrame = CreateFrame("Frame", nil, layerRoot)
	moduleFrame:SetAllPoints()
	moduleFrame:Hide()

	-- No ApplyOptions here: EnableModule calls it immediately after Initialize, and
	-- Data:Refresh fires CooldownViewer.EntriesChanged which calls it too.
	Data:Refresh()
end

local EL = CreateFrame("Frame")

local KEYBIND_EVENTS = {
	UPDATE_BINDINGS = true,
	ACTIONBAR_SLOT_CHANGED = true,
	ACTIONBAR_PAGE_CHANGED = true,
}

EL:SetScript("OnEvent", function(_, event)
	if KEYBIND_EVENTS[event] then
		addon.Keybinds:InvalidateCaches()
		Skin:Refresh()
		return
	end
	-- PLAYER_REGEN_ENABLED fires after every fight regardless of whether a Refresh was
	-- actually dropped for combat; without this every combat exit paid for a full
	-- rebuild (ReleaseWidgets + per-icon ApplyOptions) for nothing. This is an event
	-- branch, not a per-category one -- Invariant 2 holds.
	if event == "PLAYER_REGEN_ENABLED" and not Data:HasPendingRefresh() then
		return
	end
	if event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
		-- Talent overrides change the spell (and so the keybind) in place.
		Skin:Refresh()
	end
	RequestStructuralRefresh()
end)

local function EnableModule(enabled)
	moduleEnabled = enabled == true
	if enabled then
		if not moduleFrame then
			CooldownManager:Initialize()
		end
		Skin:SetModuleEnabled(true)
		EL:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
		EL:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
		EL:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
		EL:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		EL:RegisterEvent("SPELLS_CHANGED")
		EL:RegisterEvent("PLAYER_REGEN_ENABLED")
		-- Keybind text goes stale after any rebind without these; AssistedHighlight
		-- registers the same three.
		EL:RegisterEvent("UPDATE_BINDINGS")
		EL:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
		EL:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
		if EventRegistry then
			EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", RequestStructuralRefresh, CooldownManager)
		end
		Anchor:InstallAllHooks()
		Anchor:SetGlobalHidden(GetDBBool("cooldownmanager_hideBlizzardViewers"))
		CooldownManager:ApplyOptions()
	else
		EL:UnregisterAllEvents()
		-- EventRegistry is a separate registry; EL:UnregisterAllEvents does not cover it,
		-- and leaving it bound means Blizzard's CDM settings UI keeps waking a disabled
		-- module. Same pairing as .clones/Cooldown-Companion/Core/Lifecycle.lua:175/312.
		if EventRegistry then
			EventRegistry:UnregisterCallback("CooldownViewerSettings.OnDataChanged", CooldownManager)
		end
		Skin:SetModuleEnabled(false)
		-- Restore Blizzard's own frames before letting go of them.
		Anchor:SetGlobalHidden(false)
		Anchor:DetachAll()
		if moduleFrame then
			moduleFrame:Hide()
		end
		AnchorFrame:Hide("cooldownmanager")
	end
end

local settingKeys = {
	"cooldownmanager_showKeybind",
	"cooldownmanager_glowOnReady",
	"cooldownmanager_textSize",
	"cooldownmanager_keybindColor",
	"cooldownmanager_timerColor",
	"cooldownmanager_countColor",
	"cooldownmanager_glowColor",
	-- Groups are placed from the cast ring's outer edge; follow a resized ring.
	"cast_radius",
}
for _, group in ipairs(GROUPS) do
	for _, suffix in ipairs({ "mode", "placement", "nudgeX", "nudgeY" }) do
		settingKeys[#settingKeys + 1] = "cooldownmanager_" .. group.key .. "_" .. suffix
	end
end
for _, key in ipairs(settingKeys) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		CooldownManager:ApplyOptions()
	end, CooldownManager)
end

CallbackRegistry:Register("CooldownViewer.EntriesChanged", function()
	CooldownManager:ApplyOptions()
end, CooldownManager)

-- RefreshLayout fires constantly (every full aura update); only act while a Data
-- refresh is actually waiting on Blizzard's display data.
CallbackRegistry:Register("CooldownViewer.LayoutRefreshed", function()
	if moduleEnabled and Data:HasPendingDisplayData() then
		RequestStructuralRefresh()
	end
end, CooldownManager)

CallbackRegistry:RegisterSettingCallback("cooldownmanager_hideBlizzardViewers", function()
	-- Guarded for the same reason as ApplyOptions: CallbackRegistry has no unregister, so a
	-- write to this key while the module is disabled would still SetAlpha Blizzard's frames.
	if not moduleEnabled then
		return
	end
	Anchor:SetGlobalHidden(GetDBBool("cooldownmanager_hideBlizzardViewers"))
end, CooldownManager)

CallbackRegistry:Register("VisibilityContextChanged", function()
	CooldownManager:UpdateVisibility()
end, CooldownManager)

addon.ControlCenter:AddModule({
	name = L["Cooldown Manager"] or "Cooldown Manager",
	dbKey = "moduleEnabled_CooldownManager",
	description = L["Cooldown Manager Description"] or "Mirrors Blizzard's Cooldown Manager into the SparkPoint HUD",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 8,
})
