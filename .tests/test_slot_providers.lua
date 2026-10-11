-- Core/SlotProviders.lua: capability requirements and localized dropdown labels.

return function(T)
	local function loadRegistry(capabilities, L)
		local addon = {
			L = L or {},
			Has = function(name)
				return capabilities[name] == true
			end,
		}
		T.loadAddonFile("Core/SlotProviders.lua", addon)
		return addon.SlotProviders
	end

	local function optionValues(options)
		local values = {}
		for _, option in ipairs(options) do
			values[#values + 1] = option.value
		end
		return table.concat(values, ",")
	end

	return {
		{
			name = "provider without requires is always available",
			fn = function()
				local registry = loadRegistry({})
				local provider = { displayName = "GCD" }
				registry:Register("GCD", provider)
				T.eq(registry:Get("GCD"), provider, "Get")
				T.eq(optionValues(registry:GetDropdownOptions()), "NONE,GCD", "dropdown")
			end,
		},
		{
			name = "provider whose capability is missing is hidden from Get and the dropdown",
			fn = function()
				local registry = loadRegistry({ swingTimer = false })
				registry:Register("SWING_MH", { displayName = "Main Hand Swing", requires = { "swingTimer" } })
				T.eq(registry:Get("SWING_MH"), nil, "Get")
				T.eq(optionValues(registry:GetDropdownOptions()), "NONE", "dropdown")
			end,
		},
		{
			name = "provider whose capability is present is available",
			fn = function()
				local registry = loadRegistry({ swingTimer = true })
				local provider = { displayName = "Main Hand Swing", requires = { "swingTimer" } }
				registry:Register("SWING_MH", provider)
				T.eq(registry:Get("SWING_MH"), provider, "Get")
				T.eq(optionValues(registry:GetDropdownOptions()), "NONE,SWING_MH", "dropdown")
			end,
		},
		{
			name = "labels resolve through addon.L with a literal fallback",
			fn = function()
				local registry = loadRegistry({}, { ["Main Hand Swing"] = "Hauptwaffe" })
				registry:Register("A", { displayName = "Main Hand Swing" })
				registry:Register("B", { displayName = "Untranslated" })
				local options = registry:GetDropdownOptions()
				T.eq(options[2].label, "Hauptwaffe", "translated label")
				T.eq(options[3].label, "Untranslated", "fallback label")
			end,
		},
	}
end
