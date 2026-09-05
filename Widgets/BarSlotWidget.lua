-- SparkPoint BarSlotWidget
-- Curved horizontal status bar widget for HUD bar slots.

local _, addon = ...

local BarSlotWidget = {}
addon.BarSlotWidget = BarSlotWidget

local BAR_TEXTURE_WIDTH = 1024
local BAR_TEXTURE_HEIGHT = 512
-- The expanded fill texture is authored on the full 1024x512 canvas, but the
-- shell art only accepts fill cleanly inside this narrower fit rectangle.
-- These bounds are in source-texture pixels and are normalized below when the
-- widget is laid out at runtime.
local FILL_FIT_BOUNDS = {
	left = 200,
	right = 830,
	top = 100,
	bottom = 425,
}

local SafeCall = addon.Util.SafeCall
local SetTextureSmooth = addon.Util.SetTextureSmooth

local function ApplyTexCoords8(texture, tc)
	if not texture or not tc then
		return
	end
	texture:SetTexCoord(tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8])
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

	widget.fillFrame = CreateFrame("Frame", nil, widget.frame)

	widget.statusBar = CreateFrame("StatusBar", nil, widget.fillFrame)
	widget.statusBar:SetAllPoints(widget.fillFrame)
	widget.statusBar:SetMinMaxValues(0, 1)
	widget.statusBar:SetValue(0)
	SafeCall(widget.statusBar, "SetOrientation", config.orientation or "HORIZONTAL")
	SafeCall(widget.statusBar, "SetReverseFill", config.reverseFill and true or false)

	widget.statusTex = widget.statusBar:CreateTexture(nil, "ARTWORK", nil, 1)
	widget.statusBar:SetStatusBarTexture(widget.statusTex)

	widget.frameTex = widget.frame:CreateTexture(nil, "OVERLAY")
	widget.frameTex:SetAllPoints(widget.frame)

	setmetatable(widget, { __index = BarSlotWidget })

	widget.backgroundBase = config.backgroundBase
	widget.fillBase = config.fillBase
	widget.frameBase = config.frameBase
	widget.flipFillBoundsY = config.flipFillBoundsY and true or false
	widget.shellTexCoords = config.shellTexCoords

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
	if self.shellTexCoords then
		ApplyTexCoords8(self.background, self.shellTexCoords)
		ApplyTexCoords8(self.frameTex, self.shellTexCoords)
	end
end

function BarSlotWidget:AttachTo(parent)
	self.frame:SetParent(parent)
end

function BarSlotWidget:SetSize(width, height)
	self.frame:SetSize(width, height)
	self.fillFrame:ClearAllPoints()

	local insetLeft = width * (FILL_FIT_BOUNDS.left / BAR_TEXTURE_WIDTH)
	local insetRight = width * ((BAR_TEXTURE_WIDTH - FILL_FIT_BOUNDS.right) / BAR_TEXTURE_WIDTH)
	local insetTop = height * (FILL_FIT_BOUNDS.top / BAR_TEXTURE_HEIGHT)
	local insetBottom = height * ((BAR_TEXTURE_HEIGHT - FILL_FIT_BOUNDS.bottom) / BAR_TEXTURE_HEIGHT)

	if self.flipFillBoundsY then
		insetTop, insetBottom = insetBottom, insetTop
	end

	self.fillFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", insetLeft, -insetTop)
	self.fillFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -insetRight, insetBottom)
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
	self.fillFrame:SetFrameLevel(math.max(0, level))
	self.statusBar:SetFrameLevel(math.max(0, level))
end

function BarSlotWidget:SetFrameStrata(strata)
	self.frame:SetFrameStrata(strata)
	self.fillFrame:SetFrameStrata(strata)
	self.statusBar:SetFrameStrata(strata)
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
