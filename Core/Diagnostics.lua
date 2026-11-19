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

-- Resolved class resources, the Druid form and (when a combo resource is active) the combo reading.
function Diagnostics.BuildResourceLine()
	local resolved = addon.ResourceModel:Resolve("player")
	local context = resolved.context or {}
	local keys = {}
	local comboDef
	for _, entry in ipairs(resolved.resources or {}) do
		keys[#keys + 1] = entry.key
		if not comboDef and entry.def and entry.def.comboPoints then
			comboDef = entry.def
		end
	end
	local form = "n/a"
	if context.classTag == "DRUID" and context.druidForm then
		form = tostring(context.druidForm)
	end
	local line = string.format("Class resources: %s; form %s", #keys > 0 and table.concat(keys, ", ") or "none", form)
	if comboDef then
		local cur, max = addon.API.GetComboPoints(comboDef.maxCount)
		local Util = addon.Util
		if Util.IsAccessibleNumber(cur) and Util.IsAccessibleNumber(max) then
			line = line .. string.format("; combo %d/%d (%s)", cur, max, addon.Has("comboPointsOnTarget") and "target-bound" or "player")
		else
			line = line .. "; combo unreadable"
		end
	end
	return line
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
	if addon.ResourceModel then
		lines[#lines + 1] = Diagnostics.BuildResourceLine()
	end
	if addon.TargetRange then
		local targetKind = addon.TargetRange:GetTargetKind()
		local activeID, activeName = addon.TargetRange:GetActiveSpell()
		local function describe(kind)
			local candidateID, name = addon.TargetRange:GetResolvedSpell(kind)
			if activeID and targetKind == (kind or "HOSTILE") then
				candidateID, name = activeID, activeName
			end
			if candidateID then
				return tostring(name) .. " (" .. tostring(candidateID) .. ")"
			end
			return "none"
		end
		lines[#lines + 1] = string.format(
			"Range tint: %s, friendly %s, spell %s, friendly spell %s, target %s, state %s",
			addon.GetDBBool("ring_rangeTintEnabled") and "on" or "off",
			addon.GetDBBool("targetRange_friendlyEnabled") and "on" or "off",
			describe(),
			describe("FRIENDLY"),
			tostring(targetKind or "none"),
			tostring(addon.TargetRange:GetState())
		)
	end
	return lines
end

function Diagnostics:PrintStatus()
	for _, line in ipairs(self.BuildStatusLines()) do
		print(line)
	end
end
