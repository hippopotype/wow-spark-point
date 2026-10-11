-- Frame Theme: tint for SparkPoint's metallic frame art (Silver / Copper). "AUTO" resolves
-- through addon.DefaultFrameTheme, set by a per-game data file (Data/FrameTheme_Forever.lua);
-- unset means Silver. Frame Color pickers left at the default white follow the theme; any
-- other colour wins. Alpha is never tinted: callers own opacity.

local _, addon = ...

local THEMES = {
	SILVER = { r = 1, g = 1, b = 1 },
	COPPER = { r = 1.0, g = 0.70, b = 0.45 },
}
addon.FrameThemeColors = THEMES

local function ResolveTheme()
	local choice = addon.GetDBValue and addon.GetDBValue("hud_frameTheme")
	if choice == "SILVER" or choice == "COPPER" then
		return choice
	end
	if addon.DefaultFrameTheme == "COPPER" then
		return "COPPER"
	end
	return "SILVER"
end

function addon.GetFrameTint()
	return THEMES[ResolveTheme()]
end

-- Tints a white-based frame colour (frames without a Frame Color picker).
function addon.TintFrameColor(r, g, b, a)
	local tint = addon.GetFrameTint()
	return r * tint.r, g * tint.g, b * tint.b, a
end

-- Frame Color picker composition: exact white follows the theme; any other colour wins.
function addon.ResolvePickerFrameColor(r, g, b, a)
	if r == 1 and g == 1 and b == 1 then
		return addon.TintFrameColor(1, 1, 1, a)
	end
	return r, g, b, a
end
