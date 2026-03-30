-- SparkPoint Mage Arcane Charges Class Resource System
-- Dedicated Arcane Charge implementation using Blizzard-style charge transitions.

local _, addon = ...
local ResourceModel = addon.ResourceModel
local ClassResourceSystems = addon.ClassResourceSystems

local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax

local CHARGE_SIZE = 21
local CHARGE_SPACING = 10

local MageArcaneCharges = {}
MageArcaneCharges.__index = MageArcaneCharges

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

local function AddFlipBook(group, target, order, duration, rows, columns, frames)
	local anim = group:CreateAnimation("FlipBook")
	anim:SetTarget(target)
	anim:SetOrder(order or 1)
	anim:SetDuration(duration)
	anim:SetFlipBookRows(rows)
	anim:SetFlipBookColumns(columns)
	anim:SetFlipBookFrames(frames)
	anim:SetFlipBookFrameWidth(0)
	anim:SetFlipBookFrameHeight(0)
	return anim
end

local function RestartGroup(group)
	if not group then
		return
	end

	if group.Restart then
		group:Restart()
	else
		group:Play()
	end
end

local function StopGroup(group)
	if group and group:IsPlaying() then
		group:Stop()
	end
end

local function SetAlpha(region, alpha)
	if region then
		region:SetAlpha(alpha or 0)
	end
end

local function CreateAtlasTexture(parent, layer, subLevel, atlas, useAtlasSize, x, y)
	local texture = parent:CreateTexture(nil, layer, nil, subLevel or 0)
	texture:SetPoint("CENTER", x or 0, y or 0)
	texture:SetAtlas(atlas, useAtlasSize and true or false)
	return texture
end

function MageArcaneCharges:ResetVisuals(point)
	StopGroup(point.activateAnim)
	StopGroup(point.deactivateAnim)

	for _, texture in ipairs(point.fxTextures) do
		SetAlpha(texture, 0)
	end
end

function MageArcaneCharges:ApplyActiveBase(point)
	SetAlpha(point.ArcaneIcon, 1)
end

function MageArcaneCharges:PrimeDeactivateBase(point)
	SetAlpha(point.ArcaneIcon, 1)
	SetAlpha(point.ArcaneFlare, 1)
	SetAlpha(point.ArcaneOuterFX, 1)
	SetAlpha(point.FrameGlow, 1)
end

function MageArcaneCharges:CreatePoint(index)
	local point = CreateFrame("Frame", nil, self.root)
	point:SetSize(CHARGE_SIZE, CHARGE_SIZE)
	point.index = index
	point.active = nil

	point.ArcaneBGShadow = CreateAtlasTexture(point, "BACKGROUND", 0, "UF-Arcane-BGShadow", true, 0, -2.5)
	point.ArcaneBG = CreateAtlasTexture(point, "BACKGROUND", 0, "UF-Arcane-BG", true)
	point.ArcaneCircle = CreateAtlasTexture(point, "BORDER", 0, "UF-Arcane-MagicCirc", true)
	point.ArcaneTriangle = CreateAtlasTexture(point, "BORDER", 0, "UF-Arcane-MagicTriangle", true)
	point.ArcaneSquare = CreateAtlasTexture(point, "BORDER", 0, "UF-Arcane-MagicSquare", true)
	point.ArcaneDiamond = CreateAtlasTexture(point, "BORDER", 0, "UF-Arcane-MagicDiamond", true)
	point.ArcaneIcon = CreateAtlasTexture(point, "ARTWORK", 0, "UF-Arcane-Icon", true)
	point.Orb = CreateAtlasTexture(point, "ARTWORK", 0, "UF-Arcane-Orb", true)
	point.ArcaneFlare = CreateAtlasTexture(point, "OVERLAY", 0, "UF-Arcane-Flare", true)
	point.FBArcaneFX = CreateAtlasTexture(point, "OVERLAY", 0, "UF-Arcane-ShockFX", false, 0, 1)
	point.FBArcaneFX:SetSize(50, 45)
	point.ArcaneOuterFX = CreateAtlasTexture(point, "OVERLAY", 0, "UF-Arcane-OuterFX", true)
	point.FrameGlow = CreateAtlasTexture(point, "OVERLAY", 0, "UF-Arcane-FrameGlow", true)

	point.fxTextures = {
		point.ArcaneCircle,
		point.ArcaneTriangle,
		point.ArcaneSquare,
		point.ArcaneDiamond,
		point.ArcaneIcon,
		point.ArcaneFlare,
		point.FBArcaneFX,
		point.ArcaneOuterFX,
		point.FrameGlow,
	}

	point.activateAnim = CreateAnimationGroup(point, true)
	AddAlpha(point.activateAnim, point.FrameGlow, 1, 0.17, 0, 0.45)
	AddAlpha(point.activateAnim, point.FrameGlow, 1, 0.60, 0.45, 0.70, 0.17)
	AddAlpha(point.activateAnim, point.FrameGlow, 1, 0.20, 0.70, 0.70, 0.77)
	AddAlpha(point.activateAnim, point.FrameGlow, 1, 0.20, 0.70, 0, 0.97)
	AddAlpha(point.activateAnim, point.FBArcaneFX, 1, 0, 0, 1)
	AddFlipBook(point.activateAnim, point.FBArcaneFX, 1, 1.0, 5, 6, 28)
	AddAlpha(point.activateAnim, point.ArcaneIcon, 1, 0.10, 0, 0.5)
	AddAlpha(point.activateAnim, point.ArcaneIcon, 1, 0.13, 0.5, 1, 0.47)
	AddAlpha(point.activateAnim, point.ArcaneFlare, 1, 0.23, 0, 0)
	AddAlpha(point.activateAnim, point.ArcaneFlare, 1, 0.23, 0, 1, 0.23)
	AddAlpha(point.activateAnim, point.ArcaneFlare, 1, 0.27, 1, 0.65, 0.46)
	AddAlpha(point.activateAnim, point.ArcaneFlare, 1, 0.27, 0.65, 0, 0.73)
	AddAlpha(point.activateAnim, point.ArcaneDiamond, 1, 0.33, 0, 1)
	AddAlpha(point.activateAnim, point.ArcaneDiamond, 1, 0.57, 1, 0, 0.33)
	AddAlpha(point.activateAnim, point.ArcaneSquare, 1, 0.27, 0, 1)
	AddAlpha(point.activateAnim, point.ArcaneSquare, 1, 0.63, 1, 0, 0.27)
	AddAlpha(point.activateAnim, point.ArcaneCircle, 1, 0.17, 0, 1)
	AddAlpha(point.activateAnim, point.ArcaneCircle, 1, 0.33, 1, 1, 0.17)
	AddAlpha(point.activateAnim, point.ArcaneCircle, 1, 0.50, 1, 0, 0.50)
	AddAlpha(point.activateAnim, point.ArcaneTriangle, 1, 0.17, 0, 0)
	AddAlpha(point.activateAnim, point.ArcaneTriangle, 1, 0.10, 0, 1, 0.17)
	AddAlpha(point.activateAnim, point.ArcaneTriangle, 1, 0.53, 1, 0, 0.27)

	point.deactivateAnim = CreateAnimationGroup(point, true)
	AddAlpha(point.deactivateAnim, point.FrameGlow, 1, 0.08, 0, 1)
	AddAlpha(point.deactivateAnim, point.FrameGlow, 1, 0.035, 1, 1, 0.08)
	AddAlpha(point.deactivateAnim, point.FrameGlow, 1, 0.235, 1, 0, 0.12)
	AddAlpha(point.deactivateAnim, point.ArcaneIcon, 1, 0.15, 1, 0)
	AddAlpha(point.deactivateAnim, point.ArcaneFlare, 1, 0.25, 1, 0)
	AddAlpha(point.deactivateAnim, point.ArcaneOuterFX, 1, 0.15, 1, 1)
	AddAlpha(point.deactivateAnim, point.ArcaneOuterFX, 1, 0.235, 1, 0, 0.15)

	self:ResetVisuals(point)
	point:Show()
	return point
end

function MageArcaneCharges:GetPoint(index)
	if self.points[index] then
		return self.points[index]
	end

	local point = self:CreatePoint(index)
	self.points[index] = point
	return point
end

function MageArcaneCharges:Initialize(parentFrame)
	self.parentFrame = parentFrame
	if self.root then
		return
	end

	self.root = CreateFrame("Frame", nil, parentFrame)
	self.root:SetPoint("CENTER")
	self.root:SetSize(1, 1)
	self.root:Hide()
end

function MageArcaneCharges:Shutdown()
	self.activeResource = nil
	self.resolved = nil
	self.pointMax = 0
	self.suppressTransitions = true

	for i = 1, #self.points do
		local point = self.points[i]
		if point then
			self:ResetVisuals(point)
			point.active = nil
			point:Hide()
		end
	end

	if self.root then
		self.root:Hide()
	end
end

function MageArcaneCharges:SetResource(resourceDef, resolved)
	self.activeResource = resourceDef
	self.resolved = resolved
	self.pointMax = 0
	self.suppressTransitions = true

	for i = 1, #self.points do
		local point = self.points[i]
		if point then
			self:ResetVisuals(point)
			point.active = nil
		end
	end
end

function MageArcaneCharges:LayoutPoints(count)
	if not self.root or count < 1 then
		self.root:SetSize(1, 1)
		if self.parentFrame then
			self.parentFrame:SetSize(1, 1)
		end
		return
	end

	local total = count * CHARGE_SIZE + (count - 1) * CHARGE_SPACING
	local x0 = -(total / 2) + (CHARGE_SIZE / 2)

	for i = 1, count do
		local point = self:GetPoint(i)
		point:ClearAllPoints()
		point:SetPoint("CENTER", self.root, "CENTER", x0 + (i - 1) * (CHARGE_SIZE + CHARGE_SPACING), 0)
		point:Show()
	end

	for i = count + 1, #self.points do
		if self.points[i] then
			self.points[i]:Hide()
		end
	end

	self.root:SetSize(total, CHARGE_SIZE)
	if self.parentFrame then
		self.parentFrame:SetSize(total, CHARGE_SIZE)
	end
	self.pointMax = count
end

function MageArcaneCharges:ApplyLayout()
	if not self.root then
		return
	end

	self.root:ClearAllPoints()
	self.root:SetPoint("CENTER")
	self:LayoutPoints(self.activeResource and (self.activeResource.maxCount or 0) or 0)
end

function MageArcaneCharges:ApplyVisualOptions() end

function MageArcaneCharges:SetVisible(visible)
	if not self.root then
		return
	end

	if visible then
		self.root:Show()
	else
		self.root:Hide()
	end
end

function MageArcaneCharges:ReadState()
	local resource = self.activeResource
	if not resource or not resource.powerEnum then
		return 0, 0
	end

	return UnitPower("player", resource.powerEnum, true) or 0, UnitPowerMax("player", resource.powerEnum) or 0
end

function MageArcaneCharges:SetPointActive(point, isActive, skipTransition)
	if point.active == isActive and not skipTransition then
		return
	end

	self:ResetVisuals(point)

	if isActive then
		if skipTransition then
			self:ApplyActiveBase(point)
		else
			RestartGroup(point.activateAnim)
		end
	else
		if not skipTransition then
			self:PrimeDeactivateBase(point)
			RestartGroup(point.deactivateAnim)
		end
	end

	point.active = isActive
end

function MageArcaneCharges:Sync()
	if not self.activeResource then
		return
	end

	local current, maxPoints = self:ReadState()
	local skipTransition = self.suppressTransitions

	if maxPoints ~= self.pointMax then
		self:LayoutPoints(maxPoints)
		skipTransition = true
	end

	for i = 1, maxPoints do
		local point = self:GetPoint(i)
		point:Show()
		self:SetPointActive(point, i <= current, skipTransition)
	end

	for i = maxPoints + 1, #self.points do
		if self.points[i] then
			self.points[i]:Hide()
		end
	end

	self.suppressTransitions = false
end

function MageArcaneCharges:WantsEvent(event)
	return event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
end

function MageArcaneCharges:HandleEvent(event, unit, powerToken)
	if unit ~= "player" then
		return
	end

	if powerToken and self.activeResource and self.activeResource.powerToken and powerToken ~= self.activeResource.powerToken then
		return
	end

	self:Sync()
end

local function CreateMageArcaneCharges()
	return setmetatable({
		root = nil,
		parentFrame = nil,
		points = {},
		pointMax = 0,
		activeResource = nil,
		resolved = nil,
		suppressTransitions = true,
	}, MageArcaneCharges)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.MAGE_ARCANE_CHARGES, CreateMageArcaneCharges)
