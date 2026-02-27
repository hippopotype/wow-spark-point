-- SparkPoint Cast Module
-- Displays a ring around cursor during spell casting with latency indicator

local _, addon = ...
local L = addon.L
local API = addon.API
local DonutWidget = addon.DonutWidget
local CallbackRegistry = addon.CallbackRegistry
local AnchorFrame = addon.AnchorFrame
local Visibility = addon.Visibility
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor
local GetDBColorTable = addon.GetDBColorTable

local SlotRingWidget = addon.SlotRingWidget
local SlotProviders = addon.SlotProviders

local Cast
local SPELL_ICON_MASK_PATH = addon.addonFolder .. "\\Textures\\spell_icon_mask.png"
local SPELL_ICON_ERROR_PATH = addon.addonFolder .. "\\Textures\\spell_icon_error.png"
local CAST_FEEDBACK_PATH = addon.addonFolder .. "\\Textures\\cast_feedback.png"
local SPELL_ICON_MASK_BASE_SIZE = 32
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
local interruptFlashToken = 0
local interruptFlashActive = false
local INTERRUPT_FLASH_DURATION = 0.2
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

--------------------------------------------------------------------------------
-- Cast Module Object
--------------------------------------------------------------------------------
Cast = {}
addon.Modules.CastObj = Cast

function Cast:GetFrame()
	return castFrame
end

local function ApplySpellIconMask()
	if not castFrame or not castFrame.iconFrame or not castFrame.iconFrame.icon then
		return false
	end
	local iconFrame = castFrame.iconFrame
	local icon = iconFrame.icon
	if not icon.AddMaskTexture then
		return false
	end

	iconFrame.iconMask = iconFrame.iconMask or iconFrame:CreateMaskTexture()
	local mask = iconFrame.iconMask
	if not mask then
		return false
	end

	local iconSize = icon:GetWidth() or SPELL_ICON_MASK_BASE_SIZE
	local expand = math.floor((iconSize / SPELL_ICON_MASK_BASE_SIZE) * SPELL_ICON_MASK_BASE_EXPAND + 0.5)
	if expand < 0 then
		expand = 0
	end

	mask:SetTexture(SPELL_ICON_MASK_PATH, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	mask:ClearAllPoints()
	mask:SetPoint("TOPLEFT", icon, "TOPLEFT", -expand, expand)
	mask:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", expand, -expand)

	if not iconFrame.iconMaskAttached then
		local ok = pcall(icon.AddMaskTexture, icon, mask)
		if not ok then
			return false
		end
		iconFrame.iconMaskAttached = true
	end

	-- Cooldown swipe uses its own texture regions; mask them too so the
	-- progress sweep stays circular inside the spell icon silhouette.
	if iconFrame.cooldown and not iconFrame.cooldownMaskAttached then
		local maskedAny = false
		local regionCount = select("#", iconFrame.cooldown:GetRegions())
		for i = 1, regionCount do
			local region = select(i, iconFrame.cooldown:GetRegions())
			if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.AddMaskTexture then
				local ok = pcall(region.AddMaskTexture, region, mask)
				if ok then
					maskedAny = true
				end
			end
		end
		-- Cooldown regions can be created lazily; only mark attached if we actually masked one.
		if maskedAny then
			iconFrame.cooldownMaskAttached = true
		end
	end

	return true
end

local function LayoutSpellIconErrorOverlay()
	if not castFrame or not castFrame.iconFrame or not castFrame.iconFrame.icon or not castFrame.iconFrame.errorIcon then
		return
	end

	local icon = castFrame.iconFrame.icon
	local overlay = castFrame.iconFrame.errorIcon
	local iconSize = icon:GetWidth() or SPELL_ICON_MASK_BASE_SIZE
	local expand = math.floor((iconSize / SPELL_ICON_MASK_BASE_SIZE) * SPELL_ICON_MASK_BASE_EXPAND + 0.5)
	if expand < 0 then
		expand = 0
	end

	overlay:ClearAllPoints()
	overlay:SetPoint("TOPLEFT", icon, "TOPLEFT", -expand, expand)
	overlay:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", expand, -expand)
end

local function LayoutSpellIconCooldown()
	if not castFrame or not castFrame.iconFrame or not castFrame.iconFrame.icon or not castFrame.iconFrame.cooldown then
		return
	end

	local icon = castFrame.iconFrame.icon
	local cooldown = castFrame.iconFrame.cooldown
	local iconSize = icon:GetWidth() or SPELL_ICON_MASK_BASE_SIZE
	local expand = math.floor((iconSize / SPELL_ICON_MASK_BASE_SIZE) * SPELL_ICON_MASK_BASE_EXPAND + 0.5)
	if expand < 0 then
		expand = 0
	end

	cooldown:ClearAllPoints()
	cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", -expand, expand)
	cooldown:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", expand, -expand)
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
			pcall(castFrame.iconFrame.cooldown.SetSwipeTexture, castFrame.iconFrame.cooldown, SPELL_ICON_MASK_PATH)
		end
		LayoutSpellIconCooldown()
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
	if not IsCastVisibilityAllowed() or not castFrame:IsShown() then
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
	castFrame.iconFrame:Show()
	self:UpdateIconCooldown()
end

local function ClearInstantIcon(reason)
	instantIconActive = false
	instantIconConfirmed = false
	instantIconExpiry = 0
	if instantIconForcedShell then
		instantIconForcedShell = false
		Cast:UpdateShellVisibility()
	elseif not isCasting then
		Cast:UpdateSpellIcon()
	end
end

local function ShowInstantSpellIcon(spellID, fromSucceeded)
	if not GetDBBool("spellicon_showInstantCasts") then
		return
	end
	if not spellIconEnabled then
		return
	end
	if not spellID then
		return
	end

	local info = C_Spell.GetSpellInfo(spellID)
	if not info then
		return
	end
	if (info.castTime or 0) > 0 then
		return
	end

	-- SENT-based previews must not override a confirmed (SUCCEEDED) icon.
	if instantIconConfirmed and not fromSucceeded then
		return
	end

	currentSpellID = spellID
	currentSpellName = info.name or currentSpellName
	currentSpellTexture = info.iconID or currentSpellTexture
	instantIconActive = true
	if fromSucceeded then
		instantIconConfirmed = true
	end

	-- Instant casts have no cast bar start event, so the cast shell parent may still be hidden.
	-- Temporarily show it so the child icon frame can render, then restore via UpdateShellVisibility().
	if castFrame and (not castFrame:IsShown()) and IsCastVisibilityAllowed() then
		instantIconForcedShell = true
		AnchorFrame:Show("cast")
		castFrame:Show()
	end

	Cast:UpdateSpellIcon()

	local _, gcdDuration = API.GetSpellCooldown(61304)
	local duration = tonumber(gcdDuration) or 0
	if duration <= 0 or duration > 2 then
		duration = 0.35
	end
	-- Expiry is checked each frame in OnUpdate; no timer closure needed.
	instantIconExpiry = GetTime() + duration
end

function Cast:UpdateIconCooldown()
	if not castFrame or not castFrame.iconFrame or not castFrame.iconFrame.cooldown then
		return
	end
	if not GetDBBool("spellicon_castProgressSwipe") then
		castFrame.iconFrame.cooldown:Hide()
		return
	end
	if not isCasting or not castStartTime or castDuration == 0 then
		castFrame.iconFrame.cooldown:Hide()
		return
	end
	castFrame.iconFrame.cooldown:SetCooldown(castStartTime / 1000, castDuration / 1000)
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
	local useClassColor = GetDBBool("cast_useClassColor")
	local cr, cg, cb, ca
	if useClassColor then
		cr, cg, cb, ca = API.GetPlayerClassColor()
	end

	if castPerc < 1 then
		local angle = castPerc * 360
		local clampedPerc = math.max(0, math.min(1, castPerc))

		-- Reverse for channeled spells if enabled
		if GetDBBool("cast_reverseChanneling") and UnitChannelInfo("player") then
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
		if useClassColor then
			r, g, b, a = cr, cg, cb, ca
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
			castFrame:Hide()
		end
		AnchorFrame:Hide("cast")
		return
	end
	AnchorFrame:Show("cast")

	-- Show latency indicator
	if latencyDonut then
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
	if castFrame.sparkTexture then
		castFrame.sparkTexture:Show()
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

	castFrame:Show()
end

function Cast:UpdateShellVisibility()
	if not castFrame then
		return
	end

	local allowed = moduleEnabled and IsCastVisibilityAllowed()
	if not allowed then
		if castDonut then
			castDonut:Hide()
			castDonut:SetOverlayShown(false)
			castDonut:SetOverlayAlpha(0)
			castDonut:SetAngle(0)
		end
		if latencyDonut then
			latencyDonut:Hide()
		end
		if castFrame.frameTexture then
			castFrame.frameTexture:Hide()
		end
		if castFrame.sparkTexture then
			castFrame.sparkTexture:Hide()
		end
		if castFrame.spellText then
			castFrame.spellText:Hide()
		end
		if castFrame.iconFrame then
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
		castFrame:Hide()
		AnchorFrame:Hide("cast")
		return
	end

	AnchorFrame:Show("cast")
	castFrame:Show()

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

	interruptFlashToken = interruptFlashToken + 1
	interruptFlashActive = false
	isCasting = false
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
		SetTextureSmooth(castFrame.iconFrame.errorIcon, SPELL_ICON_ERROR_PATH)
		LayoutSpellIconErrorOverlay()
		castFrame.iconFrame.errorIcon:Show()
		castFrame.iconFrame:Show()
		if castFrame.iconFrame.cooldown then
			castFrame.iconFrame.cooldown:Hide()
		end
	end
	castDonut:Show()
	castFrame:Show()
	AnchorFrame:Show("cast")

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

	-- SENT fires earlier than SUCCEEDED for instant abilities; pre-show to avoid visible lag.
	if not isCasting and not interruptFlashActive and not UnitCastingInfo("player") and not UnitChannelInfo("player") then
		ShowInstantSpellIcon(spellID, false)
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
	interruptFlashToken = interruptFlashToken + 1
	interruptFlashActive = false

	local name, text, texture, startTimeMS, endTimeMS = UnitCastingInfo("player")
	if not name then
		return
	end

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
		return
	end
	if castGUID == currentCastGUID then
		self:ShowInterruptFlash(castGUID)
	end
end

function Cast:UNIT_SPELLCAST_FAILED_QUIET(event, unit, castGUID, spellID)
	if unit ~= "player" then
		return
	end
	if not isCasting then
		return
	end
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
	interruptFlashToken = interruptFlashToken + 1
	interruptFlashActive = false

	local name, text, texture, startTimeMS, endTimeMS = UnitChannelInfo("player")
	if not name then
		return
	end

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
	if isCasting or interruptFlashActive then
		return
	end
	if UnitCastingInfo("player") or UnitChannelInfo("player") then
		return
	end

	-- Refresh/confirm the instant icon window after cooldown data settles.
	ShowInstantSpellIcon(spellID, true)
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
			slot.widget:SetRadius(radius * SLOT_ROOT_SCALE[i])
			slot.widget:SetBarColor(GetSlotBarColor(i))
			slot.widget:SetBackgroundColor({ r = 1, g = 1, b = 1, a = backgroundOpacity })
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
	local useClassColor = GetDBBool("cast_useClassColor")
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
	local cr, cg, cb, ca
	if useClassColor then
		cr, cg, cb, ca = API.GetPlayerClassColor()
	end
	local backgroundColor = { r = 1, g = 1, b = 1, a = backgroundOpacity }
	local frameColor = { r = 1, g = 1, b = 1, a = frameOpacity }
	local glowColor = { r = 1, g = 1, b = 1, a = glowOpacity }

	-- Update spark
	local r, g, b, a
	if useClassColor then
		r, g, b, a = cr, cg, cb, ca
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
			barColor = useClassColor and { r = cr, g = cg, b = cb, a = ca } or GetDBColorTable("cast_barColor"),
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
		castDonut:SetBarColor(useClassColor and { r = cr, g = cg, b = cb, a = ca } or GetDBColorTable("cast_barColor"))
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
		if useClassColor then
			tr, tg, tb, ta = cr, cg, cb, ca
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
		pcall(castFrame.iconFrame.cooldown.SetSwipeTexture, castFrame.iconFrame.cooldown, SPELL_ICON_MASK_PATH)
		LayoutSpellIconCooldown()
		castFrame.iconFrame.cooldown:Hide()
	end

	castFrame.iconMaskReady = ApplySpellIconMask()

	-- Create inner ring slot widgets
	local radius = GetDBValue("cast_radius")
	for i = 1, NUM_SLOTS do
		local widget = SlotRingWidget:Create({
			radius = radius * SLOT_ROOT_SCALE[i],
			fillBase = "slot" .. i .. "_fill",
			frameBase = "slot" .. i .. "_frame",
			backgroundBase = "slot" .. i .. "_background",
			sparkRadiusRatio = SLOT_SPARK_RADIUS_RATIOS[i],
			barColor = GetDBColorTable("slot" .. i .. "_barColor"),
			backgroundColor = { r = 1, g = 1, b = 1, a = GetDBValue("slot" .. i .. "_backgroundOpacity") or 0.8 },
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
	"cast_latencyColor",
	"cast_useClassColor",
	"cast_spellTextEnabled",
	"cast_spellTextFont",
	"cast_spellTextSize",
	"cast_spellTextOutline",
	"cast_spellTextColor",
	"cast_spellTextOffsetX",
	"cast_spellTextOffsetY",
	"spellicon_size",
	"spellicon_offsetX",
	"spellicon_offsetY",
	"spellicon_castProgressSwipe",
}

for _, key in ipairs(settingKeys) do
	CallbackRegistry:RegisterSettingCallback(key, function()
		Cast:ApplyOptions()
	end)
end

for _, key in ipairs({ "visibility_mode", "cast_visibilitySource", "cast_visibility" }) do
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
	for _, suffix in ipairs({ "_barColor", "_backgroundOpacity", "_useClassColor" }) do
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
