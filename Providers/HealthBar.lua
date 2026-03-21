-- SparkPoint Health Bar Provider

local _, addon = ...

local HealthBarProvider = {}
HealthBarProvider.id = "HEALTH"
HealthBarProvider.displayName = "Health"

local isEnabled = false

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

function HealthBarProvider:Enable()
	isEnabled = true
end

function HealthBarProvider:Disable()
	isEnabled = false
end

addon.BarProviders:Register("HEALTH", HealthBarProvider)
