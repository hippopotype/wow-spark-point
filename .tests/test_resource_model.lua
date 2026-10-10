-- ResourceModel behavior: retail snapshot must never change; no-spec flavors resolve empty.

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
			name = "Forever data is class-keyed and empty -> empty resources",
			fn = function()
				local resolveFor = Snapshot.NewResolver("Camelot", { "Data/ResourceModels_Forever.lua" })
				local resolved = resolveFor("ROGUE", 0, "ENERGY")
				T.eq(#resolved.resources, 0, "resources")
				T.eq(resolved.specModel, nil, "specModel")
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
