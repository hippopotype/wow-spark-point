-- SparkPoint API Utilities
-- Common utility functions using new WoW APIs (C_Spell.*, etc.)

local _, addon = ...

local API = {}
addon.API = API
local issecretvalue = _G.issecretvalue
local GetActionCooldown = GetActionCooldown
local GetActionCharges = GetActionCharges

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

-- Compatibility pattern adapted from .clones/Plumber/Modules/Shared/CooldownUtil.lua.
local function NormalizeCooldownInfo(rawInfo)
	if type(rawInfo) ~= "table" then
		return nil
	end

	local startTime = SafeNumber(rawInfo.startTime, 0)
	local duration = SafeNumber(rawInfo.duration, 0)
	local modRate = SafeNumber(rawInfo.modRate, 1)
	local isEnabled = (startTime > 0 or duration > 0) and 1 or 0
	local isActive = isEnabled ~= 0 and startTime > 0 and duration > 0

	return {
		startTime = startTime,
		duration = duration,
		isEnabled = isEnabled,
		modRate = modRate,
		isActive = isActive,
	}
end

local function NormalizeChargeCooldownInfo(rawInfo)
	if type(rawInfo) ~= "table" then
		return nil
	end

	local currentCharges = SafeNumber(rawInfo.currentCharges, nil)
	local maxCharges = SafeNumber(rawInfo.maxCharges, 0)
	local cooldownStartTime = SafeNumber(rawInfo.cooldownStartTime, 0)
	local cooldownDuration = SafeNumber(rawInfo.cooldownDuration, 0)
	local chargeModRate = SafeNumber(rawInfo.chargeModRate, 1)
	local isActive = maxCharges > 1 and currentCharges ~= nil and currentCharges < maxCharges and cooldownStartTime > 0 and cooldownDuration > 0

	return {
		currentCharges = currentCharges,
		maxCharges = maxCharges,
		cooldownStartTime = cooldownStartTime,
		cooldownDuration = cooldownDuration,
		chargeModRate = chargeModRate,
		isActive = isActive,
	}
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

function API.GetSpellCooldownInfo(spellID)
	if not spellID then
		return nil
	end
	if not (C_Spell and C_Spell.GetSpellCooldown) then
		return nil
	end

	return NormalizeCooldownInfo(C_Spell.GetSpellCooldown(spellID))
end

function API.GetActionCooldownInfo(actionSlot)
	if not actionSlot or not GetActionCooldown then
		return nil
	end

	local startTime, duration, _, modRate = GetActionCooldown(actionSlot)
	if type(startTime) == "table" then
		return NormalizeCooldownInfo(startTime)
	end

	return NormalizeCooldownInfo({
		startTime = startTime,
		duration = duration,
		modRate = modRate,
	})
end

function API.GetSpellChargeCooldownInfo(spellID)
	if not spellID or not (C_Spell and C_Spell.GetSpellCharges) then
		return nil
	end

	return NormalizeChargeCooldownInfo(C_Spell.GetSpellCharges(spellID))
end

function API.GetActionChargeCooldownInfo(actionSlot)
	if not actionSlot or not GetActionCharges then
		return nil
	end

	local currentCharges, maxCharges, cooldownStartTime, cooldownDuration, chargeModRate = GetActionCharges(actionSlot)

	return NormalizeChargeCooldownInfo({
		currentCharges = currentCharges,
		maxCharges = maxCharges,
		cooldownStartTime = cooldownStartTime,
		cooldownDuration = cooldownDuration,
		chargeModRate = chargeModRate,
	})
end

function API.IsCooldownInfoActive(info)
	if type(info) ~= "table" then
		return false
	end

	return info.isEnabled ~= 0 and info.startTime > 0 and info.duration > 0
end

function API.IsChargeCooldownInfoActive(info)
	if type(info) ~= "table" then
		return false
	end

	return info.maxCharges > 1 and info.currentCharges ~= nil and info.currentCharges < info.maxCharges and info.cooldownStartTime > 0 and info.cooldownDuration > 0
end

function API.GetSpellCooldown(spellID)
	local info = API.GetSpellCooldownInfo(spellID)
	if type(info) ~= "table" then
		return 0, 0, 0, 1
	end

	return info.startTime, info.duration, info.isEnabled, info.modRate
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
