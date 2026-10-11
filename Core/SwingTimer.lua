-- SparkPoint Swing Timer service (WoW Forever)
-- Per-hand swing state from PLAYER_SWING and C_SwingTimer, consumed by the swing slot
-- providers (Providers/SwingTimer.lua). Never reads attack speed or haste: unit stats
-- are secret in combat; every PLAYER_SWING carries the next swing's duration instead.
-- Range checks are only ever enabled, never disabled: Blizzard_SwingTimer turns the
-- shared toggle off whenever its own bar stops needing it, so the events below
-- re-assert it.

local _, addon = ...
local Util = addon.Util

local SwingTimer = {}
addon.SwingTimer = SwingTimer

local HAND_BY_TYPE = { [0] = "MH", [1] = "OH", [2] = "RANGED" }
local TYPE_BY_HAND = { MH = 0, OH = 1, RANGED = 2 }

local EVENTS = {
	"PLAYER_SWING",
	"PLAYER_SWING_RANGE_UPDATE",
	"PLAYER_ENTER_COMBAT",
	"PLAYER_LEAVE_COMBAT",
	"START_AUTOREPEAT_SPELL",
	"STOP_AUTOREPEAT_SPELL",
	"PLAYER_TARGET_CHANGED",
	"PLAYER_ENTERING_WORLD",
	"WEAPON_SLOT_CHANGED",
	"CVAR_UPDATE",
	"CURRENT_SPELL_CAST_CHANGED",
	"ACTIONBAR_UPDATE_STATE",
}

local swings = {}
local outOfRange = {}
local meleeActive = false
local rangedActive = false
local queued = false
local refCount = 0

local EL = CreateFrame("Frame")

local function ResetState()
	swings = {}
	outOfRange = {}
	meleeActive = false
	rangedActive = false
	queued = false
end

local function EnsureRangeChecks()
	local api = _G.C_SwingTimer
	if not (api and api.EnableRangeCheck) then
		return
	end
	for swingType = 0, 2 do
		pcall(api.EnableRangeCheck, swingType, true)
	end
end

local function PollRange()
	local api = _G.C_SwingTimer
	for hand, swingType in pairs(TYPE_BY_HAND) do
		local inRange
		if api and api.IsTargetWithinSwingRange then
			local ok, result = pcall(api.IsTargetWithinSwingRange, swingType)
			if ok then
				inRange = Util.GetAccessibleBoolean(result, nil)
			end
		end
		-- nil means "could not check" and counts as in range, as Blizzard does.
		outOfRange[hand] = inRange == false or nil
	end
end

-- Enabling does not push a range event, so every re-assert also polls the current
-- range (Blizzard polls right after enabling too).
local function ReassertRange()
	EnsureRangeChecks()
	PollRange()
end

local function IsCurrentSpell(identifier)
	local api = _G.C_Spell
	if not (api and api.IsCurrentSpell) then
		return false
	end
	local ok, result = pcall(api.IsCurrentSpell, identifier)
	if not ok then
		return false
	end
	return Util.GetAccessibleBoolean(result, false)
end

local function GetSpellName(spellID)
	local api = _G.C_Spell
	if not (api and api.GetSpellInfo) then
		return nil
	end
	local ok, info = pcall(api.GetSpellInfo, spellID)
	if ok and type(info) == "table" and type(info.name) == "string" then
		return info.name
	end
	return nil
end

-- True while one of the class's next-melee attacks (Heroic Strike, Cleave, Maul, Raptor
-- Strike) is queued. A spell name resolves to the player's known rank.
local function IsQueued()
	local spellsByClass = addon.SwingQueueSpells
	local class = addon.API and addon.API.GetPlayerClass and addon.API.GetPlayerClass()
	local spells = spellsByClass and class and spellsByClass[class]
	if not spells then
		return false
	end
	for _, spellID in ipairs(spells) do
		if IsCurrentSpell(spellID) then
			return true
		end
		local name = GetSpellName(spellID)
		if name and IsCurrentSpell(name) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------
-- Event handlers
--------------------------------------------------------------------------------
function SwingTimer:PLAYER_SWING(_, duration, swingType)
	if not (Util.IsAccessibleNumber(duration) and duration > 0 and Util.IsAccessibleNumber(swingType)) then
		return
	end
	local hand = HAND_BY_TYPE[swingType]
	if not hand then
		return
	end
	swings[hand] = { startTime = _G.GetTime(), duration = duration }
	if hand == "RANGED" then
		rangedActive = true
	else
		meleeActive = true
	end
	if hand == "MH" then
		queued = IsQueued()
	end
end

function SwingTimer:PLAYER_SWING_RANGE_UPDATE(_, swingType, isInRange, checksRange)
	if not Util.IsAccessibleNumber(swingType) then
		return
	end
	local hand = HAND_BY_TYPE[swingType]
	if not hand then
		return
	end
	local checking = Util.GetAccessibleBoolean(checksRange, false)
	local inRange = Util.GetAccessibleBoolean(isInRange, true)
	outOfRange[hand] = (checking and not inRange) or nil
end

function SwingTimer:PLAYER_ENTER_COMBAT()
	meleeActive = true
end

function SwingTimer:PLAYER_LEAVE_COMBAT()
	meleeActive = false
end

function SwingTimer:START_AUTOREPEAT_SPELL()
	rangedActive = true
end

function SwingTimer:STOP_AUTOREPEAT_SPELL()
	rangedActive = false
end

function SwingTimer:PLAYER_TARGET_CHANGED()
	ReassertRange()
end

function SwingTimer:PLAYER_ENTERING_WORLD()
	ReassertRange()
end

function SwingTimer:WEAPON_SLOT_CHANGED()
	ReassertRange()
end

function SwingTimer:CVAR_UPDATE()
	ReassertRange()
end

function SwingTimer:CURRENT_SPELL_CAST_CHANGED()
	queued = IsQueued()
end

function SwingTimer:ACTIONBAR_UPDATE_STATE()
	queued = IsQueued()
end

EL:SetScript("OnEvent", function(_, event, ...)
	if SwingTimer[event] then
		SwingTimer[event](SwingTimer, event, ...)
	end
end)

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
function SwingTimer:Acquire()
	refCount = refCount + 1
	if refCount == 1 then
		for _, event in ipairs(EVENTS) do
			pcall(EL.RegisterEvent, EL, event)
		end
		ReassertRange()
	end
end

function SwingTimer:Release()
	if refCount == 0 then
		return
	end
	refCount = refCount - 1
	if refCount == 0 then
		EL:UnregisterAllEvents()
		ResetState()
	end
end

function SwingTimer:GetState(hand)
	local swing = swings[hand]
	local progress, active = 0, false
	if swing then
		progress = math.min(1, math.max(0, (_G.GetTime() - swing.startTime) / swing.duration))
		local attacking
		if hand == "RANGED" then
			attacking = rangedActive
		else
			attacking = meleeActive
		end
		active = progress < 1 and attacking
	end
	return {
		progress = progress,
		active = active,
		outOfRange = outOfRange[hand] == true,
		queued = hand == "MH" and queued,
	}
end

function SwingTimer:GetAutoHand()
	return rangedActive and "RANGED" or "MH"
end
