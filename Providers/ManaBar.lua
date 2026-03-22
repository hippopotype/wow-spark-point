-- SparkPoint Mana Bar Provider

local _, addon = ...

local ManaBarProvider = {}
ManaBarProvider.id = "MANA"
ManaBarProvider.displayName = "Mana"

local isEnabled = false
local POWER_TYPE_MANA = Enum.PowerType.Mana

local function FormatDisplayNumber(value)
	local text = tostring(value or 0)
	local numeric = tonumber(text)
	if numeric ~= nil then
		if AbbreviateNumbers then
			return AbbreviateNumbers(numeric)
		end
		if BreakUpLargeNumbers then
			return BreakUpLargeNumbers(numeric)
		end
	end
	return text
end

local function FormatPercentText()
	local percent
	if UnitPowerPercent then
		percent = UnitPowerPercent("player", POWER_TYPE_MANA, true, CurveConstants and CurveConstants.ScaleTo100)
	end

	if percent == nil then
		local current = tonumber(tostring(UnitPower("player", POWER_TYPE_MANA) or 0)) or 0
		local maxValue = tonumber(tostring(UnitPowerMax("player", POWER_TYPE_MANA) or 0)) or 0
		if maxValue > 0 then
			percent = (current / maxValue) * 100
		else
			percent = 0
		end
	end

	return string.format("%d%%", math.floor((tonumber(tostring(percent)) or 0) + 0.5))
end

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

function ManaBarProvider:GetTextParts(result)
	if not isEnabled then
		return nil
	end

	local current = result and result.current or UnitPower("player", POWER_TYPE_MANA)
	local maxValue = result and result.max or UnitPowerMax("player", POWER_TYPE_MANA)
	if maxValue == nil or maxValue == 0 then
		return nil
	end

	return {
		current = FormatDisplayNumber(current),
		max = FormatDisplayNumber(maxValue),
		percent = FormatPercentText(),
	}
end

function ManaBarProvider:Enable()
	isEnabled = true
end

function ManaBarProvider:Disable()
	isEnabled = false
end

addon.BarProviders:Register("MANA", ManaBarProvider)
