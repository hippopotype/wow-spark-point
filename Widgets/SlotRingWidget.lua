-- SparkPoint SlotRingWidget
-- Lightweight ring widget for inner ring slots
-- Has spark + frame layers, no glow/overlay (lighter than DonutWidget)
-- StatusBar-backed rendering (safer with secret-wrapped values)

local _, addon = ...

local SlotRingWidget = {}
addon.SlotRingWidget = SlotRingWidget

local cos, sin, rad = math.cos, math.sin, math.rad
local GetTime = GetTime
local issecretvalue = _G.issecretvalue

local function SafeCall(obj, method, ...)
	if obj and obj[method] then
		obj[method](obj, ...)
	end
end

local function SetTextureSmooth(texture, texturePath)
	if not texture then return end
	local ok = pcall(texture.SetTexture, texture, texturePath, nil, nil, "TRILINEAR")
	if not ok then
		texture:SetTexture(texturePath)
	end
	SafeCall(texture, "SetSnapToPixelGrid", false)
	SafeCall(texture, "SetTexelSnappingBias", 0)
end

--------------------------------------------------------------------------------
-- SlotRingWidget:Create(config) -> ring
--
-- config = {
--     radius = 16,
--     fillBase = "slot1_fill",           -- texture base name (no extension)
--     frameBase = "slot1_frame",          -- nil to skip frame layer
--     backgroundBase = "slot1_background",-- nil to skip background
--     barColor = {r, g, b, a},
--     backgroundColor = {r, g, b, a},
--     sparkColor = {r, g, b, a},         -- optional, defaults to bar color
--     sparkRadiusRatio = 1.0,             -- optional centerline ratio vs radius
--     parent = frame,                     -- optional parent frame
-- }
--------------------------------------------------------------------------------
function SlotRingWidget:Create(config)
	local ring = {}

	ring.radius = config.radius or 16
	ring.fillBase = config.fillBase
	ring.frameBase = config.frameBase
	ring.backgroundBase = config.backgroundBase
	ring.sparkRadiusRatio = config.sparkRadiusRatio or 1.0

	--------------------------------------------------------------------------
	-- Create frames
	--------------------------------------------------------------------------
	local bgFrame
	if config.parent then
		bgFrame = CreateFrame("Frame", nil, config.parent)
	else
		bgFrame = CreateFrame("Frame")
	end
	ring.bgFrame = bgFrame

	local ringFrame = CreateFrame("Frame", nil, bgFrame)
	ring.ringFrame = ringFrame
	ringFrame:SetPoint("CENTER", bgFrame, "CENTER")

	-- Dedicated overlay container that stays above fill/cooldown visuals.
	ring.overlayFrame = CreateFrame("Frame", nil, ringFrame)
	ring.overlayFrame:SetAllPoints(ringFrame)
	ring.overlayFrame:SetFrameLevel((ringFrame:GetFrameLevel() or 1) + 2)

	--------------------------------------------------------------------------
	-- Background texture (full ring)
	--------------------------------------------------------------------------
	ring.background = ringFrame:CreateTexture(nil, "BACKGROUND")
	ring.background:SetPoint("CENTER", ringFrame, "CENTER")

	--------------------------------------------------------------------------
	-- StatusBar-backed fill (engine-driven value rendering)
	--------------------------------------------------------------------------
	ring.statusBar = CreateFrame("StatusBar", nil, ringFrame)
	ring.statusBar:SetPoint("CENTER", ringFrame, "CENTER")
	ring.statusBar:SetMinMaxValues(0, 1)
	ring.statusBar:SetValue(0)

	ring.statusTex = ring.statusBar:CreateTexture(nil, "ARTWORK", nil, 1)
	ring.statusTex:SetPoint("TOPLEFT", ring.statusBar, "TOPLEFT")
	ring.statusTex:SetPoint("BOTTOMRIGHT", ring.statusBar, "BOTTOMRIGHT")
	ring.statusBar:SetStatusBarTexture(ring.statusTex)

	ring.fillMask = ring.statusBar:CreateMaskTexture()
	ring.fillMask:SetPoint("TOPLEFT", ring.statusBar, "TOPLEFT")
	ring.fillMask:SetPoint("BOTTOMRIGHT", ring.statusBar, "BOTTOMRIGHT")
	if ring.statusTex and ring.statusTex.AddMaskTexture then
		ring.statusTex:AddMaskTexture(ring.fillMask)
	end

	--------------------------------------------------------------------------
	-- Radial fill path (clockwise donut progress)
	--------------------------------------------------------------------------
	ring.foreground = ringFrame:CreateTexture(nil, "ARTWORK")
	ring.foreground:SetPoint("CENTER", ringFrame, "CENTER")
	ring.foreground:Hide()

	ring.cooldown = CreateFrame("Cooldown", nil, ringFrame, "CooldownFrameTemplate")
	ring.cooldown:SetAllPoints(ringFrame)
	ring.cooldown:SetFrameLevel(5)
	SafeCall(ring.cooldown, "SetHideCountdownNumbers", true)
	SafeCall(ring.cooldown, "SetDrawEdge", false)
	SafeCall(ring.cooldown, "SetDrawBling", false)
	SafeCall(ring.cooldown, "SetReverse", false)
	ring.cooldown:Hide()

	ring._lastProgress = 0

	--------------------------------------------------------------------------
	-- Frame texture (top border)
	--------------------------------------------------------------------------
	ring.frameTex = ring.overlayFrame:CreateTexture(nil, "OVERLAY")
	ring.frameTex:SetPoint("CENTER", ring.overlayFrame, "CENTER")
	ring.frameTex:SetDrawLayer("OVERLAY", 7)
	ring.frameTex:Hide()

	-- Spark texture
	--------------------------------------------------------------------------
	ring.spark = ring.overlayFrame:CreateTexture(nil, "OVERLAY")
	ring.spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	ring.spark:SetBlendMode("ADD")
	ring.spark:SetDrawLayer("OVERLAY", 2)

	--------------------------------------------------------------------------
	-- Apply initial configuration
	--------------------------------------------------------------------------
	setmetatable(ring, {__index = SlotRingWidget})

	ring:SetRadius(ring.radius)
	ring:LoadTextures()

	if config.barColor then
		ring:SetBarColor(config.barColor)
	else
		ring:SetBarColor({r = 1, g = 1, b = 1, a = 0.8})
	end

	if config.backgroundColor then
		ring:SetBackgroundColor(config.backgroundColor)
	else
		ring:SetBackgroundColor({r = 0.4, g = 0.4, b = 0.4, a = 0.8})
	end

	if config.sparkColor then
		ring:SetSparkColor(config.sparkColor)
	end

	ring:SetProgress(0)

	return ring
end

--------------------------------------------------------------------------------
-- LoadTextures: Load texture files based on base names
--------------------------------------------------------------------------------
function SlotRingWidget:LoadTextures()
	if self.backgroundBase then
		local path = addon.addonFolder .. "\\Textures\\" .. self.backgroundBase .. ".png"
		SetTextureSmooth(self.background, path)
		self.background:Show()
	else
		self.background:Hide()
	end

	if self.fillBase then
		local path = addon.addonFolder .. "\\Textures\\" .. self.fillBase .. ".png"
		SetTextureSmooth(self.statusTex, path)
		if self.fillMask then
			SetTextureSmooth(self.fillMask, path)
		end
		SetTextureSmooth(self.foreground, path)
		SafeCall(self.cooldown, "SetSwipeTexture", path)
	end

	if self.frameBase then
		local path = addon.addonFolder .. "\\Textures\\" .. self.frameBase .. ".png"
		SetTextureSmooth(self.frameTex, path)
		self.frameTex:Show()
	else
		self.frameTex:Hide()
	end
end

--------------------------------------------------------------------------------
-- AttachTo: Parent ring to an anchor frame
--------------------------------------------------------------------------------
function SlotRingWidget:AttachTo(anchor)
	self.bgFrame:SetParent(anchor)
	self.bgFrame:SetAllPoints(anchor)
end

--------------------------------------------------------------------------------
-- SetRadius: Change ring size
--------------------------------------------------------------------------------
function SlotRingWidget:SetRadius(radius)
	self.radius = radius
	local size = radius * 2
	self.ringFrame:SetSize(size, size)
	self.background:SetSize(size, size)
	self.statusBar:SetSize(size, size)
	self.statusTex:SetSize(size, size)
	self.foreground:SetSize(size, size)
	self.frameTex:SetSize(size, size)
	self.cooldown:SetSize(size, size)

	-- Scale spark relative to radius
	self.sparkRadius = radius * self.sparkRadiusRatio
	local sparkSize = math.max(8, self.sparkRadius * 0.4)
	self.spark:SetSize(sparkSize, sparkSize)
end

local function IsSecretNumber(value)
	return type(value) == "number" and issecretvalue and issecretvalue(value)
end

function SlotRingWidget:SetProgress(progress)
	if progress == nil or type(progress) ~= "number" then
		progress = 0
	end
	if progress < 0 then
		progress = 0
	elseif progress > 1 then
		progress = 1
	end

	self._lastProgress = progress

	-- Use radial donut progress (clockwise) for regular provider progress values.
	self.statusBar:Hide()
	self.foreground:Hide()

	if progress <= 0 then
		self.cooldown:Hide()
		self.spark:Hide()
		return
	end

	if progress >= 1 then
		self.cooldown:Hide()
		self.foreground:Show()
		self:UpdateSparkPosition(360)
		return
	end

	local duration = 1
	local start = GetTime() - (progress * duration)
	self.cooldown:SetCooldown(start, duration)
	self.cooldown:Show()
	self:UpdateSparkPosition(progress * 360)
end

-- SetValueRange uses engine min/max fill logic and can accept secret-wrapped values.
-- If we also have a numeric percent, we use it for spark placement.
function SlotRingWidget:SetValueRange(value, maxValue, percentForSpark)
	if value == nil or maxValue == nil then
		self:SetProgress(0)
		return
	end

	self.cooldown:Hide()
	self.foreground:Hide()
	self.statusBar:Show()

	local okRange = pcall(self.statusBar.SetMinMaxValues, self.statusBar, 0, maxValue)
	local okValue = pcall(self.statusBar.SetValue, self.statusBar, value)
	if not okRange or not okValue then
		self:SetProgress(0)
		return
	end

	if type(percentForSpark) == "number" and not IsSecretNumber(percentForSpark) then
		if percentForSpark < 0 then
			percentForSpark = 0
		elseif percentForSpark > 1 then
			percentForSpark = 1
		end
		self._lastProgress = percentForSpark
		if percentForSpark > 0 then
			self:UpdateSparkPosition(percentForSpark * 360)
		else
			self.spark:Hide()
		end
	else
		-- No safe ratio available: keep fill visible, suppress spark to avoid unsafe math.
		self.spark:Hide()
	end
end

--------------------------------------------------------------------------------
-- UpdateSparkPosition: Position spark on ring circumference
--------------------------------------------------------------------------------
function SlotRingWidget:UpdateSparkPosition(degree)
	local sparkAngle = 360 - (-90 + degree)
	local sparkRadius = self.sparkRadius or self.radius
	local x = cos(rad(sparkAngle)) * sparkRadius
	local y = sin(rad(sparkAngle)) * sparkRadius

	self.spark:SetRotation(rad(sparkAngle + 90))
	self.spark:ClearAllPoints()
	self.spark:SetPoint("CENTER", self.ringFrame, "CENTER", x, y)
	self.spark:Show()
end

--------------------------------------------------------------------------------
-- SetBarColor: Update bar RGBA
--------------------------------------------------------------------------------
function SlotRingWidget:SetBarColor(color)
	local a = color.a
	if a == nil then a = 1 end
	self.statusBar:SetStatusBarColor(color.r, color.g, color.b, a)
	SafeCall(self.cooldown, "SetSwipeColor", color.r, color.g, color.b, a)
	self.foreground:SetVertexColor(color.r, color.g, color.b, a)
	self.statusTex:SetVertexColor(1, 1, 1, 1)
end

--------------------------------------------------------------------------------
-- SetBackgroundColor: Update background RGBA
--------------------------------------------------------------------------------
function SlotRingWidget:SetBackgroundColor(color)
	self.background:SetVertexColor(color.r, color.g, color.b, color.a)
end

--------------------------------------------------------------------------------
-- SetSparkColor: Update spark RGBA
--------------------------------------------------------------------------------
function SlotRingWidget:SetSparkColor(color)
	self.spark:SetVertexColor(color.r, color.g, color.b, color.a)
end

--------------------------------------------------------------------------------
-- SetFrameColor: Update frame texture RGBA
--------------------------------------------------------------------------------
function SlotRingWidget:SetFrameColor(color)
	self.frameTex:SetVertexColor(color.r, color.g, color.b, color.a)
end

--------------------------------------------------------------------------------
-- SetFrameLevel: Adjust ringFrame layering
--------------------------------------------------------------------------------
function SlotRingWidget:SetFrameLevel(level)
	if self.ringFrame then
		self.ringFrame:SetFrameLevel(level)
	end
	if self.cooldown then
		self.cooldown:SetFrameLevel(math.max(0, level))
	end
	if self.statusBar then
		self.statusBar:SetFrameLevel(math.max(0, level - 1))
	end
	if self.overlayFrame then
		self.overlayFrame:SetFrameLevel(math.max(0, level + 2))
	end
end

--------------------------------------------------------------------------------
-- Show/Hide
--------------------------------------------------------------------------------
function SlotRingWidget:Show()
	self.bgFrame:Show()
end

function SlotRingWidget:Hide()
	self.bgFrame:Hide()
	self:SetProgress(0)
end

function SlotRingWidget:IsShown()
	return self.bgFrame:IsShown()
end

--------------------------------------------------------------------------------
-- Frame access
--------------------------------------------------------------------------------
function SlotRingWidget:GetFrame()
	return self.bgFrame
end
