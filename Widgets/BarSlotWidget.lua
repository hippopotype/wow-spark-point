-- SparkPoint BarSlotWidget
-- Curved horizontal status bar widget for top HUD bar slots.

local _, addon = ...

local BarSlotWidget = {}
addon.BarSlotWidget = BarSlotWidget

local function SafeCall(obj, method, ...)
	if obj and obj[method] then
		obj[method](obj, ...)
	end
end

local function SetTextureSmooth(texture, texturePath)
	if not texture then
		return
	end
	local ok = pcall(texture.SetTexture, texture, texturePath, nil, nil, "TRILINEAR")
	if not ok then
		texture:SetTexture(texturePath)
	end
	SafeCall(texture, "SetSnapToPixelGrid", false)
	SafeCall(texture, "SetTexelSnappingBias", 0)
end

function BarSlotWidget:Create(config)
	local widget = {}

	local parent = config.parent
	if parent then
		widget.frame = CreateFrame("Frame", nil, parent)
	else
		widget.frame = CreateFrame("Frame")
	end

	widget.background = widget.frame:CreateTexture(nil, "BACKGROUND")
	widget.background:SetAllPoints(widget.frame)

	widget.statusBar = CreateFrame("StatusBar", nil, widget.frame)
	widget.statusBar:SetAllPoints(widget.frame)
	widget.statusBar:SetMinMaxValues(0, 1)
	widget.statusBar:SetValue(0)
	SafeCall(widget.statusBar, "SetOrientation", "HORIZONTAL")
	SafeCall(widget.statusBar, "SetReverseFill", false)

	widget.statusTex = widget.statusBar:CreateTexture(nil, "ARTWORK", nil, 1)
	widget.statusBar:SetStatusBarTexture(widget.statusTex)

	widget.frameTex = widget.frame:CreateTexture(nil, "OVERLAY")
	widget.frameTex:SetAllPoints(widget.frame)

	setmetatable(widget, { __index = BarSlotWidget })

	widget.backgroundBase = config.backgroundBase
	widget.fillBase = config.fillBase
	widget.frameBase = config.frameBase

	widget:LoadTextures()
	widget:SetSize(config.width or 1, config.height or 1)
	widget:SetBackgroundColor(config.backgroundColor or { r = 1, g = 1, b = 1, a = 1 })
	widget:SetBarColor(config.barColor or { r = 1, g = 1, b = 1, a = 1 })
	widget:SetFrameColor(config.frameColor or { r = 1, g = 1, b = 1, a = 1 })
	widget:Hide()

	return widget
end

function BarSlotWidget:LoadTextures()
	if self.backgroundBase then
		SetTextureSmooth(self.background, addon.addonFolder .. "\\Textures\\" .. self.backgroundBase .. ".png")
	end
	if self.fillBase then
		SetTextureSmooth(self.statusTex, addon.addonFolder .. "\\Textures\\" .. self.fillBase .. ".png")
	end
	if self.frameBase then
		SetTextureSmooth(self.frameTex, addon.addonFolder .. "\\Textures\\" .. self.frameBase .. ".png")
	end
end

function BarSlotWidget:AttachTo(parent)
	self.frame:SetParent(parent)
end

function BarSlotWidget:SetSize(width, height)
	self.frame:SetSize(width, height)
end

function BarSlotWidget:SetValueRange(value, maxValue)
	if value == nil or maxValue == nil then
		self.statusBar:SetMinMaxValues(0, 1)
		self.statusBar:SetValue(0)
		return false
	end

	local okRange = pcall(self.statusBar.SetMinMaxValues, self.statusBar, 0, maxValue)
	local okValue = pcall(self.statusBar.SetValue, self.statusBar, value)
	if not okRange or not okValue then
		self.statusBar:SetMinMaxValues(0, 1)
		self.statusBar:SetValue(0)
		return false
	end

	return true
end

function BarSlotWidget:SetBarColor(color)
	local a = color.a
	if a == nil then
		a = 1
	end
	self.statusBar:SetStatusBarColor(1, 1, 1, 1)
	self.statusTex:SetVertexColor(color.r, color.g, color.b, a)
end

function BarSlotWidget:SetBackgroundColor(color)
	self.background:SetVertexColor(color.r, color.g, color.b, color.a)
end

function BarSlotWidget:SetFrameColor(color)
	self.frameTex:SetVertexColor(color.r, color.g, color.b, color.a)
end

function BarSlotWidget:SetFrameLevel(level)
	self.frame:SetFrameLevel(level)
	self.statusBar:SetFrameLevel(math.max(0, level))
end

function BarSlotWidget:Show()
	self.frame:Show()
end

function BarSlotWidget:Hide()
	self.frame:Hide()
end

function BarSlotWidget:IsShown()
	return self.frame:IsShown()
end

function BarSlotWidget:GetFrame()
	return self.frame
end
