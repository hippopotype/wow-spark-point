-- Data/Defaults_Forever.lua: WoW Forever default overrides on top of Core/Defaults.lua.

return function(T)
	local function loadDefaults(withForever)
		local addon = {}
		T.loadAddonFile("Core/Defaults.lua", addon)
		if withForever then
			T.loadAddonFile("Data/Defaults_Forever.lua", addon)
		end
		return addon.DefaultValues
	end

	return {
		{
			name = "retail keeps GCD as the Outer Ring Slot source",
			fn = function()
				T.eq(loadDefaults(false).innerslot_outer_provider, "GCD", "retail outer source")
			end,
		},
		{
			name = "Forever defaults the Outer Ring Slot source to Swing (Auto)",
			fn = function()
				T.eq(loadDefaults(true).innerslot_outer_provider, "SWING", "forever outer source")
			end,
		},
		{
			name = "Forever changes no other default",
			fn = function()
				local retail, forever = loadDefaults(false), loadDefaults(true)
				for key, value in pairs(retail) do
					if key ~= "innerslot_outer_provider" and type(value) ~= "table" then
						T.eq(forever[key], value, key)
					end
				end
				for key in pairs(forever) do
					T.truthy(retail[key] ~= nil, "unexpected new default " .. key)
				end
			end,
		},
	}
end
