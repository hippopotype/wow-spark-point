-- SparkPoint Assisted Highlight Module
-- Shows the next suggested spell from Blizzard Assisted Highlight.

local _, addon = ...
local L = addon.L
local IconMask = addon.IconMask
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local Visibility = addon.Visibility
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool

local AssistedHighlight = {}
addon.Modules.AssistedHighlightObj = AssistedHighlight

local moduleEnabled = false
local cvarEnabled = false
local moduleFrame

local GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"
local ICON_MASK_BASE_SIZE = 32
local ICON_MASK_BASE_EXPAND = 6

local function IsVisibilityAllowed()
	return (not Visibility) or Visibility:ShouldShow("assistedhighlight")
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

local function HideModuleFrame()
	if moduleFrame then
		moduleFrame:Hide()
		if moduleFrame.iconFrame then
			moduleFrame.iconFrame:Hide()
		end
	end
	AnchorFrame:Hide("assistedhighlight")
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

	local size = tonumber(GetDBValue("assistedhighlight_size")) or 40
	local offsetX = tonumber(GetDBValue("assistedhighlight_offsetX")) or 0
	local offsetY = tonumber(GetDBValue("assistedhighlight_offsetY")) or 0

	moduleFrame.iconFrame:SetSize(size, size)
	moduleFrame.iconFrame:ClearAllPoints()
	moduleFrame.iconFrame:SetPoint("CENTER", moduleFrame, "CENTER", offsetX, offsetY)

	moduleFrame.iconFrame.icon:SetSize(size, size)
	moduleFrame.iconMaskReady = IconMask and IconMask:ApplyToIconFrame(moduleFrame.iconFrame, ICON_MASK_BASE_EXPAND, ICON_MASK_BASE_SIZE)

	if moduleFrame.iconFrame.glow then
		moduleFrame.iconFrame.glow:SetSize(size * 1.8, size * 1.8)
		moduleFrame.iconFrame.glow:ClearAllPoints()
		moduleFrame.iconFrame.glow:SetPoint("CENTER", moduleFrame.iconFrame.icon, "CENTER")
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

	if not moduleFrame.iconMaskReady and IconMask then
		moduleFrame.iconMaskReady = IconMask:ApplyToIconFrame(moduleFrame.iconFrame, ICON_MASK_BASE_EXPAND, ICON_MASK_BASE_SIZE)
	end

	if moduleFrame.iconFrame.glow then
		if GetDBBool("assistedhighlight_glowEnabled") then
			moduleFrame.iconFrame.glow:Show()
		else
			moduleFrame.iconFrame.glow:Hide()
		end
	end

	moduleFrame.iconFrame:Show()
	moduleFrame:Show()
	AnchorFrame:Show("assistedhighlight")
end

function AssistedHighlight:Initialize()
	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	moduleFrame = CreateFrame("Frame", nil, anchor)
	moduleFrame:SetAllPoints()
	moduleFrame:Hide()

	moduleFrame.iconFrame = CreateFrame("Frame", nil, moduleFrame)
	moduleFrame.iconFrame:SetSize(40, 40)
	moduleFrame.iconFrame:SetPoint("CENTER", moduleFrame, "CENTER", 0, 0)
	moduleFrame.iconFrame:Hide()

	moduleFrame.iconFrame.icon = moduleFrame.iconFrame:CreateTexture(nil, "ARTWORK")
	moduleFrame.iconFrame.icon:SetPoint("CENTER")
	moduleFrame.iconFrame.icon:SetTexCoord(0, 1, 0, 1)

	moduleFrame.iconFrame.glow = moduleFrame.iconFrame:CreateTexture(nil, "OVERLAY")
	moduleFrame.iconFrame.glow:SetTexture(GLOW_TEXTURE)
	moduleFrame.iconFrame.glow:SetBlendMode("ADD")
	moduleFrame.iconFrame.glow:SetVertexColor(0.35, 0.7, 1, 0.85)
	moduleFrame.iconFrame.glow:SetPoint("CENTER", moduleFrame.iconFrame.icon, "CENTER")
	moduleFrame.iconFrame.glow:Hide()

	self:RefreshCVarState()
	self:ApplyOptions()
	self:UpdateVisibility()
end

function AssistedHighlight:OnEvent(event, ...)
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
		EL:RegisterEvent("PLAYER_TARGET_CHANGED")
		EL:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		EL:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")

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

for _, key in ipairs({ "visibility_mode", "assistedhighlight_visibilitySource", "assistedhighlight_visibility" }) do
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
