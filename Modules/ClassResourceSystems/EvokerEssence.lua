-- SparkPoint Evoker Essence Class Resource System
-- Dedicated Evoker Essence implementation with Blizzard-style recharge and transition phases.

local _, addon = ...
local ResourceModel = addon.ResourceModel
local ClassResourceSystems = addon.ClassResourceSystems

local GetTime = GetTime
local UnitPartialPower = UnitPartialPower
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local math_abs = math.abs
local math_max = math.max
local math_min = math.min
local math_pi = math.pi

local ESSENCE_POINT_SIZE = 24
local ESSENCE_SPACING = -1
local ESSENCE_UPDATE_INTERVAL = 0.05
local ESSENCE_FULL_BURST_DURATION = 0.80
local ESSENCE_DEPLETE_DURATION = 0.80

local EssenceState = {
	EMPTY = 1,
	FILLING = 2,
	FULL_BURST = 3,
	FULL = 4,
	DEPLETING = 5,
}

local EvokerEssence = {}
EvokerEssence.__index = EvokerEssence

local function Clamp01(value)
	return math_max(0, math_min(1, value or 0))
end

local function SetAlpha(region, alpha)
	if region then
		region:SetAlpha(alpha or 0)
	end
end

local function SetRotation(texture, degrees)
	if texture and texture.SetRotation then
		texture:SetRotation((degrees or 0) * math_pi / 180)
	end
end

local function CreateLayerFrame(parent)
	local frame = CreateFrame("Frame", nil, parent)
	frame:SetAllPoints()
	return frame
end

local function CreateAtlasTexture(parent, layer, subLevel, atlas, useAtlasSize, point, x, y)
	local texture = parent:CreateTexture(nil, layer, nil, subLevel or 0)
	texture:SetPoint(point or "CENTER", x or 0, y or 0)
	texture:SetAtlas(atlas, useAtlasSize and true or false)
	return texture
end

function EvokerEssence:CreatePoint(index)
	local point = CreateFrame("Frame", nil, self.root)
	point:SetSize(ESSENCE_POINT_SIZE, ESSENCE_POINT_SIZE)
	point.index = index
	point.state = EssenceState.EMPTY
	point.fullBurstStartTime = nil
	point.depleteStartTime = nil
	point.lastFillingProgress = nil

	point.Empty = CreateLayerFrame(point)
	point.Empty.BG = CreateAtlasTexture(point.Empty, "ARTWORK", 0, "UF-Essence-BG", true)

	point.Full = CreateLayerFrame(point)
	point.Full.Icon = CreateAtlasTexture(point.Full, "ARTWORK", 0, "UF-Essence-Icon-Active", true)

	point.Filling = CreateLayerFrame(point)
	point.Filling.BG = CreateAtlasTexture(point.Filling, "BACKGROUND", 0, "UF-Essence-BG", true)
	point.Filling.TrailSpinnerIn = CreateAtlasTexture(point.Filling, "ARTWORK", 0, "UF-Essence-TimerSpin-Trail", true)
	point.Filling.IconProgB = CreateAtlasTexture(point.Filling, "ARTWORK", 0, "UF-Essence-Icon-ProgB", true)
	point.Filling.IconProgC = CreateAtlasTexture(point.Filling, "ARTWORK", 0, "UF-Essence-Icon-ProgC", true)
	point.Filling.IconProg = CreateAtlasTexture(point.Filling, "ARTWORK", 0, "UF-Essence-Icon-Prog", true)
	point.Filling.TrailSpinner = CreateAtlasTexture(point.Filling, "ARTWORK", 1, "UF-Essence-Spinner", true)
	point.Filling.TimerSpinner = CreateAtlasTexture(point.Filling, "OVERLAY", 0, "UF-Essence-TimerSpin", true)
	point.Filling.SpinnerOut = CreateAtlasTexture(point.Filling, "ARTWORK", 2, "UF-Essence-SpinnerOut", true)
	point.Filling.SpinStar = CreateAtlasTexture(point.Filling, "ARTWORK", 2, "UF-Essence-Spin-Stars", true)
	point.Filling.SpinOutBG = CreateAtlasTexture(point.Filling, "BORDER", 0, "UF-Essence-Spin-OutBG", true)

	point.FillDone = CreateLayerFrame(point)
	point.FillDone.CircBG = CreateAtlasTexture(point.FillDone, "BACKGROUND", 1, "UF-Essence-BG", true)
	point.FillDone.FXBurst = CreateAtlasTexture(point.FillDone, "BACKGROUND", 0, "UF-Essence-FX-Burst", true)
	point.FillDone.CircBGActive = CreateAtlasTexture(point.FillDone, "BACKGROUND", 2, "UF-Essence-BG-Active", true)
	point.FillDone.Icon = CreateAtlasTexture(point.FillDone, "ARTWORK", 1, "UF-Essence-Icon", true)
	point.FillDone.IconProg = CreateAtlasTexture(point.FillDone, "ARTWORK", 0, "UF-Essence-Icon-Prog", true)
	point.FillDone.RimGlow = CreateAtlasTexture(point.FillDone, "ARTWORK", 0, "UF-Essence-FX-RimGlw", true)
	point.FillDone.IconGlow = CreateAtlasTexture(point.FillDone, "ARTWORK", 2, "UF-Essence-Icon-Glw", true)

	point.Depleting = CreateLayerFrame(point)
	point.Depleting.BG = CreateAtlasTexture(point.Depleting, "BACKGROUND", 0, "UF-Essence-BG", true)
	point.Depleting.FXDepBG = CreateAtlasTexture(point.Depleting, "BORDER", 0, "UF-Essence-FX-DepletedBG", true)
	point.Depleting.CircBGActive = CreateAtlasTexture(point.Depleting, "BORDER", 1, "UF-Essence-BG-Active", true)
	point.Depleting.Icon = CreateAtlasTexture(point.Depleting, "BORDER", 2, "UF-Essence-Icon", true)
	point.Depleting.FXRimGlow = CreateAtlasTexture(point.Depleting, "ARTWORK", 0, "UF-Essence-FX-RimGlwDep", true)
	point.Depleting.IconDeplete = CreateAtlasTexture(point.Depleting, "ARTWORK", 0, "UF-Essence-Icon-Dep", true)
	point.Depleting.FXSmoke = CreateAtlasTexture(point.Depleting, "ARTWORK", 0, "UF-Essence-FX-DepSmoke", true, "CENTER", 0, 10)

	point.Empty:Hide()
	point.Full:Hide()
	point.Filling:Hide()
	point.FillDone:Hide()
	point.Depleting:Hide()

	return point
end

function EvokerEssence:HideTransitions(point)
	point.FillDone:Hide()
	point.Depleting:Hide()
	point.fullBurstStartTime = nil
	point.depleteStartTime = nil
end

function EvokerEssence:ShowEmpty(point)
	self:HideTransitions(point)
	point.Filling:Hide()
	point.Full:Hide()
	point.Empty:Show()
	point.state = EssenceState.EMPTY
	point.lastFillingProgress = nil
end

function EvokerEssence:ShowFull(point)
	self:HideTransitions(point)
	point.Filling:Hide()
	point.Empty:Hide()
	point.Full:Show()
	point.state = EssenceState.FULL
	point.lastFillingProgress = nil
end

function EvokerEssence:UpdateFillingVisual(point, progress)
	progress = Clamp01(progress)
	point.Empty:Hide()
	point.Full:Hide()
	point.FillDone:Hide()
	point.Depleting:Hide()
	point.Filling:Show()
	point.state = EssenceState.FILLING
	point.lastFillingProgress = progress

	local timerAlpha = (progress < 0.56) and 1 or 0
	local trailInAlpha = Clamp01((progress - 0.10) / 0.20) * Clamp01((1 - progress) / 0.04)
	local trailAlpha = Clamp01((progress - 0.10) / 0.40) * Clamp01((1 - progress) / 0.04)
	local progBAlpha = Clamp01((progress - 0.44) / 0.10) * 0.8
	local progCAlpha = Clamp01((progress - 0.60) / 0.10) * 0.8
	local progAlpha = Clamp01((progress - 0.86) / 0.14)
	local spinProgress = Clamp01((progress - 0.80) / 0.20)
	local spinAlpha = Clamp01(1 - Clamp01((progress - 0.92) / 0.08))

	SetAlpha(point.Filling.BG, 1)
	SetAlpha(point.Filling.TimerSpinner, timerAlpha)
	SetAlpha(point.Filling.TrailSpinnerIn, trailInAlpha)
	SetAlpha(point.Filling.TrailSpinner, trailAlpha)
	SetAlpha(point.Filling.IconProgB, progBAlpha)
	SetAlpha(point.Filling.IconProgC, progCAlpha)
	SetAlpha(point.Filling.IconProg, progAlpha)
	SetAlpha(point.Filling.SpinOutBG, spinProgress * spinAlpha)
	SetAlpha(point.Filling.SpinnerOut, spinProgress * spinAlpha)
	SetAlpha(point.Filling.SpinStar, spinProgress * spinAlpha)

	SetRotation(point.Filling.TimerSpinner, -360 * progress)
	SetRotation(point.Filling.TrailSpinnerIn, -360 * progress)
	SetRotation(point.Filling.TrailSpinner, -360 * progress)
	SetRotation(point.Filling.SpinnerOut, -260 * spinProgress)
	SetRotation(point.Filling.SpinStar, -260 * Clamp01((progress - 0.86) / 0.14))
end

function EvokerEssence:StartFullBurst(point, now)
	point.fullBurstStartTime = now
	point.depleteStartTime = nil
	point.state = EssenceState.FULL_BURST
	point.lastFillingProgress = nil
end

function EvokerEssence:UpdateFullBurst(point, now)
	if not point.fullBurstStartTime then
		self:ShowFull(point)
		return false
	end

	local progress = Clamp01((now - point.fullBurstStartTime) / ESSENCE_FULL_BURST_DURATION)
	point.Empty:Hide()
	point.Full:Hide()
	point.Filling:Hide()
	point.Depleting:Hide()
	point.FillDone:Show()
	point.state = EssenceState.FULL_BURST

	local iconGlowAlpha = (progress < 0.31) and Clamp01(progress / 0.31) or Clamp01(1 - ((progress - 0.62) / 0.38))
	local rimGlowAlpha = (progress < 0.31) and Clamp01(progress / 0.31) or Clamp01(1 - ((progress - 0.62) / 0.18))
	local burstAlpha = (progress < 0.25) and (0.8 * Clamp01(progress / 0.25)) or (0.8 * Clamp01(1 - ((progress - 0.25) / 0.50)))

	SetAlpha(point.FillDone.CircBG, 1)
	SetAlpha(point.FillDone.CircBGActive, Clamp01(progress / 0.62))
	SetAlpha(point.FillDone.Icon, Clamp01(progress / 0.31))
	SetAlpha(point.FillDone.IconProg, Clamp01(1 - Clamp01(progress / 0.25)))
	SetAlpha(point.FillDone.RimGlow, rimGlowAlpha)
	SetAlpha(point.FillDone.IconGlow, iconGlowAlpha)
	SetAlpha(point.FillDone.FXBurst, burstAlpha)
	SetRotation(point.FillDone.FXBurst, -30 * Clamp01(progress / 0.25))

	if progress >= 1 then
		self:ShowFull(point)
		return false
	end

	return true
end

function EvokerEssence:StartDeplete(point, now)
	point.depleteStartTime = now
	point.fullBurstStartTime = nil
	point.state = EssenceState.DEPLETING
	point.lastFillingProgress = nil
end

function EvokerEssence:UpdateDeplete(point, now)
	if not point.depleteStartTime then
		self:ShowEmpty(point)
		return false
	end

	local progress = Clamp01((now - point.depleteStartTime) / ESSENCE_DEPLETE_DURATION)
	point.Empty:Hide()
	point.Full:Hide()
	point.Filling:Hide()
	point.FillDone:Hide()
	point.Depleting:Show()
	point.state = EssenceState.DEPLETING

	local fadeLate = Clamp01((progress - 0.375) / 0.625)
	local smokeIn = Clamp01(progress / 0.375)
	local smokeOut = Clamp01((progress - 0.50) / 0.50)

	SetAlpha(point.Depleting.BG, 1)
	SetAlpha(point.Depleting.CircBGActive, 1 - progress)
	SetAlpha(point.Depleting.Icon, 1 - Clamp01(progress / 0.625))
	SetAlpha(point.Depleting.FXDepBG, 1 - fadeLate)
	SetAlpha(point.Depleting.FXRimGlow, 1 - fadeLate)
	SetAlpha(point.Depleting.IconDeplete, 1 - fadeLate)
	SetAlpha(point.Depleting.FXSmoke, smokeIn * (1 - smokeOut))
	point.Depleting.FXSmoke:ClearAllPoints()
	point.Depleting.FXSmoke:SetPoint("CENTER", 0, 10 + (5 * progress))

	if progress >= 1 then
		self:ShowEmpty(point)
		return false
	end

	return true
end

function EvokerEssence:LayoutPoints(count)
	if not self.root then
		return
	end

	local pointCount = count or 0
	local totalWidth = 1
	if pointCount > 0 then
		totalWidth = (pointCount * ESSENCE_POINT_SIZE) + ((pointCount - 1) * ESSENCE_SPACING)
	end
	local x0 = -(totalWidth / 2) + (ESSENCE_POINT_SIZE / 2)

	for i = 1, pointCount do
		local point = self.points[i]
		if not point then
			point = self:CreatePoint(i)
			self.points[i] = point
		end

		point:ClearAllPoints()
		point:SetPoint("CENTER", self.root, "CENTER", x0 + ((i - 1) * (ESSENCE_POINT_SIZE + ESSENCE_SPACING)), 0)
		point:Show()
	end

	for i = pointCount + 1, #self.points do
		self.points[i]:Hide()
	end

	self.visiblePointCount = pointCount
	self.root:SetSize(totalWidth, ESSENCE_POINT_SIZE)
	if self.parentFrame then
		self.parentFrame:SetSize(totalWidth, ESSENCE_POINT_SIZE)
	end
end

function EvokerEssence:ReadEssenceState()
	local resource = self.activeResource
	if not resource or not resource.powerEnum then
		return 0, 0, 0
	end

	local current = UnitPower("player", resource.powerEnum) or 0
	local maxValue = UnitPowerMax("player", resource.powerEnum) or 0
	local partial = 0
	if current < maxValue then
		partial = (UnitPartialPower and UnitPartialPower("player", resource.powerEnum) or 0) or 0
	end

	return current, maxValue, Clamp01((partial or 0) / 1000)
end

function EvokerEssence:UpdateTicker(shouldAnimate)
	if not self.root then
		return
	end

	if shouldAnimate then
		if self.root:GetScript("OnUpdate") then
			return
		end

		self.elapsed = 0
		self.root:SetScript("OnUpdate", function(_, elapsed)
			self.elapsed = self.elapsed + (elapsed or 0)
			if self.elapsed < ESSENCE_UPDATE_INTERVAL then
				return
			end

			self.elapsed = 0
			self:Sync()
		end)
		return
	end

	self.elapsed = 0
	self.root:SetScript("OnUpdate", nil)
end

function EvokerEssence:Initialize(parentFrame)
	self.parentFrame = parentFrame

	if self.root then
		return
	end

	self.root = CreateFrame("Frame", nil, parentFrame)
	self.root:SetPoint("CENTER")
	self.root:SetSize(1, 1)
	self.root:Hide()
end

function EvokerEssence:Shutdown()
	self.activeResource = nil
	self.resolved = nil
	self.suppressTransitions = true
	self:UpdateTicker(false)

	for i = 1, #self.points do
		self.points[i]:Hide()
	end

	if self.root then
		self.root:Hide()
	end
end

function EvokerEssence:SetResource(resourceDef, resolved)
	self.activeResource = resourceDef
	self.resolved = resolved
	self.suppressTransitions = true
	self:LayoutPoints(resourceDef and resourceDef.maxCount or 0)
end

function EvokerEssence:ApplyLayout()
	if not self.root then
		return
	end

	self.root:ClearAllPoints()
	self.root:SetPoint("CENTER")
	self.root:SetScale(1)
	self.root:SetAlpha(1)
	self:LayoutPoints(self.activeResource and (self.activeResource.maxCount or 0) or 0)
end

function EvokerEssence:ApplyVisualOptions() end

function EvokerEssence:SetVisible(visible)
	if not self.root then
		return
	end

	if visible then
		self.root:Show()
		self:Sync()
	else
		self.root:Hide()
		self:UpdateTicker(false)
	end
end

function EvokerEssence:Sync()
	if not self.activeResource or not self.root then
		return
	end

	local current, maxValue, partialProgress = self:ReadEssenceState()
	local now = GetTime()
	local anyAnimating = false
	local allowTransitions = not self.suppressTransitions

	if maxValue ~= self.visiblePointCount then
		self:LayoutPoints(maxValue)
		allowTransitions = false
	end

	for i = 1, maxValue do
		local point = self.points[i]
		if point then
			if i <= current then
				if allowTransitions and point.state ~= EssenceState.FULL and point.state ~= EssenceState.FULL_BURST then
					self:StartFullBurst(point, now)
				end

				if point.state == EssenceState.FULL_BURST then
					if self:UpdateFullBurst(point, now) then
						anyAnimating = true
					end
				else
					self:ShowFull(point)
				end
			elseif i == (current + 1) and current < maxValue then
				point.fullBurstStartTime = nil
				point.depleteStartTime = nil
				self:UpdateFillingVisual(point, partialProgress)
				anyAnimating = true
			else
				if allowTransitions and point.state ~= EssenceState.EMPTY and point.state ~= EssenceState.DEPLETING then
					self:StartDeplete(point, now)
				end

				if point.state == EssenceState.DEPLETING then
					if self:UpdateDeplete(point, now) then
						anyAnimating = true
					end
				else
					self:ShowEmpty(point)
				end
			end
		end
	end

	for i = maxValue + 1, #self.points do
		self.points[i]:Hide()
	end

	self.suppressTransitions = false
	self:UpdateTicker(anyAnimating)
end

function EvokerEssence:WantsEvent(event)
	return event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_POWER_POINT_CHARGE"
end

function EvokerEssence:HandleEvent(event, unit, powerToken)
	if unit ~= "player" or not self.activeResource then
		return
	end

	if powerToken and self.activeResource.powerToken and powerToken ~= self.activeResource.powerToken then
		return
	end

	self:Sync()
end

local function CreateEvokerEssence()
	return setmetatable({
		root = nil,
		parentFrame = nil,
		points = {},
		activeResource = nil,
		resolved = nil,
		visiblePointCount = 0,
		elapsed = 0,
		suppressTransitions = true,
	}, EvokerEssence)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.EVOKER_ESSENCE, CreateEvokerEssence)
