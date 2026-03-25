-- SparkPoint GCD Slot Provider
-- Provides GCD progress data for inner ring slots

local _, addon = ...
local API = addon.API
local Visibility = addon.Visibility

--------------------------------------------------------------------------------
-- Provider State
--------------------------------------------------------------------------------
local gcdStartTime, gcdDuration
local isTracking = false
local isEnabled = false
local gcdSpellID

local GetTime = GetTime

--------------------------------------------------------------------------------
-- GCD Spell Detection
--------------------------------------------------------------------------------
local CLASS_SPELLS = {
	DRUID = 5185, -- Healing Touch
	PALADIN = 635, -- Holy Light
	PRIEST = 2050, -- Heal
	SHAMAN = 331, -- Healing Wave
	WARRIOR = 6673, -- Battle Shout
	DEATHKNIGHT = 45902, -- Blood Strike
	HUNTER = 75, -- Auto Shot
	MAGE = 1459, -- Arcane Intellect
	WARLOCK = 687, -- Demon Skin
	ROGUE = 1752, -- Sinister Strike
	MONK = 100780, -- Jab
	DEMONHUNTER = 162243, -- Demon's Bite
	EVOKER = 361469, -- Living Flame
}

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")

--------------------------------------------------------------------------------
-- GCD Provider Object
--------------------------------------------------------------------------------
local GCDProvider = {}
GCDProvider.id = "GCD"
GCDProvider.displayName = "GCD"

--------------------------------------------------------------------------------
-- Detect GCD Spell
--------------------------------------------------------------------------------
function GCDProvider:DetectSpell()
	if C_Spell.DoesSpellExist(61304) then
		gcdSpellID = 61304
		return
	end
	local class = API.GetPlayerClass()
	gcdSpellID = CLASS_SPELLS[class]
end

local function GetProviderBarColor()
	-- Slot bars are styled via slot{N}_barColor settings.
	-- Keep provider bar color unset unless a future provider-specific tint is desired.
	return nil
end

--------------------------------------------------------------------------------
-- Provider Interface: GetProgress
-- Returns {
--   progress=0..1,
--   active=bool,
--   show=bool,
--   barColor={r,g,b,a}|nil,
-- }
--------------------------------------------------------------------------------
function GCDProvider:GetProgress()
	if not isTracking or not gcdDuration or gcdDuration == 0 then
		return { progress = 0, active = false, show = false, barColor = GetProviderBarColor() }
	end

	local now = GetTime()
	local perc = (now - gcdStartTime) / gcdDuration
	if perc >= 1 then
		isTracking = false
		return { progress = 0, active = false, show = false, barColor = GetProviderBarColor() }
	end

	return { progress = perc, active = true, show = true, barColor = GetProviderBarColor() }
end

--------------------------------------------------------------------------------
-- Provider Interface: Enable / Disable
--------------------------------------------------------------------------------
function GCDProvider:Enable()
	if isEnabled then
		return
	end
	isEnabled = true

	EL:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
	EL:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	EL:RegisterEvent("PLAYER_STARTED_MOVING")
	EL:RegisterEvent("PLAYER_STOPPED_MOVING")
	EL:RegisterEvent("SPELLS_CHANGED")
	EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
	EL:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
	EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
	EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
	EL:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	self:DetectSpell()
	self:ACTIONBAR_UPDATE_COOLDOWN()
end

function GCDProvider:Disable()
	if not isEnabled then
		return
	end
	isEnabled = false

	EL:UnregisterAllEvents()
	gcdStartTime = nil
	gcdDuration = nil
	isTracking = false
end

--------------------------------------------------------------------------------
-- Cooldown activity helper (normalized cooldown info)
--------------------------------------------------------------------------------
local function IsTrackedCooldownActive(cooldownInfo)
	return API and API.IsCooldownInfoActive and API.IsCooldownInfoActive(cooldownInfo)
end

local function ResolveGCDSpellID(spellID)
	if gcdSpellID then
		return gcdSpellID
	end
	return spellID
end

local function HasActiveTrackingWindow()
	return isTracking and gcdStartTime and gcdDuration and gcdDuration > 0 and (GetTime() - gcdStartTime) < gcdDuration
end

local function StartTrackingWindow(startTime, duration)
	gcdStartTime = startTime
	gcdDuration = duration
	isTracking = true
end

local function ClearTrackingWindow()
	gcdStartTime = nil
	gcdDuration = nil
	isTracking = false
end

local function StartFallbackTracking(spellID)
	if not spellID then
		return false
	end

	local info = C_Spell.GetSpellInfo(spellID)
	if not info or (info.castTime or 0) > 0 then
		return false
	end

	local duration = 0
	if Visibility and Visibility.GetAfterInstantCastRemaining then
		duration = Visibility:GetAfterInstantCastRemaining()
	end
	if (not duration or duration <= 0) and Visibility and Visibility.GetInstantCastFallbackDuration then
		duration = Visibility:GetInstantCastFallbackDuration()
	end
	duration = tonumber(duration) or 0
	if duration <= 0 then
		return false
	end

	StartTrackingWindow(GetTime(), duration)
	return true
end

local function UpdateTrackingFromSpellCooldown(spellID, allowFallback)
	local id = ResolveGCDSpellID(spellID)
	if not id then
		return
	end

	local cooldownInfo = API and API.GetSpellCooldownInfo and API.GetSpellCooldownInfo(id)
	if IsTrackedCooldownActive(cooldownInfo) and cooldownInfo.duration <= 1.5 then
		StartTrackingWindow(cooldownInfo.startTime, cooldownInfo.duration)
	elseif allowFallback and StartFallbackTracking(spellID) then
		return
	elseif HasActiveTrackingWindow() then
		return
	else
		ClearTrackingWindow()
	end
end

local function RefreshOrClearTracking()
	local cooldownInfo = API and API.GetSpellCooldownInfo and API.GetSpellCooldownInfo(gcdSpellID)
	if IsTrackedCooldownActive(cooldownInfo) and cooldownInfo.duration <= 1.5 then
		StartTrackingWindow(cooldownInfo.startTime, cooldownInfo.duration)
	else
		ClearTrackingWindow()
	end
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------
function GCDProvider:SPELLS_CHANGED()
	self:DetectSpell()
end

function GCDProvider:UNIT_SPELLCAST_START(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	UpdateTrackingFromSpellCooldown(spellID, false)
end

function GCDProvider:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end

	UpdateTrackingFromSpellCooldown(spellID, true)

	-- Instant casts often populate the GCD cooldown on the next update tick.
	C_Timer.After(0, function()
		if isEnabled then
			GCDProvider:ACTIONBAR_UPDATE_COOLDOWN()
		end
	end)
end

function GCDProvider:UNIT_SPELLCAST_INTERRUPTED(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	RefreshOrClearTracking()
end

function GCDProvider:UNIT_SPELLCAST_FAILED(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	RefreshOrClearTracking()
end

GCDProvider.UNIT_SPELLCAST_FAILED_QUIET = GCDProvider.UNIT_SPELLCAST_FAILED

function GCDProvider:ACTIONBAR_UPDATE_COOLDOWN()
	UpdateTrackingFromSpellCooldown(gcdSpellID)
end

GCDProvider.SPELL_UPDATE_COOLDOWN = GCDProvider.ACTIONBAR_UPDATE_COOLDOWN

function GCDProvider:PLAYER_STARTED_MOVING()
	self:ACTIONBAR_UPDATE_COOLDOWN()
end

function GCDProvider:PLAYER_STOPPED_MOVING()
	self:ACTIONBAR_UPDATE_COOLDOWN()
end

--------------------------------------------------------------------------------
-- Event Dispatcher
--------------------------------------------------------------------------------
EL:SetScript("OnEvent", function(self, event, ...)
	if GCDProvider[event] then
		GCDProvider[event](GCDProvider, event, ...)
	end
end)

--------------------------------------------------------------------------------
-- Register with SlotProviders
--------------------------------------------------------------------------------
addon.SlotProviders:Register("GCD", GCDProvider)
