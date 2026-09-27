-- SparkPoint Cooldown Viewer Anchor -- BLIZZARD render mode.
--
-- Positions Blizzard's own Cooldown Manager viewers onto the SparkPoint anchor so
-- Blizzard's untainted code keeps rendering aura timers and stack counts that
-- addon code cannot compute (see Core/CooldownViewerBridge.lua).
--
-- ============================ READ BEFORE EDITING ============================
-- NEVER parent a viewer to anything but UIParent. Parenting it to SparkPointAnchor
-- looks like the obvious way to make it follow the HUD, and it is the broken one.
-- SetParent(UIParent) is the one permitted reparent: it is how Blizzard's own
-- BreakFromFrameManager (EditModeSystemTemplates.lua:336-343) takes a viewer out of
-- BottomManagedFrameContainer's layout, and without it that container re-anchors the
-- viewer on every Layout pass.
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
-- SetAlpha is a pure widget call that executes no Blizzard Lua, so visibility is
-- safe. Position is safe only through the native Frame SetPoint/ClearAllPoints
-- (below): cooldown viewers are Edit Mode systems whose own SetPoint/ClearAllPoints
-- are Lua overrides, so calling viewer:SetPoint directly runs Blizzard Lua under our
-- taint. Parentage is safe only to UIParent (E13).
-- =============================================================================

-- E14 (measured 2026-09-26): writing viewer.ignoreFramePositionManager from addon code
-- TAINTS. ManagedFrameMixin:OnShow reads it before CooldownViewerMixin:OnShow, so a
-- hidden->shown transition of an attached viewer (Edit Mode "In Combat" visibility)
-- ran RefreshLayout tainted, and Edit Mode enter/exit read it too. Replaced by the
-- BottomManagedFrameContainer:UpdateFrame post-hook below. Never write fields on a
-- Blizzard frame table. Viewer SetPoint/ClearAllPoints are Edit Mode Lua overrides
-- that write snappedToFrame; call the native Frame methods.

local _, addon = ...
local AnchorFrame = addon.AnchorFrame
local Bridge = addon.CooldownViewerBridge
local CallbackRegistry = addon.CallbackRegistry
local Util = addon.Util

-- Cooldown viewers are Edit Mode systems: EditModeSystemMixin.OnSystemLoad replaces
-- their SetPoint/ClearAllPoints with Lua overrides that write snappedToFrame and
-- EditModeManagerFrame.editModeSystemAnchorDirty (EditModeSystemTemplates.lua:12-17,
-- 147-156). Called from our code those writes are tainted. Always use the native
-- Frame methods, taken from UIParent (not an Edit Mode system).
local FrameSetPoint = UIParent.SetPoint
local FrameClearAllPoints = UIParent.ClearAllPoints

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
-- Per category, the screen center { x, y } where Blizzard's own layout (default
-- position, container-managed) or saved Edit Mode anchor (custom position) last
-- placed the viewer. Captured from reads only; see PinToBlizzardHome below.
local blizzardHome = {}
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
	if not viewer or not state or not state.relativeTo then
		return
	end

	pcall(function()
		FrameClearAllPoints(viewer)
		-- Take the viewer out of BottomManagedFrameContainer's layout (header). Guarded:
		-- after the first call the parent is already UIParent.
		if viewer:GetParent() ~= UIParent then
			viewer:SetParent(UIParent)
		end
		FrameSetPoint(viewer, state.point, state.relativeTo, state.relativePoint, state.offsetX, state.offsetY)
	end)
end

-- Without ignoreFramePositionManager, Blizzard's bottom container re-adopts a viewer on
-- every show (ManagedFrameMixin:OnShow -> AddManagedFrame -> UpdateFrame, which
-- SetParents it back into the container). Undo that right after, from a post-hook: a
-- hooksecurefunc body never taints the secure caller.
local managedContainerHooked = false
local function InstallManagedContainerHook()
	if managedContainerHooked then
		return
	end
	local container = _G.BottomManagedFrameContainer
	if not container or type(container.UpdateFrame) ~= "function" then
		return
	end
	managedContainerHooked = true
	hooksecurefunc(container, "UpdateFrame", function(_, frame)
		if editModeSuspended then
			return
		end
		for category in pairs(attached) do
			if GetViewer(category) == frame then
				-- Capture Blizzard's own placement (native GetCenter, pure read) before we
				-- move the viewer to the SparkPoint anchor below, so Edit Mode can later
				-- show it where Blizzard's last layout pass actually put it.
				local ok, x, y = pcall(frame.GetCenter, frame)
				if ok and Util.IsAccessibleNumber(x) and Util.IsAccessibleNumber(y) then
					blizzardHome[category] = { x = x, y = y }
				end
				ApplyPoint(category)
			end
		end
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
	InstallManagedContainerHook()

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
		-- Blizzard's RefreshLayout may have just rebuilt its display data securely
		-- (RefreshLayout :2028 -> GetCooldownIDs :2064-2067, when the provider was
		-- dirty), so a Data refresh waiting on PENDING can run now. Blizzard also
		-- rebuilds via OnCooldownDataChanged without going through RefreshLayout; that
		-- path is covered separately by the module's CooldownViewerSettings.OnDataChanged
		-- registration -- keep both.
		CallbackRegistry:Trigger("CooldownViewer.LayoutRefreshed")
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

-- Installed for every viewer when the module enables, not only attached ones: the
-- LayoutRefreshed retry must also reach SPARKPOINT-only setups. The hooks are inert
-- for unattached viewers unless hideBlizzardViewers is on.
function CooldownViewerAnchor:InstallAllHooks()
	for category in pairs(VIEWER_BY_CATEGORY) do
		InstallHooks(category)
	end
end

-- relativeTo is a SparkPoint frame or another CDM viewer (stacked slots). Either way
-- this stays one pure SetPoint -- never SetParent (header).
function CooldownViewerAnchor:Attach(category, point, relativeTo, relativePoint, offsetX, offsetY)
	if not GetViewer(category) or not relativeTo then
		return
	end
	local state = attached[category] or {}
	attached[category] = state
	state.point = point or "CENTER"
	state.relativeTo = relativeTo
	state.relativePoint = relativePoint or "CENTER"
	state.offsetX = offsetX or 0
	state.offsetY = offsetY or 0
	InstallHooks(category)
	-- Still in Blizzard's bottom container (first attach this session): its current
	-- center IS Blizzard's default slot. Capture it before we move it.
	if not blizzardHome[category] then
		local viewer = GetViewer(category)
		local okParent, parent = pcall(viewer.GetParent, viewer)
		if okParent and parent and parent == _G.BottomManagedFrameContainer then
			local ok, x, y = pcall(viewer.GetCenter, viewer)
			if ok and Util.IsAccessibleNumber(x) and Util.IsAccessibleNumber(y) then
				blizzardHome[category] = { x = x, y = y }
			end
		end
	end
	ApplyPoint(category)
end

-- For use ONLY as a SetPoint relativeTo when chaining a SparkPoint group after a
-- Blizzard-mode group. Never call methods on it.
function CooldownViewerAnchor:GetViewer(category)
	return GetViewer(category)
end

-- Edit Mode shows the viewer where Blizzard itself would put it. Pure reads of
-- systemInfo plus native SetPoint -- nothing is written to Blizzard's tables.
local function ApplyAnchorInfo(viewer, info, scale)
	if type(info) ~= "table" then
		return false
	end
	local point, relativeTo, relativePoint = info.point, info.relativeTo, info.relativePoint
	local offsetX, offsetY = info.offsetX, info.offsetY
	if type(point) ~= "string" or type(relativePoint) ~= "string" then
		return false
	end
	if not Util.IsAccessibleNumber(offsetX) or not Util.IsAccessibleNumber(offsetY) then
		return false
	end
	if type(relativeTo) ~= "string" and type(relativeTo) ~= "table" then
		return false
	end
	FrameSetPoint(viewer, point, relativeTo, relativePoint, offsetX / scale, offsetY / scale)
	return true
end

local function PinToBlizzardHome(category, viewer)
	pcall(function()
		local info = viewer.systemInfo
		local scale = viewer:GetScale()
		if not Util.IsAccessibleNumber(scale) or scale <= 0 then
			scale = 1
		end
		if type(info) == "table" and info.isInDefaultPosition == false then
			FrameClearAllPoints(viewer)
			if ApplyAnchorInfo(viewer, info.anchorInfo, scale) then
				ApplyAnchorInfo(viewer, info.anchorInfo2, scale)
				return
			end
		end
		local home = blizzardHome[category]
		local x, y
		if home then
			x, y = home.x, home.y
		else
			-- No layout pass seen yet this session: freeze in place (previous behaviour).
			x, y = viewer:GetCenter()
		end
		if Util.IsAccessibleNumber(x) and Util.IsAccessibleNumber(y) then
			FrameClearAllPoints(viewer)
			FrameSetPoint(viewer, "CENTER", UIParent, "BOTTOMLEFT", x, y)
		end
	end)
end

function CooldownViewerAnchor:Detach(category)
	local viewer = GetViewer(category)
	local wasAttached = attached[category] ~= nil
	if viewer and wasAttached then
		-- Re-home the viewer before dropping our own attached state below: Blizzard's
		-- container will not reclaim it on its own until Edit Mode or reload.
		PinToBlizzardHome(category, viewer)
	end
	attached[category] = nil
	if not viewer then
		return
	end
	alphaGuard[viewer] = true
	-- Respect globalHidden: with hideBlizzardViewers on, forcing alpha 1 here would pop
	-- this viewer back to its own screen position and leave it visible until the next
	-- RefreshLayout or loading screen re-applies ApplyGlobalHidden.
	pcall(viewer.SetAlpha, viewer, globalHidden and 0 or 1)
	alphaGuard[viewer] = nil
	-- Detached viewers are pinned at Blizzard's saved Edit Mode position (stored anchor
	-- when moved, captured container slot otherwise); Blizzard re-adopts it on its next
	-- UpdateManagedFrames/Edit Mode apply.
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

-- ApplyGlobalHidden is referenced by the hooks above before it is defined at load
-- time; both run only after this file finishes loading, so the forward reference is
-- fine. Declared here for readability.
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
-- fights their drag. Instead show each attached viewer at Blizzard's own saved Edit
-- Mode position: the stored anchor (systemInfo.anchorInfo) when the player has moved
-- it to a custom spot, or the container slot we captured from Blizzard's last layout
-- pass when it is still in its default position. Dragging the viewer in Edit Mode
-- updates Blizzard's own layout but does not change the SparkPoint placement, which
-- is re-applied on exit via ApplyPoint below.
function CooldownViewerAnchor:SuspendForEditMode(suspended)
	editModeSuspended = suspended and true or false
	if editModeSuspended then
		for category in pairs(attached) do
			local viewer = GetViewer(category)
			if viewer then
				PinToBlizzardHome(category, viewer)
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

-- Edit Mode enter/exit fire through EventRegistry (securecallfunction-isolated, so our
-- callback cannot taint Blizzard's caller). Core/AnchorFrame.lua uses the same events.
if EventRegistry then
	EventRegistry:RegisterCallback("EditMode.Enter", function()
		CooldownViewerAnchor:SuspendForEditMode(true)
	end, CooldownViewerAnchor)
	EventRegistry:RegisterCallback("EditMode.Exit", function()
		CooldownViewerAnchor:SuspendForEditMode(false)
	end, CooldownViewerAnchor)
end
