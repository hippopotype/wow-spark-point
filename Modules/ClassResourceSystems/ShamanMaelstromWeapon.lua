-- SparkPoint Shaman Maelstrom Weapon Class Resource System
-- Dedicated Enhancement implementation using SparkPoint pip art and aura-driven low/high states.

local _, addon = ...
local API = addon.API
local ResourceModel = addon.ResourceModel
local ResourceColors = addon.ResourceColors
local ClassResourceSystems = addon.ClassResourceSystems
local GetDBColor = addon.GetDBColor
local GetDBValue = addon.GetDBValue

local PIP_TEXTURE_FRAME_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\class_resource_frame.png"
local PIP_TEXTURE_BG_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\class_resource_background.png"
local PIP_TEXTURE_FILL_PATH = "Interface\\AddOns\\SparkPoint\\Textures\\class_resource_fill.png"
local PIP_TEXTURE_FALLBACK = "Interface\\Buttons\\WHITE8x8"

local POINT_SIZE = 18
local POINT_SPACING = 4

local STATE_EMPTY = 1
local STATE_CHARGED = 2
local STATE_SURGED = 3

local ShamanMaelstromWeapon = {}
ShamanMaelstromWeapon.__index = ShamanMaelstromWeapon

local function Clamp01(value)
	if value == nil then
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

local function SetTextureSmooth(tex, path)
	local ok = pcall(tex.SetTexture, tex, path, nil, nil, "TRILINEAR")
	if not ok then
		tex:SetTexture(path)
	end
	if tex.SetSnapToPixelGrid then
		tex:SetSnapToPixelGrid(false)
	end
	if tex.SetTexelSnappingBias then
		tex:SetTexelSnappingBias(0)
	end
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

local function AddScale(group, target, order, duration, scaleX, scaleY, startDelay)
	local anim = group:CreateAnimation("Scale")
	anim:SetTarget(target)
	anim:SetOrder(order or 1)
	anim:SetDuration(duration)
	anim:SetScale(scaleX or 1, scaleY or scaleX or 1)
	anim:SetOrigin("CENTER", 0, 0)
	if startDelay and startDelay > 0 then
		anim:SetStartDelay(startDelay)
	end
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

local function MixToWhite(r, g, b, amount)
	amount = Clamp01(amount or 0)
	return r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount
end

local function LerpColor(r1, g1, b1, a1, r2, g2, b2, a2, t)
	t = Clamp01(t or 0)
	return r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t, a1 + ((a2 or a1) - a1) * t
end

local function GetChargedColor(resource)
	local fillSource = tostring(GetDBValue("classresource_fillColorSource") or "CLASS")
	if fillSource == "CLASS" and API and API.GetPlayerClassColor then
		return API.GetPlayerClassColor()
	end

	if fillSource == "RESOURCE" and ResourceColors and ResourceColors.GetColor then
		local color = ResourceColors:GetColor(resource)
		return color.r, color.g, color.b, color.a
	end

	if GetDBValue("classresource_fillColor") then
		return GetDBColor("classresource_fillColor")
	end

	local fillColor = resource and resource.fillColor
	if fillColor then
		return fillColor.r, fillColor.g, fillColor.b, fillColor.a
	end

	return 1, 1, 1, 1
end

local function GetEmptyColor(resource)
	local br, bg, bb, ba = GetDBColor("classresource_backgroundColor")
	if br == nil then
		br, bg, bb, ba = 1, 1, 1, 1
	end

	local emptyColor = resource and resource.emptyColor
	if not emptyColor then
		return br, bg, bb, ba
	end

	local usingDefaultBackgroundTint = br == 1 and bg == 1 and bb == 1 and ba == 1
	if usingDefaultBackgroundTint then
		return emptyColor.r, emptyColor.g, emptyColor.b, emptyColor.a
	end

	return br, bg, bb, emptyColor.a * ba
end

local function GetSurgedColor(resource, chargedR, chargedG, chargedB, chargedA)
	local fillSource = tostring(GetDBValue("classresource_fillColorSource") or "CLASS")
	local empowerColor = resource and resource.empowerColor
	if empowerColor then
		if fillSource == "CUSTOM" and GetDBValue("classresource_fillColor") then
			return LerpColor(chargedR, chargedG, chargedB, chargedA, empowerColor.r, empowerColor.g, empowerColor.b, empowerColor.a, 0.65)
		end

		return empowerColor.r, empowerColor.g, empowerColor.b, empowerColor.a
	end

	local surgedR, surgedG, surgedB = MixToWhite(chargedR, chargedG, chargedB, 0.35)
	return surgedR, surgedG, surgedB, chargedA
end

local function NormalizeAuraStacks(auraData)
	if not auraData then
		return 0
	end

	local applications = auraData.applications
	if type(applications) ~= "number" then
		return 0
	end

	return applications
end

function ShamanMaelstromWeapon:StopPointAnimations(point)
	StopGroup(point.chargedGainAnim)
	StopGroup(point.chargedSpendAnim)
	StopGroup(point.surgedGainAnim)
	StopGroup(point.surgedSpendAnim)
	StopGroup(point.emptyToSurgedAnim)
	StopGroup(point.surgedToEmptyAnim)
	StopGroup(point.thresholdPulseAnim)
	SetAlpha(point.ChargedPulse, 0)
	SetAlpha(point.SurgedPulse, 0)
	SetAlpha(point.SpendPulse, 0)
	point.ChargedPulse:SetScale(1)
	point.SurgedPulse:SetScale(1)
	point.SpendPulse:SetScale(1)
end

function ShamanMaelstromWeapon:ApplyVisualState(point, state)
	if state == STATE_SURGED then
		SetAlpha(point.BaseFill, 1)
		SetAlpha(point.SurgeFill, 1)
	elseif state == STATE_CHARGED then
		SetAlpha(point.BaseFill, 1)
		SetAlpha(point.SurgeFill, 0)
	else
		SetAlpha(point.BaseFill, 0)
		SetAlpha(point.SurgeFill, 0)
	end

	SetAlpha(point.Background, 1)
	SetAlpha(point.Frame, 0.95)
	SetAlpha(point.ChargedPulse, 0)
	SetAlpha(point.SurgedPulse, 0)
	SetAlpha(point.SpendPulse, 0)
	point.ChargedPulse:SetScale(1)
	point.SurgedPulse:SetScale(1)
	point.SpendPulse:SetScale(1)
	point.state = state
end

function ShamanMaelstromWeapon:PlayTransition(point, previousState, nextState)
	if previousState == nextState then
		self:ApplyVisualState(point, nextState)
		return
	end

	self:StopPointAnimations(point)

	if previousState == STATE_EMPTY and nextState == STATE_CHARGED then
		self:ApplyVisualState(point, STATE_EMPTY)
		RestartGroup(point.chargedGainAnim)
	elseif previousState == STATE_CHARGED and nextState == STATE_EMPTY then
		self:ApplyVisualState(point, STATE_CHARGED)
		RestartGroup(point.chargedSpendAnim)
	elseif previousState == STATE_CHARGED and nextState == STATE_SURGED then
		self:ApplyVisualState(point, STATE_CHARGED)
		RestartGroup(point.surgedGainAnim)
	elseif previousState == STATE_SURGED and nextState == STATE_CHARGED then
		self:ApplyVisualState(point, STATE_SURGED)
		RestartGroup(point.surgedSpendAnim)
	elseif previousState == STATE_EMPTY and nextState == STATE_SURGED then
		self:ApplyVisualState(point, STATE_EMPTY)
		RestartGroup(point.emptyToSurgedAnim)
	elseif previousState == STATE_SURGED and nextState == STATE_EMPTY then
		self:ApplyVisualState(point, STATE_SURGED)
		RestartGroup(point.surgedToEmptyAnim)
	else
		self:ApplyVisualState(point, nextState)
	end

	point.state = nextState
end

function ShamanMaelstromWeapon:StateForIndex(stacks, index)
	local surgeThreshold = (self.activeResource and self.activeResource.empowerThreshold) or 5
	local surgedCount = math.max(stacks - surgeThreshold, 0)
	local chargedCount = math.min(stacks, self.activeResource and (self.activeResource.maxCount or 5) or 5)

	if index <= surgedCount then
		return STATE_SURGED
	end

	if index <= chargedCount then
		return STATE_CHARGED
	end

	return STATE_EMPTY
end

function ShamanMaelstromWeapon:ConfigurePoint(point)
	SetTextureSmooth(point.Background, PIP_TEXTURE_BG_PATH)
	SetTextureSmooth(point.BaseFill, PIP_TEXTURE_FILL_PATH)
	SetTextureSmooth(point.SurgeFill, PIP_TEXTURE_FILL_PATH)
	SetTextureSmooth(point.Frame, PIP_TEXTURE_FRAME_PATH)
	SetTextureSmooth(point.ChargedPulse, PIP_TEXTURE_FILL_PATH)
	SetTextureSmooth(point.SurgedPulse, PIP_TEXTURE_FILL_PATH)
	SetTextureSmooth(point.SpendPulse, PIP_TEXTURE_FILL_PATH)

	if not point.Background:GetTexture() then
		point.Background:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not point.BaseFill:GetTexture() then
		point.BaseFill:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not point.SurgeFill:GetTexture() then
		point.SurgeFill:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not point.Frame:GetTexture() then
		point.Frame:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not point.ChargedPulse:GetTexture() then
		point.ChargedPulse:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not point.SurgedPulse:GetTexture() then
		point.SurgedPulse:SetTexture(PIP_TEXTURE_FALLBACK)
	end
	if not point.SpendPulse:GetTexture() then
		point.SpendPulse:SetTexture(PIP_TEXTURE_FALLBACK)
	end

	local chargedR, chargedG, chargedB, chargedA = GetChargedColor(self.activeResource)
	local emptyR, emptyG, emptyB, emptyA = GetEmptyColor(self.activeResource)
	local surgedR, surgedG, surgedB, surgedA = GetSurgedColor(self.activeResource, chargedR, chargedG, chargedB, chargedA)
	local chargedPulseR, chargedPulseG, chargedPulseB = MixToWhite(chargedR, chargedG, chargedB, 0.45)
	local surgedPulseR, surgedPulseG, surgedPulseB = MixToWhite(surgedR, surgedG, surgedB, 0.25)

	point.Background:SetVertexColor(emptyR, emptyG, emptyB, emptyA)
	point.BaseFill:SetVertexColor(chargedR, chargedG, chargedB, chargedA)
	point.SurgeFill:SetVertexColor(surgedR, surgedG, surgedB, surgedA)
	point.Frame:SetVertexColor(1, 1, 1, 0.95)
	point.ChargedPulse:SetVertexColor(chargedPulseR, chargedPulseG, chargedPulseB, chargedA)
	point.SurgedPulse:SetVertexColor(surgedPulseR, surgedPulseG, surgedPulseB, surgedA)
	point.SpendPulse:SetVertexColor(surgedPulseR, surgedPulseG, surgedPulseB, surgedA)
end

function ShamanMaelstromWeapon:CreatePoint(index)
	local point = CreateFrame("Frame", nil, self.root)
	point:SetSize(POINT_SIZE, POINT_SIZE)
	point.index = index
	point.state = STATE_EMPTY

	point.Background = point:CreateTexture(nil, "BACKGROUND", nil, 0)
	point.Background:SetPoint("CENTER")
	point.Background:SetSize(POINT_SIZE, POINT_SIZE)

	point.BaseFill = point:CreateTexture(nil, "ARTWORK", nil, 0)
	point.BaseFill:SetPoint("CENTER")
	point.BaseFill:SetSize(POINT_SIZE, POINT_SIZE)

	point.SurgeFill = point:CreateTexture(nil, "ARTWORK", nil, 1)
	point.SurgeFill:SetPoint("CENTER")
	point.SurgeFill:SetSize(POINT_SIZE, POINT_SIZE)
	point.SurgeFill:SetBlendMode("ADD")

	point.Frame = point:CreateTexture(nil, "OVERLAY", nil, 0)
	point.Frame:SetPoint("CENTER")
	point.Frame:SetSize(POINT_SIZE, POINT_SIZE)

	point.ChargedPulse = point:CreateTexture(nil, "OVERLAY", nil, 1)
	point.ChargedPulse:SetPoint("CENTER")
	point.ChargedPulse:SetSize(POINT_SIZE + 4, POINT_SIZE + 4)
	point.ChargedPulse:SetBlendMode("ADD")

	point.SurgedPulse = point:CreateTexture(nil, "OVERLAY", nil, 2)
	point.SurgedPulse:SetPoint("CENTER")
	point.SurgedPulse:SetSize(POINT_SIZE + 6, POINT_SIZE + 6)
	point.SurgedPulse:SetBlendMode("ADD")

	point.SpendPulse = point:CreateTexture(nil, "OVERLAY", nil, 3)
	point.SpendPulse:SetPoint("CENTER")
	point.SpendPulse:SetSize(POINT_SIZE + 8, POINT_SIZE + 8)
	point.SpendPulse:SetBlendMode("ADD")

	point.chargedGainAnim = CreateAnimationGroup(point, true)
	AddAlpha(point.chargedGainAnim, point.BaseFill, 1, 0.14, 0, 1)
	AddAlpha(point.chargedGainAnim, point.ChargedPulse, 1, 0.08, 0, 0.90)
	AddAlpha(point.chargedGainAnim, point.ChargedPulse, 1, 0.20, 0.90, 0, 0.08)
	AddScale(point.chargedGainAnim, point.ChargedPulse, 1, 0.28, 1.18, 1.18)

	point.chargedSpendAnim = CreateAnimationGroup(point, true)
	AddAlpha(point.chargedSpendAnim, point.SpendPulse, 1, 0.08, 0, 0.65)
	AddAlpha(point.chargedSpendAnim, point.SpendPulse, 1, 0.18, 0.65, 0, 0.08)
	AddScale(point.chargedSpendAnim, point.SpendPulse, 1, 0.26, 1.20, 1.20)
	AddAlpha(point.chargedSpendAnim, point.BaseFill, 1, 0.16, 1, 0)

	point.surgedGainAnim = CreateAnimationGroup(point, true)
	AddAlpha(point.surgedGainAnim, point.SurgeFill, 1, 0.12, 0, 1)
	AddAlpha(point.surgedGainAnim, point.SurgedPulse, 1, 0.08, 0, 1)
	AddAlpha(point.surgedGainAnim, point.SurgedPulse, 1, 0.22, 1, 0, 0.08)
	AddScale(point.surgedGainAnim, point.SurgedPulse, 1, 0.30, 1.24, 1.24)

	point.surgedSpendAnim = CreateAnimationGroup(point, true)
	AddAlpha(point.surgedSpendAnim, point.SpendPulse, 1, 0.08, 0, 0.85)
	AddAlpha(point.surgedSpendAnim, point.SpendPulse, 1, 0.18, 0.85, 0, 0.08)
	AddScale(point.surgedSpendAnim, point.SpendPulse, 1, 0.26, 1.24, 1.24)
	AddAlpha(point.surgedSpendAnim, point.SurgeFill, 1, 0.14, 1, 0)

	point.emptyToSurgedAnim = CreateAnimationGroup(point, true)
	AddAlpha(point.emptyToSurgedAnim, point.BaseFill, 1, 0.10, 0, 1)
	AddAlpha(point.emptyToSurgedAnim, point.SurgeFill, 1, 0.14, 0, 1, 0.06)
	AddAlpha(point.emptyToSurgedAnim, point.ChargedPulse, 1, 0.08, 0, 0.70)
	AddAlpha(point.emptyToSurgedAnim, point.ChargedPulse, 1, 0.16, 0.70, 0, 0.08)
	AddScale(point.emptyToSurgedAnim, point.ChargedPulse, 1, 0.24, 1.14, 1.14)
	AddAlpha(point.emptyToSurgedAnim, point.SurgedPulse, 1, 0.08, 0, 1, 0.08)
	AddAlpha(point.emptyToSurgedAnim, point.SurgedPulse, 1, 0.22, 1, 0, 0.16)
	AddScale(point.emptyToSurgedAnim, point.SurgedPulse, 1, 0.32, 1.26, 1.26)

	point.surgedToEmptyAnim = CreateAnimationGroup(point, true)
	AddAlpha(point.surgedToEmptyAnim, point.SpendPulse, 1, 0.08, 0, 1)
	AddAlpha(point.surgedToEmptyAnim, point.SpendPulse, 1, 0.22, 1, 0, 0.08)
	AddScale(point.surgedToEmptyAnim, point.SpendPulse, 1, 0.32, 1.28, 1.28)
	AddAlpha(point.surgedToEmptyAnim, point.SurgeFill, 1, 0.12, 1, 0)
	AddAlpha(point.surgedToEmptyAnim, point.BaseFill, 1, 0.18, 1, 0, 0.04)

	point.thresholdPulseAnim = CreateAnimationGroup(point, true)
	AddAlpha(point.thresholdPulseAnim, point.SurgedPulse, 1, 0.10, 0, 0.85)
	AddAlpha(point.thresholdPulseAnim, point.SurgedPulse, 1, 0.26, 0.85, 0, 0.10)
	AddScale(point.thresholdPulseAnim, point.SurgedPulse, 1, 0.36, 1.32, 1.32)

	self:ConfigurePoint(point)
	self:ApplyVisualState(point, STATE_EMPTY)
	point:Show()
	return point
end

function ShamanMaelstromWeapon:GetPoint(index)
	if self.points[index] then
		return self.points[index]
	end

	local point = self:CreatePoint(index)
	self.points[index] = point
	return point
end

function ShamanMaelstromWeapon:PlayThresholdPulse()
	if not self.activeResource then
		return
	end

	local pointCount = self.activeResource.maxCount or 5
	for i = 1, pointCount do
		local point = self.points[i]
		if point and point.state ~= STATE_EMPTY then
			StopGroup(point.thresholdPulseAnim)
			SetAlpha(point.SurgedPulse, 0)
			point.SurgedPulse:SetScale(1)
			RestartGroup(point.thresholdPulseAnim)
		end
	end
end

function ShamanMaelstromWeapon:Initialize(parentFrame)
	self.parentFrame = parentFrame
	if self.root then
		return
	end

	self.root = CreateFrame("Frame", nil, parentFrame)
	self.root:SetPoint("CENTER")
	self.root:SetSize(1, 1)
	self.root:Hide()
end

function ShamanMaelstromWeapon:Shutdown()
	self.activeResource = nil
	self.resolved = nil
	self.visiblePointCount = 0
	self.suppressTransitions = true
	self.lastStacks = 0

	for i = 1, #self.points do
		local point = self.points[i]
		if point then
			self:StopPointAnimations(point)
			self:ApplyVisualState(point, STATE_EMPTY)
			point:Hide()
		end
	end

	if self.root then
		self.root:Hide()
	end
end

function ShamanMaelstromWeapon:SetResource(resourceDef, resolved)
	self.activeResource = resourceDef
	self.resolved = resolved
	self.visiblePointCount = 0
	self.suppressTransitions = true
	self.lastStacks = 0

	for i = 1, #self.points do
		local point = self.points[i]
		if point then
			self:StopPointAnimations(point)
			self:ConfigurePoint(point)
			self:ApplyVisualState(point, STATE_EMPTY)
			point:Hide()
		end
	end
end

function ShamanMaelstromWeapon:ApplyLayout()
	if not self.root or not self.activeResource then
		return
	end

	local count = self.activeResource.maxCount or 5
	local totalWidth = count * POINT_SIZE + (count - 1) * POINT_SPACING
	local x0 = -(totalWidth / 2) + (POINT_SIZE / 2)

	for i = 1, count do
		local point = self:GetPoint(i)
		local x = x0 + (i - 1) * (POINT_SIZE + POINT_SPACING)
		point:ClearAllPoints()
		point:SetPoint("CENTER", self.root, "CENTER", x, 0)
		point:Show()
	end

	for i = count + 1, #self.points do
		self.points[i]:Hide()
	end

	self.visiblePointCount = count
	self.root:SetSize(totalWidth, POINT_SIZE)
	if self.parentFrame then
		self.parentFrame:SetSize(totalWidth, POINT_SIZE)
	end
end

function ShamanMaelstromWeapon:ApplyVisualOptions()
	for i = 1, #self.points do
		local point = self.points[i]
		if point then
			self:ConfigurePoint(point)
			self:ApplyVisualState(point, point.state or STATE_EMPTY)
		end
	end
end

function ShamanMaelstromWeapon:SetVisible(visible)
	if not self.root then
		return
	end

	if visible then
		self.root:Show()
	else
		self.root:Hide()
	end
end

function ShamanMaelstromWeapon:ReadStacks()
	local resource = self.activeResource
	if not resource or not resource.auraSpellID then
		return 0
	end

	local auraData = C_UnitAuras.GetPlayerAuraBySpellID(resource.auraSpellID)
	local stacks = NormalizeAuraStacks(auraData)
	local logicalMax = resource.logicalMax or ((resource.maxCount or 5) * 2)

	if stacks < 0 then
		stacks = 0
	elseif stacks > logicalMax then
		stacks = logicalMax
	end

	return stacks
end

function ShamanMaelstromWeapon:Sync()
	if not self.activeResource then
		return
	end

	local pointCount = self.activeResource.maxCount or 5
	local stacks = self:ReadStacks()
	local previousStacks = self.lastStacks or 0
	local surgeThreshold = self.activeResource.empowerThreshold or 5

	if pointCount ~= self.visiblePointCount then
		self:ApplyLayout()
	end

	for i = 1, pointCount do
		local point = self:GetPoint(i)
		local nextState = self:StateForIndex(stacks, i)
		local currentState = point.state or STATE_EMPTY
		if self.suppressTransitions then
			self:StopPointAnimations(point)
			self:ApplyVisualState(point, nextState)
		elseif currentState ~= nextState then
			self:PlayTransition(point, currentState, nextState)
		else
			self:ApplyVisualState(point, nextState)
		end
	end

	if not self.suppressTransitions and previousStacks < surgeThreshold and stacks >= surgeThreshold then
		self:PlayThresholdPulse()
	end

	self.lastStacks = stacks
	self.suppressTransitions = false
end

function ShamanMaelstromWeapon:WantsEvent(event)
	if not self.activeResource then
		return false
	end

	return event == "UNIT_AURA"
end

function ShamanMaelstromWeapon:HandleEvent(event)
	if event ~= "UNIT_AURA" then
		return
	end

	self:Sync()
end

local function CreateShamanMaelstromWeapon()
	return setmetatable({
		root = nil,
		parentFrame = nil,
		points = {},
		activeResource = nil,
		resolved = nil,
		visiblePointCount = 0,
		lastStacks = 0,
		suppressTransitions = true,
	}, ShamanMaelstromWeapon)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.SHAMAN_MAELSTROM_WEAPON, CreateShamanMaelstromWeapon)
