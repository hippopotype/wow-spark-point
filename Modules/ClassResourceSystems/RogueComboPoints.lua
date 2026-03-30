-- SparkPoint Rogue Combo Points Class Resource System
-- Dedicated Rogue implementation with charged-point support and native animation groups.

local _, addon = ...
local ResourceModel = addon.ResourceModel
local ClassResourceSystems = addon.ClassResourceSystems

local GetUnitChargedPowerPoints = GetUnitChargedPowerPoints
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax

local POINT_SIZE = 20
local POINT_SPACING = 4

local STATE_UNCHARGED_EMPTY = 1
local STATE_UNCHARGED_FULL = 2
local STATE_CHARGED_EMPTY = 3
local STATE_CHARGED_FULL = 4

local RogueComboPoints = {}
RogueComboPoints.__index = RogueComboPoints

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

local function CreateAtlasTexture(parent, layer, subLevel, atlas, useAtlasSize, x, y)
	local texture = parent:CreateTexture(nil, layer, nil, subLevel or 0)
	texture:SetPoint("CENTER", x or 0, y or 0)
	texture:SetAtlas(atlas, useAtlasSize and true or false)
	return texture
end

local function StateKey(isCharged, isFull)
	if isCharged then
		return isFull and STATE_CHARGED_FULL or STATE_CHARGED_EMPTY
	end

	return isFull and STATE_UNCHARGED_FULL or STATE_UNCHARGED_EMPTY
end

local TRANSITION_BY_STATE = {
	[STATE_UNCHARGED_EMPTY] = {
		[STATE_UNCHARGED_EMPTY] = "unchargedEmpty",
		[STATE_UNCHARGED_FULL] = "unchargedEmptyToUnchargedFull",
		[STATE_CHARGED_EMPTY] = "unchargedEmptyToChargedEmpty",
		[STATE_CHARGED_FULL] = "unchargedEmptyToChargedFull",
	},
	[STATE_UNCHARGED_FULL] = {
		[STATE_UNCHARGED_EMPTY] = "unchargedFullToUnchargedEmpty",
		[STATE_UNCHARGED_FULL] = nil,
		[STATE_CHARGED_EMPTY] = "unchargedFullToChargedEmpty",
		[STATE_CHARGED_FULL] = "unchargedFullToChargedFull",
	},
	[STATE_CHARGED_EMPTY] = {
		[STATE_UNCHARGED_EMPTY] = "chargedEmptyToUnchargedEmpty",
		[STATE_UNCHARGED_FULL] = "chargedEmptyToUnchargedFull",
		[STATE_CHARGED_EMPTY] = nil,
		[STATE_CHARGED_FULL] = "chargedEmptyToChargedFull",
	},
	[STATE_CHARGED_FULL] = {
		[STATE_UNCHARGED_EMPTY] = "chargedFullToUnchargedEmpty",
		[STATE_UNCHARGED_FULL] = "chargedFullToUnchargedFull",
		[STATE_CHARGED_EMPTY] = "chargedFullToChargedEmpty",
		[STATE_CHARGED_FULL] = nil,
	},
}

local TRANSITION_SPECS = {
	unchargedEmpty = {
		{ type = "alpha", target = "BGInactive", from = 0, to = 1, duration = 0.10 },
	},
	unchargedEmptyToUnchargedFull = {
		{ type = "alpha", target = "SlashFBUncharged", from = 0, to = 1, duration = 0.0 },
		{ type = "flipbook", target = "SlashFBUncharged", duration = 0.57, rows = 3, columns = 6, frames = 17 },
		{ type = "alpha", target = "IconUncharged", from = 0, to = 0.5, duration = 0.10 },
		{ type = "alpha", target = "IconUncharged", from = 0.5, to = 1, duration = 0.27, delay = 0.27 },
		{ type = "alpha", target = "BGActive", from = 0, to = 0, duration = 0.20 },
		{ type = "alpha", target = "BGActive", from = 0, to = 1, duration = 0.17, delay = 0.20 },
		{ type = "alpha", target = "BGInactive", from = 1, to = 1, duration = 0.37 },
		{ type = "alpha", target = "BGInactive", from = 1, to = 0, duration = 0.10, delay = 0.37 },
		{ type = "alpha", target = "BGGlow", from = 0, to = 1, duration = 0.17 },
		{ type = "alpha", target = "BGGlow", from = 1, to = 0, duration = 0.40, delay = 0.17 },
		{ type = "alpha", target = "FXUncharged", from = 0, to = 1, duration = 0.12, delay = 0.18 },
		{ type = "alpha", target = "FXUncharged", from = 1, to = 0, duration = 0.32, delay = 0.30 },
		{ type = "alpha", target = "FrameGlow", from = 0, to = 1, duration = 0.12, delay = 0.20 },
		{ type = "alpha", target = "FrameGlow", from = 1, to = 0, duration = 0.35, delay = 0.32 },
	},
	unchargedEmptyToChargedFull = {
		{ type = "alpha", target = "SlashFBCharged", from = 0, to = 1, duration = 0.0 },
		{ type = "flipbook", target = "SlashFBCharged", duration = 0.57, rows = 3, columns = 6, frames = 17 },
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 1, duration = 0.17 },
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 0, duration = 0.33, delay = 0.17 },
		{ type = "alpha", target = "ChargedFrameActive", from = 0, to = 0, duration = 0.20 },
		{ type = "alpha", target = "ChargedFrameActive", from = 0, to = 1, duration = 0.17, delay = 0.20 },
		{ type = "alpha", target = "IconCharged", from = 0, to = 0.5, duration = 0.10 },
		{ type = "alpha", target = "IconCharged", from = 0.5, to = 1, duration = 0.27, delay = 0.27 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 0, to = 0.5, duration = 0.10 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 0.5, to = 0, duration = 0.13, delay = 0.37 },
		{ type = "alpha", target = "FXCharged", from = 0, to = 1, duration = 0.12, delay = 0.18 },
		{ type = "alpha", target = "FXCharged", from = 1, to = 0, duration = 0.32, delay = 0.30 },
		{ type = "alpha", target = "FrameGlow", from = 0, to = 1, duration = 0.15, delay = 0.20 },
		{ type = "alpha", target = "FrameGlow", from = 1, to = 0, duration = 0.35, delay = 0.32 },
	},
	unchargedEmptyToChargedEmpty = {
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 1, duration = 0.17 },
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 0, duration = 0.33, delay = 0.17 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 0, to = 1, duration = 0.17 },
		{ type = "alpha", target = "BGGlow", from = 1, to = 0, duration = 0.47 },
	},
	chargedEmptyToChargedFull = {
		{ type = "alpha", target = "SlashFBCharged", from = 0, to = 1, duration = 0.0 },
		{ type = "flipbook", target = "SlashFBCharged", duration = 0.57, rows = 3, columns = 6, frames = 17 },
		{ type = "alpha", target = "ChargedFrameActive", from = 0, to = 0, duration = 0.20 },
		{ type = "alpha", target = "ChargedFrameActive", from = 0, to = 1, duration = 0.17, delay = 0.20 },
		{ type = "alpha", target = "IconCharged", from = 0, to = 0.5, duration = 0.10 },
		{ type = "alpha", target = "IconCharged", from = 0.5, to = 1, duration = 0.27, delay = 0.27 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 1, to = 0.5, duration = 0.10 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 0.5, to = 0, duration = 0.13, delay = 0.37 },
		{ type = "alpha", target = "FXCharged", from = 0, to = 1, duration = 0.12, delay = 0.18 },
		{ type = "alpha", target = "FXCharged", from = 1, to = 0, duration = 0.32, delay = 0.30 },
		{ type = "alpha", target = "FrameGlow", from = 0, to = 1, duration = 0.15, delay = 0.20 },
		{ type = "alpha", target = "FrameGlow", from = 1, to = 0, duration = 0.35, delay = 0.32 },
		{ type = "alpha", target = "BGGlow", from = 1, to = 0, duration = 0.47 },
	},
	chargedEmptyToUnchargedFull = {
		{ type = "alpha", target = "SlashFBUncharged", from = 0, to = 1, duration = 0.0 },
		{ type = "flipbook", target = "SlashFBUncharged", duration = 0.57, rows = 3, columns = 6, frames = 17 },
		{ type = "alpha", target = "IconUncharged", from = 0, to = 0.5, duration = 0.10 },
		{ type = "alpha", target = "IconUncharged", from = 0.5, to = 1, duration = 0.27, delay = 0.27 },
		{ type = "alpha", target = "BGActive", from = 0, to = 0, duration = 0.20 },
		{ type = "alpha", target = "BGActive", from = 0, to = 1, duration = 0.17, delay = 0.20 },
		{ type = "alpha", target = "BGGlow", from = 0, to = 1, duration = 0.17 },
		{ type = "alpha", target = "BGGlow", from = 1, to = 0, duration = 0.40, delay = 0.17 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 1, to = 0.5, duration = 0.10 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 0.5, to = 0, duration = 0.33, delay = 0.17 },
		{ type = "alpha", target = "FXUncharged", from = 0, to = 1, duration = 0.12, delay = 0.18 },
		{ type = "alpha", target = "FXUncharged", from = 1, to = 0, duration = 0.32, delay = 0.30 },
		{ type = "alpha", target = "FrameGlow", from = 0, to = 1, duration = 0.12, delay = 0.20 },
		{ type = "alpha", target = "FrameGlow", from = 1, to = 0, duration = 0.35, delay = 0.32 },
	},
	chargedEmptyToUnchargedEmpty = {
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 1, duration = 0.17 },
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 0, duration = 0.33, delay = 0.17 },
		{ type = "alpha", target = "BGGlow", from = 1, to = 0, duration = 0.47 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 1, to = 1, duration = 0.17 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 1, to = 0, duration = 0.33, delay = 0.17 },
		{ type = "alpha", target = "BGInactive", from = 0, to = 0, duration = 0.37 },
		{ type = "alpha", target = "BGInactive", from = 0, to = 1, duration = 0.10, delay = 0.37 },
	},
	unchargedFullToUnchargedEmpty = {
		{ type = "alpha", target = "FrameGlow", from = 1, to = 0, duration = 0.50 },
		{ type = "alpha", target = "IconUncharged", from = 1, to = 0, duration = 0.17 },
		{ type = "alpha", target = "FXUncharged", from = 1, to = 0, duration = 0.40 },
		{ type = "alpha", target = "BGActive", from = 1, to = 1, duration = 0.20 },
		{ type = "alpha", target = "BGActive", from = 1, to = 0, duration = 0.17, delay = 0.20 },
		{ type = "alpha", target = "BGInactive", from = 0, to = 0, duration = 0.37 },
		{ type = "alpha", target = "BGInactive", from = 0, to = 1, duration = 0.10, delay = 0.37 },
	},
	unchargedFullToChargedFull = {
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 1, duration = 0.17 },
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 0, duration = 0.33, delay = 0.17 },
		{ type = "alpha", target = "BGGlow", from = 1, to = 0, duration = 0.47 },
		{ type = "alpha", target = "ChargedFrameActive", from = 0, to = 0, duration = 0.20 },
		{ type = "alpha", target = "ChargedFrameActive", from = 0, to = 1, duration = 0.17, delay = 0.20 },
		{ type = "alpha", target = "BGActive", from = 1, to = 1, duration = 0.20 },
		{ type = "alpha", target = "BGActive", from = 1, to = 0, duration = 0.17, delay = 0.20 },
		{ type = "alpha", target = "IconCharged", from = 0, to = 0, duration = 0.27 },
		{ type = "alpha", target = "IconCharged", from = 0, to = 1, duration = 0.27, delay = 0.27 },
		{ type = "alpha", target = "IconUncharged", from = 1, to = 1, duration = 0.27 },
		{ type = "alpha", target = "IconUncharged", from = 1, to = 0, duration = 0.27, delay = 0.27 },
	},
	unchargedFullToChargedEmpty = {
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 0, duration = 0.50 },
		{ type = "alpha", target = "IconUncharged", from = 1, to = 0, duration = 0.17 },
		{ type = "alpha", target = "FXUncharged", from = 1, to = 0, duration = 0.40 },
		{ type = "alpha", target = "BGActive", from = 1, to = 1, duration = 0.20 },
		{ type = "alpha", target = "BGActive", from = 1, to = 0, duration = 0.17, delay = 0.20 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 0, to = 0, duration = 0.17 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 0, to = 1, duration = 0.33, delay = 0.17 },
	},
	chargedFullToChargedEmpty = {
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 0, duration = 0.50 },
		{ type = "alpha", target = "IconCharged", from = 1, to = 0, duration = 0.17 },
		{ type = "alpha", target = "FXCharged", from = 1, to = 0, duration = 0.40 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 0, to = 0, duration = 0.17 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 0, to = 1, duration = 0.33, delay = 0.17 },
	},
	chargedFullToUnchargedEmpty = {
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 0, duration = 0.50 },
		{ type = "alpha", target = "IconCharged", from = 1, to = 0, duration = 0.17 },
		{ type = "alpha", target = "FXCharged", from = 1, to = 0, duration = 0.40 },
		{ type = "alpha", target = "ChargedFrameInactive", from = 0, to = 0, duration = 0.17 },
		{ type = "alpha", target = "BGInactive", from = 0, to = 0, duration = 0.37 },
		{ type = "alpha", target = "BGInactive", from = 0, to = 1, duration = 0.10, delay = 0.37 },
	},
	chargedFullToUnchargedFull = {
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 1, duration = 0.17 },
		{ type = "alpha", target = "ChargedFrameGlow", from = 1, to = 0, duration = 0.33, delay = 0.17 },
		{ type = "alpha", target = "BGGlow", from = 1, to = 0, duration = 0.47 },
		{ type = "alpha", target = "ChargedFrameActive", from = 1, to = 0, duration = 0.20 },
		{ type = "alpha", target = "BGActive", from = 0, to = 0, duration = 0.20 },
		{ type = "alpha", target = "BGActive", from = 0, to = 1, duration = 0.17, delay = 0.20 },
		{ type = "alpha", target = "IconCharged", from = 1, to = 1, duration = 0.27 },
		{ type = "alpha", target = "IconCharged", from = 1, to = 0, duration = 0.27, delay = 0.27 },
		{ type = "alpha", target = "IconUncharged", from = 0, to = 0, duration = 0.27 },
		{ type = "alpha", target = "IconUncharged", from = 0, to = 1, duration = 0.27, delay = 0.27 },
	},
}

function RogueComboPoints:Initialize(parentFrame)
	self.parentFrame = parentFrame
	if self.root then
		return
	end

	self.root = CreateFrame("Frame", nil, parentFrame)
	self.root:SetPoint("CENTER")
	self.root:SetSize(1, 1)
	self.root:Hide()
end

function RogueComboPoints:Shutdown()
	self.activeResource = nil
	self.resolved = nil
	self.pointMax = 0

	for i = 1, #self.points do
		local point = self.points[i]
		if point then
			self:StopPointAnimations(point)
			point.state = nil
			point:Hide()
		end
	end

	if self.root then
		self.root:Hide()
	end
end

function RogueComboPoints:StopPointAnimations(point)
	for _, group in pairs(point.transitionAnims) do
		StopGroup(group)
	end

	for _, texture in ipairs(point.fxTextures) do
		texture:SetAlpha(0)
	end
end

function RogueComboPoints:CreatePoint(index)
	local point = CreateFrame("Frame", nil, self.root)
	point:SetSize(POINT_SIZE, POINT_SIZE)
	point.index = index
	point.state = nil
	point.fxTextures = {}
	point.transitionAnims = {}

	point.BGShadow = CreateAtlasTexture(point, "BACKGROUND", 0, "uf-roguecp-bg-shadow", true, 0, -4)
	point.BGActive = CreateAtlasTexture(point, "BACKGROUND", 1, "uf-roguecp-bg", true)
	point.BGInactive = CreateAtlasTexture(point, "BACKGROUND", 1, "uf-roguecp-bg-dis", true)
	point.BGGlow = CreateAtlasTexture(point, "BACKGROUND", 1, "uf-roguecp-bg", true)
	point.IconUncharged = CreateAtlasTexture(point, "ARTWORK", 1, "uf-roguecp-icon-red", true)
	point.IconCharged = CreateAtlasTexture(point, "ARTWORK", 1, "uf-roguecp-icon-blue", true)
	point.FXUncharged = CreateAtlasTexture(point, "ARTWORK", 2, "uf-roguecp-fx-red", true)
	point.FXCharged = CreateAtlasTexture(point, "ARTWORK", 2, "uf-roguecp-fx-blue", true)
	point.ChargedFrameInactive = CreateAtlasTexture(point, "ARTWORK", 3, "uf-roguecp-bg-anima-dis", true)
	point.ChargedFrameActive = CreateAtlasTexture(point, "ARTWORK", 3, "uf-roguecp-bg-anima", true)
	point.ChargedFrameGlow = CreateAtlasTexture(point, "ARTWORK", 3, "uf-roguecp-bg-animaglow", true)
	point.FrameGlow = CreateAtlasTexture(point, "OVERLAY", 0, "uf-roguecp-frame-glow", true)
	point.SlashFBUncharged = CreateAtlasTexture(point, "OVERLAY", 0, "uf-roguecp-slash-red", false)
	point.SlashFBUncharged:SetSize(43, 43)
	point.SlashFBCharged = CreateAtlasTexture(point, "OVERLAY", 0, "uf-roguecp-slash-blue", false)
	point.SlashFBCharged:SetSize(43, 43)

	point.fxTextures = {
		point.BGActive,
		point.BGInactive,
		point.BGGlow,
		point.IconUncharged,
		point.IconCharged,
		point.FXUncharged,
		point.FXCharged,
		point.ChargedFrameInactive,
		point.ChargedFrameActive,
		point.ChargedFrameGlow,
		point.FrameGlow,
		point.SlashFBUncharged,
		point.SlashFBCharged,
	}

	for name, animations in pairs(TRANSITION_SPECS) do
		local group = CreateAnimationGroup(point, true)
		for _, spec in ipairs(animations) do
			local target = point[spec.target]
			if spec.type == "alpha" then
				AddAlpha(group, target, 1, spec.duration, spec.from, spec.to, spec.delay)
			elseif spec.type == "flipbook" then
				AddFlipBook(group, target, 1, spec.duration, spec.rows, spec.columns, spec.frames)
			end
		end
		point.transitionAnims[name] = group
	end

	self:StopPointAnimations(point)
	point:Show()
	return point
end

function RogueComboPoints:GetPoint(index)
	if self.points[index] then
		return self.points[index]
	end

	local point = self:CreatePoint(index)
	self.points[index] = point
	return point
end

function RogueComboPoints:SetResource(resourceDef, resolved)
	self.activeResource = resourceDef
	self.resolved = resolved
	self.pointMax = 0

	for i = 1, #self.points do
		local point = self.points[i]
		if point then
			self:StopPointAnimations(point)
			point.state = nil
		end
	end
end

function RogueComboPoints:LayoutPoints(count)
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

function RogueComboPoints:ApplyLayout()
	if not self.root then
		return
	end

	self.root:ClearAllPoints()
	self.root:SetPoint("CENTER")
	self.root:SetScale(1)
	self.root:SetAlpha(1)
end

function RogueComboPoints:ApplyVisualOptions() end

function RogueComboPoints:SetVisible(visible)
	if not self.root then
		return
	end

	if visible then
		self.root:Show()
	else
		self.root:Hide()
	end
end

function RogueComboPoints:ReadState()
	if not self.activeResource or not self.activeResource.powerEnum then
		return 0, 0, nil
	end

	local current = UnitPower("player", self.activeResource.powerEnum) or 0
	local maxPoints = UnitPowerMax("player", self.activeResource.powerEnum) or 0
	local chargedMap = nil

	if GetUnitChargedPowerPoints then
		local chargedPoints = GetUnitChargedPowerPoints("player")
		if type(chargedPoints) == "table" and #chargedPoints > 0 then
			chargedMap = {}
			for i = 1, #chargedPoints do
				local pointIndex = tonumber(chargedPoints[i])
				if pointIndex and pointIndex > 0 then
					chargedMap[pointIndex] = true
				end
			end
		end
	end

	return current, maxPoints, chargedMap
end

function RogueComboPoints:ApplyPointState(point, isFull, isCharged)
	local nextState = StateKey(isCharged, isFull)
	local previousState = point.state or STATE_UNCHARGED_EMPTY
	if nextState == point.state then
		return
	end

	self:StopPointAnimations(point)
	local transitionName = TRANSITION_BY_STATE[previousState] and TRANSITION_BY_STATE[previousState][nextState]
	if transitionName and point.transitionAnims[transitionName] then
		RestartGroup(point.transitionAnims[transitionName])
	elseif nextState == STATE_UNCHARGED_EMPTY and point.transitionAnims.unchargedEmpty then
		RestartGroup(point.transitionAnims.unchargedEmpty)
	end

	point.state = nextState
end

function RogueComboPoints:Sync()
	if not self.activeResource then
		return
	end

	local current, maxPoints, chargedMap = self:ReadState()
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
		self:ApplyPointState(point, i <= current, chargedMap and chargedMap[i] or false)
	end
end

function RogueComboPoints:WantsEvent(event)
	return event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
end

function RogueComboPoints:HandleEvent(event, unit, powerToken)
	if unit ~= "player" then
		return
	end

	if powerToken and self.activeResource and self.activeResource.powerToken and powerToken ~= self.activeResource.powerToken then
		return
	end

	self:Sync()
end

local function CreateRogueComboPoints()
	return setmetatable({
		root = nil,
		parentFrame = nil,
		points = {},
		pointMax = 0,
		activeResource = nil,
		resolved = nil,
	}, RogueComboPoints)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.ROGUE_COMBO_POINTS, CreateRogueComboPoints)
