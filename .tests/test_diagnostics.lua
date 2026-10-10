-- /sparkpoint status content.

return function(T)
	return {
		{
			name = "status lists game, capabilities, module states and registries",
			fn = function()
				local addon = {
					VERSION = "1.6.0",
					Flavor = {
						GetDiagnostics = function()
							return { game = "Forever", interface = 16001, capabilities = { specs = false, cooldownViewer = true } }
						end,
					},
					ControlCenter = {
						GetAllModules = function()
							return {
								{ name = "Cast Ring", dbKey = "moduleEnabled_Cast", isEnabled = true },
								{ name = "Assisted Highlight", dbKey = "moduleEnabled_AssistedHighlight", isEnabled = false },
							}
						end,
						GetUnavailableReason = function(_, dbKey)
							if dbKey == "moduleEnabled_AssistedHighlight" then
								return "requires assistedCombat"
							end
						end,
					},
					SlotProviders = {
						GetDropdownOptions = function()
							return { { value = "NONE", label = "None" }, { value = "GCD", label = "GCD" } }
						end,
					},
					BarProviders = {
						GetDropdownOptions = function()
							return { { value = "NONE", label = "None" }, { value = "HEALTH", label = "Health" } }
						end,
					},
					ClassResourceSystems = {
						GetRegisteredIDs = function()
							return { "GENERIC_PIPS", "ROGUE_COMBO_POINTS" }
						end,
					},
				}
				T.loadAddonFile("Core/Diagnostics.lua", addon)
				local text = table.concat(addon.Diagnostics.BuildStatusLines(), "\n")
				T.truthy(text:find("SparkPoint 1.6.0", 1, true), "version")
				T.truthy(text:find("Game: Forever (interface 16001)", 1, true), "game")
				T.truthy(text:find("cooldownViewer=true", 1, true), "capabilities sorted")
				T.truthy(text:find("specs=false", 1, true), "capabilities")
				T.truthy(text:find("Cast Ring: enabled", 1, true), "enabled module")
				T.truthy(text:find("Assisted Highlight: skipped (requires assistedCombat)", 1, true), "skipped module")
				T.truthy(text:find("Slot providers: GCD", 1, true), "slot providers without NONE")
				T.truthy(text:find("Bar providers: HEALTH", 1, true), "bar providers")
				T.truthy(text:find("Class resource systems: GENERIC_PIPS, ROGUE_COMBO_POINTS", 1, true), "systems")
			end,
		},
		{
			name = "ClassResourceSystems:GetRegisteredIDs is sorted",
			fn = function()
				local addon = {}
				T.loadAddonFile("Core/ClassResourceSystems.lua", addon)
				addon.ClassResourceSystems:Register("ZED", function() end)
				addon.ClassResourceSystems:Register("ALPHA", function() end)
				local ids = addon.ClassResourceSystems:GetRegisteredIDs()
				T.eq(ids[1], "ALPHA", "first")
				T.eq(ids[2], "ZED", "second")
			end,
		},
	}
end
