-- SparkPoint Cooldown Viewer Skin
--
-- QUARANTINE. The only code allowed to touch Blizzard's Cooldown Manager ITEM
-- frames (the icons inside Essential/Utility/BuffIcon viewers). It restyles them
-- to the SparkPoint icon look while Blizzard keeps rendering timers, charges,
-- stacks, buff durations, proc alerts and the pandemic indicator.
-- Spec: docs/superpowers/specs/2026-09-27-cooldown-manager-skin-design.md
--
-- ============================ READ BEFORE EDITING ============================
--  * Native widget calls only on Blizzard regions/frames. Item frames have no Lua
--    method overrides (unlike viewers, whose SetPoint is an Edit Mode override).
--  * NEVER write a key on a Blizzard frame or region (E14: a tainted key that
--    Blizzard reads taints its secure code). Everything lives in the weak tables
--    below. hooksecurefunc / HookScript post-hooks are allowed.
--  * NEVER call Blizzard Lua that builds or writes state
--    (Core/CooldownViewerBridge.lua rule 3).
--  * Child frames of an item frame are never hidden: the pandemic FX frame is a
--    pooled child (CooldownViewer.lua:2125-2131) that would vanish when re-used.
--  * Another skinning addon may style the same icons. We win by re-applying last
--    (layout pass + next frame) and by reasserting whenever someone else touches
--    the Icon (SetTexCoord/SetSize post-hooks -- Blizzard never calls those on
--    these icons). Its swipe COLOUR may still win; accepted. No addon is named.
-- =============================================================================

local _, addon = ...
local Util = addon.Util
local IconMask = addon.IconMask
local IconGlow = addon.IconGlow
local Keybinds = addon.Keybinds
local CallbackRegistry = addon.CallbackRegistry
local GetDBValue = addon.GetDBValue
local GetDBBool = addon.GetDBBool
local GetDBColor = addon.GetDBColor
local SetTextureSmooth = Util.SetTextureSmooth

local Skin = {}
addon.CooldownViewerSkin = Skin

local VIEWER_BY_CATEGORY = {
	[0] = "EssentialCooldownViewer",
	[1] = "UtilityCooldownViewer",
	[2] = "BuffIconCooldownViewer",
}

local TEXTURES = addon.addonFolder .. "\\Textures\\"
local BACKGROUND_PATH = TEXTURES .. "spell_icon_background.png"
local FRAME_PATH = TEXTURES .. "spell_icon_frame.png"
local GLOW_PATH = TEXTURES .. "spell_icon_glow.png"
local SWIPE_PATH = TEXTURES .. "spell_icon_cooldown_swipe.png"
local BLIZZARD_SWIPE_PATH = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local ICON_OVERLAY_ATLAS = "UI-HUD-CoolDownManager-IconOverlay"
local TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local TEXT_OUTLINE = "OUTLINE"
local BASE_EXPAND = 6
local BASE_SIZE = 32
local OVERLAY_LEVEL_OFFSET = 10

-- Dispel colours: ui-debuff-border-<type>-(no)icon atlases (AuraUtil.lua:5-9).
local DISPEL_COLOR_GLOBALS = {
	magic = "DEBUFF_TYPE_MAGIC_COLOR",
	curse = "DEBUFF_TYPE_CURSE_COLOR",
	disease = "DEBUFF_TYPE_DISEASE_COLOR",
	poison = "DEBUFF_TYPE_POISON_COLOR",
	bleed = "DEBUFF_TYPE_BLEED_COLOR",
}

local moduleEnabled = false
local globalHooksInstalled = false
local viewerHooked = {}
local enabledCategories = {}
local secondPassQueued = {}

-- All SparkPoint-owned, weak-keyed on Blizzard frames. Never stored ON the frames.
local skinned = setmetatable({}, { __mode = "k" })
local frameCategory = setmetatable({}, { __mode = "k" })
local reasserting = setmetatable({}, { __mode = "k" })
local reassertQueued = setmetatable({}, { __mode = "k" })

local SkinFrame -- forward declaration (used by hooks defined before it)

local function GetViewer(category)
	local name = VIEWER_BY_CATEGORY[category]
	return name and _G[name] or nil
end

local function IsActive(frame)
	local state = skinned[frame]
	return moduleEnabled and state ~= nil and state.applied == true and enabledCategories[frameCategory[frame]] == true
end

local function IsItemFrame(child)
	if not child or not Util.CanAccessFrameSafe(child) then
		return false
	end
	local ok, icon, cooldown = pcall(function()
		return child.Icon, child.Cooldown
	end)
	return ok and type(icon) == "table" and type(cooldown) == "table"
end

local function ForEachItemFrame(category, fn)
	local viewer = GetViewer(category)
	if not viewer then
		return
	end
	local ok, children = pcall(function()
		return { viewer:GetChildren() }
	end)
	if not ok or not children then
		return
	end
	for _, child in ipairs(children) do
		if IsItemFrame(child) then
			fn(child)
		end
	end
end

local function Contains(list, value)
	for _, item in ipairs(list) do
		if item == value then
			return true
		end
	end
	return false
end

local function GetTextSize()
	return tonumber(GetDBValue("cooldownmanager_textSize")) or 13
end

local function RecordFont(fontString)
	local font, size, flags = fontString:GetFont()
	local r, g, b, a = fontString:GetTextColor()
	return { font = font, size = size, flags = flags, r = r, g = g, b = b, a = a }
end

local function RestoreFont(fontString, record)
	if not fontString or not record then
		return
	end
	if record.font then
		fontString:SetFont(record.font, record.size, record.flags)
	end
	fontString:SetTextColor(record.r or 1, record.g or 1, record.b or 1, record.a or 1)
end

local function HideRegion(state, region)
	if not region then
		return
	end
	if state.hiddenRegions[region] == nil then
		state.hiddenRegions[region] = region:GetAlpha()
	end
	region:SetAlpha(0)
end

local function GetDispelColor(frame)
	local border = frame.DebuffBorder
	local texture = border and border.Texture
	if not border or not texture then
		return nil
	end
	-- UpdateFromAuraData shows the FRAME for any aura but only shows its Texture for a
	-- harmful one (AuraUtil.SetAuraBorderAtlasFromAura); a helpful buff stays neutral.
	local okShown, shown = pcall(border.IsShown, border)
	if not okShown or Util.GetAccessibleBoolean(shown, false) ~= true then
		return nil
	end
	local okTex, texShown = pcall(texture.IsShown, texture)
	if not okTex or Util.GetAccessibleBoolean(texShown, false) ~= true then
		return nil
	end
	if texture.GetAtlas then
		local ok, atlas = pcall(texture.GetAtlas, texture)
		if ok and type(atlas) == "string" and not (_G.issecretvalue and _G.issecretvalue(atlas)) then
			local kind = atlas:match("^ui%-debuff%-border%-(%a+)%-")
			local colorName = kind and DISPEL_COLOR_GLOBALS[kind]
			local color = colorName and _G[colorName]
			if color and color.r then
				return color.r, color.g, color.b
			end
		end
	end
	local generic = _G.DEBUFF_TYPE_NONE_COLOR
	if generic and generic.r then
		return generic.r, generic.g, generic.b
	end
	return 0.8, 0, 0
end

-- Element steps. Each runs in its own pcall so a template change in one region
-- never stops the rest of the skin.

local function EnsureOwnLayers(frame, state)
	if state.glow then
		return
	end
	state.ownRegions = state.ownRegions or {}
	state.mask = state.mask or IconMask:CreateMask(frame)
	state.background = state.background or frame:CreateTexture(nil, "BACKGROUND")
	state.ownRegions[state.background] = true
	if state.mask then
		state.ownRegions[state.mask] = true
	end
	SetTextureSmooth(state.background, BACKGROUND_PATH)

	-- Border, glow and keybind above Blizzard's Cooldown child: child frames draw over
	-- all parent regions, so the swipe would otherwise cover them (user-verified on the
	-- renderer). The swipe stays above the icon, below the frame and text.
	state.overlay = state.overlay or CreateFrame("Frame", nil, frame)
	state.overlay:SetAllPoints(frame)
	state.border = state.border or state.overlay:CreateTexture(nil, "OVERLAY", nil, 2)
	SetTextureSmooth(state.border, FRAME_PATH)
	state.glowTexture = state.glowTexture or state.overlay:CreateTexture(nil, "OVERLAY", nil, 1)
	SetTextureSmooth(state.glowTexture, GLOW_PATH)
	state.keybindText = state.keybindText or state.overlay:CreateFontString(nil, "OVERLAY")
	state.keybindText:SetPoint("TOP", frame, "TOP", 0, 4)
	state.keybindText:SetFont(TEXT_FONT, GetTextSize(), TEXT_OUTLINE)
	state.glow = IconGlow:Attach(state.glowTexture)
end

local function ApplyIcon(frame, state)
	local icon = frame.Icon
	icon:ClearAllPoints()
	icon:SetAllPoints(frame)
	icon:SetTexCoord(0, 1, 0, 1)

	local hasOurs = false
	for i = icon:GetNumMaskTextures(), 1, -1 do
		local mask = icon:GetMaskTexture(i)
		if mask == state.mask then
			hasOurs = true
		elseif mask then
			icon:RemoveMaskTexture(mask)
			if not Contains(state.removedMasks, mask) then
				state.removedMasks[#state.removedMasks + 1] = mask
			end
		end
	end
	if state.mask then
		IconMask:LayoutToIcon(state.mask, icon, BASE_EXPAND, BASE_SIZE)
		if not hasOurs then
			icon:AddMaskTexture(state.mask)
		end
	end
end

local function ApplyOwnLayers(frame, state)
	local icon = frame.Icon
	local cooldownLevel = frame.Cooldown and frame.Cooldown:GetFrameLevel() or frame:GetFrameLevel()
	state.overlay:SetFrameLevel(math.max(cooldownLevel + 1, frame:GetFrameLevel() + OVERLAY_LEVEL_OFFSET))
	IconMask:LayoutToIcon(state.background, icon, BASE_EXPAND, BASE_SIZE)
	IconMask:LayoutToIcon(state.border, icon, BASE_EXPAND, BASE_SIZE)
	IconMask:LayoutToIcon(state.glowTexture, icon, BASE_EXPAND, BASE_SIZE)
	state.background:Show()
	state.border:Show()
	state.overlay:Show()
	state.glow:SetColor(GetDBColor("cooldownmanager_glowColor"))

	local r, g, b = GetDispelColor(frame)
	if r then
		state.border:SetVertexColor(r, g, b, 1)
	else
		state.border:SetVertexColor(1, 1, 1, 1)
	end
end

local function ApplyCooldown(frame, state, textSize)
	local cooldown = frame.Cooldown
	cooldown:SetSwipeTexture(SWIPE_PATH)
	IconMask:LayoutToIcon(cooldown, frame.Icon, BASE_EXPAND, BASE_SIZE)
	local countdown = cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
	if countdown then
		if not state.countdownFont then
			state.countdownFont = RecordFont(countdown)
		end
		countdown:SetFont(TEXT_FONT, textSize, TEXT_OUTLINE)
		countdown:SetTextColor(GetDBColor("cooldownmanager_timerColor"))
	end
end

local function ApplyCounts(frame, state, textSize)
	local chargeText = frame.ChargeCount and frame.ChargeCount.Current
	local stackText = frame.Applications and frame.Applications.Applications
	for key, fontString in pairs({ charge = chargeText, stack = stackText }) do
		if fontString then
			if not state.countFonts[key] then
				state.countFonts[key] = RecordFont(fontString)
			end
			fontString:SetFont(TEXT_FONT, textSize, TEXT_OUTLINE)
			fontString:SetTextColor(GetDBColor("cooldownmanager_countColor"))
		end
	end
end

local function ApplyOutOfRange(frame, state)
	local oor = frame.OutOfRange
	if not oor then
		return
	end
	if not state.outOfRangeLayer then
		local layer, sublevel = oor:GetDrawLayer()
		state.outOfRangeLayer = { layer = layer, sublevel = sublevel }
	end
	oor:SetDrawLayer("OVERLAY", 0)
	local hasOurs = false
	for i = oor:GetNumMaskTextures(), 1, -1 do
		local mask = oor:GetMaskTexture(i)
		if mask == state.mask then
			hasOurs = true
		elseif mask then
			oor:RemoveMaskTexture(mask)
			if not Contains(state.removedOorMasks, mask) then
				state.removedOorMasks[#state.removedOorMasks + 1] = mask
			end
		end
	end
	if state.mask and not hasOurs then
		oor:AddMaskTexture(state.mask)
	end
end

local function HideBlizzardArt(frame, state)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region ~= frame.Icon and region.GetAtlas then
			-- Mask textures and other region types may not answer GetAtlas; one failing
			-- region must not stop the overlay from being found.
			local ok, atlas = pcall(region.GetAtlas, region)
			if ok and type(atlas) == "string" and not (_G.issecretvalue and _G.issecretvalue(atlas)) and atlas == ICON_OVERLAY_ATLAS then
				state.iconOverlay = region
			end
		end
	end
	HideRegion(state, state.iconOverlay)
	HideRegion(state, frame.DebuffBorder)
	HideRegion(state, frame.CooldownFlash)
end

local function HideUnknownRegions(frame, state)
	for _, region in ipairs({ frame:GetRegions() }) do
		local known = region == frame.Icon
			or region == frame.OutOfRange
			or region == state.iconOverlay
			or state.ownRegions[region]
			or Contains(state.removedMasks, region)
			or Contains(state.removedOorMasks, region)
		if not known then
			HideRegion(state, region)
		end
	end
end

local function ApplyKeybind(frame, state, textSize)
	local text = state.keybindText
	if not GetDBBool("cooldownmanager_showKeybind") or frame.Applications then
		text:Hide()
		return
	end
	local spellID
	local info = frame.cooldownInfo
	if type(info) == "table" then
		if Util.IsAccessibleNumber(info.overrideSpellID) then
			spellID = info.overrideSpellID
		elseif Util.IsAccessibleNumber(info.spellID) then
			spellID = info.spellID
		end
	end
	local key = spellID and Keybinds:GetBindingKeyForSpell(spellID)
	text:SetFont(TEXT_FONT, textSize, TEXT_OUTLINE)
	text:SetTextColor(GetDBColor("cooldownmanager_keybindColor"))
	text:SetText(key and Keybinds:FormatBindingText(key, "COMPACT") or "")
	text:Show()
end

local function SyncProcGlow(frame, state)
	local manager = _G.ActionButtonSpellAlertManager
	local alerted = manager and type(manager.activeAlerts) == "table" and manager.activeAlerts[frame] ~= nil
	if alerted then
		local alert = frame.SpellActivationAlert
		if alert then
			HideRegion(state, alert)
		end
		state.glow:StartProc()
	else
		state.glow:StopProc()
	end
end

local STEPS = {
	ApplyIcon,
	ApplyOwnLayers,
	ApplyCooldown,
	ApplyCounts,
	ApplyOutOfRange,
	HideBlizzardArt,
	HideUnknownRegions,
	ApplyKeybind,
	SyncProcGlow,
}

local function QueueReassert(frame)
	if reasserting[frame] or reassertQueued[frame] or not IsActive(frame) then
		return
	end
	reassertQueued[frame] = true
	C_Timer.After(0, function()
		reassertQueued[frame] = nil
		if IsActive(frame) then
			SkinFrame(frame, frameCategory[frame])
		end
	end)
end

local function InstallFrameHooks(frame, state)
	if state.hooked then
		return
	end
	state.hooked = true

	local flash = frame.CooldownFlash and frame.CooldownFlash.FlashAnim
	if flash and flash.HookScript then
		-- Blizzard Play()s this at cooldown START with a start delay; it only FINISHES
		-- naturally at cooldown end (Stop() fires OnStop). CooldownViewer.lua:1164-1178.
		flash:HookScript("OnFinished", function()
			local s = skinned[frame]
			if s and IsActive(frame) and GetDBBool("cooldownmanager_glowOnReady") then
				s.glow:PlayReady()
			end
		end)
	end

	local border = frame.DebuffBorder
	if border then
		local function OnBorderChanged()
			local s = skinned[frame]
			if s and IsActive(frame) then
				pcall(ApplyOwnLayers, frame, s)
			end
		end
		if border.UpdateFromAuraData then
			hooksecurefunc(border, "UpdateFromAuraData", OnBorderChanged)
		end
		border:HookScript("OnShow", OnBorderChanged)
		border:HookScript("OnHide", OnBorderChanged)
	end

	-- Blizzard calls RefreshIconColor from every RefreshData; other skinners move
	-- OutOfRange there, so re-assert its layer and mask right after.
	if frame.RefreshIconColor then
		hooksecurefunc(frame, "RefreshIconColor", function()
			local s = skinned[frame]
			if s and IsActive(frame) then
				pcall(ApplyOutOfRange, frame, s)
			end
		end)
	end

	hooksecurefunc(frame.Icon, "SetTexCoord", function()
		QueueReassert(frame)
	end)
	hooksecurefunc(frame.Icon, "SetSize", function()
		QueueReassert(frame)
	end)
end

SkinFrame = function(frame, category)
	local state = skinned[frame]
	if not state then
		state = { hiddenRegions = {}, removedMasks = {}, removedOorMasks = {}, countFonts = {} }
		skinned[frame] = state
	end
	frameCategory[frame] = category
	reasserting[frame] = true
	local okLayers = pcall(EnsureOwnLayers, frame, state)
	if okLayers and state.glow then
		pcall(InstallFrameHooks, frame, state)
		state.applied = true
		local textSize = GetTextSize()
		for _, step in ipairs(STEPS) do
			pcall(step, frame, state, textSize)
		end
	end
	reasserting[frame] = nil
end

local function UnskinFrame(frame)
	local state = skinned[frame]
	if not state or not state.applied then
		return
	end
	reasserting[frame] = true
	state.applied = false

	local icon = frame.Icon
	local oor = frame.OutOfRange
	if state.mask then
		pcall(icon.RemoveMaskTexture, icon, state.mask)
		if oor then
			pcall(oor.RemoveMaskTexture, oor, state.mask)
		end
	end
	for _, mask in ipairs(state.removedMasks) do
		pcall(icon.AddMaskTexture, icon, mask)
	end
	if oor then
		for _, mask in ipairs(state.removedOorMasks) do
			pcall(oor.AddMaskTexture, oor, mask)
		end
		if state.outOfRangeLayer then
			pcall(oor.SetDrawLayer, oor, state.outOfRangeLayer.layer, state.outOfRangeLayer.sublevel)
		end
	end
	state.removedMasks = {}
	state.removedOorMasks = {}
	state.outOfRangeLayer = nil

	local cooldown = frame.Cooldown
	pcall(cooldown.SetSwipeTexture, cooldown, BLIZZARD_SWIPE_PATH)
	pcall(function()
		cooldown:ClearAllPoints()
		cooldown:SetAllPoints(frame)
		RestoreFont(cooldown:GetCountdownFontString(), state.countdownFont)
	end)
	state.countdownFont = nil
	pcall(RestoreFont, frame.ChargeCount and frame.ChargeCount.Current, state.countFonts.charge)
	pcall(RestoreFont, frame.Applications and frame.Applications.Applications, state.countFonts.stack)
	state.countFonts = {}

	for region, alpha in pairs(state.hiddenRegions) do
		pcall(region.SetAlpha, region, alpha)
	end
	state.hiddenRegions = {}

	if state.glow then
		state.glow:StopAll()
	end
	for _, layer in ipairs({ state.background, state.border, state.overlay }) do
		pcall(layer.Hide, layer)
	end
	reasserting[frame] = nil
end

local function InstallViewerHooks(category)
	if viewerHooked[category] then
		return
	end
	local viewer = GetViewer(category)
	if not viewer or not viewer.RefreshData then
		return
	end
	viewerHooked[category] = true
	-- In-place updates that skip RefreshLayout (CooldownViewer.lua:2011-2023).
	hooksecurefunc(viewer, "RefreshData", function()
		Skin:Refresh(category)
	end)
end

local function InstallGlobalHooks()
	if globalHooksInstalled then
		return
	end
	local manager = _G.ActionButtonSpellAlertManager
	if not manager then
		return
	end
	globalHooksInstalled = true
	-- Fires on every item RefreshData (RefreshOverlayGlow): keep these O(1).
	hooksecurefunc(manager, "ShowAlert", function(_, button)
		local state = button and skinned[button]
		-- Another post-hook may already have hidden the alert again; follow the truth.
		if state and IsActive(button) and manager.activeAlerts[button] ~= nil then
			local alert = button.SpellActivationAlert
			if alert then
				HideRegion(state, alert)
			end
			state.glow:StartProc()
		end
	end)
	hooksecurefunc(manager, "HideAlert", function(_, button)
		local state = button and skinned[button]
		if state and IsActive(button) then
			state.glow:StopProc()
		end
	end)
end

function Skin:SetModuleEnabled(enabled)
	moduleEnabled = enabled == true
	if moduleEnabled then
		InstallGlobalHooks()
		return
	end
	for frame in pairs(skinned) do
		UnskinFrame(frame)
	end
	enabledCategories = {}
end

function Skin:SetCategoryEnabled(category, enabled)
	if not VIEWER_BY_CATEGORY[category] then
		return
	end
	if enabled and moduleEnabled then
		enabledCategories[category] = true
		InstallViewerHooks(category)
		-- Immediate pass: viewers are already laid out at login, before our hooks.
		self:Refresh(category)
	elseif enabledCategories[category] then
		enabledCategories[category] = nil
		ForEachItemFrame(category, UnskinFrame)
	end
end

function Skin:Refresh(category)
	if not moduleEnabled then
		return
	end
	if category == nil then
		for enabledCategory in pairs(enabledCategories) do
			self:Refresh(enabledCategory)
		end
		return
	end
	if not enabledCategories[category] then
		return
	end
	ForEachItemFrame(category, function(frame)
		SkinFrame(frame, category)
	end)
end

function Skin:ApplyOptions()
	self:Refresh(nil)
end

CallbackRegistry:Register("CooldownViewer.LayoutRefreshed", function(_, category)
	if not moduleEnabled or category == nil or not enabledCategories[category] then
		return
	end
	Skin:Refresh(category)
	-- Second pass next frame: lands after any skinner that deferred its own work.
	if not secondPassQueued[category] then
		secondPassQueued[category] = true
		C_Timer.After(0, function()
			secondPassQueued[category] = nil
			Skin:Refresh(category)
		end)
	end
end, Skin)
