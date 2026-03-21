-- SparkPoint Mana Bar Provider

local _, addon = ...

local ManaBarProvider = {}
ManaBarProvider.id = "MANA"
ManaBarProvider.displayName = "Mana"

local isEnabled = false
local POWER_TYPE_MANA = Enum.PowerType.Mana

local function GetManaColor()
	local color
	if PowerBarColor then
		color = PowerBarColor.MANA or PowerBarColor[POWER_TYPE_MANA]
	end
	if color then
		return {
			r = color.r or 0,
			g = color.g or 0.55,
			b = color.b or 1,
			a = 1,
		}
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

function ManaBarProvider:Enable()
	isEnabled = true
end

function ManaBarProvider:Disable()
	isEnabled = false
end

addon.BarProviders:Register("MANA", ManaBarProvider)
