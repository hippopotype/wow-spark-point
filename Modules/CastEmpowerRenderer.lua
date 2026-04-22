local _, addon = ...

local CastEmpowerRenderer = {}
addon.CastEmpowerRenderer = CastEmpowerRenderer

-- Rendering model (session 20 pivot, supersedes Amendment 2 §3 stacked-band
-- design): the main cast donut is the sole progress fill. Its swipe colour is
-- recoloured on-the-fly to match the current rank's tier, so the single
-- advancing arc communicates both "how far into the cast" and "which rank is
-- currently being charged". Tier boundaries are marked by unified breakpoint
-- markers on the ring. Rank-up transitions are reported to Cast.lua for
-- spell-icon feedback. The stacked-band / reverse-z design
-- was abandoned because CooldownFrame instances at overlapping ranges did not
-- render reliably (session 20 runtime testing confirmed a middle band
-- dropping its swipe entirely even with all state flags correct).
local MARKER_TEXTURE_PATH = addon.addonFolder .. "\\Textures\\cast_empower_marker.png"
local MARKER_FRAME_TEXTURE_PATH = addon.addonFolder .. "\\Textures\\cast_empower_marker_frame.png"

local TIER_HUE_STEP = 24 / 360
local TIER_SATURATION_STEP = 0.14
local TIER_LIGHTNESS_STEP = 0.12

local nextLayoutID = 1
local function AllocateLayoutID()
	local id = nextLayoutID
	nextLayoutID = nextLayoutID + 1
	return id
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function SafeCall(object, method, ...)
	if object and object[method] then
		object[method](object, ...)
	end
end

local function Clamp01(value)
	if type(value) ~= "number" then
		return 0
	end
	if value < 0 then
		return 0
	end
	if value > 1 then
		return 1
	end
	return value
end

local function NormalizeColor(color)
	return {
		r = (type(color) == "table" and color.r) or 1,
		g = (type(color) == "table" and color.g) or 1,
		b = (type(color) == "table" and color.b) or 1,
		a = (type(color) == "table" and color.a) or 1,
	}
end

local function RGBToHSL(r, g, b)
	local maxValue = math.max(r, g, b)
	local minValue = math.min(r, g, b)
	local lightness = (maxValue + minValue) / 2

	if maxValue == minValue then
		return 0, 0, lightness
	end

	local delta = maxValue - minValue
	local saturation
	if lightness > 0.5 then
		saturation = delta / (2 - maxValue - minValue)
	else
		saturation = delta / (maxValue + minValue)
	end

	local hue
	if maxValue == r then
		hue = ((g - b) / delta) % 6
	elseif maxValue == g then
		hue = ((b - r) / delta) + 2
	else
		hue = ((r - g) / delta) + 4
	end

	return hue / 6, saturation, lightness
end

local function HueToRGB(p, q, t)
	if t < 0 then
		t = t + 1
	elseif t > 1 then
		t = t - 1
	end

	if t < 1 / 6 then
		return p + (q - p) * 6 * t
	end
	if t < 1 / 2 then
		return q
	end
	if t < 2 / 3 then
		return p + (q - p) * (2 / 3 - t) * 6
	end

	return p
end

local function HSLToRGB(hue, saturation, lightness)
	if saturation <= 0 then
		return lightness, lightness, lightness
	end

	local q
	if lightness < 0.5 then
		q = lightness * (1 + saturation)
	else
		q = lightness + saturation - lightness * saturation
	end
	local p = 2 * lightness - q

	return HueToRGB(p, q, hue + 1 / 3), HueToRGB(p, q, hue), HueToRGB(p, q, hue - 1 / 3)
end

local function GetTierColor(baseColor, bandIndex)
	local color = NormalizeColor(baseColor)
	local hue, saturation, lightness = RGBToHSL(Clamp01(color.r), Clamp01(color.g), Clamp01(color.b))
	local step = math.max(0, (tonumber(bandIndex) or 1) - 1)
	local r, g, b = HSLToRGB((hue + TIER_HUE_STEP * step) % 1, Clamp01(saturation + TIER_SATURATION_STEP * step), Clamp01(lightness + TIER_LIGHTNESS_STEP * step))

	return { r = r, g = g, b = b, a = color.a }
end

local function SetTextureSmooth(texture, texturePath)
	if not texture then
		return
	end

	if not texturePath then
		texture:Hide()
		return
	end

	local ok = pcall(texture.SetTexture, texture, texturePath, nil, nil, "TRILINEAR")
	if not ok then
		texture:SetTexture(texturePath)
	end

	SafeCall(texture, "SetSnapToPixelGrid", false)
	SafeCall(texture, "SetTexelSnappingBias", 0)
end

--------------------------------------------------------------------------------
-- Layout interpretation
--
-- The ring is driven on the cast+hold timeline (the same timeline the main
-- cast donut and the spark use), so the fill, the spark, and the band markers
-- all advance at the same rate. Each band's `endProgress` here is the
-- cast+hold fraction at which that rank is reached, matching
-- EmpowerStageLayout's stage.endProgress directly. holdStartProgress marks the
-- boundary between cast and hold-at-max; the ring passes holdStartProgress
-- as the last rank "achieves".
--------------------------------------------------------------------------------

local function BuildBands(layout)
	if type(layout) ~= "table" then
		return nil
	end

	local stages = layout.stages
	if type(stages) ~= "table" or #stages == 0 then
		return nil
	end

	local holdStart = layout.holdStartProgress
	if type(holdStart) ~= "number" or holdStart <= 0 then
		return nil
	end

	local bands = {}
	for index, stage in ipairs(stages) do
		bands[index] = {
			index = index,
			startProgress = Clamp01(stage.startProgress or 0),
			endProgress = Clamp01(stage.endProgress or 0),
		}
	end

	-- The last rank is achieved at the cast/hold boundary; clamp to
	-- holdStartProgress so its marker never lands in the hold zone.
	bands[#bands].endProgress = holdStart
	return bands
end

-- Resolve the active band and achieved count from the cast-only progress.
-- Achieved is a one-way latch (Amendment 2 §4): once crossed it stays crossed
-- even if a later update jitters back.
local function ResolveBandStates(bands, castProgress, previousAchievedCount, isHoldingAtMax)
	local count = #bands
	local achieved = 0
	local active = 0

	if isHoldingAtMax then
		achieved = count
	else
		for index = 1, count do
			if castProgress >= bands[index].endProgress then
				achieved = index
			else
				break
			end
		end
	end

	if previousAchievedCount and previousAchievedCount > achieved then
		achieved = previousAchievedCount
	end

	if achieved < count and not isHoldingAtMax then
		active = achieved + 1
	end

	return achieved, active
end

--------------------------------------------------------------------------------
-- Overlay primitives
--------------------------------------------------------------------------------

-- Place a breakpoint marker texture at the ring angle that corresponds to
-- `progress` (cast-only, 0..1). Matches Empower.GetProgressPolarAngle in
-- Modules/Cast.lua: progress 0 = 12 o'clock, clockwise positive.
local function PositionOnRing(texture, parent, progress, ringRadius)
	local angle = Clamp01(progress) * 360
	local polar = 360 - (-90 + angle)
	local rad = math.rad(polar)
	local x = math.cos(rad) * ringRadius
	local y = math.sin(rad) * ringRadius
	texture:ClearAllPoints()
	texture:SetPoint("CENTER", parent, "CENTER", x, y)
	texture:SetRotation(math.rad(polar + 90))
end

--------------------------------------------------------------------------------
-- Renderer lifecycle
--------------------------------------------------------------------------------

function CastEmpowerRenderer:Create(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	frame:Hide()

	local ringFrame = CreateFrame("Frame", nil, frame)
	ringFrame:SetPoint("CENTER", frame, "CENTER")
	ringFrame:SetSize(1, 1)
	ringFrame:SetFrameLevel(frame:GetFrameLevel() + 1)

	local markerLayer = CreateFrame("Frame", nil, ringFrame)
	markerLayer:SetAllPoints(ringFrame)
	markerLayer:SetFrameLevel(ringFrame:GetFrameLevel() + 10)

	local renderer = {
		frame = frame,
		ringFrame = ringFrame,
		markerLayer = markerLayer,

		layout = nil,
		layoutID = 0,
		bands = nil,
		radius = 0,

		activeBandIndex = 0,
		achievedBandCount = 0,
		isHoldingAtMax = false,

		markers = {},
		onBandAchieved = nil,
	}

	return setmetatable(renderer, { __index = CastEmpowerRenderer })
end

-- Allocate or reuse pooled primitives up to `count` bands' worth of
-- markers (one breakpoint per band).
function CastEmpowerRenderer:EnsurePoolCapacity(count)
	for index = 1, math.max(count, #self.markers) do
		if not self.markers[index] then
			local fill = self.markerLayer:CreateTexture(nil, "ARTWORK", nil, 0)
			SetTextureSmooth(fill, MARKER_TEXTURE_PATH)
			fill:SetSize(16, 16)
			fill:Hide()

			local frame = self.markerLayer:CreateTexture(nil, "OVERLAY", nil, 1)
			SetTextureSmooth(frame, MARKER_FRAME_TEXTURE_PATH)
			frame:SetSize(16, 16)
			frame:Hide()

			self.markers[index] = { fill = fill, frame = frame }
		end
	end
end

function CastEmpowerRenderer:HideAll()
	for _, marker in ipairs(self.markers) do
		marker.fill:Hide()
		marker.frame:Hide()
	end
end

function CastEmpowerRenderer:SetBandAchievedCallback(callback)
	if type(callback) == "function" then
		self.onBandAchieved = callback
	else
		self.onBandAchieved = nil
	end
end

function CastEmpowerRenderer:Begin(layout)
	local bands = BuildBands(layout)
	if not bands then
		self:Finish()
		return false
	end

	self.layout = layout
	self.layoutID = AllocateLayoutID()
	self.bands = bands
	self.activeBandIndex = 0
	self.achievedBandCount = 0
	self.isHoldingAtMax = false

	local count = #bands
	self:EnsurePoolCapacity(count)

	for index = count + 1, #self.markers do
		if self.markers[index] then
			self.markers[index].fill:Hide()
			self.markers[index].frame:Hide()
		end
	end

	self:Show()
	return true
end

-- SetLayout is a compatibility shim for Cast.lua's existing callers. It is
-- cast-start-only: repeated calls during an in-progress cast are no-ops.
function CastEmpowerRenderer:SetLayout(layout)
	if layout == nil then
		self:Finish()
		return
	end

	if self.layout == layout and self.bands then
		return
	end

	self:Begin(layout)
end

function CastEmpowerRenderer:Finish()
	self:HideAll()
	self.layout = nil
	self.bands = nil
	self.activeBandIndex = 0
	self.achievedBandCount = 0
	self.isHoldingAtMax = false
	self.frame:Hide()
end

function CastEmpowerRenderer:SetRadius(radius)
	if type(radius) ~= "number" or radius < 0 then
		radius = 0
	end

	if self.radius == radius then
		return
	end

	self.radius = radius

	local size = math.max(1, radius * 2)
	if self.ringFrame then
		self.ringFrame:SetSize(size, size)
	end
end

local function GetMarkerAlpha(index, achievedCount, activeIndex)
	if index == activeIndex then
		return 1.0
	end

	if index <= achievedCount then
		return 0.55
	end

	return 0.35
end

--------------------------------------------------------------------------------
-- Public query API for the cast donut recolour
--------------------------------------------------------------------------------

-- Return the tier colour that the main cast donut should render during the
-- current cast progress. Cast.lua calls this from its per-frame donut update.
function CastEmpowerRenderer:GetActiveTierColor(baseColor)
	if not self.bands then
		return nil
	end

	-- While holding-at-max we lock to the last band's tier (max rank reached).
	if self.isHoldingAtMax then
		return GetTierColor(baseColor, #self.bands)
	end

	local index = self.activeBandIndex
	if index <= 0 then
		index = 1
	end
	return GetTierColor(baseColor, index)
end

--------------------------------------------------------------------------------
-- Per-frame update
--------------------------------------------------------------------------------

function CastEmpowerRenderer:ApplyProgress(progress, color, frameColor)
	if not self.bands or not self.layout or self.radius <= 0 then
		self:Hide()
		return
	end

	local holdStart = self.layout.holdStartProgress or 1
	local clamped = Clamp01(progress)
	local isHoldingAtMax = holdStart > 0 and clamped >= holdStart

	local previousAchievedCount = self.achievedBandCount
	local achievedCount, activeIndex = ResolveBandStates(self.bands, clamped, previousAchievedCount, isHoldingAtMax)
	local baseColor = NormalizeColor(color)

	self:UpdateMarkers(achievedCount, activeIndex, baseColor, frameColor)

	if previousAchievedCount < achievedCount then
		for index = previousAchievedCount + 1, achievedCount do
			local tierColor = GetTierColor(baseColor, index)
			if self.onBandAchieved then
				self.onBandAchieved(index, tierColor)
			end
		end
	end

	self.achievedBandCount = achievedCount
	self.isHoldingAtMax = isHoldingAtMax and true or false
	self.activeBandIndex = self.isHoldingAtMax and 0 or activeIndex

	self.frame:Show()
	self.markerLayer:Show()
end

function CastEmpowerRenderer:UpdateMarkers(achievedCount, activeIndex, baseColor, frameColor)
	local bands = self.bands
	local count = #bands
	local ringRadius = self.radius
	if ringRadius <= 0 or count <= 0 then
		for _, marker in ipairs(self.markers) do
			marker.fill:Hide()
			marker.frame:Hide()
		end
		return
	end

	-- Markers sit at each stage breakpoint, including the final breakpoint
	-- at the cast/hold boundary. Each marker inherits the derived tier colour
	-- for the band that ends there.
	for index = 1, count do
		local marker = self.markers[index]
		if marker then
			PositionOnRing(marker.fill, self.markerLayer, bands[index].endProgress, ringRadius)
			PositionOnRing(marker.frame, self.markerLayer, bands[index].endProgress, ringRadius)
			local tierColor = GetTierColor(baseColor, index)
			local markerAlpha = GetMarkerAlpha(index, achievedCount, activeIndex)
			local normalizedFrameColor = NormalizeColor(frameColor)
			marker.fill:SetVertexColor(tierColor.r, tierColor.g, tierColor.b, markerAlpha)
			marker.frame:SetVertexColor(normalizedFrameColor.r, normalizedFrameColor.g, normalizedFrameColor.b, (normalizedFrameColor.a or 1) * markerAlpha)
			marker.fill:Show()
			marker.frame:Show()
		end
	end

	for index = count + 1, #self.markers do
		if self.markers[index] then
			self.markers[index].fill:Hide()
			self.markers[index].frame:Hide()
		end
	end
end

function CastEmpowerRenderer:Show()
	self.frame:Show()
	self.markerLayer:Show()
end

function CastEmpowerRenderer:Hide()
	self:HideAll()
	self.frame:Hide()
end
