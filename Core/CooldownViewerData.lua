-- SparkPoint Cooldown Viewer Data
--
-- The only caller of C_CooldownViewer.*. Produces plain entry tables; no secret
-- value and no Blizzard frame ever leaves this file.
--
-- Two sources, and they disagree. The Bridge returns the player's configured,
-- ordered set. The raw C API (GetCooldownViewerCategorySet) returns the whole
-- category regardless of what the player enabled. Measured 2026-09-06:
-- Essential 3 vs 8, TrackedBuff 4 vs 22, Utility 16 vs 13 -- they differ in BOTH
-- directions. So the fallback is a materially different display, not merely an
-- unordered one, and that difference is surfaced to the user in settings.

local _, addon = ...
local Util = addon.Util
local Bridge = addon.CooldownViewerBridge
local CallbackRegistry = addon.CallbackRegistry
local GetDBValue = addon.GetDBValue
local SetDBValue = addon.SetDBValue

local CooldownViewerData = {}
addon.CooldownViewerData = CooldownViewerData

CooldownViewerData.CATEGORY = {
	ESSENTIAL = 0,
	UTILITY = 1,
	TRACKEDBUFF = 2,
}

local entriesByCategory = {}
-- Unfiltered mirror. The settings filter list must show entries the player has
-- hidden -- otherwise unchecking one would remove it from the list and make the
-- choice unrecoverable.
local allEntriesByCategory = {}
-- Per category: a single shared flag would report whichever category happened to be
-- iterated last, which is wrong whenever the three disagree.
local usingFallbackByCategory = {}
local pendingRefresh = false

-- Uses C_SpecializationInfo, NOT the global GetSpecialization/GetSpecializationInfo.
-- Those globals exist only when the loadDeprecationFallbacks CVar is set
-- (.clones/wow-ui-source/.../Blizzard_DeprecatedSpecialization/Deprecated_Specialization_Standard.lua:4).
-- With the CVar off they are nil, GetSpecKey silently returns 0, and every spec
-- shares one filter bucket -- the exact opposite of the per-spec requirement.
local function GetSpecKey()
	local S = C_SpecializationInfo
	if not (S and S.GetSpecialization and S.GetSpecializationInfo) then
		return 0
	end
	local index = S.GetSpecialization()
	if not index then
		return 0
	end
	local id = S.GetSpecializationInfo(index)
	return Util.IsAccessibleNumber(id) and id or 0
end

function CooldownViewerData:IsHidden(cooldownID)
	-- Guard before the table-key use below; this is public API and later callers
	-- source cooldownID from elsewhere. Invariant 1 makes a secret key a hard defect.
	if not Util.IsAccessibleNumber(cooldownID) then
		return false
	end
	local hidden = GetDBValue("cooldownmanager_hiddenEntries")
	if type(hidden) ~= "table" then
		return false
	end
	local specTable = hidden[GetSpecKey()]
	return type(specTable) == "table" and specTable[cooldownID] == true
end

function CooldownViewerData:SetHidden(cooldownID, hidden)
	if not Util.IsAccessibleNumber(cooldownID) then
		return
	end
	local stored = GetDBValue("cooldownmanager_hiddenEntries")
	local map = (type(stored) == "table") and Util.DeepCopy(stored) or {}
	local specKey = GetSpecKey()
	map[specKey] = map[specKey] or {}
	map[specKey][cooldownID] = hidden and true or nil
	SetDBValue("cooldownmanager_hiddenEntries", map, true)
	self:Refresh()
end

function CooldownViewerData:IsAvailable()
	if not C_CooldownViewer or not C_CooldownViewer.IsCooldownViewerAvailable then
		return false, "no API"
	end
	local ok, available, reason = pcall(C_CooldownViewer.IsCooldownViewerAvailable)
	if not ok then
		return false, "call failed"
	end
	return available == true, reason or ""
end

-- Separate from IsAvailable on purpose. With cooldownViewerEnabled off, the viewer
-- frames exist but never update, so BLIZZARD mode is silently dead -- but
-- SPARKPOINT mode reads C_Spell.GetSpellCooldownDuration and
-- GetCooldownViewerCategorySet, neither of which depends on that CVar. Folding the
-- CVar into IsAvailable would kill a working feature.
function CooldownViewerData:IsBlizzardModeUsable()
	if not self:IsAvailable() then
		return false
	end
	return not (GetCVar and GetCVar("cooldownViewerEnabled") == "0")
end

function CooldownViewerData:IsUsingFallback(category)
	return usingFallbackByCategory[category] == true
end

local function ResolveIDs(category)
	local ids = Bridge:IsSupported() and Bridge:GetOrderedIDs(category) or nil
	if ids then
		usingFallbackByCategory[category] = false
		return ids
	end

	usingFallbackByCategory[category] = true
	if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
		return {}
	end
	local ok, set = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, false)
	if not ok or type(set) ~= "table" then
		return {}
	end
	return set
end

local function BuildEntry(cooldownID)
	if not Util.IsAccessibleNumber(cooldownID) then
		return nil
	end
	-- GetCooldownViewerCooldownInfo is MayReturnNothing: nil-check every result.
	local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
	if not ok or not info then
		return nil
	end
	-- Never bare-compare a cooldownInfo boolean; see Util.GetAccessibleBoolean.
	if Util.GetAccessibleBoolean(info.isKnown, false) ~= true then
		return nil
	end

	-- Blizzard hides entries flagged HideAura from its own display; match that.
	-- Filter adapted from .clones/Cooldown-Companion/Config/Pickers.lua:121-153
	local flags = info.flags
	if Util.IsAccessibleNumber(flags) and Enum and Enum.CooldownSetSpellFlags then
		if bit.band(flags, Enum.CooldownSetSpellFlags.HideAura) ~= 0 then
			return nil
		end
	end

	-- Prefer the current override so talent-morphed spells show the right icon.
	local spellID = info.overrideSpellID or info.spellID
	if not Util.IsAccessibleNumber(spellID) then
		return nil
	end

	-- CooldownViewerCooldown has NO iconID field; the icon is a separate call.
	local okTex, iconFileID = pcall(C_Spell.GetSpellTexture, spellID)

	return {
		cooldownID = cooldownID,
		spellID = spellID,
		iconFileID = (okTex and Util.IsAccessibleNumber(iconFileID)) and iconFileID or nil,
		category = info.category,
		hasAura = Util.GetAccessibleBoolean(info.hasAura, false),
		charges = Util.GetAccessibleBoolean(info.charges, false),
		isKnown = true,
	}
end

-- The combat gate lives HERE, not in one caller: Refresh reaches
-- Bridge:GetOrderedIDs -> CheckBuildDisplayData, which lazily builds Blizzard's
-- cache. Running that under our taint writes tainted tables into it. Both direct
-- callers (Initialize, SetHidden) can fire mid-combat, so gating a single event
-- path is not enough. The dropped request is replayed on PLAYER_REGEN_ENABLED.
function CooldownViewerData:Refresh()
	if InCombatLockdown() then
		pendingRefresh = true
		return
	end
	pendingRefresh = false
	entriesByCategory = {}
	allEntriesByCategory = {}
	for _, category in pairs(self.CATEGORY) do
		local visible, all = {}, {}
		for _, cooldownID in ipairs(ResolveIDs(category)) do
			local entry = BuildEntry(cooldownID)
			if entry then
				all[#all + 1] = entry
				if not self:IsHidden(cooldownID) then
					visible[#visible + 1] = entry
				end
			end
		end
		entriesByCategory[category] = visible
		allEntriesByCategory[category] = all
	end
	CallbackRegistry:Trigger("CooldownViewer.EntriesChanged")
end

function CooldownViewerData:HasPendingRefresh()
	return pendingRefresh
end

-- Passthrough to the Bridge for Tracked Buff, SPARKPOINT mode: true / false / nil.
-- Widgets/CooldownIconWidget.lua branches on entry.hasAura (per-entry data) to call
-- this instead of the cooldown-based on/off read used for every other entry.
function CooldownViewerData:GetAuraActive(cooldownID)
	return Bridge:GetAuraActive(cooldownID)
end

-- What the HUD renders (hidden entries removed).
function CooldownViewerData:GetEntries(category)
	return entriesByCategory[category] or {}
end

-- What the settings filter list renders (hidden entries included, so they can be
-- unhidden again).
function CooldownViewerData:GetAllEntries(category)
	return allEntriesByCategory[category] or {}
end
