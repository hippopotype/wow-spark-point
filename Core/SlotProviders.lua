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
--   provider.requires     (array of addon.Has capabilities) -- optional; providers
--                         whose capabilities are missing are hidden from Get and the dropdown
--   provider:GetProgress() -> {
--       progress=0..1,
--       current=number|nil,          -- optional raw value for StatusBar-backed widgets
--       max=number|nil,              -- optional max for StatusBar-backed widgets
--       active=bool,
--       show=bool,                  -- optional; defaults to `active`
--       barColor={r,g,b,a}|nil,     -- optional
--       dimmed=bool|nil,            -- optional; slot fill drawn at reduced opacity
--   }
--   provider:Enable()
--   provider:Disable()
--------------------------------------------------------------------------------
function SlotProviders:Register(id, provider)
	registry[id] = provider
end

-- A provider is available when it declares no requirements or every required
-- capability is present on this client (flavor capability layer, Core/Flavor.lua).
local function IsAvailable(provider)
	local requires = provider.requires
	if not requires then
		return true
	end
	for _, capability in ipairs(requires) do
		if not addon.Has(capability) then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Get a provider by ID (nil when unknown or unavailable on this client)
--------------------------------------------------------------------------------
function SlotProviders:Get(id)
	local provider = registry[id]
	if provider and IsAvailable(provider) then
		return provider
	end
	return nil
end

--------------------------------------------------------------------------------
-- Build dropdown options for settings UI
-- Returns array of {value, label} for AddDropdown. Labels are localized here, at
-- call time, because Localization/enUS.lua loads after the providers.
--------------------------------------------------------------------------------
function SlotProviders:GetDropdownOptions()
	local L = addon.L or {}
	local options = {
		{ value = "NONE", label = L["None"] or "None" },
	}

	local ids = {}
	for id, provider in pairs(registry) do
		if IsAvailable(provider) then
			table.insert(ids, id)
		end
	end
	table.sort(ids)

	for _, id in ipairs(ids) do
		local displayName = registry[id].displayName
		table.insert(options, { value = id, label = L[displayName] or displayName })
	end
	return options
end
