-- SparkPoint ClassResource Module
-- Displays class resources in either PIPS or TEXT mode near the cursor.

local _, addon = ...
local L = addon.L
local API = addon.API
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local Visibility = addon.Visibility
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor

local UnitClass = UnitClass
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local GetRuneCooldown = GetRuneCooldown
local GetSpecialization = GetSpecialization

--------------------------------------------------------------------------------
-- Power Type Enums
--------------------------------------------------------------------------------
local PT = {
	COMBO_POINTS = Enum.PowerType.ComboPoints,
	RUNES = Enum.PowerType.Runes,
	SOUL_SHARDS = Enum.PowerType.SoulShards,
	HOLY_POWER = Enum.PowerType.HolyPower,
	MAELSTROM = Enum.PowerType.Maelstrom,
	CHI = Enum.PowerType.Chi,
	INSANITY = Enum.PowerType.Insanity,
	ARCANE_CHARGES = Enum.PowerType.ArcaneCharges,
	FURY = Enum.PowerType.Fury,
	PAIN = Enum.PowerType.Pain,
	ESSENCE = Enum.PowerType.Essence,
}

-- Maelstrom Weapon aura spell ID (Enhancement Shaman)
local MAELSTROM_WEAPON_SPELL_ID = 344179

-- Unified pip texture.
-- Place your custom art at these paths (or change constants below).
local PIP_TEXTURE_FRAME_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\class_resource_frame.png"
local PIP_TEXTURE_BG_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\class_resource_background.png"
local PIP_TEXTURE_FILL_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\class_resource_fill.png"
local PIP_TEXTURE_FALLBACK = "Interface\\Buttons\\WHITE8x8"

--------------------------------------------------------------------------------
-- Per-class pip configuration
--------------------------------------------------------------------------------
local CLASS_CONFIG = {
	PALADIN = {
		powerEnum = PT.HOLY_POWER,
		maxCount = 5,
		fillColor = { r = 0.95, g = 0.89, b = 0.59, a = 1.00 },
		emptyColor = { r = 0.30, g = 0.28, b = 0.18, a = 0.40 },
	},
	DEATHKNIGHT = {
		isRune = true,
		maxCount = 6,
		fillColor = { r = 0.77, g = 0.12, b = 0.23, a = 1.00 },
		emptyColor = { r = 0.30, g = 0.06, b = 0.06, a = 0.40 },
	},
	ROGUE = {
		powerEnum = PT.COMBO_POINTS,
		maxCount = 5,
		fillColor = { r = 1.00, g = 0.96, b = 0.00, a = 1.00 },
		emptyColor = { r = 0.40, g = 0.38, b = 0.00, a = 0.40 },
	},
	DRUID = {
		powerEnum = PT.COMBO_POINTS,
		maxCount = 5,
		fillColor = { r = 1.00, g = 0.49, b = 0.04, a = 1.00 },
		emptyColor = { r = 0.40, g = 0.20, b = 0.02, a = 0.40 },
	},
	MAGE = {
		powerEnum = PT.ARCANE_CHARGES,
		maxCount = 4,
		fillColor = { r = 0.41, g = 0.80, b = 0.94, a = 1.00 },
		emptyColor = { r = 0.16, g = 0.32, b = 0.38, a = 0.40 },
	},
	MONK = {
		powerEnum = PT.CHI,
		maxCount = 5,
		fillColor = { r = 0.00, g = 1.00, b = 0.59, a = 1.00 },
		emptyColor = { r = 0.00, g = 0.40, b = 0.24, a = 0.40 },
	},
	WARLOCK = {
		powerEnum = PT.SOUL_SHARDS,
		maxCount = 5,
		fillColor = { r = 0.58, g = 0.51, b = 0.79, a = 1.00 },
		emptyColor = { r = 0.23, g = 0.20, b = 0.32, a = 0.40 },
	},
	EVOKER = {
		powerEnum = PT.ESSENCE,
		maxCount = 6,
		fillColor = { r = 0.20, g = 0.58, b = 0.50, a = 1.00 },
		emptyColor = { r = 0.08, g = 0.23, b = 0.20, a = 0.40 },
	},
	SHAMAN = {
		isMaelstrom = true,
		maxCount = 5,
		fillColor = { r = 0.00, g = 0.44, b = 0.87, a = 1.00 },
		emptyColor = { r = 0.00, g = 0.18, b = 0.35, a = 0.40 },
	},
}

local TEXT_POWER_CONFIG = {
	ROGUE = { default = PT.COMBO_POINTS },
	DRUID = {
		[2] = PT.COMBO_POINTS,
		[4] = PT.COMBO_POINTS,
		[1] = Enum.PowerType.LunarPower,
	},
	PALADIN = { default = PT.HOLY_POWER },
	MONK = { [3] = PT.CHI },
	DEATHKNIGHT = { default = PT.RUNES },
	WARLOCK = { default = PT.SOUL_SHARDS },
	MAGE = { [1] = PT.ARCANE_CHARGES },
	DEMONHUNTER = {
		[1] = PT.FURY,
		[2] = PT.PAIN,
	},
	EVOKER = { default = PT.ESSENCE },
	PRIEST = { [3] = PT.INSANITY },
	SHAMAN = {
		[1] = PT.MAELSTROM,
		[2] = PT.MAELSTROM,
	},
}

-- Visual dimensions (pixels at scale 1)
local PIP_SIZE = 18
local PIP_SPACING = 4

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")

local ClassResource = {}
addon.Modules.ClassResourceObj = ClassResource

local MODE_TEXT = "TEXT"
local MODE_PIPS = "PIPS"

local isEnabled = false
local container = nil
local pips = {}
local pipMax = 0
local activeCfg = nil

local textFrame = nil
local currentTextSource = nil
local currentTextPowerType = nil
local lastTextValue = nil

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------
local function GetCurrentMode()
	local mode = GetDBValue("classresource_mode")
	if mode == MODE_TEXT then
		return MODE_TEXT
	end
	return MODE_PIPS
end

--------------------------------------------------------------------------------
-- Shared helpers
--------------------------------------------------------------------------------
local function NormalizePowerValue(value)
	if value == nil then
		return 0
	end
	if type(value) == "number" then
		return value
	end

	local s = tostring(value) or "0"
	local n = tonumber(s)
	if n then
		return n
	end

	local token = s:match("[-+]?%d+%.?%d*")
	return tonumber(token) or 0
end

local function IsPowerTypeUsable(powerType)
	if powerType == nil then
		return false
	end
	local maxPower = NormalizePowerValue(UnitPowerMax("player", powerType))
	return maxPower > 0
end

--------------------------------------------------------------------------------
-- Text Mode
--------------------------------------------------------------------------------
local function EnsureTextFrame()
	if textFrame then
		return
	end

	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	textFrame = CreateFrame("Frame", nil, anchor)
	textFrame:SetFrameStrata("HIGH")
	textFrame:SetFrameLevel((anchor:GetFrameLevel() or 1) + 20)
	textFrame:SetSize(1, 1)
	textFrame:Hide()

	textFrame.powerText = textFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	textFrame.powerText:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
	textFrame.powerText:SetText("0")
end

function ClassResource:DetectTextPowerType()
	local _, classTag = UnitClass("player")
	local spec = GetSpecialization() or 0

	local classConfig = TEXT_POWER_CONFIG[classTag]
	if not classConfig then
		currentTextSource = nil
		currentTextPowerType = nil
		return
	end

	local powerType = classConfig[spec] or classConfig.default

	-- Enhancement Shaman uses Maelstrom Weapon aura stacks (not UnitPower-based).
	if classTag == "SHAMAN" and spec == 2 then
		currentTextSource = "MAELSTROM_WEAPON"
		currentTextPowerType = nil
		return
	end

	if IsPowerTypeUsable(powerType) then
		currentTextSource = "POWER"
		currentTextPowerType = powerType
	else
		currentTextSource = nil
		currentTextPowerType = nil
	end
end

function ClassResource:ApplyTextOptions()
	if not textFrame then
		return
	end

	local font = GetDBValue("classresource_font") or "Fonts\\FRIZQT__.TTF"
	local fontSize = GetDBValue("classresource_fontSize") or 16
	local fontOutline = GetDBValue("classresource_fontOutline") or ""
	textFrame.powerText:SetFont(font, fontSize, fontOutline)

	local r, g, b, a
	if GetDBBool("classresource_useClassColor") then
		r, g, b, a = API.GetPlayerClassColor()
	else
		r, g, b, a = GetDBColor("classresource_fontColor")
	end
	textFrame.powerText:SetTextColor(r, g, b, a)
end

function ClassResource:UpdateTextMode()
	if not isEnabled then
		return
	end
	if not textFrame then
		return
	end

	if not Visibility:ShouldShow("classresource") then
		textFrame:Hide()
		AnchorFrame:Hide("classresource")
		return
	end

	if not currentTextSource then
		self:DetectTextPowerType()
	end

	if not currentTextSource then
		textFrame:Hide()
		AnchorFrame:Hide("classresource")
		return
	end

	local powerValue = 0
	if currentTextSource == "POWER" and currentTextPowerType then
		powerValue = NormalizePowerValue(UnitPower("player", currentTextPowerType))
	elseif currentTextSource == "MAELSTROM_WEAPON" then
		local aura = C_UnitAuras.GetPlayerAuraBySpellID(MAELSTROM_WEAPON_SPELL_ID)
		powerValue = aura and (aura.applications or 0) or 0
	end

	local powerString = tostring(powerValue)
	if powerString ~= lastTextValue then
		lastTextValue = powerString
		textFrame.powerText:SetText(powerString)
	end

	if not textFrame:IsShown() then
		textFrame:Show()
	end
	AnchorFrame:Show("classresource")
end

--------------------------------------------------------------------------------
-- PIPS Mode (current implementation)
--------------------------------------------------------------------------------
local function GetRunePower()
	local ready = 0
	for i = 1, 6 do
		local start, _, runeReady = GetRuneCooldown(i)
		if runeReady or start == 0 then
			ready = ready + 1
		end
	end
	return ready, 6
end

local function GetMaelstromWeaponPower()
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(MAELSTROM_WEAPON_SPELL_ID)
	if not aura then
		return 0, 5
	end
	return (aura.applications or 0), 5
end

local function ReadPower()
	if not activeCfg then
		return 0, 0
	end

	if activeCfg.isRune then
		return GetRunePower()
	end

	if activeCfg.isMaelstrom then
		return GetMaelstromWeaponPower()
	end

	local pEnum = activeCfg.powerEnum
	if not pEnum then
		return 0, 0
	end

	local cur = NormalizePowerValue(UnitPower("player", pEnum))
	local max = NormalizePowerValue(UnitPowerMax("player", pEnum))
	return cur, max
end

local function EnsureContainer()
	if container then
		return
	end
	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	container = CreateFrame("Frame", nil, anchor)
	container:SetFrameStrata("HIGH")
	container:SetFrameLevel((anchor:GetFrameLevel() or 1) + 20)
	container:SetSize(1, 1)
	container:Hide()
end

local function GetPip(i)
	if pips[i] then
		return pips[i]
	end
	if not container then
		return nil
	end
	local p = {
		frame = container:CreateTexture(nil, "ARTWORK", nil, 2),
		bg = container:CreateTexture(nil, "ARTWORK", nil, 0),
		fill = container:CreateTexture(nil, "ARTWORK", nil, 1),
	}
	p.styleReady = false
	p.frame:Hide()
	p.bg:Hide()
	p.fill:Hide()
	pips[i] = p
	return p
end

local function ConfigurePipTextures(p, cfg)
	if not p then
		return
	end

	p.frame:SetTexCoord(0, 1, 0, 1)
	p.bg:SetTexCoord(0, 1, 0, 1)
	p.fill:SetTexCoord(0, 1, 0, 1)

	local function SetTextureSmooth(tex, path)
		local ok = pcall(tex.SetTexture, tex, path, nil, nil, "TRILINEAR")
		if not ok then
			tex:SetTexture(path)
		end
		if tex.SetSnapToPixelGrid then
			tex:SetSnapToPixelGrid(false)
		end
		if tex.SetTexelSnappingBias then
			tex:SetTexelSnappingBias(0)
		end
	end

	SetTextureSmooth(p.frame, PIP_TEXTURE_FRAME_PATH)
	SetTextureSmooth(p.bg, PIP_TEXTURE_BG_PATH)
	SetTextureSmooth(p.fill, PIP_TEXTURE_FILL_PATH)

	if not p.frame:GetTexture() then
		p.frame:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not p.bg:GetTexture() then
		p.bg:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not p.fill:GetTexture() then
		p.fill:SetTexture(PIP_TEXTURE_FALLBACK)
	end

	local function GetPipFillColor()
		if GetDBBool("classresource_fillUseClassColor") then
			return API.GetPlayerClassColor()
		end

		local customFill = GetDBValue("classresource_fillColor")
		if customFill then
			return GetDBColor("classresource_fillColor")
		end

		local fc = cfg and cfg.fillColor
		if fc then
			return fc.r, fc.g, fc.b, fc.a
		end
		return 1, 1, 1, 1
	end

	local fr, fg, fb, fa = GetPipFillColor()
	local ec = cfg.emptyColor
	local br, bg, bb, ba = GetDBColor("classresource_backgroundColor")
	if br == nil then
		br = 1
	end
	if bg == nil then
		bg = 1
	end
	if bb == nil then
		bb = 1
	end
	if ba == nil then
		ba = 1
	end
	local usingDefaultBackgroundTint = br == 1 and bg == 1 and bb == 1 and ba == 1
	p.frame:SetVertexColor(1, 1, 1, 0.95)
	if usingDefaultBackgroundTint then
		p.bg:SetVertexColor(ec.r, ec.g, ec.b, ec.a)
	else
		p.bg:SetVertexColor(br, bg, bb, ec.a * ba)
	end
	p.fill:SetVertexColor(fr, fg, fb, fa)

	p.styleReady = true
end

function ClassResource:ApplyPipVisualOptions()
	if not activeCfg then
		return
	end
	for i = 1, #pips do
		local p = pips[i]
		if p then
			ConfigurePipTextures(p, activeCfg)
		end
	end
end

local function LayoutPips(cfg, count)
	if not container or count < 1 then
		return
	end

	local total = count * PIP_SIZE + (count - 1) * PIP_SPACING
	local x0 = -(total / 2) + (PIP_SIZE / 2)

	for i = 1, count do
		local p = GetPip(i)
		if p then
			local x = x0 + (i - 1) * (PIP_SIZE + PIP_SPACING)

			p.frame:SetSize(PIP_SIZE, PIP_SIZE)
			p.frame:ClearAllPoints()
			p.frame:SetPoint("CENTER", container, "CENTER", x, 0)

			p.bg:SetSize(PIP_SIZE, PIP_SIZE)
			p.bg:ClearAllPoints()
			p.bg:SetPoint("CENTER", container, "CENTER", x, 0)

			p.fill:SetSize(PIP_SIZE, PIP_SIZE)
			p.fill:ClearAllPoints()
			p.fill:SetPoint("CENTER", container, "CENTER", x, 0)

			if not p.styleReady then
				ConfigurePipTextures(p, cfg)
			end
		end
	end

	for i = count + 1, #pips do
		local p = pips[i]
		if p then
			p.frame:Hide()
			p.bg:Hide()
			p.fill:Hide()
		end
	end

	container:SetSize(total, PIP_SIZE)
	pipMax = count
end

local function HidePips()
	for i = 1, #pips do
		local p = pips[i]
		if p then
			p.frame:Hide()
			p.bg:Hide()
			p.fill:Hide()
		end
	end
end

local function ApplyPipState(current, max)
	if not container or not activeCfg then
		HidePips()
		return
	end

	if max ~= pipMax then
		if max > 0 then
			LayoutPips(activeCfg, max)
		else
			HidePips()
			return
		end
	end

	if max <= 0 then
		HidePips()
		return
	end

	for i = 1, max do
		local p = pips[i]
		if p then
			p.frame:Show()
			p.bg:Show()
			if i <= current then
				p.fill:Show()
			else
				p.fill:Hide()
			end
		end
	end

	for i = max + 1, #pips do
		local p = pips[i]
		if p then
			p.frame:Hide()
			p.bg:Hide()
			p.fill:Hide()
		end
	end
end

--------------------------------------------------------------------------------
-- Layout and Visibility
--------------------------------------------------------------------------------
function ClassResource:ApplyLayout()
	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	local offsetX = GetDBValue("classresource_offsetX") or 0
	local offsetY = GetDBValue("classresource_offsetY") or 0
	local scale = GetDBValue("classresource_scale") or 1
	local opacity = GetDBValue("classresource_opacity")
	if opacity == nil then
		opacity = 1
	end

	if container then
		container:SetParent(anchor)
		container:ClearAllPoints()
		container:SetPoint("CENTER", anchor, "CENTER", offsetX, offsetY)
		container:SetScale(scale)
		container:SetAlpha(opacity)
		container:SetFrameStrata("HIGH")
		container:SetFrameLevel((anchor:GetFrameLevel() or 1) + 20)
	end

	if textFrame then
		local textOffsetX = GetDBValue("classresource_textOffsetX") or 0
		local textOffsetY = GetDBValue("classresource_textOffsetY") or 0
		textFrame:SetParent(anchor)
		textFrame:ClearAllPoints()
		textFrame:SetPoint("CENTER", anchor, "CENTER", textOffsetX, textOffsetY)
		textFrame:SetScale(1)
		textFrame:SetAlpha(1)
		textFrame:SetFrameStrata("HIGH")
		textFrame:SetFrameLevel((anchor:GetFrameLevel() or 1) + 20)
	end
end

function ClassResource:UpdateVisibility()
	if not isEnabled then
		if container then
			container:Hide()
		end
		if textFrame then
			textFrame:Hide()
		end
		AnchorFrame:Hide("classresource")
		return
	end

	if GetCurrentMode() == MODE_TEXT then
		if container then
			container:Hide()
		end
		HidePips()
		self:UpdateTextMode()
		return
	end

	if textFrame then
		textFrame:Hide()
	end

	if not activeCfg then
		if container then
			container:Hide()
		end
		AnchorFrame:Hide("classresource")
		return
	end

	if not Visibility:ShouldShow("classresource") then
		if container then
			container:Hide()
		end
		AnchorFrame:Hide("classresource")
		return
	end

	if container then
		container:Show()
	end
	AnchorFrame:Show("classresource")
end

function ClassResource:SyncPower()
	if GetCurrentMode() ~= MODE_PIPS then
		return
	end
	if not isEnabled or not activeCfg then
		return
	end
	local current, max = ReadPower()
	ApplyPipState(current, max)
end

--------------------------------------------------------------------------------
-- Class Detection
--------------------------------------------------------------------------------
local function DetectActiveClass()
	local _, classTag = UnitClass("player")
	if not classTag then
		return nil, nil
	end

	local cfg = CLASS_CONFIG[classTag]
	if not cfg then
		return nil, nil
	end

	if classTag == "SHAMAN" then
		local spec = GetSpecialization() or 0
		if spec ~= 2 then
			return nil, nil
		end
	end

	return classTag, cfg
end

function ClassResource:Refresh()
	EnsureContainer()
	EnsureTextFrame()

	local _, cfg = DetectActiveClass()
	activeCfg = cfg
	pipMax = 0
	for i = 1, #pips do
		pips[i].styleReady = false
	end

	if activeCfg then
		LayoutPips(activeCfg, activeCfg.maxCount)
	else
		HidePips()
	end

	currentTextPowerType = nil
	currentTextSource = nil
	lastTextValue = nil

	self:ApplyTextOptions()
	self:ApplyLayout()
	self:UpdateVisibility()

	if GetCurrentMode() == MODE_PIPS then
		self:SyncPower()
	else
		self:UpdateTextMode()
	end
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------
function ClassResource:PLAYER_ENTERING_WORLD()
	self:Refresh()
end

function ClassResource:PLAYER_SPECIALIZATION_CHANGED()
	self:Refresh()
end

function ClassResource:UPDATE_SHAPESHIFT_FORM()
	self:Refresh()
end

function ClassResource:UNIT_POWER_UPDATE(event, unit)
	if unit ~= "player" then
		return
	end
	if GetCurrentMode() == MODE_TEXT then
		self:UpdateTextMode()
	else
		self:SyncPower()
	end
end

function ClassResource:UNIT_MAXPOWER(event, unit)
	if unit ~= "player" then
		return
	end
	if GetCurrentMode() == MODE_TEXT then
		self:Refresh()
	else
		self:SyncPower()
	end
end

function ClassResource:UNIT_DISPLAYPOWER(event, unit)
	if unit ~= "player" then
		return
	end
	self:Refresh()
end

function ClassResource:UNIT_AURA(event, unit)
	if unit ~= "player" then
		return
	end
	if GetCurrentMode() == MODE_TEXT then
		self:UpdateTextMode()
		return
	end
	if activeCfg and activeCfg.isMaelstrom then
		self:SyncPower()
	end
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------
local function EnableModule(enabled)
	isEnabled = enabled and true or false

	if enabled then
		EL:RegisterEvent("PLAYER_ENTERING_WORLD")
		EL:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		EL:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		EL:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
		EL:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
		EL:RegisterUnitEvent("UNIT_MAXPOWER", "player")
		EL:RegisterUnitEvent("UNIT_AURA", "player")

		ClassResource:Refresh()
	else
		EL:UnregisterAllEvents()
		if container then
			container:Hide()
		end
		if textFrame then
			textFrame:Hide()
		end
		AnchorFrame:Hide("classresource")
		activeCfg = nil
		currentTextSource = nil
		currentTextPowerType = nil
		HidePips()
	end
end

EL:SetScript("OnEvent", function(self, event, ...)
	if ClassResource[event] then
		ClassResource[event](ClassResource, event, ...)
	end
end)

--------------------------------------------------------------------------------
-- Setting Callbacks
--------------------------------------------------------------------------------
for _, key in ipairs({
	"classresource_scale",
	"classresource_opacity",
	"classresource_offsetX",
	"classresource_offsetY",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ClassResource:ApplyLayout()
	end)
end

for _, key in ipairs({ "classresource_textOffsetX", "classresource_textOffsetY" }) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ClassResource:ApplyLayout()
	end)
end

for _, key in ipairs({
	"classresource_font",
	"classresource_fontSize",
	"classresource_fontOutline",
	"classresource_fontColor",
	"classresource_useClassColor",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ClassResource:ApplyTextOptions()
		if GetCurrentMode() == MODE_TEXT then
			ClassResource:UpdateTextMode()
		end
	end)
end

CallbackRegistry:RegisterSettingCallback("classresource_mode", function()
	ClassResource:Refresh()
end)

CallbackRegistry:RegisterSettingCallback("classresource_visibility", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("classresource_visibilitySource", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("visibility_mode", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("visibility_hideOnUIHover", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("classresource_hideOnUIHover", function()
	ClassResource:UpdateVisibility()
end)
CallbackRegistry:RegisterSettingCallback("attachToMouse", function()
	ClassResource:UpdateVisibility()
end)

for _, key in ipairs({ "classresource_fillColor", "classresource_fillUseClassColor", "classresource_backgroundColor" }) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ClassResource:ApplyPipVisualOptions()
		if GetCurrentMode() == MODE_PIPS then
			ClassResource:SyncPower()
		end
	end)
end

CallbackRegistry:Register("VisibilityContextChanged", function()
	ClassResource:UpdateVisibility()
end, ClassResource)

--------------------------------------------------------------------------------
-- Module Registration
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
	name = L["Class Resource"] or "Class Resource",
	dbKey = "moduleEnabled_ClassResource",
	description = L["Class Resource Description"] or "Displays class resources near the cursor",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 3,
})
