-- SparkPoint API Utilities
-- Common utility functions using new WoW APIs (C_Spell.*, etc.)

local _, addon = ...

local API = {}
addon.API = API

function API.GetSpellCooldown(spellID)
	if not spellID then
		return 0, 0, 0
	end
	local info = C_Spell.GetSpellCooldown(spellID)
	if type(info) ~= "table" then
		return 0, 0, 0, 1
	end
	return info.startTime or 0, info.duration or 0, (info.isEnabled and 1 or 0), info.modRate or 1
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
