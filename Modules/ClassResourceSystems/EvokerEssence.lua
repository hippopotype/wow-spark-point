-- SparkPoint Evoker Essence Class Resource System
-- Dedicated Evoker Essence implementation with native animation groups.

local _, addon = ...
local ResourceModel = addon.ResourceModel
local ClassResourceSystems = addon.ClassResourceSystems

local GetPowerRegenForPowerType = GetPowerRegenForPowerType
local UnitPartialPower = UnitPartialPower
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local math_abs = math.abs

local ESSENCE_POINT_SIZE = 24
local ESSENCE_SPACING = -1
local FILLING_ANIMATION_TIME = 5.0

local EssenceState = {
	EMPTY = 1,
	FILLING = 2,
	FULL_BURST = 3,
	FULL = 4,
	DEPLETING = 5,
}

local EvokerEssence = {}
EvokerEssence.__index = EvokerEssence

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

local function CreateAnimationGroup(parent, toFinalAlpha)
	local group = parent:CreateAnimationGroup()
	if toFinalAlpha ~= nil then
		group:SetToFinalAlpha(toFinalAlpha)
	end
	return group
end

local function AddAlpha(group, target, order, duration, fromAlpha, toAlpha, startDelay)
	local anim = group:CreateAnimation("Alpha")
	anim:SetTarget(target)
	anim:SetOrder(order or 1)
	anim:SetDuration(duration)
	anim:SetFromAlpha(fromAlpha)
	anim:SetToAlpha(toAlpha)
	if startDelay and startDelay > 0 then
		anim:SetStartDelay(startDelay)
	end
	return anim
end

local function AddRotation(group, target, order, duration, degrees, startDelay)
	local anim = group:CreateAnimation("Rotation")
	anim:SetTarget(target)
	anim:SetOrder(order or 1)
	anim:SetDuration(duration)
	anim:SetDegrees(degrees)
	if startDelay and startDelay > 0 then
		anim:SetStartDelay(startDelay)
	end
	return anim
end

local function AddTranslation(group, target, order, duration, offsetX, offsetY, startDelay)
	local anim = group:CreateAnimation("Translation")
	anim:SetTarget(target)
	anim:SetOrder(order or 1)
	anim:SetDuration(duration)
	anim:SetOffset(offsetX or 0, offsetY or 0)
	if startDelay and startDelay > 0 then
		anim:SetStartDelay(startDelay)
	end
	return anim
end

local function GetEssenceAnimationSpeedMultiplier()
	local regen = GetPowerRegenForPowerType and GetPowerRegenForPowerType(Enum.PowerType.Essence)
	if regen == nil or regen == 0 then
		regen = 0.2
	end

	local cooldownDuration = 1 / regen
	return FILLING_ANIMATION_TIME / cooldownDuration
end

local function HideFrame(frame)
	if frame then
		frame:Hide()
	end
end

local function StopGroup(group)
	if group and group:IsPlaying() then
		group:Stop()
	end
end

local function ResetFillingVisual(point)
	local filling = point.Filling
	HideFrame(filling)
	filling.TimerSpinner:SetAlpha(1)
	filling.TimerSpinner:ClearAllPoints()
	filling.TimerSpinner:SetPoint("CENTER", 0, 0)
	filling.TrailSpinner:SetAlpha(0)
	filling.TrailSpinnerIn:SetAlpha(0)
	filling.IconProgB:SetAlpha(0)
	filling.IconProgC:SetAlpha(0)
	filling.IconProg:SetAlpha(0)
	filling.SpinnerOut:SetAlpha(0)
	filling.SpinStar:SetAlpha(0)
	filling.SpinOutBG:SetAlpha(0)
end

local function ResetBurstVisual(point)
	local frame = point.FillDone
	HideFrame(frame)
	frame.CircBG:SetAlpha(1)
	frame.CircBGActive:SetAlpha(0)
	frame.Icon:SetAlpha(0)
	frame.IconProg:SetAlpha(1)
	frame.RimGlow:SetAlpha(0)
	frame.IconGlow:SetAlpha(0)
	frame.FXBurst:SetAlpha(0)
end

local function ResetDepleteVisual(point)
	local frame = point.Depleting
	HideFrame(frame)
	frame.BG:SetAlpha(1)
	frame.FXDepBG:SetAlpha(1)
	frame.CircBGActive:SetAlpha(1)
	frame.Icon:SetAlpha(1)
	frame.FXRimGlow:SetAlpha(1)
	frame.IconDeplete:SetAlpha(1)
	frame.FXSmoke:SetAlpha(0)
	frame.FXSmoke:ClearAllPoints()
	frame.FXSmoke:SetPoint("CENTER", 0, 10)
end

local function StopPointOnUpdate(point)
	if point and point:GetScript("OnUpdate") then
		point:SetScript("OnUpdate", nil)
	end
end

function EvokerEssence:StopPointAnimations(point)
	StopPointOnUpdate(point)
	StopGroup(point.Filling.FillingAnim)
	StopGroup(point.Filling.CircleAnim)
	StopGroup(point.FillDone.AnimIn)
	StopGroup(point.Depleting.AnimIn)
	ResetFillingVisual(point)
	ResetBurstVisual(point)
	ResetDepleteVisual(point)
end

function EvokerEssence:ShowEmpty(point)
	self:StopPointAnimations(point)
	point.Empty:Show()
	point.Full:Hide()
	point.state = EssenceState.EMPTY
end

function EvokerEssence:ShowFull(point)
	self:StopPointAnimations(point)
	point.Empty:Hide()
	point.Full:Show()
	point.state = EssenceState.FULL
end

function EvokerEssence:UpdateFillingAnimationSpeed(point)
	local speedMultiplier = GetEssenceAnimationSpeedMultiplier()
	point.Filling.FillingAnim:SetAnimationSpeedMultiplier(speedMultiplier)
	point.Filling.CircleAnim:SetAnimationSpeedMultiplier(speedMultiplier)
end

function EvokerEssence:StartFilling(point, progress)
	progress = progress or 0
	self:StopPointAnimations(point)
	point.Empty:Hide()
	point.Full:Hide()
	point.FillDone:Hide()
	point.Depleting:Hide()
	point.Filling:Show()
	point.state = EssenceState.FILLING

	self:UpdateFillingAnimationSpeed(point)
	point:SetScript("OnUpdate", function(frame)
		self:UpdateFillingAnimationSpeed(frame)
	end)

	local fillingElapsedOffset = progress * point.Filling.FillingAnim:GetDuration()
	local circleElapsedOffset = progress * point.Filling.CircleAnim:GetDuration()
	point.Filling.FillingAnim:Play(false, fillingElapsedOffset)
	point.Filling.CircleAnim:Play(false, circleElapsedOffset)
end

function EvokerEssence:StartFullBurst(point)
	self:StopPointAnimations(point)
	point.Empty:Hide()
	point.Full:Hide()
	point.Filling:Hide()
	point.Depleting:Hide()
	point.FillDone:Show()
	point.state = EssenceState.FULL_BURST
	point.FillDone.AnimIn:Play()
end

function EvokerEssence:StartDepleting(point, fromFilling)
	self:StopPointAnimations(point)
	point.Empty:Hide()
	point.Full:Hide()
	point.Filling:Hide()
	point.FillDone:Hide()
	point.Depleting:Show()
	point.state = EssenceState.DEPLETING

	if fromFilling then
		point.Depleting.AnimIn:Play(false, point.Depleting.AnimIn:GetDuration())
	else
		point.Depleting.AnimIn:Play()
	end
end

function EvokerEssence:CreatePoint(index)
	local point = CreateFrame("Frame", nil, self.root)
	point:SetSize(ESSENCE_POINT_SIZE, ESSENCE_POINT_SIZE)
	point.index = index
	point.state = EssenceState.EMPTY

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

	point.Filling.FillingAnim = CreateAnimationGroup(point.Filling, false)
	AddRotation(point.Filling.FillingAnim, point.Filling.TimerSpinner, 1, 5, -360)
	AddAlpha(point.Filling.FillingAnim, point.Filling.TimerSpinner, 1, 0.1, 1, 0, 2.8)
	AddTranslation(point.Filling.FillingAnim, point.Filling.TimerSpinner, 1, 0.1, 0, 20, 4.9)
	AddAlpha(point.Filling.FillingAnim, point.Filling.TimerSpinner, 1, 0.1, 0, 1, 0)
	AddRotation(point.Filling.FillingAnim, point.Filling.TrailSpinner, 1, 5, -360)
	AddAlpha(point.Filling.FillingAnim, point.Filling.TrailSpinner, 1, 2, 0, 1, 0.5)
	AddAlpha(point.Filling.FillingAnim, point.Filling.TrailSpinner, 1, 0.2, 1, 0, 4.8)
	AddRotation(point.Filling.FillingAnim, point.Filling.TrailSpinnerIn, 1, 5, -360)
	AddAlpha(point.Filling.FillingAnim, point.Filling.TrailSpinnerIn, 1, 1, 0, 1, 0.5)
	AddAlpha(point.Filling.FillingAnim, point.Filling.TrailSpinnerIn, 1, 0.2, 1, 0, 4.8)
	AddAlpha(point.Filling.FillingAnim, point.Filling.IconProgB, 1, 0.5, 0, 0.8, 2.2)
	AddAlpha(point.Filling.FillingAnim, point.Filling.IconProgC, 1, 0.5, 0, 0.8, 3.0)
	AddAlpha(point.Filling.FillingAnim, point.Filling.IconProg, 1, 0.6, 0, 1, 4.3)

	point.Filling.CircleAnim = CreateAnimationGroup(point.Filling, false)
	AddAlpha(point.Filling.CircleAnim, point.Filling.SpinOutBG, 1, 0.3, 0, 1, 4.0)
	AddAlpha(point.Filling.CircleAnim, point.Filling.SpinOutBG, 1, 0.2, 1, 0, 4.7)
	AddAlpha(point.Filling.CircleAnim, point.Filling.SpinnerOut, 1, 0.3, 0, 1, 4.3)
	AddAlpha(point.Filling.CircleAnim, point.Filling.SpinnerOut, 1, 0.2, 1, 0, 4.6)
	AddRotation(point.Filling.CircleAnim, point.Filling.SpinnerOut, 1, 0.6, -260, 4.3)
	AddAlpha(point.Filling.CircleAnim, point.Filling.SpinStar, 1, 0.3, 0, 1, 4.3)
	AddAlpha(point.Filling.CircleAnim, point.Filling.SpinStar, 1, 0.2, 1, 0, 4.6)
	AddRotation(point.Filling.CircleAnim, point.Filling.SpinStar, 1, 0.7, -260, 4.3)

	point.FillDone.AnimIn = CreateAnimationGroup(point.FillDone, true)
	AddAlpha(point.FillDone.AnimIn, point.FillDone.IconGlow, 1, 0.25, 0, 1, 0)
	AddAlpha(point.FillDone.AnimIn, point.FillDone.IconGlow, 1, 0.5, 1, 0, 0.5)
	AddAlpha(point.FillDone.AnimIn, point.FillDone.Icon, 1, 0.25, 0, 1, 0)
	AddAlpha(point.FillDone.AnimIn, point.FillDone.RimGlow, 1, 0.25, 0, 1, 0)
	AddAlpha(point.FillDone.AnimIn, point.FillDone.RimGlow, 1, 0.3, 1, 0, 0.5)
	AddAlpha(point.FillDone.AnimIn, point.FillDone.CircBGActive, 1, 0.5, 0, 1, 0)
	AddAlpha(point.FillDone.AnimIn, point.FillDone.FXBurst, 1, 0.2, 0, 0.8, 0)
	AddAlpha(point.FillDone.AnimIn, point.FillDone.FXBurst, 1, 0.4, 0.8, 0, 0.2)
	AddRotation(point.FillDone.AnimIn, point.FillDone.FXBurst, 1, 0.2, -30, 0)
	AddRotation(point.FillDone.AnimIn, point.FillDone.FXBurst, 1, 0.5, -10, 0.2)

	point.Depleting.AnimIn = CreateAnimationGroup(point.Depleting, true)
	AddAlpha(point.Depleting.AnimIn, point.Depleting.FXRimGlow, 1, 0.5, 1, 0, 0.3)
	AddAlpha(point.Depleting.AnimIn, point.Depleting.IconDeplete, 1, 0.5, 1, 0, 0.3)
	AddAlpha(point.Depleting.AnimIn, point.Depleting.FXDepBG, 1, 0.5, 1, 0, 0.3)
	AddAlpha(point.Depleting.AnimIn, point.Depleting.CircBGActive, 1, 0.8, 1, 0, 0)
	AddAlpha(point.Depleting.AnimIn, point.Depleting.Icon, 1, 0.5, 1, 0, 0)
	AddAlpha(point.Depleting.AnimIn, point.Depleting.FXSmoke, 1, 0.3, 0, 1, 0)
	AddAlpha(point.Depleting.AnimIn, point.Depleting.FXSmoke, 1, 0.5, 1, 0, 0.4)
	AddTranslation(point.Depleting.AnimIn, point.Depleting.FXSmoke, 1, 0.3, 0, 2, 0)
	AddTranslation(point.Depleting.AnimIn, point.Depleting.FXSmoke, 1, 0.7, 0, 3, 0.3)

	point.Filling.FillingAnim:SetScript("OnFinished", function()
		if point.state == EssenceState.FILLING then
			self:StartFullBurst(point)
		end
	end)

	point.FillDone.AnimIn:SetScript("OnFinished", function()
		if point.state == EssenceState.FULL_BURST then
			self:ShowFull(point)
		end
	end)

	point.Depleting.AnimIn:SetScript("OnFinished", function()
		if point.state == EssenceState.DEPLETING then
			self:ShowEmpty(point)
		end
	end)

	ResetFillingVisual(point)
	ResetBurstVisual(point)
	ResetDepleteVisual(point)
	point.Empty:Show()
	point.Full:Hide()

	return point
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
	if current < maxValue and UnitPartialPower then
		partial = UnitPartialPower("player", resource.powerEnum) or 0
	end

	return current, maxValue, (partial or 0) / 1000
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

	for i = 1, #self.points do
		self:StopPointAnimations(self.points[i])
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
		for i = 1, #self.points do
			StopPointOnUpdate(self.points[i])
		end
	end
end

function EvokerEssence:Sync()
	if not self.activeResource or not self.root then
		return
	end

	local current, maxValue, partialProgress = self:ReadEssenceState()
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
					self:StartFullBurst(point)
				elseif point.state ~= EssenceState.FULL and point.state ~= EssenceState.FULL_BURST then
					self:ShowFull(point)
				end
			elseif i == (current + 1) and current < maxValue then
				local alreadyFilling = point.Filling.FillingAnim:IsPlaying() or point.Full:IsShown()
				local outdatedProgress = false
				if alreadyFilling and point.Filling.FillingAnim.GetProgress then
					outdatedProgress = math_abs(partialProgress - point.Filling.FillingAnim:GetProgress()) > 0.1
				end

				if not alreadyFilling or outdatedProgress or point.state ~= EssenceState.FILLING then
					self:StartFilling(point, partialProgress)
				end
			else
				local wasFilling = point.Filling.FillingAnim:IsPlaying()
				if allowTransitions and (point.Full:IsShown() or point.Filling:IsShown() or point.FillDone:IsShown()) then
					self:StartDepleting(point, wasFilling)
				elseif point.state ~= EssenceState.EMPTY and point.state ~= EssenceState.DEPLETING then
					self:ShowEmpty(point)
				end
			end
		end
	end

	for i = maxValue + 1, #self.points do
		self.points[i]:Hide()
	end

	self.suppressTransitions = false
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
		suppressTransitions = true,
	}, EvokerEssence)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.EVOKER_ESSENCE, CreateEvokerEssence)
