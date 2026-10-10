-- SparkPoint Module Registry (ControlCenter)

local _, addon = ...
local CallbackRegistry = addon.CallbackRegistry

local ControlCenter = {}
addon.ControlCenter = ControlCenter

ControlCenter.modules = {}
ControlCenter.dbKeyToModule = {}

--------------------------------------------------------------------------------
-- Module Data Structure:
-- {
--     name = "Display Name",
--     dbKey = "moduleEnabled_Cast",  -- Key in SparkPointDB for enable/disable
--     description = "Module description",
--     toggleFunc = function(enabled) end,  -- Called on enable/disable
--     requires = { "capability" },  -- Optional: addon.Has() capabilities the module needs
--     categoryID = 1,  -- For grouping in settings UI
--     uiOrder = 1,     -- Sort order in settings panel
-- }
--------------------------------------------------------------------------------

function ControlCenter:AddModule(moduleData)
	if not moduleData.dbKey then
		error("SparkPoint: Module must have a dbKey: " .. (moduleData.name or "unknown"))
		return
	end

	table.insert(self.modules, moduleData)
	self.dbKeyToModule[moduleData.dbKey] = moduleData

	-- Store reference in addon.Modules by a clean name
	local cleanName = moduleData.dbKey:gsub("moduleEnabled_", "")
	addon.Modules[cleanName] = moduleData
end

-- nil when the module can run on this client; otherwise a short reason for diagnostics.
function ControlCenter:GetUnavailableReason(dbKey)
	local moduleData = self.dbKeyToModule[dbKey]
	if not moduleData then
		return "not loaded"
	end
	if moduleData.requires then
		for _, capability in ipairs(moduleData.requires) do
			if not addon.Has(capability) then
				return "requires " .. capability
			end
		end
	end
	return nil
end

function ControlCenter:IsAvailable(dbKey)
	return self:GetUnavailableReason(dbKey) == nil
end

function ControlCenter:InitializeModules()
	for _, moduleData in ipairs(self.modules) do
		if self:IsAvailable(moduleData.dbKey) then
			local enabled = addon.GetDBValue(moduleData.dbKey)

			if enabled == nil then
				-- Use default from DefaultValues
				enabled = addon.DefaultValues[moduleData.dbKey]
				if enabled == nil then
					enabled = true
				end
			end

			moduleData.isEnabled = enabled

			if moduleData.toggleFunc and enabled then
				moduleData.toggleFunc(true)
			end
		else
			moduleData.isEnabled = false
		end
	end

	CallbackRegistry:Trigger("ModulesInitialized")
end

function ControlCenter:EnableModule(dbKey)
	if not self:IsAvailable(dbKey) then
		return
	end
	local moduleData = self.dbKeyToModule[dbKey]
	if moduleData and not moduleData.isEnabled then
		moduleData.isEnabled = true
		addon.SetDBValue(dbKey, true, true)
		if moduleData.toggleFunc then
			moduleData.toggleFunc(true)
		end
		CallbackRegistry:Trigger("ModuleEnabled", dbKey)
	end
end

function ControlCenter:DisableModule(dbKey)
	if not self:IsAvailable(dbKey) then
		return
	end
	local moduleData = self.dbKeyToModule[dbKey]
	if moduleData and moduleData.isEnabled then
		moduleData.isEnabled = false
		addon.SetDBValue(dbKey, false, true)
		if moduleData.toggleFunc then
			moduleData.toggleFunc(false)
		end
		CallbackRegistry:Trigger("ModuleDisabled", dbKey)
	end
end

function ControlCenter:GetAllModules()
	return self.modules
end

-- Get modules sorted by uiOrder for settings panel
function ControlCenter:GetModulesSorted()
	local sorted = {}
	for _, moduleData in ipairs(self.modules) do
		if self:IsAvailable(moduleData.dbKey) then
			table.insert(sorted, moduleData)
		end
	end
	table.sort(sorted, function(a, b)
		return (a.uiOrder or 999) < (b.uiOrder or 999)
	end)
	return sorted
end
