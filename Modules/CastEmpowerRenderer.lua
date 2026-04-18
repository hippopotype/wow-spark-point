local _, addon = ...

local CastEmpowerRenderer = {}
addon.CastEmpowerRenderer = CastEmpowerRenderer

-- Rendering model (session 20 pivot, supersedes Amendment 2 §3 stacked-band
-- design): the main cast donut is the sole progress fill. Its swipe colour is
-- recoloured on-the-fly to match the current rank's tier, so the single
-- advancing arc communicates both "how far into the cast" and "which rank is
-- currently being charged". Tier boundaries are marked by unified breakpoint
-- markers on the ring. Burst flashes at rank-up transitions; a hold-glow
-- overlay shows once hold-at-max begins. The stacked-band / reverse-z design
-- was abandoned because CooldownFrame instances at overlapping ranges did not
-- render reliably (session 20 runtime testing confirmed a middle band
-- dropping its swipe entirely even with all state flags correct).
local MARKER_TEXTURE_PATH = addon.addonFolder .. "\\Textures\\cast_empower_marker.png"
local BURST_TEXTURE_PATH = addon.addonFolder .. "\\Textures\\cast_empower_burst.png"
local HOLD_GLOW_TEXTURE_PATH = addon.addonFolder .. "\\Textures\\cast_empower_hold_glow.png"

-- Tier colours applied to the cast donut fill while the corresponding rank is
-- the active rank. Index 1 is the windup stage (pre-rank-1); indices 2..N are
-- the N-1 rank transitions. Index 5 is a fallback for >4-rank future specs.
local BAND_TIER_COLORS = {
	[1] = { r = 0.55, g = 0.55, b = 0.60 },
	[2] = { r = 0.95, g = 0.65, b = 0.30 },
	[3] = { r = 1.00, g = 0.50, b = 0.18 },
	[4] = { r = 1.00, g = 0.85, b = 0.30 },
	[5] = { r = 0.95, g = 0.95, b = 0.85 },
}

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

local function GetTierColor(bandIndex)
	return BAND_TIER_COLORS[bandIndex] or BAND_TIER_COLORS[5]
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
	-- holdStartProgress so the separator for it would never land in the hold
	-- zone.
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

local function CreateBurstAnimation(texture)
	local animation = texture:CreateAnimationGroup()

	local fadeIn = animation:CreateAnimation("Alpha")
	fadeIn:SetOrder(1)
	fadeIn:SetFromAlpha(0)
	fadeIn:SetToAlpha(1)
	fadeIn:SetDuration(0.08)

	local scaleUp = animation:CreateAnimation("Scale")
	scaleUp:SetOrder(1)
	scaleUp:SetScale(1.12, 1.12)
	scaleUp:SetDuration(0.08)
	scaleUp:SetOrigin("CENTER", 0, 0)

	local fadeOut = animation:CreateAnimation("Alpha")
	fadeOut:SetOrder(2)
	fadeOut:SetFromAlpha(1)
	fadeOut:SetToAlpha(0)
	fadeOut:SetDuration(0.22)

	local scaleDown = animation:CreateAnimation("Scale")
	scaleDown:SetOrder(2)
	scaleDown:SetScale(0.94, 0.94)
	scaleDown:SetDuration(0.22)
	scaleDown:SetOrigin("CENTER", 0, 0)

	animation:SetScript("OnFinished", function()
		texture:Hide()
	end)

	return animation
end

local function CreateBurstVisual(parent)
	local texture = parent:CreateTexture(nil, "OVERLAY", nil, 6)
	SetTextureSmooth(texture, BURST_TEXTURE_PATH)
	texture:SetBlendMode("ADD")
	texture:SetAllPoints(parent)
	texture:Hide()
	return {
		texture = texture,
		animation = CreateBurstAnimation(texture),
	}
end

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
	texture:SetRotation(math.rad(polar - 90))
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

	local burstLayer = CreateFrame("Frame", nil, ringFrame)
	burstLayer:SetAllPoints(ringFrame)
	burstLayer:SetFrameLevel(ringFrame:GetFrameLevel() + 15)

	local holdGlowLayer = CreateFrame("Frame", nil, frame)
	holdGlowLayer:SetAllPoints(ringFrame)
	holdGlowLayer:SetFrameLevel(burstLayer:GetFrameLevel() + 5)

	local holdGlow = holdGlowLayer:CreateTexture(nil, "OVERLAY", nil, 0)
	SetTextureSmooth(holdGlow, HOLD_GLOW_TEXTURE_PATH)
	holdGlow:SetBlendMode("ADD")
	holdGlow:SetAllPoints(holdGlowLayer)
	holdGlow:Hide()

	local renderer = {
		frame = frame,
		ringFrame = ringFrame,
		markerLayer = markerLayer,
		burstLayer = burstLayer,
		holdGlowLayer = holdGlowLayer,
		holdGlow = holdGlow,

		layout = nil,
		layoutID = 0,
		bands = nil,
		radius = 0,

		activeBandIndex = 0,
		achievedBandCount = 0,
		isHoldingAtMax = false,

		markers = {},
		bursts = {},
	}

	return setmetatable(renderer, { __index = CastEmpowerRenderer })
end

-- Allocate or reuse pooled primitives up to `count` bands' worth of
-- markers (one breakpoint per band) and bursts (one per band for rank-up
-- flash).
function CastEmpowerRenderer:EnsurePoolCapacity(count)
	for index = 1, count do
		if not self.bursts[index] then
			self.bursts[index] = CreateBurstVisual(self.burstLayer)
		end
	end

	for index = 1, math.max(count, #self.markers) do
		if not self.markers[index] then
			local texture = self.markerLayer:CreateTexture(nil, "ARTWORK", nil, 0)
			SetTextureSmooth(texture, MARKER_TEXTURE_PATH)
			texture:SetSize(16, 16)
			texture:Hide()

			self.markers[index] = texture
		end
	end
end

function CastEmpowerRenderer:HideAll()
	for _, marker in ipairs(self.markers) do
		marker:Hide()
	end
	for _, burst in ipairs(self.bursts) do
		burst.texture:Hide()
		burst.animation:Stop()
	end
	if self.holdGlow then
		self.holdGlow:Hide()
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
			self.markers[index]:Hide()
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

function CastEmpowerRenderer:PlayBandBurst(bandIndex, color)
	local visual = self.bursts[bandIndex]
	if not visual then
		return
	end

	local safeColor = NormalizeColor(color)
	visual.texture:SetVertexColor(safeColor.r, safeColor.g, safeColor.b, 1)
	visual.texture:Show()
	visual.animation:Stop()
	visual.animation:Play()
end

local function GetMarkerAlpha(index, achievedCount, activeIndex)
	if index == activeIndex then
		return 1.0, 1.0
	end

	if index <= achievedCount then
		return 0.45, 0.55
	end

	return 0.20, 0.35
end

--------------------------------------------------------------------------------
-- Public query API for the cast donut recolour
--------------------------------------------------------------------------------

-- Return the tier colour that the main cast donut should render during the
-- current cast progress. Cast.lua calls this from its per-frame donut update.
function CastEmpowerRenderer:GetActiveTierColor()
	if not self.bands then
		return nil
	end

	-- While holding-at-max we lock to the last band's tier (max rank reached).
	if self.isHoldingAtMax then
		return GetTierColor(#self.bands)
	end

	local index = self.activeBandIndex
	if index <= 0 then
		index = 1
	end
	return GetTierColor(index)
end

--------------------------------------------------------------------------------
-- Per-frame update
--------------------------------------------------------------------------------

function CastEmpowerRenderer:ApplyProgress(progress, color)
	if not self.bands or not self.layout or self.radius <= 0 then
		self:Hide()
		return
	end

	local holdStart = self.layout.holdStartProgress or 1
	local clamped = Clamp01(progress)
	local isHoldingAtMax = holdStart > 0 and clamped >= holdStart

	local previousAchievedCount = self.achievedBandCount
	local achievedCount, activeIndex = ResolveBandStates(self.bands, clamped, previousAchievedCount, isHoldingAtMax)
	local burstColor = NormalizeColor(color)

	self:UpdateMarkers(achievedCount, activeIndex)

	if previousAchievedCount < achievedCount then
		for index = previousAchievedCount + 1, achievedCount do
			local tierColor = GetTierColor(index)
			self:PlayBandBurst(index, tierColor)
		end
	end

	self.achievedBandCount = achievedCount
	self.isHoldingAtMax = isHoldingAtMax and true or false
	self.activeBandIndex = self.isHoldingAtMax and 0 or activeIndex

	if self.isHoldingAtMax then
		self.holdGlow:SetVertexColor(burstColor.r, burstColor.g, burstColor.b, 0.6)
		self.holdGlow:Show()
	else
		self.holdGlow:Hide()
	end

	self.frame:Show()
	self.markerLayer:Show()
	self.burstLayer:Show()
end

function CastEmpowerRenderer:UpdateMarkers(achievedCount, activeIndex)
	local bands = self.bands
	local count = #bands
	local ringRadius = self.radius
	if ringRadius <= 0 or count <= 0 then
		for _, marker in ipairs(self.markers) do
			marker:Hide()
		end
		return
	end

	-- Markers sit at each stage breakpoint, including the final breakpoint
	-- at the cast/hold boundary. Each breakpoint is attributed to the band that
	-- ends there, so marker i lights in band i's tier colour once band i is
	-- achieved.
	for index = 1, count do
		local marker = self.markers[index]
		if marker then
			PositionOnRing(marker, self.markerLayer, bands[index].endProgress, ringRadius)
			local tierColor = GetTierColor(index)
			local _unusedSeparatorAlpha, markerAlpha = GetMarkerAlpha(index, achievedCount, activeIndex)
			marker:SetVertexColor(tierColor.r, tierColor.g, tierColor.b, markerAlpha)
			marker:Show()
		end
	end

	for index = count + 1, #self.markers do
		if self.markers[index] then
			self.markers[index]:Hide()
		end
	end
end

function CastEmpowerRenderer:Show()
	self.frame:Show()
	self.markerLayer:Show()
	self.burstLayer:Show()
	if self.holdGlowLayer then
		self.holdGlowLayer:Show()
	end
end

function CastEmpowerRenderer:Hide()
	self:HideAll()
	self.frame:Hide()
end
