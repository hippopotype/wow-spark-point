-- SparkPoint DonutWidget
-- Reusable ring/arc rendering widget with clean API
-- Ported from original donut.lua (Circle Cast 2 by Greg Flynn)

local addonName, addon = ...

local DonutWidget = {}
addon.DonutWidget = DonutWidget

local rad, sin, cos, ceil = math.rad, math.sin, math.cos, math.ceil
local tinsert = table.insert

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
    donut.thickness = config.thickness or 25
    donut.direction = config.direction ~= false  -- default true (clockwise)

    ----------------------------------------------------------------------------
    -- Create frames
    ----------------------------------------------------------------------------
    local bgFrame = config.parent or CreateFrame("Frame")
    donut.bgFrame = bgFrame

    local frame = CreateFrame("Frame", nil, bgFrame)
    donut.frame = frame
    frame:SetParent(bgFrame)
    frame:SetAllPoints(bgFrame)

    ----------------------------------------------------------------------------
    -- Background textures (4 quarters)
    ----------------------------------------------------------------------------
    donut.background = {}

    -- Quarter 1 (bottom-left)
    local texture = bgFrame:CreateTexture(nil, "BACKGROUND")
    texture:SetPoint("BOTTOMLEFT", bgFrame, "CENTER")
    tinsert(donut.background, texture)

    -- Quarter 2 (top-left)
    texture = bgFrame:CreateTexture(nil, "BACKGROUND")
    texture:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
    texture:SetPoint("TOPLEFT", bgFrame, "CENTER")
    tinsert(donut.background, texture)

    -- Quarter 3 (top-right)
    texture = bgFrame:CreateTexture(nil, "BACKGROUND")
    texture:SetTexCoord(1, 1, 1, 0, 0, 1, 0, 0)
    texture:SetPoint("TOPRIGHT", bgFrame, "CENTER")
    tinsert(donut.background, texture)

    -- Quarter 4 (bottom-right)
    texture = bgFrame:CreateTexture(nil, "BACKGROUND")
    texture:SetTexCoord(1, 0, 1, 1, 0, 0, 0, 1)
    texture:SetPoint("BOTTOMRIGHT", bgFrame, "CENTER")
    tinsert(donut.background, texture)

    ----------------------------------------------------------------------------
    -- Foreground segments (3 quarters for progress display)
    ----------------------------------------------------------------------------
    donut.segment1 = frame:CreateTexture(nil, "ARTWORK")
    donut.segment2 = frame:CreateTexture(nil, "ARTWORK")
    donut.segment3 = frame:CreateTexture(nil, "ARTWORK")

    ----------------------------------------------------------------------------
    -- Dynamic parts (slice, red, blue for smooth arc edges)
    ----------------------------------------------------------------------------
    donut.slice = frame:CreateTexture(nil, "ARTWORK")
    donut.slice:SetTexture(addon.addonFolder .. "\\Textures\\slice")
    donut.red = frame:CreateTexture(nil, "ARTWORK")
    donut.blue = frame:CreateTexture(nil, "ARTWORK")

    ----------------------------------------------------------------------------
    -- Apply initial configuration
    ----------------------------------------------------------------------------
    -- Set metatable first so methods work
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

    -- Show background textures
    for _, v in ipairs(donut.background) do
        v:Show()
    end
    donut.slice:Show()
    donut.red:Show()
    donut.blue:Show()

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
    for _, v in ipairs(self.background) do
        v:SetWidth(radius)
        v:SetHeight(radius)
    end

    self.segment1:SetWidth(radius)
    self.segment1:SetHeight(radius)
    self.segment2:SetWidth(radius)
    self.segment2:SetHeight(radius)
    self.segment3:SetWidth(radius)
    self.segment3:SetHeight(radius)
end

--------------------------------------------------------------------------------
-- SetThickness: Change ring thickness (reloads texture)
--------------------------------------------------------------------------------
function DonutWidget:SetThickness(thickness)
    self.thickness = thickness
    local texPath = addon.addonFolder .. "\\Textures\\segment_" .. thickness

    for _, v in ipairs(self.background) do
        v:SetTexture(texPath)
    end

    self.segment1:SetTexture(texPath)
    self.segment2:SetTexture(texPath)
    self.segment3:SetTexture(texPath)
    self.red:SetTexture(texPath)
    self.blue:SetTexture(texPath)
end

--------------------------------------------------------------------------------
-- SetDirection: Toggle clockwise/counter-clockwise
--------------------------------------------------------------------------------
function DonutWidget:SetDirection(direction)
    self.direction = direction
    local donutFrame = self.frame
    local s1, s2, s3 = self.segment1, self.segment2, self.segment3

    -- Clear existing points
    s1:ClearAllPoints()
    s2:ClearAllPoints()
    s3:ClearAllPoints()

    if direction then
        -- Clockwise
        s1:SetPoint("BOTTOMLEFT", donutFrame, "CENTER")
        s1:SetTexCoord(0, 0, 0, 0, 0, 0, 0, 0)  -- Default

        s2:SetPoint("TOPLEFT", donutFrame, "CENTER")
        s2:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)

        s3:SetPoint("TOPRIGHT", donutFrame, "CENTER")
        s3:SetTexCoord(1, 1, 1, 0, 0, 1, 0, 0)
    else
        -- Counter-clockwise
        s1:SetPoint("BOTTOMRIGHT", donutFrame, "CENTER")
        s1:SetTexCoord(1, 0, 1, 1, 0, 0, 0, 1)

        s2:SetPoint("TOPRIGHT", donutFrame, "CENTER")
        s2:SetTexCoord(1, 1, 1, 0, 0, 1, 0, 0)

        s3:SetPoint("TOPLEFT", donutFrame, "CENTER")
        s3:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
    end
end

--------------------------------------------------------------------------------
-- SetBarColor: Update bar RGBA
--------------------------------------------------------------------------------
function DonutWidget:SetBarColor(color)
    self.red:SetVertexColor(color.r, color.g, color.b, color.a)
    self.blue:SetVertexColor(color.r, color.g, color.b, color.a)
    self.slice:SetVertexColor(color.r, color.g, color.b, color.a)
    self.segment1:SetVertexColor(color.r, color.g, color.b, color.a)
    self.segment2:SetVertexColor(color.r, color.g, color.b, color.a)
    self.segment3:SetVertexColor(color.r, color.g, color.b, color.a)
end

--------------------------------------------------------------------------------
-- SetBackgroundColor: Update background RGBA
--------------------------------------------------------------------------------
function DonutWidget:SetBackgroundColor(color)
    for _, v in ipairs(self.background) do
        v:SetVertexColor(color.r, color.g, color.b, color.a)
    end
end

--------------------------------------------------------------------------------
-- SetAngle: Set progress (0-360 degrees) - main animation driver
-- Complex texture coordinate math for smooth arc rendering
--------------------------------------------------------------------------------
function DonutWidget:SetAngle(degree)
    local OR = 256  -- Outer Radius in texture space
    local IR = OR - self.thickness  -- Inner Radius
    local TS = 256  -- Texture Size

    -- Clamp degree
    if degree < 0 then
        degree = 0
    elseif degree > 360 then
        degree = 360
    end

    local quarter = ceil(degree / 90)
    if quarter == 0 then quarter = 1 end

    -- Get degree within current quarter
    local quarterDegree = degree - (quarter - 1) * 90
    local radian = rad(quarterDegree)

    -- Calculate intersection points
    local Ix = sin(radian) * IR
    local Iy = TS - cos(radian) * IR
    local Ox = sin(radian) * OR
    local Oy = TS - cos(radian) * OR

    -- Normalize to texture coordinates
    local IxCoord = Ix / TS
    local IyCoord = Iy / TS
    local OxCoord = Ox / TS
    local OyCoord = Oy / TS

    -- Scale to actual radius
    local radius = self.radius
    Ix = IxCoord * radius
    Iy = IyCoord * radius
    Ox = OxCoord * radius
    Oy = OyCoord * radius

    local red, blue, slice = self.red, self.blue, self.slice
    local s1, s2, s3 = self.segment1, self.segment2, self.segment3
    local frame = self.frame

    red:ClearAllPoints()
    blue:ClearAllPoints()
    slice:ClearAllPoints()

    if quarter == 1 then
        s1:Hide()
        s2:Hide()
        s3:Hide()

        if self.direction then
            red:SetTexCoord(0, IxCoord, 0, IyCoord)
            red:SetPoint("TOPLEFT", frame, "CENTER", 0, radius)
            red:SetWidth(Ix)
            red:SetHeight(Iy)

            blue:SetTexCoord(IxCoord, OxCoord, 0, OyCoord)
            blue:SetPoint("TOPLEFT", frame, "CENTER", Ix, radius)
            blue:SetWidth(Ox - Ix)
            blue:SetHeight(Oy)

            slice:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
            slice:SetPoint("TOPLEFT", frame, "CENTER", Ix, radius - Oy)
            slice:SetWidth(Ox - Ix)
            slice:SetHeight(Iy - Oy)
        else
            red:SetTexCoord(IxCoord, 0, IxCoord, IyCoord, 0, 0, 0, IyCoord)
            red:SetPoint("TOPRIGHT", frame, "CENTER", 0, radius)
            red:SetWidth(Ix)
            red:SetHeight(Iy)

            blue:SetTexCoord(OxCoord, 0, OxCoord, OyCoord, IxCoord, 0, IxCoord, OyCoord)
            blue:SetPoint("TOPRIGHT", frame, "CENTER", -Ix, radius)
            blue:SetWidth(Ox - Ix)
            blue:SetHeight(Oy)

            slice:SetTexCoord(1, 0, 1, 1, 0, 0, 0, 1)
            slice:SetPoint("TOPRIGHT", frame, "CENTER", -Ix, radius - Oy)
            slice:SetWidth(Ox - Ix)
            slice:SetHeight(Iy - Oy)
        end

    elseif quarter == 2 then
        s1:Show()
        s2:Hide()
        s3:Hide()

        if self.direction then
            red:SetTexCoord(0, IyCoord, IxCoord, IyCoord, 0, 0, IxCoord, 0)
            red:SetPoint("TOPRIGHT", frame, "CENTER", radius, 0)
            red:SetWidth(Iy)
            red:SetHeight(Ix)

            blue:SetTexCoord(IxCoord, OyCoord, OxCoord, OyCoord, IxCoord, 0, OxCoord, 0)
            blue:SetPoint("TOPRIGHT", frame, "CENTER", radius, -Ix)
            blue:SetWidth(Oy)
            blue:SetHeight(Ox - Ix)

            slice:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
            slice:SetPoint("TOPRIGHT", frame, "CENTER", radius - Oy, -Ix)
            slice:SetWidth(Iy - Oy)
            slice:SetHeight(Ox - Ix)
        else
            red:SetTexCoord(0, 0, IxCoord, 0, 0, IyCoord, IxCoord, IyCoord)
            red:SetPoint("TOPLEFT", frame, "CENTER", -radius, 0)
            red:SetWidth(Iy)
            red:SetHeight(Ix)

            blue:SetTexCoord(IxCoord, 0, OxCoord, 0, IxCoord, OyCoord, OxCoord, OyCoord)
            blue:SetPoint("TOPLEFT", frame, "CENTER", -radius, -Ix)
            blue:SetWidth(Oy)
            blue:SetHeight(Ox - Ix)

            slice:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1)
            slice:SetPoint("TOPLEFT", frame, "CENTER", -radius + Oy, -Ix)
            slice:SetWidth(Iy - Oy)
            slice:SetHeight(Ox - Ix)
        end

    elseif quarter == 3 then
        s1:Show()
        s2:Show()
        s3:Hide()

        if self.direction then
            red:SetTexCoord(IxCoord, IyCoord, IxCoord, 0, 0, IyCoord, 0, 0)
            red:SetPoint("BOTTOMRIGHT", frame, "CENTER", 0, -radius)
            red:SetWidth(Ix)
            red:SetHeight(Iy)

            blue:SetTexCoord(OxCoord, OyCoord, OxCoord, 0, IxCoord, OyCoord, IxCoord, 0)
            blue:SetPoint("BOTTOMRIGHT", frame, "CENTER", -Ix, -radius)
            blue:SetWidth(Ox - Ix)
            blue:SetHeight(Oy)

            slice:SetTexCoord(1, 1, 1, 0, 0, 1, 0, 0)
            slice:SetPoint("BOTTOMRIGHT", frame, "CENTER", -Ix, -radius + Oy)
            slice:SetWidth(Ox - Ix)
            slice:SetHeight(Iy - Oy)
        else
            red:SetTexCoord(0, IyCoord, 0, 0, IxCoord, IyCoord, IxCoord, 0)
            red:SetPoint("BOTTOMLEFT", frame, "CENTER", 0, -radius)
            red:SetWidth(Ix)
            red:SetHeight(Iy)

            blue:SetTexCoord(IxCoord, OyCoord, IxCoord, 0, OxCoord, OyCoord, OxCoord, 0)
            blue:SetPoint("BOTTOMLEFT", frame, "CENTER", Ix, -radius)
            blue:SetWidth(Ox - Ix)
            blue:SetHeight(Oy)

            slice:SetTexCoord(0, 1, 0, 0, 1, 1, 1, 0)
            slice:SetPoint("BOTTOMLEFT", frame, "CENTER", Ix, -radius + Oy)
            slice:SetWidth(Ox - Ix)
            slice:SetHeight(Iy - Oy)
        end

    elseif quarter == 4 then
        s1:Show()
        s2:Show()
        s3:Show()

        if self.direction then
            red:SetTexCoord(IxCoord, 0, 0, 0, IxCoord, IyCoord, 0, IyCoord)
            red:SetPoint("BOTTOMLEFT", frame, "CENTER", -radius, 0)
            red:SetWidth(Iy)
            red:SetHeight(Ix)

            blue:SetTexCoord(OxCoord, 0, IxCoord, 0, OxCoord, OyCoord, IxCoord, OyCoord)
            blue:SetPoint("BOTTOMLEFT", frame, "CENTER", -radius, Ix)
            blue:SetWidth(Oy)
            blue:SetHeight(Ox - Ix)

            slice:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
            slice:SetPoint("BOTTOMLEFT", frame, "CENTER", -radius + Oy, Ix)
            slice:SetWidth(Iy - Oy)
            slice:SetHeight(Ox - Ix)
        else
            red:SetTexCoord(IxCoord, IyCoord, 0, IyCoord, IxCoord, 0, 0, 0)
            red:SetPoint("BOTTOMRIGHT", frame, "CENTER", radius, 0)
            red:SetWidth(Iy)
            red:SetHeight(Ix)

            blue:SetTexCoord(OxCoord, OyCoord, IxCoord, OyCoord, OxCoord, 0, IxCoord, 0)
            blue:SetPoint("BOTTOMRIGHT", frame, "CENTER", radius, Ix)
            blue:SetWidth(Oy)
            blue:SetHeight(Ox - Ix)

            slice:SetTexCoord(1, 1, 0, 1, 1, 0, 0, 0)
            slice:SetPoint("BOTTOMRIGHT", frame, "CENTER", radius - Oy, Ix)
            slice:SetWidth(Iy - Oy)
            slice:SetHeight(Ox - Ix)
        end
    end

    -- Hide slice at exact quarter boundaries
    if quarterDegree == 90 or quarterDegree == 0 then
        slice:Hide()
    else
        slice:Show()
    end
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
