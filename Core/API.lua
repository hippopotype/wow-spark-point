-- SparkPoint API Utilities
-- Common utility functions using new WoW APIs (C_Spell.*, etc.)

local _, addon = ...

local API = {}
addon.API = API
local issecretvalue = _G.issecretvalue

local function SafeNumber(value, fallback)
	if value == nil then
		return fallback
	end

	local ok, stringValue = pcall(tostring, value)
	if not ok then
		return fallback
	end

	local numericValue = tonumber(stringValue)
	if numericValue == nil then
		return fallback
	end

	return numericValue
end

function API.SafeReadableNumber(value, fallback)
	return SafeNumber(value, fallback)
end

local function IsSecretReadableValue(value)
	return value ~= nil and issecretvalue and issecretvalue(value)
end

-- Shared bar-slot text helpers used by bar providers and the BarSlots module.
function API.FormatBarTextValue(value, style)
	if value == nil then
		return "0"
	end

	if style == "SHORT" and AbbreviateNumbers then
		local ok, formatted = pcall(AbbreviateNumbers, value)
		if ok and formatted ~= nil then
			return tostring(formatted)
		end
	end

	if BreakUpLargeNumbers then
		local ok, formatted = pcall(BreakUpLargeNumbers, value)
		if ok and formatted ~= nil then
			return tostring(formatted)
		end
	end

	if IsSecretReadableValue(value) then
		local ok, formatted = pcall(tostring, value)
		if ok and formatted ~= nil then
			return formatted
		end
		return "0"
	end

	local numericValue = SafeNumber(value, 0)
	return tostring(numericValue)
end

function API.FormatBarTextPercent(value)
	if value == nil then
		return "0%"
	end

	if IsSecretReadableValue(value) then
		if C_StringUtil and C_StringUtil.RoundToNearestString then
			local ok, rounded = pcall(C_StringUtil.RoundToNearestString, value)
			if ok and rounded ~= nil then
				return tostring(rounded) .. "%"
			end
		end

		local ok, formatted = pcall(tostring, value)
		if ok and formatted ~= nil then
			return formatted .. "%"
		end

		return "0%"
	end

	local numericValue = SafeNumber(value, 0)
	return string.format("%d%%", math.floor(numericValue + 0.5))
end

function API.ComposeBarTextDisplay(mode, currentText, maxText, percentText)
	if mode == "CURRENT" then
		return currentText
	elseif mode == "CURRENT_MAX" then
		return currentText .. " / " .. maxText
	elseif mode == "PERCENT" then
		return percentText
	elseif mode == "CURRENT_MAX_PERCENT" then
		return currentText .. " / " .. maxText .. " (" .. percentText .. ")"
	end

	return currentText .. " - " .. percentText
end

function API.GetSpellCooldown(spellID)
	if not spellID then
		return 0, 0, 0
	end
	local info = C_Spell.GetSpellCooldown(spellID)
	if type(info) ~= "table" then
		return 0, 0, 0, 1
	end
	local startTime = SafeNumber(info.startTime, 0)
	local duration = SafeNumber(info.duration, 0)
	local enabled = (startTime > 0 or duration > 0) and 1 or 0
	return startTime, duration, enabled, SafeNumber(info.modRate, 1)
end

--------------------------------------------------------------------------------
-- Class/Spec Detection
--------------------------------------------------------------------------------
function API.GetPlayerClass()
	local _, class = UnitClass("player")
	return class
end

function API.GetPlayerClassColor()
	local class = API.GetPlayerClass()
	if not class then
		return 1, 1, 1, 1
	end

	if CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class] then
		local c = CUSTOM_CLASS_COLORS[class]
		return c.r or 1, c.g or 1, c.b or 1, c.a or 1
	end

	if RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
		local c = RAID_CLASS_COLORS[class]
		return c.r or 1, c.g or 1, c.b or 1, c.a or 1
	end

	if C_ClassColor and C_ClassColor.GetClassColor then
		local c = C_ClassColor.GetClassColor(class)
		if c and c.GetRGBA then
			return c:GetRGBA()
		elseif c and c.GetRGB then
			local r, g, b = c:GetRGB()
			return r, g, b, 1
		end
	end

	return 1, 1, 1, 1
end
