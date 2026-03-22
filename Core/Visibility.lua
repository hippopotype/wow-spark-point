-- SparkPoint Visibility Service
-- Shared visibility policy evaluation for addon-level and module-level displays.

local _, addon = ...

local API = addon.API
local CallbackRegistry = addon.CallbackRegistry
local GetDBBool = addon.GetDBBool
local Transition = addon.Transition

local Visibility = {}
addon.Visibility = Visibility

Visibility.MODES = {
	ALWAYS = "ALWAYS",
	IN_COMBAT = "IN_COMBAT",
	OUT_OF_COMBAT = "OUT_OF_COMBAT",
	HAS_TARGET = "HAS_TARGET",
	TARGET_ALIVE = "TARGET_ALIVE",
	TARGET_DEAD = "TARGET_DEAD",
	TARGET_HOSTILE = "TARGET_HOSTILE",
	TARGET_NEUTRAL = "TARGET_NEUTRAL",
	TARGET_FRIENDLY = "TARGET_FRIENDLY",
	CASTING = "CASTING",
	AFTER_INSTANT_CAST = "AFTER_INSTANT_CAST",
	AFTER_TRIGGERED_INSTANT_CAST = "AFTER_TRIGGERED_INSTANT_CAST",
	IN_PARTY = "IN_PARTY",
	IN_RAID = "IN_RAID",
	IN_INSTANCE = "IN_INSTANCE",
}

Visibility.SOURCES = {
	INHERIT = "INHERIT",
	CUSTOM = "CUSTOM",
}

local VisibilityRuleOrder = {
	Visibility.MODES.ALWAYS,
	Visibility.MODES.IN_COMBAT,
	Visibility.MODES.OUT_OF_COMBAT,
	Visibility.MODES.HAS_TARGET,
	Visibility.MODES.TARGET_ALIVE,
	Visibility.MODES.TARGET_DEAD,
	Visibility.MODES.TARGET_HOSTILE,
	Visibility.MODES.TARGET_NEUTRAL,
	Visibility.MODES.TARGET_FRIENDLY,
	Visibility.MODES.CASTING,
	Visibility.MODES.AFTER_INSTANT_CAST,
	Visibility.MODES.AFTER_TRIGGERED_INSTANT_CAST,
	Visibility.MODES.IN_PARTY,
	Visibility.MODES.IN_RAID,
	Visibility.MODES.IN_INSTANCE,
}

local GCD_SPELL_ID = 61304
local MAX_GCD_WINDOW = 2
local FALLBACK_AFTER_INSTANT_CAST_DURATION = 1.0
local MAX_SYNTHETIC_AFTER_INSTANT_CAST_DURATION = 2.0
local hoverWatcher
local lastHoveringInteractiveUI = false
local UI_HOVER_PREFIXES = { "cast", "barslot_top", "classresource", "ring", "assistedhighlight" }
local hysteresisTokenByPrefix = {}
local stableVisibilityByPrefix = {}
local pendingVisibilityByPrefix = {}
local instantVisibilityStates = {
	player = { active = false, expiry = 0, timerToken = 0, refreshToken = 0 },
	triggered = { active = false, expiry = 0, timerToken = 0, refreshToken = 0 },
}

local GetMouseFoci = GetMouseFoci
local GetMouseFocus = GetMouseFocus
local UIParent = UIParent
local WorldFrame = WorldFrame
local STABLE_PREFIX_GLOBAL = "__global__"
local MOTION_SETTING_KEYS = {
	"transition_enabled",
	"transition_hysteresisShowMs",
	"transition_hysteresisHideMs",
}

local function NormalizePrefix(prefix)
	return prefix or STABLE_PREFIX_GLOBAL
end

local function GetHysteresisDurations()
	if not Transition or not Transition.GetConfig then
		return 0, 0
	end
	local cfg = Transition:GetConfig()
	if not cfg or not cfg.enabled then
		return 0, 0
	end
	return cfg.hysteresisShow or 0, cfg.hysteresisHide or 0
end

local function ResetStableVisibilityState(prefix)
	local key = NormalizePrefix(prefix)
	hysteresisTokenByPrefix[key] = (hysteresisTokenByPrefix[key] or 0) + 1
	pendingVisibilityByPrefix[key] = nil
	stableVisibilityByPrefix[key] = nil
end

local function IsValidGCDCooldown(startTime, duration)
	return type(startTime) == "number" and type(duration) == "number" and startTime > 0 and duration > 0 and duration <= MAX_GCD_WINDOW
end

local function GetInstantVisibilityState(kind)
	return instantVisibilityStates[kind]
end

local function ScheduleInstantVisibilityExpiryCheck(kind)
	local state = GetInstantVisibilityState(kind)
	if not state or not state.active then
		return
	end

	state.timerToken = state.timerToken + 1
	local token = state.timerToken
	local remaining = (state.expiry or 0) - GetTime()
	if remaining < 0 then
		remaining = 0
	end

	C_Timer.After(remaining, function()
		local latestState = GetInstantVisibilityState(kind)
		if not latestState or token ~= latestState.timerToken then
			return
		end
		if latestState.active and type(latestState.expiry) == "number" and GetTime() < latestState.expiry then
			return
		end

		local changed = latestState.active
		latestState.active = false
		latestState.expiry = 0
		if changed then
			CallbackRegistry:Trigger("VisibilityContextChanged", "AFTER_INSTANT_CAST_EXPIRE_TIMER", kind)
		end
	end)
end

local function SetInstantVisibilityState(kind, shouldBeActive, nextExpiry)
	local state = GetInstantVisibilityState(kind)
	if not state then
		return false
	end

	local changed = (state.active ~= shouldBeActive) or (shouldBeActive and math.abs((state.expiry or 0) - (nextExpiry or 0)) > 0.001)
	state.active = shouldBeActive
	state.expiry = shouldBeActive and nextExpiry or 0

	if changed and state.active then
		ScheduleInstantVisibilityExpiryCheck(kind)
	elseif changed and not state.active then
		state.timerToken = state.timerToken + 1
	end

	return changed
end

local function GetInstantVisibilityRemaining(kind)
	local state = GetInstantVisibilityState(kind)
	if not state or not state.active or type(state.expiry) ~= "number" or state.expiry <= 0 then
		return 0
	end
	return math.max(0, state.expiry - GetTime())
end

local function IsInstantVisibilityActive(kind)
	return GetInstantVisibilityRemaining(kind) > 0
end

local function RefreshInstantVisibilityFromGCD(kind, event)
	local state = GetInstantVisibilityState(kind)
	if not state then
		return false
	end

	local now = GetTime()
	local startTime, duration = 0, 0
	if API and API.GetSpellCooldown then
		startTime, duration = API.GetSpellCooldown(GCD_SPELL_ID)
	end

	local shouldBeActive = false
	local nextExpiry = 0
	if IsValidGCDCooldown(startTime, duration) then
		shouldBeActive = true
		nextExpiry = startTime + duration
	elseif state.active and type(state.expiry) == "number" and now < state.expiry then
		-- Cooldown data can lag briefly after instant casts; preserve the active window until expected end.
		shouldBeActive = true
		nextExpiry = state.expiry
	end

	local changed = SetInstantVisibilityState(kind, shouldBeActive, nextExpiry)
	if changed then
		CallbackRegistry:Trigger("VisibilityContextChanged", event, kind)
	end
	return changed
end

local function ActivateInstantVisibilityWindow(kind, duration, opts)
	local state = GetInstantVisibilityState(kind)
	if not state then
		return false
	end

	opts = opts or {}
	duration = tonumber(duration) or 0
	if duration <= 0 then
		duration = FALLBACK_AFTER_INSTANT_CAST_DURATION
	end
	if duration > MAX_SYNTHETIC_AFTER_INSTANT_CAST_DURATION then
		duration = MAX_SYNTHETIC_AFTER_INSTANT_CAST_DURATION
	end

	local nextExpiry = GetTime() + duration
	if state.active and type(state.expiry) == "number" and state.expiry > nextExpiry then
		nextExpiry = state.expiry
	end

	local changed = SetInstantVisibilityState(kind, true, nextExpiry)

	if opts.syncToGCD then
		local syncDuration = tonumber(duration) or 0
		if syncDuration <= FALLBACK_AFTER_INSTANT_CAST_DURATION + 0.001 then
			RefreshInstantVisibilityFromGCD(kind, "AFTER_INSTANT_CAST_GCD_SYNC")

			state.refreshToken = state.refreshToken + 1
			local refreshToken = state.refreshToken
			C_Timer.After(0, function()
				local latestState = GetInstantVisibilityState(kind)
				if not latestState or refreshToken ~= latestState.refreshToken then
					return
				end
				RefreshInstantVisibilityFromGCD(kind, "AFTER_INSTANT_CAST_GCD_SYNC_DEFERRED")
			end)
		end
	end

	return changed
end

function Visibility:IsAfterInstantCastActive()
	return IsInstantVisibilityActive("player")
end

function Visibility:IsAfterTriggeredInstantCastActive()
	return IsInstantVisibilityActive("triggered")
end

function Visibility:GetAfterInstantCastRemaining()
	return math.max(GetInstantVisibilityRemaining("player"), GetInstantVisibilityRemaining("triggered"))
end

function Visibility:GetInstantCastFallbackDuration()
	return FALLBACK_AFTER_INSTANT_CAST_DURATION
end

function Visibility:ActivateAfterInstantCastWindow(duration)
	return ActivateInstantVisibilityWindow("player", duration)
end

function Visibility:ActivateAfterPlayerInstantCastWindow(duration)
	return ActivateInstantVisibilityWindow("player", duration, { syncToGCD = true })
end

function Visibility:ActivateAfterTriggeredInstantCastWindow(duration)
	return ActivateInstantVisibilityWindow("triggered", duration, { syncToGCD = true })
end

local function NormalizeRules(rules)
	local normalized = {}
	if type(rules) ~= "table" then
		normalized[Visibility.MODES.ALWAYS] = true
		return normalized
	end
	for _, key in ipairs(VisibilityRuleOrder) do
		if rules[key] == true then
			normalized[key] = true
		end
	end
	-- "ALWAYS" is an exclusive rule. If any conditional rule is selected, ignore ALWAYS.
	if normalized[Visibility.MODES.ALWAYS] then
		for _, key in ipairs(VisibilityRuleOrder) do
			if key ~= Visibility.MODES.ALWAYS and normalized[key] then
				normalized[Visibility.MODES.ALWAYS] = nil
				break
			end
		end
	end
	return normalized
end

local function NormalizeSource(source)
	if source == Visibility.SOURCES.CUSTOM then
		return Visibility.SOURCES.CUSTOM
	end
	return Visibility.SOURCES.INHERIT
end

local function GetTopMouseFocus()
	if GetMouseFoci then
		local frames = GetMouseFoci()
		if frames and frames[1] then
			return frames[1]
		end
	end
	if GetMouseFocus then
		return GetMouseFocus()
	end
	return nil
end

local INTERACTIVE_OBJECT_TYPES = {
	Button = true,
	CheckButton = true,
	Slider = true,
	EditBox = true,
	PlayerModel = true,
	DressUpModel = true,
	Model = true,
}

local INTERACTIVE_MOUSE_SCRIPTS = {
	OnMouseDown = true,
	OnMouseUp = true,
	OnClick = true,
	OnDoubleClick = true,
	OnMouseWheel = true,
	OnDragStart = true,
	OnDragStop = true,
	OnReceiveDrag = true,
}

local function HasInteractiveMouseScript(frame)
	if not (frame and frame.HasScript and frame.GetScript) then
		return false
	end

	for scriptName in pairs(INTERACTIVE_MOUSE_SCRIPTS) do
		if frame:HasScript(scriptName) and frame:GetScript(scriptName) then
			return true
		end
	end

	return false
end

local function IsFrameMouseInteractive(frame)
	local current = frame
	local depth = 0

	while current and depth < 12 do
		if current.IsObjectType then
			for objectType in pairs(INTERACTIVE_OBJECT_TYPES) do
				if current:IsObjectType(objectType) then
					return true
				end
			end
		end

		if HasInteractiveMouseScript(current) then
			return true
		end

		if not current.GetParent then
			break
		end
		current = current:GetParent()
		depth = depth + 1
	end

	return false
end

function Visibility:IsHoveringInteractiveUI()
	local focus = GetTopMouseFocus()
	if not focus then
		return false
	end
	if focus == UIParent or focus == WorldFrame then
		return false
	end
	return IsFrameMouseInteractive(focus)
end

function Visibility:ShouldHideOnUIHover()
	if not (GetDBBool and GetDBBool("attachToMouse")) then
		return false
	end
	return self:IsHoveringInteractiveUI()
end

function Visibility:GetGlobalHideOnUIHover()
	return GetDBBool and GetDBBool("visibility_hideOnUIHover") or false
end

function Visibility:GetGlobalHideInPetBattle()
	return GetDBBool and GetDBBool("visibility_hideInPetBattle") or false
end

function Visibility:GetGlobalHideInSpecialActionBarContext()
	return GetDBBool and GetDBBool("visibility_hideInSpecialActionBarContext") or false
end

function Visibility:GetModuleHideOnUIHover(prefix)
	if not prefix then
		return self:GetGlobalHideOnUIHover()
	end
	if self:GetModuleSource(prefix) == Visibility.SOURCES.INHERIT then
		return self:GetGlobalHideOnUIHover()
	end
	local GetDBBoolLocal = addon.GetDBBool
	return GetDBBoolLocal and GetDBBoolLocal(prefix .. "_hideOnUIHover") or false
end

function Visibility:GetModuleHideInPetBattle(prefix)
	if not prefix then
		return self:GetGlobalHideInPetBattle()
	end
	if self:GetModuleSource(prefix) == Visibility.SOURCES.INHERIT then
		return self:GetGlobalHideInPetBattle()
	end
	local GetDBBoolLocal = addon.GetDBBool
	return GetDBBoolLocal and GetDBBoolLocal(prefix .. "_hideInPetBattle") or false
end

function Visibility:GetModuleHideInSpecialActionBarContext(prefix)
	if not prefix then
		return self:GetGlobalHideInSpecialActionBarContext()
	end
	if self:GetModuleSource(prefix) == Visibility.SOURCES.INHERIT then
		return self:GetGlobalHideInSpecialActionBarContext()
	end
	local GetDBBoolLocal = addon.GetDBBool
	return GetDBBoolLocal and GetDBBoolLocal(prefix .. "_hideInSpecialActionBarContext") or false
end

function Visibility:IsAnyHoverHideEnabled()
	if not (GetDBBool and GetDBBool("attachToMouse")) then
		return false
	end
	if self:GetGlobalHideOnUIHover() then
		return true
	end
	for _, prefix in ipairs(UI_HOVER_PREFIXES) do
		if self:GetModuleSource(prefix) == Visibility.SOURCES.CUSTOM and self:GetModuleHideOnUIHover(prefix) then
			return true
		end
	end
	return false
end

function Visibility:GetGlobalRules()
	local GetDBValue = addon.GetDBValue
	local rules = GetDBValue and GetDBValue("visibility_mode")
	return NormalizeRules(rules)
end

function Visibility:GetModuleSource(prefix)
	if not prefix then
		return Visibility.SOURCES.INHERIT
	end
	local GetDBValue = addon.GetDBValue
	local source = GetDBValue and GetDBValue(prefix .. "_visibilitySource")
	return NormalizeSource(source)
end

function Visibility:GetModuleRules(prefix)
	if not prefix then
		return self:GetGlobalRules()
	end
	if self:GetModuleSource(prefix) == Visibility.SOURCES.INHERIT then
		return self:GetGlobalRules()
	end

	local GetDBValue = addon.GetDBValue
	local rules = GetDBValue and GetDBValue(prefix .. "_visibility")
	return NormalizeRules(rules)
end

function Visibility:IsPlayerCasting()
	return UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil
end

function Visibility:IsInPetBattle()
	return C_PetBattles and C_PetBattles.IsInBattle and (C_PetBattles.IsInBattle() == true) or false
end

function Visibility:IsVehicleUIActive()
	local active = false
	if UnitHasVehicleUI then
		active = UnitHasVehicleUI("player") == true
	end
	if not active and C_ActionBar and C_ActionBar.HasVehicleActionBar then
		active = C_ActionBar.HasVehicleActionBar() == true
	end
	return active
end

function Visibility:IsOverrideActionBarActive()
	return C_ActionBar and C_ActionBar.HasOverrideActionBar and (C_ActionBar.HasOverrideActionBar() == true) or false
end

function Visibility:IsPossessBarActive()
	return C_ActionBar and C_ActionBar.IsPossessBarVisible and (C_ActionBar.IsPossessBarVisible() == true) or false
end

function Visibility:IsTempShapeshiftActionBarActive()
	return C_ActionBar and C_ActionBar.HasTempShapeshiftActionBar and (C_ActionBar.HasTempShapeshiftActionBar() == true) or false
end

function Visibility:IsSpecialActionBarContextActive()
	return self:IsVehicleUIActive() or self:IsOverrideActionBarActive() or self:IsPossessBarActive() or self:IsTempShapeshiftActionBarActive()
end

function Visibility:GetTargetDisposition()
	if not (UnitExists and UnitExists("target")) then
		return "NONE"
	end

	local reaction = UnitReaction and UnitReaction("target", "player")
	if type(reaction) == "number" then
		if reaction <= 3 then
			return "HOSTILE"
		end
		if reaction == 4 then
			return "NEUTRAL"
		end
		if reaction >= 5 then
			return "FRIENDLY"
		end
	end

	if UnitCanAttack and UnitCanAttack("target", "player") then
		return "HOSTILE"
	end

	if UnitCanAttack and UnitCanAttack("player", "target") then
		return "NEUTRAL"
	end

	if UnitIsFriend and UnitIsFriend("player", "target") then
		return "FRIENDLY"
	end

	return "NONE"
end

function Visibility:GetTargetLifeState()
	if not (UnitExists and UnitExists("target")) then
		return "NONE"
	end

	-- Matches the simple alive/dead condition split used by clone references like WeakTextures.
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("target") then
		return "DEAD"
	end

	return "ALIVE"
end

function Visibility:EvaluateTargetRules(rules)
	local hasTarget = UnitExists and UnitExists("target") and true or false
	if not hasTarget then
		return false
	end

	local wantsAnyTarget = rules[Visibility.MODES.HAS_TARGET] == true
	local wantsAlive = rules[Visibility.MODES.TARGET_ALIVE] == true
	local wantsDead = rules[Visibility.MODES.TARGET_DEAD] == true
	local wantsHostile = rules[Visibility.MODES.TARGET_HOSTILE] == true
	local wantsNeutral = rules[Visibility.MODES.TARGET_NEUTRAL] == true
	local wantsFriendly = rules[Visibility.MODES.TARGET_FRIENDLY] == true

	local hasTargetSubfilter = wantsAlive or wantsDead or wantsHostile or wantsNeutral or wantsFriendly
	if not wantsAnyTarget and not hasTargetSubfilter then
		return false
	end

	local targetLifeState = self:GetTargetLifeState()
	local targetDisposition = self:GetTargetDisposition()

	local matchesLifeState = true
	if wantsAlive or wantsDead then
		matchesLifeState = (wantsAlive and targetLifeState == "ALIVE") or (wantsDead and targetLifeState == "DEAD")
	end

	local matchesDisposition = true
	if wantsHostile or wantsNeutral or wantsFriendly then
		matchesDisposition = (wantsHostile and targetDisposition == "HOSTILE")
			or (wantsNeutral and targetDisposition == "NEUTRAL")
			or (wantsFriendly and targetDisposition == "FRIENDLY")
	end

	return matchesLifeState and matchesDisposition
end

function Visibility:EvaluateRules(rules)
	rules = NormalizeRules(rules)
	if rules[Visibility.MODES.ALWAYS] then
		return true
	end

	local inCombat = false
	if InCombatLockdown and InCombatLockdown() then
		inCombat = true
	elseif UnitAffectingCombat then
		inCombat = UnitAffectingCombat("player") and true or false
	end
	local isCasting = self:IsPlayerCasting()
	local afterInstantCast = self:IsAfterInstantCastActive()
	local afterTriggeredInstantCast = self:IsAfterTriggeredInstantCastActive()
	local inRaid = IsInRaid and IsInRaid() and true or false
	local inParty = (IsInGroup and IsInGroup()) and not inRaid or false
	local inInstance = false
	if IsInInstance then
		inInstance = IsInInstance() and true or false
	end

	if rules[Visibility.MODES.IN_COMBAT] and inCombat then
		return true
	end
	if rules[Visibility.MODES.OUT_OF_COMBAT] and not inCombat then
		return true
	end
	if self:EvaluateTargetRules(rules) then
		return true
	end
	if rules[Visibility.MODES.CASTING] and isCasting then
		return true
	end
	if rules[Visibility.MODES.AFTER_INSTANT_CAST] and afterInstantCast then
		return true
	end
	if rules[Visibility.MODES.AFTER_TRIGGERED_INSTANT_CAST] and afterTriggeredInstantCast then
		return true
	end
	if rules[Visibility.MODES.IN_PARTY] and inParty then
		return true
	end
	if rules[Visibility.MODES.IN_RAID] and inRaid then
		return true
	end
	if rules[Visibility.MODES.IN_INSTANCE] and inInstance then
		return true
	end

	return false
end

function Visibility:EvaluateRaw(prefix)
	if self:ShouldHideOnUIHover() and self:GetModuleHideOnUIHover(prefix) then
		return false
	end
	if self:IsInPetBattle() and self:GetModuleHideInPetBattle(prefix) then
		return false
	end
	if self:IsSpecialActionBarContextActive() and self:GetModuleHideInSpecialActionBarContext(prefix) then
		return false
	end
	return self:EvaluateRules(self:GetModuleRules(prefix))
end

function Visibility:ShouldShow(prefix)
	local key = NormalizePrefix(prefix)
	local raw = self:EvaluateRaw(prefix)
	local stable = stableVisibilityByPrefix[key]
	if stable == nil then
		stableVisibilityByPrefix[key] = raw
		return raw
	end

	if raw == stable then
		pendingVisibilityByPrefix[key] = nil
		return stable
	end

	local showDelay, hideDelay = GetHysteresisDurations()
	local delay = raw and showDelay or hideDelay
	if delay <= 0 then
		stableVisibilityByPrefix[key] = raw
		pendingVisibilityByPrefix[key] = nil
		return raw
	end

	local pending = pendingVisibilityByPrefix[key]
	if pending and pending.target == raw then
		return stable
	end

	hysteresisTokenByPrefix[key] = (hysteresisTokenByPrefix[key] or 0) + 1
	local token = hysteresisTokenByPrefix[key]
	pendingVisibilityByPrefix[key] = { target = raw, token = token }

	C_Timer.After(delay, function()
		if token ~= hysteresisTokenByPrefix[key] then
			return
		end
		local currentRaw = Visibility:EvaluateRaw(prefix)
		if currentRaw ~= raw then
			pendingVisibilityByPrefix[key] = nil
			return
		end
		pendingVisibilityByPrefix[key] = nil
		if stableVisibilityByPrefix[key] ~= raw then
			stableVisibilityByPrefix[key] = raw
			CallbackRegistry:Trigger("VisibilityContextChanged", "VISIBILITY_STABILIZED", prefix, raw)
		end
	end)

	return stable
end

local function EnsureHoverWatcher()
	if hoverWatcher then
		return
	end

	hoverWatcher = CreateFrame("Frame")
	hoverWatcher.elapsed = 0
	hoverWatcher:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = self.elapsed + (elapsed or 0)
		if self.elapsed < 0.05 then
			return
		end
		self.elapsed = 0

		local enabled = Visibility:IsAnyHoverHideEnabled()
		if not enabled then
			if lastHoveringInteractiveUI then
				lastHoveringInteractiveUI = false
				CallbackRegistry:Trigger("VisibilityContextChanged", "UI_HOVER_CHANGED")
			end
			return
		end

		local hoveringInteractiveUI = Visibility:IsHoveringInteractiveUI()
		if hoveringInteractiveUI ~= lastHoveringInteractiveUI then
			lastHoveringInteractiveUI = hoveringInteractiveUI
			CallbackRegistry:Trigger("VisibilityContextChanged", "UI_HOVER_CHANGED")
		end
	end)
end

local EL = CreateFrame("Frame")
EL:RegisterEvent("PLAYER_ENTERING_WORLD")
EL:RegisterEvent("PLAYER_REGEN_DISABLED")
EL:RegisterEvent("PLAYER_REGEN_ENABLED")
EL:RegisterUnitEvent("UNIT_FLAGS", "player")
EL:RegisterUnitEvent("UNIT_FLAGS", "target")
EL:RegisterUnitEvent("UNIT_HEALTH", "target")
EL:RegisterEvent("PLAYER_TARGET_CHANGED")
EL:RegisterEvent("GROUP_ROSTER_UPDATE")
EL:RegisterEvent("ZONE_CHANGED_NEW_AREA")
EL:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
EL:RegisterEvent("PET_BATTLE_OPENING_START")
EL:RegisterEvent("PET_BATTLE_CLOSE")
EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
EL:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR")
EL:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR")
EL:RegisterEvent("UPDATE_POSSESS_BAR")
EL:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
EL:RegisterEvent("ACTIONBAR_PAGE_CHANGED")

EL:SetScript("OnEvent", function(_, event, ...)
	CallbackRegistry:Trigger("VisibilityContextChanged", event, ...)
end)

EnsureHoverWatcher()

CallbackRegistry:RegisterSettingCallback("visibility_hideOnUIHover", function()
	lastHoveringInteractiveUI = Visibility:IsHoveringInteractiveUI()
	ResetStableVisibilityState(nil)
	for _, prefix in ipairs(UI_HOVER_PREFIXES) do
		ResetStableVisibilityState(prefix)
	end
	CallbackRegistry:Trigger("VisibilityContextChanged", "visibility_hideOnUIHover")
end)

CallbackRegistry:RegisterSettingCallback("visibility_hideInPetBattle", function()
	ResetStableVisibilityState(nil)
	for _, prefix in ipairs(UI_HOVER_PREFIXES) do
		ResetStableVisibilityState(prefix)
	end
	CallbackRegistry:Trigger("VisibilityContextChanged", "visibility_hideInPetBattle")
end)

CallbackRegistry:RegisterSettingCallback("visibility_hideInSpecialActionBarContext", function()
	ResetStableVisibilityState(nil)
	for _, prefix in ipairs(UI_HOVER_PREFIXES) do
		ResetStableVisibilityState(prefix)
	end
	CallbackRegistry:Trigger("VisibilityContextChanged", "visibility_hideInSpecialActionBarContext")
end)

for _, prefix in ipairs(UI_HOVER_PREFIXES) do
	CallbackRegistry:RegisterSettingCallback(prefix .. "_hideOnUIHover", function()
		ResetStableVisibilityState(prefix)
		CallbackRegistry:Trigger("VisibilityContextChanged", prefix .. "_hideOnUIHover")
	end)
	CallbackRegistry:RegisterSettingCallback(prefix .. "_hideInPetBattle", function()
		ResetStableVisibilityState(prefix)
		CallbackRegistry:Trigger("VisibilityContextChanged", prefix .. "_hideInPetBattle")
	end)
	CallbackRegistry:RegisterSettingCallback(prefix .. "_hideInSpecialActionBarContext", function()
		ResetStableVisibilityState(prefix)
		CallbackRegistry:Trigger("VisibilityContextChanged", prefix .. "_hideInSpecialActionBarContext")
	end)
	CallbackRegistry:RegisterSettingCallback(prefix .. "_visibilitySource", function()
		ResetStableVisibilityState(prefix)
		CallbackRegistry:Trigger("VisibilityContextChanged", prefix .. "_visibilitySource")
	end)
	CallbackRegistry:RegisterSettingCallback(prefix .. "_visibility", function()
		ResetStableVisibilityState(prefix)
		CallbackRegistry:Trigger("VisibilityContextChanged", prefix .. "_visibility")
	end)
end

CallbackRegistry:RegisterSettingCallback("attachToMouse", function()
	if not (GetDBBool and GetDBBool("attachToMouse")) then
		lastHoveringInteractiveUI = false
	end
	ResetStableVisibilityState(nil)
	for _, prefix in ipairs(UI_HOVER_PREFIXES) do
		ResetStableVisibilityState(prefix)
	end
	CallbackRegistry:Trigger("VisibilityContextChanged", "attachToMouse")
end)

CallbackRegistry:RegisterSettingCallback("visibility_mode", function()
	ResetStableVisibilityState(nil)
	for _, prefix in ipairs(UI_HOVER_PREFIXES) do
		ResetStableVisibilityState(prefix)
	end
	CallbackRegistry:Trigger("VisibilityContextChanged", "visibility_mode")
end)

for _, key in ipairs(MOTION_SETTING_KEYS) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ResetStableVisibilityState(nil)
		for _, prefix in ipairs(UI_HOVER_PREFIXES) do
			ResetStableVisibilityState(prefix)
		end
		CallbackRegistry:Trigger("VisibilityContextChanged", key)
	end)
end
