-- SparkPoint Paladin Holy Power Class Resource System
-- Dedicated Paladin implementation closely following Blizzard's holder/rune visual state flow.

local _, addon = ...
local ResourceModel = addon.ResourceModel
local ClassResourceSystems = addon.ClassResourceSystems

local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax

local HOLDER_WIDTH = 150
local HOLDER_HEIGHT = 43
local HOLY_POWER_SPELL_READY = 3

local VisualState = {
	Inactive = 1,
	Active = 2,
	SpellReady = 3,
}

local RUNE_LAYOUT = {
	{ x = 18, y = -1, width = 18, height = 18, flipbookWidth = 26, flipbookHeight = 43, flipbookOffsetY = 7 },
	{ x = 41.6, y = 0, width = 20, height = 16, flipbookWidth = 28, flipbookHeight = 42, flipbookOffsetY = 7 },
	{ x = 68, y = 0.5, width = 17, height = 15, flipbookWidth = 27, flipbookHeight = 43, flipbookOffsetY = 9 },
	{ x = 92, y = 0, width = 15, height = 16, flipbookWidth = 27, flipbookHeight = 42, flipbookOffsetY = 7 },
	{ x = 112.2, y = -1, width = 18, height = 16, flipbookWidth = 27, flipbookHeight = 44, flipbookOffsetY = 7 },
}

local PaladinHolyPower = {}
PaladinHolyPower.__index = PaladinHolyPower

local Rune = {}
Rune.__index = Rune

local Holder = {}
Holder.__index = Holder

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

function Rune:ResetAllVisuals()
	StopGroup(self.activateAnim)
	StopGroup(self.readyAnim)
	StopGroup(self.readyLoopAnim)
	StopGroup(self.depleteAnim)

	SetAlpha(self.ActiveTexture, 0)
	SetAlpha(self.Glow, 0)
	SetAlpha(self.FX, 0)
	SetAlpha(self.Blur, 0)
	SetAlpha(self.DepleteFlipbook, 0)
end

function Rune:PlayReadyLoop()
	if self.visualState == VisualState.SpellReady then
		RestartGroup(self.readyLoopAnim)
	end
end

function Rune:SetVisualState(visualState, skipTransitionAnimation)
	local oldState = self.visualState
	self.visualState = visualState

	if self.visualState ~= oldState then
		self:ResetAllVisuals()
	end

	if self.visualState == VisualState.Inactive then
		if oldState ~= VisualState.Inactive or skipTransitionAnimation then
			if skipTransitionAnimation then
				SetAlpha(self.DepleteFlipbook, 0)
				StopGroup(self.depleteAnim)
			elseif not self.depleteAnim:IsPlaying() then
				SetAlpha(self.DepleteFlipbook, 1)
				RestartGroup(self.depleteAnim)
			end
		end
	elseif self.visualState == VisualState.Active then
		if oldState == VisualState.Inactive and not skipTransitionAnimation then
			RestartGroup(self.activateAnim)
		else
			SetAlpha(self.ActiveTexture, 1)
		end
	elseif self.visualState == VisualState.SpellReady then
		SetAlpha(self.ActiveTexture, 1)

		if not skipTransitionAnimation then
			StopGroup(self.readyLoopAnim)
			RestartGroup(self.readyAnim)
		else
			StopGroup(self.readyAnim)
			RestartGroup(self.readyLoopAnim)
		end
	end
end

function Holder:ResetAllVisuals()
	StopGroup(self.activateAnim)
	StopGroup(self.readyAnim)
	StopGroup(self.readyLoopAnim)
	StopGroup(self.depleteAnim)
	self.readyAnim:SetScript("OnFinished", nil)
	self.depleteAnim:SetScript("OnFinished", nil)

	SetAlpha(self.ActiveTexture, 0)
	SetAlpha(self.ThinGlow, 0)
	SetAlpha(self.Glow, 0)
end

function Holder:PlayReadyLoopCallback(animGroup)
	animGroup:SetScript("OnFinished", nil)
	if self.visualState == VisualState.SpellReady then
		RestartGroup(self.readyLoopAnim)
	end
end

function Holder:UpdateVisualState(visualState, numHolyPower)
	if visualState == self.visualState and numHolyPower == self.lastPower then
		return
	end

	local oldState = self.visualState
	local oldPower = self.lastPower or 0

	self.visualState = visualState
	self.lastPower = numHolyPower

	if self.visualState ~= oldState then
		self:ResetAllVisuals()
	end

	if self.visualState == VisualState.Inactive then
		if self.visualState ~= oldState then
			RestartGroup(self.depleteAnim)
		end
	elseif self.visualState == VisualState.Active then
		if oldState == VisualState.SpellReady or numHolyPower < oldPower then
			SetAlpha(self.ActiveTexture, 1)
			RestartGroup(self.depleteAnim)
		else
			RestartGroup(self.activateAnim)
		end
	elseif self.visualState == VisualState.SpellReady then
		SetAlpha(self.ActiveTexture, 1)
		StopGroup(self.readyAnim)
		StopGroup(self.readyLoopAnim)

		if numHolyPower < oldPower then
			self.depleteAnim:SetScript("OnFinished", function(animGroup)
				self:PlayReadyLoopCallback(animGroup)
			end)
			RestartGroup(self.depleteAnim)
		else
			self.readyAnim:SetScript("OnFinished", function(animGroup)
				self:PlayReadyLoopCallback(animGroup)
			end)
			RestartGroup(self.readyAnim)
		end
	end
end

local function CreateRune(system, index)
	local layout = RUNE_LAYOUT[index]
	local frame = CreateFrame("Frame", nil, system.holder.frame)
	frame:SetSize(layout.width, layout.height)
	frame:SetPoint("LEFT", layout.x, layout.y)

	local rune = setmetatable({
		system = system,
		frame = frame,
		runeNumber = index,
		visualState = nil,
	}, Rune)

	local baseAtlasName = ("uf-holypower-rune%d"):format(index)

	rune.Background = CreateAtlasTexture(frame, "BACKGROUND", 1, baseAtlasName, true)
	rune.Background:Hide()

	rune.FX = CreateAtlasTexture(frame, "ARTWORK", 1, baseAtlasName .. "-fx", true, 0, 5)
	rune.DepleteFlipbook = CreateAtlasTexture(frame, "ARTWORK", 2, ("UF-HolyPower-DepleteRune%d"):format(index), false, 0, layout.flipbookOffsetY)
	rune.DepleteFlipbook:SetSize(layout.flipbookWidth, layout.flipbookHeight)
	rune.ActiveTexture = CreateAtlasTexture(frame, "OVERLAY", 1, baseAtlasName .. "-active", true)
	rune.Glow = CreateAtlasTexture(frame, "OVERLAY", 2, baseAtlasName .. "-glow", true)
	rune.Blur = CreateAtlasTexture(frame, "OVERLAY", 3, baseAtlasName .. "-blur", true)

	rune.activateAnim = CreateAnimationGroup(frame, true)
	AddAlpha(rune.activateAnim, rune.FX, 1, 0.30, 0, 1)
	AddAlpha(rune.activateAnim, rune.FX, 1, 0.50, 1, 0, 0.30)
	AddAlpha(rune.activateAnim, rune.Blur, 1, 0.27, 1, 1)
	AddAlpha(rune.activateAnim, rune.Blur, 1, 0.53, 1, 0, 0.27)
	AddTranslation(rune.activateAnim, rune.Blur, 1, 0.80, 0, 2)
	AddAlpha(rune.activateAnim, rune.Glow, 1, 0.23, 0, 1, 0.10)
	AddAlpha(rune.activateAnim, rune.Glow, 1, 0.57, 1, 0, 0.23)
	AddAlpha(rune.activateAnim, rune.ActiveTexture, 1, 0.10, 0, 0)
	AddAlpha(rune.activateAnim, rune.ActiveTexture, 1, 0.23, 0, 1, 0.10)

	rune.readyAnim = CreateAnimationGroup(frame, true)
	AddAlpha(rune.readyAnim, rune.FX, 1, 0.30, 0, 1)
	AddAlpha(rune.readyAnim, rune.FX, 1, 0.37, 1, 0, 0.30)
	AddAlpha(rune.readyAnim, rune.Blur, 1, 0.33, 1, 1)
	AddAlpha(rune.readyAnim, rune.Blur, 1, 0.37, 1, 0, 0.30)
	AddTranslation(rune.readyAnim, rune.Blur, 1, 0.67, 0, 3)
	AddAlpha(rune.readyAnim, rune.Glow, 1, 0.13, 0, 0)
	AddAlpha(rune.readyAnim, rune.Glow, 1, 0.23, 0, 1, 0.13)
	AddAlpha(rune.readyAnim, rune.Glow, 1, 0.30, 1, 0, 0.23)
	rune.readyAnim:SetScript("OnFinished", function()
		rune:PlayReadyLoop()
	end)

	rune.readyLoopAnim = CreateAnimationGroup(frame, true)
	rune.readyLoopAnim:SetLooping("REPEAT")
	AddAlpha(rune.readyLoopAnim, rune.Glow, 1, 0.50, 0, 1)
	AddAlpha(rune.readyLoopAnim, rune.Glow, 1, 0.83, 1, 0, 0.50)

	rune.depleteAnim = CreateAnimationGroup(frame, false)
	AddFlipBook(rune.depleteAnim, rune.DepleteFlipbook, 1, 0.87, 5, 6, 26)
	rune.depleteAnim:SetScript("OnPlay", function()
		SetAlpha(rune.DepleteFlipbook, 1)
	end)
	rune.depleteAnim:SetScript("OnFinished", function()
		SetAlpha(rune.DepleteFlipbook, 0)
	end)

	rune:ResetAllVisuals()
	frame:Show()
	return rune
end

local function CreateHolder(system)
	local frame = CreateFrame("Frame", nil, system.root)
	frame:SetSize(HOLDER_WIDTH, HOLDER_HEIGHT)
	frame:SetPoint("CENTER")

	local holder = setmetatable({
		system = system,
		frame = frame,
		visualState = nil,
		lastPower = 0,
	}, Holder)

	holder.Background = CreateAtlasTexture(frame, "BACKGROUND", -5, "uf-holypower-runeholder", true)
	holder.ActiveTexture = CreateAtlasTexture(frame, "BACKGROUND", -3, "uf-holypower-runeholder-active", true)
	holder.Glow = CreateAtlasTexture(frame, "BACKGROUND", -2, "uf-holypower-runeholder-glow", true)
	holder.ThinGlow = CreateAtlasTexture(frame, "BACKGROUND", -2, "uf-holypower-runeholder-thinglow", true)

	holder.activateAnim = CreateAnimationGroup(frame, true)
	AddAlpha(holder.activateAnim, holder.Glow, 1, 0.10, 0, 1)
	AddAlpha(holder.activateAnim, holder.Glow, 1, 0.20, 1, 1, 0.10)
	AddAlpha(holder.activateAnim, holder.Glow, 1, 0.37, 1, 0, 0.30)
	AddAlpha(holder.activateAnim, holder.ActiveTexture, 1, 0.10, 0, 0)
	AddAlpha(holder.activateAnim, holder.ActiveTexture, 1, 0.23, 0, 1, 0.10)

	holder.readyAnim = CreateAnimationGroup(frame, true)
	AddAlpha(holder.readyAnim, holder.ThinGlow, 1, 0.67, 1, 0.7)

	holder.readyLoopAnim = CreateAnimationGroup(frame, true)
	holder.readyLoopAnim:SetLooping("REPEAT")
	AddAlpha(holder.readyLoopAnim, holder.ThinGlow, 1, 0.50, 0.7, 1)
	AddAlpha(holder.readyLoopAnim, holder.ThinGlow, 1, 0.83, 1, 0.7, 0.50)

	holder.depleteAnim = CreateAnimationGroup(frame, true)
	AddAlpha(holder.depleteAnim, holder.Glow, 1, 0.37, 1, 1)
	AddAlpha(holder.depleteAnim, holder.Glow, 1, 0.33, 1, 0, 0.37)

	holder:ResetAllVisuals()
	return holder
end

function PaladinHolyPower:Initialize(parentFrame)
	self.parentFrame = parentFrame
	if self.root then
		return
	end

	self.root = CreateFrame("Frame", nil, parentFrame)
	self.root:SetPoint("CENTER")
	self.root:SetSize(HOLDER_WIDTH, HOLDER_HEIGHT)
	self.root:Hide()

	self.holder = CreateHolder(self)
end

function PaladinHolyPower:Shutdown()
	self.activeResource = nil
	self.resolved = nil
	self.visibleRuneCount = 0
	self.suppressTransitions = true

	if self.holder then
		self.holder:ResetAllVisuals()
		self.holder.visualState = nil
		self.holder.lastPower = 0
	end

	for i = 1, #self.runes do
		local rune = self.runes[i]
		if rune then
			rune:ResetAllVisuals()
			rune.visualState = nil
			rune.frame:Hide()
		end
	end

	if self.root then
		self.root:Hide()
	end
end

function PaladinHolyPower:SetResource(resourceDef, resolved)
	self.activeResource = resourceDef
	self.resolved = resolved
	self.visibleRuneCount = 0
	self.suppressTransitions = true

	if self.holder then
		self.holder:ResetAllVisuals()
		self.holder.visualState = nil
		self.holder.lastPower = 0
	end

	for i = 1, #self.runes do
		local rune = self.runes[i]
		if rune then
			rune:ResetAllVisuals()
			rune.visualState = nil
		end
	end
end

function PaladinHolyPower:EnsureRune(index)
	if self.runes[index] then
		return self.runes[index]
	end

	local rune = CreateRune(self, index)
	self.runes[index] = rune
	return rune
end

function PaladinHolyPower:EnsureRuneCount(maxCount)
	for i = 1, maxCount do
		self:EnsureRune(i).frame:Show()
	end

	for i = maxCount + 1, #self.runes do
		local rune = self.runes[i]
		if rune then
			rune.frame:Hide()
		end
	end

	self.visibleRuneCount = maxCount
end

function PaladinHolyPower:ApplyLayout()
	if not self.root then
		return
	end

	self.root:ClearAllPoints()
	self.root:SetPoint("CENTER")
	self.root:SetScale(1)
	self.root:SetAlpha(1)
	self.root:SetSize(HOLDER_WIDTH, HOLDER_HEIGHT)
	if self.parentFrame then
		self.parentFrame:SetSize(HOLDER_WIDTH, HOLDER_HEIGHT)
	end
end

function PaladinHolyPower:ApplyVisualOptions() end

function PaladinHolyPower:SetVisible(visible)
	if not self.root then
		return
	end

	if visible then
		self.root:Show()
	else
		self.root:Hide()
	end
end

function PaladinHolyPower:ReadState()
	if not self.activeResource or not self.activeResource.powerEnum then
		return 0, 0
	end

	return UnitPower("player", self.activeResource.powerEnum) or 0, UnitPowerMax("player", self.activeResource.powerEnum) or 0
end

function PaladinHolyPower:Sync()
	if not self.activeResource or not self.root or not self.holder then
		return
	end

	local numHolyPower, maxHolyPower = self:ReadState()
	local skipTransitionAnimation = self.suppressTransitions

	if maxHolyPower < 1 then
		for i = 1, #self.runes do
			if self.runes[i] then
				self.runes[i].frame:Hide()
			end
		end
		self.holder:ResetAllVisuals()
		self.holder.visualState = nil
		self.holder.lastPower = 0
		self.suppressTransitions = false
		return
	end

	if maxHolyPower ~= self.visibleRuneCount then
		self:EnsureRuneCount(maxHolyPower)
	end

	local isSpellReady = numHolyPower >= HOLY_POWER_SPELL_READY
	for i = 1, maxHolyPower do
		local rune = self:EnsureRune(i)
		local runeState = VisualState.Inactive
		if i <= numHolyPower then
			runeState = isSpellReady and VisualState.SpellReady or VisualState.Active
		end

		rune:SetVisualState(runeState, skipTransitionAnimation)
	end

	local holderState = VisualState.Inactive
	if numHolyPower > 0 then
		holderState = isSpellReady and VisualState.SpellReady or VisualState.Active
	end

	if skipTransitionAnimation and self.holder.visualState == nil then
		self.holder.visualState = holderState
		self.holder.lastPower = numHolyPower
		self.holder:ResetAllVisuals()
		if holderState ~= VisualState.Inactive then
			SetAlpha(self.holder.ActiveTexture, 1)
			if holderState == VisualState.SpellReady then
				RestartGroup(self.holder.readyLoopAnim)
			end
		end
	else
		self.holder:UpdateVisualState(holderState, numHolyPower)
	end

	self.suppressTransitions = false
end

function PaladinHolyPower:WantsEvent(event)
	return event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
end

function PaladinHolyPower:HandleEvent(event, unit, powerToken)
	if unit ~= "player" then
		return
	end

	if powerToken and self.activeResource and self.activeResource.powerToken and powerToken ~= self.activeResource.powerToken then
		return
	end

	self:Sync()
end

local function CreatePaladinHolyPower()
	return setmetatable({
		root = nil,
		parentFrame = nil,
		holder = nil,
		runes = {},
		activeResource = nil,
		resolved = nil,
		visibleRuneCount = 0,
		suppressTransitions = true,
	}, PaladinHolyPower)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.PALADIN_HOLY_POWER, CreatePaladinHolyPower)
