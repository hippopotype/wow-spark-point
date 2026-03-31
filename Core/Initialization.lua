-- SparkPoint Core Initialization
-- Sets up namespace, CallbackRegistry, and handles addon loading events

local addonName, addon = ...
_G.SparkPoint = addon

-- Version info
addon.VERSION = "1.4.2"

-- Addon folder path for textures
addon.addonFolder = "Interface\\AddOns\\" .. addonName

-- Core tables
addon.L = {} -- Localization (populated by Localization files)
addon.Modules = {} -- Module references

--------------------------------------------------------------------------------
-- CallbackRegistry
--------------------------------------------------------------------------------
local CallbackRegistry = {}
CallbackRegistry.events = {}
addon.CallbackRegistry = CallbackRegistry

local tinsert = table.insert
local tremove = table.remove

function CallbackRegistry:Register(event, func, owner)
	if not self.events[event] then
		self.events[event] = {}
	end

	-- callbackType 1 = function, 2 = method name (string)
	local callbackType = (type(func) == "string") and 2 or 1
	tinsert(self.events[event], { callbackType, func, owner })
end

function CallbackRegistry:Trigger(event, ...)
	if self.events[event] then
		for _, cb in ipairs(self.events[event]) do
			if cb[1] == 1 then
				-- Function callback
				if cb[3] then
					cb[2](cb[3], ...)
				else
					cb[2](...)
				end
			else
				-- Method callback: cb[3] is owner, cb[2] is method name
				cb[3][cb[2]](cb[3], ...)
			end
		end
	end
end

function CallbackRegistry:RegisterSettingCallback(dbKey, func, owner)
	self:Register("SettingChanged." .. dbKey, func, owner)
end

function CallbackRegistry:UnregisterOwner(owner)
	for event, callbacks in pairs(self.events) do
		local i = 1
		while callbacks[i] do
			if callbacks[i][3] == owner then
				tremove(callbacks, i)
			else
				i = i + 1
			end
		end
	end
end

function CallbackRegistry:UnregisterCallback(event, owner)
	if self.events[event] then
		local callbacks = self.events[event]
		local i = 1
		while callbacks[i] do
			if callbacks[i][3] == owner then
				tremove(callbacks, i)
			else
				i = i + 1
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Event Listener for initialization
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")
EL:RegisterEvent("ADDON_LOADED")
EL:RegisterEvent("PLAYER_ENTERING_WORLD")

EL:SetScript("OnEvent", function(self, event, ...)
	if event == "ADDON_LOADED" then
		local name = ...
		if name == addonName then
			self:UnregisterEvent(event)
			addon:LoadDatabase()
			CallbackRegistry:Trigger("ADDON_LOADED")
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		self:UnregisterEvent(event)
		addon.ControlCenter:InitializeModules()
		CallbackRegistry:Trigger("PLAYER_ENTERING_WORLD")
	end
end)
