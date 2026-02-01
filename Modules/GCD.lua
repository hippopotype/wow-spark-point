-- SparkPoint GCD Module
-- Displays a ring around cursor during Global Cooldown

local addonName, addon = ...
local L = addon.L
local API = addon.API
local DonutWidget = addon.DonutWidget
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor
local GetDBColorTable = addon.GetDBColorTable

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------
local gcdFrame
local gcdDonut
local isActive = false
local gcdStartTime, gcdDuration

local GetTime = GetTime
local cos, sin, rad = math.cos, math.sin, math.rad

--------------------------------------------------------------------------------
-- GCD Spell Detection
-- Use class-specific spells to detect GCD
--------------------------------------------------------------------------------
local CLASS_SPELLS = {
    DRUID = 5185,        -- Healing Touch
    PALADIN = 635,       -- Holy Light
    PRIEST = 2050,       -- Heal
    SHAMAN = 331,        -- Healing Wave
    WARRIOR = 6673,      -- Battle Shout
    DEATHKNIGHT = 45902, -- Blood Strike
    HUNTER = 75,         -- Auto Shot (fallback)
    MAGE = 1459,         -- Arcane Intellect
    WARLOCK = 687,       -- Demon Skin
    ROGUE = 1752,        -- Sinister Strike
    MONK = 100780,       -- Jab
    DEMONHUNTER = 162243, -- Demon's Bite
    EVOKER = 361469,     -- Living Flame
}

local gcdSpellID

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")

--------------------------------------------------------------------------------
-- GCD Module Object
--------------------------------------------------------------------------------
local GCD = {}
addon.Modules.GCDObj = GCD

--------------------------------------------------------------------------------
-- OnUpdate Handler
--------------------------------------------------------------------------------
local function OnUpdate(self, elapsed)
    if not isActive or not gcdDuration or gcdDuration == 0 then
        GCD:Hide()
        return
    end

    local now = GetTime()
    local gcdPerc = (now - gcdStartTime) / gcdDuration

    if gcdPerc < 1 then
        local angle = gcdPerc * 360

        -- Update donut if not spark-only mode
        if not GetDBBool("gcd_sparkOnly") and gcdDonut then
            gcdDonut:SetAngle(angle)
        end

        -- Update spark position
        local sparkAngle = 360 - (-90 + angle)
        local radius = GetDBValue("gcd_radius")
        local x = cos(rad(sparkAngle)) * radius * 0.95
        local y = sin(rad(sparkAngle)) * radius * 0.95

        local spark = gcdFrame.sparkTexture
        spark:SetRotation(rad(sparkAngle + 90))
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", gcdFrame, "CENTER", x, y)
    else
        GCD:Hide()
    end
end

--------------------------------------------------------------------------------
-- Show/Hide
--------------------------------------------------------------------------------
function GCD:Show()
    if not gcdFrame then return end

    isActive = true
    AnchorFrame:Show("gcd")
    gcdFrame:Show()
    if gcdDonut then
        gcdDonut:SetAngle(0)
        gcdDonut:Show()
    end

    -- Notify Ring module to show
    if addon.Modules.RingObj and addon.Modules.RingObj.Show then
        addon.Modules.RingObj:Show("gcd")
    end
end

function GCD:Hide()
    if not gcdFrame then return end

    isActive = false
    if gcdDonut then
        gcdDonut:Hide()
    end
    gcdFrame:Hide()
    AnchorFrame:Hide("gcd")
    gcdStartTime = nil
    gcdDuration = nil

    -- Notify Ring module to hide
    if addon.Modules.RingObj and addon.Modules.RingObj.Hide then
        addon.Modules.RingObj:Hide("gcd")
    end
end

--------------------------------------------------------------------------------
-- Detect GCD Spell
--------------------------------------------------------------------------------
function GCD:DetectSpell()
    -- Try generic GCD spell first
    if C_Spell.DoesSpellExist(61304) then
        gcdSpellID = 61304
        return
    end

    -- Fallback to class-specific spell
    local class = API.GetPlayerClass()
    gcdSpellID = CLASS_SPELLS[class]
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------
function GCD:SPELLS_CHANGED()
    self:DetectSpell()
end

local function ResolveGCDSpellID(spellID)
    if gcdSpellID then
        return gcdSpellID
    end
    return spellID
end

function GCD:UNIT_SPELLCAST_START(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    local id = ResolveGCDSpellID(spellID)
    if not id then return end
    local start, duration = API.GetSpellCooldown(id)
    if GCD.CooldownActive(start, duration) and duration <= 1.5 then
        gcdStartTime = start
        gcdDuration = duration
        self:Show()
    end
end

function GCD:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID)
    self:UNIT_SPELLCAST_START(event, unit, castGUID, spellID)
end

function GCD.CooldownActive(start, duration)
    local ok, result = pcall(function()
        return start and duration and duration > 0 and start > 0
    end)
    if not ok then
        return true
    end
    return result
end

function GCD:ACTIONBAR_UPDATE_COOLDOWN()
    if not gcdSpellID then return end

    -- Don't show GCD if cast module is active
    if addon.Modules.CastObj and addon.Modules.CastObj.isCasting then
        return
    end

    local start, duration = API.GetSpellCooldown(gcdSpellID)
    if GCD.CooldownActive(start, duration) and duration <= 1.5 then
        gcdStartTime = start
        gcdDuration = duration
        self:Show()
    else
        if isActive then
            self:Hide()
        end
    end
end

--------------------------------------------------------------------------------
-- ApplyOptions: Update visuals from settings
--------------------------------------------------------------------------------
function GCD:ApplyOptions()
    if not gcdFrame then return end

    local radius = GetDBValue("gcd_radius")
    local thickness = GetDBValue("gcd_thickness")
    local sparkOnly = GetDBBool("gcd_sparkOnly")

    -- Update spark
    local r, g, b, a = GetDBColor("gcd_sparkColor")
    gcdFrame.sparkTexture:SetVertexColor(r, g, b, a)
    gcdFrame.sparkTexture:SetSize(radius, radius)

    -- Update or create donut
    if not sparkOnly then
        if not gcdDonut then
            gcdDonut = DonutWidget:Create({
                direction = true,
                radius = radius,
                thickness = thickness,
                barColor = GetDBColorTable("gcd_barColor"),
                backgroundColor = GetDBColorTable("gcd_backgroundColor"),
            })
            gcdDonut:AttachTo(gcdFrame)
        else
            gcdDonut:SetRadius(radius)
            gcdDonut:SetThickness(thickness)
            gcdDonut:SetBarColor(GetDBColorTable("gcd_barColor"))
            gcdDonut:SetBackgroundColor(GetDBColorTable("gcd_backgroundColor"))
        end
    end
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------
function GCD:Initialize()
    local anchor = AnchorFrame:GetFrame()
    if not anchor then return end

    gcdFrame = CreateFrame("Frame", nil, anchor)
    gcdFrame:SetAllPoints()
    gcdFrame:Hide()

    -- Create spark texture
    gcdFrame.sparkTexture = gcdFrame:CreateTexture(nil, "OVERLAY")
    gcdFrame.sparkTexture:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    gcdFrame.sparkTexture:SetBlendMode("ADD")
    gcdFrame.sparkTexture:SetSize(32, 32)

    -- Set OnUpdate
    gcdFrame:SetScript("OnUpdate", OnUpdate)

    -- Detect spell
    self:DetectSpell()

    self:ApplyOptions()
end

--------------------------------------------------------------------------------
-- Enable/Disable
--------------------------------------------------------------------------------
local function EnableModule(enabled)
    if enabled then
        if not gcdFrame then
            GCD:Initialize()
        end

        EL:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        EL:RegisterEvent("PLAYER_STARTED_MOVING")
        EL:RegisterEvent("PLAYER_STOPPED_MOVING")
        EL:RegisterEvent("SPELLS_CHANGED")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        EL:UnregisterAllEvents()
        GCD:Hide()
    end
end

function GCD:PLAYER_STARTED_MOVING()
    self:ACTIONBAR_UPDATE_COOLDOWN()
end

function GCD:PLAYER_STOPPED_MOVING()
    self:ACTIONBAR_UPDATE_COOLDOWN()
end

--------------------------------------------------------------------------------
-- Event Dispatcher
--------------------------------------------------------------------------------
EL:SetScript("OnEvent", function(self, event, ...)
    if GCD[event] then
        GCD[event](GCD, event, ...)
    end
end)

--------------------------------------------------------------------------------
-- Register Setting Callbacks
--------------------------------------------------------------------------------
local settingKeys = {
    "gcd_radius", "gcd_thickness", "gcd_barColor", "gcd_backgroundColor",
    "gcd_sparkColor", "gcd_sparkOnly"
}

for _, key in ipairs(settingKeys) do
    CallbackRegistry:RegisterSettingCallback(key, function()
        GCD:ApplyOptions()
    end)
end

--------------------------------------------------------------------------------
-- Register Module
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
    name = L["GCD Ring"] or "GCD Ring",
    dbKey = "moduleEnabled_GCD",
    description = L["GCD Ring Description"] or "Shows a progress ring during Global Cooldown after instant casts",
    toggleFunc = EnableModule,
    categoryID = 1,
    uiOrder = 2,
})
