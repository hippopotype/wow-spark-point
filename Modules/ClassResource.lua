-- SparkPoint ClassResource Module
-- Displays class-specific power resources as text near the cursor

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
local classResourceFrame
local currentPowerType
local lastPowerValue = ""
local updateTimer = 0
local UPDATE_INTERVAL = 0.1  -- Throttle updates to 10 per second

local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
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

local VISIBILITY_OPTIONS = {
    ALWAYS = "ALWAYS",
    IN_COMBAT = "IN_COMBAT",
    OUT_OF_COMBAT = "OUT_OF_COMBAT",
    HAS_TARGET = "HAS_TARGET",
    CASTING = "CASTING",
}

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function IsPowerTypeUsable(powerType)
    if powerType == nil then
        return false
    end

    local maxPower = UnitPowerMax("player", powerType)
    if maxPower == nil then
        return false
    end

    -- 12.x can return secret-wrapped values that explode on numeric comparisons.
    -- If we cannot safely compare, treat the type as usable.
    if IsSecret(maxPower) then
        return true
    end

    local ok, hasPower = pcall(function()
        return maxPower > 0
    end)
    if not ok then
        return true
    end
    return hasPower and true or false
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
        return UnitCastingInfo("player") ~= nil or UnitChannelInfo("player") ~= nil
    end
    return true
end

--------------------------------------------------------------------------------
-- Power Type Detection
--------------------------------------------------------------------------------
local POWER_CONFIG = {
    ROGUE = {default = Enum.PowerType.ComboPoints},
    DRUID = {
        [2] = Enum.PowerType.ComboPoints,   -- Feral
        [4] = Enum.PowerType.ComboPoints,   -- Guardian (cat form)
        [1] = Enum.PowerType.LunarPower,    -- Balance
    },
    PALADIN = {
        [1] = Enum.PowerType.HolyPower,     -- Holy
        [2] = Enum.PowerType.HolyPower,     -- Protection
        [3] = Enum.PowerType.HolyPower,     -- Retribution
        default = Enum.PowerType.HolyPower,
    },
    MONK = {
        [3] = Enum.PowerType.Chi,           -- Windwalker
    },
    DEATHKNIGHT = {default = Enum.PowerType.Runes},
    WARLOCK = {default = Enum.PowerType.SoulShards},
    MAGE = {
        [1] = Enum.PowerType.ArcaneCharges, -- Arcane
    },
    DEMONHUNTER = {
        [1] = Enum.PowerType.Fury,          -- Havoc
        [2] = Enum.PowerType.Pain,          -- Vengeance
    },
    EVOKER = {default = Enum.PowerType.Essence},
    PRIEST = {
        [3] = Enum.PowerType.Insanity,      -- Shadow
    },
    SHAMAN = {
        [1] = Enum.PowerType.Maelstrom,     -- Elemental
        [2] = Enum.PowerType.Maelstrom,     -- Enhancement
    },
}

function ClassResource:DetectPowerType()
    local _, class = UnitClass("player")
    local spec = GetSpecialization()

    local classConfig = POWER_CONFIG[class]
    if not classConfig then
        currentPowerType = nil
        return
    end

    -- Try spec-specific power type first
    local powerType = classConfig[spec] or classConfig.default

    -- Verify power type is valid
    if IsPowerTypeUsable(powerType) then
        currentPowerType = powerType
        return
    end

    currentPowerType = nil
end

--------------------------------------------------------------------------------
-- Update Power Display
--------------------------------------------------------------------------------
function ClassResource:UpdatePower()
    if not classResourceFrame then return end

    if not currentPowerType then
        self:DetectPowerType()
        if not currentPowerType then
            classResourceFrame:Hide()
            AnchorFrame:Hide("classresource")
            return
        end
    end

    if not self:ShouldBeVisible() then
        classResourceFrame:Hide()
        AnchorFrame:Hide("classresource")
        return
    end

    local power = UnitPower("player", currentPowerType)
    local powerString
    if power == nil then
        powerString = "0"
    elseif IsSecret(power) then
        local ok, valueText = pcall(tostring, power)
        powerString = ok and valueText or "?"
    else
        local ok, valueText = pcall(tostring, power)
        powerString = ok and valueText or "0"
    end

    -- Only update if changed
    if powerString ~= lastPowerValue then
        lastPowerValue = powerString
        classResourceFrame.powerText:SetText(powerString)
    end

    -- Show if we have a valid power type
    if not classResourceFrame:IsShown() then
        classResourceFrame:Show()
        AnchorFrame:Show("classresource")
    end
end

--------------------------------------------------------------------------------
-- OnUpdate Handler (throttled)
--------------------------------------------------------------------------------
local function OnUpdate(self, elapsed)
    updateTimer = updateTimer + elapsed
    if updateTimer >= UPDATE_INTERVAL then
        updateTimer = 0
        ClassResource:UpdatePower()
    end
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------
function ClassResource:PLAYER_SPECIALIZATION_CHANGED()
    self:DetectPowerType()
    self:UpdatePower()
end

function ClassResource:PLAYER_ENTERING_WORLD()
    self:DetectPowerType()
    self:UpdatePower()
end

function ClassResource:UPDATE_SHAPESHIFT_FORM()
    -- Druid form changes may change power type
    self:DetectPowerType()
    self:UpdatePower()
end

function ClassResource:UNIT_POWER_UPDATE(event, unit, powerType)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassResource:UNIT_MAXPOWER(event, unit, powerType)
    if unit ~= "player" then return end
    self:DetectPowerType()
    self:UpdatePower()
end

function ClassResource:PLAYER_REGEN_DISABLED()
    self:UpdatePower()
end

function ClassResource:PLAYER_REGEN_ENABLED()
    self:UpdatePower()
end

function ClassResource:PLAYER_TARGET_CHANGED()
    self:UpdatePower()
end

function ClassResource:UNIT_SPELLCAST_START(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassResource:UNIT_SPELLCAST_STOP(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassResource:UNIT_SPELLCAST_INTERRUPTED(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassResource:UNIT_SPELLCAST_FAILED(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassResource:UNIT_SPELLCAST_FAILED_QUIET(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassResource:UNIT_SPELLCAST_CHANNEL_START(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassResource:UNIT_SPELLCAST_CHANNEL_STOP(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassResource:UNIT_SPELLCAST_CHANNEL_UPDATE(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

--------------------------------------------------------------------------------
-- ApplyOptions: Update visuals from settings
--------------------------------------------------------------------------------
function ClassResource:ApplyOptions()
    if not classResourceFrame then return end

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

    local powerText = classResourceFrame.powerText
    powerText:SetFont(font, fontSize, fontOutline)
    powerText:SetTextColor(r, g, b, a)
    powerText:ClearAllPoints()
    powerText:SetPoint("CENTER", classResourceFrame, "CENTER", offsetX, offsetY)
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------
function ClassResource:Initialize()
    local anchor = AnchorFrame:GetFrame()
    if not anchor then return end

    classResourceFrame = CreateFrame("Frame", nil, anchor)
    classResourceFrame:SetAllPoints()
    classResourceFrame:SetFrameStrata("HIGH")
    classResourceFrame:Hide()

    -- Create power text
    classResourceFrame.powerText = classResourceFrame:CreateFontString(nil, "OVERLAY")
    classResourceFrame.powerText:SetPoint("CENTER")

    -- Set OnUpdate for throttled updates
    classResourceFrame:SetScript("OnUpdate", OnUpdate)

    self:ApplyOptions()
    self:DetectPowerType()
end

--------------------------------------------------------------------------------
-- Enable/Disable
--------------------------------------------------------------------------------
local function EnableModule(enabled)
    if enabled then
        if not classResourceFrame then
            ClassResource:Initialize()
        end

        EL:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        EL:RegisterEvent("PLAYER_ENTERING_WORLD")
        EL:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        EL:RegisterEvent("PLAYER_REGEN_DISABLED")
        EL:RegisterEvent("PLAYER_REGEN_ENABLED")
        EL:RegisterEvent("PLAYER_TARGET_CHANGED")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
        EL:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        EL:RegisterUnitEvent("UNIT_MAXPOWER", "player")

        ClassResource:DetectPowerType()
        ClassResource:UpdatePower()
    else
        EL:UnregisterAllEvents()
        if classResourceFrame then
            classResourceFrame:Hide()
        end
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
local settingKeys = {
    "classresource_font", "classresource_fontSize", "classresource_fontOutline",
    "classresource_fontColor", "classresource_offsetX", "classresource_offsetY", "classresource_useClassColor"
}

for _, key in ipairs(settingKeys) do
    CallbackRegistry:RegisterSettingCallback(key, function()
        ClassResource:ApplyOptions()
    end)
end

CallbackRegistry:RegisterSettingCallback("classresource_visibility", function()
    ClassResource:UpdatePower()
end)

--------------------------------------------------------------------------------
-- Register Module
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
    name = L["Class Resource"] or "Class Resource",
    dbKey = "moduleEnabled_ClassResource",
    description = L["Class Resource Description"] or "Displays your class resource (combo points, holy power, etc.) as text",
    toggleFunc = EnableModule,
    categoryID = 1,
    uiOrder = 3,
})
