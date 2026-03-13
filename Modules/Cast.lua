-- SparkPoint Cast Module
-- Displays a ring around cursor during spell casting with latency indicator

local _, addon = ...
local L = addon.L
local API = addon.API
local IconMask = addon.IconMask
local DonutWidget = addon.DonutWidget
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local Visibility = addon.Visibility
local Transition = addon.Transition
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor
local GetDBColorTable = addon.GetDBColorTable

local SlotRingWidget = addon.SlotRingWidget
local SlotProviders = addon.SlotProviders

local Cast
local SPELL_ICON_COOLDOWN_SWIPE_PATH = addon.addonFolder .. "\\Textures\\spell_icon_cooldown_swipe.png"
local SPELL_ICON_ERROR_PATH = addon.addonFolder .. "\\Textures\\spell_icon_error.png"
local CAST_FEEDBACK_PATH = addon.addonFolder .. "\\Textures\\cast_feedback.png"
local SPELL_ICON_MASK_BASE_EXPAND = 6

--------------------------------------------------------------------------------
-- Inner Ring Slot Constants
--------------------------------------------------------------------------------
local NUM_SLOTS = 3
-- Slot textures are authored on a shared 1024x1024 root map with baked sizing.
-- Use one scale reference (cast_radius) and let each texture encode its own diameter.
local SLOT_ROOT_SCALE = { 1, 1, 1 }
-- Fill centerline radius ratios (measured from slot{N}_fill.png on 1024 map).
local SLOT_SPARK_RADIUS_RATIOS = { 0.5929, 0.4875, 0.3819 }

--------------------------------------------------------------------------------
-- Module State
--------------------------------------------------------------------------------
local castFrame
local castDonut, latencyDonut
local isCasting = false
local isChanneling = false
local castStartTime, castEndTime, castDuration
local castLatency = 0
local castGlowMaxOpacity = 0.8
local castSent = 0
local currentCastGUID = nil
local currentSpellName = ""
local currentSpellID
local currentSpellTexture
local spellIconEnabled = false
local pendingVisuals = false
local instantIconActive = false
local instantIconExpiry = 0
local instantIconForcedShell = false
local instantIconConfirmed = false
local instantIconMode = "instant"
local instantIconCooldownStart = 0
local instantIconCooldownDuration = 0
local lastAttemptedSpellID
local lastAttemptedActionSlot
local lastAttemptedAt = 0
local lastSentSpellID
local lastSentAt = 0
local lastSentCastGUID
local pendingInstantResolvedSpellID
local pendingInstantAt = 0
local pendingInstantCastGUID
local pendingInstantSource
local interruptFlashToken = 0
local interruptFlashActive = false
local INTERRUPT_FLASH_DURATION = 0.2
local INSTANT_PENDING_WINDOW = 0.75
local FAILED_ATTEMPT_FEEDBACK_DURATION = 0.45
local LAST_ATTEMPT_WINDOW = 0.35
local LAST_SENT_WINDOW = 0.35
local ACTION_COOLDOWN_FEEDBACK_WINDOW = 0.6
local PENDING_SOURCE_SENT = "sent"
local PENDING_SOURCE_ACTION = "action"
local CAST_OVERLAY_DEFAULT = "cast_glow"
local CAST_OVERLAY_INTERRUPT = "cast_error"

-- Inner ring slots
local slots = {} -- {widget, provider, providerID} per slot
local activeProviders = {}
local moduleEnabled = false
local clickFeedbackLeftDown = false
local clickFeedbackRightDown = false

local GetTime = GetTime
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local IsMouseButtonDown = IsMouseButtonDown
local cos, sin, rad = math.cos, math.sin, math.rad
local ShouldShowPlayerInstantCasts
local ShouldShowTriggeredInstantCasts
local ShouldShowAnyInstantCasts
local GetFailedAttemptFeedbackStyle
local ShouldShowAnySpellIconFeedback
local ClearInstantIcon
local ShowCooldownBlockedIcon
local IsConfirmedInstantIconActiveForSpell
local ShouldPreserveConfirmedInstantIcon
local TryShowActionCooldownBlocked
local rejectedAttemptToken = 0

local function NormalizeProviderID(providerID)
	if type(providerID) ~= "string" then
		return "NONE"
	end
	local normalized = string.upper(providerID)
	if normalized == "" then
		return "NONE"
	end
	return normalized
end

local function DisableSlotProviders()
	for id, provider in pairs(activeProviders) do
		if provider and provider.Disable then
			provider:Disable()
		end
		activeProviders[id] = nil
	end
end

local function GetSlotBarColor(slotIndex, providerResult)
	if GetDBBool("slot" .. slotIndex .. "_useClassColor") then
		local r, g, b, a = API.GetPlayerClassColor()
		return { r = r, g = g, b = b, a = a }
	end
	if providerResult and providerResult.barColor then
		return providerResult.barColor
	end
	return GetDBColorTable("slot" .. slotIndex .. "_barColor")
end

local function SetTextureSmooth(texture, texturePath)
	if not texture then
		return
	end
	local ok = pcall(texture.SetTexture, texture, texturePath, nil, nil, "TRILINEAR")
	if not ok then
		texture:SetTexture(texturePath)
	end
	if texture.SetSnapToPixelGrid then
		texture:SetSnapToPixelGrid(false)
	end
	if texture.SetTexelSnappingBias then
		texture:SetTexelSnappingBias(0)
	end
end

local function IsCastVisibilityAllowed()
	return (not Visibility) or Visibility:ShouldShow("cast")
end

local function ShouldShowCurrentCastProgress()
	local mode = GetDBValue("cast_displayMode")
	if mode == "CHANNEL" then
		return isChanneling
	end
	if mode == "NON_CHANNEL" then
		return not isChanneling
	end
	return true
end

local function GetActiveCastBarColor()
	local source = GetDBValue("cast_fillColorSource")
	if source == "CLASS" then
		local r, g, b, a = API.GetPlayerClassColor()
		return { r = r, g = g, b = b, a = a }
	end
	if source == "SPLIT" and isChanneling then
		return GetDBColorTable("cast_channelBarColor")
	end
	return GetDBColorTable("cast_barColor")
end

local function ShouldBypassHoverHideForInstantIcon()
	if not Visibility then
		return false
	end
	if not instantIconActive or isCasting or interruptFlashActive then
		return false
	end
	if not ShouldShowAnySpellIconFeedback() or not spellIconEnabled then
		return false
	end
	if not Visibility:ShouldHideOnUIHover() then
		return false
	end
	if not Visibility:GetModuleHideOnUIHover("cast") then
		return false
	end
	return Visibility:EvaluateRules(Visibility:GetModuleRules("cast"))
end

local function IsInstantIconVisibilityAllowed()
	if IsCastVisibilityAllowed() then
		return true
	end
	return ShouldBypassHoverHideForInstantIcon()
end

ShouldShowPlayerInstantCasts = function()
	return GetDBBool("spellicon_showInstantCasts")
end

ShouldShowTriggeredInstantCasts = function()
	return GetDBBool("spellicon_showTriggeredInstantCasts")
end

ShouldShowAnyInstantCasts = function()
	return ShouldShowPlayerInstantCasts() or ShouldShowTriggeredInstantCasts()
end

GetFailedAttemptFeedbackStyle = function()
	return GetDBValue("spellicon_failedCastStyle") or "HIDE"
end

local function ShouldShowFailedAttempts()
	return GetFailedAttemptFeedbackStyle() ~= "HIDE"
end

local function ShouldShowCooldownBlockedFeedback()
	return GetDBBool("spellicon_showCooldownBlocked")
end

ShouldShowAnySpellIconFeedback = function()
	return ShouldShowAnyInstantCasts() or ShouldShowFailedAttempts() or ShouldShowCooldownBlockedFeedback()
end

local function NormalizeSpellID(spellID)
	local numeric = tonumber(spellID)
	if numeric and numeric > 0 then
		return numeric
	end
	return nil
end

local function GetBaseSpellID(spellID)
	local normalized = NormalizeSpellID(spellID)
	if not normalized or not FindBaseSpellByID then
		return normalized
	end

	local _, baseSpellID = pcall(FindBaseSpellByID, normalized)
	baseSpellID = NormalizeSpellID(baseSpellID)
	return baseSpellID or normalized
end

local function GetOverrideSpellID(spellID)
	local normalized = NormalizeSpellID(spellID)
	if not normalized or not FindSpellOverrideByID then
		return normalized
	end

	local ok, overrideSpellID = pcall(FindSpellOverrideByID, normalized)
	if not ok then
		return normalized
	end
	overrideSpellID = NormalizeSpellID(overrideSpellID)
	return overrideSpellID or normalized
end

local function BuildSpellCandidateList(spellID)
	local normalized = NormalizeSpellID(spellID)
	local candidates = {}
	local seen = {}

	local function AddCandidate(candidate)
		candidate = NormalizeSpellID(candidate)
		if not candidate or seen[candidate] then
			return
		end
		seen[candidate] = true
		candidates[#candidates + 1] = candidate
	end

	if normalized then
		local baseSpellID = GetBaseSpellID(normalized)
		local overrideSpellID = GetOverrideSpellID(normalized)
		AddCandidate(overrideSpellID)
		AddCandidate(normalized)
		AddCandidate(baseSpellID)
		AddCandidate(GetOverrideSpellID(baseSpellID))
		AddCandidate(GetBaseSpellID(overrideSpellID))
	end

	return candidates
end

local function GetFirstActionSlotForSpell(spellID)
	if not (spellID and C_ActionBar and C_ActionBar.FindSpellActionButtons) then
		return nil
	end

	local slots = C_ActionBar.FindSpellActionButtons(spellID)
	if type(slots) ~= "table" then
		return nil
	end

	local firstSlot
	for _, value in ipairs(slots) do
		local slot = tonumber(value)
		if slot and slot > 0 and (not firstSlot or slot < firstSlot) then
			firstSlot = slot
		end
	end
	for key, value in pairs(slots) do
		local slot
		if type(value) == "number" then
			slot = value
		elseif value == true and type(key) == "number" then
			slot = key
		end
		if slot and slot > 0 and (not firstSlot or slot < firstSlot) then
			firstSlot = slot
		end
	end

	return firstSlot
end

local function GetActionSpellID(slot)
	local actionSlot = tonumber(slot)
	if not actionSlot or actionSlot <= 0 or not GetActionInfo then
		return nil
	end

	local actionType, id, subType = GetActionInfo(actionSlot)
	if actionType == "spell" then
		return NormalizeSpellID(id)
	end
	if actionType == "macro" and subType == "spell" then
		return NormalizeSpellID(id)
	end
	return nil
end

local function ResolvePlayerFacingSpellID(spellID)
	local candidates = BuildSpellCandidateList(spellID)
	for _, candidate in ipairs(candidates) do
		local slot = GetFirstActionSlotForSpell(candidate)
		if slot then
			local actionSpellID = GetActionSpellID(slot)
			if actionSpellID then
				return GetOverrideSpellID(actionSpellID)
			end
			return candidate
		end
	end

	for _, candidate in ipairs(candidates) do
		local info = C_Spell.GetSpellInfo(candidate)
		if info then
			return candidate
		end
	end

	return NormalizeSpellID(spellID)
end

local function AreSpellIntentsEquivalent(firstSpellID, secondSpellID)
	local firstResolved = NormalizeSpellID(firstSpellID)
	local secondResolved = NormalizeSpellID(secondSpellID)
	if not firstResolved or not secondResolved then
		return false
	end
	if firstResolved == secondResolved then
		return true
	end

	local candidates = {}
	for _, candidate in ipairs(BuildSpellCandidateList(firstResolved)) do
		candidates[candidate] = true
	end
	for _, candidate in ipairs(BuildSpellCandidateList(secondResolved)) do
		if candidates[candidate] then
			return true
		end
	end

	return false
end

local function GetPendingIntentPriority(source)
	if source == PENDING_SOURCE_ACTION then
		return 2
	end
	return 1
end

local function IsInstantSpell(spellID)
	local normalized = NormalizeSpellID(spellID)
	if not normalized then
		return false
	end
	local info = C_Spell.GetSpellInfo(normalized)
	return info and (info.castTime or 0) <= 0 or false
end

local function ToSafeNumber(value)
	if value == nil then
		return nil
	end
	local ok, stringValue = pcall(tostring, value)
	if not ok then
		return nil
	end
	return tonumber(stringValue)
end

local function IsCooldownActive(startTime, duration)
	startTime = ToSafeNumber(startTime)
	duration = ToSafeNumber(duration)
	return startTime and duration and startTime > 0 and duration > 0 and (startTime + duration) > GetTime() or false
end

local function IsSameCooldownWindow(firstStart, firstDuration, secondStart, secondDuration)
	if not (IsCooldownActive(firstStart, firstDuration) and IsCooldownActive(secondStart, secondDuration)) then
		return false
	end
	return math.abs(firstStart - secondStart) <= 0.05 and math.abs(firstDuration - secondDuration) <= 0.05
end

local function GetBlockedCooldownInfo(spellID, actionSlot)
	local normalized = NormalizeSpellID(spellID)
	if not normalized then
		return nil
	end

	local recentActionSlot = tonumber(actionSlot)
	if recentActionSlot and recentActionSlot > 0 and GetActionCharges then
		local currentCharges, maxCharges, cooldownStart, cooldownDuration = GetActionCharges(recentActionSlot)
		currentCharges = ToSafeNumber(currentCharges)
		maxCharges = ToSafeNumber(maxCharges)
		cooldownStart = ToSafeNumber(cooldownStart)
		cooldownDuration = ToSafeNumber(cooldownDuration)
		if maxCharges and maxCharges > 0 and currentCharges and currentCharges <= 0 and IsCooldownActive(cooldownStart, cooldownDuration) then
			return cooldownStart, cooldownDuration
		end
	end

	if recentActionSlot and recentActionSlot > 0 and GetActionCooldown then
		local startTime, duration, enabled = GetActionCooldown(recentActionSlot)
		startTime = ToSafeNumber(startTime)
		duration = ToSafeNumber(duration)
		enabled = ToSafeNumber(enabled)
		if enabled ~= 0 and IsCooldownActive(startTime, duration) then
			local gcdStart, gcdDuration = API.GetSpellCooldown(61304)
			if not IsSameCooldownWindow(startTime, duration, gcdStart, gcdDuration) then
				return startTime, duration
			end
		end
	end

	if C_Spell and C_Spell.GetSpellCharges then
		local chargeInfo = C_Spell.GetSpellCharges(normalized)
		local maxCharges = type(chargeInfo) == "table" and ToSafeNumber(chargeInfo.maxCharges) or nil
		local currentCharges = type(chargeInfo) == "table" and ToSafeNumber(chargeInfo.currentCharges) or nil
		local cooldownStart = type(chargeInfo) == "table" and ToSafeNumber(chargeInfo.cooldownStartTime) or nil
		local cooldownDuration = type(chargeInfo) == "table" and ToSafeNumber(chargeInfo.cooldownDuration) or nil
		if maxCharges and maxCharges > 0 then
			if currentCharges and currentCharges <= 0 and IsCooldownActive(cooldownStart, cooldownDuration) then
				return cooldownStart, cooldownDuration
			end
			return nil
		end
	end
end

local function ClearPendingInstantIntent()
	pendingInstantResolvedSpellID = nil
	pendingInstantAt = 0
	pendingInstantCastGUID = nil
	pendingInstantSource = nil
end

local function CancelRejectedAttemptFeedback()
	rejectedAttemptToken = rejectedAttemptToken + 1
end

local function RecordLastAttemptedSpell(spellID, actionSlot)
	local resolvedSpellID = ResolvePlayerFacingSpellID(spellID)
	if not resolvedSpellID then
		return
	end
	lastAttemptedSpellID = resolvedSpellID
	if actionSlot ~= nil then
		lastAttemptedActionSlot = tonumber(actionSlot)
	end
	lastAttemptedAt = GetTime()
end

local function GetFreshLastAttemptedSpellID()
	if lastAttemptedSpellID and lastAttemptedAt > 0 and (GetTime() - lastAttemptedAt) <= LAST_ATTEMPT_WINDOW then
		return lastAttemptedSpellID
	end
	return nil
end

local function HasRecentAttemptedSpell(spellID)
	if not (lastAttemptedSpellID and lastAttemptedAt > 0 and (GetTime() - lastAttemptedAt) <= ACTION_COOLDOWN_FEEDBACK_WINDOW) then
		return false
	end
	if spellID and not AreSpellIntentsEquivalent(lastAttemptedSpellID, spellID) then
		return false
	end
	return true
end

local function GetRecentAttemptedActionSlot(spellID)
	if not HasRecentAttemptedSpell(spellID) then
		return nil
	end
	local slot = tonumber(lastAttemptedActionSlot)
	if slot and slot > 0 then
		return slot
	end
	return nil
end

local function RecordLastSentSpell(spellID, castGUID)
	local resolvedSpellID = ResolvePlayerFacingSpellID(spellID)
	if not resolvedSpellID then
		return
	end
	lastSentSpellID = resolvedSpellID
	lastSentAt = GetTime()
	lastSentCastGUID = castGUID
end

local function GetFreshLastSentSpellID(castGUID)
	if not (lastSentSpellID and lastSentAt > 0 and (GetTime() - lastSentAt) <= LAST_SENT_WINDOW) then
		return nil
	end
	if castGUID and lastSentCastGUID and castGUID ~= lastSentCastGUID then
		return nil
	end
	return lastSentSpellID
end

local function HasFreshPendingInstantIntent()
	return pendingInstantResolvedSpellID and pendingInstantAt > 0 and (GetTime() - pendingInstantAt) <= INSTANT_PENDING_WINDOW
end

local function ShowCastFrame(opts)
	if not castFrame then
		return
	end
	AnchorFrame:Show("cast")
	if Transition and Transition.ShowFrame then
		Transition:ShowFrame(castFrame, opts)
	else
		castFrame:Show()
	end
end

local function HideCastFrame(onComplete)
	if not castFrame then
		AnchorFrame:Hide("cast")
		if onComplete then
			onComplete()
		end
		return
	end

	local function Finish()
		AnchorFrame:Hide("cast")
		if onComplete then
			onComplete()
		end
	end

	if Transition and Transition.HideFrame then
		Transition:HideFrame(castFrame, { onComplete = Finish })
	else
		castFrame:Hide()
		Finish()
	end
end

local function ClearCastShellVisuals()
	if castDonut then
		castDonut:Hide()
		castDonut:SetOverlayShown(false)
		castDonut:SetOverlayAlpha(0)
		castDonut:SetAngle(0)
	end
	if latencyDonut then
		latencyDonut:Hide()
	end
	if castFrame and castFrame.frameTexture then
		castFrame.frameTexture:Hide()
	end
	if castFrame and castFrame.sparkTexture then
		castFrame.sparkTexture:Hide()
	end
	if castFrame and castFrame.spellText then
		castFrame.spellText:Hide()
	end
	if castFrame and castFrame.iconFrame then
		if castFrame.iconFrame.errorIcon then
			castFrame.iconFrame.errorIcon:Hide()
		end
		castFrame.iconFrame:Hide()
		if castFrame.iconFrame.cooldown then
			castFrame.iconFrame.cooldown:Hide()
		end
	end
	for i = 1, NUM_SLOTS do
		if slots[i] then
			slots[i].widget:Hide()
		end
	end
end

local function IsAnyClickFeedbackActive()
	if not GetDBBool("cast_clickFeedbackEnabled") then
		return false
	end
	local leftActive = GetDBBool("cast_clickFeedbackLeft") and clickFeedbackLeftDown
	local rightActive = GetDBBool("cast_clickFeedbackRight") and clickFeedbackRightDown
	return leftActive or rightActive
end

--------------------------------------------------------------------------------
-- Event Frame
--------------------------------------------------------------------------------
local EL = CreateFrame("Frame")
local actionIntentHookInstalled = false

--------------------------------------------------------------------------------
-- Cast Module Object
--------------------------------------------------------------------------------
Cast = {}
addon.Modules.CastObj = Cast

function Cast:GetFrame()
	return castFrame
end

local function ApplySpellIconMask()
	if not castFrame or not castFrame.iconFrame then
		return false
	end
	return IconMask:ApplyToIconFrame(castFrame.iconFrame, SPELL_ICON_MASK_BASE_EXPAND)
end

local function LayoutSpellIconErrorOverlay()
	if not castFrame or not castFrame.iconFrame or not castFrame.iconFrame.icon or not castFrame.iconFrame.errorIcon then
		return
	end

	IconMask:LayoutToIcon(castFrame.iconFrame.errorIcon, castFrame.iconFrame.icon, SPELL_ICON_MASK_BASE_EXPAND)
end

local function LayoutSpellIconCooldown()
	if not castFrame or not castFrame.iconFrame or not castFrame.iconFrame.icon or not castFrame.iconFrame.cooldown then
		return
	end

	IconMask:LayoutToIcon(castFrame.iconFrame.cooldown, castFrame.iconFrame.icon, SPELL_ICON_MASK_BASE_EXPAND)
end

local function GetSpellIconSwipeColor(mode)
	local colorKey = "spellicon_castProgressSwipeColor"
	if mode == "cooldownBlocked" then
		colorKey = "spellicon_cooldownBlockedSwipeColor"
	end

	local color = GetDBValue(colorKey)
	if type(color) ~= "table" then
		return 1, 1, 1, 1
	end

	if mode == "cooldownBlocked" and GetDBBool("spellicon_cooldownBlockedUseClassColor") then
		local r, g, b = API.GetPlayerClassColor()
		return r or 1, g or 1, b or 1, color.a or 1
	end

	return color.r or 1, color.g or 1, color.b or 1, color.a or 1
end

local function ActivateAfterInstantCastVisibility(duration)
	if not Visibility or not Visibility.ActivateAfterInstantCastWindow then
		return
	end

	if Visibility:ActivateAfterInstantCastWindow(duration) then
		CallbackRegistry:Trigger("VisibilityContextChanged", "SPELL_ICON_FEEDBACK_AFTER_INSTANT_CAST")
	end
end

function Cast:SetSpellIconEnabled(enabled)
	spellIconEnabled = enabled == true
	if castFrame and castFrame.iconFrame then
		if spellIconEnabled and (isCasting or instantIconActive) and IsCastVisibilityAllowed() and castFrame:IsShown() then
			castFrame.iconFrame:Show()
		else
			castFrame.iconFrame:Hide()
		end
	end
end

function Cast:ApplyPendingVisuals()
	if not pendingVisuals then
		return
	end

	if GetDBBool("cast_spellTextEnabled") and castFrame.spellText then
		castFrame.spellText:SetText(currentSpellName)
		castFrame.spellText:Show()
	elseif castFrame.spellText then
		castFrame.spellText:Hide()
	end

	self:UpdateSpellIcon()
	pendingVisuals = false
end

function Cast:ApplyIconOptions()
	if not castFrame or not castFrame.iconFrame then
		return
	end

	local size = GetDBValue("spellicon_size")
	local offsetX = GetDBValue("spellicon_offsetX")
	local offsetY = GetDBValue("spellicon_offsetY")
	local showCooldown = GetDBBool("spellicon_castProgressSwipe")

	castFrame.iconFrame:SetSize(size, size)
	castFrame.iconFrame:ClearAllPoints()
	castFrame.iconFrame:SetPoint("CENTER", castFrame, "CENTER", offsetX, offsetY)

	castFrame.iconFrame.icon:SetSize(size, size)

	if showCooldown then
		if not castFrame.iconFrame.cooldown then
			castFrame.iconFrame.cooldown = CreateFrame("Cooldown", nil, castFrame.iconFrame, "CooldownFrameTemplate")
			castFrame.iconFrame.cooldown:SetDrawEdge(false)
			castFrame.iconFrame.cooldown:SetHideCountdownNumbers(true)
			pcall(castFrame.iconFrame.cooldown.SetSwipeTexture, castFrame.iconFrame.cooldown, SPELL_ICON_COOLDOWN_SWIPE_PATH)
		end
		LayoutSpellIconCooldown()
		if castFrame.iconFrame.cooldown.SetSwipeColor then
			local swipeR, swipeG, swipeB, swipeA = GetSpellIconSwipeColor("cast")
			castFrame.iconFrame.cooldown:SetSwipeColor(swipeR, swipeG, swipeB, swipeA)
		end
		castFrame.iconFrame.cooldown:Show()
	elseif castFrame.iconFrame.cooldown then
		castFrame.iconFrame.cooldown:Hide()
	end

	castFrame.iconMaskReady = ApplySpellIconMask()
	LayoutSpellIconCooldown()
	LayoutSpellIconErrorOverlay()
	self:UpdateIconCooldown()
end

function Cast:UpdateSpellIcon()
	if not castFrame or not castFrame.iconFrame then
		return
	end
	if castFrame.iconFrame.errorIcon then
		castFrame.iconFrame.errorIcon:Hide()
	end
	if not spellIconEnabled and addon.GetDBBool("moduleEnabled_SpellIcon") then
		spellIconEnabled = true
	end
	if not spellIconEnabled then
		castFrame.iconFrame:Hide()
		return
	end
	if not IsInstantIconVisibilityAllowed() or not castFrame:IsShown() then
		castFrame.iconFrame:Hide()
		return
	end
	if not isCasting and not instantIconActive then
		castFrame.iconFrame:Hide()
		return
	end
	if not currentSpellTexture and currentSpellID then
		local info = C_Spell.GetSpellInfo(currentSpellID)
		currentSpellTexture = info and info.iconID or currentSpellTexture
	end
	if not currentSpellTexture then
		castFrame.iconFrame:Hide()
		return
	end
	if not castFrame.iconMaskReady then
		castFrame.iconMaskReady = ApplySpellIconMask()
		if not castFrame.iconMaskReady then
			castFrame.iconFrame:Hide()
			return
		end
	end
	local texture = currentSpellTexture
	if type(texture) ~= "number" and type(texture) ~= "string" then
		texture = 134400 -- Interface\\Icons\\INV_Misc_QuestionMark
	end
	castFrame.iconFrame.icon:SetTexture(texture)
	castFrame.iconFrame.icon:Show()
	if instantIconMode == "failed" and castFrame.iconFrame.errorIcon then
		castFrame.iconFrame.errorIcon:Show()
	end
	castFrame.iconFrame:Show()
	self:UpdateIconCooldown()
end

ClearInstantIcon = function(reason)
	instantIconActive = false
	instantIconConfirmed = false
	instantIconMode = "instant"
	instantIconCooldownStart = 0
	instantIconCooldownDuration = 0
	instantIconExpiry = 0
	if instantIconForcedShell then
		instantIconForcedShell = false
		Cast:UpdateShellVisibility()
	elseif not isCasting then
		Cast:UpdateSpellIcon()
	end
end

local function ShowSpellIconFeedback(spellID, opts)
	opts = opts or {}
	local resolvedSpellID = ResolvePlayerFacingSpellID(spellID)
	if not resolvedSpellID then
		return
	end

	local info = C_Spell.GetSpellInfo(resolvedSpellID)
	if not info then
		return
	end
	if opts.requireInstant and (info.castTime or 0) > 0 then
		return
	end

	-- Only optimistic instant previews should be blocked by an existing confirmed icon.
	if instantIconConfirmed and not opts.isConfirmed and (opts.mode or "instant") == "instant" then
		return
	end

	currentSpellID = resolvedSpellID
	currentSpellName = info.name or currentSpellName
	currentSpellTexture = info.iconID or currentSpellTexture
	instantIconActive = true
	instantIconMode = opts.mode or "instant"
	instantIconCooldownStart = tonumber(opts.cooldownStart) or 0
	instantIconCooldownDuration = tonumber(opts.cooldownDuration) or 0
	if opts.isConfirmed then
		instantIconConfirmed = true
	else
		instantIconConfirmed = false
	end

	-- Instant casts have no cast bar start event, so the cast shell parent may still be hidden.
	-- Temporarily show it so the child icon frame can render, then restore via UpdateShellVisibility().
	if castFrame and (not castFrame:IsShown()) and IsInstantIconVisibilityAllowed() then
		instantIconForcedShell = true
		ShowCastFrame()
	end

	Cast:UpdateSpellIcon()

	local duration = tonumber(opts.duration) or 0
	if duration <= 0 then
		local _, gcdDuration = API.GetSpellCooldown(61304)
		duration = tonumber(gcdDuration) or 0
		if duration <= 0 or duration > 2 then
			if Visibility and Visibility.GetAfterInstantCastRemaining then
				duration = Visibility:GetAfterInstantCastRemaining()
			end
		end
		if duration <= 0 and Visibility and Visibility.GetInstantCastFallbackDuration then
			duration = Visibility:GetInstantCastFallbackDuration()
		end
		if duration <= 0 then
			duration = 1.0
		end
	end
	-- Expiry is checked each frame in OnUpdate; no timer closure needed.
	instantIconExpiry = GetTime() + duration
end

local function ShowInstantSpellIcon(spellID, isConfirmed)
	ShowSpellIconFeedback(spellID, {
		requireInstant = true,
		isConfirmed = isConfirmed,
		mode = "instant",
	})
end

local function ShowFailedAttemptIcon(spellID)
	if GetFailedAttemptFeedbackStyle() ~= "ERROR_ICON" then
		return
	end
	ActivateAfterInstantCastVisibility(FAILED_ATTEMPT_FEEDBACK_DURATION)
	ShowSpellIconFeedback(spellID, {
		requireInstant = false,
		isConfirmed = false,
		mode = "failed",
		duration = FAILED_ATTEMPT_FEEDBACK_DURATION,
	})
end

ShowCooldownBlockedIcon = function(spellID, cooldownStart, cooldownDuration)
	if not ShouldShowCooldownBlockedFeedback() then
		return
	end

	local remaining = math.max(0, (tonumber(cooldownStart) or 0) + (tonumber(cooldownDuration) or 0) - GetTime())
	if remaining <= 0 then
		return
	end

	ActivateAfterInstantCastVisibility(remaining)
	ShowSpellIconFeedback(spellID, {
		requireInstant = false,
		isConfirmed = false,
		mode = "cooldownBlocked",
		duration = remaining,
		cooldownStart = cooldownStart,
		cooldownDuration = cooldownDuration,
	})
end

local function RecordPendingInstantIntent(spellID, source, castGUID)
	if not spellIconEnabled then
		return
	end

	local resolvedSpellID = ResolvePlayerFacingSpellID(spellID)
	if not resolvedSpellID then
		return
	end

	if not IsInstantSpell(resolvedSpellID) then
		return
	end

	source = source or PENDING_SOURCE_SENT

	if HasFreshPendingInstantIntent() then
		local sameIntent = AreSpellIntentsEquivalent(pendingInstantResolvedSpellID, resolvedSpellID)
		local pendingPriority = GetPendingIntentPriority(pendingInstantSource)
		local newPriority = GetPendingIntentPriority(source)

		if sameIntent then
			pendingInstantResolvedSpellID = resolvedSpellID
			pendingInstantAt = GetTime()
			if newPriority > pendingPriority then
				pendingInstantSource = source
			end
			if castGUID then
				pendingInstantCastGUID = castGUID
			end
			return
		end

		if pendingPriority > newPriority then
			return
		end
	end

	ClearPendingInstantIntent()
	pendingInstantResolvedSpellID = resolvedSpellID
	pendingInstantAt = GetTime()
	pendingInstantCastGUID = castGUID
	pendingInstantSource = source
end

local function InstallActionIntentHook()
	if actionIntentHookInstalled or not hooksecurefunc or not UseAction then
		return
	end

	hooksecurefunc("UseAction", function(slot, checkCursor, onSelf)
		if not moduleEnabled then
			return
		end
		if isCasting or interruptFlashActive then
			return
		end
		if UnitCastingInfo("player") or UnitChannelInfo("player") then
			return
		end

		local actionSpellID = GetActionSpellID(slot)
		if actionSpellID then
			RecordLastAttemptedSpell(actionSpellID, slot)
			RecordPendingInstantIntent(actionSpellID, PENDING_SOURCE_ACTION)
		end
	end)

	actionIntentHookInstalled = true
end

local function GetConfirmedPlayerInstantSpellID(castGUID, spellID)
	if not HasFreshPendingInstantIntent() then
		return nil
	end

	local resolvedSpellID = ResolvePlayerFacingSpellID(spellID)
	local matchesPlayerIntent = (pendingInstantCastGUID and pendingInstantCastGUID == castGUID) or AreSpellIntentsEquivalent(pendingInstantResolvedSpellID, resolvedSpellID)

	if not matchesPlayerIntent then
		return nil
	end

	return pendingInstantResolvedSpellID or resolvedSpellID
end

local function GetAttemptFeedbackSpellID(spellID, castGUID)
	local freshAttempt = GetFreshLastAttemptedSpellID()
	local normalizedFailedSpellID = ResolvePlayerFacingSpellID(spellID)
	if freshAttempt and (not normalizedFailedSpellID or AreSpellIntentsEquivalent(freshAttempt, normalizedFailedSpellID)) then
		return freshAttempt
	end
	local freshSentSpellID = GetFreshLastSentSpellID(castGUID)
	if freshSentSpellID and (not normalizedFailedSpellID or AreSpellIntentsEquivalent(freshSentSpellID, normalizedFailedSpellID)) then
		return freshSentSpellID
	end
	if
		pendingInstantResolvedSpellID
		and HasFreshPendingInstantIntent()
		and (not normalizedFailedSpellID or AreSpellIntentsEquivalent(pendingInstantResolvedSpellID, normalizedFailedSpellID))
	then
		return pendingInstantResolvedSpellID
	end
	return nil
end

IsConfirmedInstantIconActiveForSpell = function(spellID)
	if not (instantIconActive and instantIconConfirmed and instantIconExpiry > GetTime()) then
		return false
	end
	if not (spellID and currentSpellID) then
		return false
	end
	return AreSpellIntentsEquivalent(spellID, currentSpellID)
end

ShouldPreserveConfirmedInstantIcon = function(spellID, castGUID)
	if IsConfirmedInstantIconActiveForSpell(spellID) then
		return true
	end

	local feedbackSpellID = GetAttemptFeedbackSpellID(spellID, castGUID)
	if not feedbackSpellID or not currentSpellID then
		return false
	end

	return IsConfirmedInstantIconActiveForSpell(feedbackSpellID)
end

TryShowActionCooldownBlocked = function(spellID)
	if not ShouldShowCooldownBlockedFeedback() then
		return false
	end

	local resolvedSpellID = ResolvePlayerFacingSpellID(spellID)
	if not resolvedSpellID or not HasRecentAttemptedSpell(resolvedSpellID) then
		return false
	end
	if isCasting or interruptFlashActive then
		return false
	end
	if UnitCastingInfo("player") or UnitChannelInfo("player") then
		return false
	end
	if ShouldPreserveConfirmedInstantIcon(resolvedSpellID) then
		return false
	end

	local actionSlot = GetRecentAttemptedActionSlot(resolvedSpellID)
	local cooldownStart, cooldownDuration = GetBlockedCooldownInfo(resolvedSpellID, actionSlot)
	if not (cooldownStart and cooldownDuration) then
		return false
	end

	ClearPendingInstantIntent()
	ClearInstantIcon("actionCooldownBlocked")
	ShowCooldownBlockedIcon(resolvedSpellID, cooldownStart, cooldownDuration)
	return true
end

local function ShowRejectedAttemptFeedback(spellID, castGUID)
	if ShouldPreserveConfirmedInstantIcon(spellID, castGUID) then
		return
	end

	CancelRejectedAttemptFeedback()
	ClearPendingInstantIntent()

	if not ShouldShowFailedAttempts() and not ShouldShowCooldownBlockedFeedback() then
		ClearInstantIcon("rejectedAttempt")
		return
	end

	local feedbackSpellID = GetAttemptFeedbackSpellID(spellID, castGUID)
	if not feedbackSpellID then
		local token = rejectedAttemptToken
		C_Timer.After(0, function()
			if token ~= rejectedAttemptToken then
				return
			end
			ShowRejectedAttemptFeedback(spellID, castGUID)
		end)
		return
	end

	if TryShowActionCooldownBlocked(feedbackSpellID) then
		return
	end

	if ShouldShowFailedAttempts() then
		ClearInstantIcon("rejectedAttempt")
		ShowFailedAttemptIcon(feedbackSpellID)
	else
		ClearInstantIcon("rejectedAttempt")
	end
end

function Cast:ACTIONBAR_UPDATE_COOLDOWN()
	local attemptedSpellID = GetFreshLastAttemptedSpellID()
	if attemptedSpellID then
		TryShowActionCooldownBlocked(attemptedSpellID)
	end
end

Cast.SPELL_UPDATE_COOLDOWN = Cast.ACTIONBAR_UPDATE_COOLDOWN

function Cast:UpdateIconCooldown()
	if not castFrame or not castFrame.iconFrame or not castFrame.iconFrame.cooldown then
		return
	end
	if isCasting and castStartTime and castDuration ~= 0 then
		if not GetDBBool("spellicon_castProgressSwipe") then
			castFrame.iconFrame.cooldown:Hide()
			return
		end
		if castFrame.iconFrame.cooldown.SetSwipeColor then
			local swipeR, swipeG, swipeB, swipeA = GetSpellIconSwipeColor("cast")
			castFrame.iconFrame.cooldown:SetSwipeColor(swipeR, swipeG, swipeB, swipeA)
		end
		castFrame.iconFrame.cooldown:SetCooldown(castStartTime / 1000, castDuration / 1000)
	elseif instantIconActive and instantIconMode == "cooldownBlocked" and instantIconCooldownStart > 0 and instantIconCooldownDuration > 0 then
		if castFrame.iconFrame.cooldown.SetSwipeColor then
			local swipeR, swipeG, swipeB, swipeA = GetSpellIconSwipeColor("cooldownBlocked")
			castFrame.iconFrame.cooldown:SetSwipeColor(swipeR, swipeG, swipeB, swipeA)
		end
		castFrame.iconFrame.cooldown:SetCooldown(instantIconCooldownStart, instantIconCooldownDuration)
	else
		castFrame.iconFrame.cooldown:Hide()
		return
	end

	if castFrame.iconMaskReady and not castFrame.iconFrame.cooldownMaskAttached then
		ApplySpellIconMask()
	end
	castFrame.iconFrame.cooldown:Show()
end

function Cast:UpdateClickFeedbackVisual()
	if not castFrame or not castFrame.feedbackTexture then
		return
	end

	if not moduleEnabled or not castFrame:IsShown() or not IsCastVisibilityAllowed() or not IsAnyClickFeedbackActive() then
		castFrame.feedbackTexture:Hide()
		return
	end

	local r, g, b, a
	if GetDBBool("cast_clickFeedbackUseClassColor") then
		r, g, b, a = API.GetPlayerClassColor()
		a = GetDBValue("cast_clickFeedbackOpacity") or a or 1
	else
		local useRight = clickFeedbackRightDown and GetDBBool("cast_clickFeedbackRight")
		local useLeft = clickFeedbackLeftDown and GetDBBool("cast_clickFeedbackLeft")
		if useRight then
			r, g, b, a = GetDBColor("cast_clickFeedbackRightColor")
		elseif useLeft then
			r, g, b, a = GetDBColor("cast_clickFeedbackLeftColor")
		else
			r, g, b, a = 1, 1, 1, 1
		end
	end
	a = a or 1

	castFrame.feedbackTexture:SetVertexColor(r or 1, g or 1, b or 1, a)
	castFrame.feedbackTexture:Show()
end

--------------------------------------------------------------------------------
-- OnUpdate Handler
--------------------------------------------------------------------------------
local function UpdateSlotProviderVisuals()
	for i = 1, NUM_SLOTS do
		local slot = slots[i]
		if slot and slot.provider then
			local result = slot.provider:GetProgress()
			slot.widget:SetBarColor(GetSlotBarColor(i, result))

			-- Keep assigned slot backgrounds visible while cast module is active.
			-- Provider activity controls the progress/spark only.
			slot.widget:Show()

			if result and result.active then
				if result.current ~= nil and result.max ~= nil then
					slot.widget:SetValueRange(result.current, result.max, result.progress)
				else
					slot.widget:SetProgress(result.progress or 0)
				end
			else
				slot.widget:SetProgress(0)
			end
		elseif slot then
			slot.widget:Hide()
		end
	end
end

local function OnUpdate(self, elapsed)
	-- Instant icon expiry: checked every frame to avoid timer closure races.
	if instantIconActive and instantIconExpiry > 0 and GetTime() >= instantIconExpiry then
		ClearInstantIcon("expiry")
	end

	local leftDown = IsMouseButtonDown and IsMouseButtonDown("LeftButton") and true or false
	local rightDown = IsMouseButtonDown and IsMouseButtonDown("RightButton") and true or false
	if leftDown ~= clickFeedbackLeftDown or rightDown ~= clickFeedbackRightDown then
		clickFeedbackLeftDown = leftDown
		clickFeedbackRightDown = rightDown
		Cast:UpdateClickFeedbackVisual()
	elseif castFrame and castFrame.feedbackTexture and castFrame.feedbackTexture:IsShown() then
		-- Keep feedback synced with visibility/module state while button is held.
		Cast:UpdateClickFeedbackVisual()
	end

	if castFrame and castFrame:IsShown() then
		UpdateSlotProviderVisuals()
	end

	if interruptFlashActive then
		return
	end

	if not isCasting or castDuration == 0 then
		return
	end

	local now = GetTime() * 1000
	local castPerc = (now - castStartTime) / castDuration

	if not ShouldShowCurrentCastProgress() then
		if castDonut then
			castDonut:SetAngle(0)
			castDonut:SetOverlayAlpha(0)
			castDonut:SetOverlayShown(false)
		end
		if latencyDonut then
			latencyDonut:Hide()
		end
		if castFrame.sparkTexture then
			castFrame.sparkTexture:Hide()
		end
		if castPerc >= 1 then
			Cast:Hide()
		end
		return
	end

	if castPerc < 1 then
		local angle = castPerc * 360
		local clampedPerc = math.max(0, math.min(1, castPerc))

		-- Reverse for channeled spells if enabled
		if GetDBBool("cast_reverseChanneling") and isChanneling then
			angle = (1 - castPerc) * 360
		end

		if castDonut then
			castDonut:SetAngle(angle)
			castDonut:SetOverlayAlpha(castGlowMaxOpacity * clampedPerc)
		end
		-- Keep latency arc static (Cooldown swipe animates otherwise)
		if latencyDonut then
			local latencyAngle = math.max(0.1, castLatency * 360)
			latencyDonut:SetAngle(latencyAngle)
		end

		-- Update spark position (rotates around ring)
		local sparkAngle = 360 - (-90 + angle)
		local radius = GetDBValue("cast_radius")
		-- Align spark to the centerline of the 20px ring texture (texture radius = 128px)
		local texThickness = 20
		local texRadius = 38
		local ringHalf = radius * (texThickness / texRadius) * 0.5
		local sparkRadius = math.max(0, radius - ringHalf)
		local x = cos(rad(sparkAngle)) * sparkRadius
		local y = sin(rad(sparkAngle)) * sparkRadius

		local spark = castFrame.sparkTexture
		spark:SetRotation(rad(sparkAngle + 90))
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", castFrame, "CENTER", x, y)

		local r, g, b, a
		if GetDBBool("cast_sparkUseClassColor") then
			r, g, b, a = API.GetPlayerClassColor()
		else
			r, g, b, a = GetDBColor("cast_sparkColor")
		end
		spark:SetVertexColor(r, g, b, a)
	else
		Cast:Hide()
	end
end

--------------------------------------------------------------------------------
-- Show/Hide
--------------------------------------------------------------------------------
function Cast:Show()
	if not castFrame then
		return
	end

	isCasting = true
	if not IsCastVisibilityAllowed() then
		if castFrame then
			HideCastFrame(ClearCastShellVisuals)
		end
		return
	end
	ShowCastFrame()

	if castDonut then
		castDonut:SetBarColor(GetActiveCastBarColor())
	end

	if castDonut and not ShouldShowCurrentCastProgress() then
		castDonut:SetOverlayTextureBase(CAST_OVERLAY_DEFAULT)
		castDonut:Show()
		castDonut:SetAngle(0)
		castDonut:SetOverlayShown(false)
		castDonut:SetOverlayAlpha(0)
	end

	-- Show latency indicator
	if latencyDonut and ShouldShowCurrentCastProgress() then
		local latencyAngle = math.max(0.1, castLatency * 360)
		latencyDonut:SetAngle(latencyAngle)
		if castDonut then
			castDonut:SetAngle(0)
		end
		latencyDonut:Show()
		if castDonut then
			castDonut:SetOverlayTextureBase(CAST_OVERLAY_DEFAULT)
			castDonut:Show()
			castDonut:SetOverlayShown(true)
			castDonut:SetOverlayAlpha(0)
		end
	end
	if castFrame.frameTexture then
		castFrame.frameTexture:Show()
	end
	if castFrame.sparkTexture and ShouldShowCurrentCastProgress() then
		castFrame.sparkTexture:Show()
	elseif castFrame.sparkTexture then
		castFrame.sparkTexture:Hide()
	end

	pendingVisuals = true
	self:ApplyPendingVisuals()
	self:UpdateIconCooldown()

	-- Show assigned slot widgets (background/frame visible even when provider idle).
	for i = 1, NUM_SLOTS do
		local slot = slots[i]
		if slot and slot.provider then
			slot.widget:Show()
		end
	end

	ShowCastFrame()
end

function Cast:UpdateShellVisibility()
	if not castFrame then
		return
	end

	local allowed = moduleEnabled and (IsCastVisibilityAllowed() or ShouldBypassHoverHideForInstantIcon())
	if not allowed then
		HideCastFrame(ClearCastShellVisuals)
		return
	end

	ShowCastFrame()

	if isCasting and not interruptFlashActive then
		self:Show()
		return
	end

	if castDonut then
		castDonut:Show()
		if not isCasting and not interruptFlashActive then
			castDonut:SetOverlayTextureBase(CAST_OVERLAY_DEFAULT)
			castDonut:SetOverlayShown(false)
			castDonut:SetOverlayAlpha(0)
			castDonut:SetAngle(0)
		end
	end
	if castFrame.frameTexture then
		castFrame.frameTexture:Show()
	end

	if not isCasting and not interruptFlashActive then
		if latencyDonut then
			latencyDonut:Hide()
		end
		if castFrame.sparkTexture then
			castFrame.sparkTexture:Hide()
		end
		if castFrame.spellText then
			castFrame.spellText:Hide()
		end
		if castFrame.iconFrame and not instantIconActive then
			if castFrame.iconFrame.errorIcon then
				castFrame.iconFrame.errorIcon:Hide()
			end
			castFrame.iconFrame:Hide()
			if castFrame.iconFrame.cooldown then
				castFrame.iconFrame.cooldown:Hide()
			end
		end
	end

	-- Keep instant icon visible through shell visibility refreshes.
	if instantIconActive and not isCasting and not interruptFlashActive then
		self:UpdateSpellIcon()
	end

	for i = 1, NUM_SLOTS do
		local slot = slots[i]
		if slot and slot.provider then
			slot.widget:Show()
		elseif slot then
			slot.widget:Hide()
		end
	end
end

function Cast:Hide()
	if not castFrame then
		return
	end

	CancelRejectedAttemptFeedback()
	ClearPendingInstantIntent()
	interruptFlashToken = interruptFlashToken + 1
	interruptFlashActive = false
	isCasting = false
	isChanneling = false
	currentCastGUID = nil
	pendingVisuals = false
	if castDonut then
		castDonut:SetOverlayTextureBase(CAST_OVERLAY_DEFAULT)
		castDonut:SetAngle(0)
		castDonut:SetOverlayShown(false)
		castDonut:SetOverlayAlpha(0)
	end
	if latencyDonut then
		latencyDonut:Hide()
	end
	if castFrame.sparkTexture then
		castFrame.sparkTexture:Hide()
	end
	if castFrame.feedbackTexture then
		castFrame.feedbackTexture:Hide()
	end
	castDuration = 0
	castStartTime = 0
	castEndTime = 0

	if castFrame.iconFrame then
		if castFrame.iconFrame.errorIcon then
			castFrame.iconFrame.errorIcon:Hide()
		end
		castFrame.iconFrame:Hide()
		if castFrame.iconFrame.cooldown then
			castFrame.iconFrame.cooldown:Hide()
		end
	end

	self:UpdateShellVisibility()
end

function Cast:ShowInterruptFlash(castGUID)
	if castGUID and castGUID ~= currentCastGUID then
		return
	end
	if not castDonut or not castFrame or not isCasting then
		self:Hide()
		return
	end
	if not IsCastVisibilityAllowed() then
		self:Hide()
		return
	end

	interruptFlashToken = interruptFlashToken + 1
	interruptFlashActive = true
	local flashToken = interruptFlashToken

	-- Stop cast progress lifecycle from racing this brief flash.
	isCasting = false
	isChanneling = false
	castDuration = 0
	castStartTime = 0
	castEndTime = 0
	currentCastGUID = nil

	castDonut:SetOverlayTextureBase(CAST_OVERLAY_INTERRUPT)
	-- Cooldown swipe textures continue animating after SetCooldown; zero fill now.
	castDonut:SetAngle(0)
	castDonut:SetOverlayColor({ r = 1, g = 1, b = 1, a = 1 })
	castDonut:SetOverlayShown(true)
	castDonut:SetOverlayAlpha(1)
	if latencyDonut then
		latencyDonut:SetAngle(0)
		latencyDonut:Hide()
	end
	if castFrame.sparkTexture then
		castFrame.sparkTexture:Hide()
	end
	-- Stop inner slot progress/sparks immediately
	for i = 1, NUM_SLOTS do
		local slot = slots[i]
		if slot and slot.widget then
			slot.widget:SetProgress(0)
		end
	end
	if spellIconEnabled and castFrame.iconFrame and castFrame.iconFrame.errorIcon then
		if GetFailedAttemptFeedbackStyle() == "ERROR_ICON" then
			SetTextureSmooth(castFrame.iconFrame.errorIcon, SPELL_ICON_ERROR_PATH)
			LayoutSpellIconErrorOverlay()
			castFrame.iconFrame.errorIcon:Show()
			castFrame.iconFrame:Show()
		else
			castFrame.iconFrame.errorIcon:Hide()
			castFrame.iconFrame:Hide()
		end
		if castFrame.iconFrame.cooldown then
			-- Cooldown swipes keep animating after SetCooldown until explicitly reset.
			castFrame.iconFrame.cooldown:SetCooldown(0, 0)
			castFrame.iconFrame.cooldown:Hide()
		end
	end
	castDonut:Show()
	ShowCastFrame({ duration = 0 })

	C_Timer.After(INTERRUPT_FLASH_DURATION, function()
		if flashToken ~= interruptFlashToken then
			return
		end
		if castDonut then
			castDonut:SetOverlayTextureBase(CAST_OVERLAY_DEFAULT)
		end
		Cast:Hide()
	end)
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------
function Cast:UNIT_SPELLCAST_SENT(event, unit, target, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	castSent = GetTime() * 1000
	RecordLastAttemptedSpell(spellID)
	RecordLastSentSpell(spellID, castGUID)

	if not isCasting and not interruptFlashActive and not UnitCastingInfo("player") and not UnitChannelInfo("player") then
		RecordPendingInstantIntent(spellID, PENDING_SOURCE_SENT, castGUID)
	end
end

function Cast:UNIT_SPELLCAST_START(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	instantIconActive = false
	instantIconExpiry = 0
	instantIconForcedShell = false
	instantIconConfirmed = false
	instantIconMode = "instant"
	instantIconCooldownStart = 0
	instantIconCooldownDuration = 0
	CancelRejectedAttemptFeedback()
	ClearPendingInstantIntent()
	interruptFlashToken = interruptFlashToken + 1
	interruptFlashActive = false

	local name, text, texture, startTimeMS, endTimeMS = UnitCastingInfo("player")
	if not name then
		return
	end

	isChanneling = false
	currentCastGUID = castGUID
	castStartTime = startTimeMS
	castEndTime = endTimeMS
	castDuration = castEndTime - castStartTime
	currentSpellID = spellID
	currentSpellTexture = texture
	if spellID then
		local info = C_Spell.GetSpellInfo(spellID)
		currentSpellName = (info and info.name) or text or name
		currentSpellTexture = (info and info.iconID) or currentSpellTexture
	else
		currentSpellName = text or name
	end

	-- Calculate latency
	local sendLag = (castSent > 0) and (GetTime() * 1000 - castSent) or 0
	if sendLag <= 0 then
		local _, _, home, world = GetNetStats()
		sendLag = math.max(home or 0, world or 0)
	end
	sendLag = math.min(sendLag, castDuration)
	castLatency = (castDuration > 0) and (sendLag / castDuration) or 0

	self:Show()
end

function Cast:UNIT_SPELLCAST_STOP(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	CancelRejectedAttemptFeedback()
	ClearPendingInstantIntent()
	if not isCasting then
		return
	end
	if interruptFlashActive then
		return
	end
	if castGUID == currentCastGUID then
		self:Hide()
	end
end

function Cast:UNIT_SPELLCAST_INTERRUPTED(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	CancelRejectedAttemptFeedback()
	ClearPendingInstantIntent()
	if not isCasting then
		return
	end
	if castGUID == currentCastGUID then
		self:ShowInterruptFlash(castGUID)
	end
end

function Cast:UNIT_SPELLCAST_FAILED(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	if not isCasting then
		ShowRejectedAttemptFeedback(spellID, castGUID)
		return
	end
	CancelRejectedAttemptFeedback()
	ClearPendingInstantIntent()
	if castGUID == currentCastGUID then
		self:ShowInterruptFlash(castGUID)
	end
end

function Cast:UNIT_SPELLCAST_FAILED_QUIET(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	if not isCasting then
		ShowRejectedAttemptFeedback(spellID, castGUID)
		return
	end
	CancelRejectedAttemptFeedback()
	ClearPendingInstantIntent()
	if castGUID == currentCastGUID then
		self:ShowInterruptFlash(castGUID)
	end
end

function Cast:UNIT_SPELLCAST_DELAYED(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end

	local name, text, texture, startTimeMS, endTimeMS = UnitCastingInfo("player")
	if name then
		castStartTime = startTimeMS
		castEndTime = endTimeMS
		castDuration = castEndTime - castStartTime
		self:UpdateIconCooldown()
	end
end

function Cast:UNIT_SPELLCAST_CHANNEL_START(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	instantIconActive = false
	instantIconExpiry = 0
	instantIconForcedShell = false
	instantIconConfirmed = false
	instantIconMode = "instant"
	instantIconCooldownStart = 0
	instantIconCooldownDuration = 0
	CancelRejectedAttemptFeedback()
	ClearPendingInstantIntent()
	interruptFlashToken = interruptFlashToken + 1
	interruptFlashActive = false

	local name, text, texture, startTimeMS, endTimeMS = UnitChannelInfo("player")
	if not name then
		return
	end

	isChanneling = true
	currentCastGUID = castGUID
	castStartTime = startTimeMS
	castEndTime = endTimeMS
	castDuration = castEndTime - castStartTime
	currentSpellID = spellID
	currentSpellTexture = texture
	if spellID then
		local info = C_Spell.GetSpellInfo(spellID)
		currentSpellName = (info and info.name) or text or name
		currentSpellTexture = (info and info.iconID) or currentSpellTexture
	else
		currentSpellName = text or name
	end

	-- Calculate latency
	local sendLag = (castSent > 0) and (GetTime() * 1000 - castSent) or 0
	if sendLag <= 0 then
		local _, _, home, world = GetNetStats()
		sendLag = math.max(home or 0, world or 0)
	end
	sendLag = math.min(sendLag, castDuration)
	castLatency = (castDuration > 0) and (sendLag / castDuration) or 0

	self:Show()
end

function Cast:UNIT_SPELLCAST_CHANNEL_STOP(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	CancelRejectedAttemptFeedback()
	if not isCasting then
		return
	end
	if interruptFlashActive then
		return
	end
	if castGUID == currentCastGUID then
		self:Hide()
	end
end

function Cast:UNIT_SPELLCAST_CHANNEL_UPDATE(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end

	local name, text, texture, startTimeMS, endTimeMS = UnitChannelInfo("player")
	if name then
		castStartTime = startTimeMS
		castEndTime = endTimeMS
		castDuration = castEndTime - castStartTime
		self:UpdateIconCooldown()
	end
end

function Cast:UNIT_SPELLCAST_SUCCEEDED(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	CancelRejectedAttemptFeedback()
	if isCasting or interruptFlashActive then
		return
	end
	if UnitCastingInfo("player") or UnitChannelInfo("player") then
		return
	end

	local playerInstantSpellID = GetConfirmedPlayerInstantSpellID(castGUID, spellID)
	local resolvedSpellID = ResolvePlayerFacingSpellID(spellID)

	ClearPendingInstantIntent()

	if playerInstantSpellID then
		if ShouldShowPlayerInstantCasts() then
			ShowInstantSpellIcon(playerInstantSpellID, true)
		end
		return
	end

	if ShouldShowTriggeredInstantCasts() and IsInstantSpell(resolvedSpellID) then
		ShowInstantSpellIcon(resolvedSpellID, true)
	end
end

-- Evoker Empower support
function Cast:UNIT_SPELLCAST_EMPOWER_START(event, unit, castGUID, spellID)
	self:UNIT_SPELLCAST_START(event, unit, castGUID, spellID)
end

function Cast:UNIT_SPELLCAST_EMPOWER_STOP(event, unit, castGUID, spellID)
	self:UNIT_SPELLCAST_STOP(event, unit, castGUID, spellID)
end

function Cast:UNIT_SPELLCAST_EMPOWER_UPDATE(event, unit, castGUID, spellID)
	self:UNIT_SPELLCAST_DELAYED(event, unit, castGUID, spellID)
end

--------------------------------------------------------------------------------
-- Inner Ring Slot Management
--------------------------------------------------------------------------------
function Cast:ApplySlotAssignments()
	-- Disable all currently active providers before re-assignment.
	DisableSlotProviders()

	-- Clear existing assignments (defer visibility changes until after re-assignment
	-- to avoid hide/show flicker while casting).
	for i = 1, NUM_SLOTS do
		local slot = slots[i]
		if slot then
			slot.provider = nil
			slot.providerID = nil
		end
	end

	-- Read settings and assign providers.
	for i = 1, NUM_SLOTS do
		local slot = slots[i]
		if slot then
			local providerID = NormalizeProviderID(GetDBValue("slot" .. i .. "_provider"))
			slot.providerID = providerID
			if providerID ~= "NONE" then
				local provider = SlotProviders:Get(providerID)
				if provider then
					slot.provider = provider
				end
			end
		end
	end

	-- Keep providers inactive if module is currently disabled.
	if not moduleEnabled then
		return
	end

	-- Enable each unique assigned provider once.
	for i = 1, NUM_SLOTS do
		local slot = slots[i]
		if slot and slot.provider and not activeProviders[slot.providerID] then
			slot.provider:Enable()
			activeProviders[slot.providerID] = slot.provider
		end
	end

	-- Enforce slot visibility contract:
	-- assigned/non-NONE slots stay mounted while cast ring is visible.
	for i = 1, NUM_SLOTS do
		local slot = slots[i]
		if slot and slot.provider and moduleEnabled and IsCastVisibilityAllowed() then
			slot.widget:Show()
		elseif slot then
			slot.widget:Hide()
		end
	end
end

function Cast:ApplySlotOptions()
	if not castFrame then
		return
	end

	local radius = GetDBValue("cast_radius")
	for i = 1, NUM_SLOTS do
		local slot = slots[i]
		if slot then
			local backgroundOpacity = GetDBValue("slot" .. i .. "_backgroundOpacity")
			if backgroundOpacity == nil then
				backgroundOpacity = 0.8
			end
			local backgroundColor = GetDBColorTable("slot" .. i .. "_backgroundColor") or { r = 1, g = 1, b = 1, a = 1 }
			slot.widget:SetRadius(radius * SLOT_ROOT_SCALE[i])
			slot.widget:SetBarColor(GetSlotBarColor(i))
			slot.widget:SetBackgroundColor({
				r = backgroundColor.r or 1,
				g = backgroundColor.g or 1,
				b = backgroundColor.b or 1,
				a = backgroundOpacity,
			})
			slot.widget:SetFrameLevel(NUM_SLOTS - i + 1)
		end
	end
end

--------------------------------------------------------------------------------
-- ApplyOptions: Update visuals from settings
--------------------------------------------------------------------------------
function Cast:ApplyOptions()
	if not castFrame then
		return
	end

	local radius = GetDBValue("cast_radius")
	local thickness = 20
	local frameOpacity = GetDBValue("cast_frameOpacity")
	if frameOpacity == nil then
		frameOpacity = 0.8
	end
	local backgroundOpacity = GetDBValue("cast_backgroundOpacity")
	if backgroundOpacity == nil then
		backgroundOpacity = 0.8
	end
	local glowOpacity = GetDBValue("cast_glowOpacity")
	if glowOpacity == nil then
		glowOpacity = 0.8
	end
	castGlowMaxOpacity = glowOpacity
	local backgroundColorSetting = GetDBColorTable("cast_backgroundColor") or { r = 1, g = 1, b = 1, a = 1 }
	local backgroundColor = {
		r = backgroundColorSetting.r or 1,
		g = backgroundColorSetting.g or 1,
		b = backgroundColorSetting.b or 1,
		a = backgroundOpacity,
	}
	local frameColor = { r = 1, g = 1, b = 1, a = frameOpacity }
	local glowColor = { r = 1, g = 1, b = 1, a = glowOpacity }

	-- Update spark
	local r, g, b, a
	if GetDBBool("cast_sparkUseClassColor") then
		r, g, b, a = API.GetPlayerClassColor()
	else
		r, g, b, a = GetDBColor("cast_sparkColor")
	end
	castFrame.sparkTexture:SetVertexColor(r, g, b, a)
	castFrame.sparkTexture:SetSize(radius * 0.5, radius * 0.5)

	-- Rebuild donuts if needed
	if not castDonut then
		-- Create latency donut (between fill and frame)
		latencyDonut = DonutWidget:Create({
			direction = false,
			radius = radius,
			thickness = thickness,
			useThicknessSuffix = false,
			barColor = GetDBColorTable("cast_latencyColor"),
			backgroundColor = { r = 1, g = 1, b = 1, a = 0 },
			backgroundTextureBase = nil,
			progressTextureBase = "cast_fill",
			frameTextureBase = nil,
		})
		latencyDonut:AttachTo(castFrame)
		latencyDonut:SetOverlayShown(false)
		latencyDonut:SetBackgroundColor({ r = 1, g = 1, b = 1, a = 0 })

		-- Create cast donut (background + fill + glow)
		castDonut = DonutWidget:Create({
			direction = true,
			radius = radius,
			thickness = thickness,
			useThicknessSuffix = false,
			barColor = GetActiveCastBarColor(),
			backgroundColor = backgroundColor,
			backgroundTextureBase = "cast_background",
			progressTextureBase = "cast_fill",
			overlayTextureBase = CAST_OVERLAY_DEFAULT,
			frameTextureBase = nil,
		})
		castDonut:AttachTo(castFrame)
	else
		-- Update existing donuts
		castDonut:SetRadius(radius)
		castDonut:SetThickness(thickness)
		castDonut:SetBarColor(GetActiveCastBarColor())
		castDonut:SetBackgroundColor(backgroundColor)

		latencyDonut:SetRadius(radius)
		latencyDonut:SetThickness(thickness)
		latencyDonut:SetBarColor(GetDBColorTable("cast_latencyColor"))
		latencyDonut:SetBackgroundColor({ r = 1, g = 1, b = 1, a = 0 })
	end

	-- Update glow overlay color
	if castDonut then
		castDonut:SetOverlayTextureBase(CAST_OVERLAY_DEFAULT)
		castDonut:SetOverlayColor(glowColor)
	end

	-- Update frame overlay texture (top border)
	if castFrame.frameTexture then
		local texPath = addon.addonFolder .. "\\Textures\\cast_frame.png"
		SetTextureSmooth(castFrame.frameTexture, texPath)
		castFrame.frameTexture:SetVertexColor(frameColor.r, frameColor.g, frameColor.b, frameColor.a)
		castFrame.frameTexture:SetSize(radius * 2, radius * 2)
		castFrame.frameTexture:ClearAllPoints()
		castFrame.frameTexture:SetPoint("CENTER", castFrame.overlayFrame, "CENTER")
		castFrame.frameTexture:Hide()
	end
	if castFrame.feedbackTexture then
		SetTextureSmooth(castFrame.feedbackTexture, CAST_FEEDBACK_PATH)
		castFrame.feedbackTexture:SetBlendMode("ADD")
		castFrame.feedbackTexture:SetSize(radius * 2, radius * 2)
		castFrame.feedbackTexture:ClearAllPoints()
		castFrame.feedbackTexture:SetPoint("CENTER", castFrame.overlayFrame, "CENTER")
		self:UpdateClickFeedbackVisual()
	end

	-- Enforce layering: slots innermost, then cast fill, then latency on top
	-- Slots are at levels 1..NUM_SLOTS (innermost = 1)
	if castFrame.iconFrame then
		castFrame.iconFrame:SetFrameLevel(0)
	end
	if castDonut then
		castDonut:SetFrameLevel(NUM_SLOTS + 1)
	end
	if latencyDonut then
		latencyDonut:SetFrameLevel(NUM_SLOTS + 2)
	end

	-- Update inner ring slot options
	self:ApplySlotOptions()

	-- Update spell text
	if castFrame.spellText then
		local font = GetDBValue("cast_spellTextFont")
		local size = GetDBValue("cast_spellTextSize")
		local outline = GetDBValue("cast_spellTextOutline")

		castFrame.spellText:SetFont(font, size, outline)

		local tr, tg, tb, ta
		if GetDBBool("cast_spellTextUseClassColor") then
			tr, tg, tb, ta = API.GetPlayerClassColor()
		else
			tr, tg, tb, ta = GetDBColor("cast_spellTextColor")
		end
		castFrame.spellText:SetTextColor(tr, tg, tb, ta)

		local offsetX = GetDBValue("cast_spellTextOffsetX")
		local offsetY = GetDBValue("cast_spellTextOffsetY")
		castFrame.spellText:ClearAllPoints()
		castFrame.spellText:SetPoint("BOTTOM", castFrame, "CENTER", offsetX, radius + 5 + offsetY)
		-- Warm text rendering after font is set
		castFrame.spellText:SetText(" ")
		castFrame.spellText:Hide()
	end

	-- No frame-level pinning; rely on natural draw order.
	self:UpdateShellVisibility()
end

--------------------------------------------------------------------------------
-- Initialize
--------------------------------------------------------------------------------
function Cast:Initialize()
	local anchor = AnchorFrame:GetFrame()
	if not anchor then
		return
	end

	castFrame = CreateFrame("Frame", nil, anchor)
	castFrame:SetAllPoints()
	castFrame:Hide()

	-- Create overlay frame for top-most elements
	castFrame.overlayFrame = CreateFrame("Frame", nil, castFrame)
	castFrame.overlayFrame:SetAllPoints()
	castFrame.overlayFrame:SetFrameLevel(castFrame:GetFrameLevel() + 10)

	-- Create spark texture (above rings)
	castFrame.sparkTexture = castFrame.overlayFrame:CreateTexture(nil, "OVERLAY")
	castFrame.sparkTexture:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	castFrame.sparkTexture:SetBlendMode("ADD")
	castFrame.sparkTexture:SetSize(32, 32)

	-- Create click feedback overlay texture
	castFrame.feedbackTexture = castFrame.overlayFrame:CreateTexture(nil, "OVERLAY")
	castFrame.feedbackTexture:SetDrawLayer("OVERLAY", 6)
	castFrame.feedbackTexture:Hide()

	-- Create cast frame overlay texture (top border)
	castFrame.frameTexture = castFrame.overlayFrame:CreateTexture(nil, "OVERLAY")
	castFrame.frameTexture:SetDrawLayer("OVERLAY", 7)
	castFrame.frameTexture:Hide()

	-- Create spell text
	castFrame.spellText = castFrame:CreateFontString(nil, "OVERLAY")
	castFrame.spellText:Hide()

	-- Create spell icon frame (rendered with cast frame)
	castFrame.iconFrame = CreateFrame("Frame", nil, castFrame)
	castFrame.iconFrame:SetSize(32, 32)
	castFrame.iconFrame:SetPoint("CENTER", castFrame, "CENTER", 0, -40)
	castFrame.iconFrame:SetFrameLevel(0)
	castFrame.iconFrame:Hide()

	castFrame.iconFrame.icon = castFrame.iconFrame:CreateTexture(nil, "BACKGROUND")
	castFrame.iconFrame.icon:SetPoint("CENTER")
	castFrame.iconFrame.icon:SetTexCoord(0, 1, 0, 1)

	castFrame.iconFrame.errorIcon = castFrame.iconFrame:CreateTexture(nil, "ARTWORK")
	castFrame.iconFrame.errorIcon:SetDrawLayer("ARTWORK", 5)
	castFrame.iconFrame.errorIcon:SetBlendMode("BLEND")
	castFrame.iconFrame.errorIcon:Hide()

	-- Preload assets to avoid first-use stutter (font must be set before text)
	castFrame.iconFrame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	castFrame.iconFrame.icon:Hide()
	SetTextureSmooth(castFrame.iconFrame.errorIcon, SPELL_ICON_ERROR_PATH)

	if not castFrame.iconFrame.cooldown then
		castFrame.iconFrame.cooldown = CreateFrame("Cooldown", nil, castFrame.iconFrame, "CooldownFrameTemplate")
		castFrame.iconFrame.cooldown:SetDrawEdge(false)
		castFrame.iconFrame.cooldown:SetHideCountdownNumbers(true)
		pcall(castFrame.iconFrame.cooldown.SetSwipeTexture, castFrame.iconFrame.cooldown, SPELL_ICON_COOLDOWN_SWIPE_PATH)
		LayoutSpellIconCooldown()
		castFrame.iconFrame.cooldown:Hide()
	end

	castFrame.iconMaskReady = ApplySpellIconMask()

	-- Create inner ring slot widgets
	local radius = GetDBValue("cast_radius")
	for i = 1, NUM_SLOTS do
		local slotBackgroundColor = GetDBColorTable("slot" .. i .. "_backgroundColor") or { r = 1, g = 1, b = 1, a = 1 }
		local widget = SlotRingWidget:Create({
			radius = radius * SLOT_ROOT_SCALE[i],
			fillBase = "slot" .. i .. "_fill",
			frameBase = "slot" .. i .. "_frame",
			backgroundBase = "slot" .. i .. "_background",
			sparkRadiusRatio = SLOT_SPARK_RADIUS_RATIOS[i],
			barColor = GetDBColorTable("slot" .. i .. "_barColor"),
			backgroundColor = {
				r = slotBackgroundColor.r or 1,
				g = slotBackgroundColor.g or 1,
				b = slotBackgroundColor.b or 1,
				a = GetDBValue("slot" .. i .. "_backgroundOpacity") or 0.8,
			},
		})
		widget:AttachTo(castFrame)
		widget:Hide()
		slots[i] = { widget = widget, provider = nil, providerID = nil }
	end

	-- Set scripts
	castFrame:SetScript("OnUpdate", OnUpdate)
	castFrame:SetScript("OnShow", function()
		Cast:ApplyPendingVisuals()
	end)

	spellIconEnabled = addon.GetDBBool("moduleEnabled_SpellIcon")
	InstallActionIntentHook()
	self:ApplyOptions()
	self:ApplyIconOptions()
	self:ApplySlotAssignments()
end

--------------------------------------------------------------------------------
-- Enable/Disable
--------------------------------------------------------------------------------
local function EnableModule(enabled)
	moduleEnabled = enabled == true

	if enabled then
		-- Initialize if needed
		if not castFrame then
			Cast:Initialize()
		end

		-- Register events
		EL:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
		EL:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
		EL:RegisterEvent("SPELL_UPDATE_COOLDOWN")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
		EL:RegisterEvent("UNIT_SPELLCAST_SENT")

		-- Evoker Empower events
		EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_START", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_STOP", "player")
		EL:RegisterUnitEvent("UNIT_SPELLCAST_EMPOWER_UPDATE", "player")

		Cast:ApplySlotAssignments()
		Cast:UpdateShellVisibility()
	else
		EL:UnregisterAllEvents()
		Cast:Hide()
		DisableSlotProviders()
	end
end

--------------------------------------------------------------------------------
-- Event Dispatcher
--------------------------------------------------------------------------------
EL:SetScript("OnEvent", function(self, event, ...)
	if Cast[event] then
		Cast[event](Cast, event, ...)
	end
end)

--------------------------------------------------------------------------------
-- Register Setting Callbacks
--------------------------------------------------------------------------------
local settingKeys = {
	"cast_radius",
	"cast_barColor",
	"cast_channelBarColor",
	"cast_fillColorSource",
	"cast_backgroundColor",
	"cast_backgroundOpacity",
	"cast_frameOpacity",
	"cast_glowOpacity",
	"cast_clickFeedbackEnabled",
	"cast_clickFeedbackLeft",
	"cast_clickFeedbackRight",
	"cast_clickFeedbackOpacity",
	"cast_clickFeedbackUseClassColor",
	"cast_clickFeedbackLeftColor",
	"cast_clickFeedbackRightColor",
	"cast_sparkColor",
	"cast_sparkUseClassColor",
	"cast_latencyColor",
	"cast_displayMode",
	"cast_spellTextEnabled",
	"cast_spellTextFont",
	"cast_spellTextSize",
	"cast_spellTextOutline",
	"cast_spellTextColor",
	"cast_spellTextUseClassColor",
	"cast_spellTextOffsetX",
	"cast_spellTextOffsetY",
	"spellicon_size",
	"spellicon_offsetX",
	"spellicon_offsetY",
	"spellicon_castProgressSwipe",
	"spellicon_castProgressSwipeColor",
	"spellicon_cooldownBlockedUseClassColor",
	"spellicon_cooldownBlockedSwipeColor",
}

for _, key in ipairs(settingKeys) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		Cast:ApplyOptions()
	end)
end

for _, key in ipairs({
	"visibility_mode",
	"cast_visibilitySource",
	"cast_visibility",
	"visibility_hideOnUIHover",
	"cast_hideOnUIHover",
	"attachToMouse",
}) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		Cast:UpdateShellVisibility()
	end)
end

CallbackRegistry:Register("VisibilityContextChanged", function()
	Cast:UpdateShellVisibility()
end, Cast)

-- Slot provider assignment callbacks
for i = 1, NUM_SLOTS do
	CallbackRegistry:RegisterSettingCallback("slot" .. i .. "_provider", function()
		Cast:ApplySlotAssignments()
	end)
end

-- Slot color callbacks
for i = 1, NUM_SLOTS do
	for _, suffix in ipairs({ "_barColor", "_backgroundColor", "_backgroundOpacity", "_useClassColor" }) do
		CallbackRegistry:RegisterSettingCallback("slot" .. i .. suffix, function()
			Cast:ApplySlotOptions()
		end)
	end
end

--------------------------------------------------------------------------------
-- Register Module
--------------------------------------------------------------------------------
addon.ControlCenter:AddModule({
	name = L["Cast Ring"] or "Cast Ring",
	dbKey = "moduleEnabled_Cast",
	description = L["Cast Ring Description"] or "Shows a progress ring around your cursor during spell casts",
	toggleFunc = EnableModule,
	categoryID = 1,
	uiOrder = 1,
})
