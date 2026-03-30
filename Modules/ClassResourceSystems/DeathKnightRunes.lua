-- SparkPoint Death Knight Runes Class Resource System
-- Dedicated DK implementation with independent rune widgets and state-based ordering.

local _, addon = ...
local ResourceModel = addon.ResourceModel
local ClassResourceSystems = addon.ClassResourceSystems

local GetRuneCooldown = GetRuneCooldown
local GetSpecialization = GetSpecialization
local GetTime = GetTime

local RUNE_SIZE = 24
local RUNE_SPACING = -1
local RUNE_COOLDOWN_SIZE = 27
local RUNE_COOLDOWN_EDGE_TEXTURE = "Interface\\PlayerFrame\\DK-BloodUnholy-Rune-CDSpark"
local RUNE_UPDATE_INTERVAL = 0.05
local COOLDOWN_ENDING_OFFSET_SECONDS = 0.67

local DEFAULT_ART_TYPE = "Default"
local ART_TYPE_BY_SPEC = {
	[1] = "Blood",
	[2] = "Frost",
	[3] = "Unholy",
}

local VisualState = {
	EMPTY = 1,
	ON_COOLDOWN = 2,
	COOLDOWN_ENDING = 3,
	READY = 4,
}

local DeathKnightRunes = {}
DeathKnightRunes.__index = DeathKnightRunes

local function SetAlpha(region, alpha)
	if region then
		region:SetAlpha(alpha)
	end
end

function DeathKnightRunes:CreateRune(runeIndex)
	local rune = CreateFrame("Frame", nil, self.root)
	rune:SetSize(RUNE_SIZE, RUNE_SIZE)
	rune.runeIndex = runeIndex
	rune.layoutIndex = 7 - runeIndex
	rune.visualState = nil
	rune.lastRuneState = { start = 0, duration = 0, runeReady = false }
	rune.cooldownEndingStartTime = nil

	rune.BG_Shadow = rune:CreateTexture(nil, "BACKGROUND", nil, 0)
	rune.BG_Shadow:SetPoint("CENTER", 0, -3)
	rune.BG_Shadow:SetAtlas("UF-DKRunes-BGShadow", true)

	rune.BG_Inactive = rune:CreateTexture(nil, "BACKGROUND", nil, 1)
	rune.BG_Inactive:SetPoint("CENTER")
	rune.BG_Inactive:SetAtlas("UF-DKRunes-BGDis", true)

	rune.BG_Active = rune:CreateTexture(nil, "BACKGROUND", nil, 1)
	rune.BG_Active:SetPoint("CENTER")
	rune.BG_Active:SetAtlas("UF-DKRunes-BGActive", true)

	rune.Rune_Inactive = rune:CreateTexture(nil, "ARTWORK", nil, 0)
	rune.Rune_Inactive:SetPoint("CENTER")
	rune.Rune_Inactive:SetAtlas("UF-DKRunes-SkullDis", true)

	rune.Rune_Grad = rune:CreateTexture(nil, "ARTWORK", nil, 1)
	rune.Rune_Grad:SetPoint("CENTER")

	rune.Rune_Lines = rune:CreateTexture(nil, "ARTWORK", nil, 1)
	rune.Rune_Lines:SetPoint("CENTER")

	rune.Rune_Active = rune:CreateTexture(nil, "ARTWORK", nil, 2)
	rune.Rune_Active:SetPoint("CENTER")

	rune.Rune_Mid = rune:CreateTexture(nil, "ARTWORK", nil, 3)
	rune.Rune_Mid:SetPoint("CENTER")

	rune.Rune_Eyes = rune:CreateTexture(nil, "ARTWORK", nil, 3)
	rune.Rune_Eyes:SetPoint("CENTER", 0, 1)

	rune.Glow = rune:CreateTexture(nil, "OVERLAY", nil, 1)
	rune.Glow:SetPoint("CENTER")

	rune.Glow2 = rune:CreateTexture(nil, "OVERLAY", nil, 1)
	rune.Glow2:SetPoint("CENTER")

	rune.Smoke = rune:CreateTexture(nil, "OVERLAY", nil, 1)
	rune.Smoke:SetPoint("CENTER", 0, -4)

	rune.Cooldown = CreateFrame("Cooldown", nil, rune, "CooldownFrameTemplate")
	rune.Cooldown:SetSize(RUNE_COOLDOWN_SIZE, RUNE_COOLDOWN_SIZE)
	rune.Cooldown:SetPoint("CENTER")
	rune.Cooldown:SetReverse(true)
	rune.Cooldown:SetHideCountdownNumbers(true)
	rune.Cooldown:SetDrawBling(false)
	rune.Cooldown:SetDrawEdge(true)
	rune.Cooldown:SetUseCircularEdge(true)
	rune.Cooldown:SetEdgeTexture(RUNE_COOLDOWN_EDGE_TEXTURE, 1, 1, 1, 1)
	rune.Cooldown:SetSwipeColor(1, 1, 1, 0.9)

	return rune
end

function DeathKnightRunes:ApplyRuneArt(rune, specIndex)
	local artType = ART_TYPE_BY_SPEC[specIndex] or DEFAULT_ART_TYPE

	rune.Rune_Grad:SetAtlas(("UF-DKRunes-%s-SkullGrad"):format(artType), true)
	rune.Rune_Lines:SetAtlas(("UF-DKRunes-%s-SkullLines"):format(artType), true)
	rune.Rune_Active:SetAtlas(("UF-DKRunes-%s-SkullActive"):format(artType), true)
	rune.Rune_Mid:SetAtlas(("UF-DKRunes-%s-SkullMid"):format(artType), true)
	rune.Rune_Eyes:SetAtlas(("UF-DKRunes-%s-Eyes"):format(artType), true)
	rune.Glow:SetAtlas(("UF-DKRunes-%s-FilledGlwA"):format(artType), true)
	rune.Glow2:SetAtlas(("UF-DKRunes-%s-FilledGlwB"):format(artType), true)
	rune.Smoke:SetAtlas(("UF-DKRunes-%s-Smoke"):format(artType), true)
end

function DeathKnightRunes:ApplyVisualState(rune, now)
	local state = rune.visualState or VisualState.EMPTY

	if state == VisualState.READY then
		SetAlpha(rune.BG_Inactive, 0)
		SetAlpha(rune.BG_Active, 1)
		SetAlpha(rune.Rune_Inactive, 0)
		SetAlpha(rune.Rune_Grad, 0)
		SetAlpha(rune.Rune_Lines, 0)
		SetAlpha(rune.Rune_Active, 1)
		SetAlpha(rune.Rune_Mid, 0)
		SetAlpha(rune.Rune_Eyes, 0)
		SetAlpha(rune.Glow, 1)
		SetAlpha(rune.Glow2, 1)
		SetAlpha(rune.Smoke, 0)
		rune.Cooldown:Hide()
		rune.Cooldown:Clear()
		return
	end

	if state == VisualState.EMPTY then
		SetAlpha(rune.BG_Inactive, 1)
		SetAlpha(rune.BG_Active, 0)
		SetAlpha(rune.Rune_Inactive, 0.4)
		SetAlpha(rune.Rune_Grad, 0)
		SetAlpha(rune.Rune_Lines, 0)
		SetAlpha(rune.Rune_Active, 0)
		SetAlpha(rune.Rune_Mid, 0)
		SetAlpha(rune.Rune_Eyes, 0)
		SetAlpha(rune.Glow, 0)
		SetAlpha(rune.Glow2, 0)
		SetAlpha(rune.Smoke, 0)
		rune.Cooldown:Hide()
		rune.Cooldown:Clear()
		return
	end

	local start = rune.lastRuneState.start or 0
	local duration = rune.lastRuneState.duration or 0
	local progress = 0
	if duration > 0 then
		progress = math.max(0, math.min(1, (now - start) / duration))
	end

	if state == VisualState.ON_COOLDOWN then
		SetAlpha(rune.BG_Inactive, 1)
		SetAlpha(rune.BG_Active, 0)
		SetAlpha(rune.Rune_Inactive, 0.4 + (0.3 * progress))
		SetAlpha(rune.Rune_Grad, 0.20 + (0.10 * progress))
		SetAlpha(rune.Rune_Lines, 0.12 + (0.18 * progress))
		SetAlpha(rune.Rune_Active, 0)
		SetAlpha(rune.Rune_Mid, 0)
		SetAlpha(rune.Rune_Eyes, 0)
		SetAlpha(rune.Glow, 0)
		SetAlpha(rune.Glow2, 0)
		SetAlpha(rune.Smoke, 0)
		rune.Cooldown:Show()
		rune.Cooldown:SetCooldown(start, duration)
		return
	end

	local endingProgress = 0
	if rune.cooldownEndingStartTime then
		endingProgress = math.max(0, math.min(1, (now - rune.cooldownEndingStartTime) / COOLDOWN_ENDING_OFFSET_SECONDS))
	end

	SetAlpha(rune.BG_Inactive, 0)
	SetAlpha(rune.BG_Active, 1)
	SetAlpha(rune.Rune_Inactive, 0)
	SetAlpha(rune.Rune_Grad, 0)
	SetAlpha(rune.Rune_Lines, 0)
	SetAlpha(rune.Rune_Active, 1)
	SetAlpha(rune.Rune_Mid, 1 - math.min(1, endingProgress * 0.8))
	SetAlpha(rune.Rune_Eyes, math.min(1, endingProgress + 0.15))
	SetAlpha(rune.Glow, 1 - (endingProgress * 0.6))
	SetAlpha(rune.Glow2, 1 - (endingProgress * 0.85))
	SetAlpha(rune.Smoke, 0.4 + (0.6 * endingProgress))
	rune.Cooldown:Show()
	rune.Cooldown:SetCooldown(start, duration)
end

function DeathKnightRunes:UpdateRuneState(rune, now)
	local start, duration, runeReady = GetRuneCooldown(rune.runeIndex)
	rune.lastRuneState = {
		start = start or 0,
		duration = duration or 0,
		runeReady = runeReady and true or false,
	}

	if runeReady then
		rune.visualState = VisualState.READY
		rune.cooldownEndingStartTime = nil
	elseif start and start > 0 and duration and duration > 0 then
		rune.cooldownEndingStartTime = math.max(start, (start + duration) - COOLDOWN_ENDING_OFFSET_SECONDS)
		if now >= rune.cooldownEndingStartTime then
			rune.visualState = VisualState.COOLDOWN_ENDING
		else
			rune.visualState = VisualState.ON_COOLDOWN
		end
	else
		rune.visualState = VisualState.EMPTY
		rune.cooldownEndingStartTime = nil
	end

	self:ApplyVisualState(rune, now)
	return rune.visualState == VisualState.ON_COOLDOWN or rune.visualState == VisualState.COOLDOWN_ENDING
end

function DeathKnightRunes:CompareRunes(runeA, runeB)
	local stateA = runeA.visualState or VisualState.EMPTY
	local stateB = runeB.visualState or VisualState.EMPTY

	if stateA ~= stateB then
		return stateA > stateB
	end

	local startA = runeA.lastRuneState and runeA.lastRuneState.start or 0
	local startB = runeB.lastRuneState and runeB.lastRuneState.start or 0
	if startA ~= startB then
		return startA < startB
	end

	return runeA.runeIndex > runeB.runeIndex
end

function DeathKnightRunes:ApplyRuneLayout()
	local total = (#self.runes * RUNE_SIZE) + ((#self.runes - 1) * RUNE_SPACING)
	local x0 = -(total / 2) + (RUNE_SIZE / 2)

	for layoutIndex, runeIndex in ipairs(self.runeIndices) do
		local rune = self.runes[runeIndex]
		if rune then
			local x = x0 + ((layoutIndex - 1) * (RUNE_SIZE + RUNE_SPACING))
			rune:ClearAllPoints()
			rune:SetPoint("CENTER", self.root, "CENTER", x, 0)
			rune.layoutIndex = layoutIndex
		end
	end

	self.root:SetSize(total, RUNE_SIZE)
	if self.parentFrame then
		self.parentFrame:SetSize(total, RUNE_SIZE)
	end
end

function DeathKnightRunes:UpdateTicker(anyCharging)
	if not self.root then
		return
	end

	if anyCharging then
		if self.root:GetScript("OnUpdate") then
			return
		end

		self.elapsed = 0
		self.root:SetScript("OnUpdate", function(_, elapsed)
			self.elapsed = self.elapsed + (elapsed or 0)
			if self.elapsed < RUNE_UPDATE_INTERVAL then
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

function DeathKnightRunes:Initialize(parentFrame)
	self.parentFrame = parentFrame

	if self.root then
		return
	end

	self.root = CreateFrame("Frame", nil, parentFrame)
	self.root:SetPoint("CENTER")
	self.root:SetSize(1, 1)
	self.root:Hide()

	for i = 1, 6 do
		self.runes[i] = self:CreateRune(i)
		self.runeIndices[i] = i
	end

	self:ApplyRuneLayout()
end

function DeathKnightRunes:Shutdown()
	self.activeResource = nil
	self.resolved = nil
	self:UpdateTicker(false)

	if self.root then
		self.root:Hide()
	end
end

function DeathKnightRunes:SetResource(resourceDef, resolved)
	self.activeResource = resourceDef
	self.resolved = resolved

	local specIndex = resolved and resolved.context and resolved.context.spec or GetSpecialization()
	for i = 1, #self.runes do
		self:ApplyRuneArt(self.runes[i], specIndex)
	end
end

function DeathKnightRunes:ApplyLayout()
	if not self.root then
		return
	end

	self.root:ClearAllPoints()
	self.root:SetPoint("CENTER")
	self.root:SetScale(1)
	self.root:SetAlpha(1)
	self:ApplyRuneLayout()
end

function DeathKnightRunes:ApplyVisualOptions() end

function DeathKnightRunes:SetVisible(visible)
	if not self.root then
		return
	end

	if visible then
		self.root:Show()
		self:Sync()
		return
	end

	self.root:Hide()
	self:UpdateTicker(false)
end

function DeathKnightRunes:Sync()
	if not self.activeResource or not self.root then
		return
	end

	local anyCharging = false
	local now = GetTime()

	for i = 1, #self.runes do
		if self:UpdateRuneState(self.runes[i], now) then
			anyCharging = true
		end
	end

	table.sort(self.runeIndices, function(aIndex, bIndex)
		return self:CompareRunes(self.runes[aIndex], self.runes[bIndex])
	end)

	self:ApplyRuneLayout()
	self:UpdateTicker(anyCharging)
end

function DeathKnightRunes:WantsEvent(event)
	return event == "RUNE_POWER_UPDATE"
end

function DeathKnightRunes:HandleEvent(event)
	if event == "RUNE_POWER_UPDATE" then
		self:Sync()
	end
end

local function CreateDeathKnightRunes()
	return setmetatable({
		root = nil,
		parentFrame = nil,
		runes = {},
		runeIndices = {},
		activeResource = nil,
		resolved = nil,
		elapsed = 0,
	}, DeathKnightRunes)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.DEATH_KNIGHT_RUNES, CreateDeathKnightRunes)
