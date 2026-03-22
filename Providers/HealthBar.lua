-- SparkPoint Health Bar Provider

local _, addon = ...
local API = addon.API

local HealthBarProvider = {}
HealthBarProvider.id = "HEALTH"
HealthBarProvider.displayName = "Health"

local isEnabled = false

local function GetHealthPercentValue(current, maxValue)
	if UnitHealthPercent then
		local ok, percent = pcall(UnitHealthPercent, "player", true, CurveConstants and CurveConstants.ScaleTo100)
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

function HealthBarProvider:GetStatus()
	if not isEnabled then
		return { current = nil, max = nil, active = false, show = false }
	end

	local current = UnitHealth("player")
	local maxValue = UnitHealthMax("player")
	if maxValue == nil then
		return { current = nil, max = nil, active = false, show = false }
	end

	return {
		current = current,
		max = maxValue,
		active = true,
		show = true,
		barColor = { r = 0.12, g = 0.86, b = 0.20, a = 1 },
	}
end

function HealthBarProvider:GetTextDisplayData(result, numberStyle)
	if not isEnabled then
		return nil
	end

	local current = result and result.current
	local maxValue = result and result.max
	if current == nil or maxValue == nil then
		current = UnitHealth("player")
		maxValue = UnitHealthMax("player")
	end

	local maxReadable = API.SafeReadableNumber(maxValue, 0)
	if maxReadable <= 0 then
		return nil
	end

	return {
		current = API.FormatReadableValue(current, numberStyle),
		max = API.FormatReadableValue(maxValue, numberStyle),
		percent = API.FormatPercentValue(GetHealthPercentValue(current, maxValue)),
	}
end

function HealthBarProvider:Enable()
	isEnabled = true
end

function HealthBarProvider:Disable()
	isEnabled = false
end

addon.BarProviders:Register("HEALTH", HealthBarProvider)
