-- ResourceModel behavior: retail snapshot must never change; no-spec flavors resolve empty.

local Snapshot = dofile(".tests/gen_resource_snapshot.lua")

local function readFile(path)
	local f = assert(io.open(path, "r"))
	local content = f:read("*a")
	f:close()
	return content
end

local function standardExtras()
	local f = io.open("Data/ResourceModels_Standard.lua", "r")
	if f then
		f:close()
		return { "Data/ResourceModels_Standard.lua" }
	end
	return {}
end

return function(T)
	return {
		{
			name = "retail resolution matches the golden snapshot",
			fn = function()
				local resolveFor = Snapshot.NewResolver("Standard", standardExtras())
				local actual = Snapshot.BuildResourceSnapshot(resolveFor)
				T.eq(actual == readFile(".tests/fixtures/resource_model_snapshot.txt"), true, "snapshot drifted; diff with gen_resource_snapshot.lua output")
			end,
		},
		{
			name = "spec unknown (nil) on retail resolves empty without error",
			fn = function()
				local resolveFor, addon = Snapshot.NewResolver("Standard", standardExtras())
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
	}
end
