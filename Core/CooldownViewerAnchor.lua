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
-- Whether ApplyGlobalHidden has actually run for the CURRENT globalHidden value.
-- Without this, PLAYER_ENTERING_WORLD / PLAYER_REGEN_ENABLED / EDIT_MODE_LAYOUTS_UPDATED
-- fire ApplyGlobalHidden unconditionally, and with no attached categories that resolves
-- to SetAlpha(1) on all three CDM viewers on every login and combat exit -- even though
-- the module defaults to disabled and hideBlizzardViewers defaults to off. See I2 in the
-- cooldown-manager-hud fix wave.
local globalHiddenApplied = false

local function GetViewer(category)
	local name = VIEWER_BY_CATEGORY[category]
	return name and _G[name] or nil
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
		-- Parent stays UIParent (see the header comment), but ApplyPoint runs from
		-- Attach, SuspendForEditMode(false), the event handler below, AND Blizzard's own
		-- RefreshLayout hook -- including in combat. After the first call the parent is
		-- already UIParent, so guard the call rather than pay for it (and its exposure
		-- to Blizzard's layout pass) on every one of those paths.
		if viewer:GetParent() ~= UIParent then
			viewer:SetParent(UIParent)
		end
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
			-- pcall, like every other alpha write in this file: an unguarded throw here
			-- would leave alphaGuard[frame] permanently true, silently swallowing every
			-- later alpha change on this frame.
			pcall(frame.SetAlpha, frame, 0)
			alphaGuard[frame] = nil
		end
	end)

	hooksecurefunc(viewer, "RefreshLayout", function(frame)
		Bridge:InvalidateFrameMap()
		-- Do not re-anchor while the player is dragging in EditMode; a Blizzard
		-- layout refresh mid-drag would fight them for the frame.
		if attached[category] and not editModeSuspended then
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
	-- Respect globalHidden: with hideBlizzardViewers on, forcing alpha 1 here would pop
	-- this viewer back to its own screen position and leave it visible until the next
	-- RefreshLayout or loading screen re-applies ApplyGlobalHidden.
	pcall(viewer.SetAlpha, viewer, globalHidden and 0 or 1)
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
	-- Nothing attached and nothing to hide or un-hide: skip the SetAlpha(1) that would
	-- otherwise run on all three CDM viewers on every login and combat exit while this
	-- module sits at its disabled default.
	if not globalHidden and not globalHiddenApplied then
		return
	end
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
	globalHiddenApplied = globalHidden
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
-- duration and restore afterwards.
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
	local editing = AnchorFrame:IsBlizzardEditModeActive()
	-- EditMode re-anchors managed systems on layout apply; SuspendForEditMode(false)
	-- already re-asserts ApplyPoint for every attached category, so doing it again here
	-- would be redundant.
	CooldownViewerAnchor:SuspendForEditMode(editing)
	if editing then
		return
	end
	-- Nothing attached and nothing hidden to (re)apply: see the guard in ApplyGlobalHidden.
	if not next(attached) and not globalHidden and not globalHiddenApplied then
		return
	end
	CooldownViewerAnchor:ApplyGlobalHidden()
end)
