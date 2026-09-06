-- SparkPoint Cooldown Viewer Anchor -- BLIZZARD render mode.
--
-- Positions Blizzard's own Cooldown Manager viewers onto the SparkPoint anchor so
-- Blizzard's untainted code keeps rendering aura timers and stack counts that
-- addon code cannot compute (see Core/CooldownViewerBridge.lua).
--
-- ============================ READ BEFORE EDITING ============================
-- NEVER call SetParent on a viewer. It looks like the obvious way to make the
-- viewer follow the HUD, and it is the broken one.
--
-- Reparenting onto SparkPointAnchor means SparkPoint's own anchor:Show() runs
-- Blizzard's CooldownViewerMixin:OnShow inside OUR tainted execution context.
-- That chain reaches auraInstanceIDToItemFramesMap, which Blizzard hardens with
-- settablesecurity(..., Enum.TableSecurityOption.DisallowTaintedAccess) in
-- CooldownViewerSecure.lua, and throws:
--
--   CooldownViewer.lua:1692: attempted to index a table that cannot be accessed
--   while tainted (execution tainted by 'SparkPoint')
--
-- Because the anchor shows and hides on every visibility change, that is a
-- continuous error storm, not a one-off. Measured in game 2026-09-06.
--
-- SetPoint and SetAlpha are pure widget calls that execute no Blizzard Lua, so
-- position and visibility are both safe. Parentage is not.
-- =============================================================================

local _, addon = ...
local AnchorFrame = addon.AnchorFrame
local Bridge = addon.CooldownViewerBridge

local CooldownViewerAnchor = {}
addon.CooldownViewerAnchor = CooldownViewerAnchor

local VIEWER_BY_CATEGORY = {
	[0] = "EssentialCooldownViewer",
	[1] = "UtilityCooldownViewer",
	[2] = "BuffIconCooldownViewer",
}

local attached = {}
local alphaGuard = {}
local hooked = {}
local globalHidden = false
local editModeSuspended = false

local function GetViewer(category)
	local name = VIEWER_BY_CATEGORY[category]
	return name and _G[name] or nil
end

-- Core/AnchorFrame.lua:68 defines the same check as a file-local function; it is
-- never assigned onto the AnchorFrame table, so `AnchorFrame:IsBlizzardEditModeActive()`
-- does not exist and would error if called. Mirrored here instead of widening
-- AnchorFrame's public surface for this file's single caller below.
local function IsBlizzardEditModeActive()
	if not EditModeManagerFrame then
		return false
	end
	if EditModeManagerFrame.IsEditModeActive then
		return EditModeManagerFrame:IsEditModeActive() and true or false
	end
	return EditModeManagerFrame:IsShown() and true or false
end

local function ApplyPoint(category)
	local viewer = GetViewer(category)
	local state = attached[category]
	if not viewer or not state then
		return
	end
	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	viewer.ignoreFramePositionManager = true

	pcall(function()
		viewer:ClearAllPoints()
		-- Parent stays UIParent. See the header comment.
		viewer:SetParent(UIParent)
		viewer:SetPoint("CENTER", anchor, "CENTER", state.offsetX, state.offsetY)
	end)
end

-- Blizzard recycles item frames (itemFramePool:ReleaseAll() then re-Acquire,
-- CooldownViewer.lua:2026-2032), so any cached spell->frame lookup goes stale on
-- every layout refresh. Hook pattern from
-- .clones/Cooldown-Companion/Core/Lifecycle.lua:201-210
local function InstallHooks(category)
	local viewer = GetViewer(category)
	if not viewer or hooked[category] then
		return
	end
	hooked[category] = true

	hooksecurefunc(viewer, "SetAlpha", function(frame)
		if alphaGuard[frame] then
			return
		end
		local state = attached[category]
		local wantHidden = (state and state.hidden) or (not state and globalHidden)
		if wantHidden then
			alphaGuard[frame] = true
			frame:SetAlpha(0)
			alphaGuard[frame] = nil
		end
	end)

	hooksecurefunc(viewer, "RefreshLayout", function(frame)
		Bridge:InvalidateFrameMap()
		if attached[category] then
			ApplyPoint(category)
		end
		CooldownViewerAnchor:ApplyGlobalHidden()
		-- Blizzard's OnAcquireItemFrame calls SetTooltipsShown(true) on every newly
		-- pooled child, so mouse suppression must be re-applied after each recycle.
		-- Out of combat only. From .clones/Cooldown-Companion/Core/Lifecycle.lua:201-210
		if globalHidden and not InCombatLockdown() then
			for _, child in pairs({ frame:GetChildren() }) do
				pcall(child.SetMouseMotionEnabled, child, false)
			end
		end
	end)
end

-- ApplyGlobalHidden is referenced by the hooks above before it is defined at load
-- time; both run only after this file finishes loading, so the forward reference is
-- fine. Declared here for readability.
function CooldownViewerAnchor:Attach(category, offsetX, offsetY)
	if not GetViewer(category) then
		return
	end
	attached[category] = attached[category] or {}
	attached[category].offsetX = offsetX or 0
	attached[category].offsetY = offsetY or 0
	InstallHooks(category)
	ApplyPoint(category)
end

function CooldownViewerAnchor:Detach(category)
	local viewer = GetViewer(category)
	attached[category] = nil
	if not viewer then
		return
	end
	viewer.ignoreFramePositionManager = nil
	alphaGuard[viewer] = true
	pcall(viewer.SetAlpha, viewer, 1)
	alphaGuard[viewer] = nil
	-- Blizzard's position manager reclaims placement on its next layout pass.
end

function CooldownViewerAnchor:DetachAll()
	for category in pairs(VIEWER_BY_CATEGORY) do
		self:Detach(category)
	end
end

-- Fades EVERY viewer, including categories in SPARKPOINT mode whose frames we do
-- not otherwise touch. Without this, a SPARKPOINT category leaves Blizzard's own
-- viewer drawn at its normal screen position and the player sees the same icons
-- twice. Mirrors .clones/Cooldown-Companion/Core/Lifecycle.lua:186-200 (cdmHidden).
function CooldownViewerAnchor:SetGlobalHidden(hidden)
	globalHidden = hidden and true or false
	self:ApplyGlobalHidden()
end

function CooldownViewerAnchor:ApplyGlobalHidden()
	for category, name in pairs(VIEWER_BY_CATEGORY) do
		local viewer = _G[name]
		-- Attached categories have their own visibility driven by SetVisible.
		if viewer and not attached[category] then
			alphaGuard[viewer] = true
			pcall(viewer.SetAlpha, viewer, globalHidden and 0 or 1)
			alphaGuard[viewer] = nil
			if globalHidden and not InCombatLockdown() then
				for _, child in pairs({ viewer:GetChildren() }) do
					pcall(child.SetMouseMotionEnabled, child, false)
				end
			end
		end
	end
end

function CooldownViewerAnchor:SetVisible(category, visible)
	local viewer = GetViewer(category)
	local state = attached[category]
	if not viewer or not state then
		return
	end
	state.hidden = not visible
	alphaGuard[viewer] = true
	pcall(viewer.SetAlpha, viewer, visible and 1 or 0)
	alphaGuard[viewer] = nil
end

-- While the player is in EditMode we must NOT re-assert our anchor -- doing so
-- fights their drag and makes the frame impossible to position. Release it for the
-- duration and restore afterwards. IsBlizzardEditModeActive above mirrors the check
-- Core/AnchorFrame.lua:68 performs internally (that one is a file-local there, not a
-- method on AnchorFrame, so it cannot be reused directly).
function CooldownViewerAnchor:SuspendForEditMode(suspended)
	editModeSuspended = suspended and true or false
	if editModeSuspended then
		for category in pairs(attached) do
			local viewer = GetViewer(category)
			if viewer then
				viewer.ignoreFramePositionManager = nil
			end
		end
		return
	end
	for category in pairs(attached) do
		ApplyPoint(category)
	end
end

local EL = CreateFrame("Frame")
EL:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
EL:RegisterEvent("PLAYER_ENTERING_WORLD")
EL:RegisterEvent("PLAYER_REGEN_ENABLED")
EL:SetScript("OnEvent", function()
	if editModeSuspended or IsBlizzardEditModeActive() then
		return
	end
	-- EditMode re-anchors managed systems on layout apply; re-assert ours.
	for category in pairs(attached) do
		ApplyPoint(category)
	end
	CooldownViewerAnchor:ApplyGlobalHidden()
end)
