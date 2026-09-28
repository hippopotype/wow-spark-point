-- SparkPoint Cooldown Manager -- SparkPoint icon renderer (render strategy)
--
-- ============================== STATUS: DORMANT ==============================
-- This renderer draws SparkPoint's own icons for Blizzard Cooldown Manager entries.
-- Since the skin rework (docs/superpowers/specs/2026-09-27-cooldown-manager-skin-design.md)
-- no mode routes to it: every shown group uses Blizzard's own viewer, skinned by
-- Core/CooldownViewerSkin.lua. It is kept, isolated and lint-clean so it can be
-- plugged back in as an option.
--
-- Support by category:
--   Essential   FULL  -- cooldown swipe, availability desaturation, ready glow, keybinds
--   Utility     FULL  -- same
--   TrackedBuff STATE-ONLY -- lit when the buff is up, desaturated when down;
--                             no swipe, no countdown, no stack count
--
-- Why Tracked Buffs are limited (measured in game, see the 2026-09-06 spec):
--   E8  C_UnitAuras.GetAuraDuration / GetAuraApplicationDisplayCount error for
--       tainted callers ("Auras cannot be accessed when secret while tainted").
--   E7  the item frame's GetApplicationsText() errors in combat.
--   Charges (C_Spell.GetSpellCharges) are secret when cooldowns are restricted.
--
-- Techniques it depends on:
--   E4  identity from cooldownInfo.spellID, never itemFrame:GetSpellID() (secret).
--   E10 C_Spell.GetSpellCooldownDuration -> scratch Cooldown -> IsShown() yields a
--       plain on/off without arithmetic (Widgets/CooldownIconWidget.lua).
--   E9  buff on/off read from Blizzard's item Cooldown region IsShown() via
--       CooldownViewerBridge:GetAuraActive.
--   E11 icon via C_Spell.GetSpellTexture (cooldownInfo has no icon field).
--   Entries come from CooldownViewerData (raw display-data reads; never build
--   Blizzard's data -- CooldownViewerBridge.lua rule 3).
--
-- Known limitation: the ready glow's GCD guard samples C_Spell.GetSpellCooldown()
-- .isOnGCD from the 0.1 s state tick rather than inside a SPELL_UPDATE_COOLDOWN handler,
-- where Blizzard documents that field as untrustworthy (it is never secret, but nilable);
-- a nil read skips the ready glow for that cooldown.
-- Tracked Buffs glow with the looping proc pulse while the buff is up (was a
-- static glow before the 2026-09-27 fixes).
--
-- Integration checklist (to plug it in again):
--   1. A mode value in Modules/CooldownManager.lua ResolveMode that calls
--      Renderer:Enable(moduleFrame) once and Renderer:ShowGroup(group, placement),
--      anchoring the returned container with ComputeAnchor like a viewer.
--   2. Renderer:HideGroup for groups leaving that mode; Renderer:Disable on module
--      disable.
--   3. Call Renderer:MarkStateDirty() from the module's keybind events.
--   4. Settings UI for the renderer-only keys (Core/Defaults.lua,
--      "Dormant SparkPoint icon renderer" group).
-- =============================================================================

local _, addon = ...
local Data = addon.CooldownViewerData
local IconWidget = addon.CooldownIconWidget
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool

local Renderer = {}
addon.CooldownManagerRenderer = Renderer

local STATE_TICK = 0.1
local ICON_SPACING = 4
local GROUP_KEYS = { "essential", "utility", "trackedbuff" }

local STATE_EVENTS = {
	"SPELL_UPDATE_COOLDOWN",
	"SPELL_UPDATE_CHARGES",
	"SPELL_UPDATE_USES",
	"SPELL_UPDATE_ICON",
}

local enabled = false
local parent
local ticker
local containers = {}
local widgetPool = {}
local activeWidgets = {}
-- groupKey -> { group = group, placement = placement } for groups currently shown.
local shownGroups = {}
local stateDirty = false
local elapsedAccum = 0

local EL = CreateFrame("Frame")
EL:SetScript("OnEvent", function()
	-- UNIT_AURA is a payload-free signal. Never inspect its arguments.
	Renderer:MarkStateDirty()
end)

local function GroupSetting(key, suffix)
	return GetDBValue("cooldownmanager_" .. key .. "_" .. suffix)
end

local function AcquireWidget(container)
	local widget = table.remove(widgetPool)
	if not widget then
		widget = IconWidget:Create(container)
	end
	widget.frame:SetParent(container)
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

-- Where icon N sits inside its group container, per placement. Returns the point
-- used on both the icon and the container, plus the offset.
local function IconOffset(placement, column, row, count, wrap, size, step)
	if placement == "LEFT" then
		return "TOPRIGHT", -column * step, -row * step
	end
	if placement == "BELOW" or placement == "ABOVE" then
		local inRow = math.min(wrap, count - row * wrap)
		local rowWidth = inRow * step - ICON_SPACING
		local x = -rowWidth / 2 + size / 2 + column * step
		if placement == "BELOW" then
			return "TOP", x, -row * step
		end
		return "BOTTOM", x, row * step
	end
	return "TOPLEFT", column * step, -row * step
end

local function LayoutGroup(group, placement)
	local container = containers[group.key]
	if not container then
		return
	end

	ReleaseWidgets(group.key)

	local entries = Data:GetEntries(group.category)
	local count = #entries
	local size = tonumber(GroupSetting(group.key, "iconSize")) or 28
	local wrap = math.max(1, math.floor(tonumber(GroupSetting(group.key, "wrapCount")) or 5))
	local step = size + ICON_SPACING
	local showKeybind = GetDBBool("cooldownmanager_showKeybind")

	local list = activeWidgets[group.key] or {}
	activeWidgets[group.key] = list

	for index, entry in ipairs(entries) do
		local widget = AcquireWidget(container)
		widget:SetEntry(entry)
		widget:ApplyOptions({
			size = size,
			showKeybind = showKeybind,
			keybindFormat = "COMPACT",
		})

		local column = (index - 1) % wrap
		local row = math.floor((index - 1) / wrap)
		local point, x, y = IconOffset(placement, column, row, count, wrap, size, step)
		widget.frame:ClearAllPoints()
		widget.frame:SetPoint(point, container, point, x, y)
		widget:UpdateState()
		widget:SetShown(true)
		list[#list + 1] = widget
	end

	-- The container's edges are the chain target for the next group in the slot. An
	-- empty group keeps a 1x1 footprint so the chain does not collapse onto the ring.
	if count == 0 then
		container:SetSize(1, 1)
	else
		local columns = math.min(count, wrap)
		local rows = math.ceil(count / wrap)
		container:SetSize(columns * step - ICON_SPACING, rows * step - ICON_SPACING)
	end
end

local function OnUpdate(_, elapsed)
	elapsedAccum = elapsedAccum + elapsed
	if elapsedAccum < STATE_TICK then
		return
	end
	elapsedAccum = 0
	if not stateDirty then
		return
	end
	stateDirty = false
	for _, key in ipairs(GROUP_KEYS) do
		for _, widget in ipairs(activeWidgets[key] or {}) do
			widget:UpdateState()
		end
	end
end

function Renderer:Enable(parentFrame)
	if enabled or not parentFrame then
		return
	end
	enabled = true
	if not parent then
		parent = parentFrame
		-- The ticker is a child of the parent so the state tick stops whenever the
		-- module frame is hidden (visibility rules), exactly as before extraction.
		ticker = CreateFrame("Frame", nil, parent)
		for _, key in ipairs(GROUP_KEYS) do
			local frame = CreateFrame("Frame", nil, parent)
			frame:SetSize(1, 1)
			frame:Hide()
			containers[key] = frame
			activeWidgets[key] = {}
		end
	end
	for _, event in ipairs(STATE_EVENTS) do
		EL:RegisterEvent(event)
	end
	EL:RegisterUnitEvent("UNIT_AURA", "player")
	ticker:SetScript("OnUpdate", OnUpdate)
end

function Renderer:Disable()
	if not enabled then
		return
	end
	enabled = false
	EL:UnregisterAllEvents()
	if ticker then
		ticker:SetScript("OnUpdate", nil)
	end
	for _, key in ipairs(GROUP_KEYS) do
		self:HideGroup(key)
	end
end

function Renderer:ShowGroup(group, placement)
	if not enabled then
		return nil
	end
	local container = containers[group.key]
	if not container then
		return nil
	end
	shownGroups[group.key] = { group = group, placement = placement }
	container:Show()
	LayoutGroup(group, placement)
	return container
end

function Renderer:HideGroup(groupKey)
	shownGroups[groupKey] = nil
	ReleaseWidgets(groupKey)
	if containers[groupKey] then
		containers[groupKey]:Hide()
	end
end

function Renderer:ApplyOptions()
	if not enabled then
		return
	end
	for _, shown in pairs(shownGroups) do
		LayoutGroup(shown.group, shown.placement)
	end
end

function Renderer:MarkStateDirty()
	if enabled then
		stateDirty = true
	end
end
