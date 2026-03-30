-- SparkPoint Class Power Bar Provider
-- Continuous class resources: Energy, Rage, Focus, Runic Power, etc.

local _, addon = ...
local API = addon.API
local ResourceModel = addon.ResourceModel
local ResourceColors = addon.ResourceColors

local ClassPowerProvider = {}
ClassPowerProvider.id = "CLASS_POWER"
ClassPowerProvider.displayName = "Class Power"

local isEnabled = false
local activePower = nil

local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax

--------------------------------------------------------------------------------
-- Detection
--------------------------------------------------------------------------------
local function DetectPowerType()
	return ResourceModel:GetCurrentClassPower("player")
end

local function RefreshDetection()
	activePower = DetectPowerType()
end

--------------------------------------------------------------------------------
-- Color
--------------------------------------------------------------------------------
local function GetPowerColor()
	if ResourceColors and ResourceColors.GetColor and activePower then
		return ResourceColors:GetColor(activePower)
	end
	return { r = 1, g = 1, b = 1, a = 1 }
end

--------------------------------------------------------------------------------
-- Percent (secret-safe)
--------------------------------------------------------------------------------
local function GetPowerPercentValue(current, maxValue)
	if activePower and activePower.powerEnum and UnitPowerPercent then
		local ok, percent = pcall(UnitPowerPercent, "player", activePower.powerEnum, true, CurveConstants and CurveConstants.ScaleTo100)
		if ok and percent ~= nil then
			return percent
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
	if not isEnabled or not activePower then
		return { current = nil, max = nil, active = false, show = false }
	end

	local current = UnitPower("player", activePower.powerEnum)
	local maxValue = UnitPowerMax("player", activePower.powerEnum)
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
	if not isEnabled or not activePower then
		return nil
	end

	local current = result and result.current
	local maxValue = result and result.max
	if current == nil or maxValue == nil then
		current = UnitPower("player", activePower.powerEnum)
		maxValue = UnitPowerMax("player", activePower.powerEnum)
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
	activePower = nil
end

function ClassPowerProvider:RefreshDetection()
	RefreshDetection()
end

function ClassPowerProvider:IsAvailable()
	if not activePower or not activePower.powerEnum then
		return false
	end

	local maxValue = UnitPowerMax("player", activePower.powerEnum)
	return maxValue ~= nil and maxValue > 0
end

addon.BarProviders:Register("CLASS_POWER", ClassPowerProvider)
