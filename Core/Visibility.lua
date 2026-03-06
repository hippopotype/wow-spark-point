-- SparkPoint Visibility Service
-- Shared visibility policy evaluation for addon-level and module-level displays.

local _, addon = ...

local API = addon.API
local CallbackRegistry = addon.CallbackRegistry
local GetDBBool = addon.GetDBBool

local Visibility = {}
addon.Visibility = Visibility

Visibility.MODES = {
	ALWAYS = "ALWAYS",
	IN_COMBAT = "IN_COMBAT",
	OUT_OF_COMBAT = "OUT_OF_COMBAT",
	HAS_TARGET = "HAS_TARGET",
	CASTING = "CASTING",
	AFTER_INSTANT_CAST = "AFTER_INSTANT_CAST",
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
	Visibility.MODES.CASTING,
	Visibility.MODES.AFTER_INSTANT_CAST,
	Visibility.MODES.IN_PARTY,
	Visibility.MODES.IN_RAID,
	Visibility.MODES.IN_INSTANCE,
}

local GCD_SPELL_ID = 61304
local MAX_GCD_WINDOW = 2
local afterInstantCastActive = false
local afterInstantCastExpiry = 0
local afterInstantCastTimerToken = 0
local hoverWatcher
local lastHoveringInteractiveUI = false
local UI_HOVER_PREFIXES = { "cast", "classresource", "ring", "assistedhighlight" }

local GetMouseFoci = GetMouseFoci
local GetMouseFocus = GetMouseFocus
local UIParent = UIParent
local WorldFrame = WorldFrame

local function IsValidGCDCooldown(startTime, duration)
	return type(startTime) == "number" and type(duration) == "number" and startTime > 0 and duration > 0 and duration <= MAX_GCD_WINDOW
end

local function ScheduleAfterInstantCastExpiryCheck()
	if not afterInstantCastActive then
		return
	end

	afterInstantCastTimerToken = afterInstantCastTimerToken + 1
	local token = afterInstantCastTimerToken
	local remaining = (afterInstantCastExpiry or 0) - GetTime()
	if remaining < 0 then
		remaining = 0
	end

	C_Timer.After(remaining, function()
		if token ~= afterInstantCastTimerToken then
			return
		end
		if Visibility:RefreshAfterInstantCastTracking("AFTER_INSTANT_CAST_EXPIRE_TIMER") then
			CallbackRegistry:Trigger("VisibilityContextChanged", "AFTER_INSTANT_CAST_EXPIRE_TIMER")
		end
	end)
end

function Visibility:RefreshAfterInstantCastTracking(event)
	local now = GetTime()
	local startTime, duration = 0, 0
	if API and API.GetSpellCooldown then
		startTime, duration = API.GetSpellCooldown(GCD_SPELL_ID)
	end

	local shouldBeActive = false
	local nextExpiry
	if IsValidGCDCooldown(startTime, duration) then
		shouldBeActive = true
		nextExpiry = startTime + duration
	elseif afterInstantCastActive and type(afterInstantCastExpiry) == "number" and now < afterInstantCastExpiry then
		-- Cooldown data can lag briefly after instant casts; preserve the active window until expected end.
		shouldBeActive = true
		nextExpiry = afterInstantCastExpiry
	else
		nextExpiry = 0
	end

	local changed = (afterInstantCastActive ~= shouldBeActive) or (shouldBeActive and math.abs((afterInstantCastExpiry or 0) - nextExpiry) > 0.001)
	afterInstantCastActive = shouldBeActive
	afterInstantCastExpiry = nextExpiry

	if changed and afterInstantCastActive then
		ScheduleAfterInstantCastExpiryCheck()
	elseif changed and not afterInstantCastActive then
		afterInstantCastTimerToken = afterInstantCastTimerToken + 1
	end

	return changed
end

function Visibility:IsAfterInstantCastActive()
	if not afterInstantCastActive then
		return false
	end
	if type(afterInstantCastExpiry) ~= "number" or afterInstantCastExpiry <= 0 then
		return false
	end
	return GetTime() < afterInstantCastExpiry
end

function Visibility:HandleUnitSpellcastSucceeded(unit, castGUID, spellID)
	if unit ~= "player" then
		return false
	end
	if UnitCastingInfo("player") or UnitChannelInfo("player") then
		return false
	end
	if not spellID then
		return false
	end

	local info = C_Spell.GetSpellInfo(spellID)
	if not info or (info.castTime or 0) > 0 then
		return false
	end

	local changed = self:RefreshAfterInstantCastTracking("UNIT_SPELLCAST_SUCCEEDED")

	-- Instant casts can update shared cooldown data one frame later.
	C_Timer.After(0, function()
		local changedDeferred = Visibility:RefreshAfterInstantCastTracking("UNIT_SPELLCAST_SUCCEEDED_DEFERRED")
		if changedDeferred then
			CallbackRegistry:Trigger("VisibilityContextChanged", "UNIT_SPELLCAST_SUCCEEDED_DEFERRED", unit, castGUID, spellID)
		end
	end)

	return changed
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

local function IsFrameMouseInteractive(frame)
	if not frame then
		return false
	end
	if frame.IsMouseEnabled then
		local ok, enabled = pcall(frame.IsMouseEnabled, frame)
		if ok and enabled then
			return true
		end
	end
	if frame.IsMouseClickEnabled then
		local ok, enabled = pcall(frame.IsMouseClickEnabled, frame)
		if ok and enabled then
			return true
		end
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
	local hasTarget = UnitExists and UnitExists("target") and true or false
	local isCasting = self:IsPlayerCasting()
	local afterInstantCast = self:IsAfterInstantCastActive()
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
	if rules[Visibility.MODES.HAS_TARGET] and hasTarget then
		return true
	end
	if rules[Visibility.MODES.CASTING] and isCasting then
		return true
	end
	if rules[Visibility.MODES.AFTER_INSTANT_CAST] and afterInstantCast then
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

function Visibility:ShouldShow(prefix)
	if self:ShouldHideOnUIHover() and self:GetModuleHideOnUIHover(prefix) then
		return false
	end
	return self:EvaluateRules(self:GetModuleRules(prefix))
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
EL:RegisterEvent("PLAYER_TARGET_CHANGED")
EL:RegisterEvent("GROUP_ROSTER_UPDATE")
EL:RegisterEvent("ZONE_CHANGED_NEW_AREA")
EL:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
EL:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
EL:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
EL:RegisterEvent("SPELL_UPDATE_COOLDOWN")

EL:SetScript("OnEvent", function(_, event, ...)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit, castGUID, spellID = ...
		Visibility:HandleUnitSpellcastSucceeded(unit, castGUID, spellID)
		CallbackRegistry:Trigger("VisibilityContextChanged", event, ...)
		return
	elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" then
		if Visibility:RefreshAfterInstantCastTracking(event) then
			CallbackRegistry:Trigger("VisibilityContextChanged", event, ...)
		end
		return
	end
	CallbackRegistry:Trigger("VisibilityContextChanged", event, ...)
end)

EnsureHoverWatcher()

CallbackRegistry:RegisterSettingCallback("visibility_hideOnUIHover", function()
	lastHoveringInteractiveUI = Visibility:IsHoveringInteractiveUI()
	CallbackRegistry:Trigger("VisibilityContextChanged", "visibility_hideOnUIHover")
end)

for _, prefix in ipairs(UI_HOVER_PREFIXES) do
	CallbackRegistry:RegisterSettingCallback(prefix .. "_hideOnUIHover", function()
		CallbackRegistry:Trigger("VisibilityContextChanged", prefix .. "_hideOnUIHover")
	end)
	CallbackRegistry:RegisterSettingCallback(prefix .. "_visibilitySource", function()
		CallbackRegistry:Trigger("VisibilityContextChanged", prefix .. "_visibilitySource")
	end)
end

CallbackRegistry:RegisterSettingCallback("attachToMouse", function()
	if not (GetDBBool and GetDBBool("attachToMouse")) then
		lastHoveringInteractiveUI = false
	end
	CallbackRegistry:Trigger("VisibilityContextChanged", "attachToMouse")
end)
