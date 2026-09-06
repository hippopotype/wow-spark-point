-- SparkPoint Cooldown Icon Widget
--
-- One pooled, round masked icon matching Modules/AssistedHighlight.lua so the two
-- features read as one system.
--
-- There is deliberately NO count region. Stack counts and charge counts cannot be
-- obtained by addon code: C_UnitAuras.GetAuraApplicationDisplayCount and the item
-- frame's GetApplicationsText() both error for tainted callers, and
-- C_Spell.GetSpellCharges is secret when cooldowns are restricted. Per
-- .skills/secret-values.md, a feature with no stable path is dropped, not faked.
--
-- Availability styling never computes expiry. Blizzard does
-- `startTime + duration <= GetTime()`, which is forbidden to us on secret fields.
-- Instead a duration object is fed to a hidden scratch Cooldown and IsShown() is
-- read back as a plain boolean.
-- Technique adapted from .clones/Cooldown-Companion/ButtonFrame/CooldownUpdate.lua:63-70

local _, addon = ...
local IconMask = addon.IconMask
local Keybinds = addon.Keybinds
local Data = addon.CooldownViewerData
local SetTextureSmooth = addon.Util.SetTextureSmooth
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor

local CooldownIconWidget = {}
addon.CooldownIconWidget = CooldownIconWidget

local ICON_MASK_BASE_EXPAND = 6
local BACKGROUND_PATH = addon.addonFolder .. "\\Textures\\spell_icon_background.png"
local GLOW_PATH = addon.addonFolder .. "\\Textures\\spell_icon_glow.png"
local FRAME_PATH = addon.addonFolder .. "\\Textures\\spell_icon_frame.png"
local SWIPE_PATH = addon.addonFolder .. "\\Textures\\spell_icon_cooldown_swipe.png"

-- Hidden probe: converts a duration object into a plain boolean without arithmetic.
local scratchParent = CreateFrame("Frame")
scratchParent:Hide()
local scratchCooldown = CreateFrame("Cooldown", nil, scratchParent, "CooldownFrameTemplate")

local function IsSpellOnCooldown(spellID)
	if not C_Spell or not C_Spell.GetSpellCooldownDuration then
		return false
	end
	local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, spellID)
	if not ok or not duration then
		return false
	end
	local okSet = pcall(scratchCooldown.SetCooldownFromDurationObject, scratchCooldown, duration)
	if not okSet then
		return false
	end
	local okShown, shown = pcall(scratchCooldown.IsShown, scratchCooldown)
	return okShown and shown == true
end

-- The Cooldown widget has no direct "set countdown text color" API (SetCountdownFont
-- only takes font/size/outline), so the color is applied to the FontString region the
-- widget creates for its own countdown text. Wrapped in pcall: GetRegions/SetTextColor
-- are plain widget calls, not secret-value hazards, but the region layout is a
-- Blizzard implementation detail this file does not otherwise depend on.
local function ApplyCountdownTextColor(cooldown, r, g, b, a)
	pcall(function()
		for _, region in ipairs({ cooldown:GetRegions() }) do
			if region.GetObjectType and region:GetObjectType() == "FontString" then
				region:SetTextColor(r, g, b, a)
			end
		end
	end)
end

local WidgetMixin = {}

function WidgetMixin:SetEntry(entry)
	self.entry = entry
	if entry and entry.iconFileID then
		self.icon:SetTexture(entry.iconFileID)
	else
		-- entry.iconFileID can be nil (icon texture lookup failed); without this the
		-- recycled widget keeps showing whatever the previous occupant's icon was.
		self.icon:SetTexture(nil)
	end
end

function WidgetMixin:ApplyOptions(opts)
	local size = opts.size or 28
	self.frame:SetSize(size, size)
	self.icon:SetSize(size, size)

	local opacity = tonumber(GetDBValue("cooldownmanager_iconOpacity")) or 1
	self.icon:SetAlpha(opacity)

	self.maskReady = IconMask:ApplyToIconFrame(self.frame, ICON_MASK_BASE_EXPAND)

	IconMask:LayoutToIcon(self.background, self.icon, ICON_MASK_BASE_EXPAND)
	SetTextureSmooth(self.background, BACKGROUND_PATH)
	self.background:SetAlpha(opacity)

	IconMask:LayoutToIcon(self.border, self.icon, ICON_MASK_BASE_EXPAND)
	SetTextureSmooth(self.border, FRAME_PATH)
	self.border:SetAlpha(opacity)

	IconMask:LayoutToIcon(self.glow, self.icon, ICON_MASK_BASE_EXPAND)
	SetTextureSmooth(self.glow, GLOW_PATH)
	local gr, gg, gb, ga = GetDBColor("cooldownmanager_glowColor")
	self.glow:SetVertexColor(gr, gg, gb, ga or 1)

	self.cooldown:SetHideCountdownNumbers(not GetDBBool("cooldownmanager_showTimerText"))
	-- Wire the timer font keys, or they are unreachable settings rows.
	local timerFont = GetDBValue("cooldownmanager_timerFont") or "Fonts\\FRIZQT__.TTF"
	local timerOutline = GetDBValue("cooldownmanager_timerFontOutline") or "OUTLINE"
	local timerSize = tonumber(GetDBValue("cooldownmanager_timerFontSize")) or 13
	pcall(self.cooldown.SetCountdownFont, self.cooldown, timerFont, timerSize, timerOutline)
	local tr, tg, tb, ta = GetDBColor("cooldownmanager_timerColor")
	ApplyCountdownTextColor(self.cooldown, tr, tg, tb, ta or 1)

	local font = GetDBValue("cooldownmanager_keybindFont") or "Fonts\\FRIZQT__.TTF"
	local outline = GetDBValue("cooldownmanager_keybindFontOutline") or "OUTLINE"
	local fontSize = tonumber(GetDBValue("cooldownmanager_keybindFontSize")) or 13
	self.keybindText:SetFont(font, fontSize, outline)
	local kr, kg, kb, ka = GetDBColor("cooldownmanager_keybindColor")
	self.keybindText:SetTextColor(kr, kg, kb, ka or 1)

	self.showKeybind = opts.showKeybind == true
	self.keybindFormat = opts.keybindFormat or "COMPACT"
end

function WidgetMixin:UpdateState()
	local entry = self.entry
	if not entry then
		return
	end

	if entry.hasAura then
		-- Tracked Buff, SPARKPOINT mode is state-only per spec: aura durations and stack
		-- counts are unreachable from addon code (see Core/CooldownViewerBridge.lua), so
		-- this never touches the cooldown swipe/countdown path used below. Branches on
		-- entry.hasAura -- per-ENTRY data, not per-category -- so Invariant 2 holds.
		local active = Data:GetAuraActive(entry.cooldownID) -- true / false / nil
		pcall(self.cooldown.Clear, self.cooldown) -- spec: no swipe, no countdown
		if active ~= nil then
			self.icon:SetDesaturated(not active)
			self.glow:SetShown(GetDBBool("cooldownmanager_glowOnReady") and active)
		end -- nil => leave unstyled (Degradation row 4)
	else
		if GetDBBool("cooldownmanager_showSwipe") and C_Spell and C_Spell.GetSpellCooldownDuration then
			local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, entry.spellID)
			if ok and duration then
				pcall(self.cooldown.SetCooldownFromDurationObject, self.cooldown, duration)
			else
				pcall(self.cooldown.Clear, self.cooldown) -- Cooldown:Clear is a real widget method
			end
		end

		local onCooldown = IsSpellOnCooldown(entry.spellID)
		if GetDBBool("cooldownmanager_desaturateOnCooldown") then
			self.icon:SetDesaturated(onCooldown)
		else
			self.icon:SetDesaturated(false)
		end
		self.glow:SetShown(GetDBBool("cooldownmanager_glowOnReady") and not onCooldown)
	end

	if self.showKeybind then
		local key = Keybinds:GetBindingKeyForSpell(entry.spellID)
		self.keybindText:SetText(key and Keybinds:FormatBindingText(key, self.keybindFormat) or "")
		self.keybindText:Show()
	else
		self.keybindText:Hide()
	end
end

function WidgetMixin:SetShown(shown)
	self.frame:SetShown(shown)
end

function WidgetMixin:Release()
	self.entry = nil
	self.frame:Hide()
	self.frame:ClearAllPoints()
	-- Without these a widget released mid-swipe (or with showSwipe off, which never
	-- clears the cooldown) keeps drawing that swipe -- or the previous spell's icon --
	-- the next time it is pulled from the pool for a different entry.
	pcall(self.cooldown.Clear, self.cooldown)
	self.icon:SetTexture(nil)
end

function CooldownIconWidget:Create(parent)
	local widget = {}
	for k, v in pairs(WidgetMixin) do
		widget[k] = v
	end

	local frame = CreateFrame("Frame", nil, parent)
	widget.frame = frame

	widget.icon = frame:CreateTexture(nil, "ARTWORK")
	widget.icon:SetPoint("CENTER")
	widget.background = frame:CreateTexture(nil, "BACKGROUND")
	widget.glow = frame:CreateTexture(nil, "OVERLAY", nil, 1)
	widget.border = frame:CreateTexture(nil, "OVERLAY", nil, 2)

	-- IconMask keys on the lowercase `cooldown` field (Core/IconMask.lua:65).
	-- Setup mirrors the house pattern at Modules/Cast.lua:3143-3146.
	widget.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	widget.cooldown:SetAllPoints(widget.icon)
	widget.cooldown:SetDrawEdge(false)
	pcall(widget.cooldown.SetSwipeTexture, widget.cooldown, SWIPE_PATH)
	frame.cooldown = widget.cooldown
	frame.icon = widget.icon

	widget.keybindText = frame:CreateFontString(nil, "OVERLAY")
	widget.keybindText:SetPoint("TOP", frame, "TOP", 0, 4)
	-- Default font so a SetText before the first ApplyOptions cannot nil-error;
	-- Modules/AssistedHighlight.lua:584 does the same.
	widget.keybindText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")

	frame:Hide()
	return widget
end
