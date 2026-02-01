-- SparkPoint SpellIcon Module
-- Displays the current casting spell icon near the cursor

local addonName, addon = ...
local L = addon.L
local API = addon.API
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------
local iconFrame
local currentSpellID
local isActive = false

local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")

--------------------------------------------------------------------------------
-- SpellIcon Module Object
--------------------------------------------------------------------------------
local SpellIcon = {}
addon.Modules.SpellIconObj = SpellIcon

--------------------------------------------------------------------------------
-- Update Icon
--------------------------------------------------------------------------------
function SpellIcon:UpdateIcon(spellID)
    if not iconFrame then return end

    if spellID then
        local texture = API.GetSpellTexture(spellID)
        if texture then
            iconFrame.icon:SetTexture(texture)
            iconFrame:Show()
            AnchorFrame:Show("spellicon")
            isActive = true
            currentSpellID = spellID
            return
        end
    end

    -- No valid spell, hide
    iconFrame:Hide()
    AnchorFrame:Hide("spellicon")
    isActive = false
    currentSpellID = nil
end

--------------------------------------------------------------------------------
-- Cast Start/End Callbacks (called by Cast module)
--------------------------------------------------------------------------------
function SpellIcon:OnCastStart(spellName)
    -- Get current casting info to find spell ID
    local name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo("player")
    if not name then
        name, text, texture, startTime, endTime, isTradeSkill, notInterruptible, spellID = UnitChannelInfo("player")
    end

    if spellID then
        self:UpdateIcon(spellID)
    elseif texture then
        -- Fallback: use texture directly if no spellID
        if iconFrame then
            iconFrame.icon:SetTexture(texture)
            iconFrame:Show()
            AnchorFrame:Show("spellicon")
            isActive = true
        end
    end
end

function SpellIcon:OnCastEnd()
    self:UpdateIcon(nil)
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------
function SpellIcon:UNIT_SPELLCAST_START(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    self:UpdateIcon(spellID)
end

function SpellIcon:UNIT_SPELLCAST_STOP(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    self:UpdateIcon(nil)
end

function SpellIcon:UNIT_SPELLCAST_CHANNEL_START(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    self:UpdateIcon(spellID)
end

function SpellIcon:UNIT_SPELLCAST_CHANNEL_STOP(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    self:UpdateIcon(nil)
end

function SpellIcon:UNIT_SPELLCAST_INTERRUPTED(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    self:UpdateIcon(nil)
end

-- Evoker Empower
function SpellIcon:UNIT_SPELLCAST_EMPOWER_START(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    self:UpdateIcon(spellID)
end

function SpellIcon:UNIT_SPELLCAST_EMPOWER_STOP(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    self:UpdateIcon(nil)
end

--------------------------------------------------------------------------------
-- ApplyOptions: Update visuals from settings
--------------------------------------------------------------------------------
function SpellIcon:ApplyOptions()
    if not iconFrame then return end

    local size = GetDBValue("spellicon_size")
    local offsetX = GetDBValue("spellicon_offsetX")
    local offsetY = GetDBValue("spellicon_offsetY")

    iconFrame:SetSize(size, size)
    iconFrame:ClearAllPoints()
    iconFrame:SetPoint("CENTER", AnchorFrame:GetFrame(), "CENTER", offsetX, offsetY)

    iconFrame.icon:SetSize(size - 4, size - 4)
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------
function SpellIcon:Initialize()
    local anchor = AnchorFrame:GetFrame()
    if not anchor then return end

    iconFrame = CreateFrame("Frame", nil, anchor)
    iconFrame:SetSize(32, 32)
    iconFrame:SetPoint("CENTER", anchor, "CENTER", 0, -40)
    iconFrame:Hide()

    -- Create border
    iconFrame.border = iconFrame:CreateTexture(nil, "OVERLAY")
    iconFrame.border:SetAllPoints()
    iconFrame.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    iconFrame.border:SetTexCoord(0.2, 0.8, 0.2, 0.8)

    -- Create icon texture
    iconFrame.icon = iconFrame:CreateTexture(nil, "ARTWORK")
    iconFrame.icon:SetPoint("CENTER")
    iconFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Slight inset to hide edges

    -- Optional: Create cooldown overlay
    if GetDBBool("spellicon_showCooldown") then
        iconFrame.cooldown = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
        iconFrame.cooldown:SetAllPoints(iconFrame.icon)
        iconFrame.cooldown:SetDrawEdge(false)
        iconFrame.cooldown:SetHideCountdownNumbers(true)
    end

    self:ApplyOptions()
end

--------------------------------------------------------------------------------
-- Enable/Disable
--------------------------------------------------------------------------------
local function EnableModule(enabled)
    if enabled then
        if not iconFrame then
            SpellIcon:Initialize()
        end

        EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
    else
        EL:UnregisterAllEvents()
        SpellIcon:UpdateIcon(nil)
    end
end

--------------------------------------------------------------------------------
-- Event Dispatcher
--------------------------------------------------------------------------------
EL:SetScript("OnEvent", function(self, event, ...)
    if SpellIcon[event] then
        SpellIcon[event](SpellIcon, event, ...)
    end
end)

--------------------------------------------------------------------------------
-- Register Setting Callbacks
--------------------------------------------------------------------------------
local settingKeys = {
    "spellicon_size", "spellicon_offsetX", "spellicon_offsetY", "spellicon_showCooldown"
}

for _, key in ipairs(settingKeys) do
    CallbackRegistry:RegisterSettingCallback(key, function()
        SpellIcon:ApplyOptions()
    end)
end

--------------------------------------------------------------------------------
-- Register Module
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
    name = L["Spell Icon"] or "Spell Icon",
    dbKey = "moduleEnabled_SpellIcon",
    description = L["Spell Icon Description"] or "Displays the icon of the spell being cast near the cursor",
    toggleFunc = EnableModule,
    categoryID = 1,
    uiOrder = 5,
})
