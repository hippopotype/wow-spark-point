-- SparkPoint Assisted Highlight Module
-- Shows the next suggested spell from Blizzard Assisted Highlight.

local _, addon = ...
local L = addon.L
local IconMask = addon.IconMask
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local HUDLayers = addon.HUDLayers
local Visibility = addon.Visibility
local Transition = addon.Transition
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor

local AssistedHighlight = {}
addon.Modules.AssistedHighlightObj = AssistedHighlight

local moduleEnabled = false
local cvarEnabled = false
local moduleFrame

local SPELL_ICON_BACKGROUND_PATH = addon.addonFolder .. "\\Textures\\spell_icon_background.png"
local SPELL_ICON_GLOW_PATH = addon.addonFolder .. "\\Textures\\spell_icon_glow.png"
local SPELL_ICON_FRAME_PATH = addon.addonFolder .. "\\Textures\\spell_icon_frame.png"
local ICON_MASK_BASE_EXPAND = 6
local GLOW_ANIM_MIN_ALPHA = 0.45
local GLOW_ANIM_MAX_ALPHA = 1
local GLOW_DEFAULT_CYCLE_DURATION = 2.6
local GLOW_DEFAULT_STRENGTH = 0.35
local COS = math.cos
local FLOOR = math.floor
local PI2 = math.pi * 2
local actionSlotCommandMap
local assistedActionSlotSet

local function GetResolvedFrameLevel()
	if moduleFrame and moduleFrame:GetParent() then
		local level = moduleFrame:GetParent():GetFrameLevel()
		if type(level) == "number" then
			return level
		end
	end
	return 50
end

local function ApplyFrameLevel()
	if not moduleFrame or not moduleFrame.iconFrame then
		return
	end

	local frameLevel = GetResolvedFrameLevel()
	moduleFrame:SetFrameLevel(frameLevel)
	moduleFrame.iconFrame:SetFrameLevel(frameLevel)
end

local function IsVisibilityAllowed()
	return (not Visibility) or Visibility:ShouldShow("assistedhighlight")
end

local function SetTextureSmooth(texture, texturePath)
	if not texture then
		return
	end
	local ok = pcall(texture.SetTexture, texture, texturePath, nil, nil, "TRILINEAR")
	if not ok then
		texture:SetTexture(texturePath)
	end
	if texture.SetSnapToPixelGrid then
		texture:SetSnapToPixelGrid(false)
	end
	if texture.SetTexelSnappingBias then
		texture:SetTexelSnappingBias(0)
	end
end

local function IsAssistedCVarEnabled()
	if GetCVarBool then
		return GetCVarBool("assistedCombatHighlight") == true
	end
	if C_CVar and C_CVar.GetCVar then
		return C_CVar.GetCVar("assistedCombatHighlight") == "1"
	end
	if GetCVar then
		return GetCVar("assistedCombatHighlight") == "1"
	end
	return false
end

local function GetSuggestedSpellID()
	if not (C_AssistedCombat and C_AssistedCombat.GetNextCastSpell) then
		return nil
	end
	return tonumber(C_AssistedCombat.GetNextCastSpell())
end

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

local function FormatBindingText(bindingKey)
	if not bindingKey then
		return nil
	end

	local formatMode = tostring(GetDBValue("assistedhighlight_keybindFormat") or "COMPACT")
	if formatMode == "FULL" then
		return (GetBindingText and GetBindingText(bindingKey)) or bindingKey
	end

	return AbbreviateKey(bindingKey)
end

local function HideModuleFrame()
	if not moduleFrame then
		AnchorFrame:Hide("assistedhighlight")
		return
	end

	local function FinishHide()
		if moduleFrame.iconFrame then
			moduleFrame.iconFrame:Hide()
			if moduleFrame.iconFrame.keybindText then
				moduleFrame.iconFrame.keybindText:Hide()
			end
		end
		AnchorFrame:Hide("assistedhighlight")
	end

	if Transition and Transition.HideFrame then
		Transition:HideFrame(moduleFrame, { onComplete = FinishHide })
	else
		moduleFrame:Hide()
		FinishHide()
	end
end

local function IsGlowTransitionEnabled()
	local enabled = GetDBValue("assistedhighlight_glowTransitionEnabled")
	if enabled == nil then
		return true
	end
	return enabled == true
end

local function GetGlowTransitionSpeed()
	local speed = tonumber(GetDBValue("assistedhighlight_glowTransitionSpeed"))
	if speed == nil then
		speed = 1
	end
	if speed < 0.05 then
		speed = 0.05
	end
	return speed
end

local function GetGlowTransitionStrength()
	local strength = tonumber(GetDBValue("assistedhighlight_glowTransitionStrength"))
	if strength == nil then
		strength = GLOW_DEFAULT_STRENGTH
	end
	if strength < 0 then
		strength = 0
	elseif strength > 1 then
		strength = 1
	end
	return strength
end

local function UpdateGlowAlpha(elapsed)
	if not moduleFrame or not moduleFrame.iconFrame or not moduleFrame.iconFrame.glow then
		return
	end

	local iconFrame = moduleFrame.iconFrame
	if not iconFrame.glowActive then
		return
	end

	if not IsGlowTransitionEnabled() then
		local staticAlpha = (iconFrame.glowColorAlpha or 1) * GLOW_ANIM_MIN_ALPHA
		iconFrame.glow:SetAlpha(staticAlpha)
		return
	end

	local glowSpeed = GetGlowTransitionSpeed()
	local duration = GLOW_DEFAULT_CYCLE_DURATION / glowSpeed
	if duration <= 0 then
		duration = 2
	end

	iconFrame.glowPhase = (iconFrame.glowPhase or 0) + (elapsed / duration)
	if iconFrame.glowPhase >= 1 then
		iconFrame.glowPhase = iconFrame.glowPhase - math.floor(iconFrame.glowPhase)
	end

	-- Continuous breath wave [0..1] without segment boundaries.
	local wave = 0.5 - 0.5 * COS(iconFrame.glowPhase * PI2)

	-- Strength controls pulse amplitude (0 = static midpoint, 1 = full min/max sweep).
	local strength = GetGlowTransitionStrength()
	local range = GLOW_ANIM_MAX_ALPHA - GLOW_ANIM_MIN_ALPHA
	local waveWithStrength = ((1 - strength) * 0.5) + (strength * wave)
	local scaled = GLOW_ANIM_MIN_ALPHA + (range * waveWithStrength)
	local colorAlpha = iconFrame.glowColorAlpha or 1
	iconFrame.glow:SetAlpha(scaled * colorAlpha)
end

function AssistedHighlight:IsCVarEnabled()
	return cvarEnabled == true
end

function AssistedHighlight:RefreshCVarState()
	cvarEnabled = IsAssistedCVarEnabled()
end

function AssistedHighlight:ApplyOptions()
	if not moduleFrame or not moduleFrame.iconFrame then
		return
	end

	ApplyFrameLevel()

	local size = tonumber(GetDBValue("assistedhighlight_size")) or 40
	local offsetX = tonumber(GetDBValue("assistedhighlight_offsetX")) or 0
	local offsetY = tonumber(GetDBValue("assistedhighlight_offsetY")) or 0
	local iconOpacity = tonumber(GetDBValue("assistedhighlight_iconOpacity")) or 1
	local keybindOpacity = tonumber(GetDBValue("assistedhighlight_keybindOpacity")) or 1
	iconOpacity = math.max(0, math.min(1, iconOpacity))
	keybindOpacity = math.max(0, math.min(1, keybindOpacity))

	moduleFrame.iconFrame:SetSize(size, size)
	moduleFrame.iconFrame:ClearAllPoints()
	moduleFrame.iconFrame:SetPoint("CENTER", moduleFrame, "CENTER", offsetX, offsetY)

	moduleFrame.iconFrame.icon:SetSize(size, size)
	moduleFrame.iconFrame.icon:SetAlpha(iconOpacity)
	moduleFrame.iconMaskReady = IconMask:ApplyToIconFrame(moduleFrame.iconFrame, ICON_MASK_BASE_EXPAND)

	if moduleFrame.iconFrame.background then
		IconMask:LayoutToIcon(moduleFrame.iconFrame.background, moduleFrame.iconFrame.icon, ICON_MASK_BASE_EXPAND)
		SetTextureSmooth(moduleFrame.iconFrame.background, SPELL_ICON_BACKGROUND_PATH)
		moduleFrame.iconFrame.background:SetVertexColor(1, 1, 1, 1)
		moduleFrame.iconFrame.background:SetAlpha(iconOpacity)
	end

	if moduleFrame.iconFrame.glow then
		IconMask:LayoutToIcon(moduleFrame.iconFrame.glow, moduleFrame.iconFrame.icon, ICON_MASK_BASE_EXPAND)
		SetTextureSmooth(moduleFrame.iconFrame.glow, SPELL_ICON_GLOW_PATH)
		local gr, gg, gb, ga = GetDBColor("assistedhighlight_glowColor")
		moduleFrame.iconFrame.glow:SetVertexColor(gr, gg, gb, 1)
		moduleFrame.iconFrame.glowColorAlpha = (ga or 1) * iconOpacity
		moduleFrame.iconFrame.glow:SetAlpha(((ga or 1) * iconOpacity) * GLOW_ANIM_MIN_ALPHA)
	end

	if moduleFrame.iconFrame.frame then
		IconMask:LayoutToIcon(moduleFrame.iconFrame.frame, moduleFrame.iconFrame.icon, ICON_MASK_BASE_EXPAND)
		SetTextureSmooth(moduleFrame.iconFrame.frame, SPELL_ICON_FRAME_PATH)
		moduleFrame.iconFrame.frame:SetVertexColor(1, 1, 1, 1)
		moduleFrame.iconFrame.frame:SetAlpha(iconOpacity)
	end

	if moduleFrame.iconFrame.keybindText then
		local font = GetDBValue("assistedhighlight_keybindFont") or "Fonts\\FRIZQT__.TTF"
		local fontOutline = GetDBValue("assistedhighlight_keybindFontOutline") or "OUTLINE"
		local fontSize = tonumber(GetDBValue("assistedhighlight_keybindFontSize")) or 12
		local textOffsetX = tonumber(GetDBValue("assistedhighlight_keybindOffsetX")) or 0
		local textOffsetY = tonumber(GetDBValue("assistedhighlight_keybindOffsetY")) or 0
		local tr, tg, tb, ta = GetDBColor("assistedhighlight_keybindColor")
		moduleFrame.iconFrame.keybindText:SetFont(font, fontSize, fontOutline)
		moduleFrame.iconFrame.keybindText:ClearAllPoints()
		moduleFrame.iconFrame.keybindText:SetPoint("CENTER", moduleFrame.iconFrame, "CENTER", textOffsetX, textOffsetY)
		moduleFrame.iconFrame.keybindText:SetTextColor(tr, tg, tb, (ta or 1) * keybindOpacity)
	end
end

function AssistedHighlight:UpdateVisibility()
	if not moduleFrame or not moduleFrame.iconFrame then
		return
	end

	if not moduleEnabled or not cvarEnabled or not IsVisibilityAllowed() then
		HideModuleFrame()
		return
	end

	local spellID = GetSuggestedSpellID()
	if not spellID then
		HideModuleFrame()
		return
	end

	local info = C_Spell.GetSpellInfo(spellID)
	local texture = info and info.iconID
	if not texture then
		HideModuleFrame()
		return
	end

	moduleFrame.iconFrame.icon:SetTexture(texture)
	moduleFrame.iconFrame.icon:Show()

	if not moduleFrame.iconMaskReady then
		moduleFrame.iconMaskReady = IconMask:ApplyToIconFrame(moduleFrame.iconFrame, ICON_MASK_BASE_EXPAND)
	end

	if moduleFrame.iconFrame.glow then
		if GetDBBool("assistedhighlight_glowEnabled") then
			moduleFrame.iconFrame.glow:Show()
			moduleFrame.iconFrame.glowActive = true
		else
			moduleFrame.iconFrame.glowActive = false
			moduleFrame.iconFrame.glow:Hide()
		end
	end
	if moduleFrame.iconFrame.background then
		moduleFrame.iconFrame.background:Show()
	end
	if moduleFrame.iconFrame.frame then
		moduleFrame.iconFrame.frame:Show()
	end

	if moduleFrame.iconFrame.keybindText then
		if GetDBBool("assistedhighlight_keybindEnabled") then
			local key = GetFirstBindingKeyForSpell(spellID)
			local text = FormatBindingText(key)
			if text and text ~= "" then
				moduleFrame.iconFrame.keybindText:SetText(text)
				moduleFrame.iconFrame.keybindText:Show()
			else
				moduleFrame.iconFrame.keybindText:Hide()
			end
		else
			moduleFrame.iconFrame.keybindText:Hide()
		end
	end

	moduleFrame.iconFrame:Show()
	AnchorFrame:Show("assistedhighlight")
	if Transition and Transition.ShowFrame then
		Transition:ShowFrame(moduleFrame)
	else
		moduleFrame:Show()
	end
end

function AssistedHighlight:Initialize()
	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	local layerRoot = (HUDLayers and HUDLayers:GetLayerFrame(HUDLayers.Names.ASSISTED_HIGHLIGHT)) or anchor
	moduleFrame = CreateFrame("Frame", nil, layerRoot)
	moduleFrame:SetAllPoints()
	moduleFrame:SetFrameLevel(layerRoot:GetFrameLevel() or 0)
	moduleFrame:Hide()

	moduleFrame.iconFrame = CreateFrame("Frame", nil, moduleFrame)
	moduleFrame.iconFrame:SetSize(40, 40)
	moduleFrame.iconFrame:SetPoint("CENTER", moduleFrame, "CENTER", 0, 0)
	moduleFrame.iconFrame:SetScript("OnUpdate", function(_, elapsed)
		UpdateGlowAlpha(elapsed)
	end)
	moduleFrame.iconFrame:Hide()

	moduleFrame.iconFrame.background = moduleFrame.iconFrame:CreateTexture(nil, "BACKGROUND")
	moduleFrame.iconFrame.background:SetDrawLayer("BACKGROUND", 0)
	moduleFrame.iconFrame.background:SetPoint("CENTER", moduleFrame.iconFrame, "CENTER")
	moduleFrame.iconFrame.background:Hide()

	moduleFrame.iconFrame.icon = moduleFrame.iconFrame:CreateTexture(nil, "ARTWORK")
	moduleFrame.iconFrame.icon:SetDrawLayer("ARTWORK", 0)
	moduleFrame.iconFrame.icon:SetPoint("CENTER")
	moduleFrame.iconFrame.icon:SetTexCoord(0, 1, 0, 1)

	moduleFrame.iconFrame.glow = moduleFrame.iconFrame:CreateTexture(nil, "ARTWORK")
	moduleFrame.iconFrame.glow:SetDrawLayer("ARTWORK", 1)
	moduleFrame.iconFrame.glow:SetBlendMode("BLEND")
	moduleFrame.iconFrame.glow:SetPoint("CENTER", moduleFrame.iconFrame.icon, "CENTER")
	moduleFrame.iconFrame.glow:Hide()
	moduleFrame.iconFrame.glowPhase = 0
	moduleFrame.iconFrame.glowActive = false
	moduleFrame.iconFrame.glowColorAlpha = 1

	moduleFrame.iconFrame.frame = moduleFrame.iconFrame:CreateTexture(nil, "OVERLAY")
	moduleFrame.iconFrame.frame:SetDrawLayer("OVERLAY", 1)
	moduleFrame.iconFrame.frame:SetBlendMode("BLEND")
	moduleFrame.iconFrame.frame:SetPoint("CENTER", moduleFrame.iconFrame.icon, "CENTER")
	moduleFrame.iconFrame.frame:Hide()

	moduleFrame.iconFrame.keybindText = moduleFrame.iconFrame:CreateFontString(nil, "OVERLAY")
	moduleFrame.iconFrame.keybindText:SetPoint("CENTER", moduleFrame.iconFrame, "CENTER", 0, 0)
	moduleFrame.iconFrame.keybindText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
	moduleFrame.iconFrame.keybindText:SetText("")
	moduleFrame.iconFrame.keybindText:Hide()

	ApplyFrameLevel()
	self:RefreshCVarState()
	self:ApplyOptions()
	self:UpdateVisibility()
end

function AssistedHighlight:OnEvent(event, ...)
	if event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BINDINGS" then
		actionSlotCommandMap = nil
		assistedActionSlotSet = nil
	end

	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		local unit = ...
		if unit ~= "player" then
			return
		end
		self:UpdateVisibility()
		return
	end

	if event == "CVAR_ASSISTED_HIGHLIGHT" then
		self:RefreshCVarState()
		self:UpdateVisibility()
		return
	end

	self:UpdateVisibility()
end

local EL = CreateFrame("Frame")
EL:SetScript("OnEvent", function(_, event, ...)
	AssistedHighlight:OnEvent(event, ...)
end)

local function EnableModule(enabled)
	moduleEnabled = enabled == true

	if moduleEnabled then
		if not moduleFrame then
			AssistedHighlight:Initialize()
		end

		EL:RegisterEvent("PLAYER_ENTERING_WORLD")
		EL:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
		EL:RegisterEvent("SPELL_UPDATE_COOLDOWN")
		EL:RegisterEvent("SPELL_UPDATE_CHARGES")
		EL:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
		EL:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
		EL:RegisterEvent("PLAYER_TARGET_CHANGED")
		EL:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		EL:RegisterEvent("UPDATE_BINDINGS")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		EL:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

		AssistedHighlight:RefreshCVarState()
		AssistedHighlight:UpdateVisibility()
	else
		EL:UnregisterAllEvents()
		HideModuleFrame()
	end
end

CallbackRegistry:RegisterSettingCallback("assistedhighlight_size", function()
	AssistedHighlight:ApplyOptions()
	AssistedHighlight:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("assistedhighlight_offsetX", function()
	AssistedHighlight:ApplyOptions()
	AssistedHighlight:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("assistedhighlight_offsetY", function()
	AssistedHighlight:ApplyOptions()
	AssistedHighlight:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("assistedhighlight_glowEnabled", function()
	AssistedHighlight:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("assistedhighlight_glowColor", function()
	AssistedHighlight:ApplyOptions()
	AssistedHighlight:UpdateVisibility()
end)
for _, key in ipairs({
	"assistedhighlight_glowTransitionEnabled",
	"assistedhighlight_glowTransitionSpeed",
	"assistedhighlight_glowTransitionStrength",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		AssistedHighlight:ApplyOptions()
		AssistedHighlight:UpdateVisibility()
	end)
end
for _, key in ipairs({
	"assistedhighlight_iconOpacity",
	"assistedhighlight_keybindEnabled",
	"assistedhighlight_keybindFormat",
	"assistedhighlight_keybindFont",
	"assistedhighlight_keybindFontOutline",
	"assistedhighlight_keybindFontSize",
	"assistedhighlight_keybindOpacity",
	"assistedhighlight_keybindOffsetX",
	"assistedhighlight_keybindOffsetY",
	"assistedhighlight_keybindColor",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		AssistedHighlight:ApplyOptions()
		AssistedHighlight:UpdateVisibility()
	end)
end

for _, key in ipairs({
	"visibility_mode",
	"moduleEnabled_Cast",
	"assistedhighlight_visibilitySource",
	"assistedhighlight_visibility",
	"visibility_hideOnUIHover",
	"assistedhighlight_hideOnUIHover",
	"attachToMouse",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		AssistedHighlight:UpdateVisibility()
	end)
end

CallbackRegistry:Register("VisibilityContextChanged", function()
	AssistedHighlight:UpdateVisibility()
end, AssistedHighlight)

if CVarCallbackRegistry and CVarCallbackRegistry.RegisterCallback then
	CVarCallbackRegistry:RegisterCallback("assistedCombatHighlight", function()
		AssistedHighlight:OnEvent("CVAR_ASSISTED_HIGHLIGHT")
	end, AssistedHighlight)
end

addon.ControlCenter:AddModule({
	name = L["Assisted Highlight"] or "Assisted Highlight",
	dbKey = "moduleEnabled_AssistedHighlight",
	description = L["Assisted Highlight Description"] or "Shows the next suggested spell from Blizzard Assisted Highlight",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 6,
})
