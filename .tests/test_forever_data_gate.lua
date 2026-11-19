-- Flavor data files: Data/*_Forever.lua is inert unless Core/Flavor.lua says Forever (and
-- Data/*_Standard.lua unless Standard). Retail clients that do
-- not know the camelot game type ignore [AllowLoadGameType camelot] and load these files.

return function(T)
	local FILES = {
		"Data/FrameTheme_Forever.lua",
		"Data/ResourceModels_Forever.lua",
		"Data/SwingQueueSpells_Forever.lua",
		"Data/Defaults_Forever.lua",
		"Data/RangeSpells_Standard.lua",
		"Data/RangeSpells_Forever.lua",
	}

	local function newAddon(game)
		local calls = {}
		local addon = {
			Flavor = { game = game },
			ResourceModel = {
				Roles = { MANA = "MANA", SECONDARY = "SECONDARY" },
				ResourceRef = function(key, role)
					return { key = key, role = role }
				end,
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
			name = "flavor data files: Forever ones change nothing on Standard",
			fn = function()
				local addon, calls = newAddon("Standard")
				loadAll(addon)
				T.eq(addon.DefaultFrameTheme, nil, "frame theme")
				T.eq(addon.SwingQueueSpells, nil, "swing queue spells")
				T.truthy(addon.RangeSpells and addon.RangeSpells.EVOKER, "standard list")
				T.truthy(addon.FriendlyRangeSpells and addon.FriendlyRangeSpells.EVOKER, "standard friendly list")
				for _, class in ipairs({ "DEATHKNIGHT", "ROGUE", "WARRIOR", "HUNTER", "DEMONHUNTER" }) do
					T.eq(addon.FriendlyRangeSpells[class], nil, "no friendly " .. class)
				end
				T.eq(#calls, 0, "resource model data")
				T.eq(addon.DefaultValues.innerslot_outer_provider, "GCD", "outer slot default")
			end,
		},
		{
			name = "flavor data files: Forever ones apply on Forever",
			fn = function()
				local addon, calls = newAddon("Forever")
				loadAll(addon)
				T.eq(addon.DefaultFrameTheme, "COPPER", "frame theme")
				T.truthy(addon.SwingQueueSpells and addon.SwingQueueSpells.WARRIOR, "swing queue spells")
				T.eq(addon.RangeSpells.EVOKER, nil, "forever list has no Evoker")
				T.truthy(addon.RangeSpells.WARRIOR, "forever warrior")
				T.eq(addon.FriendlyRangeSpells.EVOKER, nil, "forever friendly has no Evoker")
				T.truthy(addon.FriendlyRangeSpells.PRIEST, "forever friendly priest")
				for _, class in ipairs({ "DEATHKNIGHT", "ROGUE", "WARRIOR", "HUNTER", "DEMONHUNTER" }) do
					T.eq(addon.FriendlyRangeSpells[class], nil, "no friendly " .. class)
				end
				T.eq(#calls, 1, "resource model data")
				T.eq(addon.DefaultValues.innerslot_outer_provider, "SWING", "outer slot default")
			end,
		},
		{
			name = "range spell lists follow the flavor",
			fn = function()
				local onStandard = newAddon("Standard")
				T.loadAddonFile("Data/RangeSpells_Forever.lua", onStandard)
				T.eq(onStandard.RangeSpells, nil, "forever file on standard")
				T.eq(onStandard.FriendlyRangeSpells, nil, "forever friendly on standard")
				local onForever = newAddon("Forever")
				T.loadAddonFile("Data/RangeSpells_Standard.lua", onForever)
				T.eq(onForever.RangeSpells, nil, "standard file on forever")
				T.eq(onForever.FriendlyRangeSpells, nil, "standard friendly on forever")
			end,
		},
	}
end
