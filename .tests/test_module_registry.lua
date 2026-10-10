-- ControlCenter availability: capability requirements gate init, toggles and listing.

return function(T)
	local function newRegistry(capabilities, db)
		db = db or {}
		local addon = {
			DefaultValues = {},
			Has = function(name)
				return capabilities[name] == true
			end,
			GetDBValue = function(key)
				return db[key]
			end,
			SetDBValue = function(key, value)
				db[key] = value
			end,
			Modules = {},
			CallbackRegistry = { Trigger = function() end },
		}
		T.loadAddonFile("Core/ModuleRegistry.lua", addon)
		return addon.ControlCenter, db
	end

	local function addModule(cc, dbKey, requires, calls)
		cc:AddModule({
			name = dbKey,
			dbKey = dbKey,
			requires = requires,
			uiOrder = 1,
			toggleFunc = function(enabled)
				calls[#calls + 1] = dbKey .. ":" .. tostring(enabled)
			end,
		})
	end

	return {
		{
			name = "module with satisfied requires is available and initialised",
			fn = function()
				local cc = newRegistry({ cooldownViewer = true })
				local calls = {}
				addModule(cc, "moduleEnabled_CooldownManager", { "cooldownViewer" }, calls)
				T.eq(cc:IsAvailable("moduleEnabled_CooldownManager"), true, "available")
				cc:InitializeModules()
				T.eq(calls[1], "moduleEnabled_CooldownManager:true", "toggleFunc")
			end,
		},
		{
			name = "unsatisfied requires: skipped at init, hidden from list, reason given",
			fn = function()
				local cc = newRegistry({ assistedCombat = false }, { moduleEnabled_AssistedHighlight = true })
				local calls = {}
				addModule(cc, "moduleEnabled_AssistedHighlight", { "assistedCombat" }, calls)
				cc:InitializeModules()
				T.eq(#calls, 0, "toggleFunc must not run")
				T.eq(cc:IsAvailable("moduleEnabled_AssistedHighlight"), false, "available")
				T.eq(cc:GetUnavailableReason("moduleEnabled_AssistedHighlight"), "requires assistedCombat", "reason")
				T.eq(#cc:GetModulesSorted(), 0, "sorted list")
				T.eq(#cc:GetAllModules(), 1, "all modules")
			end,
		},
		{
			name = "enable/disable on an unavailable module is a no-op and keeps the saved value",
			fn = function()
				local cc, db = newRegistry({ assistedCombat = false }, { moduleEnabled_AssistedHighlight = true })
				local calls = {}
				addModule(cc, "moduleEnabled_AssistedHighlight", { "assistedCombat" }, calls)
				cc:InitializeModules()
				cc:DisableModule("moduleEnabled_AssistedHighlight")
				cc:EnableModule("moduleEnabled_AssistedHighlight")
				T.eq(#calls, 0, "toggleFunc")
				T.eq(db.moduleEnabled_AssistedHighlight, true, "saved value untouched")
			end,
		},
		{
			name = "unregistered module reports not loaded",
			fn = function()
				local cc = newRegistry({})
				T.eq(cc:IsAvailable("moduleEnabled_Nope"), false, "available")
				T.eq(cc:GetUnavailableReason("moduleEnabled_Nope"), "not loaded", "reason")
			end,
		},
		{
			name = "module without requires is always available",
			fn = function()
				local cc = newRegistry({})
				local calls = {}
				addModule(cc, "moduleEnabled_Cast", nil, calls)
				T.eq(cc:IsAvailable("moduleEnabled_Cast"), true, "available")
				T.eq(#cc:GetModulesSorted(), 1, "listed")
			end,
		},
	}
end
