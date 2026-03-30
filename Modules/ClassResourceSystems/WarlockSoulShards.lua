-- SparkPoint Warlock Soul Shards Class Resource System
-- Dedicated Warlock shard implementation with destruction fractional fill support.

local _, addon = ...
local ResourceModel = addon.ResourceModel
local ClassResourceSystems = addon.ClassResourceSystems

local GetSpecialization = GetSpecialization
local UnitAffectingCombat = UnitAffectingCombat
local UnitPower = UnitPower
local UnitPowerDisplayMod = UnitPowerDisplayMod
local UnitPowerMax = UnitPowerMax
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

local SHARD_SIZE = 23
local SHARD_SPACING = 1
local EPSILON = 1e-9

local DESTRUCTION_SPEC_INDEX = 3

local INCREMENT_SETTINGS = {
	[1] = { fillAtlas = "UF-SoulShard-Inc1", glowAtlas = "UF-SoulShard-Inc1Glow", fillYOffset = -5.5, glowYOffset = -5.5 },
	[2] = { fillAtlas = "UF-SoulShard-Inc2", glowAtlas = "UF-SoulShard-Inc2Glow", fillYOffset = -6.5, glowYOffset = -6.5 },
	[3] = { fillAtlas = "UF-SoulShard-Inc3", glowAtlas = "UF-SoulShard-Inc3Glow", fillYOffset = -6.5, glowYOffset = -6.5 },
	[4] = { fillAtlas = "UF-SoulShard-Inc4", glowAtlas = "UF-SoulShard-Inc4Glow", fillYOffset = -5.5, glowYOffset = -5.5 },
	[5] = { fillAtlas = "UF-SoulShard-Inc5", glowAtlas = "UF-SoulShard-Inc5Glow", fillYOffset = -5.5, glowYOffset = -5.5 },
	[6] = { fillAtlas = "UF-SoulShard-Inc6", glowAtlas = "UF-SoulShard-Inc6Glow", fillYOffset = -5.5, glowYOffset = -5.5 },
	[7] = { fillAtlas = "UF-SoulShard-Inc7", glowAtlas = "UF-SoulShard-Inc7Glow", fillYOffset = -5.0, glowYOffset = -3.0 },
	[8] = { fillAtlas = "UF-SoulShard-Inc8", glowAtlas = "UF-SoulShard-Inc8Glow", fillYOffset = -4.5, glowYOffset = -3.0 },
	[9] = { fillAtlas = "UF-SoulShard-Inc9", glowAtlas = "UF-SoulShard-Inc9Glow", fillYOffset = -4.5, glowYOffset = -3.0 },
}

local WarlockSoulShards = {}
WarlockSoulShards.__index = WarlockSoulShards

local Shard = {}
Shard.__index = Shard

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

function Shard:ResetVisuals()
	StopGroup(self.emptyToFullAnim)
	StopGroup(self.fillDoneAnim)
	StopGroup(self.readyLoopAnim)
	StopGroup(self.depleteAnimA)
	StopGroup(self.depleteAnimB)
	StopGroup(self.depleteAnimC)
	StopGroup(self.FillIncrement.FillAnim)

	self.FillIncrement:Hide()
	SetAlpha(self.Shard_Icon, 0)

	for _, fxTexture in ipairs(self.fxTextures) do
		SetAlpha(fxTexture, 0)
	end

	for _, flipbook in ipairs(self.fxFlipBooks) do
		flipbook:Hide()
	end
end

function Shard:UpdateFullPowerVisuals(isBarFull)
	if isBarFull and not self.readyLoopAnim:IsPlaying() then
		self.emptyToFullAnim:Stop()
		self.fillDoneAnim:Stop()
		self.Shard_Soul:Hide()
		SetAlpha(self.Shard_Icon, 1)
		RestartGroup(self.readyLoopAnim)
	elseif not isBarFull and self.readyLoopAnim:IsPlaying() then
		self.readyLoopAnim:Stop()
	end
end

function Shard:SetIncrementFill(incrementIndex)
	local settings = INCREMENT_SETTINGS[incrementIndex]
	if not settings then
		return
	end

	self.FillIncrement.Fill:SetAtlas(settings.fillAtlas, true)
	self.FillIncrement.Fill:ClearAllPoints()
	self.FillIncrement.Fill:SetPoint("CENTER", 0, settings.fillYOffset)
	self.FillIncrement.Glow:SetAtlas(settings.glowAtlas, true)
	self.FillIncrement.Glow:ClearAllPoints()
	self.FillIncrement.Glow:SetPoint("CENTER", 0, settings.glowYOffset)
	self.FillIncrement:Show()
	RestartGroup(self.FillIncrement.FillAnim)
end

function Shard:Update(powerAmount, isBarFull)
	local fillAmount = math_max(0, math_min(1, powerAmount - (self.layoutIndex - 1)))
	fillAmount = math_floor((fillAmount + EPSILON) * 10) / 10

	if self.fillAmount == fillAmount then
		self:UpdateFullPowerVisuals(isBarFull)
		return
	end

	local oldFillAmount = self.fillAmount or 0
	self.fillAmount = fillAmount

	self:ResetVisuals()

	if fillAmount <= 0 then
		if oldFillAmount >= 0.7 then
			self.FB_DepleteC:Show()
			RestartGroup(self.depleteAnimC)
		elseif oldFillAmount >= 0.4 then
			self.FB_DepleteB:Show()
			RestartGroup(self.depleteAnimB)
		elseif oldFillAmount >= 0.1 then
			self.FB_DepleteA:Show()
			RestartGroup(self.depleteAnimA)
		end
	elseif fillAmount >= 1 then
		self.Shard_Icon:Show()
		if not isBarFull then
			self.Shard_Soul:Show()
			if oldFillAmount == 0 then
				RestartGroup(self.emptyToFullAnim)
			else
				RestartGroup(self.fillDoneAnim)
			end
		else
			SetAlpha(self.Shard_Icon, 1)
		end
	else
		self:SetIncrementFill(fillAmount * 10)
	end

	if isBarFull then
		self:UpdateFullPowerVisuals(isBarFull)
	end
end

local function CreateShard(system, index)
	local frame = CreateFrame("Frame", nil, system.root)
	frame:SetSize(SHARD_SIZE, 30)
	frame.layoutIndex = index

	local shard = setmetatable({
		system = system,
		frame = frame,
		layoutIndex = index,
		fillAmount = nil,
		fxTextures = {},
		fxFlipBooks = {},
	}, Shard)

	shard.Background = CreateAtlasTexture(frame, "BACKGROUND", 0, "UF-SoulShard-Holder", true, 0, -4.5)
	shard.Frame_Glow = CreateAtlasTexture(frame, "BACKGROUND", 0, "UF-SoulShard-FX-FrameGlow", true, 0, -3.5)
	shard.Shard_Icon = CreateAtlasTexture(frame, "ARTWORK", 0, "UF-SoulShard-Icon", true, 0, -3)
	shard.FB_DepleteA = CreateAtlasTexture(frame, "ARTWORK", 0, "UF-SoulShards-Flipbook-DepleteA", false, 0, 6)
	shard.FB_DepleteA:SetSize(21, 39)
	shard.FB_DepleteB = CreateAtlasTexture(frame, "ARTWORK", 0, "UF-SoulShards-Flipbook-DepleteB", false, 0, 8)
	shard.FB_DepleteB:SetSize(21, 41)
	shard.FB_DepleteC = CreateAtlasTexture(frame, "ARTWORK", 0, "UF-SoulShards-Flipbook-DepleteC", false, -1, 4)
	shard.FB_DepleteC:SetSize(29, 35)
	shard.Shard_Refill = CreateAtlasTexture(frame, "OVERLAY", 0, "UF-SoulShard-Refill", true, 0, -3)
	shard.Shard_RefillFX = CreateAtlasTexture(frame, "OVERLAY", 0, "UF-SoulShard-RefillFX", true, 0, -3)
	shard.Shard_IconFX2 = CreateAtlasTexture(frame, "OVERLAY", 0, "UF-SoulShard-FX2", true, 0, -3)
	shard.Shard_IconGlow = CreateAtlasTexture(frame, "OVERLAY", 0, "UF-SoulShard-IconGlow", true, 0, -3)
	shard.Shard_IconFX3 = CreateAtlasTexture(frame, "OVERLAY", 0, "UF-SoulShard-FX3", true, 0, -1)
	shard.Shard_Soul = CreateAtlasTexture(frame, "OVERLAY", 0, "UF-SoulShards-Flipbook-Soul", false, 0, 15)
	shard.Shard_Soul:SetSize(34, 53)

	shard.FillIncrement = CreateFrame("Frame", nil, frame)
	shard.FillIncrement:SetAllPoints()
	shard.FillIncrement.Fill = CreateAtlasTexture(shard.FillIncrement, "BORDER", 0, "UF-SoulShard-Inc1", true, 0, -5.5)
	shard.FillIncrement.Glow = CreateAtlasTexture(shard.FillIncrement, "ARTWORK", 0, "UF-SoulShard-Inc1Glow", true, 0, -5.5)

	shard.fxTextures = {
		shard.Frame_Glow,
		shard.Shard_Refill,
		shard.Shard_RefillFX,
		shard.Shard_IconFX2,
		shard.Shard_IconGlow,
		shard.Shard_IconFX3,
	}
	shard.fxFlipBooks = {
		shard.FB_DepleteA,
		shard.FB_DepleteB,
		shard.FB_DepleteC,
		shard.Shard_Soul,
	}

	shard.FillIncrement.FillAnim = CreateAnimationGroup(shard.FillIncrement, true)
	AddAlpha(shard.FillIncrement.FillAnim, shard.FillIncrement.Glow, 1, 0.20, 0, 1)
	AddAlpha(shard.FillIncrement.FillAnim, shard.FillIncrement.Glow, 1, 0.40, 1, 0, 0.20)

	shard.emptyToFullAnim = CreateAnimationGroup(frame, true)
	AddFlipBook(shard.emptyToFullAnim, shard.Shard_Soul, 1, 0.60, 3, 7, 18)
	AddAlpha(shard.emptyToFullAnim, shard.Shard_IconFX3, 1, 0.17, 0, 1, 0.17)
	AddAlpha(shard.emptyToFullAnim, shard.Shard_IconFX3, 1, 0.33, 0, 0, 0.34)
	AddAlpha(shard.emptyToFullAnim, shard.Shard_IconGlow, 1, 0.17, 0, 1, 0.17)
	AddAlpha(shard.emptyToFullAnim, shard.Shard_IconGlow, 1, 0.33, 1, 0, 0.34)
	AddAlpha(shard.emptyToFullAnim, shard.Frame_Glow, 1, 0.20, 0, 1, 0.17)
	AddAlpha(shard.emptyToFullAnim, shard.Frame_Glow, 1, 0.30, 1, 0, 0.37)
	AddAlpha(shard.emptyToFullAnim, shard.Shard_IconFX2, 1, 0.17, 0, 1)
	AddAlpha(shard.emptyToFullAnim, shard.Shard_IconFX2, 1, 0.35, 1, 0, 0.17)
	AddAlpha(shard.emptyToFullAnim, shard.Shard_Icon, 1, 0.47, 0, 0)
	AddAlpha(shard.emptyToFullAnim, shard.Shard_Icon, 1, 0.20, 0, 1, 0.47)

	shard.fillDoneAnim = CreateAnimationGroup(frame, true)
	AddFlipBook(shard.fillDoneAnim, shard.Shard_Soul, 1, 0.60, 3, 7, 18)
	AddAlpha(shard.fillDoneAnim, shard.Shard_IconFX3, 1, 0.43, 1, 1)
	AddAlpha(shard.fillDoneAnim, shard.Shard_IconFX3, 1, 0.17, 1, 0, 0.43)
	AddAlpha(shard.fillDoneAnim, shard.Shard_RefillFX, 1, 0.43, 0, 1)
	AddAlpha(shard.fillDoneAnim, shard.Shard_RefillFX, 1, 0.17, 1, 0, 0.43)
	AddAlpha(shard.fillDoneAnim, shard.Shard_Refill, 1, 0.43, 1, 1)
	AddAlpha(shard.fillDoneAnim, shard.Shard_Refill, 1, 0.17, 1, 0, 0.43)
	AddAlpha(shard.fillDoneAnim, shard.Shard_Icon, 1, 0.43, 0, 1)
	AddAlpha(shard.fillDoneAnim, shard.Frame_Glow, 1, 0.27, 1, 1)
	AddAlpha(shard.fillDoneAnim, shard.Frame_Glow, 1, 0.33, 1, 0, 0.27)

	shard.readyLoopAnim = CreateAnimationGroup(frame, true)
	shard.readyLoopAnim:SetLooping("BOUNCE")
	AddAlpha(shard.readyLoopAnim, shard.Shard_IconGlow, 1, 0.65, 0, 1)
	AddAlpha(shard.readyLoopAnim, shard.Frame_Glow, 1, 0.65, 0.25, 0.6)

	shard.depleteAnimA = CreateAnimationGroup(frame, true)
	AddFlipBook(shard.depleteAnimA, shard.FB_DepleteA, 1, 0.50, 3, 6, 15)
	AddAlpha(shard.depleteAnimA, shard.Frame_Glow, 1, 0.50, 1, 0)

	shard.depleteAnimB = CreateAnimationGroup(frame, true)
	AddFlipBook(shard.depleteAnimB, shard.FB_DepleteB, 1, 0.50, 3, 6, 15)
	AddAlpha(shard.depleteAnimB, shard.Frame_Glow, 1, 0.50, 1, 0)

	shard.depleteAnimC = CreateAnimationGroup(frame, true)
	AddFlipBook(shard.depleteAnimC, shard.FB_DepleteC, 1, 0.50, 3, 6, 15)
	AddAlpha(shard.depleteAnimC, shard.Frame_Glow, 1, 0.50, 1, 0)

	shard:ResetVisuals()
	frame:Show()
	return shard
end

function WarlockSoulShards:GetShard(index)
	if self.shards[index] then
		return self.shards[index]
	end

	local shard = CreateShard(self, index)
	self.shards[index] = shard
	return shard
end

function WarlockSoulShards:Initialize(parentFrame)
	self.parentFrame = parentFrame
	if self.root then
		return
	end

	self.root = CreateFrame("Frame", nil, parentFrame)
	self.root:SetPoint("CENTER")
	self.root:SetSize(1, 1)
	self.root:Hide()

	self.eventFrame = CreateFrame("Frame")
	self.eventFrame:SetScript("OnEvent", function(_, event)
		if self.activeResource and (event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED") then
			self:Sync()
		end
	end)
end

function WarlockSoulShards:Shutdown()
	self.activeResource = nil
	self.resolved = nil
	self.visibleShardCount = 0

	if self.eventFrame then
		self.eventFrame:UnregisterAllEvents()
	end

	for i = 1, #self.shards do
		local shard = self.shards[i]
		if shard then
			shard:ResetVisuals()
			shard.fillAmount = nil
			shard.frame:Hide()
		end
	end

	if self.root then
		self.root:Hide()
	end
end

function WarlockSoulShards:SetResource(resourceDef, resolved)
	self.activeResource = resourceDef
	self.resolved = resolved
	self.visibleShardCount = 0

	if self.eventFrame then
		self.eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
		self.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	end

	for i = 1, #self.shards do
		local shard = self.shards[i]
		if shard then
			shard:ResetVisuals()
			shard.fillAmount = nil
		end
	end
end

function WarlockSoulShards:LayoutShards(count)
	if not self.root or count < 1 then
		self.root:SetSize(1, 1)
		if self.parentFrame then
			self.parentFrame:SetSize(1, 1)
		end
		return
	end

	local total = count * SHARD_SIZE + (count - 1) * SHARD_SPACING
	local x0 = -(total / 2) + (SHARD_SIZE / 2)

	for i = 1, count do
		local shard = self:GetShard(i)
		shard.frame:ClearAllPoints()
		shard.frame:SetPoint("CENTER", self.root, "CENTER", x0 + (i - 1) * (SHARD_SIZE + SHARD_SPACING), 0)
		shard.frame:Show()
	end

	for i = count + 1, #self.shards do
		if self.shards[i] then
			self.shards[i].frame:Hide()
		end
	end

	self.root:SetSize(total, 30)
	if self.parentFrame then
		self.parentFrame:SetSize(total, 30)
	end
	self.visibleShardCount = count
end

function WarlockSoulShards:ApplyLayout()
	if not self.root then
		return
	end

	self.root:ClearAllPoints()
	self.root:SetPoint("CENTER")
	self:LayoutShards(self.activeResource and (self.activeResource.maxCount or 0) or 0)
end

function WarlockSoulShards:ApplyVisualOptions() end

function WarlockSoulShards:SetVisible(visible)
	if not self.root then
		return
	end

	if visible then
		self.root:Show()
	else
		self.root:Hide()
	end
end

function WarlockSoulShards:ReadState()
	local resource = self.activeResource
	if not resource or not resource.powerEnum then
		return 0, 0, false
	end

	local rawPower = UnitPower("player", resource.powerEnum, true) or 0
	local displayMod = UnitPowerDisplayMod(resource.powerEnum)
	local shardPower = (displayMod and displayMod ~= 0) and (rawPower / displayMod) or 0

	local spec = (self.resolved and self.resolved.spec) or GetSpecialization() or 0
	if spec ~= DESTRUCTION_SPEC_INDEX then
		shardPower = math_floor(shardPower)
	end

	local maxPower = UnitPowerMax("player", resource.powerEnum) or 0
	local showIsFullPower = false
	if UnitAffectingCombat("player") then
		showIsFullPower = shardPower >= maxPower
	end

	return shardPower, maxPower, showIsFullPower
end

function WarlockSoulShards:Sync()
	if not self.activeResource then
		return
	end

	local powerAmount, maxPower, showIsFullPower = self:ReadState()
	if maxPower < 1 then
		for i = 1, #self.shards do
			if self.shards[i] then
				self.shards[i].frame:Hide()
			end
		end
		return
	end

	if maxPower ~= self.visibleShardCount then
		self:LayoutShards(maxPower)
	end

	for i = 1, maxPower do
		local shard = self:GetShard(i)
		shard.frame:Show()
		shard:Update(powerAmount, showIsFullPower)
	end

	for i = maxPower + 1, #self.shards do
		if self.shards[i] then
			self.shards[i].frame:Hide()
		end
	end
end

function WarlockSoulShards:WantsEvent(event)
	return event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER"
end

function WarlockSoulShards:HandleEvent(event, unit, powerToken)
	if unit ~= "player" then
		return
	end

	if powerToken and self.activeResource and self.activeResource.powerToken and powerToken ~= self.activeResource.powerToken then
		return
	end

	self:Sync()
end

local function CreateWarlockSoulShards()
	return setmetatable({
		root = nil,
		parentFrame = nil,
		eventFrame = nil,
		shards = {},
		activeResource = nil,
		resolved = nil,
		visibleShardCount = 0,
	}, WarlockSoulShards)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.WARLOCK_SOUL_SHARDS, CreateWarlockSoulShards)
