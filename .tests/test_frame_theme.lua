-- Core/FrameTint.lua: Frame Theme resolution and frame colour composition.

return function(T)
	local function loadTheme(db, withForeverData)
		local addon = {
			GetDBValue = function(key)
				return db[key]
			end,
		}
		T.loadAddonFile("Core/FrameTint.lua", addon)
		if withForeverData then
			T.loadAddonFile("Data/FrameTheme_Forever.lua", addon)
		end
		return addon
	end

	local function assertColor(actual, expected, label)
		T.eq(actual[1], expected[1], label .. " r")
		T.eq(actual[2], expected[2], label .. " g")
		T.eq(actual[3], expected[3], label .. " b")
		T.eq(actual[4], expected[4], label .. " a")
	end

	local function tinted(addon, r, g, b, a)
		return { addon.TintFrameColor(r, g, b, a) }
	end

	local function copperTimes(addon, r, g, b, a)
		local copper = addon.FrameThemeColors.COPPER
		return { r * copper.r, g * copper.g, b * copper.b, a }
	end

	return {
		{
			name = "automatic without game data is silver (colours unchanged)",
			fn = function()
				local addon = loadTheme({ hud_frameTheme = "AUTO" }, false)
				assertColor(tinted(addon, 0.5, 0.25, 1, 0.8), { 0.5, 0.25, 1, 0.8 }, "silver")
			end,
		},
		{
			name = "automatic with the Forever data file is copper",
			fn = function()
				local addon = loadTheme({ hud_frameTheme = "AUTO" }, true)
				assertColor(tinted(addon, 0.5, 0.25, 1, 0.8), copperTimes(addon, 0.5, 0.25, 1, 0.8), "copper")
			end,
		},
		{
			name = "explicit Silver and Copper override automatic on either game",
			fn = function()
				local silverOnForever = loadTheme({ hud_frameTheme = "SILVER" }, true)
				assertColor(tinted(silverOnForever, 1, 1, 1, 1), { 1, 1, 1, 1 }, "silver on forever")
				local copperOnRetail = loadTheme({ hud_frameTheme = "COPPER" }, false)
				assertColor(tinted(copperOnRetail, 1, 1, 1, 1), copperTimes(copperOnRetail, 1, 1, 1, 1), "copper on retail")
			end,
		},
		{
			name = "garbage or missing theme values behave like automatic",
			fn = function()
				local garbageRetail = loadTheme({ hud_frameTheme = "PURPLE" }, false)
				assertColor(tinted(garbageRetail, 1, 1, 1, 1), { 1, 1, 1, 1 }, "garbage on retail")
				local missingForever = loadTheme({}, true)
				assertColor(tinted(missingForever, 1, 1, 1, 1), copperTimes(missingForever, 1, 1, 1, 1), "missing on forever")
			end,
		},
		{
			name = "no database accessor yet resolves as automatic",
			fn = function()
				local addon = loadTheme({}, true)
				addon.GetDBValue = nil
				assertColor(tinted(addon, 1, 1, 1, 0.5), copperTimes(addon, 1, 1, 1, 0.5), "early call")
			end,
		},
		{
			name = "copper is a real tint and silver is neutral",
			fn = function()
				local addon = loadTheme({}, false)
				local c, s = addon.FrameThemeColors.COPPER, addon.FrameThemeColors.SILVER
				T.eq(s.r + s.g + s.b, 3, "silver neutral")
				T.truthy(c.b < 1 and c.b < c.g and c.g <= c.r, "copper warm, not white")
			end,
		},
		{
			name = "white picker colour follows the theme",
			fn = function()
				local addon = loadTheme({ hud_frameTheme = "COPPER" }, false)
				assertColor({ addon.ResolvePickerFrameColor(1, 1, 1, 0.6) }, copperTimes(addon, 1, 1, 1, 0.6), "white picker")
			end,
		},
		{
			name = "custom picker colours win under every theme",
			fn = function()
				for _, theme in ipairs({ "AUTO", "SILVER", "COPPER" }) do
					local addon = loadTheme({ hud_frameTheme = theme }, true)
					assertColor({ addon.ResolvePickerFrameColor(0.2, 0.4, 0.9, 0.7) }, { 0.2, 0.4, 0.9, 0.7 }, theme)
					assertColor({ addon.ResolvePickerFrameColor(1, 1, 0.99, 1) }, { 1, 1, 0.99, 1 }, theme .. " near-white")
				end
			end,
		},
	}
end
