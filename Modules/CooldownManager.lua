-- SparkPoint Cooldown Manager
--
-- Controller only. It resolves entries, picks a render mode per category and
-- routes events. It must never accumulate per-spell or per-category branches --
-- that is the mistake recorded in .skills/.private/class-resource.md.
--
-- SPARKPOINT mode draws our own icons. BLIZZARD mode positions Blizzard's viewer.
-- Tracked Buff defaults to BLIZZARD because aura timers and stack counts are
-- unreachable from addon code; see Core/CooldownViewerBridge.lua.

local _, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local HUDLayers = addon.HUDLayers
local Visibility = addon.Visibility
local Data = addon.CooldownViewerData
local Anchor = addon.CooldownViewerAnchor
local IconWidget = addon.CooldownIconWidget
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
local groupFrames = {}
local widgetPool = {}
local activeWidgets = {}
local structuralPending = false
local stateDirty = false
local elapsedAccum = 0

local STATE_TICK = 0.1
local STRUCTURAL_DEBOUNCE = 0.2

local function GroupSetting(key, suffix)
	return GetDBValue("cooldownmanager_" .. key .. "_" .. suffix)
end

local function AcquireWidget(parent)
	local widget = table.remove(widgetPool)
	if not widget then
		widget = IconWidget:Create(parent)
	end
	widget.frame:SetParent(parent)
	return widget
end

local function ReleaseWidgets(groupKey)
	local list = activeWidgets[groupKey]
	if not list then
		return
	end
	for _, widget in ipairs(list) do
		widget:Release()
		widgetPool[#widgetPool + 1] = widget
	end
	activeWidgets[groupKey] = {}
end

local function LayoutGroup(group)
	local parent = groupFrames[group.key]
	if not parent then
		return
	end

	ReleaseWidgets(group.key)

	local entries = Data:GetEntries(group.category)
	local size = tonumber(GroupSetting(group.key, "iconSize")) or 28
	local spacing = tonumber(GroupSetting(group.key, "spacing")) or 4
	local wrap = tonumber(GroupSetting(group.key, "wrapCount")) or 5
	local direction = tostring(GroupSetting(group.key, "direction") or "RIGHT")
	local stepX = (direction == "LEFT") and -(size + spacing) or (size + spacing)
	local rowStep = -(size + spacing)

	local list = activeWidgets[group.key] or {}
	activeWidgets[group.key] = list

	for index, entry in ipairs(entries) do
		local widget = AcquireWidget(parent)
		widget:SetEntry(entry)
		widget:ApplyOptions({
			size = size,
			showKeybind = GroupSetting(group.key, "showKeybind") == true,
			keybindFormat = "COMPACT",
		})

		local column = (index - 1) % wrap
		local row = math.floor((index - 1) / wrap)
		widget.frame:ClearAllPoints()
		widget.frame:SetPoint("CENTER", parent, "CENTER", column * stepX, row * rowStep)
		widget:UpdateState()
		widget:SetShown(true)
		list[#list + 1] = widget
	end
end

local function ApplyGroupMode(group)
	local enabled = GroupSetting(group.key, "enabled") == true
	local mode = tostring(GroupSetting(group.key, "mode") or "SPARKPOINT")
	local offsetX = tonumber(GroupSetting(group.key, "offsetX")) or 0
	local offsetY = tonumber(GroupSetting(group.key, "offsetY")) or 0

	-- Spec degradation: with cooldownViewerEnabled off the viewers exist but never
	-- update, so BLIZZARD mode would render a frozen, empty frame. Fall back to our
	-- own renderer rather than showing nothing. IsBlizzardModeUsable is a pure read
	-- (IsAvailable + GetCVar), so it is safe to call here unconditionally, including
	-- in combat.
	if mode == "BLIZZARD" and not Data:IsBlizzardModeUsable() then
		mode = "SPARKPOINT"
	end

	if not enabled or mode == "OFF" then
		ReleaseWidgets(group.key)
		Anchor:Detach(group.category)
		if groupFrames[group.key] then
			groupFrames[group.key]:Hide()
		end
		return
	end

	if mode == "BLIZZARD" then
		ReleaseWidgets(group.key)
		if groupFrames[group.key] then
			groupFrames[group.key]:Hide()
		end
		Anchor:Attach(group.category, offsetX, offsetY)
		return
	end

	Anchor:Detach(group.category)
	local parent = groupFrames[group.key]
	if parent then
		parent:ClearAllPoints()
		parent:SetPoint("CENTER", moduleFrame, "CENTER", offsetX, offsetY)
		parent:Show()
	end
	LayoutGroup(group)
end

function CooldownManager:ApplyOptions()
	if not moduleEnabled or not moduleFrame then
		return
	end
	for _, group in ipairs(GROUPS) do
		ApplyGroupMode(group)
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
		if tostring(GroupSetting(group.key, "mode") or "") == "BLIZZARD" then
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
		CooldownManager:ApplyOptions()
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

	for _, group in ipairs(GROUPS) do
		local frame = CreateFrame("Frame", nil, moduleFrame)
		frame:SetSize(1, 1)
		frame:Hide()
		groupFrames[group.key] = frame
		activeWidgets[group.key] = {}
	end

	moduleFrame:SetScript("OnUpdate", function(_, elapsed)
		elapsedAccum = elapsedAccum + elapsed
		if elapsedAccum < STATE_TICK then
			return
		end
		elapsedAccum = 0
		if not stateDirty then
			return
		end
		stateDirty = false
		for _, group in ipairs(GROUPS) do
			for _, widget in ipairs(activeWidgets[group.key] or {}) do
				widget:UpdateState()
			end
		end
	end)

	-- No ApplyOptions here: EnableModule calls it immediately after Initialize, and
	-- Data:Refresh fires CooldownViewer.EntriesChanged which calls it too.
	Data:Refresh()
end

local EL = CreateFrame("Frame")

function CooldownManager:MarkStateDirty()
	stateDirty = true
end

local STATE_EVENTS = {
	SPELL_UPDATE_COOLDOWN = true,
	SPELL_UPDATE_CHARGES = true,
	SPELL_UPDATE_USES = true,
	SPELL_UPDATE_ICON = true,
	UNIT_AURA = true,
}

local KEYBIND_EVENTS = {
	UPDATE_BINDINGS = true,
	ACTIONBAR_SLOT_CHANGED = true,
	ACTIONBAR_PAGE_CHANGED = true,
}

EL:SetScript("OnEvent", function(_, event)
	if STATE_EVENTS[event] then
		-- UNIT_AURA is a payload-free signal. Never inspect its arguments.
		CooldownManager:MarkStateDirty()
		return
	end
	if KEYBIND_EVENTS[event] then
		addon.Keybinds:InvalidateCaches()
		CooldownManager:MarkStateDirty()
		return
	end
	RequestStructuralRefresh()
end)

local function EnableModule(enabled)
	moduleEnabled = enabled == true
	if enabled then
		if not moduleFrame then
			CooldownManager:Initialize()
		end
		EL:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
		EL:RegisterEvent("COOLDOWN_VIEWER_TABLE_HOTFIXED")
		EL:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
		EL:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		EL:RegisterEvent("SPELLS_CHANGED")
		EL:RegisterEvent("PLAYER_REGEN_ENABLED")
		EL:RegisterEvent("SPELL_UPDATE_COOLDOWN")
		EL:RegisterEvent("SPELL_UPDATE_CHARGES")
		EL:RegisterEvent("SPELL_UPDATE_USES")
		EL:RegisterEvent("SPELL_UPDATE_ICON")
		EL:RegisterUnitEvent("UNIT_AURA", "player")
		-- Keybind text goes stale after any rebind without these; AssistedHighlight
		-- registers the same three.
		EL:RegisterEvent("UPDATE_BINDINGS")
		EL:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
		EL:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
		if EventRegistry then
			EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", RequestStructuralRefresh, CooldownManager)
		end
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
		-- Restore Blizzard's own frames before letting go of them.
		Anchor:SetGlobalHidden(false)
		Anchor:DetachAll()
		for _, group in ipairs(GROUPS) do
			ReleaseWidgets(group.key)
		end
		if moduleFrame then
			moduleFrame:Hide()
		end
		AnchorFrame:Hide("cooldownmanager")
	end
end

local settingKeys = {
	"cooldownmanager_iconOpacity",
	"cooldownmanager_showSwipe",
	"cooldownmanager_showTimerText",
	"cooldownmanager_desaturateOnCooldown",
	"cooldownmanager_glowOnReady",
	"cooldownmanager_glowColor",
}
for _, group in ipairs(GROUPS) do
	for _, suffix in ipairs({ "mode", "enabled", "offsetX", "offsetY", "iconSize", "spacing", "direction", "wrapCount", "showKeybind" }) do
		settingKeys[#settingKeys + 1] = "cooldownmanager_" .. group.key .. "_" .. suffix
	end
end
for _, key in ipairs(settingKeys) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		CooldownManager:ApplyOptions()
	end, CooldownManager)
end

-- cooldownmanager_hiddenEntries is deliberately NOT in settingKeys. SetHidden writes
-- the key (firing SettingChanged synchronously) and only then rebuilds entries, so an
-- ApplyOptions driven by the setting would lay out against the stale pre-filter list
-- and the corrected one would never be drawn. Relayout on the data event instead.
CallbackRegistry:Register("CooldownViewer.EntriesChanged", function()
	CooldownManager:ApplyOptions()
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
