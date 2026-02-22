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

function ControlCenter:InitializeModules()
	for _, moduleData in ipairs(self.modules) do
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
	end

	CallbackRegistry:Trigger("ModulesInitialized")
end

function ControlCenter:EnableModule(dbKey)
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

function ControlCenter:ToggleModule(dbKey)
	local moduleData = self.dbKeyToModule[dbKey]
	if moduleData then
		if moduleData.isEnabled then
			self:DisableModule(dbKey)
		else
			self:EnableModule(dbKey)
		end
	end
end

function ControlCenter:IsModuleEnabled(dbKey)
	local moduleData = self.dbKeyToModule[dbKey]
	return moduleData and moduleData.isEnabled
end

function ControlCenter:GetModule(dbKey)
	return self.dbKeyToModule[dbKey]
end

function ControlCenter:GetModuleByName(name)
	return addon.Modules[name]
end

function ControlCenter:GetAllModules()
	return self.modules
end

-- Get modules sorted by uiOrder for settings panel
function ControlCenter:GetModulesSorted()
	local sorted = {}
	for _, moduleData in ipairs(self.modules) do
		table.insert(sorted, moduleData)
	end
	table.sort(sorted, function(a, b)
		return (a.uiOrder or 999) < (b.uiOrder or 999)
	end)
	return sorted
end
