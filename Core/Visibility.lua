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
}

Visibility.SOURCES = {
	INHERIT = "INHERIT",
	CUSTOM = "CUSTOM",
}

local function NormalizeMode(mode)
	for _, value in pairs(Visibility.MODES) do
		if mode == value then
			return mode
		end
	end
	return Visibility.MODES.ALWAYS
end

local function NormalizeSource(source)
	if source == Visibility.SOURCES.CUSTOM then
		return Visibility.SOURCES.CUSTOM
	end
	return Visibility.SOURCES.INHERIT
end

function Visibility:GetGlobalMode()
	local GetDBValue = addon.GetDBValue
	local mode = GetDBValue and GetDBValue("visibility_mode")
	return NormalizeMode(mode)
end

function Visibility:GetModuleSource(prefix)
	if not prefix then
		return Visibility.SOURCES.INHERIT
	end
	local GetDBValue = addon.GetDBValue
	local source = GetDBValue and GetDBValue(prefix .. "_visibilitySource")
	return NormalizeSource(source)
end

function Visibility:GetModuleMode(prefix)
	if not prefix then
		return self:GetGlobalMode()
	end
	if self:GetModuleSource(prefix) == Visibility.SOURCES.INHERIT then
		return self:GetGlobalMode()
	end

	local GetDBValue = addon.GetDBValue
	local mode = GetDBValue and GetDBValue(prefix .. "_visibility")
	return NormalizeMode(mode)
end

function Visibility:IsPlayerCasting()
	return UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil
end

function Visibility:EvaluateMode(mode)
	mode = NormalizeMode(mode)
	if mode == Visibility.MODES.IN_COMBAT then
		return InCombatLockdown() and true or false
	end
	if mode == Visibility.MODES.OUT_OF_COMBAT then
		return not InCombatLockdown()
	end
	if mode == Visibility.MODES.HAS_TARGET then
		return UnitExists("target") and true or false
	end
	if mode == Visibility.MODES.CASTING then
		return self:IsPlayerCasting()
	end
	return true
end

function Visibility:ShouldShow(prefix)
	return self:EvaluateMode(self:GetModuleMode(prefix))
end

local EL = CreateFrame("Frame")
EL:RegisterEvent("PLAYER_ENTERING_WORLD")
EL:RegisterEvent("PLAYER_REGEN_DISABLED")
EL:RegisterEvent("PLAYER_REGEN_ENABLED")
EL:RegisterEvent("PLAYER_TARGET_CHANGED")
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
