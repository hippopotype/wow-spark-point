-- luacheck: globals WOW_PROJECT_ID WOW_PROJECT_CAMELOT
-- SparkPoint Flavor
-- The only file that knows which game client is running (retail "Standard" or "Forever").
-- Everything else asks addon.Has(capability). Add a capability only together with its
-- consumer, and give it a value in every game row.

local addonName, addon = ...

local function DetectGame()
	local game = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "X-Game")
	if game == "Camelot" then
		return "Forever"
	end
	if game == "Standard" or game == "Forever" then
		return game
	end
	if WOW_PROJECT_CAMELOT and WOW_PROJECT_ID == WOW_PROJECT_CAMELOT then
		return "Forever"
	end
	return "Standard"
end

local CAPABILITIES = {
	Standard = { specs = true, assistedCombat = true, cooldownViewer = true, swingTimer = false },
	Forever = { specs = false, assistedCombat = false, cooldownViewer = true, swingTimer = true },
}

local game = DetectGame()
local active = CAPABILITIES[game]
local interface = GetBuildInfo and select(4, GetBuildInfo()) or nil

local Flavor = { game = game }
addon.Flavor = Flavor

function addon.Has(capability)
	local value = active[capability]
	if value == nil then
		error("SparkPoint: unknown capability '" .. tostring(capability) .. "'", 2)
	end
	return value
end

function Flavor.GetDiagnostics()
	local capabilities = {}
	for name, value in pairs(active) do
		capabilities[name] = value
	end
	return { game = game, interface = interface, capabilities = capabilities }
end
