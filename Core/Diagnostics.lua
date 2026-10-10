-- SparkPoint Diagnostics
-- /sparkpoint status: game flavor, capabilities, module availability and registries.
-- First thing to ask for in bug reports.

local _, addon = ...

local Diagnostics = {}
addon.Diagnostics = Diagnostics

local function JoinOptionValues(options)
	local values = {}
	for _, option in ipairs(options or {}) do
		if option.value ~= "NONE" then
			values[#values + 1] = option.value
		end
	end
	return table.concat(values, ", ")
end

function Diagnostics.BuildStatusLines()
	local lines = {}
	local info = addon.Flavor.GetDiagnostics()

	lines[#lines + 1] = "SparkPoint " .. tostring(addon.VERSION)
	lines[#lines + 1] = string.format("Game: %s (interface %s)", info.game, tostring(info.interface))

	local names = {}
	for name in pairs(info.capabilities) do
		names[#names + 1] = name
	end
	table.sort(names)
	local capabilityParts = {}
	for _, name in ipairs(names) do
		capabilityParts[#capabilityParts + 1] = name .. "=" .. tostring(info.capabilities[name])
	end
	lines[#lines + 1] = "Capabilities: " .. table.concat(capabilityParts, ", ")

	lines[#lines + 1] = "Modules:"
	for _, moduleData in ipairs(addon.ControlCenter:GetAllModules()) do
		local reason = addon.ControlCenter:GetUnavailableReason(moduleData.dbKey)
		local state
		if reason then
			state = "skipped (" .. reason .. ")"
		else
			state = moduleData.isEnabled and "enabled" or "disabled"
		end
		lines[#lines + 1] = "  " .. tostring(moduleData.name) .. ": " .. state
	end

	lines[#lines + 1] = "Slot providers: " .. JoinOptionValues(addon.SlotProviders:GetDropdownOptions())
	lines[#lines + 1] = "Bar providers: " .. JoinOptionValues(addon.BarProviders:GetDropdownOptions())
	lines[#lines + 1] = "Class resource systems: " .. table.concat(addon.ClassResourceSystems:GetRegisteredIDs(), ", ")
	return lines
end

function Diagnostics:PrintStatus()
	for _, line in ipairs(self.BuildStatusLines()) do
		print(line)
	end
end
