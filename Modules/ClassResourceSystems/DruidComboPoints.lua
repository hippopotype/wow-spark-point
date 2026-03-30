-- SparkPoint Druid Combo Points Class Resource System
-- Dedicated Druid implementation with cat-form visuals driven by the shared resource model.

local _, addon = ...
local ResourceModel = addon.ResourceModel
local ClassResourceSystems = addon.ClassResourceSystems

local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax

local POINT_SIZE = 20
local POINT_SPACING = 4

local DruidComboPoints = {}
DruidComboPoints.__index = DruidComboPoints

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

function DruidComboPoints:Initialize(parentFrame)
	self.parentFrame = parentFrame
	if self.root then
		return
	end

	self.root = CreateFrame("Frame", nil, parentFrame)
	self.root:SetPoint("CENTER")
	self.root:SetSize(1, 1)
	self.root:Hide()
end

function DruidComboPoints:Shutdown()
	self.activeResource = nil
	self.resolved = nil
	self.pointMax = 0

	for i = 1, #self.points do
		local point = self.points[i]
		if point then
			self:StopPointAnimations(point)
			point.isActive = nil
			point:Hide()
		end
	end

	if self.root then
		self.root:Hide()
	end
end

function DruidComboPoints:ResetVisuals(point)
	StopGroup(point.activateAnim)
	StopGroup(point.deactivateAnim)
	point.FB_Slash:Hide()
	SetAlpha(point.BG_Glow, 0)
	SetAlpha(point.Point_Deplete, 0)
	SetAlpha(point.FX_RingGlow, 0)
	SetAlpha(point.Smoke, 0)
	point.Smoke:ClearAllPoints()
	point.Smoke:SetPoint("CENTER", 0, 15)
end

function DruidComboPoints:ApplyInactiveBase(point)
	SetAlpha(point.BG_Active, 0)
	SetAlpha(point.BG_Inactive, 1)
	SetAlpha(point.Point_Icon, 0)
end

function DruidComboPoints:ApplyActiveBase(point)
	SetAlpha(point.BG_Active, 1)
	SetAlpha(point.BG_Inactive, 0)
	SetAlpha(point.Point_Icon, 1)
end

function DruidComboPoints:StopPointAnimations(point)
	self:ResetVisuals(point)
end

function DruidComboPoints:CreatePoint(index)
	local point = CreateFrame("Frame", nil, self.root)
	point:SetSize(POINT_SIZE, POINT_SIZE)
	point.index = index
	point.isActive = nil

	point.BG_Shadow = CreateAtlasTexture(point, "BACKGROUND", 1, "UF-DruidCP-BG-Shadow", true, 0, -2)
	point.BG_Active = CreateAtlasTexture(point, "BACKGROUND", 1, "UF-DruidCP-BG-Active", true)
	point.BG_Inactive = CreateAtlasTexture(point, "BACKGROUND", 1, "UF-DruidCP-BG-Dis", true)
	point.BG_Glow = CreateAtlasTexture(point, "BACKGROUND", 2, "UF-DruidCP-BG-Glow", true)
	point.Point_Deplete = CreateAtlasTexture(point, "ARTWORK", 0, "UF-DruidCP-Deplete", true)
	point.Point_Icon = CreateAtlasTexture(point, "ARTWORK", 0, "UF-DruidCP-Icon", true)
	point.FX_RingGlow = CreateAtlasTexture(point, "OVERLAY", 0, "UF-DruidCP-Ring-Glow", true)
	point.FB_Slash = CreateAtlasTexture(point, "OVERLAY", 0, "UF-DruidCP-Slash", false, 1, 3)
	point.FB_Slash:SetSize(26, 41)
	point.Smoke = CreateAtlasTexture(point, "OVERLAY", 0, "UF-DruidCP-Smoke", true, 0, 15)

	point.activateAnim = CreateAnimationGroup(point, true)
	AddAlpha(point.activateAnim, point.Point_Icon, 1, 0.10, 0, 0.5)
	AddAlpha(point.activateAnim, point.Point_Icon, 1, 0.20, 0.5, 1, 0.47)
	AddFlipBook(point.activateAnim, point.FB_Slash, 1, 1.0, 3, 8, 20)
	AddAlpha(point.activateAnim, point.FX_RingGlow, 1, 0.27, 0, 1)
	AddAlpha(point.activateAnim, point.FX_RingGlow, 1, 0.47, 1, 0, 0.27)
	AddAlpha(point.activateAnim, point.BG_Active, 1, 0.27, 0, 0)
	AddAlpha(point.activateAnim, point.BG_Active, 1, 0.01, 0, 1, 0.27)
	AddAlpha(point.activateAnim, point.BG_Inactive, 1, 0.27, 1, 1)
	AddAlpha(point.activateAnim, point.BG_Inactive, 1, 0.01, 1, 0, 0.27)
	AddAlpha(point.activateAnim, point.BG_Glow, 1, 0.17, 0, 0)
	AddAlpha(point.activateAnim, point.BG_Glow, 1, 0.13, 0, 1, 0.17)
	AddAlpha(point.activateAnim, point.BG_Glow, 1, 0.40, 1, 0, 0.30)
	point.activateAnim:SetScript("OnPlay", function()
		point.FB_Slash:Show()
	end)
	point.activateAnim:SetScript("OnFinished", function()
		point.FB_Slash:Hide()
	end)

	point.deactivateAnim = CreateAnimationGroup(point, true)
	AddAlpha(point.deactivateAnim, point.Smoke, 1, 0.33, 1, 1)
	AddAlpha(point.deactivateAnim, point.Smoke, 1, 0.23, 1, 0, 0.33)
	AddTranslation(point.deactivateAnim, point.Smoke, 1, 0.56, 0, 7)
	AddAlpha(point.deactivateAnim, point.FX_RingGlow, 1, 0.43, 1, 1)
	AddAlpha(point.deactivateAnim, point.FX_RingGlow, 1, 0.23, 1, 0, 0.43)
	AddAlpha(point.deactivateAnim, point.Point_Icon, 1, 0.20, 1, 0)
	AddAlpha(point.deactivateAnim, point.Point_Deplete, 1, 0.23, 1, 1)
	AddAlpha(point.deactivateAnim, point.Point_Deplete, 1, 0.20, 1, 0, 0.23)

	self:ApplyInactiveBase(point)
	self:ResetVisuals(point)
	point:Show()
	return point
end

function DruidComboPoints:GetPoint(index)
	if self.points[index] then
		return self.points[index]
	end

	local point = self:CreatePoint(index)
	self.points[index] = point
	return point
end

function DruidComboPoints:SetResource(resourceDef, resolved)
	self.activeResource = resourceDef
	self.resolved = resolved
	self.pointMax = 0

	for i = 1, #self.points do
		local point = self.points[i]
		if point then
			self:StopPointAnimations(point)
			point.isActive = nil
			self:ApplyInactiveBase(point)
		end
	end
end

function DruidComboPoints:LayoutPoints(count)
	if not self.root or count < 1 then
		if self.parentFrame then
			self.parentFrame:SetSize(1, 1)
		end
		return
	end

	local total = count * POINT_SIZE + (count - 1) * POINT_SPACING
	local x0 = -(total / 2) + (POINT_SIZE / 2)

	for i = 1, count do
		local point = self:GetPoint(i)
		local x = x0 + (i - 1) * (POINT_SIZE + POINT_SPACING)
		point:ClearAllPoints()
		point:SetPoint("CENTER", self.root, "CENTER", x, 0)
		point:Show()
	end

	for i = count + 1, #self.points do
		if self.points[i] then
			self.points[i]:Hide()
		end
	end

	self.root:SetSize(total, POINT_SIZE)
	if self.parentFrame then
		self.parentFrame:SetSize(total, POINT_SIZE)
	end
	self.pointMax = count
end

function DruidComboPoints:ApplyLayout()
	if not self.root then
		return
	end

	self.root:ClearAllPoints()
	self.root:SetPoint("CENTER")
	self.root:SetScale(1)
	self.root:SetAlpha(1)
end

function DruidComboPoints:ApplyVisualOptions() end

function DruidComboPoints:SetVisible(visible)
	if not self.root then
		return
	end

	if visible then
		self.root:Show()
	else
		self.root:Hide()
	end
end

function DruidComboPoints:ReadState()
	if not self.activeResource or not self.activeResource.powerEnum then
		return 0, 0
	end

	return UnitPower("player", self.activeResource.powerEnum) or 0, UnitPowerMax("player", self.activeResource.powerEnum) or 0
end

function DruidComboPoints:ApplyPointState(point, isActive)
	if point.isActive == isActive then
		return
	end

	if isActive then
		self:StopPointAnimations(point)
		self:ApplyInactiveBase(point)
		point.FB_Slash:Show()
		RestartGroup(point.activateAnim)
	else
		self:StopPointAnimations(point)
		SetAlpha(point.BG_Active, 1)
		SetAlpha(point.BG_Inactive, 0)
		SetAlpha(point.Point_Icon, 1)
		SetAlpha(point.Point_Deplete, 1)
		SetAlpha(point.FX_RingGlow, 1)
		SetAlpha(point.Smoke, 1)
		RestartGroup(point.deactivateAnim)
	end

	point.isActive = isActive
end

function DruidComboPoints:Sync()
	if not self.activeResource then
		return
	end

	local current, maxPoints = self:ReadState()
	if maxPoints < 1 then
		for i = 1, #self.points do
			if self.points[i] then
				self.points[i]:Hide()
			end
		end
		return
	end

	if maxPoints ~= self.pointMax then
		self:LayoutPoints(maxPoints)
	end

	for i = 1, maxPoints do
		local point = self:GetPoint(i)
		point:Show()
		self:ApplyPointState(point, i <= current)
	end
end

function DruidComboPoints:WantsEvent(event)
	return event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
end

function DruidComboPoints:HandleEvent(event, unit, powerToken)
	if unit ~= "player" then
		return
	end

	if powerToken and self.activeResource and self.activeResource.powerToken and powerToken ~= self.activeResource.powerToken then
		return
	end

	self:Sync()
end

local function CreateDruidComboPoints()
	return setmetatable({
		root = nil,
		parentFrame = nil,
		points = {},
		pointMax = 0,
		activeResource = nil,
		resolved = nil,
	}, DruidComboPoints)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.DRUID_COMBO_POINTS, CreateDruidComboPoints)
