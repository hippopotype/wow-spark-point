-- SparkPoint Slot Provider Registry
-- Generic interface for inner ring slot data providers (GCD, future swing/cooldown)

local _, addon = ...

local SlotProviders = {}
addon.SlotProviders = SlotProviders

local registry = {}

--------------------------------------------------------------------------------
-- Register a provider
-- provider must implement:
--   provider.id           (string)
--   provider.displayName  (string)
--   provider:GetProgress() -> {
--       progress=0..1,
--       current=number|nil,          -- optional raw value for StatusBar-backed widgets
--       max=number|nil,              -- optional max for StatusBar-backed widgets
--       active=bool,
--       show=bool,                  -- optional; defaults to `active`
--       barColor={r,g,b,a}|nil,     -- optional
--   }
--   provider:Enable()
--   provider:Disable()
--------------------------------------------------------------------------------
function SlotProviders:Register(id, provider)
	registry[id] = provider
end

--------------------------------------------------------------------------------
-- Get a provider by ID
--------------------------------------------------------------------------------
function SlotProviders:Get(id)
	return registry[id]
end

--------------------------------------------------------------------------------
-- Get all registered providers
--------------------------------------------------------------------------------
function SlotProviders:GetAll()
	return registry
end

--------------------------------------------------------------------------------
-- Build dropdown options for settings UI
-- Returns array of {value, label} for AddDropdown
--------------------------------------------------------------------------------
function SlotProviders:GetDropdownOptions()
	local options = {
		{value = "NONE", label = addon.L and addon.L["None"] or "None"},
	}

	local ids = {}
	for id in pairs(registry) do
		table.insert(ids, id)
	end
	table.sort(ids)

	for _, id in ipairs(ids) do
		local provider = registry[id]
		table.insert(options, {value = id, label = provider.displayName})
	end
	return options
end
