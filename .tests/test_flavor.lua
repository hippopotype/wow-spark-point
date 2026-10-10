-- Tests for Core/Flavor.lua: game detection, capability table, diagnostics.

return function(T)
	local function loadFlavor(xGame, projectID, camelotID)
		local addon = {}
		T.withGlobals({
			C_AddOns = {
				GetAddOnMetadata = function(_, field)
					if field == "X-Game" then
						return xGame
					end
				end,
			},
			WOW_PROJECT_ID = projectID or T.NIL,
			WOW_PROJECT_CAMELOT = camelotID or T.NIL,
			GetBuildInfo = function()
				return "1.60.1", "70338", "Oct 10 2026", 16001
			end,
		}, function()
			T.loadAddonFile("Core/Flavor.lua", addon)
		end)
		return addon
	end

	return {
		{
			name = "X-Game Standard -> Standard",
			fn = function()
				T.eq(loadFlavor("Standard").Flavor.game, "Standard")
			end,
		},
		{
			name = "X-Game Camelot -> Forever",
			fn = function()
				T.eq(loadFlavor("Camelot").Flavor.game, "Forever")
			end,
		},
		{
			name = "X-Game Forever (post-rename) -> Forever",
			fn = function()
				T.eq(loadFlavor("Forever").Flavor.game, "Forever")
			end,
		},
		{
			name = "unsubstituted X-Game falls back to project ID",
			fn = function()
				T.eq(loadFlavor("[Game]", 18, 18).Flavor.game, "Forever")
			end,
		},
		{
			name = "missing X-Game + Camelot project -> Forever",
			fn = function()
				T.eq(loadFlavor(nil, 18, 18).Flavor.game, "Forever")
			end,
		},
		{
			name = "missing X-Game + no Camelot constant -> Standard",
			fn = function()
				T.eq(loadFlavor(nil, 1, nil).Flavor.game, "Standard")
			end,
		},
		{
			name = "unknown X-Game value -> Standard",
			fn = function()
				T.eq(loadFlavor("Mists", 19, 18).Flavor.game, "Standard")
			end,
		},
		{
			name = "Standard capabilities",
			fn = function()
				local addon = loadFlavor("Standard")
				T.eq(addon.Has("specs"), true, "specs")
				T.eq(addon.Has("assistedCombat"), true, "assistedCombat")
				T.eq(addon.Has("cooldownViewer"), true, "cooldownViewer")
			end,
		},
		{
			name = "Forever capabilities",
			fn = function()
				local addon = loadFlavor("Camelot")
				T.eq(addon.Has("specs"), false, "specs")
				T.eq(addon.Has("assistedCombat"), false, "assistedCombat")
				T.eq(addon.Has("cooldownViewer"), true, "cooldownViewer")
			end,
		},
		{
			name = "unknown capability errors",
			fn = function()
				local addon = loadFlavor("Standard")
				T.errors(function()
					addon.Has("specz")
				end, "unknown capability 'specz'")
			end,
		},
		{
			name = "both games define the same capability keys",
			fn = function()
				local standard = loadFlavor("Standard").Flavor.GetDiagnostics().capabilities
				local forever = loadFlavor("Camelot").Flavor.GetDiagnostics().capabilities
				for key in pairs(standard) do
					T.truthy(forever[key] ~= nil, "Forever is missing capability " .. key)
				end
				for key in pairs(forever) do
					T.truthy(standard[key] ~= nil, "Standard is missing capability " .. key)
				end
			end,
		},
		{
			name = "diagnostics returns a copy and the interface",
			fn = function()
				local addon = loadFlavor("Camelot")
				local diagnostics = addon.Flavor.GetDiagnostics()
				T.eq(diagnostics.game, "Forever", "game")
				T.eq(diagnostics.interface, 16001, "interface")
				diagnostics.capabilities.specs = true
				T.eq(addon.Has("specs"), false, "mutating the copy must not change Has()")
			end,
		},
	}
end
