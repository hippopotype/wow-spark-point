-- SparkPoint Resource Colors
-- Shared addon-wide resource color defaults and overrides.

local _, addon = ...

local ResourceModel = addon.ResourceModel
local GetDBValue = addon.GetDBValue
local SetDBValue = addon.SetDBValue

local ResourceColors = {}
addon.ResourceColors = ResourceColors

local OVERRIDES_DB_KEY = "resourceColorOverrides"

local SPECIAL_DEFAULTS = {
	HEALTH = { r = 0.12, g = 0.86, b = 0.20, a = 1 },
}

local SETTINGS_ORDER = {
	"HEALTH",
	"MANA",
	"ENERGY",
	"RAGE",
	"FOCUS",
	"FURY",
	"RUNIC_POWER",
	"LUNAR_POWER",
	"INSANITY",
	"MAELSTROM",
	"RUNES",
	"ROGUE_COMBO_POINTS",
	"DRUID_COMBO_POINTS",
	"HOLY_POWER",
	"CHI",
	"ARCANE_CHARGES",
	"SOUL_SHARDS",
	"ESSENCE",
	"MAELSTROM_WEAPON",
}

local LABEL_KEYS = {
	HEALTH = "Resource Color Health",
	MANA = "Resource Color Mana",
	ENERGY = "Resource Color Energy",
	RAGE = "Resource Color Rage",
	FOCUS = "Resource Color Focus",
	FURY = "Resource Color Fury",
	RUNIC_POWER = "Resource Color Runic Power",
	LUNAR_POWER = "Resource Color Astral Power",
	INSANITY = "Resource Color Insanity",
	MAELSTROM = "Resource Color Maelstrom",
	RUNES = "Resource Color Runes",
	ROGUE_COMBO_POINTS = "Resource Color Rogue Combo Points",
	DRUID_COMBO_POINTS = "Resource Color Druid Combo Points",
	HOLY_POWER = "Resource Color Holy Power",
	CHI = "Resource Color Chi",
	ARCANE_CHARGES = "Resource Color Arcane Charges",
	SOUL_SHARDS = "Resource Color Soul Shards",
	ESSENCE = "Resource Color Essence",
	MAELSTROM_WEAPON = "Resource Color Maelstrom Weapon",
}

local LABEL_FALLBACKS = {
	HEALTH = "Health",
	MANA = "Mana",
	ENERGY = "Energy",
	RAGE = "Rage",
	FOCUS = "Focus",
	FURY = "Fury",
	RUNIC_POWER = "Runic Power",
	LUNAR_POWER = "Astral Power",
	INSANITY = "Insanity",
	MAELSTROM = "Maelstrom",
	RUNES = "Runes",
	ROGUE_COMBO_POINTS = "Rogue Combo Points",
	DRUID_COMBO_POINTS = "Druid Combo Points",
	HOLY_POWER = "Holy Power",
	CHI = "Chi",
	ARCANE_CHARGES = "Arcane Charges",
	SOUL_SHARDS = "Soul Shards",
	ESSENCE = "Essence",
	MAELSTROM_WEAPON = "Maelstrom Weapon",
}

local function CopyColor(color)
	if type(color) ~= "table" then
		return nil
	end

	return {
		r = color.r or 1,
		g = color.g or 1,
		b = color.b or 1,
		a = color.a or 1,
	}
end

local function ColorsMatch(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end

	return math.abs((a.r or 1) - (b.r or 1)) < 0.0001
		and math.abs((a.g or 1) - (b.g or 1)) < 0.0001
		and math.abs((a.b or 1) - (b.b or 1)) < 0.0001
		and math.abs((a.a or 1) - (b.a or 1)) < 0.0001
end

local function DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local out = {}
	for key, entry in pairs(value) do
		out[key] = DeepCopy(entry)
	end
	return out
end

local function ResolveResourceDef(resource)
	if type(resource) == "table" then
		return resource
	end

	if type(resource) == "string" and ResourceModel and ResourceModel.GetResourceDefinition then
		return ResourceModel:GetResourceDefinition(resource)
	end

	return nil
end

local function GetPowerBarColor(powerToken, powerEnum)
	if not PowerBarColor then
		return nil
	end

	local candidates = { powerToken, powerEnum }
	for _, candidate in ipairs(candidates) do
		if candidate ~= nil then
			local color = PowerBarColor[candidate]
			if type(color) == "table" and color.r then
				return CopyColor(color)
			end
		end
	end

	return nil
end

function ResourceColors:GetCanonicalKey(resource)
	if type(resource) == "table" and type(resource.key) == "string" and resource.key ~= "" then
		return resource.key
	end

	if type(resource) == "string" and resource ~= "" then
		return resource
	end

	return nil
end

function ResourceColors:GetDefaultColor(resource)
	local key = self:GetCanonicalKey(resource)
	if not key then
		return { r = 1, g = 1, b = 1, a = 1 }
	end

	local specialColor = SPECIAL_DEFAULTS[key]
	if specialColor then
		return CopyColor(specialColor)
	end

	local resourceDef = ResolveResourceDef(resource)
	if not resourceDef and ResourceModel and ResourceModel.GetResourceDefinition then
		resourceDef = ResourceModel:GetResourceDefinition(key)
	end

	if resourceDef and resourceDef.fillColor then
		return CopyColor(resourceDef.fillColor)
	end

	local blizzardColor = GetPowerBarColor(resourceDef and resourceDef.powerToken, resourceDef and resourceDef.powerEnum)
	if blizzardColor then
		return blizzardColor
	end

	local fallbackColor = GetPowerBarColor(key, nil)
	if fallbackColor then
		return fallbackColor
	end

	return { r = 1, g = 1, b = 1, a = 1 }
end

function ResourceColors:GetOverrideColor(resource)
	local key = self:GetCanonicalKey(resource)
	if not key then
		return nil
	end

	local overrides = GetDBValue and GetDBValue(OVERRIDES_DB_KEY)
	local color = type(overrides) == "table" and overrides[key]
	return CopyColor(color)
end

function ResourceColors:GetColor(resource)
	return self:GetOverrideColor(resource) or self:GetDefaultColor(resource)
end

function ResourceColors:SetOverrideColor(resource, r, g, b, a)
	local key = self:GetCanonicalKey(resource)
	if not key or not SetDBValue then
		return
	end

	local overrides = DeepCopy((GetDBValue and GetDBValue(OVERRIDES_DB_KEY)) or {})
	local color = {
		r = r or 1,
		g = g or 1,
		b = b or 1,
		a = a or 1,
	}

	if ColorsMatch(color, self:GetDefaultColor(key)) then
		overrides[key] = nil
	else
		overrides[key] = color
	end

	SetDBValue(OVERRIDES_DB_KEY, overrides, true)
end

function ResourceColors:GetSettingEntries()
	local entries = {}
	local L = addon.L or {}

	for _, key in ipairs(SETTINGS_ORDER) do
		entries[#entries + 1] = {
			key = key,
			label = L[LABEL_KEYS[key]] or LABEL_FALLBACKS[key] or key,
		}
	end

	return entries
end
