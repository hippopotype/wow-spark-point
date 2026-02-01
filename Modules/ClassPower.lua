-- SparkPoint ClassPower Module
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
local classPowerFrame
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

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")

--------------------------------------------------------------------------------
-- ClassPower Module Object
--------------------------------------------------------------------------------
local ClassPower = {}
addon.Modules.ClassPowerObj = ClassPower

local VISIBILITY_OPTIONS = {
    ALWAYS = "ALWAYS",
    IN_COMBAT = "IN_COMBAT",
    OUT_OF_COMBAT = "OUT_OF_COMBAT",
    HAS_TARGET = "HAS_TARGET",
    CASTING = "CASTING",
}

function ClassPower:ShouldBeVisible()
    local setting = GetDBValue("classpower_visibility") or VISIBILITY_OPTIONS.ALWAYS
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
        [3] = Enum.PowerType.HolyPower,     -- Retribution
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

function ClassPower:DetectPowerType()
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
    if powerType then
        local maxPower = UnitPowerMax("player", powerType)
        if maxPower and maxPower > 0 then
            currentPowerType = powerType
            return
        end
    end

    currentPowerType = nil
end

--------------------------------------------------------------------------------
-- Update Power Display
--------------------------------------------------------------------------------
function ClassPower:UpdatePower()
    if not classPowerFrame then return end

    if not currentPowerType then
        classPowerFrame:Hide()
        AnchorFrame:Hide("classpower")
        return
    end

    if not self:ShouldBeVisible() then
        classPowerFrame:Hide()
        AnchorFrame:Hide("classpower")
        return
    end

    local power = UnitPower("player", currentPowerType)
    -- Convert to string to handle WoW "secret values"
    local powerString = tostring(power or 0)

    -- Only update if changed
    if powerString ~= lastPowerValue then
        lastPowerValue = powerString
        classPowerFrame.powerText:SetText(powerString)
    end

    -- Show if we have a valid power type
    if not classPowerFrame:IsShown() then
        classPowerFrame:Show()
        AnchorFrame:Show("classpower")
    end
end

--------------------------------------------------------------------------------
-- OnUpdate Handler (throttled)
--------------------------------------------------------------------------------
local function OnUpdate(self, elapsed)
    updateTimer = updateTimer + elapsed
    if updateTimer >= UPDATE_INTERVAL then
        updateTimer = 0
        ClassPower:UpdatePower()
    end
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------
function ClassPower:PLAYER_SPECIALIZATION_CHANGED()
    self:DetectPowerType()
    self:UpdatePower()
end

function ClassPower:PLAYER_ENTERING_WORLD()
    self:DetectPowerType()
    self:UpdatePower()
end

function ClassPower:UPDATE_SHAPESHIFT_FORM()
    -- Druid form changes may change power type
    self:DetectPowerType()
    self:UpdatePower()
end

function ClassPower:UNIT_POWER_UPDATE(event, unit, powerType)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassPower:UNIT_MAXPOWER(event, unit, powerType)
    if unit ~= "player" then return end
    self:DetectPowerType()
    self:UpdatePower()
end

function ClassPower:PLAYER_REGEN_DISABLED()
    self:UpdatePower()
end

function ClassPower:PLAYER_REGEN_ENABLED()
    self:UpdatePower()
end

function ClassPower:PLAYER_TARGET_CHANGED()
    self:UpdatePower()
end

function ClassPower:UNIT_SPELLCAST_START(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassPower:UNIT_SPELLCAST_STOP(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassPower:UNIT_SPELLCAST_INTERRUPTED(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassPower:UNIT_SPELLCAST_FAILED(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassPower:UNIT_SPELLCAST_FAILED_QUIET(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassPower:UNIT_SPELLCAST_CHANNEL_START(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassPower:UNIT_SPELLCAST_CHANNEL_STOP(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

function ClassPower:UNIT_SPELLCAST_CHANNEL_UPDATE(event, unit)
    if unit ~= "player" then return end
    self:UpdatePower()
end

--------------------------------------------------------------------------------
-- ApplyOptions: Update visuals from settings
--------------------------------------------------------------------------------
function ClassPower:ApplyOptions()
    if not classPowerFrame then return end

    local font = GetDBValue("classpower_font")
    local fontSize = GetDBValue("classpower_fontSize")
    local fontOutline = GetDBValue("classpower_fontOutline")
    local r, g, b, a
    if GetDBBool("classpower_useClassColor") then
        r, g, b, a = API.GetPlayerClassColor()
    else
        r, g, b, a = GetDBColor("classpower_fontColor")
    end
    local offsetX = GetDBValue("classpower_offsetX")
    local offsetY = GetDBValue("classpower_offsetY")

    local powerText = classPowerFrame.powerText
    powerText:SetFont(font, fontSize, fontOutline)
    powerText:SetTextColor(r, g, b, a)
    powerText:ClearAllPoints()
    powerText:SetPoint("CENTER", classPowerFrame, "CENTER", offsetX, offsetY)
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------
function ClassPower:Initialize()
    local anchor = AnchorFrame:GetFrame()
    if not anchor then return end

    classPowerFrame = CreateFrame("Frame", nil, anchor)
    classPowerFrame:SetAllPoints()
    classPowerFrame:SetFrameStrata("HIGH")
    classPowerFrame:Hide()

    -- Create power text
    classPowerFrame.powerText = classPowerFrame:CreateFontString(nil, "OVERLAY")
    classPowerFrame.powerText:SetPoint("CENTER")

    -- Set OnUpdate for throttled updates
    classPowerFrame:SetScript("OnUpdate", OnUpdate)

    self:ApplyOptions()
    self:DetectPowerType()
end

--------------------------------------------------------------------------------
-- Enable/Disable
--------------------------------------------------------------------------------
local function EnableModule(enabled)
    if enabled then
        if not classPowerFrame then
            ClassPower:Initialize()
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

        ClassPower:DetectPowerType()
        ClassPower:UpdatePower()
    else
        EL:UnregisterAllEvents()
        if classPowerFrame then
            classPowerFrame:Hide()
        end
        AnchorFrame:Hide("classpower")
    end
end

--------------------------------------------------------------------------------
-- Event Dispatcher
--------------------------------------------------------------------------------
EL:SetScript("OnEvent", function(self, event, ...)
    if ClassPower[event] then
        ClassPower[event](ClassPower, event, ...)
    end
end)

--------------------------------------------------------------------------------
-- Register Setting Callbacks
--------------------------------------------------------------------------------
local settingKeys = {
    "classpower_font", "classpower_fontSize", "classpower_fontOutline",
    "classpower_fontColor", "classpower_offsetX", "classpower_offsetY", "classpower_useClassColor"
}

for _, key in ipairs(settingKeys) do
    CallbackRegistry:RegisterSettingCallback(key, function()
        ClassPower:ApplyOptions()
    end)
end

CallbackRegistry:RegisterSettingCallback("classpower_visibility", function()
    ClassPower:UpdatePower()
end)

--------------------------------------------------------------------------------
-- Register Module
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
    name = L["Class Power"] or "Class Power",
    dbKey = "moduleEnabled_ClassPower",
    description = L["Class Power Description"] or "Displays your class resource (combo points, holy power, etc.) as text",
    toggleFunc = EnableModule,
    categoryID = 1,
    uiOrder = 3,
})
