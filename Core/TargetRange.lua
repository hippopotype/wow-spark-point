-- SparkPoint Target Range service
-- Answers "is my target inside the castable range of a reference spell?" for consumers
-- such as the Decorative Ring tint. Addons cannot read target distance, so range means
-- C_Spell.IsSpellInRange against a per-class candidate spell (Data/RangeSpells_*.lua),
-- chosen by the player or picked automatically.
-- Each evaluation classifies the target as HOSTILE (attackable, alive), FRIENDLY
-- (assistable, alive, not the player) or nil, and checks that kind's spell. Friendly
-- targets are checked only when targetRange_friendlyEnabled is on; otherwise they read
-- UNKNOWN without resolving a friendly spell or making a range call; the target is still
-- classified each tick.
-- A spell with a minimum range also checks a melee companion (the first known candidate
-- of the same kind with no minimum range that reaches no further than the dead zone), so
-- being too close counts as in range.
-- Polls only: it never calls C_Spell.EnableSpellRangeCheck and never listens for
-- SPELL_RANGE_CHECK_UPDATE. That toggle is shared and other code (the Cooldown Viewer,
-- other addons) turns it off, so the event cannot be trusted; IsSpellInRange needs no
-- enable call, and Blizzard's own hostile-target bar polls it bare on a ticker.
-- Consumers Acquire/Release by owner name; with no owners the service is fully idle.

local _, addon = ...
local Util = addon.Util

local TargetRange = {}
addon.TargetRange = TargetRange

local DEFAULT_KIND = "HOSTILE"
-- Per-kind candidate list (addon field) and saved-choice key ({ [class] = spellID }).
local KINDS = {
	HOSTILE = { list = "RangeSpells", dbKey = "targetRange_spell" },
	FRIENDLY = { list = "FriendlyRangeSpells", dbKey = "targetRange_friendlySpell" },
}
local AUTO = "AUTO"
local TICK_INTERVAL = 0.1
local EVENTS = { "PLAYER_TARGET_CHANGED", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_EQUIPMENT_CHANGED" }

local owners = {}
local ownerCount = 0
local state = "UNKNOWN"
local lastKind
local resolution = {}
-- The candidate that answered the last evaluation (nil when none did), and its kind.
local activeSpell
local activeKind
local ticker
local refreshQueued = false

local EL = CreateFrame("Frame")

local function Text(key, fallback)
	local L = addon.L
	return (L and L[key]) or fallback
end

-- Calls fn(...) under pcall and reads the result as a boolean; nil when the call
-- fails or the value is not an accessible boolean.
local function ReadBoolean(fn, ...)
	if not fn then
		return nil
	end
	local ok, value = pcall(fn, ...)
	if not ok then
		return nil
	end
	return Util.GetAccessibleBoolean(value, nil)
end

local function GetSpellInfo(spell)
	local api = _G.C_Spell
	if not (api and api.GetSpellInfo) then
		return nil
	end
	local ok, info = pcall(api.GetSpellInfo, spell)
	if ok and type(info) == "table" then
		return info
	end
	return nil
end

local function GetInfoName(info)
	local name = info and info.name
	if type(name) == "string" and not (_G.issecretvalue and _G.issecretvalue(name)) then
		return name
	end
	return nil
end

local function GetInfoRange(info, field)
	local value = info and info[field]
	if Util.IsAccessibleNumber(value) and value > 0 then
		return value
	end
	return 0
end

local function IsKnown(spellID)
	local api = _G.C_SpellBook
	local fn = api and (api.IsSpellKnown or api.IsSpellInSpellBook)
	return ReadBoolean(fn, spellID) == true
end

-- Returns the candidate when the player knows it, by ID or (Forever ranks) by name.
local function ResolveCandidate(spellID)
	local info = GetSpellInfo(spellID)
	local name = GetInfoName(info)
	local identifier
	if IsKnown(spellID) then
		identifier = spellID
	elseif name then
		local rankInfo = GetSpellInfo(name)
		local rankID = rankInfo and rankInfo.spellID
		if Util.IsAccessibleNumber(rankID) and IsKnown(rankID) then
			identifier = name
			info = rankInfo
		end
	end
	if not (identifier and name) then
		return nil
	end
	return {
		id = spellID,
		name = name,
		identifier = identifier,
		minRange = GetInfoRange(info, "minRange"),
		maxRange = GetInfoRange(info, "maxRange"),
	}
end

local function GetClass()
	return addon.API and addon.API.GetPlayerClass and addon.API.GetPlayerClass()
end

-- Returns the KINDS entry for kind (default HOSTILE); nil for an unknown kind.
local function GetKind(kind)
	return KINDS[kind or DEFAULT_KIND]
end

local function GetKnownCandidates(kind)
	local def = GetKind(kind)
	local lists = def and addon[def.list]
	local class = GetClass()
	local list = type(lists) == "table" and class and lists[class]
	local candidates = {}
	if type(list) ~= "table" then
		return candidates
	end
	for _, spellID in ipairs(list) do
		local candidate = ResolveCandidate(spellID)
		if candidate then
			candidates[#candidates + 1] = candidate
		end
	end
	return candidates
end

-- Automatic picks the first known candidate: lists are ordered longest reach first and
-- the melee companion covers "too close" for spells with a minimum range.
local function PickAutomatic(candidates)
	return candidates[1]
end

-- For a spell with a minimum range: the first other known candidate with no minimum
-- range that reaches no further than the dead zone (a true melee check).
local function FindCompanion(spell, candidates)
	if not (spell and spell.minRange > 0) then
		return nil
	end
	for _, candidate in ipairs(candidates) do
		if candidate ~= spell and candidate.minRange == 0 and candidate.maxRange <= spell.minRange then
			return candidate
		end
	end
	return nil
end

-- Saved choice wins when it is a known candidate; otherwise Automatic applies.
local function Resolve(kind)
	local candidates = GetKnownCandidates(kind)
	local saved = TargetRange:GetSavedSpell(kind)
	local spell, auto
	if saved then
		for _, candidate in ipairs(candidates) do
			if candidate.id == saved then
				spell, auto = candidate, false
				break
			end
		end
	end
	if not spell then
		spell, auto = PickAutomatic(candidates), true
	end
	return { spell = spell, auto = auto, candidates = candidates, companion = FindCompanion(spell, candidates) }
end

local function CheckRange(identifier)
	local api = _G.C_Spell
	return ReadBoolean(api and api.IsSpellInRange, identifier, "target")
end

-- Returns "HOSTILE", "FRIENDLY" or nil (spec F1). Attack wins over assist; an
-- inaccessible read gives nil, except UnitIsUnit, where it counts as not-self.
local function ClassifyTarget()
	if ReadBoolean(_G.UnitExists, "target") ~= true then
		return nil
	end
	local canAttack = ReadBoolean(_G.UnitCanAttack, "player", "target")
	if canAttack == nil then
		return nil
	elseif canAttack then
		return ReadBoolean(_G.UnitIsDeadOrGhost, "target") == false and "HOSTILE" or nil
	end
	if ReadBoolean(_G.UnitIsUnit, "target", "player") == true then
		return nil
	end
	if ReadBoolean(_G.UnitCanAssist, "player", "target") ~= true then
		return nil
	end
	return ReadBoolean(_G.UnitIsDeadOrGhost, "target") == false and "FRIENDLY" or nil
end

local function IsFriendlyEnabled()
	return addon.GetDBValue("targetRange_friendlyEnabled") == true
end

local function Evaluate()
	-- Set again below only when a candidate answers.
	activeSpell, activeKind = nil, nil
	local kind = ClassifyTarget()
	lastKind = kind
	if not kind then
		return "UNKNOWN"
	end
	-- Opt-in off: no friendly spell resolution and no range call.
	if kind == "FRIENDLY" and not IsFriendlyEnabled() then
		return "UNKNOWN"
	end
	resolution[kind] = resolution[kind] or Resolve(kind)
	local res = resolution[kind]
	local spell = res.spell
	if not spell then
		return "UNKNOWN"
	end
	local inRange = CheckRange(spell.identifier)
	local answered = inRange ~= nil and spell or nil
	-- Too close for a min-range spell: the melee companion answering true wins.
	local companion = res.companion
	local companionInRange
	if inRange ~= true and companion then
		companionInRange = CheckRange(companion.identifier)
		if companionInRange == true then
			inRange, answered = true, companion
		end
	end
	-- Automatic only: a candidate that cannot check (Forever Shoot spells that do not
	-- match the equipped weapon) falls through to the next known one. The companion's
	-- answer is reused rather than asked again.
	if inRange == nil and res.auto then
		for _, candidate in ipairs(res.candidates) do
			if candidate ~= spell then
				if candidate == companion then
					inRange = companionInRange
				else
					inRange = CheckRange(candidate.identifier)
				end
				if inRange ~= nil then
					answered = candidate
					break
				end
			end
		end
	end
	if answered then
		activeSpell, activeKind = answered, kind
	end
	if inRange == true then
		return "IN_RANGE"
	elseif inRange == false then
		return "OUT_OF_RANGE"
	end
	return "UNKNOWN"
end

local function SetState(newState)
	if newState == state then
		return
	end
	state = newState
	addon.CallbackRegistry:Trigger("TargetRangeChanged", newState)
end

local function StopTicker()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function SyncTicker()
	local wanted = ownerCount > 0 and ReadBoolean(_G.UnitExists, "target") == true
	if wanted and not ticker then
		local ok, handle = pcall(_G.C_Timer.NewTicker, TICK_INTERVAL, function()
			TargetRange:Tick()
		end)
		ticker = ok and handle or nil
	elseif not wanted then
		StopTicker()
	end
end

local function ClearCache()
	resolution = {}
	activeSpell, activeKind = nil, nil
end

-- Re-evaluates now and starts or stops the ticker; keeps the resolution cache.
local function Update()
	if ownerCount == 0 then
		return
	end
	TargetRange:Tick()
	SyncTicker()
end

-- Clears the resolution cache, then updates.
-- Takes no arguments: setting callbacks call it with (owner, value, userInput).
local function Refresh()
	if ownerCount == 0 then
		return
	end
	ClearCache()
	Update()
end

local function QueueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	_G.C_Timer.After(0, function()
		refreshQueued = false
		Refresh()
	end)
end

local function FormatLabel(candidate)
	local function Yards(value)
		return math.floor(value + 0.5)
	end
	if candidate.maxRange == 0 then
		return string.format(Text("Range Spell Label Melee", "%s (melee)"), candidate.name)
	elseif candidate.minRange > 0 then
		return string.format(Text("Range Spell Label MinMax", "%s (%d–%d yd)"), candidate.name, Yards(candidate.minRange), Yards(candidate.maxRange))
	end
	return string.format(Text("Range Spell Label", "%s (%d yd)"), candidate.name, Yards(candidate.maxRange))
end

--------------------------------------------------------------------------------
-- Event handlers
--------------------------------------------------------------------------------
-- A new target needs no new spell: evaluate without clearing the cache.
function TargetRange:PLAYER_TARGET_CHANGED()
	Update()
end

function TargetRange:SPELLS_CHANGED()
	QueueRefresh()
end

function TargetRange:PLAYER_ENTERING_WORLD()
	QueueRefresh()
end

-- Weapon swaps are handled by the per-tick Automatic fallthrough; this refresh is a
-- cheap hedge so known-spell changes from equipment are picked up.
function TargetRange:PLAYER_EQUIPMENT_CHANGED()
	QueueRefresh()
end

function TargetRange:Tick()
	if ownerCount == 0 then
		return
	end
	SetState(Evaluate())
end

EL:SetScript("OnEvent", function(_, event, ...)
	if TargetRange[event] then
		TargetRange[event](TargetRange, event, ...)
	end
end)

for _, def in pairs(KINDS) do
	addon.CallbackRegistry:RegisterSettingCallback(def.dbKey, Refresh, TargetRange)
end
addon.CallbackRegistry:RegisterSettingCallback("targetRange_friendlyEnabled", Refresh, TargetRange)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
function TargetRange:Acquire(owner)
	if owner == nil or owners[owner] then
		return
	end
	owners[owner] = true
	ownerCount = ownerCount + 1
	if ownerCount == 1 then
		for _, event in ipairs(EVENTS) do
			pcall(EL.RegisterEvent, EL, event)
		end
		Refresh()
	end
end

function TargetRange:Release(owner)
	if owner == nil or not owners[owner] then
		return
	end
	owners[owner] = nil
	ownerCount = ownerCount - 1
	if ownerCount == 0 then
		EL:UnregisterAllEvents()
		StopTicker()
		ClearCache()
		lastKind = nil
		SetState("UNKNOWN")
	end
end

function TargetRange:GetState()
	return state
end

-- The kind from the last evaluation: "HOSTILE", "FRIENDLY" or nil (nil with no owners).
function TargetRange:GetTargetKind()
	return lastKind
end

-- The candidate that produced the last answer for the current target kind: the resolved
-- spell, its melee companion or an Automatic fallthrough. nil with no owners, after a
-- cache clear, or when the last answer was for another kind.
function TargetRange:GetActiveSpell()
	if not (activeSpell and activeKind == lastKind) then
		return nil, nil
	end
	return activeSpell.id, activeSpell.name
end

-- Recomputes on every call (no cache), so Diagnostics always sees the live pick.
function TargetRange:GetResolvedSpell(kind)
	if not GetKind(kind) then
		return nil, nil, nil
	end
	local spell = Resolve(kind).spell
	if not spell then
		return nil, nil, nil
	end
	return spell.id, spell.name, spell.identifier
end

function TargetRange:GetCandidates(kind)
	local out = {}
	for i, candidate in ipairs(GetKnownCandidates(kind)) do
		out[i] = {
			id = candidate.id,
			name = candidate.name,
			minRange = candidate.minRange,
			maxRange = candidate.maxRange,
		}
	end
	return out
end

function TargetRange:GetSavedSpell(kind)
	local def = GetKind(kind)
	if not def then
		return nil
	end
	local saved = addon.GetDBValue(def.dbKey)
	local class = GetClass()
	local value = type(saved) == "table" and class and saved[class]
	if type(value) == "number" then
		return value
	end
	return nil
end

function TargetRange:SetSavedSpell(spellID, kind)
	local def = GetKind(kind)
	local class = GetClass()
	if not (def and class) then
		return
	end
	local saved = addon.GetDBValue(def.dbKey)
	local copy = type(saved) == "table" and Util.DeepCopy(saved) or {}
	copy[class] = type(spellID) == "number" and spellID or nil
	addon.SetDBValue(def.dbKey, copy, true)
end

function TargetRange:GetDropdownOptions(kind)
	kind = kind or DEFAULT_KIND
	if not GetKind(kind) then
		return {}
	end
	local candidates = GetKnownCandidates(kind)
	-- The Automatic label describes the automatic rule, whatever is saved.
	local autoPick = PickAutomatic(candidates)
	local autoLabel
	if autoPick then
		autoLabel = string.format(Text("Range Spell Automatic Resolved", "Automatic (%s)"), FormatLabel(autoPick))
	elseif kind == "FRIENDLY" then
		autoLabel = Text("Range Spell Automatic None Friendly", "Automatic (no friendly spell known)")
	else
		autoLabel = Text("Range Spell Automatic None", "Automatic (no range spell known)")
	end
	local options = { { value = AUTO, label = autoLabel } }
	local saved = self:GetSavedSpell(kind)
	local savedListed = false
	for _, candidate in ipairs(candidates) do
		options[#options + 1] = { value = tostring(candidate.id), label = FormatLabel(candidate) }
		savedListed = savedListed or candidate.id == saved
	end
	if saved and not savedListed then
		local name = GetInfoName(GetSpellInfo(saved)) or tostring(saved)
		options[#options + 1] = {
			value = tostring(saved),
			label = string.format(Text("Range Spell Unavailable", "%s (unavailable — using Automatic)"), name),
		}
	end
	return options
end

function TargetRange:GetDropdownValue(kind)
	if not GetKind(kind) then
		return nil
	end
	local saved = self:GetSavedSpell(kind)
	return saved and tostring(saved) or AUTO
end

function TargetRange:SetDropdownValue(value, kind)
	if value == AUTO then
		self:SetSavedSpell(nil, kind)
		return
	end
	local spellID = tonumber(value)
	if spellID then
		self:SetSavedSpell(spellID, kind)
	end
end
