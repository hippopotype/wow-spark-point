-- SparkPoint ClassResource Module
-- Displays class resources as either simple text or dynamic status bars near the cursor

local addonName, addon = ...
local L = addon.L
local API = addon.API
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------
local classResourceTextFrame
local classResourceBarsFrame
local currentPowerType
local lastPowerValue = ""
local updateTimer = 0
local UPDATE_INTERVAL = 0.1

local bars = {}

local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local GetSpecialization = GetSpecialization
local UnitClass = UnitClass
local tostring = tostring
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local issecretvalue = _G.issecretvalue

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")

--------------------------------------------------------------------------------
-- ClassResource Module Object
--------------------------------------------------------------------------------
local ClassResource = {}
addon.Modules.ClassResourceObj = ClassResource

local MODE_TEXT = "TEXT"
local MODE_BARS = "BARS"

local VISIBILITY_OPTIONS = {
	ALWAYS = "ALWAYS",
	IN_COMBAT = "IN_COMBAT",
	OUT_OF_COMBAT = "OUT_OF_COMBAT",
	HAS_TARGET = "HAS_TARGET",
	CASTING = "CASTING",
}

local BLIZZARD_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local BAR_TEX_BY_RESOURCE = {
	LUNAR_POWER = "Unit_Druid_AstralPower_Fill",
	MAELSTROM = "Unit_Shaman_Maelstrom_Fill",
	INSANITY = "Unit_Priest_Insanity_Fill",
	FURY = "Unit_DemonHunter_Fury_Fill",
	RUNIC_POWER = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-RunicPower",
	ENERGY = "UI-HUD-UnitFrame-Player-PortraitOn-ClassResource-Bar-Energy",
	FOCUS = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Focus",
	RAGE = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Rage",
	MANA = "UI-HUD-UnitFrame-Player-PortraitOn-Bar-Mana",
}

local POWER_ENUM = {
	RAGE = Enum.PowerType.Rage,
	FOCUS = Enum.PowerType.Focus,
	ENERGY = Enum.PowerType.Energy,
	COMBO_POINTS = Enum.PowerType.ComboPoints,
	RUNIC_POWER = Enum.PowerType.RunicPower,
	RUNES = Enum.PowerType.Runes,
	SOUL_SHARDS = Enum.PowerType.SoulShards,
	LUNAR_POWER = Enum.PowerType.LunarPower,
	HOLY_POWER = Enum.PowerType.HolyPower,
	MAELSTROM = Enum.PowerType.Maelstrom,
	CHI = Enum.PowerType.Chi,
	INSANITY = Enum.PowerType.Insanity,
	ARCANE_CHARGES = Enum.PowerType.ArcaneCharges,
	FURY = Enum.PowerType.Fury,
	PAIN = Enum.PowerType.Pain,
	ESSENCE = Enum.PowerType.Essence,
	MANA = Enum.PowerType.Mana,
}

local POWER_ORDER = {
	"RAGE",
	"ESSENCE",
	"FOCUS",
	"ENERGY",
	"FURY",
	"PAIN",
	"COMBO_POINTS",
	"RUNIC_POWER",
	"RUNES",
	"SOUL_SHARDS",
	"LUNAR_POWER",
	"HOLY_POWER",
	"MAELSTROM",
	"CHI",
	"INSANITY",
	"ARCANE_CHARGES",
	"MANA",
}

local POWER_CONFIG = {
	ROGUE = {default = Enum.PowerType.ComboPoints},
	DRUID = {
		[2] = Enum.PowerType.ComboPoints,
		[4] = Enum.PowerType.ComboPoints,
		[1] = Enum.PowerType.LunarPower,
	},
	PALADIN = {
		[1] = Enum.PowerType.HolyPower,
		[2] = Enum.PowerType.HolyPower,
		[3] = Enum.PowerType.HolyPower,
		default = Enum.PowerType.HolyPower,
	},
	MONK = {
		[3] = Enum.PowerType.Chi,
	},
	DEATHKNIGHT = {default = Enum.PowerType.Runes},
	WARLOCK = {default = Enum.PowerType.SoulShards},
	MAGE = {
		[1] = Enum.PowerType.ArcaneCharges,
	},
	DEMONHUNTER = {
		[1] = Enum.PowerType.Fury,
		[2] = Enum.PowerType.Pain,
	},
	EVOKER = {default = Enum.PowerType.Essence},
	PRIEST = {
		[3] = Enum.PowerType.Insanity,
	},
	SHAMAN = {
		[1] = Enum.PowerType.Maelstrom,
		[2] = Enum.PowerType.Maelstrom,
	},
}

local POWERTYPE_CLASSES = {
	DRUID = {
		[1] = { MAIN = "LUNAR_POWER", RAGE = true, ENERGY = true, MANA = true, COMBO_POINTS = true },
		[2] = { MAIN = "ENERGY", COMBO_POINTS = true, RAGE = true, MANA = true },
		[3] = { MAIN = "RAGE", ENERGY = true, MANA = true, COMBO_POINTS = true },
		[4] = { MAIN = "MANA", RAGE = true, ENERGY = true, COMBO_POINTS = true },
	},
	DEMONHUNTER = {
		[1] = { MAIN = "FURY" },
		[2] = { MAIN = "PAIN", FURY = true },
	},
	DEATHKNIGHT = {
		[1] = { MAIN = "RUNIC_POWER", RUNES = true },
		[2] = { MAIN = "RUNIC_POWER", RUNES = true },
		[3] = { MAIN = "RUNIC_POWER", RUNES = true },
	},
	PALADIN = {
		[1] = { MAIN = "HOLY_POWER", MANA = true },
		[2] = { MAIN = "HOLY_POWER", MANA = true },
		[3] = { MAIN = "HOLY_POWER", MANA = true },
	},
	HUNTER = {
		[1] = { MAIN = "FOCUS" },
		[2] = { MAIN = "FOCUS" },
		[3] = { MAIN = "FOCUS" },
	},
	ROGUE = {
		[1] = { MAIN = "ENERGY", COMBO_POINTS = true },
		[2] = { MAIN = "ENERGY", COMBO_POINTS = true },
		[3] = { MAIN = "ENERGY", COMBO_POINTS = true },
	},
	PRIEST = {
		[1] = { MAIN = "MANA" },
		[2] = { MAIN = "MANA" },
		[3] = { MAIN = "INSANITY", MANA = true },
	},
	SHAMAN = {
		[1] = { MAIN = "MAELSTROM", MANA = true },
		[2] = { MAIN = "MAELSTROM", MANA = true },
		[3] = { MAIN = "MANA" },
	},
	MAGE = {
		[1] = { MAIN = "ARCANE_CHARGES", MANA = true },
		[2] = { MAIN = "MANA" },
		[3] = { MAIN = "MANA" },
	},
	WARLOCK = {
		[1] = { MAIN = "SOUL_SHARDS", MANA = true },
		[2] = { MAIN = "SOUL_SHARDS", MANA = true },
		[3] = { MAIN = "SOUL_SHARDS", MANA = true },
	},
	MONK = {
		[1] = { MAIN = "ENERGY" },
		[2] = { MAIN = "MANA" },
		[3] = { MAIN = "CHI", ENERGY = true, MANA = true },
	},
	EVOKER = {
		[1] = { MAIN = "ESSENCE", MANA = true },
		[2] = { MAIN = "MANA", ESSENCE = true },
		[3] = { MAIN = "ESSENCE", MANA = true },
	},
	WARRIOR = {
		[1] = { MAIN = "RAGE" },
		[2] = { MAIN = "RAGE" },
		[3] = { MAIN = "RAGE" },
	},
}

local function IsSecret(value)
	return issecretvalue and issecretvalue(value)
end

local function SafeToString(value, fallback)
	local ok, text = pcall(tostring, value)
	if ok then return text end
	return fallback or "0"
end

local function IsPlayerCastingNow()
	local castName = UnitCastingInfo("player")
	if castName ~= nil then return true end

	local channelName = UnitChannelInfo("player")
	if channelName ~= nil then return true end

	local castModule = addon.Modules and addon.Modules.CastObj
	if castModule and castModule.GetFrame then
		local castFrame = castModule:GetFrame()
		if castFrame and castFrame:IsShown() then
			return true
		end
	end

	return false
end

local function IsPowerTypeUsable(powerType)
	if powerType == nil then return false end

	local maxPower = UnitPowerMax("player", powerType)
	if maxPower == nil then return false end
	if IsSecret(maxPower) then return true end

	local ok, hasPower = pcall(function()
		return maxPower > 0
	end)
	if not ok then return true end
	return hasPower and true or false
end

local function GetCurrentMode()
	local mode = GetDBValue("classresource_mode")
	if mode == MODE_BARS then return MODE_BARS end
	return MODE_TEXT
end

local function GetPowerTokenFromEnum(enumValue)
	for token, enumType in pairs(POWER_ENUM) do
		if enumType == enumValue then
			return token
		end
	end
	return nil
end

function ClassResource:ShouldBeVisible()
	local setting = GetDBValue("classresource_visibility") or VISIBILITY_OPTIONS.ALWAYS
	if setting == VISIBILITY_OPTIONS.IN_COMBAT then
		return InCombatLockdown()
	elseif setting == VISIBILITY_OPTIONS.OUT_OF_COMBAT then
		return not InCombatLockdown()
	elseif setting == VISIBILITY_OPTIONS.HAS_TARGET then
		return UnitExists("target")
	elseif setting == VISIBILITY_OPTIONS.CASTING then
		return IsPlayerCastingNow()
	end
	return true
end

--------------------------------------------------------------------------------
-- Text Mode
--------------------------------------------------------------------------------
function ClassResource:DetectPowerType()
	local _, class = UnitClass("player")
	local spec = GetSpecialization()

	local classConfig = POWER_CONFIG[class]
	if not classConfig then
		currentPowerType = nil
		return
	end

	local powerType = classConfig[spec] or classConfig.default
	if IsPowerTypeUsable(powerType) then
		currentPowerType = powerType
		return
	end

	currentPowerType = nil
end

function ClassResource:UpdateTextMode()
	if not classResourceTextFrame then return end

	if not currentPowerType then
		self:DetectPowerType()
		if not currentPowerType then
			classResourceTextFrame:Hide()
			AnchorFrame:Hide("classresource")
			return
		end
	end

	if not self:ShouldBeVisible() then
		classResourceTextFrame:Hide()
		AnchorFrame:Hide("classresource")
		return
	end

	local power = UnitPower("player", currentPowerType)
	local powerString
	if power == nil then
		powerString = "0"
	elseif IsSecret(power) then
		powerString = SafeToString(power, "?")
	else
		powerString = SafeToString(power, "0")
	end

	if powerString ~= lastPowerValue then
		lastPowerValue = powerString
		classResourceTextFrame.powerText:SetText(powerString)
	end

	if not classResourceTextFrame:IsShown() then
		classResourceTextFrame:Show()
		AnchorFrame:Show("classresource")
	end
end

function ClassResource:ApplyTextOptions()
	if not classResourceTextFrame then return end

	local font = GetDBValue("classresource_font")
	local fontSize = GetDBValue("classresource_fontSize")
	local fontOutline = GetDBValue("classresource_fontOutline")
	local r, g, b, a
	if GetDBBool("classresource_useClassColor") then
		r, g, b, a = API.GetPlayerClassColor()
	else
		r, g, b, a = GetDBColor("classresource_fontColor")
	end
	local offsetX = GetDBValue("classresource_offsetX")
	local offsetY = GetDBValue("classresource_offsetY")

	local powerText = classResourceTextFrame.powerText
	powerText:SetFont(font, fontSize, fontOutline)
	powerText:SetTextColor(r, g, b, a)
	powerText:ClearAllPoints()
	powerText:SetPoint("CENTER", classResourceTextFrame, "CENTER", offsetX, offsetY)
end

--------------------------------------------------------------------------------
-- Bars Mode
--------------------------------------------------------------------------------
local function BuildSpecResourceList()
	local _, class = UnitClass("player")
	local spec = GetSpecialization()
	local classMap = POWERTYPE_CLASSES[class]
	if not classMap then return {} end
	local specInfo = classMap[spec]
	if not specInfo or not specInfo.MAIN then return {} end

	local showSecondary = GetDBBool("classresource_bars_showSecondary")
	local list = {}
	list[#list + 1] = specInfo.MAIN

	if showSecondary then
		for _, token in ipairs(POWER_ORDER) do
			if token ~= specInfo.MAIN and specInfo[token] then
				list[#list + 1] = token
			end
		end
	end

	-- Keep displayed power type visible for stance/spec transitions.
	local displayEnum = UnitPowerType("player")
	local displayToken = GetPowerTokenFromEnum(displayEnum)
	if displayToken then
		local already = false
		for i = 1, #list do
			if list[i] == displayToken then
				already = true
				break
			end
		end
		if not already then
			list[#list + 1] = displayToken
		end
	end

	return list
end

local function ResolveBarTexture(token)
	local mode = GetDBValue("classresource_bars_texture") or "AUTO"
	if mode == "BLIZZARD" then
		return BLIZZARD_TEX
	end
	if mode == "MANA" then
		return BAR_TEX_BY_RESOURCE.MANA or BLIZZARD_TEX
	end
	if mode == "RAGE" then
		return BAR_TEX_BY_RESOURCE.RAGE or BLIZZARD_TEX
	end
	if mode == "AUTO" then
		return BAR_TEX_BY_RESOURCE[token] or BLIZZARD_TEX
	end
	return BLIZZARD_TEX
end

local function ApplyStatusBarTexture(bar, token)
	if not bar then return end
	local tex = ResolveBarTexture(token)
	local ok = pcall(bar.SetStatusBarTexture, bar, tex)
	if not ok then
		bar:SetStatusBarTexture(BLIZZARD_TEX)
	end
end

local function GetBarColor(token)
	if GetDBBool("classresource_bars_useClassColor") then
		return API.GetPlayerClassColor()
	end

	if GetDBBool("classresource_bars_usePowerColor") then
		local pbc = PowerBarColor
		if pbc then
			local byToken = pbc[token]
			if byToken and byToken.r then
				return byToken.r, byToken.g, byToken.b, byToken.a or 1
			end
			local enumValue = POWER_ENUM[token]
			local byEnum = enumValue and pbc[enumValue]
			if byEnum and byEnum.r then
				return byEnum.r, byEnum.g, byEnum.b, byEnum.a or 1
			end
		end
	end

	return GetDBColor("classresource_bars_barColor")
end

local function FormatBarText(cur, max)
	local style = GetDBValue("classresource_bars_textStyle") or "PERCENT"
	if style == "NONE" then return "" end

	if IsSecret(cur) or IsSecret(max) then
		if style == "CURRENT" then return SafeToString(cur, "?") end
		if style == "CURMAX" then return SafeToString(cur, "?") .. " / " .. SafeToString(max, "?") end
		return "?"
	end

	local curN = tonumber(cur) or 0
	local maxN = tonumber(max) or 0

	if style == "CURRENT" then
		return tostring(curN)
	elseif style == "CURMAX" then
		return tostring(curN) .. " / " .. tostring(maxN)
	else
		if maxN <= 0 then return "0%" end
		return string.format("%d%%", math.floor((curN / maxN) * 100 + 0.5))
	end
end

local function GetOrCreateBar(index, token)
	local bar = bars[index]
	if bar then
		bar.token = token
		bar.powerEnum = POWER_ENUM[token]
		return bar
	end

	bar = CreateFrame("StatusBar", nil, classResourceBarsFrame, "BackdropTemplate")
	bar.token = token
	bar.powerEnum = POWER_ENUM[token]

	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints(bar)

	bar.text = bar:CreateFontString(nil, "OVERLAY")
	bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)

	bars[index] = bar
	return bar
end

function ClassResource:ApplyBarsOptions()
	if not classResourceBarsFrame then return end

	local width = GetDBValue("classresource_bars_width")
	local height = GetDBValue("classresource_bars_height")
	local spacing = GetDBValue("classresource_bars_spacing")
	local offsetX = GetDBValue("classresource_bars_offsetX")
	local offsetY = GetDBValue("classresource_bars_offsetY")
	local showText = GetDBBool("classresource_bars_showText")
	local bgR, bgG, bgB, bgA = GetDBColor("classresource_bars_backgroundColor")

	classResourceBarsFrame:ClearAllPoints()
	classResourceBarsFrame:SetPoint("CENTER", AnchorFrame:GetFrame(), "CENTER", offsetX, offsetY)

	local font = GetDBValue("classresource_bars_font")
	local fontSize = GetDBValue("classresource_bars_fontSize")
	local fontOutline = GetDBValue("classresource_bars_fontOutline")

	for i, bar in ipairs(bars) do
		bar:ClearAllPoints()
		if i == 1 then
			bar:SetPoint("TOP", classResourceBarsFrame, "TOP", 0, 0)
		else
			bar:SetPoint("TOP", bars[i - 1], "BOTTOM", 0, -spacing)
		end
		bar:SetSize(width, height)

		local r, g, b, a = GetBarColor(bar.token)
		bar:SetStatusBarColor(r, g, b, a)
		bar.bg:SetColorTexture(bgR, bgG, bgB, bgA)
		ApplyStatusBarTexture(bar, bar.token)

		bar.text:SetFont(font, fontSize, fontOutline)
		bar.text:SetShown(showText)
		if showText then
			bar.text:SetTextColor(1, 1, 1, 1)
		end
	end

	local count = #bars
	if count > 0 then
		classResourceBarsFrame:SetSize(width, (count * height) + ((count - 1) * spacing))
	else
		classResourceBarsFrame:SetSize(width, height)
	end
end

function ClassResource:RebuildBars()
	if not classResourceBarsFrame then return end

	local desired = BuildSpecResourceList()
	for i = 1, #desired do
		GetOrCreateBar(i, desired[i]):Show()
	end

	for i = #desired + 1, #bars do
		bars[i]:Hide()
	end

	self:ApplyBarsOptions()
end

function ClassResource:UpdateBarsMode()
	if not classResourceBarsFrame then return end

	if not self:ShouldBeVisible() then
		classResourceBarsFrame:Hide()
		AnchorFrame:Hide("classresource")
		return
	end

	if #bars == 0 then
		self:RebuildBars()
	end

	local anyShown = false
	for _, bar in ipairs(bars) do
		if bar:IsShown() then
			local powerEnum = bar.powerEnum
			if powerEnum then
				local cur = UnitPower("player", powerEnum)
				local max = UnitPowerMax("player", powerEnum)

				if cur ~= nil and max ~= nil then
					pcall(bar.SetMinMaxValues, bar, 0, max)
					pcall(bar.SetValue, bar, cur)
					if bar.text and bar.text:IsShown() then
						bar.text:SetText(FormatBarText(cur, max))
					end
					anyShown = true
				end
			end
		end
	end

	if anyShown then
		if not classResourceBarsFrame:IsShown() then
			classResourceBarsFrame:Show()
		end
		AnchorFrame:Show("classresource")
	else
		classResourceBarsFrame:Hide()
		AnchorFrame:Hide("classresource")
	end
end

--------------------------------------------------------------------------------
-- Unified Update
--------------------------------------------------------------------------------
function ClassResource:UpdateDisplay()
	if GetCurrentMode() == MODE_BARS then
		if classResourceTextFrame then
			classResourceTextFrame:Hide()
		end
		self:UpdateBarsMode()
	else
		if classResourceBarsFrame then
			classResourceBarsFrame:Hide()
		end
		self:UpdateTextMode()
	end
end

local function OnUpdate(self, elapsed)
	updateTimer = updateTimer + elapsed
	if updateTimer >= UPDATE_INTERVAL then
		updateTimer = 0
		ClassResource:UpdateDisplay()
	end
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------
function ClassResource:PLAYER_SPECIALIZATION_CHANGED()
	self:DetectPowerType()
	self:RebuildBars()
	self:UpdateDisplay()
end

function ClassResource:PLAYER_ENTERING_WORLD()
	self:DetectPowerType()
	self:RebuildBars()
	self:UpdateDisplay()
end

function ClassResource:UPDATE_SHAPESHIFT_FORM()
	self:DetectPowerType()
	self:RebuildBars()
	self:UpdateDisplay()
end

function ClassResource:UNIT_DISPLAYPOWER(event, unit)
	if unit ~= "player" then return end
	self:RebuildBars()
	self:UpdateDisplay()
end

function ClassResource:UNIT_POWER_UPDATE(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

function ClassResource:UNIT_POWER_FREQUENT(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

function ClassResource:UNIT_MAXPOWER(event, unit)
	if unit ~= "player" then return end
	self:DetectPowerType()
	self:RebuildBars()
	self:UpdateDisplay()
end

function ClassResource:PLAYER_REGEN_DISABLED()
	self:UpdateDisplay()
end

function ClassResource:PLAYER_REGEN_ENABLED()
	self:UpdateDisplay()
end

function ClassResource:PLAYER_TARGET_CHANGED()
	self:UpdateDisplay()
end

function ClassResource:UNIT_SPELLCAST_START(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

function ClassResource:UNIT_SPELLCAST_STOP(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

function ClassResource:UNIT_SPELLCAST_INTERRUPTED(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

function ClassResource:UNIT_SPELLCAST_FAILED(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

function ClassResource:UNIT_SPELLCAST_FAILED_QUIET(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

function ClassResource:UNIT_SPELLCAST_CHANNEL_START(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

function ClassResource:UNIT_SPELLCAST_CHANNEL_STOP(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

function ClassResource:UNIT_SPELLCAST_CHANNEL_UPDATE(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

function ClassResource:UNIT_SPELLCAST_EMPOWER_START(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

function ClassResource:UNIT_SPELLCAST_EMPOWER_STOP(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

function ClassResource:UNIT_SPELLCAST_EMPOWER_UPDATE(event, unit)
	if unit ~= "player" then return end
	self:UpdateDisplay()
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------
function ClassResource:Initialize()
	local anchor = AnchorFrame:GetFrame()
	if not anchor then return end

	classResourceTextFrame = CreateFrame("Frame", nil, anchor)
	classResourceTextFrame:SetAllPoints()
	classResourceTextFrame:SetFrameStrata("HIGH")
	classResourceTextFrame:Hide()

	classResourceTextFrame.powerText = classResourceTextFrame:CreateFontString(nil, "OVERLAY")
	classResourceTextFrame.powerText:SetPoint("CENTER")
	classResourceTextFrame:SetScript("OnUpdate", OnUpdate)

	classResourceBarsFrame = CreateFrame("Frame", nil, anchor)
	classResourceBarsFrame:SetFrameStrata("HIGH")
	classResourceBarsFrame:Hide()

	self:ApplyTextOptions()
	self:DetectPowerType()
	self:RebuildBars()
	self:UpdateDisplay()
end

local function EnableModule(enabled)
	if enabled then
		if not classResourceTextFrame or not classResourceBarsFrame then
			ClassResource:Initialize()
		end

		EL:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
		EL:RegisterEvent("PLAYER_ENTERING_WORLD")
		EL:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		EL:RegisterEvent("PLAYER_REGEN_DISABLED")
		EL:RegisterEvent("PLAYER_REGEN_ENABLED")
		EL:RegisterEvent("PLAYER_TARGET_CHANGED")
		EL:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
		EL:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
		EL:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
		EL:RegisterUnitEvent("UNIT_MAXPOWER", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")

		ClassResource:DetectPowerType()
		ClassResource:RebuildBars()
		ClassResource:UpdateDisplay()
	else
		EL:UnregisterAllEvents()
		if classResourceTextFrame then classResourceTextFrame:Hide() end
		if classResourceBarsFrame then classResourceBarsFrame:Hide() end
		AnchorFrame:Hide("classresource")
	end
end

--------------------------------------------------------------------------------
-- Event Dispatcher
--------------------------------------------------------------------------------
EL:SetScript("OnEvent", function(self, event, ...)
	if ClassResource[event] then
		ClassResource[event](ClassResource, event, ...)
	end
end)

--------------------------------------------------------------------------------
-- Register Setting Callbacks
--------------------------------------------------------------------------------
local textSettingKeys = {
	"classresource_font",
	"classresource_fontSize",
	"classresource_fontOutline",
	"classresource_fontColor",
	"classresource_offsetX",
	"classresource_offsetY",
	"classresource_useClassColor",
}

for _, key in ipairs(textSettingKeys) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ClassResource:ApplyTextOptions()
		ClassResource:UpdateDisplay()
	end)
end

local barsSettingKeys = {
	"classresource_bars_width",
	"classresource_bars_height",
	"classresource_bars_spacing",
	"classresource_bars_offsetX",
	"classresource_bars_offsetY",
	"classresource_bars_showSecondary",
	"classresource_bars_showText",
	"classresource_bars_textStyle",
	"classresource_bars_font",
	"classresource_bars_fontSize",
	"classresource_bars_fontOutline",
	"classresource_bars_barColor",
	"classresource_bars_backgroundColor",
	"classresource_bars_useClassColor",
	"classresource_bars_usePowerColor",
	"classresource_bars_texture",
}

for _, key in ipairs(barsSettingKeys) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		ClassResource:RebuildBars()
		ClassResource:UpdateDisplay()
	end)
end

CallbackRegistry:RegisterSettingCallback("classresource_mode", function()
	ClassResource:RebuildBars()
	ClassResource:UpdateDisplay()
end)

CallbackRegistry:RegisterSettingCallback("classresource_visibility", function()
	ClassResource:UpdateDisplay()
end)

--------------------------------------------------------------------------------
-- Register Module
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
	name = L["Class Resource"] or "Class Resource",
	dbKey = "moduleEnabled_ClassResource",
	description = L["Class Resource Description"] or "Displays your class resource as text or bars",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 3,
})
