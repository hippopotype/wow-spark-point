-- SparkPoint Keybinds
-- Shared action-slot -> binding-key resolution and COMPACT/FULL formatting.
-- Extracted verbatim from Modules/AssistedHighlight.lua so the Cooldown Manager
-- widget reuses it rather than duplicating ~150 lines. No behaviour change.

local _, addon = ...

local Keybinds = {}
addon.Keybinds = Keybinds

local FLOOR = math.floor
local actionSlotCommandMap
local assistedActionSlotSet

local function BuildAssistedActionSlotSet()
	if assistedActionSlotSet then
		return assistedActionSlotSet
	end

	local set = {}
	if C_ActionBar and C_ActionBar.HasAssistedCombatActionButtons and C_ActionBar.FindAssistedCombatActionButtons then
		if C_ActionBar.HasAssistedCombatActionButtons() then
			local slots = C_ActionBar.FindAssistedCombatActionButtons()
			if type(slots) == "table" then
				for _, value in ipairs(slots) do
					local slot = tonumber(value)
					if slot and slot > 0 then
						set[slot] = true
					end
				end
				for key, value in pairs(slots) do
					local slot
					if type(value) == "number" then
						slot = value
					elseif value == true and type(key) == "number" then
						slot = key
					end
					if slot and slot > 0 then
						set[slot] = true
					end
				end
			end
		end
	end

	assistedActionSlotSet = set
	return assistedActionSlotSet
end

local function GetFirstActionSlotForSpell(spellID)
	if not (spellID and C_ActionBar and C_ActionBar.FindSpellActionButtons) then
		return nil
	end

	local slots = C_ActionBar.FindSpellActionButtons(spellID)
	if type(slots) ~= "table" then
		return nil
	end

	local assistedSlots = BuildAssistedActionSlotSet()
	local firstSlot
	for _, value in ipairs(slots) do
		local slot = tonumber(value)
		if slot and slot > 0 and not assistedSlots[slot] and (not firstSlot or slot < firstSlot) then
			firstSlot = slot
		end
	end
	for key, value in pairs(slots) do
		local slot
		if type(value) == "number" then
			slot = value
		elseif value == true and type(key) == "number" then
			slot = key
		end
		if slot and slot > 0 and not assistedSlots[slot] and (not firstSlot or slot < firstSlot) then
			firstSlot = slot
		end
	end

	return firstSlot
end

local function GetBindingCommandForActionSlot(slot)
	local actionSlot = tonumber(slot)
	if not actionSlot or actionSlot < 1 then
		return nil
	end

	if actionSlotCommandMap and actionSlotCommandMap[actionSlot] then
		return actionSlotCommandMap[actionSlot]
	end

	local map = {}
	local actionButtonUtil = _G.ActionButtonUtil
	local buttonNames = (actionButtonUtil and actionButtonUtil.ActionBarButtonNames) or _G.DEFAULT_ACTION_BUTTON_NAMES
	local buttonCount = tonumber(_G.NUM_ACTIONBAR_BUTTONS) or 12

	if type(buttonNames) == "table" then
		for _, prefix in ipairs(buttonNames) do
			for index = 1, buttonCount do
				local button = _G[prefix .. index]
				if button then
					local slotID = tonumber(button.action)
					if not slotID and button.GetAttribute then
						slotID = tonumber(button:GetAttribute("action"))
					end
					if slotID and slotID > 0 and not map[slotID] then
						local command = button.commandName or button.keyBoundTarget
						if not command and button.GetName then
							local name = button:GetName()
							if name and name ~= "" then
								command = "CLICK " .. name .. ":LeftButton"
							end
						end
						if command and command ~= "" then
							map[slotID] = command
						end
					end
				end
			end
		end
	end

	actionSlotCommandMap = map
	if actionSlotCommandMap[actionSlot] then
		return actionSlotCommandMap[actionSlot]
	end

	-- Fallback for cases where button scan doesn't produce a mapping.
	local index = ((actionSlot - 1) % 12) + 1
	local group = FLOOR((actionSlot - 1) / 12)
	if group == 0 then
		return "ACTIONBUTTON" .. index
	elseif group == 1 then
		return "MULTIACTIONBAR1BUTTON" .. index
	elseif group == 2 then
		return "MULTIACTIONBAR2BUTTON" .. index
	elseif group == 3 then
		return "MULTIACTIONBAR3BUTTON" .. index
	elseif group == 4 then
		return "MULTIACTIONBAR4BUTTON" .. index
	end

	return nil
end

local function GetFirstBindingKeyForSpell(spellID)
	local slot = GetFirstActionSlotForSpell(spellID)
	if not slot then
		return nil
	end

	local command = GetBindingCommandForActionSlot(slot)
	if not command then
		return nil
	end

	local key1, key2 = GetBindingKey(command)
	return key1 or key2
end

local COMPACT_KEY_MAP = {
	["CTRL"] = "C",
	["SHIFT"] = "S",
	["ALT"] = "A",
	["META"] = "M",
	["MOUSE1"] = "M1",
	["MOUSE2"] = "M2",
	["MOUSE3"] = "M3",
	["MOUSE4"] = "M4",
	["MOUSE5"] = "M5",
	["LEFTBUTTON"] = "M1",
	["RIGHTBUTTON"] = "M2",
	["MIDDLEBUTTON"] = "M3",
	["BUTTON1"] = "M1",
	["BUTTON2"] = "M2",
	["BUTTON3"] = "M3",
	["BUTTON4"] = "M4",
	["BUTTON5"] = "M5",
	["MOUSEWHEELUP"] = "MwU",
	["MOUSEWHEELDOWN"] = "MwD",
	["NUMPAD0"] = "N0",
	["NUMPAD1"] = "N1",
	["NUMPAD2"] = "N2",
	["NUMPAD3"] = "N3",
	["NUMPAD4"] = "N4",
	["NUMPAD5"] = "N5",
	["NUMPAD6"] = "N6",
	["NUMPAD7"] = "N7",
	["NUMPAD8"] = "N8",
	["NUMPAD9"] = "N9",
	["NUMPADDECIMAL"] = "N.",
	["NUMPADPLUS"] = "N+",
	["NUMPADMINUS"] = "N-",
	["NUMPADMULTIPLY"] = "N*",
	["NUMPADDIVIDE"] = "N/",
	["SPACE"] = "SpB",
	["BACKSPACE"] = "BS",
	["DELETE"] = "Del",
	["INSERT"] = "Ins",
	["HOME"] = "Hm",
	["END"] = "End",
	["PAGEUP"] = "PU",
	["PAGEDOWN"] = "PD",
	["ESCAPE"] = "Esc",
	["CAPSLOCK"] = "Cap",
	["NUMLOCK"] = "NL",
	["PRINTSCREEN"] = "PrS",
	["SCROLLLOCK"] = "SL",
	["PAUSE"] = "Pau",
	["TAB"] = "Tab",
}

local function AbbreviateKey(raw)
	local parts = {}
	for token in raw:gmatch("[^%-]+") do
		local upper = token:upper()
		local mapped = COMPACT_KEY_MAP[upper]
		if mapped then
			parts[#parts + 1] = mapped
		else
			parts[#parts + 1] = token
		end
	end
	return table.concat(parts, "-")
end

local function FormatBindingText(bindingKey, formatMode)
	if not bindingKey then
		return nil
	end

	if formatMode == "FULL" then
		return (GetBindingText and GetBindingText(bindingKey)) or bindingKey
	end

	return AbbreviateKey(bindingKey)
end

function Keybinds:GetBindingKeyForSpell(spellID)
	return GetFirstBindingKeyForSpell(spellID)
end

function Keybinds:FormatBindingText(bindingKey, formatMode)
	return FormatBindingText(bindingKey, formatMode)
end

-- Modules/AssistedHighlight.lua:595-597 clears these two caches on
-- ACTIONBAR_SLOT_CHANGED / ACTIONBAR_PAGE_CHANGED / UPDATE_BINDINGS. After the
-- move those assignments would write to undefined globals, so the caches would
-- never clear again -- for AssistedHighlight OR the new widget. The keybind text
-- would simply go stale after any rebind, which the "keybind still shows" check
-- would not catch.
function Keybinds:InvalidateCaches()
	actionSlotCommandMap = nil
	assistedActionSlotSet = nil
end
