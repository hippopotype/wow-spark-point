-- SparkPoint Class Power Bar Provider
-- Continuous class resources: Energy, Rage, Focus, Runic Power, etc.

local _, addon = ...
local API = addon.API

local ClassPowerProvider = {}
ClassPowerProvider.id = "CLASS_POWER"
ClassPowerProvider.displayName = "Class Power"

local isEnabled = false
local activePowerType = nil
local activePowerToken = nil

local UnitClass = UnitClass
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local GetSpecialization = GetSpecialization

--------------------------------------------------------------------------------
-- Per-class/spec continuous resource mapping
-- Only non-mana continuous resources; mana-primary specs return nil.
--------------------------------------------------------------------------------
local SPEC_POWER_MAP = {
	WARRIOR = { default = { type = Enum.PowerType.Rage, token = "RAGE" } },
	HUNTER = { default = { type = Enum.PowerType.Focus, token = "FOCUS" } },
	ROGUE = { default = { type = Enum.PowerType.Energy, token = "ENERGY" } },
	DEATHKNIGHT = { default = { type = Enum.PowerType.RunicPower, token = "RUNIC_POWER" } },
	DEMONHUNTER = {
		[1] = { type = Enum.PowerType.Fury, token = "FURY" },
		[2] = { type = Enum.PowerType.Pain, token = "PAIN" },
	},
	SHAMAN = {
		[1] = { type = Enum.PowerType.Maelstrom, token = "MAELSTROM" },
		-- Enhancement and Restoration: mana-primary, no continuous bar
	},
	PRIEST = {
		[3] = { type = Enum.PowerType.Insanity, token = "INSANITY" },
	},
	DRUID = {
		[1] = { type = Enum.PowerType.LunarPower, token = "LUNAR_POWER" },
		[2] = { type = Enum.PowerType.Energy, token = "ENERGY" },
		[3] = { type = Enum.PowerType.Rage, token = "RAGE" },
		-- Restoration: mana-primary, no continuous bar
	},
	MONK = {
		[1] = { type = Enum.PowerType.Energy, token = "ENERGY" },
		[3] = { type = Enum.PowerType.Energy, token = "ENERGY" },
		-- Mistweaver: mana-primary, no continuous bar
	},
}

--------------------------------------------------------------------------------
-- Detection
--------------------------------------------------------------------------------
local function DetectPowerType()
	local _, classTag = UnitClass("player")
	if not classTag then
		return nil, nil
	end

	local classMap = SPEC_POWER_MAP[classTag]
	if not classMap then
		return nil, nil
	end

	local spec = GetSpecialization() or 0
	local entry = classMap[spec] or classMap.default
	if not entry then
		return nil, nil
	end

	return entry.type, entry.token
end

local function RefreshDetection()
	activePowerType, activePowerToken = DetectPowerType()
end

--------------------------------------------------------------------------------
-- Color
--------------------------------------------------------------------------------
local function GetPowerColor()
	if activePowerToken and PowerBarColor then
		local color = PowerBarColor[activePowerToken]
		if color then
			return {
				r = color.r or 1,
				g = color.g or 1,
				b = color.b or 1,
				a = 1,
			}
		end
	end
	return { r = 1, g = 1, b = 1, a = 1 }
end

--------------------------------------------------------------------------------
-- Percent (secret-safe)
--------------------------------------------------------------------------------
local function GetPowerPercentValue(current, maxValue)
	if activePowerType and UnitPowerPercent then
		local ok, percent = pcall(UnitPowerPercent, "player", activePowerType, true, CurveConstants and CurveConstants.ScaleTo100)
		if ok and percent ~= nil then
			local readablePercent = API.SafeReadableNumber(percent, nil)
			if readablePercent ~= nil then
				return readablePercent
			end
		end
	end

	local currentValue = API.SafeReadableNumber(current, 0)
	local maxReadable = API.SafeReadableNumber(maxValue, 0)
	if maxReadable > 0 then
		return (currentValue / maxReadable) * 100
	end

	return 0
end

--------------------------------------------------------------------------------
-- Provider Interface
--------------------------------------------------------------------------------
function ClassPowerProvider:GetStatus()
	if not isEnabled or not activePowerType then
		return { current = nil, max = nil, active = false, show = false }
	end

	local current = UnitPower("player", activePowerType)
	local maxValue = UnitPowerMax("player", activePowerType)
	if maxValue == nil or maxValue == 0 then
		return { current = nil, max = nil, active = false, show = false, barColor = GetPowerColor() }
	end

	return {
		current = current,
		max = maxValue,
		active = true,
		show = true,
		barColor = GetPowerColor(),
	}
end

function ClassPowerProvider:GetTextDisplayData(result, numberStyle)
	if not isEnabled or not activePowerType then
		return nil
	end

	local current = result and result.current
	local maxValue = result and result.max
	if current == nil or maxValue == nil then
		current = UnitPower("player", activePowerType)
		maxValue = UnitPowerMax("player", activePowerType)
	end

	local maxReadable = API.SafeReadableNumber(maxValue, 0)
	if maxReadable <= 0 then
		return nil
	end

	return {
		current = API.FormatBarTextValue(current, numberStyle),
		max = API.FormatBarTextValue(maxValue, numberStyle),
		percent = API.FormatBarTextPercent(GetPowerPercentValue(current, maxValue)),
	}
end

function ClassPowerProvider:Enable()
	isEnabled = true
	RefreshDetection()
end

function ClassPowerProvider:Disable()
	isEnabled = false
	activePowerType = nil
	activePowerToken = nil
end

function ClassPowerProvider:RefreshDetection()
	RefreshDetection()
end

addon.BarProviders:Register("CLASS_POWER", ClassPowerProvider)
