-- ResourceModel behavior: retail and Forever snapshots are golden; no-data flavors resolve empty.

local Snapshot = dofile(".tests/gen_resource_snapshot.lua")

local function readFile(path)
	local f = assert(io.open(path, "r"))
	local content = f:read("*a")
	f:close()
	return content
end

return function(T)
	return {
		{
			name = "retail resolution matches the golden snapshot",
			fn = function()
				local resolveFor = Snapshot.NewResolver("Standard", { "Data/ResourceModels_Standard.lua" })
				local actual = Snapshot.BuildResourceSnapshot(resolveFor)
				T.eq(actual == readFile(".tests/fixtures/resource_model_snapshot.txt"), true, "snapshot drifted; diff with gen_resource_snapshot.lua output")
			end,
		},
		{
			name = "spec unknown (nil) on retail resolves empty without error",
			fn = function()
				local _, addon = Snapshot.NewResolver("Standard", { "Data/ResourceModels_Standard.lua" })
				_G.C_SpecializationInfo = {
					GetSpecialization = function()
						return nil
					end,
				}
				T.eq(addon.API.GetSpecIndex(), 0, "GetSpecIndex")
				local resolved = addon.ResourceModel:Resolve("player")
				T.eq(#resolved.resources, 0, "resources")
			end,
		},
		{
			name = "Forever never calls the spec API",
			fn = function()
				local _, addon = Snapshot.NewResolver("Camelot")
				_G.C_SpecializationInfo = {
					GetSpecialization = function()
						error("spec API must not be called on Forever")
					end,
				}
				_G.GetSpecialization = nil
				T.eq(addon.API.GetSpecIndex(), 0, "GetSpecIndex")
				local resolved = addon.ResourceModel:Resolve("player")
				T.eq(#resolved.resources, 0, "resources")
			end,
		},
		{
			name = "Forever resolution matches the golden snapshot",
			fn = function()
				local resolveFor = Snapshot.NewResolver("Camelot", { "Data/ResourceModels_Forever.lua" })
				local actual = Snapshot.BuildResourceSnapshot(resolveFor, Snapshot.FOREVER_CLASSES, { 0 }, Snapshot.FOREVER_TOKENS)
				T.eq(
					actual == readFile(".tests/fixtures/resource_model_snapshot_forever.txt"),
					true,
					"Forever snapshot drifted; diff with gen_resource_snapshot.lua forever output"
				)
			end,
		},
		{
			name = "class-keyed data resolves by class and druid form",
			fn = function()
				local resolveFor, addon = Snapshot.NewResolver("Camelot")
				local RM = addon.ResourceModel
				RM:SetModelData({
					keyedBy = "class",
					models = {
						DRUID = {
							resources = { RM.ResourceRef("MANA", RM.Roles.MANA) },
							formOverrides = { CAT = { resources = { RM.ResourceRef("ENERGY") } } },
						},
					},
				})
				T.eq(resolveFor("DRUID", 0, "MANA").resources[1].key, "MANA", "caster form")
				T.eq(resolveFor("DRUID", 0, "ENERGY").resources[1].key, "ENERGY", "cat form")
			end,
		},
		{
			name = "colour settings list only reachable resources",
			fn = function()
				local function keysFor(game, files)
					local _, addon = Snapshot.NewResolver(game, files)
					T.loadAddonFile("Core/Util.lua", addon)
					T.loadAddonFile("Core/ResourceColors.lua", addon)
					local keys = {}
					for _, entry in ipairs(addon.ResourceColors:GetSettingEntries()) do
						keys[#keys + 1] = entry.key
					end
					return keys, addon
				end
				local retail = keysFor("Standard", { "Data/ResourceModels_Standard.lua" })
				T.eq(
					table.concat(retail, ","),
					"HEALTH,MANA,ENERGY,RAGE,FOCUS,FURY,RUNIC_POWER,LUNAR_POWER,INSANITY,MAELSTROM,RUNES,ROGUE_COMBO_POINTS,DRUID_COMBO_POINTS,HOLY_POWER,CHI,ARCANE_CHARGES,SOUL_SHARDS,ESSENCE,MAELSTROM_WEAPON",
					"retail unchanged"
				)
				T.eq(#retail, 19, "retail count")
				local forever = keysFor("Camelot", { "Data/ResourceModels_Forever.lua" })
				T.eq(table.concat(forever, ","), "HEALTH,MANA,ENERGY,RAGE,ROGUE_COMBO_POINTS,DRUID_COMBO_POINTS", "forever")
				local none, addon = keysFor("Standard")
				T.eq(next(addon.ResourceModel:GetReachableResourceKeys()), nil, "no reachable keys")
				T.eq(table.concat(none, ","), "HEALTH", "health only")
			end,
		},
		{
			name = "no registered data -> empty resources",
			fn = function()
				local resolveFor = Snapshot.NewResolver("Standard")
				T.eq(#resolveFor("WARLOCK", 1, "MANA").resources, 0, "resources")
			end,
		},
		{
			name = "SetModelData rejects an unknown keyedBy",
			fn = function()
				local _, addon = Snapshot.NewResolver("Standard")
				T.errors(function()
					addon.ResourceModel:SetModelData({ keyedBy = "race", models = {} })
				end, "keyedBy")
			end,
		},
	}
end
