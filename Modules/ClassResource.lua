-- SparkPoint ClassResource Module
-- Displays class resource pips near the cursor anchor.
-- Reads power directly from WoW APIs for immediate, accurate display.

local addonName, addon = ...
local L = addon.L
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local GetDBValue = addon.GetDBValue

local UnitClass       = UnitClass
local UnitPower       = UnitPower
local UnitPowerMax    = UnitPowerMax
local UnitExists      = UnitExists
local InCombatLockdown = InCombatLockdown
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local GetRuneCooldown = GetRuneCooldown
local GetSpecialization = GetSpecialization

--------------------------------------------------------------------------------
-- Power Type Enums
--------------------------------------------------------------------------------
local PT = {
	COMBO_POINTS   = (Enum and Enum.PowerType and Enum.PowerType.ComboPoints)   or 4,
	RUNES          = (Enum and Enum.PowerType and Enum.PowerType.Runes)          or 5,
	SOUL_SHARDS    = (Enum and Enum.PowerType and Enum.PowerType.SoulShards)     or 7,
	HOLY_POWER     = (Enum and Enum.PowerType and Enum.PowerType.HolyPower)      or 9,
	CHI            = (Enum and Enum.PowerType and Enum.PowerType.Chi)            or 12,
	ARCANE_CHARGES = (Enum and Enum.PowerType and Enum.PowerType.ArcaneCharges)  or 16,
	ESSENCE        = (Enum and Enum.PowerType and Enum.PowerType.Essence)        or 19,
}

-- Maelstrom Weapon aura spell ID (Enhancement Shaman)
local MAELSTROM_WEAPON_SPELL_ID = 344179

-- Unified pip texture.
-- Place your custom art at these paths (or change constants below).
local PIP_TEXTURE_FRAME_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\ClassResourcePipFrame.png"
local PIP_TEXTURE_BG_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\ClassResourcePipBg.png"
local PIP_TEXTURE_FILL_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\ClassResourcePipFill.png"
local PIP_TEXTURE_FALLBACK = "Interface\\Buttons\\WHITE8x8"

--------------------------------------------------------------------------------
-- Per-class pip configuration
-- powerEnum : Enum.PowerType value; nil for isRune / isMaelstrom special cases
-- maxCount  : default pip count (overridden live by UnitPowerMax)
-- fillColor : active pip color  {r,g,b,a}
-- emptyColor: inactive pip color {r,g,b,a}
--------------------------------------------------------------------------------
local CLASS_CONFIG = {
	PALADIN = {
		powerEnum  = PT.HOLY_POWER,
		maxCount   = 5,
		fillColor  = { r=0.95, g=0.89, b=0.59, a=1.00 },
		emptyColor = { r=0.30, g=0.28, b=0.18, a=0.40 },
	},
	DEATHKNIGHT = {
		isRune     = true,
		maxCount   = 6,
		fillColor  = { r=0.77, g=0.12, b=0.23, a=1.00 },
		emptyColor = { r=0.30, g=0.06, b=0.06, a=0.40 },
	},
	ROGUE = {
		powerEnum  = PT.COMBO_POINTS,
		maxCount   = 5,
		fillColor  = { r=1.00, g=0.96, b=0.00, a=1.00 },
		emptyColor = { r=0.40, g=0.38, b=0.00, a=0.40 },
	},
	DRUID = {
		powerEnum  = PT.COMBO_POINTS,
		maxCount   = 5,
		fillColor  = { r=1.00, g=0.49, b=0.04, a=1.00 },
		emptyColor = { r=0.40, g=0.20, b=0.02, a=0.40 },
	},
	MAGE = {
		powerEnum  = PT.ARCANE_CHARGES,
		maxCount   = 4,
		fillColor  = { r=0.41, g=0.80, b=0.94, a=1.00 },
		emptyColor = { r=0.16, g=0.32, b=0.38, a=0.40 },
	},
	MONK = {
		powerEnum  = PT.CHI,
		maxCount   = 5,
		fillColor  = { r=0.00, g=1.00, b=0.59, a=1.00 },
		emptyColor = { r=0.00, g=0.40, b=0.24, a=0.40 },
	},
	WARLOCK = {
		powerEnum  = PT.SOUL_SHARDS,
		maxCount   = 5,
		fillColor  = { r=0.58, g=0.51, b=0.79, a=1.00 },
		emptyColor = { r=0.23, g=0.20, b=0.32, a=0.40 },
	},
	EVOKER = {
		powerEnum  = PT.ESSENCE,
		maxCount   = 6,
		fillColor  = { r=0.20, g=0.58, b=0.50, a=1.00 },
		emptyColor = { r=0.08, g=0.23, b=0.20, a=0.40 },
	},
	SHAMAN = {
		isMaelstrom = true,
		maxCount    = 5,
		fillColor   = { r=0.00, g=0.44, b=0.87, a=1.00 },
		emptyColor  = { r=0.00, g=0.18, b=0.35, a=0.40 },
	},
}

-- Visual dimensions (pixels at scale 1)
local PIP_SIZE    = 14
local PIP_SPACING = 3

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")

local ClassResource = {}
addon.Modules.ClassResourceObj = ClassResource

local VISIBILITY = {
	ALWAYS        = "ALWAYS",
	IN_COMBAT     = "IN_COMBAT",
	OUT_OF_COMBAT = "OUT_OF_COMBAT",
	HAS_TARGET    = "HAS_TARGET",
	CASTING       = "CASTING",
}

local isEnabled  = false
local container  = nil         -- pip container frame, child of AnchorFrame
local pips       = {}          -- { [i] = { frame=Texture, bg=Texture, fill=Texture } }
local pipMax     = 0           -- current max pip count rendered
local activeCfg  = nil         -- active CLASS_CONFIG entry

--------------------------------------------------------------------------------
-- Visibility
--------------------------------------------------------------------------------
local function IsPlayerCasting()
	return UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil
end

function ClassResource:ShouldBeVisible()
	local vis = GetDBValue("classresource_visibility") or VISIBILITY.ALWAYS
	if vis == VISIBILITY.IN_COMBAT     then return InCombatLockdown() and true or false end
	if vis == VISIBILITY.OUT_OF_COMBAT then return not InCombatLockdown() end
	if vis == VISIBILITY.HAS_TARGET    then return UnitExists("target") end
	if vis == VISIBILITY.CASTING       then return IsPlayerCasting() end
	return true
end

--------------------------------------------------------------------------------
-- Power Sampling
-- All reads happen here against live WoW API; no Blizzard frame state used.
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
	if not C_UnitAuras or not C_UnitAuras.GetPlayerAuraBySpellID then
		return 0, 5
	end
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(MAELSTROM_WEAPON_SPELL_ID)
	if not aura then return 0, 5 end
	return (aura.applications or 0), 5
end

local function ReadPower()
	if not activeCfg then return 0, 0 end

	if activeCfg.isRune then
		return GetRunePower()
	end

	if activeCfg.isMaelstrom then
		return GetMaelstromWeaponPower()
	end

	local pEnum = activeCfg.powerEnum
	if not pEnum then return 0, 0 end

	local function NormalizePowerValue(value)
		if value == nil then return 0 end
		if type(value) == "number" then return value end

		-- Secret values can stringify to non-plain numerics depending on client build.
		local s = tostring(value) or "0"
		local n = tonumber(s)
		if n then return n end

		-- Fallback: extract first numeric token from the string representation.
		local token = s:match("[-+]?%d+%.?%d*")
		return tonumber(token) or 0
	end

	local cur = NormalizePowerValue(UnitPower("player", pEnum))
	local max = NormalizePowerValue(UnitPowerMax("player", pEnum))
	return cur, max
end

--------------------------------------------------------------------------------
-- Pip Widget
--------------------------------------------------------------------------------
local function EnsureContainer()
	if container then return end
	local anchor = AnchorFrame:GetFrame()
	if not anchor then return end

	container = CreateFrame("Frame", nil, anchor)
	container:SetFrameStrata("HIGH")
	container:SetFrameLevel((anchor:GetFrameLevel() or 1) + 20)
	container:SetSize(1, 1)
	container:Hide()
end

local function GetPip(i)
	if pips[i] then return pips[i] end
	if not container then return nil end
	local p = {
		frame = container:CreateTexture(nil, "ARTWORK", nil, 2),
		bg    = container:CreateTexture(nil, "ARTWORK", nil, 0),
		fill  = container:CreateTexture(nil, "ARTWORK", nil, 1),
	}
	p.styleReady = false
	p.frame:Hide()
	p.bg:Hide()
	p.fill:Hide()
	pips[i] = p
	return p
end

local function ConfigurePipTextures(p, cfg)
	if not p then return end

	p.frame:SetTexCoord(0, 1, 0, 1)
	p.bg:SetTexCoord(0, 1, 0, 1)
	p.fill:SetTexCoord(0, 1, 0, 1)
	p.frame:SetTexture(PIP_TEXTURE_FRAME_PATH)
	p.bg:SetTexture(PIP_TEXTURE_BG_PATH)
	p.fill:SetTexture(PIP_TEXTURE_FILL_PATH)

	if not p.frame:GetTexture() then
		p.frame:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not p.bg:GetTexture() then
		p.bg:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not p.fill:GetTexture() then
		p.fill:SetTexture(PIP_TEXTURE_FALLBACK)
	end

	local fc = cfg.fillColor
	local ec = cfg.emptyColor
	p.frame:SetVertexColor(1, 1, 1, 0.95)
	p.bg:SetVertexColor(ec.r, ec.g, ec.b, ec.a)
	p.fill:SetVertexColor(fc.r, fc.g, fc.b, fc.a)

	p.styleReady = true
end

local function LayoutPips(cfg, count)
	if not container or count < 1 then return end

	local total = count * PIP_SIZE + (count - 1) * PIP_SPACING
	local x0    = -(total / 2) + (PIP_SIZE / 2)

	for i = 1, count do
			local p  = GetPip(i)
		if p then
			local x  = x0 + (i - 1) * (PIP_SIZE + PIP_SPACING)

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

	-- Hide any surplus pips from a previous larger layout
	for i = count + 1, #pips do
		local p = pips[i]
		if p then p.frame:Hide(); p.bg:Hide(); p.fill:Hide() end
	end

	container:SetSize(total, PIP_SIZE)
	pipMax = count
end

local function HidePips()
	for i = 1, #pips do
		local p = pips[i]
		if p then p.frame:Hide(); p.bg:Hide(); p.fill:Hide() end
	end
end

local function ApplyPipState(current, max)
	if not container or not activeCfg then
		HidePips()
		return
	end

	-- Rebuild layout when max changes (e.g. Chi varies by spec, Druid form)
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
		if p then p.frame:Hide(); p.bg:Hide(); p.fill:Hide() end
	end
end

--------------------------------------------------------------------------------
-- Layout and Visibility
--------------------------------------------------------------------------------
function ClassResource:ApplyLayout()
	if not container then return end
	local anchor = AnchorFrame:GetFrame()
	if not anchor then return end

	local offsetX = GetDBValue("classresource_offsetX") or 0
	local offsetY = GetDBValue("classresource_offsetY") or 0
	local scale   = GetDBValue("classresource_scale")   or 1
	local opacity = GetDBValue("classresource_opacity")
	if opacity == nil then opacity = 1 end

	container:SetParent(anchor)
	container:ClearAllPoints()
	container:SetPoint("CENTER", anchor, "CENTER", offsetX, offsetY)
	container:SetScale(scale)
	container:SetAlpha(opacity)
	container:SetFrameStrata("HIGH")
	container:SetFrameLevel((anchor:GetFrameLevel() or 1) + 20)
end

function ClassResource:UpdateVisibility()
	if not isEnabled or not activeCfg then
		if container then container:Hide() end
		AnchorFrame:Hide("classresource")
		return
	end

	if not self:ShouldBeVisible() then
		if container then container:Hide() end
		AnchorFrame:Hide("classresource")
		return
	end

	if container then container:Show() end
	AnchorFrame:Show("classresource")
end

function ClassResource:SyncPower()
	if not isEnabled or not activeCfg then return end
	local current, max = ReadPower()
	ApplyPipState(current, max)
end

--------------------------------------------------------------------------------
-- Class Detection
--------------------------------------------------------------------------------
local function DetectActiveClass()
	local _, classTag = UnitClass("player")
	if not classTag then return nil, nil end

	local cfg = CLASS_CONFIG[classTag]
	if not cfg then return nil, nil end

	-- Shaman: Maelstrom Weapon is Enhancement-only (spec 2)
	if classTag == "SHAMAN" then
		local spec = GetSpecialization and GetSpecialization() or 0
		if spec ~= 2 then return nil, nil end
	end

	-- For Druids: activeCfg is always set; SyncPower hides pips when
	-- UnitPowerMax returns 0 (non-feral forms without combo points).

	return classTag, cfg
end

function ClassResource:Refresh()
	EnsureContainer()

	local _, cfg = DetectActiveClass()
	activeCfg   = cfg
	pipMax      = 0  -- force LayoutPips on next SyncPower
	for i = 1, #pips do
		pips[i].styleReady = false
	end

	if activeCfg then
		LayoutPips(activeCfg, activeCfg.maxCount)
		self:ApplyLayout()
	else
		HidePips()
	end

	self:UpdateVisibility()
	self:SyncPower()
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
	-- Druid form changes affect combo point availability
	self:SyncPower()
end

function ClassResource:UNIT_POWER_UPDATE(event, unit)
	if unit ~= "player" then return end
	self:SyncPower()
end

function ClassResource:UNIT_MAXPOWER(event, unit)
	if unit ~= "player" then return end
	-- Max can change (e.g. Chi count differs by talent, Druid form changes)
	self:SyncPower()
end

function ClassResource:UNIT_DISPLAYPOWER(event, unit)
	if unit ~= "player" then return end
	-- Power type display change (Druid entering/leaving forms, etc.)
	self:Refresh()
end

function ClassResource:UNIT_AURA(event, unit)
	if unit ~= "player" then return end
	-- Maelstrom Weapon stacks tracked as an aura
	if activeCfg and activeCfg.isMaelstrom then
		self:SyncPower()
	end
end

function ClassResource:PLAYER_REGEN_DISABLED()
	self:UpdateVisibility()
end

function ClassResource:PLAYER_REGEN_ENABLED()
	self:UpdateVisibility()
end

function ClassResource:PLAYER_TARGET_CHANGED()
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_START(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_STOP(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_INTERRUPTED(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_FAILED(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_FAILED_QUIET(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_CHANNEL_START(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_CHANNEL_STOP(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_EMPOWER_START(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
end

function ClassResource:UNIT_SPELLCAST_EMPOWER_STOP(event, unit)
	if unit ~= "player" then return end
	self:UpdateVisibility()
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
		EL:RegisterEvent("PLAYER_REGEN_DISABLED")
		EL:RegisterEvent("PLAYER_REGEN_ENABLED")
		EL:RegisterEvent("PLAYER_TARGET_CHANGED")
		EL:RegisterUnitEvent("UNIT_DISPLAYPOWER",              "player")
		EL:RegisterUnitEvent("UNIT_POWER_UPDATE",              "player")
		EL:RegisterUnitEvent("UNIT_MAXPOWER",                  "player")
		EL:RegisterUnitEvent("UNIT_AURA",                      "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_START",           "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_STOP",            "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED",     "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED",          "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET",    "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START",   "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP",    "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START",   "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP",    "player")

		ClassResource:Refresh()
	else
		EL:UnregisterAllEvents()
		if container then container:Hide() end
		AnchorFrame:Hide("classresource")
		activeCfg   = nil
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
for _, key in ipairs({ "classresource_scale", "classresource_opacity",
                       "classresource_offsetX", "classresource_offsetY" }) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ClassResource:ApplyLayout()
	end)
end

CallbackRegistry:RegisterSettingCallback("classresource_visibility", function()
	ClassResource:UpdateVisibility()
end)

--------------------------------------------------------------------------------
-- Module Registration
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
	name        = L["Class Resource"] or "Class Resource",
	dbKey       = "moduleEnabled_ClassResource",
	description = L["Class Resource Description"] or "Displays class resource pips near the cursor",
	toggleFunc  = EnableModule,
	categoryID  = 1,
	uiOrder     = 3,
})
