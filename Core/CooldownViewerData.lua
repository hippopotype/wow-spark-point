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
-- unordered one.

local _, addon = ...
local Util = addon.Util
local Bridge = addon.CooldownViewerBridge
local CallbackRegistry = addon.CallbackRegistry

local CooldownViewerData = {}
addon.CooldownViewerData = CooldownViewerData

CooldownViewerData.CATEGORY = {
	ESSENTIAL = 0,
	UTILITY = 1,
	TRACKEDBUFF = 2,
}

local entriesByCategory = {}
local pendingRefresh = false
-- True while Blizzard's display data is dirty. We must not build it (see the Bridge
-- header, rule 3); the RefreshLayout post-hook retries once Blizzard has built it.
local pendingDisplayData = false

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

-- Returns ids, or nil when Blizzard's display data is still being built. nil means
-- "keep what you have" -- it must NOT fall through to the raw category set, which
-- is a materially different display (header comment).
local function ResolveIDs(category)
	if Bridge:IsSupported() then
		local ids, reason = Bridge:GetOrderedIDs(category)
		if ids then
			return ids
		end
		if reason == "PENDING" then
			return nil
		end
	end

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

-- The combat gate is kept as a conservative default: Refresh rebuilds every widget
-- and nothing needs that mid-fight. It is NOT what prevents taint -- the Bridge's
-- raw reads are (rule 3). The dropped request is replayed on PLAYER_REGEN_ENABLED.
function CooldownViewerData:Refresh()
	if InCombatLockdown() then
		pendingRefresh = true
		return
	end
	pendingRefresh = false
	pendingDisplayData = false
	for _, category in pairs(self.CATEGORY) do
		local ids = ResolveIDs(category)
		if ids == nil then
			-- Keep this category's previous entries until Blizzard has built its data.
			pendingDisplayData = true
		else
			local entries = {}
			for _, cooldownID in ipairs(ids) do
				local entry = BuildEntry(cooldownID)
				if entry then
					entries[#entries + 1] = entry
				end
			end
			entriesByCategory[category] = entries
		end
	end
	CallbackRegistry:Trigger("CooldownViewer.EntriesChanged")
end

function CooldownViewerData:HasPendingDisplayData()
	return pendingDisplayData
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

-- What the HUD renders, in the player's Blizzard Cooldown Manager order.
function CooldownViewerData:GetEntries(category)
	return entriesByCategory[category] or {}
end
