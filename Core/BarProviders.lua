-- SparkPoint Bar Provider Registry
-- Generic interface for horizontal bar slot data providers.

local _, addon = ...

local BarProviders = {}
addon.BarProviders = BarProviders

local registry = {}

--------------------------------------------------------------------------------
-- Register a provider
-- provider must implement:
--   provider.id           (string)
--   provider.displayName  (string)
--   provider:GetStatus() -> {
--       current=number|nil,
--       max=number|nil,
--       active=bool,
--       show=bool,                  -- optional; defaults to `active`
--       barColor={r,g,b,a}|nil,     -- optional
--   }
--   provider:Enable()
--   provider:Disable()
--------------------------------------------------------------------------------
function BarProviders:Register(id, provider)
	registry[id] = provider
end

--------------------------------------------------------------------------------
-- Get a provider by ID
--------------------------------------------------------------------------------
function BarProviders:Get(id)
	return registry[id]
end

--------------------------------------------------------------------------------
-- Get all registered providers
--------------------------------------------------------------------------------
function BarProviders:GetAll()
	return registry
end

--------------------------------------------------------------------------------
-- Build dropdown options for settings UI
--------------------------------------------------------------------------------
function BarProviders:GetDropdownOptions()
	local options = {}
	local ids = {}
	for id in pairs(registry) do
		table.insert(ids, id)
	end
	table.sort(ids)

	for _, id in ipairs(ids) do
		local provider = registry[id]
		table.insert(options, { value = id, label = provider.displayName })
	end

	return options
end
