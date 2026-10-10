-- Builds a deterministic text snapshot of ResourceModel:Resolve for every class, spec
-- (0-4) and display power token. Shared by the snapshot test and its regeneration command:
--   lua .tests/gen_resource_snapshot.lua > .tests/fixtures/resource_model_snapshot.txt

local CLASSES = {
	"DEATHKNIGHT",
	"DEMONHUNTER",
	"DRUID",
	"EVOKER",
	"HUNTER",
	"MAGE",
	"MONK",
	"PALADIN",
	"PRIEST",
	"ROGUE",
	"SHAMAN",
	"WARLOCK",
	"WARRIOR",
}
local TOKENS = { "MANA", "ENERGY", "RAGE", "LUNAR_POWER", "FOCUS", "RUNIC_POWER", "FURY", "INSANITY", "MAELSTROM" }

local function BuildResourceSnapshot(resolveFor)
	local lines = {}
	for _, classTag in ipairs(CLASSES) do
		for spec = 0, 4 do
			for _, token in ipairs(TOKENS) do
				local resolved = resolveFor(classTag, spec, token)
				local parts = {}
				for _, entry in ipairs(resolved.resources) do
					parts[#parts + 1] = entry.key .. ":" .. tostring(entry.role)
				end
				lines[#lines + 1] = string.format("%s/%d/%s => %s", classTag, spec, token, table.concat(parts, ","))
			end
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

-- Loads the real ResourceModel (plus API and Flavor for the spec lookup) under stubs.
-- `extraFiles` lets later tasks add the per-game data file after ResourceModel.
local function NewResolver(game, extraFiles)
	local current = { classTag = "WARRIOR", spec = 0, token = "RAGE" }
	local addon = {}
	local stubs = {
		C_AddOns = {
			GetAddOnMetadata = function()
				return game
			end,
		},
		GetSpecialization = function()
			return current.spec
		end,
		C_SpecializationInfo = {
			GetSpecialization = function()
				return current.spec
			end,
		},
		UnitClass = function()
			return current.classTag, current.classTag
		end,
		UnitPowerType = function()
			return 0, current.token
		end,
		-- ResourceModel reads Enum.PowerType.* at load; values are irrelevant to the snapshot.
		Enum = setmetatable({}, {
			__index = function()
				return setmetatable({}, {
					__index = function(_, key)
						return key
					end,
				})
			end,
		}),
	}
	-- The test runner restores globals after every case, so these stubs do not leak.
	for name, value in pairs(stubs) do
		_G[name] = value
	end
	local files = { "Core/Flavor.lua", "Core/API.lua", "Core/ResourceModel.lua" }
	for _, path in ipairs(extraFiles or {}) do
		files[#files + 1] = path
	end
	for _, path in ipairs(files) do
		local chunk = assert(loadfile(path))
		chunk("SparkPoint", addon)
	end
	return function(classTag, spec, token)
		current.classTag, current.spec, current.token = classTag, spec, token
		return addon.ResourceModel:Resolve("player")
	end, addon
end

local M = { BuildResourceSnapshot = BuildResourceSnapshot, NewResolver = NewResolver }

-- Only write the snapshot when executed directly (dofile from the tests must not).
if arg and arg[0] and arg[0]:find("gen_resource_snapshot", 1, true) then
	local extra = {}
	local f = io.open("Data/ResourceModels_Standard.lua", "r")
	if f then
		f:close()
		extra = { "Data/ResourceModels_Standard.lua" }
	end
	io.write(BuildResourceSnapshot((NewResolver("Standard", extra))))
end

return M
