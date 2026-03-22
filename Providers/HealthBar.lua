-- SparkPoint Health Bar Provider

local _, addon = ...

local HealthBarProvider = {}
HealthBarProvider.id = "HEALTH"
HealthBarProvider.displayName = "Health"

local isEnabled = false

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
	if UnitHealthPercent then
		percent = UnitHealthPercent("player", true, CurveConstants and CurveConstants.ScaleTo100)
	end

	if percent == nil then
		local current = tonumber(tostring(UnitHealth("player") or 0)) or 0
		local maxValue = tonumber(tostring(UnitHealthMax("player") or 0)) or 0
		if maxValue > 0 then
			percent = (current / maxValue) * 100
		else
			percent = 0
		end
	end

	return string.format("%d%%", math.floor((tonumber(tostring(percent)) or 0) + 0.5))
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

function HealthBarProvider:GetTextParts(result)
	if not isEnabled then
		return nil
	end

	local current = result and result.current or UnitHealth("player")
	local maxValue = result and result.max or UnitHealthMax("player")
	if maxValue == nil then
		return nil
	end

	return {
		current = FormatDisplayNumber(current),
		max = FormatDisplayNumber(maxValue),
		percent = FormatPercentText(),
	}
end

function HealthBarProvider:Enable()
	isEnabled = true
end

function HealthBarProvider:Disable()
	isEnabled = false
end

addon.BarProviders:Register("HEALTH", HealthBarProvider)
