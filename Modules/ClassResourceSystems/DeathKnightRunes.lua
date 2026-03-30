-- SparkPoint Death Knight Runes Class Resource System
-- Dedicated DK implementation with independent rune widgets and state-based ordering.

local _, addon = ...
local ResourceModel = addon.ResourceModel
local ClassResourceSystems = addon.ClassResourceSystems

local C_Texture = C_Texture
local GetRuneCooldown = GetRuneCooldown
local GetSpecialization = GetSpecialization
local GetTime = GetTime
local math_floor = math.floor

local RUNE_SIZE = 24
local RUNE_SPACING = -1
local RUNE_COOLDOWN_SIZE = 27
local RUNE_COOLDOWN_EDGE_TEXTURE = "Interface\\PlayerFrame\\DK-BloodUnholy-Rune-CDSpark"
local RUNE_UPDATE_INTERVAL = 0.05
local COOLDOWN_ENDING_OFFSET_SECONDS = 0.67
local EMPTY_TRANSITION_DURATION = 0.10
local DEPLETE_VISUAL_DURATION = 1.0
local DEPLETE_VISUAL_FADE_START = 0.83

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

local function SetAlpha(region, alpha)
	if region then
		region:SetAlpha(alpha)
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
	if not texture or not C_Texture or not C_Texture.GetAtlasInfo then
		return
	end

	local atlasInfo = C_Texture.GetAtlasInfo(RUNE_ART_SET.depleteFlipbook:format(artType))
	if not atlasInfo then
		return
	end

	local file = atlasInfo.file or atlasInfo.filename
	if not file then
		return
	end

	texture:SetTexture(file)
	texture.flipbookAtlasInfo = atlasInfo
end

local function SetFlipbookFrame(texture, frameIndex, totalFrames, columns, rows)
	local atlasInfo = texture and texture.flipbookAtlasInfo
	if not atlasInfo then
		return
	end

	local clampedIndex = math.max(0, math.min(totalFrames - 1, frameIndex))
	local column = clampedIndex % columns
	local row = math_floor(clampedIndex / columns)
	local uWidth = ((atlasInfo.rightTexCoord or 1) - (atlasInfo.leftTexCoord or 0)) / columns
	local vHeight = ((atlasInfo.bottomTexCoord or 1) - (atlasInfo.topTexCoord or 0)) / rows
	local u1 = (atlasInfo.leftTexCoord or 0) + (column * uWidth)
	local u2 = u1 + uWidth
	local v1 = (atlasInfo.topTexCoord or 0) + (row * vHeight)
	local v2 = v1 + vHeight
	texture:SetTexCoord(u1, u2, v1, v2)
end

function DeathKnightRunes:CreateRune(runeIndex)
	local rune = CreateFrame("Frame", nil, self.root)
	rune:SetSize(RUNE_SIZE, RUNE_SIZE)
	rune:SetFrameLevel((self.root:GetFrameLevel() or 0) + 1)
	rune.runeIndex = runeIndex
	rune.layoutIndex = 7 - runeIndex
	rune.visualState = nil
	rune.lastRuneState = { start = 0, duration = 0, runeReady = false }
	rune.cooldownEndingStartTime = nil
	rune.cooldownEndingAnimStartTime = nil
	rune.emptyAnimStartTime = nil
	rune.pendingCooldownStart = nil
	rune.pendingCooldownDuration = nil
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

	return rune
end

function DeathKnightRunes:CreateSlotVisual(index)
	local slot = CreateFrame("Frame", nil, self.root)
	slot:SetSize(RUNE_SIZE, RUNE_SIZE)
	slot:SetFrameLevel((self.root:GetFrameLevel() or 0) + 10)
	slot.index = index
	slot.depleteStartTime = nil

	slot.Rune_Inactive = slot:CreateTexture(nil, "OVERLAY", nil, 2)
	slot.Rune_Inactive:SetPoint("CENTER")
	slot.Rune_Inactive:SetAtlas("UF-DKRunes-SkullDis", true)
	slot.Rune_Inactive:SetAlpha(0)

	slot.Rune_Lines = slot:CreateTexture(nil, "OVERLAY", nil, 2)
	slot.Rune_Lines:SetPoint("CENTER")
	slot.Rune_Lines:SetAlpha(0)

	slot.FB_RuneDeplete = slot:CreateTexture(nil, "OVERLAY", nil, 2)
	slot.FB_RuneDeplete:SetSize(20, 36)
	slot.FB_RuneDeplete:SetPoint("CENTER", 0, 10)
	slot.FB_RuneDeplete:SetAlpha(0)

	slot.Glow2 = slot:CreateTexture(nil, "OVERLAY", nil, 2)
	slot.Glow2:SetPoint("CENTER")
	slot.Glow2:SetAlpha(0)

	slot:Hide()
	return slot
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
	SetFlipbookFrame(slot.FB_RuneDeplete, 0, 23, 6, 4)
end

function DeathKnightRunes:ShowAsReady(rune)
	rune.visualState = VisualState.READY
	rune.cooldownEndingStartTime = nil
	rune.cooldownEndingAnimStartTime = nil
	rune.emptyAnimStartTime = nil
	rune.pendingCooldownStart = nil
	rune.pendingCooldownDuration = nil
	rune.Cooldown:Clear()
end

function DeathKnightRunes:ShowAsEmpty(rune, now)
	rune.visualState = VisualState.EMPTY
	rune.cooldownEndingStartTime = nil
	rune.cooldownEndingAnimStartTime = nil
	rune.emptyAnimStartTime = now or GetTime()
	rune.Cooldown:Clear()
	rune.isNewlyDepleted = true
end

function DeathKnightRunes:ShowAsOnCooldown(rune, start, duration, previousState, now)
	local previousEndTime = rune.lastRuneState and ((rune.lastRuneState.start or 0) + (rune.lastRuneState.duration or 0)) or 0
	local newEndTime = (start or 0) + (duration or 0)
	local sameCooldown = math.abs(previousEndTime - newEndTime) < 0.01

	rune.cooldownEndingStartTime = math.max(start or 0, newEndTime - COOLDOWN_ENDING_OFFSET_SECONDS)

	if previousState == nil or previousState == VisualState.READY or (previousState == VisualState.COOLDOWN_ENDING and now < rune.cooldownEndingStartTime) then
		self:ShowAsEmpty(rune, now)
		rune.pendingCooldownStart = start
		rune.pendingCooldownDuration = duration
		return
	end

	if rune.emptyAnimStartTime and (now - rune.emptyAnimStartTime) < EMPTY_TRANSITION_DURATION then
		rune.pendingCooldownStart = start
		rune.pendingCooldownDuration = duration
		rune.visualState = VisualState.EMPTY
		return
	end

	rune.emptyAnimStartTime = nil
	rune.pendingCooldownStart = nil
	rune.pendingCooldownDuration = nil

	rune.Cooldown:SetCooldown(start, duration)

	if now >= rune.cooldownEndingStartTime then
		rune.visualState = VisualState.COOLDOWN_ENDING
		if not rune.cooldownEndingAnimStartTime or not sameCooldown then
			rune.cooldownEndingAnimStartTime = now
		end
	else
		rune.visualState = VisualState.ON_COOLDOWN
		rune.cooldownEndingAnimStartTime = nil
	end
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
		SetAlpha(rune.Glow, 0)
		SetAlpha(rune.Glow2, 0)
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
		SetAlpha(rune.Rune_Inactive, 0.40)
		SetAlpha(rune.Rune_Grad, 0.30 * progress)
		SetAlpha(rune.Rune_Lines, 0.30 * math.max(0, (progress - 0.15) / 0.85))
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

	local endingStart = rune.cooldownEndingAnimStartTime or rune.cooldownEndingStartTime or now
	local endingProgress = math.max(0, math.min(1, (now - endingStart) / COOLDOWN_ENDING_OFFSET_SECONDS))
	if endingProgress >= 1 then
		self:ShowAsReady(rune)
		self:ApplyVisualState(rune, now)
		return
	end

	SetAlpha(rune.BG_Inactive, 0)
	SetAlpha(rune.BG_Active, 1)
	SetAlpha(rune.Rune_Inactive, 0)
	SetAlpha(rune.Rune_Grad, 0)
	SetAlpha(rune.Rune_Lines, math.max(0, 1 - math.max(0, (endingProgress - 0.67) / 0.17)))
	SetAlpha(rune.Rune_Active, 1)
	SetAlpha(rune.Rune_Mid, math.max(0, 1 - math.max(0, (endingProgress - 0.15) / 0.60)))
	SetAlpha(rune.Rune_Eyes, math.min(1, math.max(0, (endingProgress - 0.24) / 0.43)))
	SetAlpha(rune.Glow, math.max(0, 1 - math.max(0, (endingProgress - 0.84) / 0.23)))
	SetAlpha(rune.Glow2, math.max(0, 1 - math.max(0, (endingProgress - 1.00) / 0.17)))
	SetAlpha(rune.Smoke, math.max(0, 1 - math.max(0, (endingProgress - 0.83) / 0.20)))
	rune.Cooldown:Show()
	rune.Cooldown:SetCooldown(start, duration)
end

function DeathKnightRunes:UpdateRuneState(rune, now)
	local previousState = rune.visualState
	local start, duration, runeReady = GetRuneCooldown(rune.runeIndex)
	rune.isNewlyDepleted = false

	if not runeReady then
		if start and start > 0 and duration and duration > 0 then
			self:ShowAsOnCooldown(rune, start, duration, previousState, now)
		elseif previousState ~= VisualState.EMPTY then
			self:ShowAsEmpty(rune, now)
		end
	else
		self:ShowAsReady(rune)
	end

	rune.lastRuneState = {
		start = start or 0,
		duration = duration or 0,
		runeReady = runeReady and true or false,
	}

	self:ApplyVisualState(rune, now)
	return rune.visualState == VisualState.ON_COOLDOWN or rune.visualState == VisualState.COOLDOWN_ENDING
end

function DeathKnightRunes:PlayDepleteVisual(slot)
	if not slot then
		return
	end

	slot.depleteStartTime = GetTime()
	SetAlpha(slot.Rune_Inactive, 1)
	SetAlpha(slot.Rune_Lines, 1)
	SetAlpha(slot.FB_RuneDeplete, 0)
	SetAlpha(slot.Glow2, 1)
	slot:Show()
end

function DeathKnightRunes:UpdateDepleteVisual(slot, now)
	if not slot or not slot.depleteStartTime then
		return false
	end

	local elapsed = now - slot.depleteStartTime
	if elapsed >= DEPLETE_VISUAL_DURATION then
		slot.depleteStartTime = nil
		slot:Hide()
		return false
	end

	local progress = math.max(0, math.min(1, elapsed / DEPLETE_VISUAL_DURATION))
	local fadeProgress = 0
	if progress > DEPLETE_VISUAL_FADE_START then
		fadeProgress = (progress - DEPLETE_VISUAL_FADE_START) / (1 - DEPLETE_VISUAL_FADE_START)
	end

	local frameIndex = math.min(22, math_floor(progress * 23))
	SetFlipbookFrame(slot.FB_RuneDeplete, frameIndex, 23, 6, 4)
	SetAlpha(slot.FB_RuneDeplete, progress < 0.1 and (progress / 0.1) or math.max(0, 1 - fadeProgress))
	SetAlpha(slot.Glow2, math.max(0, 1 - math.min(1, progress / 0.4)))
	SetAlpha(slot.Rune_Lines, progress < 0.4 and 1 or math.max(0, 1 - ((progress - 0.4) / 0.43)))
	SetAlpha(slot.Rune_Inactive, progress < 0.67 and (1 - (0.6 * (progress / 0.67))) or math.max(0, 0.4 * (1 - fadeProgress)))
	slot:Show()
	return true
end

function DeathKnightRunes:CompareRunes(runeA, runeB)
	local stateA = runeA.visualState or VisualState.EMPTY
	local stateB = runeB.visualState or VisualState.EMPTY

	if stateA ~= stateB then
		return stateA > stateB
	end

	if stateA == VisualState.READY then
		local endingA = runeA.cooldownEndingAnimStartTime ~= nil
		local endingB = runeB.cooldownEndingAnimStartTime ~= nil
		if endingA ~= endingB then
			return not endingA
		end
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

function DeathKnightRunes:UpdateTicker(anyCharging, anyAnimating)
	if not self.root then
		return
	end

	if anyCharging or anyAnimating then
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
		self.slotVisuals[i] = self:CreateSlotVisual(i)
		self.runes[i] = self:CreateRune(i)
		self.runeIndices[i] = i
	end

	self:ApplyRuneLayout()
end

function DeathKnightRunes:Shutdown()
	self.activeResource = nil
	self.resolved = nil
	self:UpdateTicker(false, false)
	for i = 1, #self.slotVisuals do
		local slot = self.slotVisuals[i]
		if slot then
			slot.depleteStartTime = nil
			slot:Hide()
		end
	end

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
		self:ApplySlotVisualArt(self.slotVisuals[i], specIndex)
		self.slotVisuals[i].depleteStartTime = nil
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
		return
	end

	self.root:Hide()
	self:UpdateTicker(false, false)
end

function DeathKnightRunes:Sync()
	if not self.activeResource or not self.root then
		return
	end

	local anyCharging = false
	local anyAnimating = false
	local now = GetTime()
	local numNewlyDepleted = 0

	for i = 1, #self.runes do
		if self:UpdateRuneState(self.runes[i], now) then
			anyCharging = true
		end
		if self.runes[i].isNewlyDepleted then
			numNewlyDepleted = numNewlyDepleted + 1
		end
	end

	table.sort(self.runeIndices, function(aIndex, bIndex)
		return self:CompareRunes(self.runes[aIndex], self.runes[bIndex])
	end)

	self:ApplyRuneLayout()

	if numNewlyDepleted > 0 then
		for layoutIndex, runeIndex in ipairs(self.runeIndices) do
			local rune = self.runes[runeIndex]
			if rune and rune.visualState ~= VisualState.READY then
				self:PlayDepleteVisual(self.slotVisuals[layoutIndex])
				numNewlyDepleted = numNewlyDepleted - 1
				if numNewlyDepleted <= 0 then
					break
				end
			end
		end
	end

	for i = 1, #self.slotVisuals do
		if self:UpdateDepleteVisual(self.slotVisuals[i], now) then
			anyAnimating = true
		end
	end

	self:UpdateTicker(anyCharging, anyAnimating)
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
		resolved = nil,
		elapsed = 0,
	}, DeathKnightRunes)
end

ClassResourceSystems:Register(ResourceModel.SystemIDs.DEATH_KNIGHT_RUNES, CreateDeathKnightRunes)
