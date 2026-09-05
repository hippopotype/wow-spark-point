-- SparkPoint Database System
-- Lightweight profiles: one global shared profile or one profile per class.

local _, addon = ...

local DeepCopy = addon.Util.DeepCopy

local DB -- Active profile table (used by modules/settings)
local RootDB -- SavedVariables root
local ActiveProfileMode

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------
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

local function GetClassDisplayName(classTag)
	if not classTag then
		return "Unknown"
	end
	if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classTag] then
		return LOCALIZED_CLASS_NAMES_MALE[classTag]
	end
	if LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[classTag] then
		return LOCALIZED_CLASS_NAMES_FEMALE[classTag]
	end
	return classTag
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
	if not RootDB then
		return nil
	end

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
	local mode = addon.GetActiveProfileMode and addon.GetActiveProfileMode() or addon.GetProfileMode()
	if mode == (addon.ProfileModes and addon.ProfileModes.CLASS or "CLASS") then
		return "CLASS:" .. GetPlayerClassKey()
	end
	return "GLOBAL"
end

function addon.GetProfileDisplayName(profileKey)
	if profileKey == "GLOBAL" then
		return "Global"
	end
	local classTag = type(profileKey) == "string" and profileKey:match("^CLASS:(.+)$")
	if classTag then
		return "Class: " .. GetClassDisplayName(classTag)
	end
	return tostring(profileKey or "Unknown")
end

function addon.GetAvailableProfileSources()
	EnsureRootSchema()

	local activeKey = addon.GetProfileKey()
	local list = {}

	if activeKey ~= "GLOBAL" and RootDB.profiles.global then
		list[#list + 1] = {
			key = "GLOBAL",
			label = addon.GetProfileDisplayName("GLOBAL"),
		}
	end

	local classKeys = {}
	for classTag in pairs(RootDB.profiles.class or {}) do
		classKeys[#classKeys + 1] = classTag
	end
	table.sort(classKeys)

	for _, classTag in ipairs(classKeys) do
		local key = "CLASS:" .. classTag
		if key ~= activeKey then
			list[#list + 1] = {
				key = key,
				label = addon.GetProfileDisplayName(key),
			}
		end
	end

	return list
end

local function ResolveProfileTableByKey(profileKey)
	if not RootDB or not RootDB.profiles then
		return nil
	end
	if profileKey == "GLOBAL" then
		return RootDB.profiles.global
	end

	local classTag = type(profileKey) == "string" and profileKey:match("^CLASS:(.+)$")
	if classTag then
		return RootDB.profiles.class and RootDB.profiles.class[classTag]
	end

	return nil
end

local function ClearTable(t)
	for k in pairs(t) do
		t[k] = nil
	end
end

function addon.CopyProfileFrom(profileKey, userInput)
	EnsureRootSchema()
	if not DB then
		ActivateProfile(false)
	end

	local activeKey = addon.GetProfileKey()
	if not profileKey or profileKey == "NONE" or profileKey == activeKey then
		return false
	end

	local source = ResolveProfileTableByKey(profileKey)
	if type(source) ~= "table" then
		return false
	end

	ClearTable(DB)
	for k, v in pairs(source) do
		DB[k] = DeepCopy(v)
	end
	ApplyDefaults(DB, addon.DefaultValues)

	-- Sync module enabled states immediately (module toggles are not settings callbacks).
	local controlCenter = addon.ControlCenter
	if controlCenter and controlCenter.GetAllModules then
		for _, moduleData in ipairs(controlCenter:GetAllModules()) do
			local dbKey = moduleData and moduleData.dbKey
			if dbKey and DB[dbKey] ~= nil then
				local shouldEnable = DB[dbKey] == true
				local isEnabled = moduleData.isEnabled == true
				if shouldEnable ~= isEnabled then
					if shouldEnable then
						controlCenter:EnableModule(dbKey)
					else
						controlCenter:DisableModule(dbKey)
					end
				end
			end
		end
	end

	for dbKey, value in pairs(DB) do
		addon.CallbackRegistry:Trigger("SettingChanged." .. dbKey, value, userInput and true or false)
	end
	addon.CallbackRegistry:Trigger("ProfileChanged", addon.GetActiveProfileMode and addon.GetActiveProfileMode() or addon.GetProfileMode(), activeKey)

	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		local srcLabel = addon.GetProfileDisplayName(profileKey)
		local dstLabel = addon.GetProfileDisplayName(activeKey)
		DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff33ff99SparkPoint|r: Copied settings from %s to %s.", srcLabel, dstLabel))
	end

	return true
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

-- Color helpers
function addon.GetDBColor(dbKey)
	local c = DB and DB[dbKey]
	if c then
		return c.r or 1, c.g or 1, c.b or 1, c.a or 1
	end
	return 1, 1, 1, 1
end

function addon.SetDBColor(dbKey, r, g, b, a)
	addon.SetDBValue(dbKey, { r = r, g = g, b = b, a = a or 1 }, true)
end

function addon.GetDBColorTable(dbKey)
	local c = DB and DB[dbKey]
	if c then
		return { r = c.r or 1, g = c.g or 1, b = c.b or 1, a = c.a or 1 }
	end
	return { r = 1, g = 1, b = 1, a = 1 }
end
