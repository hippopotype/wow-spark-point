-- SparkPoint Mana Bar Provider

local _, addon = ...
local API = addon.API
local ResourceColors = addon.ResourceColors

local ManaBarProvider = {}
ManaBarProvider.id = "MANA"
ManaBarProvider.displayName = "Mana"

local isEnabled = false
local POWER_TYPE_MANA = Enum.PowerType.Mana

local function GetManaPercentValue(current, maxValue)
	if UnitPowerPercent then
		local ok, percent = pcall(UnitPowerPercent, "player", POWER_TYPE_MANA, true, CurveConstants and CurveConstants.ScaleTo100)
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

local function GetManaColor()
	if ResourceColors and ResourceColors.GetColor then
		return ResourceColors:GetColor("MANA")
	end
	return { r = 0, g = 0.55, b = 1, a = 1 }
end

function ManaBarProvider:GetStatus()
	if not isEnabled then
		return { current = nil, max = nil, active = false, show = false }
	end

	local current = UnitPower("player", POWER_TYPE_MANA)
	local maxValue = UnitPowerMax("player", POWER_TYPE_MANA)
	if maxValue == nil or maxValue == 0 then
		return { current = nil, max = nil, active = false, show = false, barColor = GetManaColor() }
	end

	return {
		current = current,
		max = maxValue,
		active = true,
		show = true,
		barColor = GetManaColor(),
	}
end

function ManaBarProvider:GetTextDisplayData(result, numberStyle)
	if not isEnabled then
		return nil
	end

	local current = result and result.current
	local maxValue = result and result.max
	if current == nil or maxValue == nil then
		current = UnitPower("player", POWER_TYPE_MANA)
		maxValue = UnitPowerMax("player", POWER_TYPE_MANA)
	end

	local maxReadable = API.SafeReadableNumber(maxValue, 0)
	if maxReadable <= 0 then
		return nil
	end

	return {
		current = API.FormatBarTextValue(current, numberStyle),
		max = API.FormatBarTextValue(maxValue, numberStyle),
		percent = API.FormatBarTextPercent(GetManaPercentValue(current, maxValue)),
	}
end

function ManaBarProvider:Enable()
	isEnabled = true
end

function ManaBarProvider:Disable()
	isEnabled = false
end

addon.BarProviders:Register("MANA", ManaBarProvider)
