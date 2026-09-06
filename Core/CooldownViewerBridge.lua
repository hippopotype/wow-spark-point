-- SparkPoint Cooldown Viewer Bridge
--
-- QUARANTINE. This is the only file in SparkPoint allowed to touch Blizzard's
-- Cooldown Manager Lua internals (CooldownViewerSettings and the viewer item
-- frames). Everything else consumes the three functions below and never sees a
-- Blizzard frame.
--
-- Two hard-won rules, measured in game 2026-09-06:
--
--  1. Identity comes from `cooldownInfo.spellID`, NEVER `itemFrame:GetSpellID()`.
--     In combat GetSpellID() returns a SECRET number while the struct field stays
--     plain. Calling the mixin method and comparing the result throws.
--
--  2. Aura durations and stack counts are UNREACHABLE. C_UnitAuras.GetAuraDuration,
--     C_UnitAuras.GetAuraApplicationDisplayCount and the item frame's own
--     GetApplicationsText() all error for tainted callers:
--       "Auras cannot be accessed when secret while tainted by 'SparkPoint'"
--     That is why GetAuraActive returns a bare boolean and nothing richer. The
--     boolean is read off Blizzard's Cooldown region via IsShown(), which is a
--     plain value that correctly tracks whether the aura is up.

local _, addon = ...
local Util = addon.Util

local CooldownViewerBridge = {}
addon.CooldownViewerBridge = CooldownViewerBridge

-- BuffBarCooldownViewer (category 3) is deliberately absent: TrackedBar is out of
-- scope, and requiring it in IsSupported would let one out-of-scope frame disable
-- the whole Bridge and silently force the materially different fallback set.
local VIEWER_BY_CATEGORY = {
	[0] = "EssentialCooldownViewer",
	[1] = "UtilityCooldownViewer",
	[2] = "BuffIconCooldownViewer",
}

-- cooldownID -> Blizzard item frame. Invalidated whenever Blizzard re-pools its
-- children; see InvalidateFrameMap and Task 7's RefreshLayout hook.
local frameMap = {}
local frameMapValid = false

-- Separates "the call succeeded" from "what it returned". Using a raw pcall tuple
-- as a predicate is the bug recorded in .skills/.private/class-resource.md:195-204.
--
-- Every call routed through here can throw for one of two reasons: the Blizzard
-- mixin method internally inspects secret aura data (GetApplicationsText does
-- `applications > 1`), or the frame/table is guarded against tainted access
-- (auraInstanceIDToItemFramesMap). Both are expected, not exceptional.
local function TryCall(fn, ...)
	local ok, result = pcall(fn, ...)
	if not ok then
		return false, nil
	end
	return true, result
end

local function GetSettingsDataProvider()
	local settings = _G.CooldownViewerSettings
	if not settings or not settings.GetDataProvider then
		return nil
	end
	local ok, provider = TryCall(settings.GetDataProvider, settings)
	if not ok or not provider then
		return nil
	end
	return provider
end

function CooldownViewerBridge:IsSupported()
	if not _G.CooldownViewerSettings then
		-- Blizzard_CooldownViewer has no LoadOnDemand today, but load it defensively
		-- rather than assume. Guard adapted from
		-- .clones/Cooldown-Companion/Config/Pickers.lua:169-172
		if C_AddOns and C_AddOns.LoadAddOn then
			pcall(C_AddOns.LoadAddOn, "Blizzard_CooldownViewer")
		end
	end
	if not _G.CooldownViewerSettings then
		return false
	end
	if not GetSettingsDataProvider() then
		return false
	end
	for _, name in pairs(VIEWER_BY_CATEGORY) do
		if not _G[name] then
			return false
		end
	end
	return true
end

-- Returns the player's configured, ordered set for a category, or nil.
--
-- This triggers Blizzard's CheckBuildDisplayData(), which lazily builds cached
-- tables. Running that under our taint writes tainted tables into Blizzard's
-- cache, so callers must only reach here out of combat and must cache the result.
-- Both prior-art addons agree: Cooldown-Companion calls it only from config UI
-- (Config/Pickers.lua:174-208); EnhanceQoL never calls it at all.
function CooldownViewerBridge:GetOrderedIDs(category)
	local provider = GetSettingsDataProvider()
	if not provider or not provider.GetOrderedCooldownIDsForCategory then
		return nil
	end

	if provider.CheckBuildDisplayData then
		TryCall(provider.CheckBuildDisplayData, provider)
	end

	local ok, ids = TryCall(provider.GetOrderedCooldownIDsForCategory, provider, category)
	if not ok or type(ids) ~= "table" then
		return nil
	end

	local result = {}
	for _, id in ipairs(ids) do
		if Util.IsAccessibleNumber(id) then
			result[#result + 1] = id
		end
	end
	-- An empty table is indistinguishable from a half-failed CheckBuildDisplayData,
	-- and returning it would make the caller's "nil -> fallback" branch unreachable.
	-- A genuinely empty category costs one wasted fallback call and nothing else.
	if #result == 0 then
		return nil
	end
	return result
end

function CooldownViewerBridge:InvalidateFrameMap()
	frameMap = {}
	frameMapValid = false
end

local function BuildFrameMap()
	frameMap = {}
	for _, name in pairs(VIEWER_BY_CATEGORY) do
		local viewer = _G[name]
		if viewer and Util.CanAccessFrameSafe(viewer) then
			local ok, children = TryCall(function()
				return { viewer:GetChildren() }
			end)
			if ok and children then
				for _, child in ipairs(children) do
					-- luacheck: push ignore 221
					-- luacheck cannot see that `info` receives TryCall's second return
					-- when CanAccessFrameSafe(child) is true; the multres only flows
					-- when this expression is used in the last position of the
					-- assignment, which Lua does but luacheck's flow analysis misses.
					local okInfo, info = Util.CanAccessFrameSafe(child) and TryCall(function()
						return child.cooldownInfo
					end)
					-- luacheck: pop
					if okInfo and info then
						local okID, cooldownID = TryCall(function()
							return info.cooldownID
						end)
						if okID and Util.IsAccessibleNumber(cooldownID) then
							frameMap[cooldownID] = child
						end
					end
				end
			end
		end
	end
	frameMapValid = true
end

-- Plain boolean for "is this tracked buff currently active", or nil if unknown.
-- Keyed on cooldownID rather than spellID so a spell present in two categories
-- resolves to the right frame.
function CooldownViewerBridge:GetAuraActive(cooldownID)
	if not Util.IsAccessibleNumber(cooldownID) then
		return nil
	end
	if not frameMapValid then
		BuildFrameMap()
	end

	local frame = frameMap[cooldownID]
	if not frame or not Util.CanAccessFrameSafe(frame) then
		return nil
	end

	local okCD, cooldownFrame = TryCall(frame.GetCooldownFrame, frame)
	if not okCD or not cooldownFrame then
		return nil
	end

	local okShown, shown = TryCall(cooldownFrame.IsShown, cooldownFrame)
	if not okShown then
		return nil
	end
	return shown == true
end
