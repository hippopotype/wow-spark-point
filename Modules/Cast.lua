-- SparkPoint Cast Module
-- Displays a ring around cursor during spell casting with latency indicator

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
local castFrame
local castDonut, latencyDonut
local isCasting = false
local castStartTime, castEndTime, castDuration
local castLatency = 0
local castSent = 0
local currentSpellName = ""

local GetTime = GetTime
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local cos, sin, rad = math.cos, math.sin, math.rad

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")

--------------------------------------------------------------------------------
-- Cast Module Object
--------------------------------------------------------------------------------
local Cast = {}
addon.Modules.CastObj = Cast

--------------------------------------------------------------------------------
-- OnUpdate Handler
--------------------------------------------------------------------------------
local function OnUpdate(self, elapsed)
    if not isCasting or castDuration == 0 then
        Cast:Hide()
        return
    end

    local now = GetTime() * 1000
    local castPerc = (now - castStartTime) / castDuration

    if castPerc < 1 then
        local angle = castPerc * 360

        -- Reverse for channeled spells if enabled
        if GetDBBool("cast_reverseChanneling") and UnitChannelInfo("player") then
            angle = (1 - castPerc) * 360
        end

        -- Update donut if not spark-only mode
        if not GetDBBool("cast_sparkOnly") and castDonut then
            castDonut:SetAngle(angle)
        end

        -- Update spark position (rotates around ring)
        local sparkAngle = 360 - (-90 + angle)
        local radius = GetDBValue("cast_radius")
        local x = cos(rad(sparkAngle)) * radius * 0.95
        local y = sin(rad(sparkAngle)) * radius * 0.95

        local spark = castFrame.sparkTexture
        spark:SetRotation(rad(sparkAngle + 90))
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", castFrame, "CENTER", x, y)

        -- Latency coloring in final portion (spark-only mode)
        if GetDBBool("cast_sparkOnly") and castPerc > 1 - castLatency then
            local r, g, b, a = GetDBColor("cast_latencyColor")
            spark:SetVertexColor(r, g, b, a)
        else
            local r, g, b, a = GetDBColor("cast_sparkColor")
            spark:SetVertexColor(r, g, b, a)
        end
    else
        Cast:Hide()
    end
end

--------------------------------------------------------------------------------
-- Show/Hide
--------------------------------------------------------------------------------
function Cast:Show()
    if not castFrame then return end

    isCasting = true
    AnchorFrame:Show("cast")
    castFrame:Show()

    -- Show latency indicator
    if not GetDBBool("cast_sparkOnly") and latencyDonut then
        local latencyAngle = math.max(0.1, castLatency * 360)
        latencyDonut:SetAngle(latencyAngle)
        if castDonut then
            castDonut:SetAngle(0)
        end
        latencyDonut:Show()
        if castDonut then
            castDonut:Show()
        end
    end

    -- Show spell text if enabled
    if GetDBBool("cast_spellTextEnabled") and castFrame.spellText then
        castFrame.spellText:SetText(currentSpellName)
        castFrame.spellText:Show()
    elseif castFrame.spellText then
        castFrame.spellText:Hide()
    end

    -- Notify Ring module to show
    if addon.Modules.RingObj and addon.Modules.RingObj.Show then
        addon.Modules.RingObj:Show("cast")
    end

    -- Notify SpellIcon module
    if addon.Modules.SpellIconObj and addon.Modules.SpellIconObj.OnCastStart then
        addon.Modules.SpellIconObj:OnCastStart(currentSpellName)
    end
end

function Cast:Hide()
    if not castFrame then return end

    isCasting = false
    if castDonut then
        castDonut:Hide()
    end
    if latencyDonut then
        latencyDonut:Hide()
    end
    castDuration = 0
    castStartTime = 0
    castEndTime = 0
    castFrame:Hide()
    AnchorFrame:Hide("cast")

    -- Notify Ring module to hide
    if addon.Modules.RingObj and addon.Modules.RingObj.Hide then
        addon.Modules.RingObj:Hide("cast")
    end

    -- Notify SpellIcon module
    if addon.Modules.SpellIconObj and addon.Modules.SpellIconObj.OnCastEnd then
        addon.Modules.SpellIconObj:OnCastEnd()
    end
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------
function Cast:UNIT_SPELLCAST_SENT(event, unit, target, castGUID, spellID)
    if unit ~= "player" then return end
    castSent = GetTime() * 1000
end

function Cast:UNIT_SPELLCAST_START(event, unit, castGUID, spellID)
    if unit ~= "player" then return end

    local name, text, texture, startTimeMS, endTimeMS = UnitCastingInfo("player")
    if not name then return end

    castStartTime = startTimeMS
    castEndTime = endTimeMS
    castDuration = castEndTime - castStartTime
    currentSpellName = text or name

    -- Calculate latency
    local sendLag = (castSent > 0) and (GetTime() * 1000 - castSent) or 0
    sendLag = math.min(sendLag, castDuration)
    castLatency = (castDuration > 0) and (sendLag / castDuration) or 0

    self:Show()
end

function Cast:UNIT_SPELLCAST_STOP(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    self:Hide()
end

function Cast:UNIT_SPELLCAST_INTERRUPTED(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    self:Hide()
end

function Cast:UNIT_SPELLCAST_FAILED(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    self:Hide()
end

function Cast:UNIT_SPELLCAST_FAILED_QUIET(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    self:Hide()
end

function Cast:UNIT_SPELLCAST_DELAYED(event, unit, castGUID, spellID)
    if unit ~= "player" then return end

    local name, text, texture, startTimeMS, endTimeMS = UnitCastingInfo("player")
    if name then
        castStartTime = startTimeMS
        castEndTime = endTimeMS
        castDuration = castEndTime - castStartTime
    end
end

function Cast:UNIT_SPELLCAST_CHANNEL_START(event, unit, castGUID, spellID)
    if unit ~= "player" then return end

    local name, text, texture, startTimeMS, endTimeMS = UnitChannelInfo("player")
    if not name then return end

    castStartTime = startTimeMS
    castEndTime = endTimeMS
    castDuration = castEndTime - castStartTime
    currentSpellName = text or name

    -- Calculate latency
    local sendLag = (castSent > 0) and (GetTime() * 1000 - castSent) or 0
    sendLag = math.min(sendLag, castDuration)
    castLatency = (castDuration > 0) and (sendLag / castDuration) or 0

    self:Show()
end

function Cast:UNIT_SPELLCAST_CHANNEL_STOP(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    self:Hide()
end

function Cast:UNIT_SPELLCAST_CHANNEL_UPDATE(event, unit, castGUID, spellID)
    if unit ~= "player" then return end

    local name, text, texture, startTimeMS, endTimeMS = UnitChannelInfo("player")
    if name then
        castStartTime = startTimeMS
        castEndTime = endTimeMS
        castDuration = castEndTime - castStartTime
    end
end

-- Evoker Empower support
function Cast:UNIT_SPELLCAST_EMPOWER_START(event, unit, castGUID, spellID)
    self:UNIT_SPELLCAST_START(event, unit, castGUID, spellID)
end

function Cast:UNIT_SPELLCAST_EMPOWER_STOP(event, unit, castGUID, spellID)
    self:UNIT_SPELLCAST_STOP(event, unit, castGUID, spellID)
end

function Cast:UNIT_SPELLCAST_EMPOWER_UPDATE(event, unit, castGUID, spellID)
    self:UNIT_SPELLCAST_DELAYED(event, unit, castGUID, spellID)
end

--------------------------------------------------------------------------------
-- ApplyOptions: Update visuals from settings
--------------------------------------------------------------------------------
function Cast:ApplyOptions()
    if not castFrame then return end

    local radius = GetDBValue("cast_radius")
    local thickness = GetDBValue("cast_thickness")
    local sparkOnly = GetDBBool("cast_sparkOnly")

    -- Update spark
    local r, g, b, a = GetDBColor("cast_sparkColor")
    castFrame.sparkTexture:SetVertexColor(r, g, b, a)
    castFrame.sparkTexture:SetSize(radius, radius)

    -- Rebuild donuts if needed
    if not sparkOnly then
        if not castDonut then
            -- Create latency donut (background layer)
            latencyDonut = DonutWidget:Create({
                direction = false,
                radius = radius,
                thickness = thickness,
                barColor = GetDBColorTable("cast_latencyColor"),
                backgroundColor = GetDBColorTable("cast_backgroundColor"),
            })
            latencyDonut:AttachTo(castFrame)

            -- Create cast donut (foreground layer)
            castDonut = DonutWidget:Create({
                direction = true,
                radius = radius,
                thickness = thickness,
                barColor = GetDBColorTable("cast_barColor"),
                backgroundColor = {r = 0, g = 0, b = 0, a = 0},  -- Transparent bg
                parent = latencyDonut:GetFrame(),
            })
            castDonut:AttachTo(castFrame)
        else
            -- Update existing donuts
            castDonut:SetRadius(radius)
            castDonut:SetThickness(thickness)
            castDonut:SetBarColor(GetDBColorTable("cast_barColor"))

            latencyDonut:SetRadius(radius)
            latencyDonut:SetThickness(thickness)
            latencyDonut:SetBarColor(GetDBColorTable("cast_latencyColor"))
            latencyDonut:SetBackgroundColor(GetDBColorTable("cast_backgroundColor"))
        end
    end

    -- Update spell text
    if castFrame.spellText then
        local font = GetDBValue("cast_spellTextFont")
        local size = GetDBValue("cast_spellTextSize")
        local outline = GetDBValue("cast_spellTextOutline")

        castFrame.spellText:SetFont(font, size, outline)

        local tr, tg, tb, ta = GetDBColor("cast_spellTextColor")
        castFrame.spellText:SetTextColor(tr, tg, tb, ta)

        local offsetX = GetDBValue("cast_spellTextOffsetX")
        local offsetY = GetDBValue("cast_spellTextOffsetY")
        castFrame.spellText:ClearAllPoints()
        castFrame.spellText:SetPoint("BOTTOM", castFrame, "CENTER", offsetX, radius + 5 + offsetY)
    end
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------
function Cast:Initialize()
    local anchor = AnchorFrame:GetFrame()
    if not anchor then return end

    castFrame = CreateFrame("Frame", nil, anchor)
    castFrame:SetAllPoints()
    castFrame:Hide()

    -- Create spark texture
    castFrame.sparkTexture = castFrame:CreateTexture(nil, "OVERLAY")
    castFrame.sparkTexture:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    castFrame.sparkTexture:SetBlendMode("ADD")
    castFrame.sparkTexture:SetSize(32, 32)

    -- Create spell text
    castFrame.spellText = castFrame:CreateFontString(nil, "OVERLAY")
    castFrame.spellText:Hide()

    -- Set OnUpdate
    castFrame:SetScript("OnUpdate", OnUpdate)

    self:ApplyOptions()
end

--------------------------------------------------------------------------------
-- Enable/Disable
--------------------------------------------------------------------------------
local function EnableModule(enabled)
    if enabled then
        -- Initialize if needed
        if not castFrame then
            Cast:Initialize()
        end

        -- Register events
        EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
        EL:RegisterEvent("UNIT_SPELLCAST_SENT")

        -- Evoker Empower events
        EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
        EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")

        -- Hide Blizzard cast bar if requested
        if GetDBBool("cast_hideCastBar") then
            if PlayerCastingBarFrame then
                PlayerCastingBarFrame:UnregisterAllEvents()
                PlayerCastingBarFrame:Hide()
            end
        end
    else
        EL:UnregisterAllEvents()
        Cast:Hide()
    end
end

--------------------------------------------------------------------------------
-- Event Dispatcher
--------------------------------------------------------------------------------
EL:SetScript("OnEvent", function(self, event, ...)
    if Cast[event] then
        Cast[event](Cast, event, ...)
    end
end)

--------------------------------------------------------------------------------
-- Register Setting Callbacks
--------------------------------------------------------------------------------
local settingKeys = {
    "cast_radius", "cast_thickness", "cast_barColor", "cast_backgroundColor",
    "cast_sparkColor", "cast_latencyColor", "cast_sparkOnly",
    "cast_spellTextEnabled", "cast_spellTextFont", "cast_spellTextSize",
    "cast_spellTextOutline", "cast_spellTextColor",
    "cast_spellTextOffsetX", "cast_spellTextOffsetY"
}

for _, key in ipairs(settingKeys) do
    CallbackRegistry:RegisterSettingCallback(key, function()
        Cast:ApplyOptions()
    end)
end

-- Special handling for hideCastBar
CallbackRegistry:RegisterSettingCallback("cast_hideCastBar", function(value)
    if value then
        if PlayerCastingBarFrame then
            PlayerCastingBarFrame:UnregisterAllEvents()
            PlayerCastingBarFrame:Hide()
        end
    else
        if PlayerCastingBarFrame then
            PlayerCastingBarFrame:OnLoad(PlayerCastingBarFrame)
        end
    end
end)

--------------------------------------------------------------------------------
-- Register Module
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
    name = L["Cast Ring"] or "Cast Ring",
    dbKey = "moduleEnabled_Cast",
    description = L["Cast Ring Description"] or "Shows a progress ring around your cursor during spell casts",
    toggleFunc = EnableModule,
    categoryID = 1,
    uiOrder = 1,
})
