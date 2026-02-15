-- SparkPoint DonutWidget
-- Reusable ring/arc rendering widget with clean API
-- Cooldown swipe-based rendering (full-ring texture)

local addonName, addon = ...

local DonutWidget = {}
addon.DonutWidget = DonutWidget

local GetTime = GetTime

local function ClampThickness(value)
    local numericThickness = tonumber(value) or 25
    local valid = {15, 20, 25, 30, 35}
    local clamped = valid[1]
    local minDiff = math.abs(numericThickness - clamped)
    for i = 2, #valid do
        local diff = math.abs(numericThickness - valid[i])
        if diff < minDiff then
            minDiff = diff
            clamped = valid[i]
        end
    end
    return clamped
end

local function SafeCall(obj, method, ...)
    if obj and obj[method] then
        obj[method](obj, ...)
    end
end

local function SetTextureSmooth(texture, texturePath)
    if not texture then return end

    -- Try trilinear sampling first; fallback to default if unsupported.
    local ok = pcall(texture.SetTexture, texture, texturePath, nil, nil, "TRILINEAR")
    if not ok then
        texture:SetTexture(texturePath)
    end

    -- Avoid pixel-grid snapping for softer vector-derived edges.
    SafeCall(texture, "SetSnapToPixelGrid", false)
    SafeCall(texture, "SetTexelSnappingBias", 0)
end

--------------------------------------------------------------------------------
-- DonutWidget:Create(config) -> donut
--
-- config = {
--     direction = true,      -- true = clockwise, false = counter-clockwise
--     radius = 22,
--     thickness = 25,        -- 15, 20, 25, 30, or 35
--     barColor = {r, g, b, a},
--     backgroundColor = {r, g, b, a},
--     parent = frame,        -- optional parent frame
-- }
--------------------------------------------------------------------------------
function DonutWidget:Create(config)
    local donut = {}

    donut.radius = config.radius or 22
    donut.thickness = ClampThickness(config.thickness)
    donut.direction = config.direction ~= false  -- default true (clockwise)
    donut.backgroundBase = config.backgroundTextureBase or "ring"
    donut.progressBase = config.progressTextureBase or "ring"
    donut.overlayBase = config.overlayTextureBase
    donut.frameBase = config.frameTextureBase

    ----------------------------------------------------------------------------
    -- Create frames
    ----------------------------------------------------------------------------
    local bgFrame
    if config.parent then
        bgFrame = CreateFrame("Frame", nil, config.parent)
    else
        bgFrame = CreateFrame("Frame")
    end
    donut.bgFrame = bgFrame

    local frame = CreateFrame("Frame", nil, bgFrame)
    donut.frame = frame
    frame:SetParent(bgFrame)
    frame:SetAllPoints(bgFrame)

    -- Ring-sized container to avoid full-screen cooldown scaling
    local ringFrame = CreateFrame("Frame", nil, frame)
    donut.ringFrame = ringFrame
    ringFrame:SetPoint("CENTER", frame, "CENTER")
    ringFrame:SetFrameLevel(1)

    ----------------------------------------------------------------------------
    -- Background texture (full ring)
    ----------------------------------------------------------------------------
    donut.background = ringFrame:CreateTexture(nil, "BACKGROUND")
    donut.background:SetPoint("CENTER", ringFrame, "CENTER")

    ----------------------------------------------------------------------------
    -- Foreground (full ring for 100%)
    ----------------------------------------------------------------------------
    donut.foreground = ringFrame:CreateTexture(nil, "ARTWORK")
    donut.foreground:SetPoint("CENTER", ringFrame, "CENTER")
    donut.foreground:Hide()

    ----------------------------------------------------------------------------
    -- Overlay (glow)
    ----------------------------------------------------------------------------
    donut.overlay = ringFrame:CreateTexture(nil, "OVERLAY")
    donut.overlay:SetPoint("CENTER", ringFrame, "CENTER")
    donut.overlay:SetBlendMode("ADD")
    donut.overlay:SetDrawLayer("OVERLAY", 1)
    donut.overlay:Hide()

    ----------------------------------------------------------------------------
    -- Frame (top border)
    ----------------------------------------------------------------------------
    donut.frameTex = ringFrame:CreateTexture(nil, "OVERLAY")
    donut.frameTex:SetPoint("CENTER", ringFrame, "CENTER")
    donut.frameTex:SetDrawLayer("OVERLAY", 7)
    donut.frameTex:Hide()

    ----------------------------------------------------------------------------
    -- Cooldown swipe (progress)
    ----------------------------------------------------------------------------
    donut.cooldown = CreateFrame("Cooldown", nil, ringFrame, "CooldownFrameTemplate")
    donut.cooldown:SetAllPoints(ringFrame)
    donut.cooldown:SetFrameLevel(5)
    SafeCall(donut.cooldown, "SetHideCountdownNumbers", true)
    SafeCall(donut.cooldown, "SetDrawEdge", false)
    SafeCall(donut.cooldown, "SetDrawBling", false)

    ----------------------------------------------------------------------------
    -- Apply initial configuration
    ----------------------------------------------------------------------------
    setmetatable(donut, {__index = DonutWidget})

    donut:SetThickness(donut.thickness)
    donut:SetDirection(donut.direction)
    donut:SetRadius(donut.radius)

    if config.barColor then
        donut:SetBarColor(config.barColor)
    else
        donut:SetBarColor({r = 1, g = 1, b = 1, a = 0.8})
    end

    if config.backgroundColor then
        donut:SetBackgroundColor(config.backgroundColor)
    else
        donut:SetBackgroundColor({r = 0.4, g = 0.4, b = 0.4, a = 0.8})
    end

    donut:SetAngle(0)

    return donut
end

--------------------------------------------------------------------------------
-- AttachTo: Parent donut to an anchor frame
--------------------------------------------------------------------------------
function DonutWidget:AttachTo(anchor)
    self.bgFrame:SetParent(anchor)
    self.bgFrame:SetAllPoints(anchor)
end

--------------------------------------------------------------------------------
-- SetRadius: Change ring size
--------------------------------------------------------------------------------
function DonutWidget:SetRadius(radius)
    self.radius = radius

    local size = radius * 2
    self.ringFrame:SetSize(size, size)
    self.background:SetSize(size, size)
    self.foreground:SetSize(size, size)
    self.overlay:SetSize(size, size)
    self.frameTex:SetSize(size, size)
    self.cooldown:SetSize(size, size)
end

--------------------------------------------------------------------------------
-- SetThickness: Change ring thickness (switches ring texture)
--------------------------------------------------------------------------------
function DonutWidget:SetThickness(thickness)
    local clamped = ClampThickness(thickness)
    self.thickness = clamped

    if self.backgroundBase then
        local backgroundPath = addon.addonFolder .. "\\Textures\\" .. self.backgroundBase .. "_" .. clamped .. ".png"
        SetTextureSmooth(self.background, backgroundPath)
        self.background:Show()
    else
        self.background:Hide()
    end

    local progressPath = addon.addonFolder .. "\\Textures\\" .. self.progressBase .. "_" .. clamped .. ".png"
    SetTextureSmooth(self.foreground, progressPath)
    SafeCall(self.cooldown, "SetSwipeTexture", progressPath)

    if self.overlayBase then
        local overlayPath = addon.addonFolder .. "\\Textures\\" .. self.overlayBase .. "_" .. clamped .. ".png"
        SetTextureSmooth(self.overlay, overlayPath)
    end

    if self.frameBase then
        local framePath = addon.addonFolder .. "\\Textures\\" .. self.frameBase .. "_" .. clamped .. ".png"
        SetTextureSmooth(self.frameTex, framePath)
        self.frameTex:Show()
    else
        self.frameTex:Hide()
    end
end

--------------------------------------------------------------------------------
-- SetDirection: Toggle clockwise/counter-clockwise
--------------------------------------------------------------------------------
function DonutWidget:SetDirection(direction)
    self.direction = direction
    -- Use a fixed Cooldown direction and flip angle math for counter-clockwise.
    self.reverse = not direction
    SafeCall(self.cooldown, "SetReverse", false)
end

--------------------------------------------------------------------------------
-- SetBarColor: Update bar RGBA
--------------------------------------------------------------------------------
function DonutWidget:SetBarColor(color)
    SafeCall(self.cooldown, "SetSwipeColor", color.r, color.g, color.b, color.a)
    self.foreground:SetVertexColor(color.r, color.g, color.b, color.a)
end

--------------------------------------------------------------------------------
-- SetOverlayColor: Update overlay RGBA
--------------------------------------------------------------------------------
function DonutWidget:SetOverlayColor(color)
    self.overlay:SetVertexColor(color.r, color.g, color.b, color.a)
end

--------------------------------------------------------------------------------
-- SetOverlayShown: Show/Hide overlay
--------------------------------------------------------------------------------
function DonutWidget:SetOverlayShown(shown)
    if not self.overlayBase then
        self.overlay:Hide()
        return
    end
    if shown then
        self.overlay:Show()
    else
        self.overlay:Hide()
    end
end

--------------------------------------------------------------------------------
-- SetFrameColor: Update frame RGBA
--------------------------------------------------------------------------------
function DonutWidget:SetFrameColor(color)
    self.frameTex:SetVertexColor(color.r, color.g, color.b, color.a)
end

--------------------------------------------------------------------------------
-- SetFrameLevel: Adjust ringFrame layering
--------------------------------------------------------------------------------
function DonutWidget:SetFrameLevel(level)
    if self.ringFrame then
        self.ringFrame:SetFrameLevel(level)
    end
end

--------------------------------------------------------------------------------
-- SetBackgroundColor: Update background RGBA
--------------------------------------------------------------------------------
function DonutWidget:SetBackgroundColor(color)
    self.background:SetVertexColor(color.r, color.g, color.b, color.a)
end

--------------------------------------------------------------------------------
-- SetAngle: Set progress (0-360 degrees) - main animation driver
--------------------------------------------------------------------------------
function DonutWidget:SetAngle(degree)
    -- Clamp degree
    if degree < 0 then
        degree = 0
    elseif degree > 360 then
        degree = 360
    end

    if degree == 0 then
        self.cooldown:Hide()
        self.foreground:Hide()
        return
    end

    if degree >= 360 then
        self.cooldown:Hide()
        self.foreground:Show()
        return
    end

    self.foreground:Hide()

    if self.reverse then
        degree = 360 - degree
    end

    local duration = 1
    local progress = degree / 360
    -- Cooldown swipe fills based on elapsed; compute start so elapsed == progress.
    local start = GetTime() - (progress * duration)

    self.cooldown:SetCooldown(start, duration)
    self.cooldown:Show()
end

--------------------------------------------------------------------------------
-- Show/Hide
--------------------------------------------------------------------------------
function DonutWidget:Show()
    self.bgFrame:Show()
end

function DonutWidget:Hide()
    self.bgFrame:Hide()
    self:SetAngle(0)
end

function DonutWidget:IsShown()
    return self.bgFrame:IsShown()
end

--------------------------------------------------------------------------------
-- Frame access
--------------------------------------------------------------------------------
function DonutWidget:GetFrame()
    return self.bgFrame
end
