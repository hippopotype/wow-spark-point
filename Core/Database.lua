-- SparkPoint Database System
-- Lightweight profiles: one global shared profile or one profile per class.

local _, addon = ...

local DB           -- Active profile table (used by modules/settings)
local RootDB       -- SavedVariables root
local ActiveProfileMode

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
local function DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = DeepCopy(v)
	end
	return out
end

local function ApplyDefaults(target, defaults)
	for dbKey, defaultValue in pairs(defaults or {}) do
		if target[dbKey] == nil then
			target[dbKey] = DeepCopy(defaultValue)
		end
	end
end

local function NormalizeProfileMode(mode)
	local ProfileModes = addon.ProfileModes or {}
	if mode == ProfileModes.CLASS then
		return ProfileModes.CLASS
	end
	return ProfileModes.GLOBAL or "GLOBAL"
end

local function GetPlayerClassKey()
	local _, classTag = UnitClass("player")
	return classTag or "UNKNOWN"
end

local function EnsureRootSchema()
	SparkPointDB = SparkPointDB or {}
	RootDB = SparkPointDB
	addon.DBRoot = RootDB

	ApplyDefaults(RootDB, addon.RootDefaultValues)

	RootDB.profiles = RootDB.profiles or {}
	RootDB.profiles.global = RootDB.profiles.global or {}
	RootDB.profiles.class = RootDB.profiles.class or {}
end

local function ResolveActiveProfileTable()
	if not RootDB then return nil end

	local mode = NormalizeProfileMode(RootDB.profileMode)
	RootDB.profileMode = mode

	if mode == (addon.ProfileModes and addon.ProfileModes.CLASS or "CLASS") then
		local classKey = GetPlayerClassKey()
		RootDB.profiles.class[classKey] = RootDB.profiles.class[classKey] or {}
		return RootDB.profiles.class[classKey]
	end

	RootDB.profiles.global = RootDB.profiles.global or {}
	return RootDB.profiles.global
end

local function ActivateProfile(triggerCallbacks)
	DB = ResolveActiveProfileTable() or {}
	ActiveProfileMode = NormalizeProfileMode(RootDB and RootDB.profileMode)
	ApplyDefaults(DB, addon.DefaultValues)
	addon.DB = DB

	if triggerCallbacks then
		for dbKey, value in pairs(DB) do
			addon.CallbackRegistry:Trigger("SettingChanged." .. dbKey, value, false)
		end
		addon.CallbackRegistry:Trigger("ProfileChanged", addon.GetProfileMode(), addon.GetProfileKey())
	end
end

--------------------------------------------------------------------------------
-- Database Loading
--------------------------------------------------------------------------------
function addon:LoadDatabase()
	EnsureRootSchema()
	ActivateProfile(false)

	-- Trigger initial setting callbacks for active profile
	for dbKey, value in pairs(DB) do
		addon.CallbackRegistry:Trigger("SettingChanged." .. dbKey, value, false)
	end
end

--------------------------------------------------------------------------------
-- Profile API
--------------------------------------------------------------------------------
function addon.GetProfileMode()
	if not RootDB then
		return NormalizeProfileMode((addon.RootDefaultValues and addon.RootDefaultValues.profileMode) or nil)
	end
	return NormalizeProfileMode(RootDB.profileMode)
end

function addon.GetActiveProfileMode()
	if ActiveProfileMode then
		return ActiveProfileMode
	end
	return addon.GetProfileMode()
end

function addon.GetProfileKey()
	local mode = addon.GetProfileMode()
	if mode == (addon.ProfileModes and addon.ProfileModes.CLASS or "CLASS") then
		return "CLASS:" .. GetPlayerClassKey()
	end
	return "GLOBAL"
end

function addon.SetProfileMode(mode, userInput)
	EnsureRootSchema()
	local normalized = NormalizeProfileMode(mode)
	local oldMode = addon.GetActiveProfileMode and addon.GetActiveProfileMode() or addon.GetProfileMode()
	RootDB.profileMode = normalized
	ActivateProfile(true)

	addon.CallbackRegistry:Trigger("SettingChanged.profileMode", normalized, userInput)

	-- Blizzard Settings controls are bound to the old active profile table reference.
	-- Keep this lightweight and reliable: reload to rebuild controls against the new DB.
	if ReloadUI and (not InCombatLockdown or not InCombatLockdown()) then
		ReloadUI()
	else
		addon.CallbackRegistry:Trigger("ProfileReloadRequired", normalized)
		if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
			DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99SparkPoint|r: Profile mode changed. Reload UI to fully apply settings panel bindings.")
		end
	end

	return oldMode ~= normalized
end

--------------------------------------------------------------------------------
-- Database Access Functions (DialogueUI-style)
--------------------------------------------------------------------------------
function addon.GetDBValue(dbKey)
	return DB and DB[dbKey]
end

function addon.SetDBValue(dbKey, value, userInput)
	if DB then
		DB[dbKey] = DeepCopy(value)
		addon.CallbackRegistry:Trigger("SettingChanged." .. dbKey, value, userInput)
	end
end

function addon.GetDBBool(dbKey)
	return DB and DB[dbKey] == true
end

function addon.FlipDBBool(dbKey)
	addon.SetDBValue(dbKey, not addon.GetDBBool(dbKey), true)
end

-- Color helpers
function addon.GetDBColor(dbKey)
	local c = DB and DB[dbKey]
	if c then
		return c.r or 1, c.g or 1, c.b or 1, c.a or 1
	end
	return 1, 1, 1, 1
end

function addon.SetDBColor(dbKey, r, g, b, a)
	addon.SetDBValue(dbKey, {r = r, g = g, b = b, a = a or 1}, true)
end

function addon.GetDBColorTable(dbKey)
	local c = DB and DB[dbKey]
	if c then
		return {r = c.r or 1, g = c.g or 1, b = c.b or 1, a = c.a or 1}
	end
	return {r = 1, g = 1, b = 1, a = 1}
end
