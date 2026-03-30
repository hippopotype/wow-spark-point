-- SparkPoint Death Knight Runes Class Resource System
-- Dedicated DK implementation using Blizzard-style animation groups and slot-based deplete visuals.

local _, addon = ...
local ResourceModel = addon.ResourceModel
local ClassResourceSystems = addon.ClassResourceSystems

local C_Texture = C_Texture
local GetRuneCooldown = GetRuneCooldown
local GetSpecialization = GetSpecialization
local GetTime = GetTime
local math_abs = math.abs
local math_floor = math.floor

local RUNE_SIZE = 24
local RUNE_SPACING = -1
local RUNE_COOLDOWN_SIZE = 27
local RUNE_COOLDOWN_EDGE_TEXTURE = "Interface\\PlayerFrame\\DK-BloodUnholy-Rune-CDSpark"
local COOLDOWN_FILL_ANIM_BASIS_SECONDS = 8
local COOLDOWN_ENDING_OFFSET_SECONDS = 0.67

local DEFAULT_ART_TYPE = "Default"
local ART_TYPE_BY_SPEC = {
	[1] = "Blood",
	[2] = "Frost",
	[3] = "Unholy",
}

local RUNE_ART_SET = {
	cooldownSwipe = "UF-DKRunes-%s-LevelBar",
	depleteFlipbook = "UF-DKRunes-%sDeplete",
}

local VisualState = {
	EMPTY = 1,
	ON_COOLDOWN = 2,
	COOLDOWN_ENDING = 3,
	READY = 4,
}

local DeathKnightRunes = {}
DeathKnightRunes.__index = DeathKnightRunes

local function ApproximatelyEqual(a, b, epsilon)
	return math_abs((a or 0) - (b or 0)) <= (epsilon or 0.01)
end

local function SetAlpha(region, alpha)
	if region then
		region:SetAlpha(alpha or 0)
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

local function RestartAnimationGroup(group, startOffset)
	if not group then
		return
	end

	if group.Restart then
		group:Restart(false, startOffset or 0)
	else
		group:Play(false, startOffset or 0)
	end
end

local function StopAnimationGroup(group)
	if group and group:IsPlaying() then
		group:Stop()
	end
end

local function ApplyCooldownSwipeArt(cooldown, artType)
	if not cooldown or not C_Texture or not C_Texture.GetAtlasInfo then
		return
	end

	local atlasInfo = C_Texture.GetAtlasInfo(RUNE_ART_SET.cooldownSwipe:format(artType))
	if not atlasInfo then
		return
	end

	local file = atlasInfo.file or atlasInfo.filename
	if file then
		cooldown:SetSwipeTexture(file)
	end

	if cooldown.SetTexCoordRange then
		local lowTexCoords = {
			x = atlasInfo.leftTexCoord or 0,
			y = atlasInfo.topTexCoord or 0,
		}
		local highTexCoords = {
			x = atlasInfo.rightTexCoord or 1,
			y = atlasInfo.bottomTexCoord or 1,
		}
		cooldown:SetTexCoordRange(lowTexCoords, highTexCoords)
	end
end

local function ApplyDepleteFlipbookArt(texture, artType)
	if not texture then
		return
	end

	texture:SetAtlas(RUNE_ART_SET.depleteFlipbook:format(artType), false)
	texture:SetTexCoord(0, 1, 0, 1)
end

local function ResetDepleteVisualState(slot)
	SetAlpha(slot.Rune_Inactive, 0)
	SetAlpha(slot.Rune_Lines, 0)
	SetAlpha(slot.FB_RuneDeplete, 0)
	SetAlpha(slot.Glow2, 0)
end

local function PrimeDepleteVisualState(slot)
	SetAlpha(slot.Rune_Inactive, 1)
	SetAlpha(slot.Rune_Lines, 1)
	SetAlpha(slot.FB_RuneDeplete, 0)
	SetAlpha(slot.Glow2, 1)
end

function DeathKnightRunes:ApplyEmptyBaseState(rune)
	SetAlpha(rune.BG_Active, 0)
	SetAlpha(rune.BG_Inactive, 1)
	SetAlpha(rune.Rune_Active, 0)
	SetAlpha(rune.Rune_Inactive, 0.4)
	SetAlpha(rune.Rune_Grad, 0)
	SetAlpha(rune.Rune_Lines, 0)
	SetAlpha(rune.Rune_Mid, 0)
	SetAlpha(rune.Rune_Eyes, 0)
	SetAlpha(rune.Glow, 0)
	SetAlpha(rune.Glow2, 0)
	SetAlpha(rune.Smoke, 0)
	rune.Cooldown:Hide()
end

function DeathKnightRunes:ApplyReadyBaseState(rune)
	SetAlpha(rune.BG_Active, 1)
	SetAlpha(rune.BG_Inactive, 0)
	SetAlpha(rune.Rune_Active, 1)
	SetAlpha(rune.Rune_Inactive, 0)
	SetAlpha(rune.Rune_Grad, 0)
	SetAlpha(rune.Rune_Lines, 0)
	SetAlpha(rune.Rune_Mid, 0)
	SetAlpha(rune.Rune_Eyes, 0)
	SetAlpha(rune.Glow, 0)
	SetAlpha(rune.Glow2, 0)
	SetAlpha(rune.Smoke, 0)
	rune.Cooldown:Hide()
end

function DeathKnightRunes:SkipToFinalAnimState(group)
	if group then
		RestartAnimationGroup(group, group:GetDuration())
	end
end

function DeathKnightRunes:CreateSlotVisual(index)
	local slot = CreateFrame("Frame", nil, self.root)
	slot:SetSize(RUNE_SIZE, RUNE_SIZE)
	slot:SetFrameLevel((self.root:GetFrameLevel() or 0) + 10)

	slot.Rune_Inactive = slot:CreateTexture(nil, "OVERLAY", nil, 2)
	slot.Rune_Inactive:SetPoint("CENTER")
	slot.Rune_Inactive:SetAtlas("UF-DKRunes-SkullDis", true)

	slot.Rune_Lines = slot:CreateTexture(nil, "OVERLAY", nil, 2)
	slot.Rune_Lines:SetPoint("CENTER")

	slot.FB_RuneDeplete = slot:CreateTexture(nil, "OVERLAY", nil, 2)
	slot.FB_RuneDeplete:SetSize(20, 36)
	slot.FB_RuneDeplete:SetPoint("CENTER", 0, 10)

	slot.Glow2 = slot:CreateTexture(nil, "OVERLAY", nil, 2)
	slot.Glow2:SetPoint("CENTER")

	slot.DepleteAnim = CreateAnimationGroup(slot, true)
	AddAlpha(slot.DepleteAnim, slot.Rune_Inactive, 1, 0.1, 1, 1)
	AddAlpha(slot.DepleteAnim, slot.FB_RuneDeplete, 1, 0.1, 0, 1)
	AddAlpha(slot.DepleteAnim, slot.Rune_Inactive, 1, 0.67, 1, 0.4)
	AddFlipBook(slot.DepleteAnim, slot.FB_RuneDeplete, 1, 1.0, 4, 6, 23)
	AddAlpha(slot.DepleteAnim, slot.Glow2, 1, 0.4, 1, 0)
	AddAlpha(slot.DepleteAnim, slot.Rune_Lines, 1, 0.4, 1, 1)
	AddAlpha(slot.DepleteAnim, slot.Rune_Lines, 1, 0.43, 1, 0, 0.4)
	AddAlpha(slot.DepleteAnim, slot.FB_RuneDeplete, 1, 0.1, 1, 0, 1.0)
	AddAlpha(slot.DepleteAnim, slot.Rune_Inactive, 1, 0.1, 0.4, 0, 1.0)
	slot.DepleteAnim:SetScript("OnPlay", function()
		PrimeDepleteVisualState(slot)
		slot:Show()
	end)
	slot.DepleteAnim:SetScript("OnFinished", function()
		ResetDepleteVisualState(slot)
		slot:Hide()
	end)

	ResetDepleteVisualState(slot)
	slot:Hide()
	return slot
end

function DeathKnightRunes:CreateRune(runeIndex)
	local rune = CreateFrame("Frame", nil, self.root)
	rune:SetSize(RUNE_SIZE, RUNE_SIZE)
	rune:SetFrameLevel((self.root:GetFrameLevel() or 0) + 1)
	rune.runeIndex = runeIndex
	rune.layoutIndex = 7 - runeIndex
	rune.visualState = nil
	rune.lastRuneState = { start = 0, duration = 0, runeReady = false }
	rune.cooldownFillAnimBasisSeconds = COOLDOWN_FILL_ANIM_BASIS_SECONDS
	rune.cooldownEndingOffsetSeconds = COOLDOWN_ENDING_OFFSET_SECONDS
	rune.cooldownEndingStartTime = nil
	rune.isNewlyDepleted = false

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
	rune.Cooldown:SetDrawSwipe(true)
	rune.Cooldown:SetDrawEdge(true)
	rune.Cooldown:SetUseCircularEdge(true)
	rune.Cooldown:SetEdgeTexture(RUNE_COOLDOWN_EDGE_TEXTURE, 1, 1, 1, 1)
	rune.Cooldown:SetSwipeColor(1, 1, 1, 1)

	rune.CooldownFillAnim = CreateAnimationGroup(rune, true)
	AddAlpha(rune.CooldownFillAnim, rune.Rune_Mid, 1, 0.1, 0, 0)
	AddAlpha(rune.CooldownFillAnim, rune.Rune_Eyes, 1, 0.1, 0, 0)
	AddAlpha(rune.CooldownFillAnim, rune.Smoke, 1, 0.1, 0, 0)
	AddAlpha(rune.CooldownFillAnim, rune.Glow, 1, 0.1, 0, 0)
	AddAlpha(rune.CooldownFillAnim, rune.Rune_Grad, 1, 0.86, 0, 0)
	AddAlpha(rune.CooldownFillAnim, rune.Rune_Lines, 1, 0.1, 0, 0, 0.85)
	AddAlpha(rune.CooldownFillAnim, rune.Rune_Lines, 1, 3.18, 0, 0.16, 0.86)
	AddAlpha(rune.CooldownFillAnim, rune.Rune_Grad, 1, 3.18, 0, 0.3, 0.86)
	AddAlpha(rune.CooldownFillAnim, rune.Rune_Lines, 1, 2.83, 0.16, 0.3, 4.0)

	rune.CooldownEndingAnim = CreateAnimationGroup(rune, true)
	AddAlpha(rune.CooldownEndingAnim, rune.Rune_Mid, 1, 0.47, 0, 1)
	AddAlpha(rune.CooldownEndingAnim, rune.Rune_Eyes, 1, 0.43, 0, 1, 0.24)
	AddAlpha(rune.CooldownEndingAnim, rune.Smoke, 1, 0.5, 0, 1, 0.34)
	AddTranslation(rune.CooldownEndingAnim, rune.Smoke, 1, 0.7, 0, 12, 0.34)
	AddAlpha(rune.CooldownEndingAnim, rune.Rune_Lines, 1, 0.17, 1, 0, 0.67)
	AddAlpha(rune.CooldownEndingAnim, rune.Rune_Grad, 1, 0.01, 1, 0, 0.67)
	AddAlpha(rune.CooldownEndingAnim, rune.Rune_Inactive, 1, 0.01, 1, 0, 0.67)
	AddAlpha(rune.CooldownEndingAnim, rune.BG_Active, 1, 0.01, 0, 1, 0.67)
	AddAlpha(rune.CooldownEndingAnim, rune.BG_Inactive, 1, 0.01, 1, 0, 0.67)
	AddAlpha(rune.CooldownEndingAnim, rune.Glow, 1, 0, 1, 1, 0.67)
	AddAlpha(rune.CooldownEndingAnim, rune.Glow2, 1, 0, 1, 1, 0.67)
	AddAlpha(rune.CooldownEndingAnim, rune.Rune_Active, 1, 0.01, 0, 1, 0.77)
	AddAlpha(rune.CooldownEndingAnim, rune.Rune_Mid, 1, 0.4, 1, 0, 0.77)
	AddAlpha(rune.CooldownEndingAnim, rune.Smoke, 1, 0.2, 1, 0, 0.83)
	AddAlpha(rune.CooldownEndingAnim, rune.Glow, 1, 0.23, 1, 0, 0.84)
	AddAlpha(rune.CooldownEndingAnim, rune.Glow2, 1, 0.17, 1, 0, 1.0)
	AddAlpha(rune.CooldownEndingAnim, rune.Rune_Eyes, 1, 0.5, 1, 0, 1.14)

	rune.EmptyAnim = CreateAnimationGroup(rune, true)
	AddAlpha(rune.EmptyAnim, rune.BG_Active, 1, 0.1, 0, 0)
	AddAlpha(rune.EmptyAnim, rune.BG_Inactive, 1, 0.1, 1, 1)
	AddAlpha(rune.EmptyAnim, rune.Rune_Active, 1, 0.1, 0, 0)
	AddAlpha(rune.EmptyAnim, rune.Rune_Inactive, 1, 0.1, 1, 0.4)
	AddAlpha(rune.EmptyAnim, rune.Rune_Lines, 1, 0.1, 1, 0)

	rune.Cooldown:SetScript("OnUpdate", function()
		self:OnCooldownUpdate(rune)
	end)

	self:ApplyEmptyBaseState(rune)
	return rune
end

function DeathKnightRunes:ApplyRuneArt(rune, specIndex)
	local artType = ART_TYPE_BY_SPEC[specIndex] or DEFAULT_ART_TYPE

	ApplyCooldownSwipeArt(rune.Cooldown, artType)
	rune.Rune_Grad:SetAtlas(("UF-DKRunes-%s-SkullGrad"):format(artType), true)
	rune.Rune_Lines:SetAtlas(("UF-DKRunes-%s-SkullLines"):format(artType), true)
	rune.Rune_Active:SetAtlas(("UF-DKRunes-%s-SkullActive"):format(artType), true)
	rune.Rune_Mid:SetAtlas(("UF-DKRunes-%s-SkullMid"):format(artType), true)
	rune.Rune_Eyes:SetAtlas(("UF-DKRunes-%s-Eyes"):format(artType), true)
	rune.Glow:SetAtlas(("UF-DKRunes-%s-FilledGlwA"):format(artType), true)
	rune.Glow2:SetAtlas(("UF-DKRunes-%s-FilledGlwB"):format(artType), true)
	rune.Smoke:SetAtlas(("UF-DKRunes-%s-Smoke"):format(artType), true)
end

function DeathKnightRunes:ApplySlotVisualArt(slot, specIndex)
	local artType = ART_TYPE_BY_SPEC[specIndex] or DEFAULT_ART_TYPE

	slot.Rune_Lines:SetAtlas(("UF-DKRunes-%s-SkullLines"):format(artType), true)
	slot.Glow2:SetAtlas(("UF-DKRunes-%s-FilledGlwB"):format(artType), true)
	ApplyDepleteFlipbookArt(slot.FB_RuneDeplete, artType)
end

function DeathKnightRunes:PlayDepleteVisual(slot)
	if not slot then
		return
	end

	ResetDepleteVisualState(slot)
	RestartAnimationGroup(slot.DepleteAnim)
end

function DeathKnightRunes:UpdateLayoutIndex(rune, layoutIndex)
	if rune.layoutIndex == layoutIndex then
		return false
	end

	rune.layoutIndex = layoutIndex
	return true
end

function DeathKnightRunes:ShowAsReady(rune, previousState)
	if rune.EmptyAnim:IsPlaying() then
		self:SkipToFinalAnimState(rune.EmptyAnim)
	end

	if rune.CooldownFillAnim:IsPlaying() then
		self:SkipToFinalAnimState(rune.CooldownFillAnim)
	end

	if not rune.CooldownEndingAnim:IsPlaying() and previousState ~= VisualState.READY then
		self:SkipToFinalAnimState(rune.CooldownEndingAnim)
	end

	rune.visualState = VisualState.READY
	rune.cooldownEndingStartTime = nil
	rune.Cooldown:Clear()
	self:ApplyReadyBaseState(rune)
end

function DeathKnightRunes:ShowAsEmpty(rune)
	if rune.CooldownFillAnim:IsPlaying() then
		self:SkipToFinalAnimState(rune.CooldownFillAnim)
	end
	if rune.CooldownEndingAnim:IsPlaying() then
		self:SkipToFinalAnimState(rune.CooldownEndingAnim)
	end
	if not rune.EmptyAnim:IsPlaying() then
		self:SkipToFinalAnimState(rune.EmptyAnim)
	end
	rune.Cooldown:Clear()
	rune.cooldownEndingStartTime = nil
	rune.visualState = VisualState.EMPTY
	rune.isNewlyDepleted = true
	self:ApplyEmptyBaseState(rune)
end

function DeathKnightRunes:ShowAsOnCooldown(rune, start, duration, previousState)
	local timeEpsilon = 0.01
	local oldStart, oldDuration = rune.Cooldown:GetCooldownTimes()
	local oldEnd = (oldStart + oldDuration) / 1000
	local newEnd = start + duration
	if ApproximatelyEqual(oldEnd, newEnd, timeEpsilon) and rune.CooldownFillAnim:IsPlaying() then
		return
	end

	local timeNow = GetTime()
	local timeNowFloored = math_floor(timeNow)

	rune.cooldownEndingStartTime = (start + duration) - rune.cooldownEndingOffsetSeconds
	local isBeforeCooldownEndStartTime = timeNowFloored < math_floor(rune.cooldownEndingStartTime)

	if previousState == nil or (isBeforeCooldownEndStartTime and rune.CooldownEndingAnim:IsPlaying()) then
		self:SkipToFinalAnimState(rune.CooldownEndingAnim)
	end

	if previousState == nil or previousState == VisualState.READY or (previousState == VisualState.COOLDOWN_ENDING and isBeforeCooldownEndStartTime) then
		RestartAnimationGroup(rune.EmptyAnim)
		rune.visualState = VisualState.EMPTY
		rune.isNewlyDepleted = true
	end

	rune.Cooldown:SetCooldown(start, duration)
	rune.Cooldown:Show()

	if isBeforeCooldownEndStartTime and timeNowFloored >= math_floor(start) then
		local speedMultiplier = rune.cooldownFillAnimBasisSeconds / duration
		local startOffset = timeNow - start
		local shouldRestartFillAnim = true

		if rune.CooldownFillAnim:IsPlaying() then
			local currentMultiplier = rune.CooldownFillAnim:GetAnimationSpeedMultiplier()
			local currentElapsed = rune.CooldownFillAnim:GetElapsed()
			if ApproximatelyEqual(currentMultiplier, speedMultiplier, timeEpsilon) and ApproximatelyEqual(currentElapsed, startOffset, timeEpsilon) then
				shouldRestartFillAnim = false
			end
		end

		if shouldRestartFillAnim then
			rune.CooldownFillAnim:SetAnimationSpeedMultiplier(speedMultiplier)
			RestartAnimationGroup(rune.CooldownFillAnim, startOffset)
		end

		rune.visualState = VisualState.ON_COOLDOWN
	else
		self:OnCooldownUpdate(rune)
	end
end

function DeathKnightRunes:OnCooldownUpdate(rune)
	if not rune.cooldownEndingStartTime then
		return
	end

	local timeNow = GetTime()
	if timeNow >= rune.cooldownEndingStartTime then
		local animStartOffset = timeNow - rune.cooldownEndingStartTime

		StopAnimationGroup(rune.CooldownFillAnim)
		RestartAnimationGroup(rune.CooldownEndingAnim, animStartOffset)
		rune.cooldownEndingStartTime = nil
		rune.visualState = VisualState.COOLDOWN_ENDING
	end
end

function DeathKnightRunes:UpdateRuneState(rune)
	local previousState = rune.visualState

	rune.isNewlyDepleted = false

	local start, duration, runeReady = GetRuneCooldown(rune.runeIndex)
	rune.lastRuneState = {
		start = start or 0,
		duration = duration or 0,
		runeReady = runeReady and true or false,
	}

	if not runeReady then
		if start then
			self:ShowAsOnCooldown(rune, start, duration, previousState)
		elseif previousState ~= VisualState.EMPTY then
			self:ShowAsEmpty(rune)
		end
	else
		self:ShowAsReady(rune, previousState)
	end
end

function DeathKnightRunes:CompareRunes(runeA, runeB)
	local stateA = runeA.visualState
	local stateB = runeB.visualState

	if stateA == nil or stateB == nil then
		if stateA == nil and stateB == nil then
			return runeA.runeIndex > runeB.runeIndex
		end
		return stateA ~= nil
	end

	if stateA ~= stateB then
		return stateA > stateB
	end

	if stateA == VisualState.READY then
		local playingA = runeA.CooldownEndingAnim:IsPlaying()
		local playingB = runeB.CooldownEndingAnim:IsPlaying()
		if playingA ~= playingB then
			return not playingA
		end

		local progressA = runeA.CooldownEndingAnim:GetProgress()
		local progressB = runeB.CooldownEndingAnim:GetProgress()
		if progressA ~= progressB then
			return progressA > progressB
		end
	end

	local startA = runeA.lastRuneState.start
	local startB = runeB.lastRuneState.start
	if startA ~= startB then
		return startA < startB
	end

	return runeA.runeIndex > runeB.runeIndex
end

function DeathKnightRunes:ApplyRuneLayout()
	local total = (#self.runes * RUNE_SIZE) + ((#self.runes - 1) * RUNE_SPACING)
	local x0 = -(total / 2) + (RUNE_SIZE / 2)

	for layoutIndex = 1, #self.runes do
		local x = x0 + ((layoutIndex - 1) * (RUNE_SIZE + RUNE_SPACING))
		local slot = self.slotVisuals[layoutIndex]
		if slot then
			slot:ClearAllPoints()
			slot:SetPoint("CENTER", self.root, "CENTER", x, 0)
		end
	end

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
		self.slotVisuals[i] = self:CreateSlotVisual(i)
		self.runes[i] = self:CreateRune(i)
		self.runeIndices[i] = i
	end

	self:ApplyRuneLayout()
end

function DeathKnightRunes:Shutdown()
	self.activeResource = nil

	for i = 1, #self.slotVisuals do
		local slot = self.slotVisuals[i]
		if slot then
			StopAnimationGroup(slot.DepleteAnim)
			ResetDepleteVisualState(slot)
			slot:Hide()
		end
	end

	for i = 1, #self.runes do
		local rune = self.runes[i]
		if rune then
			StopAnimationGroup(rune.CooldownFillAnim)
			StopAnimationGroup(rune.CooldownEndingAnim)
			StopAnimationGroup(rune.EmptyAnim)
			rune.Cooldown:Clear()
			rune.Cooldown:Hide()
		end
	end

	if self.root then
		self.root:Hide()
	end
end

function DeathKnightRunes:SetResource(resourceDef, resolved)
	self.activeResource = resourceDef

	local specIndex = resolved and resolved.context and resolved.context.spec or GetSpecialization()
	for i = 1, #self.runes do
		self:ApplyRuneArt(self.runes[i], specIndex)
		self:ApplySlotVisualArt(self.slotVisuals[i], specIndex)
		StopAnimationGroup(self.slotVisuals[i].DepleteAnim)
		ResetDepleteVisualState(self.slotVisuals[i])
		self.slotVisuals[i]:Hide()
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
	else
		self.root:Hide()
	end
end

function DeathKnightRunes:Sync()
	if not self.activeResource or not self.root then
		return
	end

	local numNewlyDepleted = 0

	for i = 1, #self.runes do
		self:UpdateRuneState(self.runes[i])
		if self.runes[i].isNewlyDepleted then
			numNewlyDepleted = numNewlyDepleted + 1
		end
	end

	table.sort(self.runeIndices, function(aIndex, bIndex)
		return self:CompareRunes(self.runes[aIndex], self.runes[bIndex])
	end)

	local anyLayoutUpdates = false
	for newLayoutIndex, runeIndex in ipairs(self.runeIndices) do
		local rune = self.runes[runeIndex]
		if self:UpdateLayoutIndex(rune, newLayoutIndex) then
			anyLayoutUpdates = true
		end

		if numNewlyDepleted > 0 and rune.visualState ~= VisualState.READY then
			self:PlayDepleteVisual(self.slotVisuals[newLayoutIndex])
			numNewlyDepleted = numNewlyDepleted - 1
		end
	end

	if anyLayoutUpdates then
		self:ApplyRuneLayout()
	end
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
		slotVisuals = {},
		runeIndices = {},
		activeResource = nil,
	}, DeathKnightRunes)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.DEATH_KNIGHT_RUNES, CreateDeathKnightRunes)
