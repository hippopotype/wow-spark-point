-- SparkPoint Monk Chi Class Resource System
-- Dedicated Monk implementation using Blizzard-style orb transitions and spacing rules.

local _, addon = ...
local ResourceModel = addon.ResourceModel
local ClassResourceSystems = addon.ClassResourceSystems

local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax

local DEFAULT_CHI_SPACING = 3
local TIGHT_CHI_SPACING = 2
local TIGHT_CHI_SPACING_THRESHOLD = 6
local POINT_SIZE = 21

local MonkChi = {}
MonkChi.__index = MonkChi

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

local function AddRotation(group, target, order, duration, degrees)
	local anim = group:CreateAnimation("Rotation")
	anim:SetTarget(target)
	anim:SetOrder(order or 1)
	anim:SetDuration(duration)
	anim:SetDegrees(degrees)
	return anim
end

local function AddTranslation(group, target, order, duration, offsetX, offsetY)
	local anim = group:CreateAnimation("Translation")
	anim:SetTarget(target)
	anim:SetOrder(order or 1)
	anim:SetDuration(duration)
	anim:SetOffset(offsetX or 0, offsetY or 0)
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

function MonkChi:ResetVisuals(point)
	StopGroup(point.activateAnim)
	StopGroup(point.deactivateAnim)
	SetAlpha(point.Chi_Icon, 0)
	SetAlpha(point.Chi_BG_Active, 0)
	for _, fxTexture in ipairs(point.fxTextures) do
		SetAlpha(fxTexture, 0)
	end
end

function MonkChi:ApplyActiveBase(point)
	SetAlpha(point.Chi_BG, 0)
	SetAlpha(point.Chi_BG_Active, 1)
	SetAlpha(point.Chi_Icon, 1)
end

function MonkChi:ApplyInactiveBase(point)
	SetAlpha(point.Chi_BG, 1)
	SetAlpha(point.Chi_BG_Active, 0)
	SetAlpha(point.Chi_Icon, 0)
end

function MonkChi:StopPointAnimations(point)
	self:ResetVisuals(point)
end

function MonkChi:CreatePoint(index)
	local point = CreateFrame("Frame", nil, self.root)
	point:SetSize(POINT_SIZE, POINT_SIZE)
	point.index = index
	point.active = nil

	point.Chi_BG = CreateAtlasTexture(point, "BACKGROUND", 0, "uf-chi-bg", true, 0, -2.5)
	point.Chi_BG_Glow = CreateAtlasTexture(point, "BACKGROUND", 0, "uf-chi-fx-bgglow", true, 0, -1)
	point.Chi_BG_Active = CreateAtlasTexture(point, "BACKGROUND", 0, "uf-chi-bg-active", true, 0, -2.5)
	point.FB_Wind_FX = CreateAtlasTexture(point, "ARTWORK", 0, "uf-chi-windfx", false, -1, 3)
	point.FB_Wind_FX:SetSize(37, 36)
	point.Chi_FX_2 = CreateAtlasTexture(point, "ARTWORK", 0, "uf-chi-fx-2", true)
	point.Chi_Icon = CreateAtlasTexture(point, "ARTWORK", 2, "uf-chi-icon", true)
	point.Chi_Deplete = CreateAtlasTexture(point, "ARTWORK", 2, "uf-chi-fx-deplete", true)
	point.FX_OuterGlow = CreateAtlasTexture(point, "ARTWORK", 3, "uf-chi-outerglow", true, 0, -0.5)
	point.FX_Smoke = CreateAtlasTexture(point, "ARTWORK", 3, "uf-chi-fx-smoke", true, 0, 6)
	point.Orb_Gleam = CreateAtlasTexture(point, "OVERLAY", 0, "uf-chi-orbgleam", true)

	point.fxTextures = {
		point.Chi_BG_Glow,
		point.FB_Wind_FX,
		point.Chi_FX_2,
		point.Chi_Deplete,
		point.FX_OuterGlow,
		point.FX_Smoke,
	}

	point.activateAnim = CreateAnimationGroup(point, true)
	AddFlipBook(point.activateAnim, point.FB_Wind_FX, 1, 0.57, 3, 6, 17)
	AddAlpha(point.activateAnim, point.FX_OuterGlow, 1, 0.17, 0, 1)
	AddAlpha(point.activateAnim, point.FX_OuterGlow, 1, 0.10, 1, 1, 0.17)
	AddAlpha(point.activateAnim, point.FX_OuterGlow, 1, 0.65, 1, 0, 0.18)
	AddAlpha(point.activateAnim, point.Chi_Icon, 1, 0.40, 0, 0)
	AddAlpha(point.activateAnim, point.Chi_Icon, 1, 0.43, 0, 1, 0.40)
	AddAlpha(point.activateAnim, point.Chi_FX_2, 1, 0.40, 0, 1)
	AddAlpha(point.activateAnim, point.Chi_FX_2, 1, 0.43, 1, 0, 0.40)
	AddRotation(point.activateAnim, point.Chi_FX_2, 1, 0.43, -65)
	AddAlpha(point.activateAnim, point.Chi_BG_Active, 1, 0.15, 0, 1)
	AddAlpha(point.activateAnim, point.Chi_BG, 1, 0.17, 1, 1)
	AddAlpha(point.activateAnim, point.Chi_BG, 1, 0.10, 1, 0, 0.17)
	AddAlpha(point.activateAnim, point.Chi_BG_Glow, 1, 0.17, 0, 1)
	AddAlpha(point.activateAnim, point.Chi_BG_Glow, 1, 0.33, 1, 1, 0.17)
	AddAlpha(point.activateAnim, point.Chi_BG_Glow, 1, 0.33, 1, 0, 0.50)

	point.deactivateAnim = CreateAnimationGroup(point, true)
	AddAlpha(point.deactivateAnim, point.FX_OuterGlow, 1, 0.33, 1, 1)
	AddAlpha(point.deactivateAnim, point.FX_OuterGlow, 1, 0.17, 1, 0, 0.33)
	AddAlpha(point.deactivateAnim, point.FX_Smoke, 1, 0.30, 1, 1)
	AddTranslation(point.deactivateAnim, point.FX_Smoke, 1, 0.50, 0, 5)
	AddAlpha(point.deactivateAnim, point.FX_Smoke, 1, 0.20, 1, 0, 0.30)
	AddAlpha(point.deactivateAnim, point.Chi_Icon, 1, 0.20, 1, 0)
	AddAlpha(point.deactivateAnim, point.Chi_Deplete, 1, 0.50, 1, 0)
	AddRotation(point.deactivateAnim, point.Chi_Deplete, 1, 0.50, -30)

	self:ApplyInactiveBase(point)
	self:ResetVisuals(point)
	point:Show()
	return point
end

function MonkChi:GetPoint(index)
	if self.points[index] then
		return self.points[index]
	end

	local point = self:CreatePoint(index)
	self.points[index] = point
	return point
end

function MonkChi:Initialize(parentFrame)
	self.parentFrame = parentFrame
	if self.root then
		return
	end

	self.root = CreateFrame("Frame", nil, parentFrame)
	self.root:SetPoint("CENTER")
	self.root:SetSize(1, 1)
	self.root:Hide()
end

function MonkChi:Shutdown()
	self.activeResource = nil
	self.resolved = nil
	self.visiblePointCount = 0
	self.suppressTransitions = true

	for i = 1, #self.points do
		local point = self.points[i]
		if point then
			self:StopPointAnimations(point)
			point.active = nil
			point:Hide()
		end
	end

	if self.root then
		self.root:Hide()
	end
end

function MonkChi:SetResource(resourceDef, resolved)
	self.activeResource = resourceDef
	self.resolved = resolved
	self.visiblePointCount = 0
	self.suppressTransitions = true

	for i = 1, #self.points do
		local point = self.points[i]
		if point then
			self:StopPointAnimations(point)
			point.active = nil
			self:ApplyInactiveBase(point)
		end
	end
end

function MonkChi:LayoutPoints(count)
	local spacing = count >= TIGHT_CHI_SPACING_THRESHOLD and TIGHT_CHI_SPACING or DEFAULT_CHI_SPACING
	if not self.root or count < 1 then
		self.root:SetSize(1, 1)
		if self.parentFrame then
			self.parentFrame:SetSize(1, 1)
		end
		return
	end

	local total = count * POINT_SIZE + (count - 1) * spacing
	local x0 = -(total / 2) + (POINT_SIZE / 2)

	for i = 1, count do
		local point = self:GetPoint(i)
		local x = x0 + (i - 1) * (POINT_SIZE + spacing)
		point:ClearAllPoints()
		point:SetPoint("CENTER", self.root, "CENTER", x, 0)
		point:Show()
	end

	for i = count + 1, #self.points do
		if self.points[i] then
			self.points[i]:Hide()
		end
	end

	self.root:SetSize(total, 60)
	if self.parentFrame then
		self.parentFrame:SetSize(total, 60)
	end
	self.visiblePointCount = count
end

function MonkChi:ApplyLayout()
	if not self.root then
		return
	end

	self.root:ClearAllPoints()
	self.root:SetPoint("CENTER")
	self.root:SetScale(1)
	self.root:SetAlpha(1)
end

function MonkChi:ApplyVisualOptions() end

function MonkChi:SetVisible(visible)
	if not self.root then
		return
	end

	if visible then
		self.root:Show()
	else
		self.root:Hide()
	end
end

function MonkChi:ReadState()
	if not self.activeResource or not self.activeResource.powerEnum then
		return 0, 0
	end

	return UnitPower("player", self.activeResource.powerEnum) or 0, UnitPowerMax("player", self.activeResource.powerEnum) or 0
end

function MonkChi:SetPointActive(point, active, skipTransitions)
	if point.active == active then
		return
	end

	if active then
		self:StopPointAnimations(point)
		self:ApplyInactiveBase(point)
		if skipTransitions then
			self:ApplyActiveBase(point)
		else
			SetAlpha(point.FB_Wind_FX, 1)
			RestartGroup(point.activateAnim)
		end
	else
		self:StopPointAnimations(point)
		if skipTransitions then
			self:ApplyInactiveBase(point)
		else
			SetAlpha(point.Chi_BG, 1)
			SetAlpha(point.Chi_Icon, 1)
			SetAlpha(point.Chi_Deplete, 1)
			RestartGroup(point.deactivateAnim)
		end
	end

	point.active = active
end

function MonkChi:Sync()
	if not self.activeResource then
		return
	end

	local current, maxPoints = self:ReadState()
	local skipTransitions = self.suppressTransitions

	if maxPoints < 1 then
		for i = 1, #self.points do
			if self.points[i] then
				self.points[i]:Hide()
			end
		end
		self.suppressTransitions = false
		return
	end

	if maxPoints ~= self.visiblePointCount then
		self:LayoutPoints(maxPoints)
		skipTransitions = true
	end

	for i = 1, maxPoints do
		local point = self:GetPoint(i)
		point:Show()
		self:SetPointActive(point, i <= current, skipTransitions)
	end

	self.suppressTransitions = false
end

function MonkChi:WantsEvent(event)
	return event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
end

function MonkChi:HandleEvent(event, unit, powerToken)
	if unit ~= "player" then
		return
	end

	if powerToken and self.activeResource and self.activeResource.powerToken and powerToken ~= self.activeResource.powerToken then
		return
	end

	self:Sync()
end

local function CreateMonkChi()
	return setmetatable({
		root = nil,
		parentFrame = nil,
		points = {},
		activeResource = nil,
		resolved = nil,
		visiblePointCount = 0,
		suppressTransitions = true,
	}, MonkChi)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.MONK_CHI, CreateMonkChi)
