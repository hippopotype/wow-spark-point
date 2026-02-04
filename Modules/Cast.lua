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

local Masque
local masqueGroup
local masqueLoader
local Cast

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
local currentSpellID
local currentSpellTexture
local spellIconEnabled = false
local pendingVisuals = false

local GetTime = GetTime
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local cos, sin, rad = math.cos, math.sin, math.rad

local function GetMasqueGroup()
    if not Masque and LibStub then
        Masque = LibStub("Masque", true)
    end
    if not Masque then return nil end
    if not masqueGroup then
        masqueGroup = Masque:Group(addonName, L["Spell Icon"] or "Spell Icon", "SpellIcon")
    end
    return masqueGroup
end

local function EnsureMasqueLoader()
    if masqueLoader then return end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(_, event, name)
        if event == "ADDON_LOADED" and name == "Masque" then
            if Cast and Cast.RegisterMasqueButtons then
                Cast:RegisterMasqueButtons()
                Cast:ReskinMasque()
            end
        end
    end)
    masqueLoader = frame
end

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")

--------------------------------------------------------------------------------
-- Cast Module Object
--------------------------------------------------------------------------------
Cast = {}
addon.Modules.CastObj = Cast

function Cast:GetFrame()
    return castFrame
end

function Cast:RegisterMasqueButtons()
    local group = GetMasqueGroup()
    if not group or not castFrame or not castFrame.iconFrame then return end
    local iconFrame = castFrame.iconFrame
    if iconFrame._sparkMasqueAdded then return end

    local regions = {
        Icon = iconFrame.icon,
        Cooldown = iconFrame.cooldown,
        Normal = iconFrame.border,
    }

    group:AddButton(iconFrame, regions, "Action", true)
    iconFrame._sparkMasqueAdded = true
end

function Cast:ReskinMasque()
    local group = GetMasqueGroup()
    if group and group.ReSkin then
        group:ReSkin()
    end
end

function Cast:SetSpellIconEnabled(enabled)
    spellIconEnabled = enabled == true
    if castFrame and castFrame.iconFrame then
        if spellIconEnabled and isCasting then
            castFrame.iconFrame:Show()
        else
            castFrame.iconFrame:Hide()
        end
    end
end

function Cast:ApplyPendingVisuals()
    if not pendingVisuals then return end

    if GetDBBool("cast_spellTextEnabled") and castFrame.spellText then
        castFrame.spellText:SetText(currentSpellName)
        castFrame.spellText:Show()
    elseif castFrame.spellText then
        castFrame.spellText:Hide()
    end

    self:UpdateSpellIcon()
    pendingVisuals = false
end

function Cast:ApplyIconOptions()
    if not castFrame or not castFrame.iconFrame then return end

    local size = GetDBValue("spellicon_size")
    local offsetX = GetDBValue("spellicon_offsetX")
    local offsetY = GetDBValue("spellicon_offsetY")
    local showCooldown = GetDBBool("spellicon_castProgressSwipe")
    local useClassColor = GetDBBool("spellicon_useClassColor")

    castFrame.iconFrame:SetSize(size, size)
    castFrame.iconFrame:ClearAllPoints()
    castFrame.iconFrame:SetPoint("CENTER", castFrame, "CENTER", offsetX, offsetY)

    castFrame.iconFrame.icon:SetSize(size - 4, size - 4)
    if castFrame.iconFrame.border then
        if useClassColor then
            local r, g, b, a = API.GetPlayerClassColor()
            castFrame.iconFrame.border:SetVertexColor(r, g, b, a)
        else
            castFrame.iconFrame.border:SetVertexColor(1, 1, 1, 1)
        end
    end

    if showCooldown then
        if not castFrame.iconFrame.cooldown then
            castFrame.iconFrame.cooldown = CreateFrame("Cooldown", nil, castFrame.iconFrame, "CooldownFrameTemplate")
            castFrame.iconFrame.cooldown:SetAllPoints(castFrame.iconFrame.icon)
            castFrame.iconFrame.cooldown:SetDrawEdge(false)
            castFrame.iconFrame.cooldown:SetHideCountdownNumbers(true)
        end
        castFrame.iconFrame.cooldown:Show()
    elseif castFrame.iconFrame.cooldown then
        castFrame.iconFrame.cooldown:Hide()
    end

    self:UpdateIconCooldown()
    self:ReskinMasque()
end

function Cast:UpdateSpellIcon()
    if not castFrame or not castFrame.iconFrame then return end
    if not spellIconEnabled and addon.GetDBBool("moduleEnabled_SpellIcon") then
        spellIconEnabled = true
    end
    if not spellIconEnabled then
        castFrame.iconFrame:Hide()
        return
    end
    if not currentSpellTexture and currentSpellID and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(currentSpellID)
        currentSpellTexture = info and info.iconID or currentSpellTexture
    end
    if not currentSpellTexture then
        castFrame.iconFrame:Hide()
        return
    end
    local texture = currentSpellTexture
    if type(texture) ~= "number" and type(texture) ~= "string" then
        texture = 134400 -- Interface\\Icons\\INV_Misc_QuestionMark
    end
    castFrame.iconFrame.icon:SetTexture(texture)
    castFrame.iconFrame.icon:Show()
    castFrame.iconFrame:Show()
    self:UpdateIconCooldown()
end

function Cast:UpdateIconCooldown()
    if not castFrame or not castFrame.iconFrame or not castFrame.iconFrame.cooldown then return end
    if not GetDBBool("spellicon_castProgressSwipe") then
        castFrame.iconFrame.cooldown:Hide()
        return
    end
    if not isCasting or not castStartTime or castDuration == 0 then
        castFrame.iconFrame.cooldown:Hide()
        return
    end
    castFrame.iconFrame.cooldown:SetCooldown(castStartTime / 1000, castDuration / 1000)
    castFrame.iconFrame.cooldown:Show()
end

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
    local useClassColor = GetDBBool("cast_useClassColor")
    local cr, cg, cb, ca
    if useClassColor then
        cr, cg, cb, ca = API.GetPlayerClassColor()
    end

    if castPerc < 1 then
        local angle = castPerc * 360

        -- Reverse for channeled spells if enabled
        if GetDBBool("cast_reverseChanneling") and UnitChannelInfo("player") then
            angle = (1 - castPerc) * 360
        end

        -- Update donuts if not spark-only mode
        if not GetDBBool("cast_sparkOnly") then
            if castDonut then
                castDonut:SetAngle(angle)
            end
            -- Keep latency arc static (Cooldown swipe animates otherwise)
            if latencyDonut then
                local latencyAngle = math.max(0.1, castLatency * 360)
                latencyDonut:SetAngle(latencyAngle)
            end
        end

        -- Update spark position (rotates around ring)
        local sparkAngle = 360 - (-90 + angle)
        local radius = GetDBValue("cast_radius")
        -- Align spark to the centerline of the 20px ring texture (texture radius = 128px)
        local texThickness = 20
        local texRadius = 38
        local ringHalf = radius * (texThickness / texRadius) * 0.5
        local sparkRadius = math.max(0, radius - ringHalf)
        local x = cos(rad(sparkAngle)) * sparkRadius
        local y = sin(rad(sparkAngle)) * sparkRadius

        local spark = castFrame.sparkTexture
        spark:SetRotation(rad(sparkAngle + 90))
        spark:ClearAllPoints()
        spark:SetPoint("CENTER", castFrame, "CENTER", x, y)

        -- Latency coloring in final portion (spark-only mode)
        if GetDBBool("cast_sparkOnly") and castPerc > 1 - castLatency then
            local r, g, b, a = GetDBColor("cast_latencyColor")
            spark:SetVertexColor(r, g, b, a)
        else
            local r, g, b, a
            if useClassColor then
                r, g, b, a = cr, cg, cb, ca
            else
                r, g, b, a = GetDBColor("cast_sparkColor")
            end
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
            castDonut:SetOverlayShown(true)
        end
    end
    if castFrame.frameTexture and not GetDBBool("cast_sparkOnly") then
        castFrame.frameTexture:Show()
    end

    pendingVisuals = true
    self:ApplyPendingVisuals()
    self:UpdateIconCooldown()

    -- Notify Ring module to show
    if addon.Modules.RingObj and addon.Modules.RingObj.Show then
        addon.Modules.RingObj:Show("cast")
    end

    castFrame:Show()
end

function Cast:Hide()
    if not castFrame then return end

    isCasting = false
    pendingVisuals = false
    if castDonut then
        castDonut:Hide()
        castDonut:SetOverlayShown(false)
    end
    if latencyDonut then
        latencyDonut:Hide()
    end
    if castFrame.frameTexture then
        castFrame.frameTexture:Hide()
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

    if castFrame.iconFrame then
        castFrame.iconFrame:Hide()
        if castFrame.iconFrame.cooldown then
            castFrame.iconFrame.cooldown:Hide()
        end
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
    currentSpellID = spellID
    currentSpellTexture = texture
    if spellID and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        currentSpellName = (info and info.name) or text or name
        currentSpellTexture = (info and info.iconID) or currentSpellTexture
    else
        currentSpellName = text or name
    end

    -- Calculate latency
    local sendLag = (castSent > 0) and (GetTime() * 1000 - castSent) or 0
    if sendLag <= 0 and GetNetStats then
        local _, _, home, world = GetNetStats()
        sendLag = math.max(home or 0, world or 0)
    end
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
        self:UpdateIconCooldown()
    end
end

function Cast:UNIT_SPELLCAST_CHANNEL_START(event, unit, castGUID, spellID)
    if unit ~= "player" then return end

    local name, text, texture, startTimeMS, endTimeMS = UnitChannelInfo("player")
    if not name then return end

    castStartTime = startTimeMS
    castEndTime = endTimeMS
    castDuration = castEndTime - castStartTime
    currentSpellID = spellID
    currentSpellTexture = texture
    if spellID and C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        currentSpellName = (info and info.name) or text or name
        currentSpellTexture = (info and info.iconID) or currentSpellTexture
    else
        currentSpellName = text or name
    end

    -- Calculate latency
    local sendLag = (castSent > 0) and (GetTime() * 1000 - castSent) or 0
    if sendLag <= 0 and GetNetStats then
        local _, _, home, world = GetNetStats()
        sendLag = math.max(home or 0, world or 0)
    end
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
        self:UpdateIconCooldown()
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
    local thickness = 20
    local sparkOnly = GetDBBool("cast_sparkOnly")
    local useClassColor = GetDBBool("cast_useClassColor")
    local frameOpacity = GetDBValue("cast_frameOpacity")
    if frameOpacity == nil then
        frameOpacity = 0.8
    end
    local backgroundOpacity = GetDBValue("cast_backgroundOpacity")
    if backgroundOpacity == nil then
        backgroundOpacity = 0.8
    end
    local glowOpacity = GetDBValue("cast_glowOpacity")
    if glowOpacity == nil then
        glowOpacity = 0.8
    end
    local cr, cg, cb, ca
    if useClassColor then
        cr, cg, cb, ca = API.GetPlayerClassColor()
    end
    local backgroundColor = {r = 1, g = 1, b = 1, a = backgroundOpacity}
    local frameColor = {r = 1, g = 1, b = 1, a = frameOpacity}
    local glowColor = {r = 1, g = 1, b = 1, a = glowOpacity}

    -- Update spark
    local r, g, b, a
    if useClassColor then
        r, g, b, a = cr, cg, cb, ca
    else
        r, g, b, a = GetDBColor("cast_sparkColor")
    end
    castFrame.sparkTexture:SetVertexColor(r, g, b, a)
    castFrame.sparkTexture:SetSize(radius * 0.5, radius * 0.5)

    -- Rebuild donuts if needed
    if not sparkOnly then
        if not castDonut then
            -- Create latency donut (between fill and frame)
            latencyDonut = DonutWidget:Create({
                direction = false,
                radius = radius,
                thickness = thickness,
                barColor = GetDBColorTable("cast_latencyColor"),
                backgroundColor = {r = 1, g = 1, b = 1, a = 0},
                backgroundTextureBase = nil,
                progressTextureBase = "cast_fill",
                frameTextureBase = nil,
            })
            latencyDonut:AttachTo(castFrame)
            latencyDonut:SetOverlayShown(false)
            latencyDonut:SetBackgroundColor({r = 1, g = 1, b = 1, a = 0})

            -- Create cast donut (background + fill + glow)
            castDonut = DonutWidget:Create({
                direction = true,
                radius = radius,
                thickness = thickness,
                barColor = useClassColor and {r = cr, g = cg, b = cb, a = ca} or GetDBColorTable("cast_barColor"),
                backgroundColor = backgroundColor,
                backgroundTextureBase = "cast_background",
                progressTextureBase = "cast_fill",
                overlayTextureBase = "cast_glow",
                frameTextureBase = nil,
            })
            castDonut:AttachTo(castFrame)
        else
            -- Update existing donuts
            castDonut:SetRadius(radius)
            castDonut:SetThickness(thickness)
            castDonut:SetBarColor(useClassColor and {r = cr, g = cg, b = cb, a = ca} or GetDBColorTable("cast_barColor"))
            castDonut:SetBackgroundColor(backgroundColor)

            latencyDonut:SetRadius(radius)
            latencyDonut:SetThickness(thickness)
            latencyDonut:SetBarColor(GetDBColorTable("cast_latencyColor"))
            latencyDonut:SetBackgroundColor({r = 1, g = 1, b = 1, a = 0})
        end
    end

    -- Update glow overlay color
    if castDonut then
        castDonut:SetOverlayColor(glowColor)
    end

    -- Update frame overlay texture (top border)
    if castFrame.frameTexture then
        local texPath = addon.addonFolder .. "\\Textures\\cast_frame_20"
        castFrame.frameTexture:SetTexture(texPath)
        castFrame.frameTexture:SetVertexColor(frameColor.r, frameColor.g, frameColor.b, frameColor.a)
        castFrame.frameTexture:SetSize(radius * 2, radius * 2)
        castFrame.frameTexture:ClearAllPoints()
        castFrame.frameTexture:SetPoint("CENTER", castFrame.overlayFrame, "CENTER")
        if not sparkOnly and isActive then
            castFrame.frameTexture:Show()
        else
            castFrame.frameTexture:Hide()
        end
    end

    -- Enforce layering: fill below latency, frame on top
    if castDonut then
        castDonut:SetFrameLevel(1)
    end
    if latencyDonut then
        latencyDonut:SetFrameLevel(2)
    end

    -- Update spell text
    if castFrame.spellText then
        local font = GetDBValue("cast_spellTextFont")
        local size = GetDBValue("cast_spellTextSize")
        local outline = GetDBValue("cast_spellTextOutline")

        castFrame.spellText:SetFont(font, size, outline)

        local tr, tg, tb, ta
        if useClassColor then
            tr, tg, tb, ta = cr, cg, cb, ca
        else
            tr, tg, tb, ta = GetDBColor("cast_spellTextColor")
        end
        castFrame.spellText:SetTextColor(tr, tg, tb, ta)

        local offsetX = GetDBValue("cast_spellTextOffsetX")
        local offsetY = GetDBValue("cast_spellTextOffsetY")
        castFrame.spellText:ClearAllPoints()
        castFrame.spellText:SetPoint("BOTTOM", castFrame, "CENTER", offsetX, radius + 5 + offsetY)
        -- Warm text rendering after font is set
        castFrame.spellText:SetText(" ")
        castFrame.spellText:Hide()
    end

    -- No frame-level pinning; rely on natural draw order.
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

    -- Create overlay frame for top-most elements
    castFrame.overlayFrame = CreateFrame("Frame", nil, castFrame)
    castFrame.overlayFrame:SetAllPoints()
    castFrame.overlayFrame:SetFrameLevel(castFrame:GetFrameLevel() + 10)

    -- Create spark texture (above rings)
    castFrame.sparkTexture = castFrame.overlayFrame:CreateTexture(nil, "OVERLAY")
    castFrame.sparkTexture:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
    castFrame.sparkTexture:SetBlendMode("ADD")
    castFrame.sparkTexture:SetSize(32, 32)

    -- Create cast frame overlay texture (top border)
    castFrame.frameTexture = castFrame.overlayFrame:CreateTexture(nil, "OVERLAY")
    castFrame.frameTexture:SetDrawLayer("OVERLAY", 7)
    castFrame.frameTexture:Hide()

    -- Create spell text
    castFrame.spellText = castFrame:CreateFontString(nil, "OVERLAY")
    castFrame.spellText:Hide()

    -- Create spell icon frame (rendered with cast frame)
    castFrame.iconFrame = CreateFrame("Frame", nil, castFrame)
    castFrame.iconFrame:SetSize(32, 32)
    castFrame.iconFrame:SetPoint("CENTER", castFrame, "CENTER", 0, -40)
    castFrame.iconFrame:Hide()

    castFrame.iconFrame.border = castFrame.iconFrame:CreateTexture(nil, "OVERLAY")
    castFrame.iconFrame.border:SetAllPoints()
    castFrame.iconFrame.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    castFrame.iconFrame.border:SetTexCoord(0.2, 0.8, 0.2, 0.8)

    castFrame.iconFrame.icon = castFrame.iconFrame:CreateTexture(nil, "ARTWORK")
    castFrame.iconFrame.icon:SetPoint("CENTER")
    castFrame.iconFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Preload assets to avoid first-use stutter (font must be set before text)
    castFrame.iconFrame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    castFrame.iconFrame.icon:Hide()

    if not castFrame.iconFrame.cooldown then
        castFrame.iconFrame.cooldown = CreateFrame("Cooldown", nil, castFrame.iconFrame, "CooldownFrameTemplate")
        castFrame.iconFrame.cooldown:SetAllPoints(castFrame.iconFrame.icon)
        castFrame.iconFrame.cooldown:SetDrawEdge(false)
        castFrame.iconFrame.cooldown:SetHideCountdownNumbers(true)
        castFrame.iconFrame.cooldown:Hide()
    end

    self:RegisterMasqueButtons()
    self:ReskinMasque()
    EnsureMasqueLoader()

    -- Set scripts
    castFrame:SetScript("OnUpdate", OnUpdate)
    castFrame:SetScript("OnShow", function()
        Cast:ApplyPendingVisuals()
    end)

    spellIconEnabled = addon.GetDBBool("moduleEnabled_SpellIcon")
    self:ApplyOptions()
    self:ApplyIconOptions()
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
        "cast_radius", "cast_barColor", "cast_backgroundOpacity", "cast_frameOpacity", "cast_glowOpacity",
        "cast_sparkColor", "cast_latencyColor", "cast_sparkOnly", "cast_useClassColor",
        "cast_spellTextEnabled", "cast_spellTextFont", "cast_spellTextSize",
        "cast_spellTextOutline", "cast_spellTextColor",
        "cast_spellTextOffsetX", "cast_spellTextOffsetY",
        "spellicon_size", "spellicon_offsetX", "spellicon_offsetY", "spellicon_castProgressSwipe", "spellicon_useClassColor"
    }

for _, key in ipairs(settingKeys) do
    CallbackRegistry:RegisterSettingCallback(key, function()
        Cast:ApplyOptions()
    end)
end

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
