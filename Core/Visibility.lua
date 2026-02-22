-- SparkPoint Visibility Service
-- Shared visibility policy evaluation for addon-level and module-level displays.

local _, addon = ...

local CallbackRegistry = addon.CallbackRegistry

local Visibility = {}
addon.Visibility = Visibility

Visibility.MODES = {
	ALWAYS = "ALWAYS",
	IN_COMBAT = "IN_COMBAT",
	OUT_OF_COMBAT = "OUT_OF_COMBAT",
	HAS_TARGET = "HAS_TARGET",
	CASTING = "CASTING",
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
	Visibility.MODES.IN_PARTY,
	Visibility.MODES.IN_RAID,
	Visibility.MODES.IN_INSTANCE,
}

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
	return normalized
end

local function NormalizeSource(source)
	if source == Visibility.SOURCES.CUSTOM then
		return Visibility.SOURCES.CUSTOM
	end
	return Visibility.SOURCES.INHERIT
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

	local inCombat = InCombatLockdown and InCombatLockdown() and true or false
	local hasTarget = UnitExists and UnitExists("target") and true or false
	local isCasting = self:IsPlayerCasting()
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
	return self:EvaluateRules(self:GetModuleRules(prefix))
end

local EL = CreateFrame("Frame")
EL:RegisterEvent("PLAYER_ENTERING_WORLD")
EL:RegisterEvent("PLAYER_REGEN_DISABLED")
EL:RegisterEvent("PLAYER_REGEN_ENABLED")
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

EL:SetScript("OnEvent", function(_, event, ...)
	CallbackRegistry:Trigger("VisibilityContextChanged", event, ...)
end)
