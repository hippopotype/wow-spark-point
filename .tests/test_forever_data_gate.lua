-- Data/*_Forever.lua: inert unless Core/Flavor.lua says Forever. Retail clients that do
-- not know the camelot game type ignore [AllowLoadGameType camelot] and load these files.

return function(T)
	local FILES = {
		"Data/FrameTheme_Forever.lua",
		"Data/ResourceModels_Forever.lua",
		"Data/SwingQueueSpells_Forever.lua",
		"Data/Defaults_Forever.lua",
	}

	local function newAddon(game)
		local calls = {}
		local addon = {
			Flavor = { game = game },
			ResourceModel = {
				SetModelData = function(_, data)
					calls[#calls + 1] = data
				end,
			},
		}
		T.loadAddonFile("Core/Defaults.lua", addon)
		return addon, calls
	end

	local function loadAll(addon)
		for _, path in ipairs(FILES) do
			T.loadAddonFile(path, addon)
		end
	end

	return {
		{
			name = "Forever data files change nothing on Standard",
			fn = function()
				local addon, calls = newAddon("Standard")
				loadAll(addon)
				T.eq(addon.DefaultFrameTheme, nil, "frame theme")
				T.eq(addon.SwingQueueSpells, nil, "swing queue spells")
				T.eq(#calls, 0, "resource model data")
				T.eq(addon.DefaultValues.innerslot_outer_provider, "GCD", "outer slot default")
			end,
		},
		{
			name = "Forever data files apply on Forever",
			fn = function()
				local addon, calls = newAddon("Forever")
				loadAll(addon)
				T.eq(addon.DefaultFrameTheme, "COPPER", "frame theme")
				T.truthy(addon.SwingQueueSpells and addon.SwingQueueSpells.WARRIOR, "swing queue spells")
				T.eq(#calls, 1, "resource model data")
				T.eq(addon.DefaultValues.innerslot_outer_provider, "SWING", "outer slot default")
			end,
		},
	}
end
